import SwiftUI

@main
struct WatchFaceLabApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Device diagnostics must run when the process starts, even when
        // CoreDevice launches the app while the Watch UI never becomes active.
        // The loader's one-shot guard keeps the scene callback idempotent.
        _ = CustomFaceLoader.runRequestedSystemAction()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                if !CustomFaceLoader.runRequestedSystemAction() {
                    CustomFaceLoader.present()
                }
            }
        }
    }
}
