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

    @MainActor
    static func testBundleDiscovery() {
        guard let frameworksURL = Bundle.main.privateFrameworksURL else {
            print("Argon PoC: Frameworks directory unavailable")
            return
        }

        let frameworkURL = frameworksURL
            .appendingPathComponent("MYCustomFaceExperiment.framework")
            .appendingPathComponent("MYCustomFaceExperiment")

        
        let libraries = [
            "/System/Library/PrivateFrameworks/NanoTimeKit.framework/NanoTimeKit",
            "/System/Library/PrivateFrameworks/ClockKitUI.framework/ClockKitUI"
        ]

        for path in libraries {
            let handle = dlopen(path, RTLD_NOW | RTLD_GLOBAL)

            if handle == nil {
                print("Private framework load failed: \(path): \(String(cString: dlerror()))")
            } else {
                print("Private framework loaded: \(path)")
            }
        }
        
        guard let handle = dlopen(frameworkURL.path, RTLD_NOW) else {
            print("Argon PoC: dlopen failed: \(String(cString: dlerror()))")
            return
        }

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

        guard let frameworksURL = Bundle.main.privateFrameworksURL else {
            print("CustomFace: Frameworks directory unavailable")
            return
        }

        let frameworkURL = frameworksURL
            .appendingPathComponent("MYCustomFaceExperiment.framework")
            .appendingPathComponent("MYCustomFaceExperiment")

        guard let handle = dlopen(frameworkURL.path, RTLD_NOW) else {
            print("CustomFace: dlopen failed: \(String(cString: dlerror()))")
            return
        }

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

        // Style observed in the previous successful experiment.
        let style = 4_345_047_376

        let result = present(style)

        if result != 0 {
            didPresent = true
            print("CustomFace: presented successfully")
        } else {
            print("CustomFace: presentation failed")
        }
    }
}
