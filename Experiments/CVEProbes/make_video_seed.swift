#!/usr/bin/env swift

import AVFoundation
import CoreVideo
import Darwin
import Foundation

enum SeedError: LocalizedError {
    case usage
    case cannotAddInput
    case cannotCreatePixelBuffer(OSStatus)
    case appendFailed
    case finishTimedOut
    case writerFailed(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            return "usage: make_video_seed.swift OUTPUT.mp4"
        case .cannotAddInput:
            return "AVAssetWriter rejected the H.264 input"
        case .cannotCreatePixelBuffer(let status):
            return "CVPixelBufferCreate failed with status \(status)"
        case .appendFailed:
            return "AVAssetWriterInputPixelBufferAdaptor append failed"
        case .finishTimedOut:
            return "AVAssetWriter did not finish within 30 seconds"
        case .writerFailed(let message):
            return "AVAssetWriter failed: \(message)"
        }
    }
}

func makePixelBuffer(width: Int, height: Int, frame: Int) throws -> CVPixelBuffer {
    var optionalBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ] as CFDictionary,
        &optionalBuffer
    )
    guard status == kCVReturnSuccess, let buffer = optionalBuffer else {
        throw SeedError.cannotCreatePixelBuffer(status)
    }

    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
        throw SeedError.cannotCreatePixelBuffer(kCVReturnError)
    }
    let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    for y in 0..<height {
        let row = baseAddress
            .advanced(by: y * bytesPerRow)
            .assumingMemoryBound(to: UInt8.self)
        for x in 0..<width {
            let offset = x * 4
            let active = ((x + frame * 3) % width) < width / 2
            row[offset] = UInt8((x * 4 + frame * 7) % 256)
            row[offset + 1] = active ? 220 : 32
            row[offset + 2] = UInt8((y * 4 + frame * 11) % 256)
            row[offset + 3] = 255
        }
    }
    return buffer
}

func generateVideo(
    at outputURL: URL,
    codec: AVVideoCodecType,
    fileType: AVFileType
) throws {
    let fileManager = FileManager.default
    try? fileManager.removeItem(at: outputURL)

    let writer = try AVAssetWriter(outputURL: outputURL, fileType: fileType)
    let settings: [String: Any] = [
        AVVideoCodecKey: codec,
        AVVideoWidthKey: 64,
        AVVideoHeightKey: 64,
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: 64_000,
            AVVideoMaxKeyFrameIntervalKey: 10,
        ],
    ]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = false
    guard writer.canAdd(input) else { throw SeedError.cannotAddInput }
    writer.add(input)

    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 64,
            kCVPixelBufferHeightKey as String: 64,
        ]
    )
    guard writer.startWriting() else {
        let reason = writer.error.map { String(describing: $0 as NSError) }
            ?? "startWriting returned false"
        throw SeedError.writerFailed(reason)
    }
    writer.startSession(atSourceTime: .zero)

    for frame in 0..<10 {
        let deadline = Date().addingTimeInterval(5)
        while !input.isReadyForMoreMediaData && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard input.isReadyForMoreMediaData else {
            throw SeedError.writerFailed("input was not ready for frame \(frame)")
        }
        let buffer = try makePixelBuffer(width: 64, height: 64, frame: frame)
        let time = CMTime(value: CMTimeValue(frame), timescale: 10)
        guard adaptor.append(buffer, withPresentationTime: time) else {
            throw SeedError.appendFailed
        }
    }

    input.markAsFinished()
    let semaphore = DispatchSemaphore(value: 0)
    writer.finishWriting { semaphore.signal() }
    guard semaphore.wait(timeout: .now() + 30) == .success else {
        writer.cancelWriting()
        throw SeedError.finishTimedOut
    }
    guard writer.status == .completed else {
        let reason = writer.error.map { String(describing: $0 as NSError) }
            ?? "status \(writer.status.rawValue)"
        throw SeedError.writerFailed(reason)
    }
}

do {
    guard CommandLine.arguments.count == 2 else { throw SeedError.usage }
    let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let attempts: [(AVVideoCodecType, AVFileType, String)] = [
        (.h264, .mp4, "h264"),
        (.jpeg, .mov, "mjpeg"),
    ]
    var lastError: Error = SeedError.writerFailed("no codec attempt was made")
    var selectedCodec: String?
    for (codec, fileType, label) in attempts {
        do {
            try generateVideo(at: outputURL, codec: codec, fileType: fileType)
            selectedCodec = label
            break
        } catch {
            lastError = error
            try? FileManager.default.removeItem(at: outputURL)
        }
    }
    guard let selectedCodec else { throw lastError }
    print("VIDEO_SEED=PASS CODEC=\(selectedCodec) PATH=\(outputURL.path)")
} catch {
    fputs("ERROR: \(error.localizedDescription)\n", stderr)
    exit(2)
}
