# WatchFaceLab milestones

| Milestone | Status |
| --- | --- |
| SwiftUI watch simulator baseline | User-verified |
| Custom NTKFace and renderer | User-verified |
| Native time view/controller lifecycle | User-verified |
| Local bundle discovery and identified model restoration | User-verified |
| Restored model presentation/activation/dismissal | User-verified |
| Local gallery contract/native collection consumption | One clean cycle; earlier intermittent fault unresolved |
| Original ClockFace debugger attachment | Blocked by hardened target without get-task-allow |
| Debuggable research target | Installed/launched/attached x86_64; native scene startup hits remote-complication nil trap |
| Shared/session discovery bridge | Built; system-host execution pending |
| System gallery visibility | Not established |
| Persistent installation/selection/restoration | Not attempted |

Current action: owned-host shared-manager discovery integration. The copied host's
startup trap has been traced to ClockKit's bundle-identity gate (RESEARCH.md).
The next milestone is one install/consume/remove cycle in the owned app, without
full ClockFace server startup. It must retain host/runtime guards and verify
restoration of the original manager behavior. System visibility and persistence
remain separate gates; more renderer-only checks are unnecessary.
