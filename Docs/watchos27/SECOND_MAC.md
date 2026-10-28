# Run the watchOS 27 Simulator experiment on another Mac

This path does not require Codex. It requires the full Xcode application, a
watchOS 27.x Simulator runtime, and an Apple Silicon Mac capable of running that
runtime.

## One-time Xcode setup

1. Open Xcode and complete its first-launch setup.
2. Open **Xcode > Settings > Components**.
3. Install a **watchOS 27.x Simulator** runtime.
4. If more than one Xcode is installed, select the intended one:

   ```sh
   sudo xcode-select -s /Applications/Xcode.app
   ```

`sudo` is only appropriate for selecting Xcode. Do not run the experiment
itself with `sudo`; CoreSimulator devices belong to the logged-in user.

## Pull and run

From the repository:

```sh
git switch version/simulator27
git pull --ff-only
bash Experiments/bootstrap-watchos27-simulator.sh
```

The script checks the active Xcode and SDK, finds the newest available watchOS
27.x runtime, creates or reuses `WatchFaceLab27 Research`, boots it, builds for
the runtime's actual architecture, prepares a temporary hybrid root, installs
and selects the custom face, and opens Simulator.

It does not modify the Apple runtime. Build products and the hybrid root live in
`/tmp`; the only persistent object it creates is the dedicated Simulator device.

## Preflight and recovery

Check prerequisites without creating or booting a device:

```sh
bash Experiments/bootstrap-watchos27-simulator.sh --check
```

Create and boot the dedicated simulator without loading the face:

```sh
bash Experiments/bootstrap-watchos27-simulator.sh --create-only
```

If the loader succeeds, it prints the exact rollback command. The standard form
is:

```sh
bash Experiments/test-system-discovery-overlay.sh rollback SIMULATOR-UUID
```

To discard the entire dedicated simulator after rollback:

```sh
xcrun simctl delete SIMULATOR-UUID
```

If the bootstrap reports that watchOS 27 is missing, return to Xcode's Components
settings and install it. If multiple 27.x runtimes are installed, select one
explicitly using the identifier printed by `xcrun simctl list runtimes`:

```sh
bash Experiments/bootstrap-watchos27-simulator.sh \
  --runtime com.apple.CoreSimulator.SimRuntime.watchOS-27-0
```
