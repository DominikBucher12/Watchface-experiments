//
//  CustomFaceLoader.swift
//  WatchFaceLab
//
//  Created by Dominik Bucher on 22.10.2026.
//

import Foundation
import Darwin

@MainActor
enum CustomFaceLoader {
    private static var didPresent = false
    private static var didRunSystemAction = false

    private static func writeSystemActionRecord(
        action: String,
        stage: String,
        complete: Bool,
        pass: Bool? = nil,
        error: String? = nil
    ) {
        guard let runID = ProcessInfo.processInfo.environment["WATCHFACELAB_SYSTEM_RUN_ID"],
              let documents = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
              ).first else { return }
        var record: [String: Any] = [
            "action": action,
            "stage": stage,
            "runID": runID,
            "complete": complete,
        ]
        if let pass { record["pass"] = pass }
        if let error { record["error"] = error }
        do {
            let data = try JSONSerialization.data(withJSONObject: record)
            try data.write(
                to: documents.appendingPathComponent("WatchFaceLab-SystemFaceResult.json"),
                options: .atomic
            )
        } catch {
            print("SYSTEM_FACE_RESULT_WRITE_ERROR \(error)")
        }
    }

    private static func loadExperimentFramework() -> UnsafeMutableRawPointer? {
        guard let frameworksURL = Bundle.main.privateFrameworksURL else {
            print("WatchFaceLab: Frameworks directory unavailable")
            return nil
        }
        let frameworkURL = frameworksURL
            .appendingPathComponent("MYCustomFaceExperiment.framework")
            .appendingPathComponent("MYCustomFaceExperiment")
        guard let handle = dlopen(frameworkURL.path, RTLD_NOW) else {
            print("WatchFaceLab: dlopen failed: \(String(cString: dlerror()))")
            return nil
        }
        return handle
    }

    /// Runs only when the device bootstrap explicitly supplies an action.
    /// Returns true when normal app-local preview presentation should be skipped.
    static func runRequestedSystemAction() -> Bool {
        guard let action = ProcessInfo.processInfo.environment["WATCHFACELAB_SYSTEM_ACTION"],
              !action.isEmpty else { return false }
        guard !didRunSystemAction else { return true }
        didRunSystemAction = true
        writeSystemActionRecord(action: action, stage: "swift-start", complete: false)
        guard let handle = loadExperimentFramework() else {
            writeSystemActionRecord(
                action: action,
                stage: "framework-load",
                complete: true,
                pass: false,
                error: "experiment framework could not be loaded"
            )
            return true
        }

        let noArgumentSymbols = [
            "boundary": "MYSystemFaceBoundaryPreflight",
            "preflight": "MYSystemFaceCollectionPreflight",
            "select": "MYSystemFaceSelectCandidate",
            "rollback": "MYSystemFaceRollbackCandidate",
        ]
        if let symbolName = noArgumentSymbols[action],
           let symbol = dlsym(handle, symbolName) {
            let function = unsafeBitCast(symbol, to: (@convention(c) () -> Int8).self)
            print("SYSTEM_FACE_ACTION action=\(action) result=\(function())")
            return true
        }
        if action == "install",
           let symbol = dlsym(handle, "MYSystemFaceInstallCandidate") {
            let function = unsafeBitCast(
                symbol,
                to: (@convention(c) (NSString) -> Int8).self
            )
            // The face bundle is copied at the app root, so pass that root itself.
            let appRoot = Bundle.main.bundleURL.path as NSString
            print("SYSTEM_FACE_ACTION action=install result=\(function(appRoot))")
            return true
        }
        print("SYSTEM_FACE_ACTION action=\(action) result=missing-export-or-unknown-action")
        writeSystemActionRecord(
            action: action,
            stage: "symbol-lookup",
            complete: true,
            pass: false,
            error: "missing export or unknown action"
        )
        return true
    }

    @MainActor
    static func testBundleDiscovery() {
        guard let handle = loadExperimentFramework() else { return }

        guard let symbol = dlsym(handle, "MYDiscoverLocalFaceBundle") else {
            print("Argon PoC: discovery symbol unavailable")
            return
        }

        typealias DiscoveryFunction =
            @convention(c) (NSString) -> Int8

        let discover = unsafeBitCast(
            symbol,
            to: DiscoveryFunction.self
        )

        // Our bundle is copied into the application's Resources directory.
        let directory = Bundle.main.bundleURL
            .appendingPathComponent("MYLocalFaceBundle.bundle", isDirectory: true)

        let result = discover(directory.deletingLastPathComponent().path as NSString)
        print("Nevim co dela result ale tu mas: \(result)")
    }
    
    static func present() {
        testBundleDiscovery()
        guard !didPresent else { return }

        guard let handle = loadExperimentFramework() else { return }

        if let v3Symbol = dlsym(handle, "MYInspectArgonDescriptorsV3") {
            let v3Probe = unsafeBitCast(v3Symbol, to: (@convention(c) () -> Void).self)
            v3Probe()
        } else {
            print("ARGON_V3 FAIL export missing")
        }

        guard let symbol = dlsym(handle, "MYPresentCustomFaceExperiment") else {
            print("CustomFace: entrypoint not found")
            return
        }

        // NSInteger -> Int, Objective-C BOOL -> signed char (Int8).
        typealias PresentFunction = @convention(c) (Int) -> Int8

        let present = unsafeBitCast(
            symbol,
            to: PresentFunction.self
        )

        // The bundled-face factory uses style 0x2c. It is valid for both the
        // arm64 and arm64_32 watchOS ABIs.
        let style = 44

        let result = present(style)

        if result != 0 {
            didPresent = true
            print("CustomFace: presented successfully")
        } else {
            print("CustomFace: presentation failed")
        }
    }
}
