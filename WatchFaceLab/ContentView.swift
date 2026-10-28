import ClockKit
import SwiftUI

@MainActor
private final class WatchFaceImporter: ObservableObject {
    @Published var status: String?
    private let library = CLKWatchFaceLibrary()

    func addBundledWatchFace() {
        guard let url = Bundle.main.url(forResource: "PipBoy", withExtension: "watchface") else {
            status = "Configure once, then export PipBoy.watchface"
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
            }
        }
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
