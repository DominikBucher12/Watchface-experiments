# Pip-Boy renderer preview

This is an isolated visual variant of `MYCustomFaceView` in the LLDB-loaded
experiment dylib. It does not change the SwiftUI app entry point or install a
system face.

The supplied Tenor GIF is 512x640 with 32 frames. The renderer uses ImageIO to
crop the center character from each frame, leaving out the HP panel, and scales
that animation into the 208x248 simulator face. The tabs, status panels, date,
battery/weather strip, and native digital time label are drawn separately in
monospaced green UI. Sample activity, battery, and weather values are decorative.

The app-owned preview controller requests a hidden UIKit status bar so the
system clock at the top-right does not compete with the custom layout. This is
scoped to this preview controller; it does not swizzle navigation or change
the native `NTKFaceViewController` experiment. Whether watchOS honors the
status-bar preference for this temporary window still needs visual runtime
verification.

The source animation is kept outside the project at:

```text
/tmp/WatchFaceLab26-NTK/pip-boy-reference.gif
```

Build the experiment module with:

```sh
bash Experiments/build-simulator.sh
```

With WatchFaceLab paused in LLDB on its main thread, present the renderer:

```text
thread select 1
expr -l objc++ -- (int)[NSThread isMainThread]
process load /tmp/WatchFaceLab26-NTK/MYCustomFaceExperiment.dylib
expr -l objc++ -- (int)MYPresentCustomFaceExperiment(0)
continue
```

Dismiss it from LLDB with:

```text
thread select 1
expr -l objc++ -- (void)MYDismissCustomFaceExperiment()
continue
```

The LLDB preview changes only WatchFaceLab's process. If the animation file is
missing, the renderer logs that fact and still displays the native time and
drawn panels.
