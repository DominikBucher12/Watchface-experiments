# Experiment log — watchOS 27.0.1 (24R365)

The log records **observed results** in chronological order. Exact times are approximate unless shown in supplied terminal output. Dates: 2026-10-21–22. Private memory addresses, temporary install UUIDs and unrelated identifiers are not needed for reproduction.

| Seq. | Experiment | Evidence / result | Interpretation |
| --- | --- | --- | --- |
| 01 | Build custom `MYCustomFace` and render in WatchFaceLab | `CustomFace: presented successfully`; the historical log printed an invalid oversized style value, while the verified bundled-face factory uses style `44` | App-local native renderer functions; the Swift entry now uses ABI-safe style `44` on arm64 and arm64_32. |
| 02 | Device toolchain inspection | Physical Watch Series 9; watchOS 27.0.1 (24R365); `ClockFace`, `nanotimekitd`, etc. in process listing | Separate process hosting system clock. |
| 03 | External local face bundle build + Xcode embedding | Xcode build and app installation passed | Bundle packaged, not yet proof it loads. |
| 04 | Verify framework exports | `nm -gU`: `_MYDiscoverLocalFaceBundle` and `_MYPresentCustomFaceExperiment` present | Swift `dlsym` can resolve the two entry points. |
| 05 | First `MYDiscoverLocalFaceBundle` run | `NSInvalidArgumentException`: `+[NTKFaceBundleLoader faceBundleLoaderWithDirectories:]` unrecognized | Wrong one-argument selector for device ABI. |
| 06 | Patch loader factory | Correct `faceBundleLoaderWithDirectories:appBundleIdentifierPrefixes:` source, but same runtime crash after Xcode rebuild | Stale manually built framework still embedded. |
| 07 | Explicit framework rebuild | Corrected loader selector linked | Separate framework generation must precede Xcode embed/copy. |
| 08 | Xcode strip failure | `strip ... framework/MYCustomFaceExperiment.dSYM/...` exit 1 | dSYM nested *inside* .framework. Moved sibling dSYM out. Permanent script fix deferred. |
| 09 | Actual local face discovery | `Local bundle PoC PASS ... bundle=MYLocalFaceBundle face=MYCustomFace renderer=MYCustomFaceView timeView=NTKDigitalTimeLabel`; `Argon PoC: discovery PASS` | Valid app-local executable `NTKFaceBundle` and default face. |
| 10 | Runtime Argon class probe | 8 of 9 named runtime classes present; `NTKFaceSupportServerInterface present=0`; app-local bundle readable | Confirms Objective-C runtime surfaces, not XPC authorization. |
| 11 | ABI probe | `ARGON_ABI BEGIN ... END`; method encodings captured, no private selectors invoked | Objective-C methods identified; block ABI was separate. |
| 12 | First descriptor probe | `EPERM` at extracted Argon directory; no successful count | Not a descriptor enumeration success. Initial block ABI later identified as incorrect. |
| 13 | Corrected descriptor probe V2 | Same `ENOENT` `/AppleInternal` and `EPERM` `/var/mobile/.../24R365`; no `completed count` in supplied log | Access boundary, no evidence of descriptor content. |
| 14 | Device sysdiagnose | `system_logs.logarchive`: 0 selected eventMessage matches; text scan found OSEligibility `ARGON NOT_ELIGIBLE DEVICE_CLASS` | Meaning of this separate `ARGON` eligibility key uncertain. |
| 15 | Owned manager test | Runtime UUID + ABI matched; `OWNED27 RESULT lookup=1 enumerated=1 PASS=1` | App-process manager can expose custom face through lookup and enumeration via ephemeral subclass. |
| 16 | Restore manager | `OWNED27 RESTORED class=1 absent=1`, `OWNED27 END`, renderer still presented | Interception was removed, no persistence and no ClockFace injection. |
| 17 | Initial static ClockFace audit | Only candidate named `ClockFace` was `AccessibilityBundles/ClockFace.axbundle/ClockFace` | **Wrong executable**; no conclusion about main system process. |
| 18 | Read sysdiagnose process list | `/Applications/ClockFace.app/ClockFace`, PID 198, bundle `com.apple.clockface`; platform signing flags | Actual system process path identified and library-validation enforcement observed. |
| 19 | Real ClockFace binary audit | Command prepared, user result **pending** | No findings to record yet. |
| 20 | Physical `LibraryFaces` collection probe implementation | ABI-gated preflight/install/select/rollback exports compile and package as arm64; device execution pending | Build success is not collection-server acceptance. Await `SYSTEM_FACE_RESULT` from the watchOS 27 device. |
| 21 | First physical preflight launch | Xcode 27/watchOS 27.0.1 build, signing, install and launch passed; `devicectl --console` waited until timeout without relaying the app's result | No collection conclusion. Result transport changed to a run-ID-gated file copied from the app data container. |
| 22 | Second physical preflight launch | Build/install/launch passed; no matching result was copied from the app container within 25 seconds | No collection conclusion. Added Swift/framework progress milestones and container listing to distinguish execution stalls from file-transfer failure. |
| 23 | Third physical preflight attempt | Build passed; CoreDevice error 4000 disconnected during app installation before launch | Probe did not execute. Added bounded retries only around the idempotent install step. |
| 24 | Fourth physical preflight attempt | Build/install/launch passed; app `Documents` listed `WatchFaceLab-SystemFaceResult.json` (318 bytes, current timestamp), but per-file copy did not produce the expected local path | Probe produced a record; collection conclusion awaits its contents. Changed CoreDevice receive destination to an existing directory and added a whole-`Documents` fallback. |
| 25 | Device workflow simplification | Added stable `watchos27-device-face.sh` entry point with automatic physical-Watch selection and `result`/`preflight`/`install`/`select`/`rollback` commands | Future iterations update one script; `result` retrieves the existing JSON without rebuilding, launching, or mutating. |
| 26 | First convenience `result` fetch | CoreDevice error 7000 / RemoteServices 11001: destination path was an existing directory and could not be opened as a file | Corrected receive target to a concrete file with an existing parent; added relative/root-relative source fallback and property-list JSON validation. |
| 27 | First recovered physical preflight result | All eight collection selector encodings match the expected ABI; `sharedLibraryCollection` remained `hasLoaded=false` for 12 seconds | Do not mutate. Expanded preflight to report connection/registration/reference/device state and perform one read-only `_registerIfNeeded` retry only when the collection requests it. |
| 28 | Expanded physical preflight result | `NSXPCConnection` exists; registration flag stays false; sequence ID and reference collection stay nil; current `CLKDevice` exists; no state changed from initial through timeout | Registration was issued but produced no callback or interruption. Added a duplicate read-only registration with a dedicated XPC error handler to test the service-authorization boundary. |
| 29 | First XPC-error preflight attempt | Launch reported success, but the result file retained the preceding run ID and timestamp | `--terminate-existing` did not guarantee a fresh watchOS process. The workflow now enumerates and force-terminates only WatchFaceLab by PID before passing a new action environment. |
| 30 | Fresh XPC-registration preflight | Fresh run ID; all eight selector ABIs matched; `NSXPCConnection` and its proxy were present; registration was enqueued; no error callback arrived; `LibraryFaces` stayed unloaded with nil sequence/reference state until timeout | Stop repeating app preflights and do not mutate. The unresolved boundary is now system service identity, authorization, sandbox policy, or server-side filtering rather than selector ABI or message construction. |
| 31 | Static system-boundary audit implementation | Added a host-only `audit` command for exact `ClockFace.app/ClockFace`, `nanotimekitd`, NanoTimeKit, FaceSupport components, signatures, entitlements, dependencies, and service-related strings | Results from the matching watchOS 27 DeviceSupport tree are pending; missing components are reported explicitly and are not confused with negative findings. |
| 32 | Physical DeviceSupport system-boundary audit | `nanotimekitd` is present at `NanoTimeKit.framework/nanotimekitd`; strings include `NTKCollectionServer` and `runCollectionServer`; entitlements include collectionserver Mach lookup, FaceSupport storage, platform application, and library replicator; ClockFace is absent; ClockFaceSupport is present; launchd plist is absent | Confirms the physical daemon/service side and exposes a likely client sandbox boundary. The library-replicator entitlement is not yet proven to authorize persistent collection access. Missing ClockFace/plist data is a DeviceSupport limitation, not a runtime-absence claim. |
| 33 | App sandbox boundary probe implementation | Added `boundary`, which checks WatchFaceLab's own sandbox decision and signed entitlement values without constructing an XPC connection or sending a request | Physical result pending. This distinguishes a Mach lookup denial from later collection-server filtering without another collection timeout. |
| 34 | First boundary launch | Build, signing, installation, and CoreDevice launch returned success, but the app container retained the older `install` result and no fresh `swift-start` record appeared | No sandbox conclusion. SwiftUI never reported an active scene. The action now runs from the app initializer, and the bootstrap records whether WatchFaceLab has a PID one second after launch. |
| 35 | Fresh app sandbox boundary result | WatchFaceLab ran as PID 6716; `sandbox_check` for `mach-lookup` of `com.apple.nanotimekit.collectionserver` completed with `rawResult=1`, `denied=true`, `allowed=false`; the app's signed Mach-lookup, FaceSupport storage, library-replicator, and platform-application entitlements were all absent; `xpcRequestSent=false` | The normal third-party watchOS app path is blocked before collection-server authorization. Do not repeat collection preflights or mutations. Persisting the custom executable renderer now requires a platform-authorized system distribution/host route or a modified research OS. |
| 36 | Container-token escape prerequisite | Added a dedicated, valid App Group with explicit approval; Xcode built, signed, installed, and launched the app, and the group container URL resolved | The signing prerequisite is satisfied; this is not itself a sandbox escape. |
| 37 | Container-token issuance matrix | The class-7/part-3 query returned a result with both known flags (`0x8000000000` and `0x800000000`) but returned no sandbox-extension token; own-group `Library/Caches` was restored | The iOS 27.0.1 token path does not transfer to this measured watchOS build. Park this exact route after two issuance failures. |
| 38 | Static FaceSupport listener audit | In the matching 24R365 NanoTimeKit image, `-[NTKDArgonService listener:shouldAcceptNewConnection:]` installs `_NTKFaceSupportServerInterface`, exports the shared wrapper, resumes the connection, and returns true without a visible client audit-token or entitlement check | The server appears permissive only after transport admission; this does not imply that a third-party app can perform the Mach lookup. |
| 39 | Physical FaceSupport read-only boundary | On Watch7,4 / watchOS 27.0.1 (24R365), `sandbox_check` denied `mach-lookup` of `com.apple.nanotimekit.facesupportserver`; the guarded probe recorded `request-sent=0` and did not call `knownKeyDescriptors:` | The direct app-to-FaceSupport route is blocked by the client sandbox before the permissive listener. Do not repeat direct NanoTimeKit Mach-service probes; pivot to a separately reachable intermediary. |
| 40 | Greenfield watch-face decoder intermediary audit | NanoTimeKit embeds `GreenfieldService-Gizmo.xpc`; it accepts caller-issued read/write sandbox extensions and unzips `.watchface` archives into a UUID-named temporary directory. Its signature uses `temporary-sandbox`, and the duplicated `NTKUnzipUtilities` implementation selects extraction flags `0x308`, including the secure symlink and `..` protections | This helper does not hold FaceSupport write access, and the obvious archive-traversal path is guarded. Do not run a device traversal probe without a new patch-diff or parser-specific premise. |
| 41 | CVE-2022-26704 Spotlight precondition audit | The 24R365 image contains `corespotlightd` and Spotlight frameworks, but its index root is `/private/var/db/Spotlight-V100/%s-%s`. The published exploit requires attacker-controlled mounted-volume metadata/cache entries and a symlink or equivalent filesystem alias; a third-party watch app cannot mount a volume or precreate an entry in that root | Spotlight is present, but the known macOS trigger does not transfer to the stock watch app. A normal CoreSpotlight indexing request would not exercise the vulnerable filesystem precondition, so no device mutation was run. |
| 42 | Physical BPF access gate | `/dev/bpf` returned `ENOENT`; `/dev/bpf0` returned `EPERM`, after which the bounded probe stopped. No BPF ioctl or race was executed | The signed third-party app cannot reach the changed BPF setup path. Disable the opt-in and do not repeat this route from the same sandbox. |
| 43 | Physical IOMobileFramebuffer access gate | On Watch7,4 / watchOS 27.0.1 (24R365), the normally signed app loaded `IOMobileFramebuffer`, `IOMobileFramebufferGetMainDisplay` returned success with a non-null object, and `IOMobileFramebufferGetServiceObject` returned IOService 26371. The app stayed alive; no swap or race was issued | Unlike the parked BPF route, the CVE-2026-112459 userspace surface is reachable from this sandbox. Prioritize exact transaction-state attribution before a bounded lifecycle test. |
| 44 | Physical IOMobileFramebuffer sequential lifecycle | One explicit `IOMobileFramebufferSwapBegin` returned `0` and swap ID 1237807; one immediate `IOMobileFramebufferSwapCancel` of that ID returned `0`. The app and watch remained stable; no concurrency or frame data was used | The suspected transaction lifecycle is reachable and accepts a normal begin/cancel pair from the third-party app. Disable the opt-in; require patch or call-site evidence before choosing a race pair. |
| 45 | Physical owned IOMobileFramebuffer user client | `IOMobileFramebufferOpen` created a separate client for service 26883, `SwapBegin` returned ID 1238384, `SwapCancel` succeeded, and releasing the framebuffer cleanly closed the client. The app and watch remained stable | We now control both the transaction lifecycle and the `IOMobileFramebufferUserClient::stop` teardown path identified by the 27.2 firmware diff. Disable the opt-in; next inspect the pre-fix `stop` implementation before any concurrent teardown. |
| 46 | Physical one-shot IOMFB cancel/teardown overlap | One raw IOConnect selector-4 begin returned swap ID 1239243; selector 0x34 cancel and `IOServiceClose` were released together on separate threads and both returned `0`. The app and watch stayed stable | The attributed `SwapCancel` versus user-client `stop` conflict is executable without a userspace object UAF. One race miss is inconclusive; proceed to a capped independent-client matrix with no payload or spray. |
| 47 | Physical 128-client IOMFB cancel/teardown matrix | All 128 independent raw clients completed. `IOServiceClose` returned success 128 times; concurrent selector-0x34 cancel returned success 126 times and a non-success result twice. The app and watch stayed stable, with no crash or reboot | The two cancel misses are consistent with close winning the connection-lifetime race and are not evidence of memory corruption. Park this exact `Cancel` versus `stop` pair after the one-shot and bounded matrix; do not repeat it without a new crash signature or patch-level premise. |
| 48 | Physical IOMFB sequential End lifecycle | An explicitly owned client opened service 27907; selector-4 `SwapBegin` returned swap ID 1243170, selector-5 `SwapEnd` accepted the zeroed 0x6e0 transaction, and client release completed cleanly | The empty transaction and End transition are valid on this display path, so End/teardown is distinct from the parked Cancel/teardown pair. |
| 49 | Physical one-shot IOMFB End/teardown overlap | A raw client began swap 1243976, then selector 5 and `IOServiceClose` were released together on separate threads. Both returned success; the app and watch stayed stable | One race miss was inconclusive, so exactly one capped independent-client matrix remained justified. |
| 50 | Physical 64-client IOMFB End/teardown matrix | All 64 independent raw clients closed successfully. Concurrent selector-5 End succeeded 63 times; once it returned `0xe00002bc` (`kIOReturnError`, the generic error), with no crash, reboot, or corruption signal | The lone generic error is not evidence of kernel-memory corruption. Park this exact End versus `stop` pair after the one-shot and bounded matrix; a new test now requires patched-disassembly or state/resource evidence. |
| 51 | Physical TCP connection-info access gate | A normally signed app established one loopback TCP connection, then `getsockopt(IPPROTO_TCP, TCP_CONNECTION_INFO)` succeeded on both the client and accepted peer (`status=0`, length 112, state 4). The app and watch remained stable | Later call-site mapping identified the changed helper as `fill_procworkqueue`: `0x817` is `TASK_CRASHINFO_WORKQUEUEINFO`, its 16-byte output is `proc_workqueueinfo`, and the small wrapper maps failure to `ESRCH`. This TCP gate therefore does not validate the candidate. Do not run a TCP race. |
| 52 | Physical process-workqueue access gate | An initialization-time self-query returned `length=0`, `ESRCH` before the process had a workqueue. The same single query from a global dispatch worker returned `length=16`, `error=0`, `threads=1`, `running=1`; app and watch remained stable | A normally signed sandboxed watch app can reach `proc_pidworkqueueinfo` for its own live process. This validates reachability only, not the UAF or cross-process access. The scheme gate was disabled after the successful run. |
## Known useful console excerpts

