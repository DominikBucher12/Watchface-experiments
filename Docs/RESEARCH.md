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

## Visual confirmation and hosting/discovery investigation — 2026-10-21

The user explicitly confirmed that preview display and dismissal work. The
allocation, visible-label, and return-to-SwiftUI milestones are now user-verified.
Three lifecycle cycles and a repeat in a fresh app process are still pending
user execution in the existing debugger. No automated result is claimed.

See `Docs/HOSTING-AND-DISCOVERY.md` for the current evidence and next experiment
design. A fresh disassembly and installed bundle plists were read without
modifying the runtime. NanoTimeKit x86_64 UUID is
`BA6B817D-D837-37DA-9BD1-DB2D1FC9CAD3`.

Key findings: native hosting uses NTKFaceViewController; its configuration
argument is a block (`@?`), not a configuration object. ClockFace imports
NTKClockViewController, which constructs the face controller. Discovery uses
NTKFaceBundleLoader, NSPrincipalClass and bundle/container classes, plus device
restriction checks. A standalone face/view dylib does not implement that bundle
identity and gallery contract. Registration remains unproved.

Added the read-only `Experiments/inspect-runtime.py` collector. Running it against
the installed runtime verified 15 expected hosting/discovery symbols and inventoried
60 bundle directories (59 root Info.plists). Its JSON report is generated under
`/tmp/WatchFaceLab26-NTK`, outside the repository. No Apple binary or header was
copied into the project. No app implementation, simulator runtime, global loader,
face library, or system process was changed during this investigation.

## Native-controller experiment implementation — 2026-10-21

Re-read installed 23T570 x86_64 Objective-C metadata before adding declarations:

| Evidence | Result |
| --- | --- |
| NTKFaceViewController superclass | UIViewController |
| `initWithFace:configuration:` | `@32@0:8@16@?24` |
| `faceView` | `@16@0:8` |
| `becomeActive` / `resignActive` | `v16@0:8` |

The block's sole explicit argument is the controller, verified in
`configureWithDuration:block:` disassembly. The new initializer call passes nil;
no unverified configuration setters are called.

Added three explicitly invoked helpers in the standalone module:
`MYPresentNativeControllerExperiment(style)`,
`MYSetNativeControllerExperimentActive(active)`, and
`MYDismissNativeControllerExperiment()`. Presentation creates the custom face,
lets NTKFaceViewController create/configure its renderer, checks the renderer
class, and hosts the native controller in a temporary app-owned window. Stage
logs distinguish device retrieval, face initialization, native initialization,
renderer validation, presentation, activation and dismissal. Both preview paths
reject simultaneous presentation. The native path retains the face/controller
and restores the previous key window during cleanup. It does not catch private
initialization exceptions or add speculative subclass overrides.

The updated module builds with warnings as errors and passes ad-hoc signature
verification. Native runtime execution remains pending in the user's existing
Xcode session; the old module requires an app restart before loading the update.
See the native-controller section of `Docs/LLDB-EXPERIMENT.md` for staged calls.
Native initialization, label visibility, teardown, explicit activation and repeated
cycles are all untested at this point. The prior simple preview success does not
establish these results. No system process or runtime file was modified; the
SwiftUI app sources and Xcode project remain unchanged by this implementation.

## Native controller execution and time-view implementation — 2026-10-21

User-provided LLDB output confirms the native controller initialized with a nil
configuration block, returned MYCustomFaceView at 208 x 248 bounds, returned YES
from presentation, and completed dismissal/ownership release. It emitted
`timeView is missing for faceView`. Explicit activation and deallocation remain
unverified. No inference about deallocation is made from ownership release.

The diagnostic originates in `-[NTKFaceView tritium_timeViews].cold.1` at
0x479729. Its caller checks the cached NTKTritiumAnimator conformance flag and
logs the diagnostic when false; it then checks the timeView and its protocol
conformance before returning a list. Thus the wording can indicate a missing
or nonconforming view; merely setting any UIView would not establish the contract.
`setTimeView:` at 0x20ed42 retains the view and computes that conformance flag.

