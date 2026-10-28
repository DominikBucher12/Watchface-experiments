# watchOS 27 native watchface research — index

**Status:** physical-device research, **not** a persistent system watchface.  
**Target:** Apple Watch Series 9 (`Watch7,4`), watchOS **27.0.1 (24R365)**, arm64e; WatchFaceLab app `dev.develodom.WatchFaceLab`.  
**Branch:** [`version/27`](https://github.com/DominikBucher12/Watchface-experiments/tree/version/27).  
**Last verified:** 2026-10-22.

## Objective

Render a custom Pip-Boy-inspired native `NTKFace` / `NTKFaceView`, then determine whether it can be discovered and used as a **persistent system watchface** by Apple's `ClockFace` process. The latter remains unproven.

## Current state

| Milestone | Status | Scope |
| --- | --- | --- |
| Native `MYCustomFace` and `MYCustomFaceView` rendered | **PASS** | WatchFaceLab process on physical Watch |
| Device framework exported and embedded | **PASS** | App bundle, signed during Xcode embedding |
| External `MYLocalFaceBundle.bundle` discovered with `NTKFaceBundleLoader` | **PASS** | Isolated loader in WatchFaceLab |
| `NTKFaceBundleManager` returns and enumerates our bundle via ephemeral subclass | **PASS** | **Only WatchFaceLab**, manager restored afterward |
| Argon classes and Objective-C method signatures inspected | **PASS** | Read-only process introspection |
| Argon extracted-directory access | **DENIED (`EPERM`)** | WatchFaceLab sandbox |
| Collection-server Mach lookup | **DENIED** | Fresh on-device `sandbox_check`; no XPC request sent |
| Descriptor enumeration result | **NOT PROVEN** | Logs showed directory errors; no complete descriptor result |
| Discovery/registration by actual `ClockFace` | **NOT PROVEN** | Separate Apple platform process |
| Pip-Boy survives exiting WatchFaceLab as native system face | **NOT ACHIEVED** | Original objective |

## Reproduce on a physical Watch

With Developer Mode enabled and the paired Watch available to Xcode:

```sh
bash Experiments/bootstrap-watchos27-device.sh --check
bash Experiments/bootstrap-watchos27-device.sh
```

The bootstrap performs automatic DeviceSupport discovery, app-contained native
artifact builds, Xcode signing, package verification, installation and launch.
The currently paired Series 9 can appear as `unavailable` while locked or when
its paired iPhone is not reachable; in that state use `--build-only` or restore
the connection before installation.

## Documents

- [../REPOSITORY_CLEANUP.md](../REPOSITORY_CLEANUP.md) — clean-checkout artifact
  policy, verified backups, and history-rewrite recovery instructions.
- [BUILD_AND_REPRODUCTION.md](BUILD_AND_REPRODUCTION.md) — build/packaging flow, device checks, previous build failures.
- [EXPERIMENT_LOG.md](EXPERIMENT_LOG.md) — chronological results and log evidence.
- [ARGON_AND_MANAGER.md](ARGON_AND_MANAGER.md) — Argon architecture, symbols, selector ABI, limitations.
- [CLOCKFACE_BOUNDARY.md](CLOCKFACE_BOUNDARY.md) — actual system process, signing constraints, next research steps.
- [DEVICE_SYSTEM_FACE_PROBE.md](DEVICE_SYSTEM_FACE_PROBE.md) — staged, ABI-gated
  `LibraryFaces` preflight/install/select/rollback experiment for a physical
  Watch, with device-console evidence requirements.
- [ALTERNATIVE_ROUTES.md](ALTERNATIVE_ROUTES.md) — supported complication plus
  `.watchface` route versus requirements for a full custom native renderer.

## Key terminology

- **Renderer PoC:** model and view displayed inside the application's lifecycle.
- **Local bundle discovery:** loader processes our executable bundle in the app container.
- **Owned manager experiment:** ephemeral, app-process-only `object_setClass` interception. Does **not** patch or inject into `ClockFace`.
- **Argon:** private NanoTimeKit distribution/extraction infrastructure; relationship to permitted third-party executable watchfaces remains unknown.

## Evidence discipline

A runtime `PASS` proves only the process and call path actually tested. Static strings/class selectors show implementation surfaces, not availability to third-party apps. A `Code Sign On Copy` checkbox alone does not demonstrate acceptance by the platform process. Error `EPERM` means access was denied, **not** that the directory exists or contains bundles.

The repository's original `Experiments/README.md` may describe an earlier, unverified device stage. This documentation records later **observed device results** and does not silently supersede source code in your checkout.
