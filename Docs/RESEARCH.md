# Research log — watchOS 26.5 / Intel simulator

These observations are from the user's own `otool`/`llvm-objdump` output, **not** a proof that injection or custom face registration works.

- Simulator runtime: watchOS 26.5, build 23T570, x86_64 and arm64.
- `NanoTimeKit.framework/NanoTimeKit` exists in `RuntimeRoot/System/Library/PrivateFrameworks` as a universal Mach-O.
- `NTKFace` subclasses `NSObject`; `NTKFaceView` subclasses `UIView`.
- `-[NTKFace(ViewSupport) faceViewClass]` base implementation returns Nil.
- `+[NTKFaceView newFaceViewForFace:]` calls `_ViewClassForFace`.
- `_ViewClassForFace` first sends `faceViewClass` to the face. If non-Nil, it uses the returned Class; otherwise it falls back to bundle identifier/style lookup.
- The view factory calls `initWithFaceStyle:forDevice:clientIdentifier:` on the resulting class.
- `-[NTKFace _initWithFaceStyle:forDevice:]` calls super init, `_commonInit`, and complication observer setup.
- `_commonInit` creates internal state; no claim is made that arbitrary subclasses can initialize safely without further checks.

## Gate for next experiment

1. Confirm the public baseline app builds and launches in an **x86_64** watchOS 26.5 simulator.
2. Locate watch face hosting process (do not assume `Carousel` still hosts it).
3. Inspect loaded `NanoTimeKit` classes and Objective-C method signatures at runtime via LLDB.
4. Compile experimental Objective-C code as a separate simulator module.
5. Verify whether debugger injection is permitted, and whether an instance of `MYCustomFace` plus `MYCustomFaceView` can be instantiated.
6. Only then investigate actual face registration or UI presentation.

**Warning:** experimental code is not linked into the shipping-style watch app. A regular third-party watch app cannot thereby install a real system watch face. Private API is unsupported and not App Store-eligible.

## First isolated module — 2026-10-21

The user confirms the SwiftUI baseline builds and launches. Its sources and Xcode
project are unchanged by this experiment. The historical injection gates above
are superseded for this milestone: no system process injection is required or
performed. There is no automatic constructor, app hook, or registration code.

### Verified directly from installed 23T570 x86_64 binaries

Runtime root:
`/Library/Developer/CoreSimulator/Volumes/watchOS_23T570/Library/Developer/CoreSimulator/Profiles/Runtimes/watchOS 26.5.simruntime/Contents/Resources/RuntimeRoot`

`xcrun otool -arch x86_64 -ov <binary>` reports:

| Method | Encoding |
| --- | --- |
| `-[NTKFace _initWithFaceStyle:forDevice:]` | `@32@0:8q16@24` |
| `-[NTKFace(ViewSupport) faceViewClass]` | `#16@0:8` |
| `-[NTKFaceView initWithFaceStyle:forDevice:clientIdentifier:]` | `@40@0:8q16@24@32` |
| `+[NTKFaceView newFaceViewForFace:]` | `@24@0:8@16` |
| `+[CLKDevice currentDevice]` | `@16@0:8` |

Style is signed (`q`), represented by `NSInteger`, correcting the starter's
unsigned declaration. Object encodings do not independently establish concrete
parameter classes or nullability.

ClockKit resides in `System/Library/Frameworks/ClockKit.framework`. Its x86_64
`currentDevice` implementation at 0x3b413 locks and checks a cached device. On a
cache miss it tests a NanoRegistry entitlement before optionally requesting an
active PDR device, then calls `_createCurrentDeviceWithPDRDevice:`. In this
simulator binary that helper (0x3b554) allocates CLKDevice and passes nil to
`initWithPDRDevice:`. This is evidence for using `+[CLKDevice currentDevice]`,
not a reason to reproduce its initialization internals. No guessed CLKDevice
initializer is called by the experiment.

### Build and entry point

Run from the repository root:

```sh
bash Experiments/build-simulator.sh
```

The optional first argument selects an output directory (default
`/tmp/WatchFaceLab26-NTK`). `WATCH_RUNTIME_ROOT` can override the installed runtime
root. No framework binaries or Apple headers are copied. The script compiles a
standalone dylib, directly linking the installed NanoTimeKit binary and using
the installed SDK for Foundation, UIKit, ClockKit, and CoreGraphics. Runtime
private-framework search paths resolve indirect linker dependencies.

UIKit's SDK marks UIView and UILabel unavailable on watchOS even though the
runtime contains UIKit. A narrowly scoped `API_UNAVAILABLE` macro override around
the UIKit import permits this private experiment to compile. Modules are disabled
so that the local override applies; the macro is restored immediately afterward.
This is a compile-time workaround, not evidence of supported UIKit hosting.

Build passed with `-Wall -Wextra -Werror`. `otool -L` confirms a NanoTimeKit
install name of `/System/Library/PrivateFrameworks/NanoTimeKit.framework/NanoTimeKit`,
not a host volume path. `vtool -show-build` confirms WATCHOSSIMULATOR, minimum OS
26.5 and SDK 26.5. The artifact is x86_64 only.