Traced the built-in digital path:

- `-[NTKDigitalFaceView _timeLabelOptions]` at 0x138f65 returns zero.
- `_createTimeViewIfNecessary` at 0x1390ad sends
  `+[NTKDigitalTimeLabel labelWithOptions:forDevice:]`, sets legibility/color and
  a framework time offset, assigns the result via `setTimeView:`, and adds it to
  `rootContainerView`.
- Installed metadata says NTKDigitalTimeLabel inherits CLKUITimeLabel, which
  inherits UIView. The factory is inherited from ClockKitUI, not implemented
  directly on NTKDigitalTimeLabel.
- ClockKitUI's `+[CLKUITimeLabel labelWithOptions:forDevice:]` at 0x2fa38 allocates
  its receiver and invokes `initWithTimeLabelOptions:forDevice:`. Invoking the
  inherited factory on NTKDigitalTimeLabel therefore allocates that subclass.

Verified encodings in installed x86_64 metadata before calling:

| Method | Encoding |
| --- | --- |
| `+[CLKUITimeLabel labelWithOptions:forDevice:]` | `@32@0:8Q16@24` |
| `-[CLKUITimeLabel setFont:]` | `v24@0:8@16` |
| `-[NTKDigitalTimeLabel setTextColor:]` | `v24@0:8@16` |
| `-[NTKFaceView timeView]` | `@16@0:8` |
| `-[NTKFaceView setTimeView:]` | `v24@0:8@16` |
| `-[NTKFaceView rootContainerView]` | `@16@0:8` |

MYCustomFaceView now creates this native time label with options zero and the
same CLKDevice, sets a white 40-point monospaced font, assigns it as timeView,
and places it in the native root container. Public UIView sizing/centering keeps
it in the middle; the PoC label is smaller and below it. Both ordinary and native
preview functions use this updated renderer. A nil factory result aborts renderer
initialization rather than masking it with a plain label. No timer, private tick
callback, custom protocol implementation, or guessed data-mode value was added.

ClockKitUI is linked directly from the installed runtime. The updated module
builds with warnings as errors, passes signature verification and diff whitespace
checks, and `otool -L` reports system install paths for both private frameworks.
No Apple binaries/headers were copied. The working SwiftUI app is untouched.

Pending runtime validation: restart the app before loading the rebuilt module;
verify the `assigned timeView=NTKDigitalTimeLabel` log, absence of the missing
view diagnostic, visible current time and PoC label, and clean dismissal. Observe
a minute boundary to check whether time advances under native management. Then
try explicit activation/deactivation separately. Font/layout, protocol acceptance,
clock advancement, snapshots and always-on behavior are not established by build
success. Framework debug time offsets and legibility styling from the complete
built-in renderer are intentionally not reproduced in this minimal experiment;
nondefault framework offset behavior remains untested.


## Time label result and LLDB expression correction — 2026-10-21

User output confirms native presentation with `assigned timeView=NTKDigitalTimeLabel`,
MYCustomFaceView bounds 208 x 248, and return YES. The prior missing-timeView
diagnostic is absent from the supplied output. Time advancement and explicit
activation remain unverified.

The attempted activation expression failed to compile because LLDB found
ambiguous BOOL typedefs; YES also expands through BOOL. Thus the activation helper
was not called, and the user correctly stopped before deactivation. Updated the
console instructions to `(int)MYSetNativeControllerExperimentActive(1)` and the
corresponding call with 0. These avoid explicit BOOL references and YES/NO macros
without changing the compiled function signature or bypassing ABI checks. This
is a debugger-expression issue, not evidence of native activation failure.

## First successful explicit native activation cycle — user-reported, 2026-10-21

Using the corrected LLDB expressions, the user reported:

