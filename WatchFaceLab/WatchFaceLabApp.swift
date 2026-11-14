import SwiftUI
import Dispatch

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
        if let mode = ProcessInfo.processInfo.environment["WATCHFACELAB_SCM_RIGHTS_PROBE"] {
            let probeMode: Int32 = mode == "replace" ? 2 : (mode == "race" ? 1 : 0)
            let result = scm_rights_probe_run(probeMode == 0 ? 1 : 64, probeMode)
            print("[scm-rights] explicit probe result=\(result)")
        }
        if ProcessInfo.processInfo.environment["WATCHFACELAB_BPF_OPEN_PROBE"] == "1" {
            let result = bpf_open_probe_run()
            print("[bpf-open] explicit accessibility result=\(result)")
        }
        if ProcessInfo.processInfo.environment["WATCHFACELAB_IOMFB_OPEN_PROBE"] == "1" {
            let result = iomfb_open_probe_run()
            print("[iomfb-open] explicit accessibility result=\(result)")
        }
        if ProcessInfo.processInfo.environment["WATCHFACELAB_IOMFB_LIFECYCLE_PROBE"] == "1" {
            let result = iomfb_lifecycle_probe_run()
            print("[iomfb-lifecycle] explicit sequential result=\(result)")
        }
        if ProcessInfo.processInfo.environment["WATCHFACELAB_IOMFB_OWNED_CLIENT_PROBE"] == "1" {
            let result = iomfb_owned_client_probe_run()
            print("[iomfb-owned] explicit owned-client result=\(result)")
        }
        if ProcessInfo.processInfo.environment["WATCHFACELAB_IOMFB_END_LIFECYCLE_PROBE"] == "1" {
            let result = iomfb_end_lifecycle_probe_run()
            print("[iomfb-end] explicit sequential result=\(result)")
        }
        if let rawIterations = ProcessInfo.processInfo.environment["WATCHFACELAB_IOMFB_TEARDOWN_RACE_PROBE"],
           let iterations = UInt32(rawIterations) {
            let result = iomfb_teardown_race_probe_run(iterations)
            print("[iomfb-race] explicit bounded result=\(result)")
        }
        if let rawIterations = ProcessInfo.processInfo.environment["WATCHFACELAB_IOMFB_END_TEARDOWN_RACE_PROBE"],
           let iterations = UInt32(rawIterations) {
            let result = iomfb_end_teardown_race_matrix_probe_run(iterations)
            print("[iomfb-end-race] explicit bounded result=\(result)")
        }
        if ProcessInfo.processInfo.environment["WATCHFACELAB_TCP_INFO_PROBE"] == "1" {
            let result = tcp_info_access_probe_run()
            print("[tcp-info] explicit access result=\(result)")
        }
        if ProcessInfo.processInfo.environment["WATCHFACELAB_WORKQUEUE_INFO_PROBE"] == "1" {
            DispatchQueue.global(qos: .utility).async {
                let result = workqueue_info_access_probe_run()
                print("[workqueue-info] explicit access result=\(result)")
            }
        }
        if ProcessInfo.processInfo.environment["WATCHFACELAB_WORKQUEUE_CROSS_PROCESS_PROBE"] == "1" {
            DispatchQueue.global(qos: .utility).async {
                let result = workqueue_info_cross_process_probe_run()
                print("[workqueue-cross] explicit access result=\(result)")
            }
        }
        if ProcessInfo.processInfo.environment["WATCHFACELAB_COW_PROBE"] == "1" {
            let result = cow_memory_probe_run()
            print("[cow-memory] explicit integrity result=\(result)")
        }
        if ProcessInfo.processInfo.environment["WATCHFACELAB_112665_PROBE"] == "1" {
            let result = cve_2026_112665_probe_run()
            print("[CVE-2026-112665 gate] explicit result=\(result)")
        }
        if ProcessInfo.processInfo.environment["WATCHFACELAB_113910_PROBE"] == "1" {
            let directory = FileManager.default.temporaryDirectory.path
            let result = directory.withCString { path in
                cve_2026_113910_probe_run(path)
            }
            print("[CVE-2026-113910 gate] explicit result=\(result)")
        }
        if ProcessInfo.processInfo.environment["WATCHFACELAB_112466_PROBE"] == "1" {
            let result = cve_2026_112466_probe_run()
            print("[CVE-2026-112466 gate] explicit result=\(result)")
        }
        if ProcessInfo.processInfo.environment["WATCHFACELAB_CONTAINER_TOKEN_PROBE"] == "1" {
            let result = watchfacelab_container_token_probe_run()
            print("[container-token] explicit result=\(result)")
        }
        if ProcessInfo.processInfo.environment["WATCHFACELAB_FACESUPPORT_READONLY_PROBE"] == "1" {
            let result = watchfacelab_facesupport_readonly_probe_run()
            print("[facesupport-readonly] explicit result=\(result)")
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
