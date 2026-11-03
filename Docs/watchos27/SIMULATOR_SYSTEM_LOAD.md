# System ClockFace loader port for the simulator27 branch

## Status

The end-to-end simulator loader has been implemented in `version/simulator27`.
It is runtime-driven rather than hardcoded to one CPU or OS version.

On 2026-10-27 the complete flow was verified on a clean disposable watchOS 26.5
(23T570), x86_64 simulator because this Mac currently has no watchOS 27
Simulator runtime installed. The verified run produced:

- custom bundle discovery in the original ClockFace and `nanotimekitd`;
- unentitled collection mutation from one to two faces;
- a generated face UUID and `selected:true`;
- active UI switching through the ABI-checked ClockFace test selector; and
- visual Pip-Boy rendering with a 32-frame, 3.2-second animated GIF.

The independent overlay-aware collection report after installation was:

```json
{
  "loaded": true,
  "numberOfFaces": 2,
  "bundleIdentifiers": [
    "com.apple.NTKBigNumeralsDigitalFaceBundle",
    "dev.develodom.WatchFaceLab.LocalFaceBundle"
  ],
  "selectedUUID": "1BBAC938-8B65-447D-8B03-40C2EE9C8A96"
}
```

This proves that the port is internally complete and remains compatible with
the known 26.5 runtime. It does **not** yet constitute runtime evidence for
watchOS 27 itself. That final result requires installing/booting the historical
arm64 watchOS 27 Simulator runtime (the branch log identifies 27.0 / 24R362) or
another available 27.x runtime and rerunning the same guarded quickstart.

The branch's historical simulator framework was also inspected and reports
`arm64`, `WATCHOSSIMULATOR`, `minos 27.0`, and `sdk 27.0`. With the currently
installed SDK, every new source file (renderer, bundle, discovery/read/mutation
probes, bootstrap, and active selector) passes an arm64 watchOS 27.0 compile-only
check with `-Wall -Wextra -Werror`. Execution still requires the missing 27
runtime; linking now also supports private frameworks stored only in that
runtime's dyld shared cache.

Reproduce the architecture compile check without modifying a simulator:

```sh
bash Experiments/check-watchos27-port.sh
```

## Quickstart

On a second Mac, after pulling `version/simulator27`, run as the logged-in macOS
user, never with `sudo`:

```sh
bash Experiments/bootstrap-watchos27-simulator.sh
```

The bootstrap requires the full Xcode application and an installed watchOS 27.x
Simulator runtime. If the runtime is missing, install it in **Xcode > Settings >
Components** and rerun. It selects the newest available 27.x runtime, creates a
compatible dedicated simulator named `WatchFaceLab27 Research`, boots it, and
passes its UUID to the existing quickstart. No UUID needs to be copied between
computers.

Read-only preflight and create-only modes are available for troubleshooting:

```sh
bash Experiments/bootstrap-watchos27-simulator.sh --check
bash Experiments/bootstrap-watchos27-simulator.sh --create-only
```

For multiple installed 27.x runtimes or an unusual device profile, use
`--runtime` and `--device-type`; `--help` prints all overrides. To reuse an
already-created research simulator directly, run:

```sh
bash Experiments/quickstart-system-face.sh WATCHOS-27-RESEARCH-SIMULATOR-UUID
```

The quickstart boots the selected simulator, derives its runtime root, builds
for that runtime's architecture and minimum OS, prepares a non-destructive
hybrid root, loads the bundle in both system processes, installs/selects the
face, derives its actual collection index, switches that face in the live
ClockFace UI, and opens Simulator. It does not assume the custom face is at
index 1; watchOS runtime defaults may contain a different number of faces. The
simulated display can be asleep immediately after ClockFace restarts. Click the
Simulator window's **Crown** button once to wake it.

## Changing the face title

watchOS builds a localization key from the face style. Style 44 therefore asks
NanoTimeKit for `FACE_STYLE_44_IN_TITLE_CASE`. Because the stock runtime has no
value for this experimental style, it normally displays the key itself. The
runtime bootstrap intercepts only style 44's two title keys and returns the
configured custom title. It also exposes the same value through the local face
bundle's gallery title.

With the research simulator booted and the custom face loaded, run:

```sh
bash Experiments/set-watchface-title.sh "VAULT BOY"
```

The script auto-detects a single available `WatchFaceLab Research` simulator,
updates its launchd environment, restarts `ClockFace` and `nanotimekitd`, opens
Simulator, and waits for a log confirmation that ClockFace resolved the new
title. Titles must contain 1–64 characters on one line.

If more than one research simulator exists, pass the intended UUID:

```sh
bash Experiments/set-watchface-title.sh "PIP-BOY 3000" SIMULATOR-UUID
```

To choose the title during a complete bootstrap, use `--title`:

```sh
bash Experiments/bootstrap-watchos27-simulator.sh --title "PIP-BOY 3000"
```

For a direct quickstart, set `WATCHFACELAB_FACE_TITLE` on that command.

The default is `VAULT BOY`. The selected title remains in the booted
simulator's launchd environment and is inherited by restarted ClockFace
processes. A later bootstrap or quickstart replaces it with the requested title
or the default. Clean rollback removes the title variable.

Rollback is printed after a successful run and has this form:

```sh
bash Experiments/test-system-discovery-overlay.sh rollback SIMULATOR-UUID
```

## Runtime and ABI safeguards

`build-system-loader.sh` derives:

- the private framework root from the selected simulator;
- the executable architecture and deployment target from NanoTimeKit or a
  system face-bundle Mach-O in the selected runtime; and
- the public watchsimulator SDK from the active Xcode toolchain.

watchOS 27 runtimes may keep `NanoTimeKit` only in the simulator dyld shared
cache, so the path
`System/Library/PrivateFrameworks/NanoTimeKit.framework/NanoTimeKit` need not
exist as a regular file. In that layout the build creates a narrow temporary
`NanoTimeKit.tbd` in its `/tmp` output and links it with NanoTimeKit's real
system install name. At launch, CoreSimulator resolves that install name from
the runtime cache. The stub contains only symbols used by this experiment; no
runtime image is extracted, copied into Git, or modified. Build output reports
either `PRIVATE_FRAMEWORKS=files` or `PRIVATE_FRAMEWORKS=dyld-cache-stub`.

The generated local bundle removes the branch's historical fake `Argon`
dictionary. Direct system discovery does not use the Argon encrypted-payload
path.

The port deliberately fails closed at unstable private boundaries:

- collection add/remove/select methods must match their expected Objective-C
  type encodings before a write occurs;
- the live UI selector must be found on a real controller and match
  `v32@0:8Q16@?24` (or the signed-index equivalent);
- activation requires stable ClockFace and `nanotimekitd` PIDs plus a bundle
  load marker from both; and
- a failed activation or quickstart clears temporary launchd variables and
  restores clean processes.

If watchOS 27 changes an encoding, the probe reports an ABI mismatch instead of
calling it. Inspect the actual 27 runtime metadata, update only the confirmed
encoding/call site, and rerun.

## Scope

This is a simulator trust-boundary experiment using CoreSimulator developer
authority. It is separate from the physical-device renderer documented in the
other watchOS 27 notes and does not provide a deployment path for a physical
Apple Watch.