The explicit exported function is declared in `Experiments/MYCustomFace.h`:

```objc
MYCustomFaceView *MYCreateCustomFaceView(NSInteger style, MYCustomFace **faceOut);
```

It must be called on the main thread in an authorized simulator app host after
loading the module. Supply a researched style value; none is selected by default.
Retain both the returned view and the face received through `faceOut`. The host
must give the view a nonzero frame and attach it to an appropriate view hierarchy.
The factory verifies that NanoTimeKit returned the custom renderer subclass.
No debugger loading, app presentation, or system-process attachment was performed.

### Remaining assumptions / blockers

- No face style value has yet been established as safe for this subclass.
- Device retrieval, face allocation, factory dispatch, and layout are verified
  statically or compiled only; they have not been executed in the app process.
- NTKFace initialization may require additional subclass behavior, services,
  entitlements, or valid style metadata. A non-nil currentDevice is not sufficient
  proof of successful initialization.
- The view factory may configure other internal views or require lifecycle state.
  Bringing the label to the front in layout is an experiment, not a guarantee of
  visibility in a real face host.
- Runtime loading may encounter signing, dyld, or process policy restrictions.
  Link success does not validate those policies.
- The view initializer's clientIdentifier is passed through from the verified
  factory; the experiment does not invent a client identifier.
- This module creates an in-process renderer only. System watch face installation
  and registration remain outside this milestone.

## App-host preview preparation — 2026-10-21

Further inspection of the installed disassembly:

- `_NTKFaceStyleDescription` (0x15b2a) normalizes the input using
  `_NTKEffectiveFaceStyleForFaceStyle`, then indexes the CFString-pointer table
  at 0x5cd338 for recognized legacy values. Reading entry zero and its CFString
  from the installed x86_64 Mach-O gives `utility` (1=`simple`, 2=`chronograph`,
  3=`color`, 4=`modular`). Chained rebase pointer metadata was masked to extract
  the low 36-bit target offset. No binary was copied into the project.
- The effective-style function leaves zero unchanged. `_initWithFaceStyle:`
  stores its supplied style before `_commonInit`; it does not itself validate
  the style. Thus zero is a researched test input, not proof of initialization
  safety. The earlier note that no style had been identified is superseded.
- `newFaceViewForFace:` obtains style, device, and bundleIdentifier from the face,
  passing the latter to the renderer initializer. The minimal face initializer
  does not populate bundleIdentifier; nil clientIdentifier acceptance remains a
  runtime assumption. No override or guessed setter was added to mask this.

Added explicit `MYPresentCustomFaceExperiment(style)` and
`MYDismissCustomFaceExperiment()` functions. The preview is restricted to the
WatchFaceLab bundle identifier, requires the main thread and an active app scene,
retains the face/window, and hosts the custom view in a temporary UIWindow using
SDK-declared UIKit APIs. It does not run automatically. The existing SwiftUI
sources and Xcode project remain unchanged. UIKit hosting on watchOS remains
unproven; these SDK declarations are ordinarily unavailable there.

The build script now ad-hoc signs the dylib. Rebuilt successfully with warnings
as errors; `codesign --verify --verbose` and `git diff --check` passed.

Live inspection found the watchOS 26.5 simulator booted and WatchFaceLab running
as PID 5785. A debugger attach to that app failed with `tried to attach to process
already being debugged`. No other process was attached, stopped, or modified.
The redundant debugger was closed. Runtime execution is pending commands in the
existing Xcode debugger; see `Docs/LLDB-EXPERIMENT.md`. Neither successful allocation
nor visual presentation is claimed yet.

## First successful in-app execution — user-reported, 2026-10-21

The user executed the prepared commands in the existing Xcode debugger and
reported:

```text
(BOOL)[NSThread isMainThread] -> YES
process load /tmp/WatchFaceLab26-NTK/MYCustomFaceExperiment.dylib -> ok
MYPresentCustomFaceExperiment((long)0):
has no material, defaulting to light aluminum
Custom Face PoC: face=MYCustomFace renderer=MYCustomFaceView style=0 bounds={{0, 0}, {208, 248}}
return -> YES
```

This supersedes the pending allocation status above. In this app process and
runtime, device retrieval returned non-nil, the custom face initializer returned
an object, and NanoTimeKit's factory returned MYCustomFaceView. The preview helper
completed window presentation and layout with nonzero bounds. The reported
material diagnostic did not prevent the function from succeeding; its precise
origin and implications have not been investigated.

The console output establishes allocation, custom renderer selection, and
completion of the app-host presentation calls. Actual on-screen label visibility
has not been explicitly confirmed separately. It does not establish system face
registration, persistence, complication behavior, or compatibility with other
styles, devices, or processes. Nil bundleIdentifier/clientIdentifier did not
prevent this tested path from completing; broader validity remains unproven.

Next validation: continue the app, confirm the label visually, then invoke
MYDismissCustomFaceExperiment on the main thread and verify the original SwiftUI
clock returns. Repeated presentation/dismissal and app restart are useful lifecycle
checks before expanding beyond this minimal in-app milestone. System process
injection and runtime changes remain outside the authorized experiment.
