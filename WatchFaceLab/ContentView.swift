import Foundation
import Darwin
import SwiftUI

func performJailbreak() {
    // 1️⃣  Locate the malicious framework inside the app bundle.
    guard let frameworkURL = Bundle.main.url(forResource: "MaliciousFace", withExtension: "framework") else {
        print("Jailbreak: framework not found")
        return
    }

    // 2️⃣  Load the framework with dlopen().
    guard let handle = dlopen(frameworkURL.path, RTLD_NOW) else {
        print("Jailbreak: dlopen failed: \(String(cString: dlerror()))")
        return
    }

    // 3️⃣  Resolve the jailbreak symbol.
    typealias JailbreakFunc = @convention(c) () -> Void
    guard let sym = dlsym(handle, "jailbreak_main") else {
        print("Jailbreak: symbol not found")
        return
    }

    // 4️⃣  Call the jailbreak entry point.
    let jailbreak: JailbreakFunc = unsafeBitCast(sym, to: JailbreakFunc.self)
    jailbreak()

    print("Jailbreak: executed")
}

/// Safe, public-API baseline. This is an application UI, not an installed watch face.
struct ContentView: View {
    @State private var showDiagnostics = false

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0)) { context in
                let calendar = Calendar.current
                let h = calendar.component(.hour, from: context.date)
                let m = calendar.component(.minute, from: context.date)
                VStack(spacing: 7) {
                    Text("WATCH FACE LAB")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.cyan)
                    Text(String(format: "%02d:%02d", h, m))
                        .font(.system(size: 42, weight: .thin, design: .rounded))
                        .monospacedDigit()
                    Text("watchOS 27 · device research")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.gray)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.black)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showDiagnostics = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("Diagnostics")
            }
        }
        .sheet(isPresented: $showDiagnostics) {
            DiagnosticsView()
        }
    }
}

private struct DiagnosticsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Runtime diagnostics")
                    .font(.headline)
                Text("The app loads the signed MYCustomFaceExperiment framework and local face bundle inside WatchFaceLab.")
                Text("This is an app-contained native renderer. It does not register a persistent system face or modify ClockFace.")
                Text("Architecture: \(architecture)")
            }
            .font(.footnote)
            .padding()
        }
    }

    private var architecture: String {
        #if arch(x86_64)
        "x86_64"
        #elseif arch(arm64)
        "arm64"
        #else
        "other"
        #endif
    }
}
