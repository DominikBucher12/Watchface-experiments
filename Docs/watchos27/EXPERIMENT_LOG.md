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

Real `ClockFace` Mach-O audit; verify its manager/gallery integration and signing/entitlements; FaceSupportServer authorization; evaluate whether any supported third-party executable face registration exists. Native persistent Pip-Boy system watchface has **not** been demonstrated.
