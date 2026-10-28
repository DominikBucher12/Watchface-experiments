# Physical-device system face collection probe

This staged experiment tests the production watchOS `LibraryFaces` collection
from the signed WatchFaceLab process. It does not claim success from build,
installation, or process launch alone. Every stage emits a
`SYSTEM_FACE_RESULT` JSON record to the device console.

## Stages

Run each command from `version/27` on the Mac that has Xcode 27, matching
watchOS 27 DeviceSupport symbols, and an available paired Watch:

```sh
bash Experiments/bootstrap-watchos27-device.sh --system-action preflight
```

`preflight` opens the real `NTKPersistentFaceCollection` library client, waits
for its XPC-backed state, records selector encodings, the selected UUID and
bundle identifiers, and performs no mutation. Continue only when its JSON says
`"pass":true`.

```sh
bash Experiments/bootstrap-watchos27-device.sh --system-action install
```

`install` creates the verified local `MYCustomFace`, adds it at the end of the
library collection, records the new UUID and the previous selected UUID, and
deliberately leaves the current face selected. It requires the exact mutation
ABI observed by the probe. A second preflight tests whether the daemon returned
the UUID and whether the custom bundle can still be resolved:

```sh
bash Experiments/bootstrap-watchos27-device.sh --system-action preflight
```

Only if that result contains both `"candidateOrdered":true` and
`"customResolved":true` should selection be attempted:

```sh
bash Experiments/bootstrap-watchos27-device.sh --system-action select
```

Selection is refused when the custom bundle cannot be resolved. This protects
the current ClockFace from switching to an unreadable descriptor.

Rollback removes the recorded UUID and restores the previous selected UUID when
it is still present:

```sh
bash Experiments/bootstrap-watchos27-device.sh --system-action rollback
```

## What the results mean

- `candidateOrdered=false`: the collection server rejected or did not retain
  the add operation.
- `candidateOrdered=true`, `customResolved=false`: persistence worked, but the
  separate consumer cannot locate the executable custom bundle. Argon/bundle
  distribution is still the blocker.
- both values `true`: the app-side collection can reconstruct the persisted
  face. Selection then tests whether the actual system ClockFace consumer has
  the same visibility.
- successful selection plus visible Pip-Boy after leaving WatchFaceLab is the
  required system-level result.

The console attachment lasts 20 seconds. A timeout status after the JSON record
is expected because a watchOS app normally remains running.
