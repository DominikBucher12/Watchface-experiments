# Watchface Experiments — watchOS 27 device / arm64

This folder is an **architecture migration**, not a proven on-device system face implementation.

## Bounded `.watchface` parser lab

The `research/watchface-parser` branch adds
`watchface-parser-lab.sh`. It inspects an owned system export, creates a small
hash-locked corpus, and sends exactly one explicitly selected case through the
public `CLKWatchFaceLibrary` API on an owned Watch. It never loops over cases or
relaunches after a possible crash. Generated corpora and run evidence are
ignored by Git. Follow
[`Docs/WATCHFACE-BOUNTY-LAB.md`](../Docs/WATCHFACE-BOUNTY-LAB.md).

## Series 9 CVE surface batch

`cve-probe-lab.sh` builds and installs the signed Watch app once, then runs up
to 16 deterministic, hash-locked cases across ImageIO, CoreText/FontParser,
CoreAudio, and the public AVFoundation/AppleAVD path. Each input gets a fresh
app process; a timeout or invalid result stops the batch without retrying it.
Generated corpus and evidence directories are ignored by Git.

```sh
bash Experiments/run-all-s9-cve-probes.sh --owned-device
```

This one command prepares and verifies the corpus, previews the plan, builds
once, and runs every available case. Use `--plan-only` for a no-device dry run.

The public watchOS SDK has no VideoToolbox encoder API, so this does not claim
to reproduce an `AVEVideoEncoder` CVE. See
[`Docs/S9-CVE-PROBE-LAB.md`](../Docs/S9-CVE-PROBE-LAB.md) for the component/CVE
map, safety limits, subsets, evidence handling, and exact commands.

## Generated files are not checked in

This directory contains experiment sources and scripts. `Build/`, copied Apple
runtimes/frameworks, disassembly dumps, dSYMs, bundles, dylibs, and Xcode user
state are ignored. Recreate products with the documented scripts and keep
DeviceSupport binaries in Xcode's directories. See
[`Docs/REPOSITORY_CLEANUP.md`](../Docs/REPOSITORY_CLEANUP.md).

## What changed
- `build-watchos-device.sh`: arm64 WATCHOS target; validates device NanoTimeKit / ClockKitUI using `vtool -arch arm64e`; links ImageIO and QuartzCore; produces four artifacts **unsigned**. It does not bundle or install any of them.
- `MYClockFaceBridge.m`: builds for arm64 physical watchOS only; stale x86_64 guard and CPU check removed. **FAILS CLOSED** by default on watchOS 27: old 26.5 simulator UUID is not trusted, and method encodings have not been verified for this device ABI. The separate owned bridge inherits this guard.
- `MYCustomFace.m`: GIF is resolved from `NSBundle mainBundle`. `WatchFaceLab/Resources/pip-boy-reference.gif` is included in the watch app Copy Bundle Resources; no Mac `/tmp` assumption.
- `NTKPrivateInterfaces.h`: explicitly documents watchOS 27 ABI as unverified.
- `symbols_test.sh`: deterministic watchOS 27.0.1 DeviceSupport path and `arm64e` inspection.
- `prepare-debug-target.py`: preserved for **simulator-only** research, with `--device` explicitly rejected. It does not prepare a physical-device system host.
- Other `.m` / `.h` files: checked; they contain no x86 assembly or x86-only compiler targets. Existing runtime API contracts remain unverified on 27.

## Animation asset
The original 512×640 Tenor animation is checked in at
`WatchFaceLab/Resources/pip-boy-reference.gif` and copied into the app bundle by Xcode.
Source: https://media1.tenor.com/m/zojzGy0Y9gQAAAAd/pip-boy-applewatch.gif

The `LocalFaceBundle` sources are included in this checkout.

## Build on Mac with Xcode watchOS 27 SDK

For the complete signed, app-contained device flow:

```sh
bash Experiments/bootstrap-watchos27-device.sh --check
bash Experiments/bootstrap-watchos27-device.sh
```

The bootstrap finds matching DeviceSupport symbols, builds the framework and
face bundle before Xcode's embed phases, verifies the signed `.app`, installs it
on an available paired Apple Watch, and launches WatchFaceLab. Use
`--build-only` when the Watch is temporarily unavailable. This renders the
native face inside WatchFaceLab; it does not modify or register with the system
`ClockFace` process.

The physical system collection experiment is explicit and staged. Start with:

```sh
bash Experiments/watchos27-device-face.sh preflight
```

This stable convenience script also accepts `audit`, `boundary`, `result`,
`install`, `select`, and `rollback`; it automatically selects the first available physical
Watch for device actions unless `--device ID` is supplied. `result` only
downloads the last JSON. `audit` does not contact the Watch: it inspects the
matching DeviceSupport copy of the real `ClockFace`, `nanotimekitd`,
NanoTimeKit, FaceSupport components, signatures, entitlements, linked images,
and boundary-related strings. `boundary` reinstalls/launches WatchFaceLab and
queries only its own sandbox and signed entitlements; it sends no XPC request
and performs no face-collection mutation.

Then follow [`Docs/watchos27/DEVICE_SYSTEM_FACE_PROBE.md`](../Docs/watchos27/DEVICE_SYSTEM_FACE_PROBE.md).
The bootstrap copies the result from the app data container and prints the
authoritative `SYSTEM_FACE_RESULT` record. This avoids relying on watchOS unified
logging being relayed through `devicectl --console`.

Manual framework builds remain available. Explicit paths override automatic
DeviceSupport discovery:

```sh
ROOT="$HOME/Library/Developer/Xcode/watchOS DeviceSupport/27.0.1 (24R365) universal/Symbols/System/Library/PrivateFrameworks"
export WATCH_NTK_BINARY="$ROOT/NanoTimeKit.framework/NanoTimeKit"
export WATCH_CLOCKKITUI_BINARY="$ROOT/ClockKitUI.framework/ClockKitUI"
bash Experiments/symbols_test.sh
bash Experiments/build-watchos-device.sh
```

Execute from the directory *above* `Experiments`. The `LocalFaceBundle` files are included.

## Device integration caution
- watchOS device and simulator binaries are distinct platforms.
- Symbol files from DeviceSupport are not necessarily suitable link-time stubs; successful linking does not guarantee on-device dynamic linking.
- Device outputs are generated under ignored `Experiments/Build/Device`; Xcode embeds and signs the framework and bundle with the containing Watch app.
- System-host hooks are disabled. Do not patch or resign system Watch apps assuming they will retain private entitlements.
- Do not assume `UIKit` availability or the selected private selectors on a physical watch; first validate with safe runtime introspection.
- The app-contained renderer and local discovery were previously verified on a
  physical watchOS 27.0.1 Watch; persistent system-face registration remains
  unproven.