```text
Local bundle PoC PASS: identifier=dev.develodom.WatchFaceLab.LocalFaceBundle bundle=MYLocalFaceBundle face=MYCustomFace renderer=MYCustomFaceView timeView=NTKDigitalTimeLabel
Argon PoC: discovery PASS
```

```text
OWNED27 NanoTimeKit loaded UUID=4EB0531F-4C9E-343F-9A9A-04C66F69934C
OWNED27 encoding enum=v36@0:8@16B24@?28 lookup=@36@0:8@16@24B32
OWNED27 RESULT lookup=1 enumerated=1 PASS=1
OWNED27 RESTORED class=1 absent=1
OWNED27 END
CustomFace: presented successfully
```

```text
/AppleInternal/Library/NanoTimeKit/FaceBundles -> NSCocoaErrorDomain 260 / ENOENT
/var/mobile/Library/NanoTimeKit/FaceSupport/ExtractedBundles/24R365 -> NSCocoaErrorDomain 257 / EPERM
```

```text
process: "ClockFace" [198]
/Applications/ClockFace.app/ClockFace
cs_flags (0x26003301): valid hard kill enforcement require_lv dyld_platform platform_binary signed
```

## Lessons / pitfalls

- **Never infer the on-device private API from the simulator.** Inspect method selector and ABI for the **running watchOS build**.
- **Check framework exports and packaged binary**, not just Swift/Xcode Build success.
- **Distinguish ObjC `@?` block encoding from the block's actual callback signature.** The first descriptor probe was not ABI-safe.
- **Avoid nested dSYM** in copied frameworks.
- **Do not equate app-local manager hook with system registration.** They are separate processes and trust domains.
- **`EPERM` is not proof of a file existing.** It says the caller was denied access.
- **Do not confuse `ClockFace.axbundle` with `ClockFace.app/ClockFace`.**
- **Do not equate unrelated uses of Apple's Argon codename** (`OSEligibility`, OTA SLAM) with NanoTimeKit Argon without stronger evidence.

## Pending work

App-side collection experiments are closed by the confirmed Mach-lookup denial.
The supported `.watchface` API imports configurations of available system faces;
it does not install an app-defined executable renderer. The practical stock
device alternative is an existing system face carrying a Pip-Boy-styled
WidgetKit complication. A full custom native renderer requires an
Apple-authorized system-host/distribution route or a modified research OS. The
real `ClockFace` binary remains absent from DeviceSupport. Native persistent
Pip-Boy system watchface has **not** been demonstrated.
