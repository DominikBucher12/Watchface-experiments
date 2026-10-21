# WatchFaceLab app-only runtime experiment

Rebuild before loading (Terminal, repository root):

```sh
bash Experiments/build-simulator.sh
```

If an earlier version of the dylib was loaded into this app process, restart the
app before loading the new version. Objective-C classes cannot reliably be
replaced by unloading/reloading the module.

Bring WatchFaceLab to the foreground on the watch simulator. In Xcode pause the
running app and open the debugger console. Use the existing Xcode session: a
second debugger cannot attach while Xcode owns the process.

Run each step separately. Stop on an error and capture the console output.

1. Select and verify the main thread:

```lldb
thread select 1
expr -l objc++ -- (BOOL)[NSThread isMainThread]
```

The result must be YES (or true). If it is not, select the thread shown with
`com.apple.main-thread` in `thread list` and verify again.

2. Load the module:

```lldb
process load /tmp/WatchFaceLab26-NTK/MYCustomFaceExperiment.dylib
image lookup -n MYPresentCustomFaceExperiment
```

Expect a successful image token and a symbol match in MYCustomFaceExperiment.
Do not call the preview if loading failed. Preserve any dyld error verbatim.

3. Inspect the verified device mechanism:

```lldb
expr -l objc++ -- id $myCLKDevice = (id)[NSClassFromString(@"CLKDevice") currentDevice]
po $myCLKDevice
```

The result must be non-nil. This checks device retrieval before face allocation.
If LLDB lacks a method declaration, use the encoding-independent object-return
cast for this verified zero-argument class selector:

```lldb
expr -l objc++ -- id $myCLKDevice = ((id (*)(id, SEL))objc_msgSend)((id)NSClassFromString(@"CLKDevice"), NSSelectorFromString(@"currentDevice"))
po $myCLKDevice
```

Use the alternative only if the first declaration failed; do not redeclare a
successfully created persistent variable.

4. Preview the custom renderer:

```lldb
expr -l objc++ -- (BOOL)MYPresentCustomFaceExperiment((long)0)
continue
```

Style 0 is verified as `utility` in the installed binary's description table.
It is a test input, not a proven safe or newly allocated custom style. The helper
checks the app bundle identifier and requires an active UIWindowScene. On success
it retains the face and preview window and logs the renderer class and bounds.
The expected image is a dark background with `Custom Face PoC`.

If the call returns NO, read the log before continuing. If it throws or crashes,
capture `bt` and the console error and do not repeatedly retry. For an Objective-C
exception, an Xcode Exception Breakpoint can capture the throw site; do not
continue through an unknown failure just to display the label.

5. To remove the preview, pause again, select the main thread, then:

```lldb
expr -l objc++ -- (void)MYDismissCustomFaceExperiment()
continue
```

The window is hidden and its renderer/face ownership is released. The module
remains loaded until app termination. Restarting the app also removes the preview.
No original app view hierarchy is replaced and no face is registered with the OS.

## Native NTKFaceViewController preview

This is a separate path from the successful ordinary UIViewController preview.
It has been compiled and signed; native initialization, appearance, and teardown
have not yet been executed. The native controller eagerly loads and configures
its renderer during initialization, so an exception may occur before presentation.
Do not add guessed face overrides if that happens; capture the failure first.

The updated module contains additional functions. **Restart WatchFaceLab from
Xcode before loading it** if the previous dylib is already loaded. An existing
Objective-C class implementation cannot be safely replaced by loading another
copy of the library. The original app sources/target are unchanged.

With the fresh app in the foreground, pause and run each command individually:

```lldb
thread select 1
expr -l objc++ -- (BOOL)[NSThread isMainThread]
process load /tmp/WatchFaceLab26-NTK/MYCustomFaceExperiment.dylib
image lookup -n MYPresentNativeControllerExperiment
expr -l objc++ -- (BOOL)MYPresentNativeControllerExperiment((long)0)
```

The main-thread check must be YES and module loading must succeed before calling
the helper. If it returns YES, run `continue` and check for the dark background
and label. Expect a log identifying `controller=NTKFaceViewController` and
`renderer=MYCustomFaceView` with nonzero bounds. Capture all stage logs. A nil
return/NO or exception is a research result, not permission to bypass the failure.
If stopped on an exception or crash, capture `bt` and the console output.

Before requesting activation, test teardown. Pause on the main thread:

