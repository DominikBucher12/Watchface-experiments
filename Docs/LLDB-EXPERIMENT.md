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
