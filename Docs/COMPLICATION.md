# Pip-Boy WidgetKit complication

Branch: `complication`

This branch is the stock-watchOS alternative to the private NanoTimeKit
experiment. The shipped Watch app contains a public WidgetKit extension and no
NanoTimeKit, ClockKitUI, local executable face bundle, collection-server XPC
probe, or system-host hook.

## Build and install

On the Mac with Xcode 27 and the paired physical Watch:

```sh
git switch complication
git pull --ff-only
bash Experiments/watchos27-complication.sh
```

The script selects the first connected physical Watch, builds and signs both
targets, verifies the WidgetKit extension point, rejects any leaked private
experiment artifact/dependency, installs the app, and opens its setup screen.
Use `--device ID`, `--build-only`, or `--check` when needed.

The host uses bundle identifier
`dev.develodom.WatchFaceLab.ComplicationHost`, so it can coexist with the
private-research WatchFaceLab installed from `version/27`.

## Add it to a system face

1. Press and hold the current face on the Watch.
2. Tap **Edit**, then open **Complications**.
3. Choose an inline, circular, corner, or rectangular slot.
4. Select **Pip-Boy Monitor**.

The complication provides a green phosphor-style Pip-Boy status display with
time, health, action points, and radiation motifs. WidgetKit controls refresh,
color adaptation, always-on rendering, and interaction according to the chosen
system face.

## Optional `.watchface` seed

Apple's `.watchface` file is a system-exported configuration of an existing
face, not a package for an executable renderer. After configuring the Pip-Boy
complication once, use the system Share action to export that face. Inspect the
export for personal complication data before retaining it, then place the file
at:

```text
WatchFaceLab/Resources/PipBoy.watchface
```

The next build embeds it. The app's **Install saved face** button imports that
known-good system export through `CLKWatchFaceLibrary`. When no seed is present,
the app keeps the manual setup path and never fabricates the private file
format.

## Scope

This route creates a real, durable Apple system face containing custom app
content. It does not replace the entire face renderer, add an `NTKFace`
subclass to `ClockFace`, animate the original GIF continuously, or bypass the
physical sandbox boundary documented on `version/27`.
