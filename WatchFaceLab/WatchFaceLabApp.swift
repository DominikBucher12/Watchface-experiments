import SwiftUI

@main
struct WatchFaceLabApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        hello_world_print()

        // Device runs are explicit. The normal app launch never enters a
        // kernel-facing probe merely because the app was rebuilt or reopened.
        if ProcessInfo.processInfo.environment["WATCHFACELAB_TTY_PROBE"] == "1" {
            let result = tty_ptmx_probe_run(1, 0)
            print("[tty-ptmx] explicit setup diagnostic result=\(result)")
        }

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