```lldb
expr -l objc++ -- (void)MYDismissNativeControllerExperiment()
continue
```

Confirm the original clock returns. The helper hides its window, releases its
controller/face ownership, and restores the previous key window if it still
exists. Ownership release does not by itself prove deallocation or absence of
framework-retained objects. The ordinary and native preview windows are mutually
exclusive; a helper returns NO if the other preview remains open.

Only after successful native presentation and teardown, present it again and
check explicit activation in separate main-thread debugger calls:

```lldb
expr -l objc++ -- (BOOL)MYPresentNativeControllerExperiment((long)0)
expr -l objc++ -- (int)MYSetNativeControllerExperimentActive(1)
continue
```

After observing the preview, pause on the main thread:

```lldb
expr -l objc++ -- (int)MYSetNativeControllerExperimentActive(0)
expr -l objc++ -- (void)MYDismissNativeControllerExperiment()
continue
```

The helper tracks only explicit successful activation calls; it does not assert
that internal UIKit/NTK appearance callbacks cannot affect activation state. No
data-mode integer, tick callback, or always-on configuration is assumed. Test
three successful cycles and a fresh app restart before considering this lifecycle
path established. This remains an in-app experiment with no bundle discovery,
gallery, library, or system registration changes.

## Native digital time label revision

The rebuilt renderer now uses NTKDigitalTimeLabel as its timeView. Restart the
app before loading this revision, then repeat the native presentation sequence
above. Expected additional log:

```text
Custom Face PoC: assigned timeView=NTKDigitalTimeLabel
```

Check that the missing-timeView diagnostic disappears and the preview shows a
white time display with `Custom Face PoC` below it. Let the app run across a
minute boundary and report whether the time changes. No custom timer was added.
First verify dismissal again. Then use the separate activation/deactivation
commands above and preserve any new diagnostics. A visible frozen time, empty
time view, clipping, or remaining Tritium diagnostic should be reported rather
than treated as a completed time-view milestone.


If LLDB reports an ambiguous BOOL typedef, avoid BOOL casts and YES/NO macros in
console expressions. The activation commands above use integer literals and cast
the result to int (1 means success). This changes only the debugger expression;
the exported function retains its compiled BOOL signature. An expression compile
error does not invoke the function or change activation state.

## App-local face bundle discovery

The build script now also creates:

```text
/tmp/WatchFaceLab26-NTK/FaceBundles/MYLocalFaceBundle.bundle
```

It contains our own executable/plist, with identifier
`dev.develodom.WatchFaceLab.LocalFaceBundle` and principal class MYLocalFaceBundle.
It depends on the experiment dylib; both artifacts must remain in their generated
relative locations. No Apple framework is embedded.

Restart WatchFaceLab in Xcode to clear prior loaded experiment classes. Bring the
app forward, pause, and run individually:

```lldb
thread select 1
expr -l objc++ -- (int)[NSThread isMainThread]
process load /tmp/WatchFaceLab26-NTK/MYCustomFaceExperiment.dylib
expr -l objc++ -- (int)MYDiscoverLocalFaceBundle(@"/tmp/WatchFaceLab26-NTK/FaceBundles")
```

The thread check must return 1 and loading must succeed before calling discovery.
Do **not** manually load the .bundle executable first. The point of this test is
for NTKFaceBundleLoader to discover and load it from its metadata.

Expected first-call stages:

```text
Local bundle PoC: metadata validated; alreadyLoaded=0; directory=...
Local bundle PoC: isolated loader created; looking up dev.develodom.WatchFaceLab.LocalFaceBundle
Local bundle PoC: identity verified; creating default face
Custom Face PoC: assigned timeView=NTKDigitalTimeLabel
Local bundle PoC PASS: identifier=dev.develodom.WatchFaceLab.LocalFaceBundle bundle=MYLocalFaceBundle face=MYCustomFace renderer=MYCustomFaceView timeView=NTKDigitalTimeLabel
```

A return value of 1 means all checks passed. Paste the entire output, including
any extra framework diagnostics. If it fails, preserve the error/stage logs; for
an exception, capture `bt`. No automatic fallback directly loads the bundle.

This test creates a renderer without displaying it. The original SwiftUI app
should remain visible after `continue`. Local loader/face/view ownership is
released on return, while the loaded Objective-C image persists until app exit.
A second call in the same process may report alreadyLoaded=1 and can test warm
lookup; only an app restart establishes a fresh-load repeat. No unloading or
filesystem cleanup is needed for normal use.

