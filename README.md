# Watchface Experiments — watchOS 27 (device / arm64)

> **Research status (2026-10-22):** A custom `NTKFace`/`NTKFaceView` renders inside the WatchFaceLab application on a physical watch, but **has not been installed as a persistent system watch face**. This repository explores private watchOS interfaces for educational reverse engineering; it is not an Apple-supported watch-face installer.
>
> **Scope:** This document describes `Experiments/` on the `version/27` branch. Findings marked **Verified** are based on the device, tool output, or the watchOS 27.0.1 NanoTimeKit binary; **Hypothesis / Open** means not experimentally established.

## Objective and current blocker

The goal is a Pip-Boy-inspired **native, persistent** watch face hosted by the system, not a third-party application that happens to draw a clock while it is foregrounded.

- **Verified:** The experimental custom face/view can render within WatchFaceLab, including wrist-down / always-on rendering observed during testing. This does **not** make it a system face: watchOS suspends the app and returns to the selected system face.
- **Verified:** `ClockFace` and `WatchFaceLab` are separate running processes. The system's `NTKFaceBundleManager` does not automatically discover a bundle merely because it is embedded in WatchFaceLab.
- **Open:** A permitted, durable mechanism for system `ClockFace` to discover, trust, instantiate, restore, and render a developer-created native `NTKFaceBundle` on stock watchOS.

## Tested environment

| Item | Observed value |
| --- | --- |
| Physical device | Apple Watch Series 9 (`Watch7,4`, arm64e) |
| Operating system | watchOS **27.0.1** (build **24R365**) |
| Developer Mode | Enabled |
| Xcode / SDK | watchOS 27 SDK; toolchain used for device builds |
| DeviceSupport symbol source | `~/Library/Developer/Xcode/watchOS DeviceSupport/27.0.1 (24R365) universal/Symbols/System/Library/PrivateFrameworks/` |
| NanoTimeKit `arm64e` UUID | `4EB0531F-4C9E-343F-9A9A-04C66F69934C` |
| NanoTimeKit `arm64e.x1` UUID | `EFE5A375-CC31-37EA-B3D0-CB0AC4486A36` |

These UUIDs describe the *on-disk DeviceSupport slices*. We have **not yet confirmed which UUID the running `ClockFace` process has loaded**. Do not set `MY_VERIFIED_NTK_UUID` solely from this table.

A read-only LLDB process list on the physical device confirmed `ClockFace`, `nanotimekitd`, `NTKFaceSnapshotService`, `Carousel`, and `WatchFaceLab` as separate processes. PID values are ephemeral; never hard-code them.

## Device build

The device build script targets `arm64-apple-watchos27.0`, validates private framework device platforms, and emits experimental binaries **without signing them**. This is intentional: the enclosing watchOS app's Xcode build / signing phase must package and sign its embedded code. An ad-hoc signature is not a substitute for deployment signing or system entitlements.

```sh
ROOT="$HOME/Library/Developer/Xcode/watchOS DeviceSupport/27.0.1 (24R365) universal/Symbols/System/Library/PrivateFrameworks"
export WATCH_NTK_BINARY="$ROOT/NanoTimeKit.framework/NanoTimeKit"
export WATCH_CLOCKKITUI_BINARY="$ROOT/ClockKitUI.framework/ClockKitUI"
bash Experiments/symbols_test.sh
bash Experiments/build-watchos-device.sh
```

Expected loose outputs from the device script (default `/tmp/WatchFaceLab27-Device/`):

- `MYCustomFaceExperiment.dylib`
- `FaceBundles/MYLocalFaceBundle.bundle/MYLocalFaceBundle`
- `MYClockFaceBridge.dylib`
- `MYOwnedDiscovery.dylib`

The source bundle manifest is `Experiments/LocalFaceBundle/Info.plist`. It previously declared `CFBundleSupportedPlatforms = WatchSimulator` even though its device Mach-O reported `LC_BUILD_VERSION platform WATCHOS`, minimum OS 27.0, SDK 27.0. **Local remediation performed:** the `version/27` device build script was edited to change the *copied output manifest* to `WatchOS`. Confirm and commit this change in source control; do not patch `/tmp` products manually. Simulator builds should continue to declare `WatchSimulator`.

The bundle's existing `NSPrincipalClass` is `MYLocalFaceBundle`; `CFBundleExecutable` matches the executable and `CFBundlePackageType` is `BNDL`. The original loose device bundle was unsigned by design. Verify the *final embedded app product* separately if deployment fails. `NTKFaceBundle` Info.plist metadata was not present in the inspected output and whether it is required for this particular path remains unproven.

## What was established on watchOS 27.0.1

### 1. `NTKFaceBundleManager` ABI

The following instance methods exist in the **device** NanoTimeKit binary. Objective-C type strings were verified with `xcrun otool -ov -arch arm64e`, not inferred from the method names:

| Method | IMP (unslid) | Verified type encoding |
| --- | --- | --- |
| `enumerateFaceBundlesOnDevice:includingLegacy:withBlock:` | `0x129fcc` | `v36@0:8@16B24@?28` |
| `faceBundleForBundleIdentifier:onDevice:forMigration:` | `0x12a164` | `@36@0:8@16@24B32` |

These match the hard-coded encodings checked by `MYClockFaceBridge.m` in the inspected revision. **Matching method encodings does not prove all private-object semantics or call paths remain compatible.**

### 2. System discovery versus app-local discovery

