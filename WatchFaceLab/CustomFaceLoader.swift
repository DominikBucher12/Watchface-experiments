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

        print("Argon PoC: discovery \(result != 0 ? "PASS✅" : "FAIL❌")")
        
        if let symbol = dlsym(handle, "MYTestOwnedManagerWatch27") {
            let test = unsafeBitCast(
                symbol,
                to: (@convention(c) () -> Void).self
            )
            test()
        } else {
            print("OWNED27 FAIL: export not found")
        }
        
//        if let symbol = dlsym(handle, "MYInspectArgonRuntime") {
//            let inspect = unsafeBitCast(
//                symbol,
//                to: (@convention(c) () -> Void).self
//            )
//            inspect()
//        } else {
//            print("❌ ARGON_PROBE FAIL: export not found")
//        }
//        
//        if let symbol = dlsym(handle, "MYInspectArgonABI") {
//            let inspectABI = unsafeBitCast(
//                symbol,
//                to: (@convention(c) () -> Void).self
//            )
//            inspectABI()
//        } else {
//            print("ARGON_ABI FAIL: export not found")
//        }

        // 😭😭😭😭😭😭😭😭😭😭
        // NSFilePath=/var/mobile/Library/NanoTimeKit/FaceSupport/ExtractedBundles/24R365, NSUnderlyingError=0x12083ccc0 {Error Domain=NSPOSIXErrorDomain Code=1 "Operation not permitted"}} 😭
//        if let symbol = dlsym(handle, "MYInspectArgonDescriptors") {
//            let inspect = unsafeBitCast(
//                symbol,
//                to: (@convention(c) () -> Void).self
//            )
//            inspect()
//        } else {
//            print("ARGON_DESCRIPTOR FAIL: export not found")
//        }
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
