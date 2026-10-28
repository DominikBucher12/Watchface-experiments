import AVFoundation
import CoreText
import CryptoKit
import Foundation
import ImageIO

private struct ResearchProbeOutcome {
    let accepted: Bool
    let details: [String: Any]
}

private enum VideoMetadataResult {
    case loaded(durationSeconds: Double, trackCount: Int)
    case rejected(String)
    case timedOut
}

private enum ResearchProbeFailure: LocalizedError {
    case invalidConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            return message
        }
    }
}

@MainActor
enum ResearchProbeRunner {
    private static let resultName = "WatchFaceLab-CVEProbeResult.json"
    private static let maximumInputBytes = 8 * 1024 * 1024
    private static var didStart = false

    /// Runs one explicitly selected, hash-locked input supplied by the host
    /// script. A new process is used for every case so parser state cannot leak
    /// between inputs.
    static func runIfRequested() async -> Bool {
        let environment = ProcessInfo.processInfo.environment
        guard let probe = environment["WATCHFACELAB_CVE_PROBE"],
              !probe.isEmpty else {
            return false
        }
        guard !didStart else { return true }
        didStart = true

        let runID = environment["WATCHFACELAB_CVE_RUN_ID"] ?? "missing-run-id"
        let caseID = environment["WATCHFACELAB_CVE_CASE_ID"] ?? "missing-case-id"
        let expectedHash = environment["WATCHFACELAB_CVE_SHA256"] ?? ""

        writeResult(
            runID: runID,
            caseID: caseID,
            probe: probe,
            phase: "started",
            complete: false
        )

        do {
            guard let inputName = environment["WATCHFACELAB_CVE_INPUT"],
                  !inputName.isEmpty,
                  inputName == (inputName as NSString).lastPathComponent else {
                throw ResearchProbeFailure.invalidConfiguration(
                    "input must be a single filename inside Documents"
                )
            }
            guard let documents = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first else {
                throw ResearchProbeFailure.invalidConfiguration(
                    "Documents directory is unavailable"
                )
            }

            let inputURL = documents.appendingPathComponent(inputName)
            let data = try Data(contentsOf: inputURL, options: [.mappedIfSafe])
            guard !data.isEmpty, data.count <= maximumInputBytes else {
                throw ResearchProbeFailure.invalidConfiguration(
                    "input must contain 1...\(maximumInputBytes) bytes"
                )
            }

            let actualHash = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
            guard !expectedHash.isEmpty, actualHash == expectedHash else {
                throw ResearchProbeFailure.invalidConfiguration(
                    "input SHA-256 does not match the host manifest"
                )
            }

            writeResult(
                runID: runID,
                caseID: caseID,
                probe: probe,
                phase: "input-verified",
                complete: false,
                inputBytes: data.count,
                inputSHA256: actualHash
            )

            let outcome: ResearchProbeOutcome
            switch probe {
            case "imageio":
                outcome = probeImage(data)
            case "font":
                outcome = probeFont(data)
            case "audio":
                outcome = probeAudio(inputURL)
            case "video":
                outcome = await probeVideo(inputURL) { phase, details in
                    writeResult(
                        runID: runID,
                        caseID: caseID,
                        probe: probe,
                        phase: phase,
                        complete: false,
                        inputBytes: data.count,
                        inputSHA256: actualHash,
                        details: details
                    )
                }
            default:
                throw ResearchProbeFailure.invalidConfiguration(
                    "unknown probe: \(probe)"
                )
            }

            writeResult(
                runID: runID,
                caseID: caseID,
                probe: probe,
                phase: "completed",
                complete: true,
                harnessSuccess: true,
                accepted: outcome.accepted,
                inputBytes: data.count,
                inputSHA256: actualHash,
                details: outcome.details
            )
        } catch {
            let value = error as NSError
            writeResult(
                runID: runID,
                caseID: caseID,
                probe: probe,
                phase: "completed",
                complete: true,
                harnessSuccess: false,
                accepted: false,
                error: value
            )
        }
        return true
    }

    private static func probeImage(_ data: Data) -> ResearchProbeOutcome {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary) else {
            return ResearchProbeOutcome(
                accepted: false,
                details: ["reason": "CGImageSource rejected the input"]
            )
        }