```text
MYSetNativeControllerExperimentActive(1):
Native controller PoC: entering becomeActive
Native controller PoC: explicit activation request completed, active=1
return (int) 1
MYSetNativeControllerExperimentActive(0):
Native controller PoC: entering resignActive
Native controller PoC: explicit activation request completed, active=0
return (int) 1
MYDismissNativeControllerExperiment():
Native controller PoC: beginning dismissal
Native controller PoC: preview ownership released
```

This establishes completion of one explicit native activation/deactivation and
dismissal cycle in the app host. No failure appears in the supplied output.
Clock advancement across a minute boundary, repeated cycles, deallocation, and
always-on behavior were not separately reported and remain unverified.
The next implementation milestone is an app-local NTKFaceBundle and isolated
loader, with exact declarations verified before use. This does not authorize
system process injection or simulator runtime modification.

## App-local bundle milestone implementation — 2026-10-21

Re-read installed x86_64 metadata before adding minimal declarations. Both
NTKFaceBundle and NTKFaceBundleLoader inherit NSObject.

| Method | Encoding |
| --- | --- |
| `+[NTKFaceBundleLoader faceBundleLoaderWithDirectories:]` | `@24@0:8@16` |
| `-[NTKFaceBundleLoader initWithURLs:]` | `@24@0:8@16` |
| `-[NTKFaceBundleLoader loadFaceBundleWithIdentifier:]` | `@24@0:8@16` |
| `+[NTKFaceBundle identifier]` | `@16@0:8` |
| `-[NTKFaceBundle faceClass]` / `faceViewClass` | `#16@0:8` |
| `-[NTKFaceBundle defaultFaceForDevice:]` | `@24@0:8@16` |

The loader factory at 0x370ad allocates a fresh NTKFaceBundleLoader and forwards
the supplied collection to initWithURLs:. The manager's previously inspected
construction uses a set of NSURL directory objects, so the experiment uses the
same shape; collection types are not inferred from object encoding alone.
The identifier lookup's block at 0x379fa filters bundle identifiers/metadata,
loads matching NSBundles, extracts bundle classes, compares class identifiers,
and allocates/initializes the matching class at 0x37df9. Thus its return is a
bundle instance, not a Class; the helper declaration and runtime checks reflect
that evidence.

Added `Experiments/LocalFaceBundle` containing our own minimal BNDL Info.plist
and MYLocalFaceBundle subclass. The class implements faceClass, faceViewClass,
and defaultFaceForDevice: using the existing MYCustomFace/MYCustomFaceView and
already exercised style zero. It inherits +identifier to test actual NSBundle
identity rather than hardcoding that method. No gallery or restriction override
is invented. No LegacyStyles or AdditionalIdentifiers metadata is needed for this
single identifier-based test. Their absence is experimental until lookup runs.

The build script compiles the principal class into a separate simulator bundle
under its temporary FaceBundles directory. The bundle links to the existing
experiment dylib via its @rpath install name, with @loader_path/../.. locating
the dylib. It defines no duplicate MYCustomFace/MYCustomFaceView classes. All
Apple dependencies resolve from the installed SDK/runtime; none are embedded.

Added `MYDiscoverLocalFaceBundle(directoryPath)` to the experiment module. It
requires the WatchFaceLab main thread, validates the disk metadata without loading
the principal class, creates its own loader for only the explicit directory,
looks up the unique identifier, verifies the returned class and its NSBundle
path/identifier, then creates and checks a default face and renderer/timeView.
It does not invoke NTKFaceBundleManager, mutate global caches, present a window,
register a gallery face, or change runtime files. Normal NSBundle/dyld class
loading remains process-wide until app exit; no unloading is attempted.

Validation: both artifacts compile with warnings as errors and pass strict
signature verification; source plist lint and git diff whitespace checks pass.
The bundle binary targets WATCHOSSIMULATOR 26.5. Symbol inspection confirms the
principal class is defined only in the bundle, while face/view symbols are
imported from the module. Dependency inspection confirms the expected @rpath
module dependency and system NanoTimeKit install path.

