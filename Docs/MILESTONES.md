# WatchFaceLab milestones

| Milestone | Status |
| --- | --- |
| SwiftUI watch simulator baseline | User-verified |
| Custom NTKFace and renderer | User-verified |
| Animated Pip-Boy renderer variant | Built in isolated LLDB experiment; simulator visual check pending |
| Native time view/controller lifecycle | User-verified |
| Local bundle discovery and identified model restoration | User-verified |
| Restored model presentation/activation/dismissal | User-verified |
| Local gallery contract/native collection consumption | One clean cycle; earlier intermittent fault unresolved |
| Original ClockFace debugger attachment | Blocked by hardened target without get-task-allow |
| Debuggable research target | Installed/launched/attached x86_64; native scene startup hits remote-complication nil trap |
| Owned-app shared discovery | User-verified full install/consume/remove cycle; PID 10520 |
| Shared/session discovery bridge | Built; ClockFace attach denied before load; unexecuted |
| Supported app-to-system custom bundle discovery | No public path identified; documented face-sharing imports existing face configurations |
| NanoTimeKit extracted-bundle cache deployment route | Assessed only; private Argon cache, and current bundle requires a separate ad-hoc dylib; not used as a system-host loading path |
| Native gallery UI suitability for isolated collection | Read-only audit complete; factory owns collection delegation and exposes add-face callbacks; not a passive browser |
| System gallery visibility | Not established |
| Persistent installation/selection/restoration | Not attempted |
| nanotimekitd collection-server static trace | Storage/reconstruction mapped; listener accepts at method level; Mach-service, registration, and operation authorization unresolved |

Owned-app milestone passed in PID 10520: baseline 58 bundles, one custom bundle,
native gallery consumption, and original class/enumeration/absent lookup restored.
See [OWNED-DISCOVERY.md](OWNED-DISCOVERY.md) for the recorded result.

Supported-route assessment complete: Apple documents adding a `.watchface`
configuration from an app bundle, not registering an app-defined `NTKFace`
subclass or renderer. The documented flow configures an existing system face and
its complications; see [Apple's watch-face HIG](https://developer.apple.com/design/human-interface-guidelines/watch-faces),
[CLKWatchFaceLibrary](https://developer.apple.com/documentation/clockkit/clkwatchfacelibrary),
and [addWatchFace(at:completionHandler:)](https://developer.apple.com/documentation/clockkit/clkwatchfacelibrary/addwatchface%28at%3Acompletionhandler%3A%29).
This project is a single watchOS app target, and NanoTimeKit's traced daemon
loader has no app-local search root. No supported path to expose this custom
renderer to another process was identified.

The next private-integration gate is unavailable in the current simulator host:
ClockFace's hardened attach was denied before the bridge loaded. Do not try to
work around that policy. Continue toward system-gallery visibility only in an
Apple-authorized debug environment or if Apple provides a public custom-face
extension point. Until then, keep this at the verified in-app/owned-process PoC;
do not attempt persistent installation or selection.

The next local UI route was audited against the installed NanoTimeKit binary. Its
`NTKFaceGalleryFactory` installs itself as the gallery collection's delegate,
observes updates, and connects detail-cell Add actions to the controller's
`faceGalleryFactory:wantsFaceAdded:withContainerFrame:` callback. The stock
gallery controller also constructs its root content through an addable collection.
This is not a read-only browsing contract, and the app-local factory route is not
needed to validate the already-proven renderer. No native gallery UI was created
and no add callback was invoked. Further safe work is limited to static analysis
or app-owned custom UI; the next system-visible milestone requires an Apple-
authorized ClockFace debugging route or a public custom-face extension point.

The launchd plist runs nanotimekitd as
`mobile`, enables `com.apple.nanotimekit.collectionserver`, and has no explicit
client allowlist; the collection-server method-level sender check and any global
authorization remain unresolved. The loader uses `IPHONE_SIMULATOR_ROOT` plus
the standard system face-bundle directory and feature-dependent AppleInternal or
Argon roots; it does not add app-local or `/tmp` paths. This means the `/tmp`
bundle used in the owned-app tests is not shown to be loadable by nanotimekitd.
See [SYSTEM-PERSISTENCE.md](SYSTEM-PERSISTENCE.md). Keep remaining investigation
read-only: do not modify the runtime or send add/remove/select requests. The
original host debugger restriction remains an independent integration limit.
