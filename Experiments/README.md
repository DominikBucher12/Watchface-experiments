# Watchface Experiments — watchOS 27 device / arm64

This folder is an **architecture migration**, not a proven on-device system face implementation.

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