Runtime discovery remains pending in the user's existing debugger. Instructions
are in `Docs/LLDB-EXPERIMENT.md`. Build/link success does not prove NSBundle lookup,
loader acceptance, identity, or default-face creation. The face model's own
bundleIdentifier remains unset by the style-zero initializer; this milestone
checks the bundle class/image identity, not face serialization or persistence.
No system registration experiment is performed by this helper.

## First successful cold app-local bundle discovery — user-reported, 2026-10-21

The user ran the discovery helper on the main thread after loading the module
into a fresh WatchFaceLab process. Supplied output:

```text
Local bundle PoC: metadata validated; alreadyLoaded=0; directory=/tmp/WatchFaceLab26-NTK/FaceBundles
Local bundle PoC: isolated loader created; looking up dev.develodom.WatchFaceLab.LocalFaceBundle
has no material, defaulting to light aluminum
Local bundle PoC: identity verified; creating default face
Custom Face PoC: assigned timeView=NTKDigitalTimeLabel
Local bundle PoC PASS: identifier=dev.develodom.WatchFaceLab.LocalFaceBundle bundle=MYLocalFaceBundle face=MYCustomFace renderer=MYCustomFaceView timeView=NTKDigitalTimeLabel
return (int) 1
```

This supersedes the pending runtime-discovery status above. The initial unloaded
state and successful identifier lookup establish cold discovery/load through the
isolated loader. Bundle-class/image identity checks, default-face creation, and
custom renderer/timeView creation all passed. The single-identifier metadata
without LegacyStyles/AdditionalIdentifiers worked for this tested path.

Not established: warm-repeat lookup, face-model bundleIdentifier, serialization,
gallery eligibility, global/shared-manager discovery, system face-library
persistence, or active system presentation. No system process or simulator
runtime file was changed. The next research gate is face-model identity and its
verified bundled-face creation/serialization path before proposing registration.

## Face-model identity and serialization implementation — 2026-10-21

New verified x86_64 metadata:

| Method / class | Evidence |
| --- | --- |
| `+[NTKFace bundledFaceWithIdentifier:forDevice:initCustomization:]` | `@40@0:8@16@24@?32` |
| `-[NTKFace bundleIdentifier]` | `@16@0:8` |
| `-[NTKFace faceStyle]` | `q16@0:8` |
| `-[NTKFace JSONObjectRepresentation]` | `@16@0:8` |
| `-[NTKFaceBundle(FaceGeneration) faceFromData:]` | `@24@0:8@16` |
| NTKFaceInstanceDescriptor superclass | NSObject |
| `initWithJSONRepresentation:resourceDirectory:` | `@32@0:8@16@24` |
| `+[NTKFaceInstanceDescriptor supportsSecureCoding]` | `B16@0:8` |

`nm -arch x86_64 -g` confirms exported NTKFaceBundleIdentifierKey and
NTKFaceBundleFaceTypeKey. The experiment imports those constants instead of
inventing JSON key strings or constructing a face schema manually.

Factory trace: the three-argument bundled factory at 0x11a436 derives an analytics
identifier and delegates to the four-argument variant at 0x11a4f8. That requests
style 0x2c (44) through defaultFaceOfStyle:forDevice:initCustomization:, then
copies bundleIdentifier into the model at offset 0x58 and analytics identifier
at 0x40. For style 44, defaultFaceOfStyle: (0x11a243) rejects the NTKFace base
class but allocates the supplied subclass directly. Other styles use style/class
resolution. It runs applyDefaultConfiguration, then the optional customization
block. No ivar writes, guessed setters, or class-resolution overrides are needed
in our implementation.

The global JSON decoder at 0x11ff6c resolves bundled identities through
NTKFaceBundleManager.sharedManager. It is unsuitable for our explicit-directory
experiment without further global integration, so it is not called.

