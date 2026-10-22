import SwiftUI

@main
struct WatchFaceLabApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                CustomFaceLoader.present()
            }
        }
    }
}