- `-[NTKFaceBundleManager _init]` constructs a loader from system-controlled search paths and an allowed identifier-prefix collection that includes `com.apple.Faces`.
- The regular system FaceBundles path is `/System/Library/NanoTimeKit/FaceBundles/`.
- A separately constructed `NTKFaceBundleLoader` can enumerate explicitly supplied directories in its **own process**. This does not register them with another process's `NTKFaceBundleManager`.
- `-[NTKFaceBundleLoader loadBundle:]` delegates to Foundation's bundle `load`; success at this level is distinct from entitlement, execution, and system-gallery acceptance.
- The loader's enumeration callback accepts bundles already loaded or declaring `NSPrincipalClass`. Our inspected bundle declares `NSPrincipalClass = MYLocalFaceBundle`.

### 3. `MYClockFaceBridge.m`

The bridge is an **opt-in, process-local** prototype that loads a custom bundle, dynamically subclasses one manager instance, and forwards/extends enumeration and identifier lookup. It has preflight checks, an explicit install/check/remove lifecycle, and no automatic process injection. It cannot bridge processes by itself.

It deliberately **fails closed** on watchOS 27 until the *loaded-image UUID* and method encodings are checked. Its host check requires `com.apple.clockface` and the main thread. These checks should not be disabled merely to make a test pass. Even a successful process-local hook does not establish persistent registration or survival across `ClockFace` restarts.

## Argon: research priority (next experiment)

**What it appears to be:** An internal NanoTimeKit mechanism for locating and processing additional face-related bundles, with code paths involving CloudKit, key descriptors, a local key database, encrypted archives, and extraction. It may support Apple's own development/distribution workflow, but the exact supported payload types and trust boundary are **not established**.

### Verified static findings

The **watchOS 27.0.1** NanoTimeKit disassembly contains:

- `NTKArgonCloudKitClient`, `NTKArgonExtractor`, `NTKArgonLocalKeyDatabase`, `NTKArgonKeyDescriptor`, and references to `NTKAppleEncryptedArchiveDiskExtractor`.
- An internal-only discovery path `/AppleInternal/Library/NanoTimeKit/FaceSupport/UnencryptedBundles/`.
- In `-[NTKFaceBundleManager _init]`, checks involving `NTKInternalBuild` and the `NanoTimeKitExtras` feature flag `load_unencrypted_argon_bundles` before appending the internal path to loader directories.
- `_NTKFaceSupportUnencryptedBundleSearchPathsForDomains`, a helper that selects search paths based on a domain mask. The existence of this helper **does not** show that ordinary production `ClockFace` enables the internal search directory.

A **read-only static PoC** (`argon_unencrypted_poc.py`, produced during research; add to the repo separately if useful) checked six expected patterns against the NanoTimeKit disassembly. Six static checks passed. **This is not a runtime PoC, an installed face, a code-signing bypass, or evidence that a stock watch accepts unencrypted developer bundles.**

### Next Argon experiments

1. **Map the trust boundary:** trace what invokes `NTKFaceBundleLoader` for Argon paths, and identify where extraction, archive authentication, executable loading, code signature enforcement, and identifier validation occur. Distinguish archive encryption keys from executable code-signing identities.
2. **Characterize the payload:** establish whether an Argon bundle includes a new executable `NTKFace` subclass or only resources/configuration for pre-existing system renderers. This is the decisive question for a custom Pip-Boy face.
3. **Controlled app-local PoC:** reproduce format/discovery behavior with files inside the *developer-owned app container*; log enumeration, bundle metadata and load failures. No writes to `/System` or `/AppleInternal` and no system-process modification.
4. **Document stock-device limitations:** if `NTKInternalBuild` / feature availability or code-signature policy blocks the production device, record that as a result. Do not infer a signature bypass from a successful unpack or local discovery test.

**Important:** Replacing a bundle identifier with `com.apple.Faces.*`, or changing an Info.plist, does not forge Apple's cryptographic code signature. Argon extraction/decryption and the operating system's code-signature validation are separate concerns.

## Verified boundaries / non-goals

- Public WidgetKit complications and `.watchface` configuration import are not the same as registering a new executable native watch-face renderer.
- The experiment has **not** modified system partitions, installed a bundle into `ClockFace`, obtained Apple-internal entitlements, or achieved a durable third-party face on stock watchOS.
- Listing the `ClockFace` PID via LLDB does not prove debugger attach, injection, or execution rights.
- Static NanoTimeKit symbols from DeviceSupport may not fully represent the runtime-loaded image or its available entitlements.
- Research on a real device should start with read-only diagnostics and isolated app-owned tests. Avoid modifying the active system watch-face process without a verified recovery plan.

## Reproducible inspection commands

```sh
ROOT="$HOME/Library/Developer/Xcode/watchOS DeviceSupport/27.0.1 (24R365) universal/Symbols/System/Library/PrivateFrameworks"
xcrun dwarfdump --uuid "$ROOT/NanoTimeKit.framework/NanoTimeKit"
xcrun otool -ov -arch arm64e "$ROOT/NanoTimeKit.framework/NanoTimeKit" \
  | grep -A 12 -B 5 -F 'enumerateFaceBundlesOnDevice:includingLegacy:withBlock:' \
  | head -100
```

The watchOS 27 device and watchOS simulator frameworks are **not interchangeable**. The earlier simulator-only preparation script is not a device system-host injector.

## Project status

- [x] Physical watchOS 27.0.1 device and NanoTimeKit ABI identified
- [x] Custom watch-face renderer working inside WatchFaceLab (app lifecycle only)
- [x] App-local bundle loader and manager bridge implemented
- [x] Argon internal unencrypted-bundle path identified statically
- [ ] Confirm loaded-image UUID and host behavior at runtime
- [ ] Establish Argon executable-versus-resource payload type
- [ ] Demonstrate trusted, durable system `ClockFace` registration

**Bottom line:** The largest unsolved issue is **system-host discovery and trust**, not rendering or the two verified Objective-C method encodings.