A pass proves explicit-directory lookup, principal-class discovery, identity,
and default-face/renderer creation. It does not establish gallery/device
eligibility, model serialization, shared-manager discovery, or system install.
The face still uses the existing style-zero initializer, which does not populate
its bundleIdentifier. The identity check here concerns the bundle class/image,
not persistent face-model identity. That is a separate research gate.

## Face-model identity and in-memory serialization round trip

Restart WatchFaceLab before loading this rebuilt module/bundle. In the foreground
app, pause and run individually:

```lldb
thread select 1
expr -l objc++ -- (int)[NSThread isMainThread]
process load /tmp/WatchFaceLab26-NTK/MYCustomFaceExperiment.dylib
expr -l objc++ -- (int)MYRoundTripLocalFaceBundle(@"/tmp/WatchFaceLab26-NTK/FaceBundles")
```

The main-thread check must return 1 and module loading must succeed. This helper
first runs the existing discovery assertions; expect its earlier PASS output.
It then creates an identified bundled face (style 44, verified from the factory
implementation), serializes the framework-generated JSON into an in-memory
securely archived NTKFaceInstanceDescriptor, and calls the local bundle's
`faceFromData:`. Nothing is written to the system face library or to disk.

Expected subsequent stages:

```text
Local identity PoC: entering bundled-face factory on MYCustomFace
Local identity PoC: model class=MYCustomFace style=44 identifier=dev.develodom.WatchFaceLab.LocalFaceBundle
Local identity PoC: serialized faceType=... JSON bytes=...
Local identity PoC: entering bundle faceFromData:, archive bytes=...
Local identity PoC PASS: class=MYCustomFace style=44 identifier=dev.develodom.WatchFaceLab.LocalFaceBundle JSON equal=1 renderer=MYCustomFaceView
```

A final return value of 1 means all checks passed. Do not assume a particular
serialized faceType string or JSON/archive byte count; those come from the
installed framework. On NO, an exception, or a crash, preserve stage logs and
`bt` before retrying. A JSON mismatch prints both representations for research.
The test has no new window; use `continue` to resume the normal app.

The global `+[NTKFace faceWithJSONObjectRepresentation:forDevice:]` decoder is
not used: it resolves bundled styles through the shared manager, which does not
know our explicit test directory. No shared-loader replacement, swizzling,
cache mutation, or system installation is used to work around that limitation.

The original discovery helper and local bundle defaultFaceForDevice: retain their
style-zero behavior for comparison. This new helper calls the bundled factory
explicitly, so successful new behavior does not silently change the old test.
A pass establishes a minimal configuration round trip through the receiving bundle;
custom edits, resource files, gallery eligibility and cross-process restoration
remain separate tests.

## Native presentation of the restored identified model

Restart WatchFaceLab to use the rebuilt module. Bring it forward, pause, and run
individually, checking each result before the next call:

```lldb
thread select 1
expr -l objc++ -- (int)[NSThread isMainThread]
process load /tmp/WatchFaceLab26-NTK/MYCustomFaceExperiment.dylib
expr -l objc++ -- (int)MYPresentRestoredLocalFaceExperiment(@"/tmp/WatchFaceLab26-NTK/FaceBundles")
continue
```

The main-thread check must return 1 and module loading must succeed. Expected:
discovery and identity PASS logs, then native controller creation with style 44,
and `Restored preview PoC PASS: exact restored model hosted`. Confirm the time
and PoC label appear. This helper reuses the complete checked round trip and
retains its returned model; it does not substitute a newly allocated face. It
rejects an already open preview instead of reporting success for the wrong model.

After successful presentation, pause on the main thread and request activation:

```lldb
thread select 1
expr -l objc++ -- (int)MYSetNativeControllerExperimentActive(1)
continue
```

After observing the time display, pause on the main thread and clean up:

```lldb
thread select 1
expr -l objc++ -- (int)MYSetNativeControllerExperimentActive(0)
expr -l objc++ -- (void)MYDismissNativeControllerExperiment()
continue
```

Return values should be 1. Preserve all new diagnostics; on an exception or NO,
stop before dependent steps and capture logs/backtrace. The prior native lifecycle
success used style zero and does not establish this identified style-44 path.

