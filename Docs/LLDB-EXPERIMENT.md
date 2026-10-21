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
