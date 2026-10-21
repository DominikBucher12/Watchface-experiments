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

## Supported app-to-system face route assessment — 2026-10-22

Apple's public ClockKit surface includes `CLKWatchFaceLibrary.addWatchFace(at:)`,
which imports a `.watchface` file from an app bundle or downloaded file. Apple's
watch-face guidance describes these as configurations of existing system faces,
including their styles, colors, images, and complications. This is a supported
way to share a configured face, but it does not provide an API for registering
an app-defined `NTKFace` subclass or renderer. Sources:

- [Watch faces HIG](https://developer.apple.com/design/human-interface-guidelines/watch-faces)
- [CLKWatchFaceLibrary](https://developer.apple.com/documentation/clockkit/clkwatchfacelibrary)
- [addWatchFace(at:completionHandler:)](https://developer.apple.com/documentation/clockkit/clkwatchfacelibrary/addwatchface%28at%3Acompletionhandler%3A%29)

The repository's Xcode project has one watchOS application target and no watch
extension or app-group configuration. Separately, the installed NanoTimeKit
daemon loader roots traced in `Docs/SYSTEM-PERSISTENCE.md` do not include an app
container or arbitrary shared directory. No supported app-managed installation
path was identified that makes a custom renderer discoverable in another
watchOS process. This is a bounded finding from the current public API/project/
runtime review, not a claim that no private mechanism exists.

ClockFace attachment was denied before the prepared session bridge loaded; see
`Docs/CLOCKFACE-BRIDGE.md`. Do not bypass the target's attach policy. Further
system-gallery research requires an Apple-authorized debug environment or a
public custom-face extension point. Persistent face-library mutations remain
unattempted.

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

## Restored-model native hosting integration — 2026-10-21

Refactored the already successful identity round-trip implementation to return its
checked restored MYCustomFace through MYRestoreLocalFaceBundle(directoryPath).
The existing boolean MYRoundTripLocalFaceBundle wrapper still runs those same
checks. No private method or declaration was added for this integration.

The native preview now has a common internal presentation function accepting a
MYCustomFace. The original style-based entry point still constructs its face and
uses that function. New explicit MYPresentRestoredLocalFaceExperiment(directoryPath)
rejects open previews, obtains the checked restored style-44 model, presents it
through the common function, and verifies that the retained model pointer is the
exact restored object. It logs style and identifier before native initialization.
Activation/deactivation/dismissal reuse the existing helpers; activation remains
an explicit later step. Restored-model initialization/appearance/lifecycle remain
pending user execution; no result is inferred from the earlier style-zero test.

Both module and bundle rebuild with warnings as errors; whitespace checks pass.
No runtime filesystem, shared manager, face-library storage or system process was
modified. Commands are in Docs/LLDB-EXPERIMENT.md.

### Further read-only gallery findings

- `+[NTKFace isRestrictedForDevice:]` at 0x12205c returns zero in the base class.
  MYCustomFace inherits this behavior; no restriction bypass override is needed.
  This is only one eligibility check, not a claim of gallery acceptance.
- `-[NTKFaceBundle galleryFacesForDevice:]` obtains gallery edit options and invokes
  defaultFaceForDevice: (selector reference at 0xbfadf), with additional pigment
  and edit-option handling. Our local bundle still returns the style-zero model
  from that method; the successful identified round trip called the bundled
  factory separately. Thus gallery-generated model identity is not yet established.
- `-[NTKFacesBundleArrayGalleryCollection initWithDevice:faceBundle:]` reads gallery
  title, description and row priorities and observes the bundle. Producing a face
  alone does not satisfy the full gallery collection/metadata path.

Next gate after restored hosting: verify and test a bundled defaultFaceForDevice:
implementation and gallery metadata/face generation using the isolated loader.
The shared manager still has no configured path to the local bundle. No proposal
to modify its caches, system search directories or running system processes is
part of this change.

## Restored identified model: complete native lifecycle — user-verified, 2026-10-21

The user supplied successful cold discovery, identity/JSON round-trip, and exact
restored-model hosting logs for style 44 and identifier
`dev.develodom.WatchFaceLab.LocalFaceBundle`. Native-controller bounds were
208 x 248. The supplied screenshot shows the central native digital time and
Custom Face PoC label on a dark background inside the app preview. A small clock
also appears at top right; its attribution to app/system chrome is an inference,
not an independently traced view identity.

The user subsequently ran explicit activation/deactivation and dismissal:

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

The user confirmed this works as expected, completing one user-verified native
presentation/activation/deactivation/dismissal cycle for the identified restored
model. This supersedes its pending runtime lifecycle status above. Deallocation,
repeated-cycle stability, time advancement across a minute boundary, always-on
behavior, gallery eligibility, global discovery and system installation remain
separate/unverified. Next milestone: isolated gallery face generation and metadata
using the local bundle; no system process/runtime changes are authorized by this
successful app-host result.

## Isolated gallery contract implementation — 2026-10-21

Verified installed 23T570 x86_64 method encodings before adding declarations:

| Method | Encoding |
| --- | --- |
| `galleryFacesForDevice:` | `@24@0:8@16` |
| `galleryTitleForDevice:` | `@24@0:8@16` |
| `galleryDescriptionForDevice:` | `@24@0:8@16` |
| `galleryRowPrioritiesForDevice:` | `@24@0:8@16` |
| `+[NTKFace isRestrictedForDevice:]` | `B24@0:8@16` |

Disassembly shows base galleryFacesForDevice: at 0xbfa7d requests gallery edit
options and a default face, then enumerates pigment/edit variants. Base
galleryEditOptionsForDevice: at 0xbfd8f returns nil. For this variant-free PoC,
MYLocalFaceBundle explicitly implements the verified galleryFacesForDevice:
selector to return one default face (or an empty array on failure). This avoids
assuming the base implementation produces an entry without edit options.

The bundle's defaultFaceForDevice: now uses the already verified bundled factory
with its actual class-derived identifier; it no longer produces the unidentified
style-zero comparison face. This supersedes earlier notes preserving the bundle's
style-zero default. The independent style-based preview remains available and
unchanged. Added concrete galleryTitleForDevice: and galleryDescriptionForDevice:
methods. Row priorities remain inherited: the base method at 0xbfa75 returns nil;
its concrete non-nil schema is not guessed (minimal declaration returns id).
No device-restriction override is added: the inherited implementation returns NO.

Added MYInspectLocalFaceGallery(directoryPath). It reuses discovery/class-image
identity assertions, obtains the bundle through another explicit-directory loader,
checks inherited restriction status and nonempty metadata, and requests gallery
faces. It requires the single returned face to be MYCustomFace, style 44, with
the correct model identifier and valid native JSON, then verifies custom renderer
and timeView creation. It does not create a collection or gallery UI, alter global
lookup caches, or write system library/runtime files. A pass will establish the
local bundle's supplied gallery contract only; it cannot establish global gallery
visibility or native collection eligibility by testing our overrides alone.

Validation: module and bundle build with warnings as errors; both strict signature
checks and diff whitespace checks pass. Runtime execution of the updated bundle
default and gallery contract is pending. Commands are in Docs/LLDB-EXPERIMENT.md.

## Successful isolated gallery contract — user-reported, 2026-10-21

The user ran MYInspectLocalFaceGallery on the main thread in a fresh app process.
Cold discovery succeeded with alreadyLoaded=0. The updated identified default-face
factory created MYCustomFaceView with NTKDigitalTimeLabel. Subsequent output:

```text
Local gallery PoC: inherited device restriction=0
Local gallery PoC: title=Custom Face PoC description=Minimal custom digital face for the isolated WatchFaceLab experiment. rowPriorities=(null)
Local gallery PoC: requesting gallery faces
Custom Face PoC: assigned timeView=NTKDigitalTimeLabel
Local gallery PoC PASS: faces=1 title=Custom Face PoC class=MYCustomFace style=44 identifier=dev.develodom.WatchFaceLab.LocalFaceBundle renderer=MYCustomFaceView
return (int) 1
```

This supersedes pending execution status for the local gallery method test.
The inherited restriction result, provided metadata, single identified gallery
model, valid JSON assertions, and renderer/timeView creation all passed. Nil row
priorities were observed and are not assumed to prove native collection acceptance.
No native gallery collection/UI, shared discovery, system gallery entry or library
installation was exercised. Next gate: a native gallery collection consuming the
explicit local bundle, with its initialization/loading/accessor signatures verified
before implementation. Runtime/system-process modifications remain outside scope.

## Native gallery collection consumer implementation — 2026-10-21

Verified superclass chain from installed x86_64 metadata:
NTKFacesBundleArrayGalleryCollection -> NTKFacesArrayGalleryCollection ->
NTKGalleryCollection -> NSObject. Minimal declarations preserve the actual chain.

Verified methods:

| Method | Encoding |
| --- | --- |
| `initWithDevice:faceBundle:` | `@32@0:8@16@24` |
| `loadFaces` | `v16@0:8` |
| `numberOfFaces` | `Q16@0:8` |
| `faceAtIndex:` | `@24@0:8Q16` |
| `title` / `descriptionText` | `@16@0:8` |

Initializer at 0x320438 retains the device/bundle, consumes title, description and
row priorities, then adds itself as a bundle observer. It does not load faces.
`loadFaces` at 0x3205f5 dispatches a block to
NTKFacesArrayGalleryCollectionLoadQueue. Its block at 0x320826 requests the
bundle's gallery faces, has a conditional widget-migration path, and publishes
results asynchronously. The inherited numberOfFaces (0x2aa3d) reads the stored
array count, and faceAtIndex: (0x2aa5a) accesses that array. `setFaces:` notifies
a delegate via the selector spelled galleryCollectionDidChange:shouldUpdateSnaphots:.
No delegate callback is implemented or called by the experiment.
The collection's dealloc at 0x3205a9 removes itself as bundle observer.

Added staged helpers: MYStartNativeGalleryCollection(directoryPath) first checks
the existing local gallery contract, then passes the explicit local bundle to
a real NTKFacesBundleArrayGalleryCollection. It verifies native metadata getters,
retains the collection, and calls loadFaces. A YES start result means scheduling
only. The app must resume before MYCheckNativeGalleryCollection queries the
stored count/index, checks class/style/identity/JSON, and constructs a renderer.
Zero is logged as ambiguous pending/empty/failed; it is not automatically retried
or treated as success. MYReleaseNativeGalleryCollection releases experiment
ownership without trying to cancel unknown internal work or prove deallocation.

Both artifacts build with warnings as errors, pass strict signature verification,
and pass whitespace checks. Native asynchronous collection consumption remains
pending user execution. This test bypasses global discovery by explicitly supplying
the local bundle, but does not replace its face array or call setFaces: itself.
There is no global gallery insertion, system library write, runtime change,
swizzling or system process attachment. Full gallery UI and system registration
remain unverified even if this native consumer test succeeds.

## Native gallery consumer: partial success with crash — user-reported, 2026-10-21

Cold discovery/local gallery checks passed. Native collection initialization
accepted metadata and loadFaces was scheduled, but the initial LLDB expression
then reported:

```text
Native gallery PoC STARTED: resume the app before checking; this is not a load-success result
error: Expression execution was interrupted: EXC_BAD_ACCESS (code=EXC_I386_GPFLT).
The process has been returned to the state before expression evaluation.
```

After the user continued the process, MYCheckNativeGalleryCollection reported
NTKFacesBundleArrayGalleryCollection, title Custom Face PoC, faces=1, and emitted
its PASS log with MYCustomFace, style 44, correct identifier, MYCustomFaceView and
an assigned native timeView. Collection ownership release was subsequently logged.

This establishes that native asynchronous loading populated the collection in
that run, but does NOT establish a clean start/load/lifecycle result. LLDB's
expression-state restoration does not roll back arbitrary Objective-C side
effects or asynchronous work. The PASS checks therefore coexist with the crash;
they must not be used to dismiss it. No backtrace, faulting instruction, or
faulting-thread identity was supplied. Cause remains unknown; attributing it to
LLDB, threading, object lifetime, or a particular private method would be speculation.

Next diagnostic: reproduce the start in a fresh app process and capture thread
list, all-thread backtrace, current frame and faulting instruction immediately at
the EXC_BAD_ACCESS, before continuing or evaluating more expressions. Stop adding
consumer/registration integrations until the failure is understood. No speculative
API overrides or threading workaround has been added.

## Fault capture refinement — 2026-10-21

User's next backtrace capture (PID 8870) shows thread 1 stopped by SIGSTOP in
mach_msg2_trap, with CoreFoundation/UIApplication/SwiftUI run-loop frames. Other
threads are idle worker/event-fetch threads. This capture does not contain an
EXC_BAD_ACCESS stop or identify its faulting instruction. It cannot establish the
cause of the prior native-collection expression interruption.

Checked `xcrun lldb --batch -o 'help expression'` locally. The installed debugger
supports `-u <boolean>` / `--unwind-on-error`, documented as cleaning up program
state when an expression crashes or raises a signal. Revised reproduction uses
`expr -l objc++ -u false -- (int)MYStartNativeGalleryCollection(...)` in a fresh
process to preserve the fault location. No implementation change or speculative
fix has been made. Capture the selected fault thread before continuing or forcing
thread 1. The earlier simple post-error capture instructions did not account for
LLDB's automatic expression unwinding.

## First clean native gallery collection cycle — user-reported, 2026-10-21

In PID 9009, after confirming the module symbol was loaded, the user invoked
MYStartNativeGalleryCollection with LLDB -u false. Cold discovery/local gallery
checks passed, native initialization accepted metadata, loadFaces was scheduled,
and the expression returned (int) 1 without an exception. After resuming and
pausing the app, the native check reported:

```text
Native gallery PoC: collection=NTKFacesBundleArrayGalleryCollection title=Custom Face PoC faces=1
Custom Face PoC: assigned timeView=NTKDigitalTimeLabel
Native gallery PoC PASS: native collection faces=1 class=MYCustomFace style=44 identifier=dev.develodom.WatchFaceLab.LocalFaceBundle renderer=MYCustomFaceView
return (int) 1
```

Collection ownership release and process resume then completed without a reported
fault. This establishes one clean explicit-local-bundle native collection
start/load/check/release cycle. It does not establish deallocation or repeated-run
stability. The earlier EXC_BAD_ACCESS did not reproduce in this run and remains
unexplained; changing the LLDB unwind option is not evidence of a fix or cause.

Established milestones now include local cold discovery, identified default and
gallery models, native JSON/descriptor reconstruction, restored model presentation
and activation, and native asynchronous gallery collection consumption. None
establish shared-manager discovery, system gallery visibility or system library
installation. Next research should map global gallery discovery and integration
constraints read-only, then prepare exact changes/rollback for a separately
approved system experiment. No system mutation follows automatically from this pass.

## Local PoC complete; system integration plan — 2026-10-21

The user requested progress and a finite account of remaining checks. No additional
local PoC variants are required before integration planning. There are two next
system gates: session shared-discovery/gallery integration, then separately designed
persistent library/selection/restoration integration.

Read-only tracing connected NTKGalleryCollection.galleryCollectionsForDevice: to
shared-manager enumeration and native bundle collection construction, with title
and internal-only checks. Base _isInternalOnlyForDevice: returns NO. Confirmed
loader _urls NSSet and manager readonly loader property in installed metadata.
Important rollback finding: manager _resetCaches clears the cached enumeration
array, not both progressive identifier/style dictionaries. Persistence uses an
XPC-backed collection rather than merely an in-process array.

Concrete scope, candidate loader-getter bridge, staged ClockFace preflight,
rollback limits and the original authorization boundary are documented in
Docs/INTEGRATION-PROPOSAL.md. This is a proposal, not a ready executable bridge;
no system process was attached or changed. No application implementation changed
in this research pass. The next engineering work is preparing the opt-in bridge
and verified rollback, followed by specific approval before system execution.

## ClockFace bridge prepared; system execution pending — 2026-10-21

Prepared Experiments/MYClockFaceBridge.m and a separately built signed dylib.
The implementation improves on the loader replacement proposal by changing only
the shared-manager instance's class to a no-ivar subclass, supplementing bundle
enumeration and exact-identifier lookup while forwarding all native requests.
It does not edit the original loader, search paths or manager cache dictionaries.

Reverified encodings: enumeration v36@0:8@16B24@?28; identifier/device/migration
lookup @36@0:8@16@24B32; loader getter/shared-manager getter @16@0:8. Traced loader
class enumeration block to allocation of bundle instances at 0x388cd, confirming
that manager enumeration callbacks receive instances, not Class values.

The bridge validates simulator architecture, exact loaded NTK UUID, main thread,
ClockFace identifier, original manager class, method encodings, bundle identity
and path. Install/remove are explicit and reject unexpected runtime class state.
No constructor runs. Removing restores the original manager class; loaded images
and in-flight callbacks can outlive bridge removal, so process restart is the
fallback for uncertain state. Existing gallery objects are not automatically
retracted or refreshed. The check proves shared enumeration/identifier resolution
only, not visible system gallery or persistent installation.

Module/local bundle/bridge build with warnings as errors. Strict bridge signature
verification, platform inspection, export inspection and whitespace checks passed.
The bridge has NOT been loaded or run in ClockFace; no system attach or mutation
was performed. Reviewable intervention, commands, limits and rollback are in
Docs/CLOCKFACE-BRIDGE.md. Specific execution approval is still required under the
user's original system-process boundary.

## Approved ClockFace attach attempt blocked by hardened target policy

The user explicitly approved the prepared preflight/install/check/remove cycle.
Rechecked the bridge's strict signature and identified the booted simulator
ClockFace process as PID 5460 (com.apple.clockface); Carousel was PID 5271 and
was not targeted. Attempted `xcrun lldb -p 5460` outside the workspace sandbox.
LLDB rejected attachment with `Not allowed to attach to process`. The redundant
LLDB session was closed. No process load, preflight, install, check, or remove
function ran; no ClockFace manager class or runtime file changed.

Read-only host logs confirm the cause. Kernel/AppleMobileFileIntegrity at
2026-10-21 23:58:47 UTC reported:

```text
macOSTaskPolicy: (com.apple.debugserver) may not get the task control port of (ClockFace) (pid: 5460): (ClockFace) is hardened, (ClockFace) doesn't have get-task-allow, (com.apple.debugserver) is a declared debugger(com.apple.debugserver) is not a declared read-only debugger
```

Debugserver logs independently show task_for_pid(5460) returning kernel failure
0x5. A later generic debugserver line said `Attach succeeded, ready to debug`,
but its task-port failures, shutdown, kernel policy records and LLDB's explicit
attach failure establish that no usable attachment occurred.

A read-only codesign entitlement display on the installed ClockFace binary warned
of an invalid entitlements blob and printed no usable entitlement dictionary.
That output alone is not treated as a complete entitlement inventory. The kernel
policy message is the direct evidence for hardened state and missing
get-task-allow at the denied attachment.

This is an environment access blocker, not a failure of the bridge implementation
or the completed local PoC. No sudo-based retry, entitlement alteration,
re-signing, security-policy change, alternate system target injection, or runtime
patch was attempted. Those actions were excluded by the approved execution plan.
Further system execution requires a separately reviewed approach to obtaining a
debuggable research host/target; more local renderer checks will not resolve this
attach-policy denial. The prepared bridge remains unexecuted in ClockFace.

## Debuggable research-target strategy — 2026-10-22

User requested a strategy/milestone and practical debugging-security guidance.
Added Docs/DEBUGGABLE-TARGET.md, Docs/MILESTONES.md and the preparation-only script
Experiments/prepare-debug-target.py. Prepared a separate current-runtime ClockFace
copy at /tmp/WatchFaceLab26-DebugTarget/ClockFaceResearch.app with unique identifier
dev.develodom.WatchFaceLab.ClockFaceResearch. The script removes copied advertised
system service names and hidden-app tags and supplies only debugging/library-
validation exceptions, not private Apple service entitlements. It signs the copy
ad hoc with hardened runtime. No original system executable is re-signed.

Strict signature verification succeeded. Signed entitlements display confirms
com.apple.security.get-task-allow, get-task-allow and
com.apple.security.cs.disable-library-validation are true. Original runtime
executable/plist hashes were unchanged. No simulator install, launch or attach of
this copy was performed. Those are the next disposable-device gates, not claimed
results. Current ClockFace bridge intentionally rejects the copy's identifier;
explicit research-host adaptation is deferred until target viability is known.

Official Apple debugging entitlement/hardened-runtime documentation was consulted
and linked in the strategy document. It supports the development signing approach
but does not guarantee watchOS simulator ClockFace can run as a separately signed
app. Loss of platform/private-service identity, hardcoded service access and early
launch failure remain real unknowns. No SIP/AMFI changes, sudo-based policy bypass,
runtime remount, original-app re-signing or Carousel injection was attempted.

## Disposable research target installed and debugged — 2026-10-22

Created/booted WatchFaceLab26 Research, UDID
E8757D97-8E48-479E-AD1C-9D8ADC8F5E5D (Series 11 46mm / watchOS 26.5).
The existing simulator and original system ClockFace were not changed.

Observed/fixed only in the prepared copy and reproducible preparation script:

1. Installer required WKApplication or WKWatchKitApp=true. Added WKApplication
   and WKWatchOnly, matching the owned standalone app packaging.
2. simctl's advertised --arch flag was rejected as an invalid device. Used
   --wait-for-debugger without it; LLDB verified x86_64 architecture.
3. First launch died with AMFI restricted-entitlement error -424. Removing the
   unprefixed get-task-allow key while retaining macOS debug exceptions allowed
   launch. This is an empirical narrowing, not a general entitlement policy claim.
4. Hardened-copy PID 10115 attached successfully, then trapped in dyld image
   notification. Kernel logs and its crash report confirmed a code-signing invalid
   debugger-modified dyld page (code 50). Terminated only this research copy.
5. Re-signed the copy with --options 0 (non-hardened); installed and launched PID
   10139. LLDB attached and reached UIApplicationMain. The script now uses that
   signing mode with only macOS get-task-allow/library-validation exceptions.

Full app initialization subsequently trapped in NanoTimeKit. Reproduced under
LLDB in research-copy PID 10178: EXC_BAD_INSTRUCTION at
ComplicationServicesServer.init(device:) + 525, unslid 0x3ec00d, ud2. Stack contains
NTKClockViewController initWithStatusViewControllerClass: +2457 and ClockFace scene
setup. Installed disassembly shows a call to NTKSharedRemoteComplicationProvider
at 0x3ebe60, a nil test and conditional jump to that trap. The provider calls
NTKRemoteComplicationManager.sharedInstance. Its nil cause remains unverified;
no assumption is made that merely adding a particular entitlement fixes it.

The debugger/target-access gate is passed for the separate copy; full system-like
scene startup is not. No bridge hooks ran, no private privilege was invented, no
trap patched, and no system process/runtime binary was modified. Original binary
and plist SHA-256 values were rechecked unchanged. The disposable simulator and
installed copy remain available for further research; launch/crash PIDs are
historical and must not be reused blindly. Preparation.json and Simulator.json
under the temporary output record current artifact and device state.

Updated DEBUGGABLE-TARGET.md with the actual working launch/signing recipe and
native service blocker, superseding its earlier untested three-entitlement,
hardened-copy recipe. Next independent question: remote-complication manager
initialization in a renamed host, or use an owned native host for shared-manager
bridge integration without full ClockFace server initialization.


### Renamed-host startup boundary traced — 2026-10-22

Read-only analysis of the installed watchOS 26.5 x86_64 binaries establishes:

- NanoTimeKit `___46+[NTKRemoteComplicationManager sharedInstance]_block_invoke`
  at 0x1fb169 first calls NTKIsUnitTests. If false, it calls
  CLKRunningInProcess with mask 0x38 at 0x1fb17b. If false, it returns without
  constructing the singleton (0x1fb182 -> 0x1fb1a5). dispatch_once means this
  decision is cached for that process. Allocation happens at 0x1fb184.
- ClockKit CLKRunningInProcess at 0x484fc interprets 0x38 as the union of
  Carousel (0x08), ClockFace (0x10), and NanoSettings (0x20).
- ClockKit ___CLKIsClockFaceApp_block_invoke at 0x47c18 sends mainBundle,
  bundleIdentifier, and isEqualToString: with `com.apple.clockface`.
  Selector references are at 0xc5ed0, 0xc5ed8, 0xc5e28; the CFString object
  is at 0xb24a0. The corresponding blocks compare `com.apple.Carousel` and
  `com.apple.NanoSettings`. Resolved the Mach-O selector/CFString pointers
  directly because otool's annotated output mislabels these references.

Together with the captured nil-provider trap, this explains why the uniquely
renamed ClockFace copy cannot follow this normal initialization path. This is
an identity gate, not evidence of a missing service entitlement. No runtime
predicate values were forced, no singleton or once token was overwritten, and
no unit-test mode was enabled. Other startup/service dependencies remain unknown.

Strategy decision: retain the attachable copied target for debugging evidence;
use an owned host to investigate shared-manager discovery without initializing
NTKClockViewController/ComplicationServicesServer. Next milestone has three
acceptance checks: explicitly install a host-scoped in-memory discovery bridge;
consume the custom bundle through the native shared manager/gallery path; remove
it and verify the original manager class and lookup behavior return. Keep the
system-only bridge guard intact and expose any owned-host experiment separately.
This demonstrates in-process integration only. System gallery visibility and
cross-process persistence remain separate, unpassed gates.


### Owned shared discovery experiment prepared — 2026-10-22

Added MYOwnedDiscovery.m as a separate compile-time host-scoped build of the
existing bridge, with distinct exports and subclass name. The default system
bridge retains its exact com.apple.clockface guard. The owned variant accepts
only dev.develodom.WatchFaceLab, the inspected x86_64 runtime UUID, main thread,
and verified manager method encodings. No application target/entry point changed.

Start captures the native shared-manager enumeration with the custom identifier
absent, installs one instance subclass, checks original entries plus exactly one
custom entry, and creates NTKFacesBundleArrayGalleryCollection from the shared
manager's custom lookup. Check validates its asynchronously loaded model,
identifier/style/JSON, renderer and native time view. Remove restores the class
and compares enumeration and absent custom lookup with baseline; it separately
reports whether consumption passed. Failures after install require cleanup or
process restart. No runtime success has yet been observed for this new variant.

Rechecked sharedManager's installed disassembly: its once-block at 0x16564c
allocates and calls _init directly; unlike the remote-complication singleton,
this immediate path has no CLKRunningInProcess gate. That does not establish
that all downstream manager initialization/services work in the owned host.
Potential blockers include those dependencies, async gallery timing, concurrent
native manager use while changing the instance class, and the earlier unresolved
LLDB expression fault. Enumeration can also change independently of this hook;
a removal snapshot mismatch must not be misreported as proven failed class
restoration. No full ClockFace server/controller startup is requested here.

Validation: all four experiment artifacts built with -Wall -Wextra -Werror;
nm confirms the three owned experiment entry points. Runtime acceptance remains
pending the explicit cycle in Docs/OWNED-DISCOVERY.md. Loaded runtime classes and
in-flight native work survive cleanup until process exit; do not unload dylibs.


## User-verified result — PID 10520

The reported LLDB cycle returned 1 from start, check, and removal. Native baseline
contained 58 bundles. The hook reported exactly one custom identifier and matching
lookup; the native gallery produced the identified custom model, renderer and
NTKDigitalTimeLabel. Removal reported original manager class restored and
`class/enumeration/absent-lookup restored=1; consumptionPassed=1; fullCyclePassed=1`.
The app resumed. This passes the owned-process milestone, not system visibility.

During native discovery, the framework logged missing ExtractedBundles/23T570
and AppleInternal paths, skipped NTKCharacterFaceBundle for missing NSPrincipalClass,
and reported a duplicate NTKTimeFontTypographicBounds class in Apple's Parmesan
and Warlock bundles. It also emitted a BigNumeralsDigital wrong-initializer warning.
These did not prevent this cycle's acceptance checks. Their broader effects are
unknown; do not delete/rename Apple classes or create missing system paths merely
to silence them. No crash was reported in this cycle, which does not resolve the
earlier intermittent expression fault.

Next research scope: read-only mapping of system-host discovery inputs and
selection/persistence consumers. Owned-manager interception is process-local;
this evidence does not establish cross-process discovery, registration, system
face selection or durable installation. Original ClockFace attach denial and the
renamed host's identity gate remain separate barriers. Do not repeat local PoCs
as a substitute for establishing that boundary.


### Persistent library path mapped statically — 2026-10-22

The installed NanoTimeKit client creates NTKPersistentFaceCollection with
collection identifier `LibraryFaces`. It connects to `com.apple.nanotimekit.collectionserver`,
configures NTKCollectionServer/NTKCollectionClient XPC interfaces, resumes and
registers. The watchOS 26.5 simulator launchd plist
`System/Library/LaunchDaemons/com.apple.nanotimekitd.plist` declares that Mach
service in nanotimekitd. Client full-load IPC transfers ordered UUIDs, selected
UUID and instance descriptors; callbacks reconstruct NTKFace instances. Add
(descriptor+UUID, update type 1), selection (UUID, update type 5), remove, order,
and configuration/resource changes are separate queued XPC mutations with
sequence IDs. The AddableFaces collection is separate staging/preferences state.
Details and evidence addresses are in SYSTEM-PERSISTENCE.md.

This identifies the daemon as owner of authoritative library state but does not
establish its authorization rules, persistence format, class/image loading in all
clients, or acceptance criteria. No XPC mutation was sent. A normal ClockFace
registration/load observation on the disposable simulator and daemon-side static
analysis remain the next read-only checks. Cross-process custom restoration is
not established.
