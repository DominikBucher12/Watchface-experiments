# Simulator system watch-face loading experiment

Status: end-to-end demonstrated on 2026-10-27 in the disposable
`WatchFaceLab26 Research` watchOS 26.5 simulator. The original ClockFace loaded
and rendered the custom face, `nanotimekitd` loaded the same bundle, and an
unentitled helper added and selected it through the collection server.

Target UUID: `E8757D97-8E48-479E-AD1C-9D8ADC8F5E5D`.

This is a simulator-only authorization and trust-boundary finding. It does not
establish an equivalent path on physical Apple Watch hardware: `simctl`, the
host runtime root, and the simulator launch environment do not exist there.

## Result of reviewing `version/simulator27`

The branch had already proved the custom `MYCustomFace`/`MYCustomFaceView`, local
`MYLocalFaceBundle.bundle`, descriptor round-trip, native gallery collection,
and an instance-only `NTKFaceBundleManager` bridge inside a renamed ClockFace
clone. None made the original `com.apple.clockface` discover the bundle.

The attempted original-process paths stopped at these boundaries:

- Direct `simctl launch com.apple.clockface` failed even without injection.
- LLDB attach to the original process was denied.
- `launchctl debug` accepted one-shot `DYLD_INSERT_LIBRARIES`, but terminating
  ClockFace created a new dynamic UIKit job label and discarded the debug
  configuration.
- The AppleInternal unencrypted Argon path was gated by
  `NTKInternalBuild() == 0`; there was also no valid `.aea` payload or key.

## Confirmed chain

### 1. Bundle discovery trusts a process environment root

`+[NTKBundleLoader rootDirectory]` reads `IPHONE_SIMULATOR_ROOT` and appends
`/System/Library/NanoTimeKit/FaceBundles`. CoreSimulator strips a global
`IPHONE_SIMULATOR_ROOT` override and restores the real runtime root, so merely
running `launchctl setenv IPHONE_SIMULATOR_ROOT=...` does not work.

Other launchd variables, including `DYLD_INSERT_LIBRARIES`, are inherited by
new ClockFace and daemon jobs. A narrowly scoped constructor therefore reads
`WATCHFACELAB_OVERLAY_ROOT` and calls `setenv("IPHONE_SIMULATOR_ROOT", ...)`
inside ClockFace and `nanotimekitd`, after CoreSimulator has sanitized the
initial environment. The global DYLD value is cleared immediately after both
jobs start.

### 2. The overlay must preserve the complete runtime namespace

Redirecting only NanoTimeKit made ClockFace abort in
`CEM::createFrameworkBundle()` because the root no longer contained CoreEmoji
resources. Symlinking the individual face-bundle entries also failed because
`NTKBundleLoader` skipped those entries.

The working hybrid overlay therefore:

- symlinks the untouched runtime namespace down to
  `System/Library/NanoTimeKit`;
- creates a real `FaceBundles` directory;
- clone-copies the 60 Apple face bundles into it; and
- adds the ad-hoc-signed `MYLocalFaceBundle.bundle` as entry 61.

This neither modifies nor replaces a file in the mounted Apple runtime.

The original processes then emitted:

```text
WATCHFACELAB_SYSTEM_BUNDLE_LOADED ... host=com.apple.clockface
WATCHFACELAB_SYSTEM_BUNDLE_LOADED ... host=com.apple.nanotimekitd
```

The independent discovery probe reported 58 eligible Apple bundles plus the
custom bundle:

```json
{"pass":true,"total":59,"matches":1,"matchedClass":"MYLocalFaceBundle"}
```

### 3. The collection service accepts an unentitled client

`CollectionReadProbe` is an ad-hoc command-line process with no special
entitlements. It connected to `com.apple.nanotimekit.collectionserver`, loaded
`NTKPersistentFaceCollection`, and read the library. The runtime-confirmed
mutation ABI is:

```text
addFace:atIndex:suppressingCallbackToObserver:  v40@0:8@16Q24@32
removeFace:suppressingCallbackToObserver:       v32@0:8@16@24
_selectFaceUUID:notify:                         v28@0:8@16B24
```

The guarded mutation probe then demonstrated missing write-side authorization:

```json
{"countBefore":1,"countAfter":2,"added":true,"selected":true,
 "uuid":"9DEC5E35-DE76-4D44-AFBA-1BC221A2C74E"}
```

ClockFace rendered the selected custom face in the original system UI. The test
face showed large yellow `17` and pink `13` digits on black.

## Implementation

- `SystemRootBootstrap.m` installs the overlay root only in ClockFace and
  `nanotimekitd`, and rejects roots outside `/tmp/WatchFaceLabSystemRoot.*`.
- `SystemDiscoveryProbe.m` verifies exactly one discoverable custom bundle.
- `CollectionReadProbe.m` demonstrates unentitled collection access and records
  the ABI.
- `CollectionMutationProbe.m` guards install/remove, rejects duplicate install,
  derives the generated UUID, verifies selection, and rolls back a failed add or
  selection.
- `MYLocalFaceBundle +load` emits a host-specific load marker only when the
  experiment marker is present.
- `test-system-discovery-overlay.sh` prepares, activates, validates, installs,
  removes, reports status, and rolls back. Activation requires stable PIDs and
  bundle-load markers from both system processes.

All helper binaries build with warnings treated as errors.

## Reproduction

Run as the normal macOS user, never through `sudo`. CoreSimulator device sets
are per-user. `sudo xcrun simctl ...` asks root's CoreSimulator service for the
UUID and correctly returns `Invalid device` because that device belongs to the
logged-in user's device set.

Prepare a hybrid root:

```sh
bash Experiments/test-system-discovery-overlay.sh prepare \
  E8757D97-8E48-479E-AD1C-9D8ADC8F5E5D
```

Use the printed `OVERLAY_ROOT`:

```sh
bash Experiments/test-system-discovery-overlay.sh activate \
  E8757D97-8E48-479E-AD1C-9D8ADC8F5E5D \
  /tmp/WatchFaceLabSystemRoot.XXXXXX

bash Experiments/test-system-discovery-overlay.sh install \
  E8757D97-8E48-479E-AD1C-9D8ADC8F5E5D
```

The bootstrap is intentionally session-scoped. If ClockFace or
`nanotimekitd` is restarted later, run `activate` again before using the custom
face. Keep the overlay until removal is complete.

Remove the face and restore clean processes and launchd environment:

```sh
bash Experiments/test-system-discovery-overlay.sh rollback \
  E8757D97-8E48-479E-AD1C-9D8ADC8F5E5D
```