Instead, `-[NTKFaceBundle(FaceGeneration) faceFromData:]` at 0x1527cb unarchives
NTKFaceInstanceDescriptor, reads faceJSONRepresentation, decodes those bytes as
JSON, obtains the receiving bundle's identifier and faceClass, and calls that
class's bundled-face factory. Its customization block at 0x152a85 constructs
NTKFaceConfiguration from the decoded dictionary, invokes the face JSON
customization hook, and applies configuration. The receiving bundle supplies the
class/identity, so this is not proof of arbitrary identifier lookup in the global
decoder. Resource-directory handling exists but is not exercised here.

NTKFaceInstanceDescriptor's initializer at 0x3d4fdd copies both supplied objects.
Its JSON payload is established as NSData by the faceFromData: consumer. The
resourceDirectory parameter is left as id in the minimal declaration and passed
nil; its concrete non-nil type/semantics are not assumed.

Added explicit `MYRoundTripLocalFaceBundle(directoryPath)`. It preserves the
existing discovery assertions, obtains the bundle via its own loader, invokes
the bundled factory on MYCustomFace with a nil customization block, and verifies
class, style 44, and model identifier. It calls JSONObjectRepresentation, validates
and encodes that output using public NSJSONSerialization, wraps it in the native
descriptor, and archives it with public secure NSKeyedArchiver. It calls the local
bundle's faceFromData:, checks restored class/style/identifier and full JSON
object equality, then creates/verifies MYCustomFaceView and a non-nil timeView.
The archive stays in memory. No fallback, shared-manager cache modification,
swizzling, file-library write, or registration is added. The original bundle
style-zero factory remains unchanged as a comparison path.

Both artifacts build with warnings as errors and passed strict signature checks;
export inspection confirms the helper and native descriptor/key dependencies.
Runtime execution remains pending in Xcode; instructions are in
Docs/LLDB-EXPERIMENT.md. New possible failure points include default configuration
for bundled style, analytics derivation for our identifier, secure descriptor
coding, configuration reconstruction and renderer behavior with style 44. Build
success establishes none of those runtime results. Even a pass covers only the
minimal configuration; edits/resources, global discovery, gallery eligibility,
face-library persistence and cross-process restoration remain unverified.

## Successful bundled identity and serialization round trip — user-reported, 2026-10-21

The user ran MYRoundTripLocalFaceBundle on the main thread after loading the
module into a fresh app process. Cold discovery passed again (alreadyLoaded=0).
The supplied subsequent output was:

```text
Local identity PoC: entering bundled-face factory on MYCustomFace
Local identity PoC: model class=MYCustomFace style=44 identifier=dev.develodom.WatchFaceLab.LocalFaceBundle
Local identity PoC: serialized faceType=bundle JSON bytes=162
Local identity PoC: entering bundle faceFromData:, archive bytes=503
Custom Face PoC: assigned timeView=NTKDigitalTimeLabel
Local identity PoC PASS: class=MYCustomFace style=44 identifier=dev.develodom.WatchFaceLab.LocalFaceBundle JSON equal=1 renderer=MYCustomFaceView
return (int) 1
```

This supersedes the pending runtime status for the minimal identity/serialization
test. The native bundled factory, generated faceType=bundle JSON, secure descriptor
archive, receiving-bundle reconstruction, full JSON equality, and restored custom
renderer/timeView creation all passed in this app process. Reported payload
sizes are observations, not stable format requirements.

This does not establish global decoder resolution, nondefault customization or
resources, native-controller presentation of the restored style-44 model,
cross-process restoration, gallery eligibility, or system face-library install.
All serialization was in memory; no system library or runtime files changed.
The next integration gate is native presentation/activation of the identified,
restored model, followed by read-only research into shared discovery and gallery
eligibility. Any eventual system-registration experiment still requires a concrete
change/rollback proposal before system-process or runtime changes.
