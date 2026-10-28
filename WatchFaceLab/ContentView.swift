import SwiftUI

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
