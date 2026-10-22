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

The framework script **requires** `WATCH_NTK_BINARY`; omission produces `line 9: WATCH_NTK_BINARY: export WATCH_NTK_BINARY with the device NanoTimeKit Mach-O path`. The local bundle script requires the built framework first.

### Xcode phase ordering / stale binary trap

Observed Xcode phases: `Embed Frameworks`, custom `Run build-local-face-bundle`, `Copy Files` (resource embedding, `Code Sign On Copy`). A normal Xcode app rebuild **did not necessarily rebuild the manually produced framework**. This caused an old Objective-C selector to remain in the deployed binary after source changes.

**Desired dependency order:** build framework → build local face bundle → embed/sign both artifacts. Xcode phases must implement that order explicitly; `Embed Frameworks` only copies/signs an existing framework. Validate framework exports with `nm` **after** build, before app installation. Confirm final `.app` layout and `LC_RPATH` if changing Copy Files destination.

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

**Known technical debt:** permanently fix output location in `build-embedded-framework.sh` (user explicitly deferred this). If destination already exists, inspect before replacing rather than blindly overwriting debug symbols.

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
