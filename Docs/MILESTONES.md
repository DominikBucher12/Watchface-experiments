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
| Owned-app shared discovery | User-verified full install/consume/remove cycle; PID 10520 |
| Shared/session discovery bridge | Built; system-host execution pending |
| System gallery visibility | Not established |
| Persistent installation/selection/restoration | Not attempted |
| nanotimekitd collection-server static trace | In progress; listener/client/curator/store path mapped, authorization and full storage path unresolved |

Owned-app milestone passed in PID 10520: baseline 58 bundles, one custom bundle,
native gallery consumption, and original class/enumeration/absent lookup restored.
See [OWNED-DISCOVERY.md](OWNED-DISCOVERY.md) for the recorded result.

Current milestone: finish read-only analysis of nanotimekitd's collection server
by checking manifest validation, complete store initialization/backing path, and
the descriptor reconstruction boundary. The installed launchd plist identifies
`com.apple.nanotimekit.collectionserver` under nanotimekitd; see
[SYSTEM-PERSISTENCE.md](SYSTEM-PERSISTENCE.md). Do not send add/remove/select
requests while mapping the service. The original host debugger restriction remains
an independent integration limit.