        let count = CGImageSourceGetCount(source)
        var decodedCount = 0
        let decodeLimit = min(count, 4)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 256,
        ]
        if decodeLimit > 0 {
            for index in 0..<decodeLimit {
                if CGImageSourceCreateThumbnailAtIndex(
                    source,
                    index,
                    options as CFDictionary
                ) != nil {
                    decodedCount += 1
                }
            }
        }

        return ResearchProbeOutcome(
            accepted: count > 0 && decodedCount > 0,
            details: [
                "imageCount": count,
                "decodedCount": decodedCount,
                "sourceType": (CGImageSourceGetType(source) as String?) ?? "unknown",
            ]
        )
    }

    private static func probeFont(_ data: Data) -> ResearchProbeOutcome {
        guard let descriptor = CTFontManagerCreateFontDescriptorFromData(
            data as CFData
        ) else {
            return ResearchProbeOutcome(
                accepted: false,
                details: ["reason": "CoreText rejected the input"]
            )
        }

        let font = CTFontCreateWithFontDescriptor(descriptor, 16, nil)
        var characters: [UniChar] = Array("WatchFaceLab".utf16)
        var glyphs = Array(repeating: CGGlyph(), count: characters.count)
        let mapped = CTFontGetGlyphsForCharacters(
            font,
            &characters,
            &glyphs,
            characters.count
        )
        var outlineCount = 0
        for glyph in glyphs.prefix(16) where glyph != 0 {
            if CTFontCreatePathForGlyph(font, glyph, nil) != nil {
                outlineCount += 1
            }
        }

        return ResearchProbeOutcome(
            accepted: mapped && outlineCount > 0,
            details: [
                "mappedCharacters": mapped,
                "outlineCount": outlineCount,
                "postScriptName": CTFontCopyPostScriptName(font) as String,
            ]
        )
    }

    private static func probeAudio(_ inputURL: URL) -> ResearchProbeOutcome {
        do {
            let file = try AVAudioFile(forReading: inputURL)
            let frameCount = AVAudioFrameCount(max(1, min(file.length, 4_096)))
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: frameCount
            ) else {
                return ResearchProbeOutcome(
                    accepted: false,
                    details: [
                        "reason": "AVAudioPCMBuffer rejected the stream format",
                    ]
                )
            }
            try file.read(into: buffer, frameCount: frameCount)
            return ResearchProbeOutcome(
                accepted: buffer.frameLength > 0,
                details: [
                    "channelCount": file.processingFormat.channelCount,
                    "decodedFrames": buffer.frameLength,
                    "fileFrames": file.length,
                    "sampleRate": file.processingFormat.sampleRate,
                ]
            )
        } catch {
            return ResearchProbeOutcome(
                accepted: false,
                details: [
                    "reason": "AVAudioFile rejected the input",
                    "parserError": (error as NSError).localizedDescription,
                ]
            )
        }
    }

    private static func probeVideo(
        _ inputURL: URL,
        progress: (String, [String: Any]?) -> Void
    ) async -> ResearchProbeOutcome {
        let asset = AVURLAsset(url: inputURL)
        progress("video-metadata-started", nil)
        let metadata = await boundedVideoMetadata(asset)
        let durationSeconds: Double
        let trackCount: Int
        switch metadata {
        case .loaded(let duration, let count):
            durationSeconds = duration
            trackCount = count
        case .rejected(let message):
            return ResearchProbeOutcome(
                accepted: false,
                details: [
                    "reason": "AVFoundation rejected the input",
                    "parserError": message,
                ]
            )
        case .timedOut:
            return ResearchProbeOutcome(
                accepted: false,
                details: ["reason": "AVFoundation metadata load timed out after 8 seconds"]
            )
        }
        guard trackCount > 0 else {
            return ResearchProbeOutcome(
                accepted: false,
                details: ["reason": "AVFoundation found no video track"]
            )
        }

        progress(
            "video-metadata-loaded",
            ["durationSeconds": durationSeconds, "trackCount": trackCount]
        )
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        progress("video-preroll-started", nil)
        let preroll = await boundedPreroll(player)
        player.pause()
        player.replaceCurrentItem(with: nil)

        var details: [String: Any] = [
            "durationSeconds": durationSeconds,
            "trackCount": trackCount,
        ]
        if let preroll {
            details["prerollCompleted"] = preroll
        } else {
            details["prerollTimedOut"] = true
        }
        progress("video-preroll-returned", details)
        return ResearchProbeOutcome(accepted: true, details: details)
    }

    /// The modern async AVAsset properties occasionally fail to call back on
    /// a physical Watch. Race them against an independent queue timeout so the
    /// harness still emits a final, classifiable result.
    private static func boundedVideoMetadata(
        _ asset: AVURLAsset
    ) async -> VideoMetadataResult {
        final class Gate: @unchecked Sendable {
            private let lock = NSLock()
            private var finished = false
            private var continuation: CheckedContinuation<VideoMetadataResult, Never>?

            func install(
                _ value: CheckedContinuation<VideoMetadataResult, Never>
            ) {
                lock.lock()
                continuation = value
                lock.unlock()
            }

            func finish(_ value: VideoMetadataResult) {
                lock.lock()
                guard !finished else {
                    lock.unlock()
                    return
                }
                finished = true
                let saved = continuation
                continuation = nil
                lock.unlock()
                saved?.resume(returning: value)
            }
        }

        let gate = Gate()
        return await withCheckedContinuation { continuation in
            gate.install(continuation)
            Task {
                do {
                    let duration = try await asset.load(.duration)
                    let tracks = try await asset.loadTracks(withMediaType: .video)
                    let seconds = duration.seconds.isFinite ? duration.seconds : -1
                    gate.finish(
                        .loaded(durationSeconds: seconds, trackCount: tracks.count)
                    )
                } catch {
                    gate.finish(.rejected((error as NSError).localizedDescription))
                }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 8) {
                gate.finish(.timedOut)
            }
        }
    }

    /// AVPlayer has no async preroll API. This gate bounds the callback to five
    /// seconds and guarantees that the continuation is resumed only once.
    private static func boundedPreroll(_ player: AVPlayer) async -> Bool? {
        final class Gate: @unchecked Sendable {
            private let lock = NSLock()
            private var finished = false
            private var continuation: CheckedContinuation<Bool?, Never>?

            func install(_ value: CheckedContinuation<Bool?, Never>) {
                lock.lock()
                continuation = value
                lock.unlock()
            }

            func finish(_ value: Bool?) {
                lock.lock()
                guard !finished else {
                    lock.unlock()
                    return
                }
                finished = true
                let saved = continuation
                continuation = nil
                lock.unlock()
                saved?.resume(returning: value)
            }
        }

        let gate = Gate()
        return await withCheckedContinuation { continuation in
            gate.install(continuation)
            player.preroll(atRate: 1) { success in
                gate.finish(success)
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) {
                gate.finish(nil)
            }
        }
    }

    private static func writeResult(
        runID: String,
        caseID: String,
        probe: String,
        phase: String,
        complete: Bool,
        harnessSuccess: Bool? = nil,
        accepted: Bool? = nil,
        inputBytes: Int? = nil,
        inputSHA256: String? = nil,
        details: [String: Any]? = nil,
        error: NSError? = nil
    ) {
        guard let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else { return }
        var record: [String: Any] = [
            "schemaVersion": 1,
            "runID": runID,
            "caseID": caseID,
            "probe": probe,
            "phase": phase,
            "complete": complete,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "processID": ProcessInfo.processInfo.processIdentifier,
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? "unknown",
            "operatingSystemVersion": ProcessInfo.processInfo.operatingSystemVersionString,
        ]
        if let harnessSuccess { record["harnessSuccess"] = harnessSuccess }
        if let accepted { record["accepted"] = accepted }
        if let inputBytes { record["inputBytes"] = inputBytes }
        if let inputSHA256 { record["inputSHA256"] = inputSHA256 }
        if let details { record["details"] = details }
        if let error {
            record["errorDomain"] = error.domain
            record["errorCode"] = error.code
            record["errorDescription"] = error.localizedDescription
        }

        do {
            let data = try JSONSerialization.data(
                withJSONObject: record,
                options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(
                to: documents.appendingPathComponent(resultName),
                options: .atomic
            )
        } catch {
            print("CVE_PROBE_RESULT_WRITE_ERROR \(error)")
        }
    }
}
