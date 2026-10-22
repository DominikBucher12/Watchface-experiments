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

    static func present() {
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