## Isolated gallery contract

The local bundle now returns an identified style-44 model from defaultFaceForDevice:,
provides a title/description, and exposes one face through galleryFacesForDevice:.
The older discovery test therefore also creates a style-44 default face now.
The independent style-zero preview entry point is unchanged.

Restart WatchFaceLab before loading both updated artifacts. In the foreground
app, pause and run individually:

```lldb
thread select 1
expr -l objc++ -- (int)[NSThread isMainThread]
process load /tmp/WatchFaceLab26-NTK/MYCustomFaceExperiment.dylib
expr -l objc++ -- (int)MYInspectLocalFaceGallery(@"/tmp/WatchFaceLab26-NTK/FaceBundles")
```

Proceed only with a main-thread result of 1 and successful module loading. Expect
the existing discovery PASS, followed by device restriction=0, nonempty metadata,
rowPriorities=(null), and:

```text
Local gallery PoC PASS: faces=1 title=Custom Face PoC class=MYCustomFace style=44 identifier=dev.develodom.WatchFaceLab.LocalFaceBundle renderer=MYCustomFaceView
```

Return value 1 means the checked bundle contract completed. Paste the full log;
on NO/exception preserve stage logs and `bt`. Use `continue` to resume the app.
There is no new window or gallery UI. This tests the bundle's gallery-facing
methods through the isolated loader, not global gallery discovery or acceptance
by an NTK gallery collection. Row priorities use the verified nil base default;
no priority schema or restriction bypass is invented.

## Native gallery collection consumer

Restart WatchFaceLab, bring it forward, pause, and run individually:

```lldb
thread select 1
expr -l objc++ -- (int)[NSThread isMainThread]
process load /tmp/WatchFaceLab26-NTK/MYCustomFaceExperiment.dylib
expr -l objc++ -- (int)MYStartNativeGalleryCollection(@"/tmp/WatchFaceLab26-NTK/FaceBundles")
continue
```

Proceed only after a thread result of 1 and successful module loading. A start
result of 1 and `Native gallery PoC STARTED` mean metadata was accepted and native
loadFaces was invoked; they do not mean faces finished loading. Resume the app
for a few seconds to allow the native background load and main-queue publication.
Then pause and check:

```lldb
thread select 1
expr -l objc++ -- (int)MYCheckNativeGalleryCollection()
```

Expect one face in NTKFacesBundleArrayGalleryCollection, followed by
`Native gallery PoC PASS` and return value 1. This reads the native collection's
numberOfFaces/faceAtIndex:, not a direct return from our gallery override.
The model must retain MYCustomFace class, style 44, correct identifier and valid
JSON, and produce MYCustomFaceView with a timeView.

If count is zero, preserve the logs. Zero can mean pending work or an empty/failed
result; resume briefly and check once more. Do not spin in LLDB while the process
is paused or repeatedly start new collections. If it remains zero or an exception
occurs, capture logs and `bt`. No private completion method is guessed or invoked.

After a successful check, release the experiment's ownership and resume:

```lldb
expr -l objc++ -- (void)MYReleaseNativeGalleryCollection()
continue
```

This does not cancel pending work or assert deallocation. The native collection
has an observer-removal path in dealloc; the helper does not manually invoke it.
No gallery UI or installed system face is created by this test.

### Preserve the native collection start fault

The first start attempt reported EXC_BAD_ACCESS, although the collection later
contained one valid face. A subsequent capture showed SIGSTOP and an idle run
loop; it was not the faulting stack. LLDB may automatically unwind expression
errors before ordinary backtrace commands can inspect them.

In a fresh app process, load the module as above, then use this diagnostic start
instead of the ordinary expression:

```lldb
thread select 1
expr -l objc++ -u false -- (int)MYStartNativeGalleryCollection(@"/tmp/WatchFaceLab26-NTK/FaceBundles")
```

`-u false` is the installed LLDB's verified --unwind-on-error option. If it faults,
do not continue or switch to thread 1. Capture the selected faulting thread:

```lldb
thread list
thread backtrace all
frame info
register read rip rsp rbp
disassemble --frame
```

Do not call the check/release helpers while diagnosing a preserved fault. After
capturing output, restart the app for a clean process rather than treating LLDB
unwinding as rollback. If it succeeds without a fault, preserve the full output;
that is a non-reproduction, not proof of the original cause.
