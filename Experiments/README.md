# Watchface Experiments — watchOS 27 device / arm64

This folder is an **architecture migration**, not a proven on-device system face implementation.

## What changed
- `build-watchos-device.sh`: arm64 WATCHOS target; validates device NanoTimeKit / ClockKitUI using `vtool -arch arm64e`; links ImageIO and QuartzCore; produces four artifacts **unsigned**. It does not bundle or install any of them.
- `MYClockFaceBridge.m`: builds for arm64 physical watchOS only; stale x86_64 guard and CPU check removed. **FAILS CLOSED** by default on watchOS 27: old 26.5 simulator UUID is not trusted, and method encodings have not been verified for this device ABI. The separate owned bridge inherits this guard.
- `MYCustomFace.m`: GIF is resolved from `NSBundle mainBundle` (add `pip-boy-reference.gif` to watch app resources); no Mac `/tmp` assumption.
- `NTKPrivateInterfaces.h`: explicitly documents watchOS 27 ABI as unverified.
- `symbols_test.sh`: deterministic watchOS 27.0.1 DeviceSupport path and `arm64e` inspection.
- `prepare-debug-target.py`: preserved for **simulator-only** research, with `--device` explicitly rejected. It does not prepare a physical-device system host.
- Other `.m` / `.h` files: checked; they contain no x86 assembly or x86-only compiler targets. Existing runtime API contracts remain unverified on 27.

## Missing input
`LocalFaceBundle/Info.plist` and `LocalFaceBundle/MYLocalFaceBundle.m` were NOT supplied. The build script expects them and cannot complete all four outputs without them. `pip-boy-reference.gif` was also not included.

## Build on Mac with Xcode watchOS 27 SDK

```sh
ROOT="$HOME/Library/Developer/Xcode/watchOS DeviceSupport/27.0.1 (24R365) universal/Symbols/System/Library/PrivateFrameworks"
export WATCH_NTK_BINARY="$ROOT/NanoTimeKit.framework/NanoTimeKit"
export WATCH_CLOCKKITUI_BINARY="$ROOT/ClockKitUI.framework/ClockKitUI"
bash Experiments/symbols_test.sh
bash Experiments/build-watchos-device.sh
```

Execute from the directory *above* `Experiments`. This requires the unsupplied `LocalFaceBundle` files to build all outputs.

## Device integration caution
- watchOS device and simulator binaries are distinct platforms.
- Symbol files from DeviceSupport are not necessarily suitable link-time stubs; successful linking does not guarantee on-device dynamic linking.
- The compiled output is a loose `.dylib`; for deployment use an appropriately structured **embedded framework**, signed by Xcode with the containing Watch app. This archive does not provide that framework target.
- System-host hooks are disabled. Do not patch or resign system Watch apps assuming they will retain private entitlements.
- Do not assume `UIKit` availability or the selected private selectors on a physical watch; first validate with safe runtime introspection.
- No watchOS 27 physical-device build or launch was performed here.
