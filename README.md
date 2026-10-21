# WatchFaceLab26

Minimal, clean-room **watchOS 26.5** research starter for an **Intel / x86_64** simulator. No dependencies, CocoaPods, Carthage, or XcodeGen.

## What you get

- `WatchFaceLab.xcodeproj` — single-target SwiftUI watch-only app built with the public SDK.
- A black digital clock UI that is intentionally **not** a real system watch face.
- `Experiments/NTKPrivateInterfaces.h` — minimal declarations checked against installed 23T570 x86_64 metadata.
- `Experiments/MYCustomFace.m` — an isolated Objective-C renderer overriding `faceViewClass`, **not linked by the app**.
- `Docs/RESEARCH.md` — evidence, assumptions, and gates for the next LLDB exercise.

## First run — do only this

1. Unzip and open `WatchFaceLab.xcodeproj` in Xcode.
2. Select target/scheme **WatchFaceLab** and a **watchOS 26.5** watch simulator (on Intel, select an x86_64 runtime).
3. In **Signing & Capabilities**, select your development team if Xcode requests it; a simulator normally needs no provisioning profile.
4. Press **Cmd+R**. Confirm that the clock is displayed.
5. Send back the exact build/run output if Xcode fails. Do not proceed to the experiments until the baseline is working.

CLI check (on your Mac):

```sh
xcodebuild -project WatchFaceLab.xcodeproj -scheme WatchFaceLab -sdk watchsimulator -configuration Debug -showdestinations
```

Build for a selected simulator destination in Xcode after confirming the simulator ID.

## Architecture / boundaries

`WatchFaceLab/` (public, runnable UI) is isolated from `Experiments/` (private-API research). The latter is source-only because we have not proved simulator process injection, required entitlements, linking behavior, runtime ABI, or face registration on watchOS 26.5.

**Do not** copy Apple frameworks into the repository. Use the framework already present in the locally installed simulator runtime. The declarations under `Experiments/` are illustrative and subject to correction after runtime introspection.

## Important status

This is a **stage-0 runnable baseline plus stage-1 source prototype**, not a working installed `NTKFace`. Project generation and compilation were not tested against Xcode 26.5 in this environment. The next milestone is to verify a clean build on your Mac.

## Continue with ChatGPT / Codex

Commit the entire directory to your own repository. The source code and `Docs/RESEARCH.md` are the authoritative project context; do not rely exclusively on conversational memory. In a new chat, provide your GitHub repo URL and say to continue from the documented milestone.

## Isolated simulator experiment

`bash Experiments/build-simulator.sh` builds the separate x86_64 watchOS 26.5
simulator dylib under `/tmp/WatchFaceLab26-NTK`. It uses the installed runtime
without copying Apple frameworks. See `Docs/RESEARCH.md` for evidence, the explicit
entry point, UIKit compilation workaround, and remaining runtime gates.
The module has been built; allocation and visual presentation have not been run.
