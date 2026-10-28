# Device build, embedding, and reproduction

## Environment and components

- **Physical device:** Apple Watch Series 9, watchOS 27.0.1 (24R365), CPU arm64e; Developer Mode enabled.
- **Host:** Intel/x86_64 Mac, Xcode/watchOS toolchain with device symbols for 27.0.1.
- **Application:** `WatchFaceLab` (`dev.develodom.WatchFaceLab`).
- **Native classes:** `MYCustomFace` (`NTKFace`) and `MYCustomFaceView` (`NTKFaceView`), with `NTKDigitalTimeLabel`.
- **Assets:** `WatchFaceLab/Resources/pip-boy-reference.gif`.
- **Framework:** `Experiments/Build/Device/MYCustomFaceExperiment.framework`, installed in `WatchFaceLab.app/Frameworks`.
- **Local bundle:** `Experiments/Build/Device/FaceBundles/MYLocalFaceBundle.bundle`, embedded as an app resource; bundle identifier `dev.develodom.WatchFaceLab.LocalFaceBundle`; principal class `MYLocalFaceBundle`.
- **Main Swift entry:** `WatchFaceLab/CustomFaceLoader.swift`, `dlopen` + `dlsym` of framework exports.

## Relevant files

`Experiments/MYCustomFace.m`, `Experiments/MYBundleDiscovery.m`, `Experiments/LocalFaceBundle/{MYLocalFaceBundle.m,Info.plist}`, `Experiments/NTKPrivateInterfaces.h`, `Experiments/build-embedded-framework.sh`, `Experiments/build-local-face-bundle.sh`, `Experiments/build-watchos-device.sh`, and probe sources added over the experiment series (`MYArgonRuntimeProbe.m`, `MYArgonABIProbe.m`, `MYArgonDescriptorProbe.m`, `MYOwnedManagerWatch27.m`). Some may exist only in the working branch, depending on which patches have been committed.

## Build sequence that worked

The current one-command path is:

```bash
bash Experiments/bootstrap-watchos27-device.sh --check
bash Experiments/bootstrap-watchos27-device.sh
```

`--build-only` produces and verifies the signed app without requiring the Watch
to be online. `--device COREDEVICE-ID` selects a particular available Watch.
The preflight rejects an active Xcode whose watchOS SDK is older than the 27.0
deployment target; select the intended Xcode with `xcode-select` first.
The resolver chooses the newest matching watchOS DeviceSupport pair by default;
set `WATCH_DEVICE_SUPPORT_FILTER=24R365` or explicit binary variables when a
specific build is required.

The bootstrap is deliberately app-contained. A successful run proves native
rendering and local bundle discovery inside WatchFaceLab, not registration in
the separately signed system `ClockFace` process.

### Manual equivalent

From repository root on the Mac:

```bash
ROOT="$HOME/Library/Developer/Xcode/watchOS DeviceSupport/27.0.1 (24R365) universal/Symbols/System/Library/PrivateFrameworks"
export WATCH_NTK_BINARY="$ROOT/NanoTimeKit.framework/NanoTimeKit"
export WATCH_CLOCKKITUI_BINARY="$ROOT/ClockKitUI.framework/ClockKitUI"

bash Experiments/build-embedded-framework.sh
bash Experiments/build-local-face-bundle.sh

FW="Experiments/Build/Device/MYCustomFaceExperiment.framework"
xcrun nm -gU "$FW/MYCustomFaceExperiment" | grep -E 'MYDiscoverLocalFaceBundle|MYPresentCustomFaceExperiment'
```

Both scripts now resolve a matching NanoTimeKit/ClockKitUI pair from Xcode
DeviceSupport automatically. Explicit `WATCH_NTK_BINARY` and
`WATCH_CLOCKKITUI_BINARY` values override discovery. The local bundle script
still requires the framework build first; the Xcode phase and bootstrap enforce
that order.

### Xcode phase ordering / stale binary trap (fixed)

Observed Xcode phases: `Embed Frameworks`, custom `Run build-local-face-bundle`, `Copy Files` (resource embedding, `Code Sign On Copy`). A normal Xcode app rebuild **did not necessarily rebuild the manually produced framework**. This caused an old Objective-C selector to remain in the deployed binary after source changes.

The bootstrap builds the framework and local face bundle before invoking
`xcodebuild`, so Xcode creates its copy graph from current, clean inputs. The
project's Run Script phase repeats the same build for direct Xcode builds, then
the copy phases embed and sign both artifacts. The bootstrap validates the final
app layout, signatures, platform load command and NanoTimeKit dependency before
installing. The watchOS 27 target is constrained to `arm64`, matching the
embedded private framework and face bundle; the verifier rejects mixed slices.

### dSYM placement failure

`build-embedded-framework.sh` initially produced:

```
MYCustomFaceExperiment.framework/
  MYCustomFaceExperiment
  MYCustomFaceExperiment.dSYM/Contents/Resources/DWARF/MYCustomFaceExperiment
```

Xcode's embed copy attempted to run `strip` on the nested dSYM DWARF executable and failed with exit status 1. Moving `.dSYM` **outside** `.framework` fixed the Xcode build:

```bash
FW="Experiments/Build/Device/MYCustomFaceExperiment.framework"
if [ -d "$FW/MYCustomFaceExperiment.dSYM" ]; then
  mv "$FW/MYCustomFaceExperiment.dSYM" "${FW}.dSYM"
fi
```

Standalone `clang -g` can create a nested dSYM after linking. The framework
script moves that output, plus any copy left by an older build, under
`Experiments/Build/Device/DebugSymbols/` before Xcode copies the framework.
Keep any future dSYM beside the framework rather than inside it.

## Selector ABI regression (fixed)

The initial app crashed with:

```
+[NTKFaceBundleLoader faceBundleLoaderWithDirectories:]: unrecognized selector
```

watchOS 27.0.1 uses:

```objc
+[NTKFaceBundleLoader faceBundleLoaderWithDirectories:appBundleIdentifierPrefixes:]
```

Runtime type encoding: `@32@0:8@16@24`. The Objective-C declaration and callers were corrected, then **framework manually rebuilt**. Fixing source only was insufficient because Xcode embedded stale binary.

## Reproducing the verified local discovery

Embedded framework export `MYDiscoverLocalFaceBundle` was verified using `nm` and invoked with `dlsym` from `CustomFaceLoader.swift`. It loads `MYLocalFaceBundle.bundle` via a standalone `NTKFaceBundleLoader`, validates bundle principal class and identity, creates `MYCustomFace` and `MYCustomFaceView`, and confirms `timeView` is `NTKDigitalTimeLabel`.

Observed:

```
Local bundle PoC PASS: identifier=dev.develodom.WatchFaceLab.LocalFaceBundle bundle=MYLocalFaceBundle face=MYCustomFace renderer=MYCustomFaceView timeView=NTKDigitalTimeLabel
Argon PoC: discovery PASS
CustomFace: presented successfully
```

Do **not** infer system-face registration from this: the view remains tied to WatchFaceLab, not `ClockFace`.

## Safe validation commands

```bash
xcrun nm -gU Experiments/Build/Device/MYCustomFaceExperiment.framework/MYCustomFaceExperiment | grep -E 'MYInspectArgon|MYTestOwnedManagerWatch27|MYDiscoverLocalFaceBundle'
xcrun otool -L Experiments/Build/Device/MYCustomFaceExperiment.framework/MYCustomFaceExperiment
```

Use Xcode Build & Run after verifying current framework; if private API crashes recur, check **deployed embedded binary** and source vs symbol strings before changing API code again.
