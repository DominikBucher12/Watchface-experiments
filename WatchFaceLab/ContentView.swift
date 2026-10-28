import ClockKit
import Foundation
import SwiftUI

@MainActor
private final class WatchFaceImporter: ObservableObject {
    @Published var status: String?
    private let library = CLKWatchFaceLibrary()
    private var automatedImportStarted = false

    func addBundledWatchFace() {
        importBundledWatchFace(completion: nil)
    }

    func runAutomatedImportIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["WATCHFACELAB_IMPORT_ON_LAUNCH"] == "1",
              !automatedImportStarted else {
            return
        }
        automatedImportStarted = true

        let runID = environment["WATCHFACELAB_IMPORT_RUN_ID"] ?? "missing-run-id"
        let caseID = environment["WATCHFACELAB_IMPORT_CASE_ID"] ?? "missing-case-id"
        writeResearchResult(
            runID: runID,
            caseID: caseID,
            phase: "started",
            complete: false,
            success: nil,
            error: nil
        )

        importBundledWatchFace { [weak self] error in
            self?.writeResearchResult(
                runID: runID,
                caseID: caseID,
                phase: "completed",
                complete: true,
                success: error == nil,
                error: error
            )
        }
    }

    private func importBundledWatchFace(completion: ((Error?) -> Void)?) {
        guard let url = Bundle.main.url(forResource: "PipBoy", withExtension: "watchface") else {
            status = "Configure once, then export PipBoy.watchface"
            let error = NSError(
                domain: "WatchFaceLab.Research",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Bundled PipBoy.watchface is missing"]
            )
            completion?(error)
            return
        }
        status = "Importing…"
        library.addWatchFace(at: url) { [weak self] error in
            Task { @MainActor [weak self] in
                if let error {
                    let value = error as NSError
                    self?.status = "Import failed (\(value.code))"
                } else {
                    self?.status = "Face added to the library"
                }
                completion?(error)
            }
        }
    }

    private func writeResearchResult(
        runID: String,
        caseID: String,
        phase: String,
        complete: Bool,
        success: Bool?,
        error: Error?
    ) {
        let value = error as NSError?
        var record: [String: Any] = [
            "schemaVersion": 1,
            "runID": runID,
            "caseID": caseID,
            "phase": phase,
            "complete": complete,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "processID": ProcessInfo.processInfo.processIdentifier,
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? "unknown",
            "operatingSystemVersion": ProcessInfo.processInfo.operatingSystemVersionString
        ]
        if let success {
            record["success"] = success
        }
        if let value {
            record["errorDomain"] = value.domain
            record["errorCode"] = value.code
            record["errorDescription"] = value.localizedDescription
        }

        guard JSONSerialization.isValidJSONObject(record),
              let data = try? JSONSerialization.data(
                withJSONObject: record,
                options: [.prettyPrinted, .sortedKeys]
              ),
              let documents = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
              ).first else {
            return
        }
        let destination = documents.appendingPathComponent(
            "WatchFaceLab-ParserResult.json",
            isDirectory: false
        )
        try? data.write(to: destination, options: .atomic)
    }
}

struct ContentView: View {
    private let pipGreen = Color(red: 0.52, green: 1.0, blue: 0.24)
    @StateObject private var importer = WatchFaceImporter()

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(pipGreen)

                Text("PIP-BOY MONITOR")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(pipGreen)

                Text("Complication installed")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 5) {
                    instruction("1", "Press and hold your watch face")
                    instruction("2", "Tap Edit, then Complications")
                    instruction("3", "Choose Pip-Boy Monitor")
                }
                .font(.system(size: 11, design: .rounded))

                Text("Works in inline, circular, corner, and rectangular slots.")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Install saved face") {
                    importer.addBundledWatchFace()
                }
                .buttonStyle(.bordered)
                .tint(pipGreen)

                if let status = importer.status {
                    Text(status)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(pipGreen)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 8)
        }
        .background(.black)
        .task {
            if await ResearchProbeRunner.runIfRequested() {
                return
            }
            importer.runAutomatedImportIfRequested()
        }
    }

    private func instruction(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(number)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(.black)
                .frame(width: 17, height: 17)
                .background(pipGreen, in: Circle())
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
