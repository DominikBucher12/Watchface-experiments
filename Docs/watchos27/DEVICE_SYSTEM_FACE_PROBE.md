# Physical-device system face collection probe

This staged experiment tests the production watchOS `LibraryFaces` collection
from the signed WatchFaceLab process. It does not claim success from build,
installation, or process launch alone. Every stage atomically writes a
`SYSTEM_FACE_RESULT` JSON record to its app data container; the bootstrap copies
that file back and prints it on the Mac.

## Stages

Run each command from `version/27` on the Mac that has Xcode 27, matching
watchOS 27 DeviceSupport symbols, and an available paired Watch:

```sh
bash Experiments/watchos27-device-face.sh preflight
```

`preflight` opens the real `NTKPersistentFaceCollection` library client, waits
for its XPC-backed state, records selector encodings, the selected UUID and
bundle identifiers, and performs no mutation. On load timeout it also records
the connection, registration flag, reference collection state, current
`CLKDevice`, and one `_registerIfNeeded` retry when requested by the collection.
It also repeats the same non-mutating registration through a dedicated XPC error
handler after a timeout, so an explicit service rejection can be recorded.
Continue only when its JSON says `"pass":true`.

```sh
bash Experiments/watchos27-device-face.sh install
```

`install` creates the verified local `MYCustomFace`, adds it at the end of the
library collection, records the new UUID and the previous selected UUID, and
deliberately leaves the current face selected. It requires the exact mutation
ABI observed by the probe. A second preflight tests whether the daemon returned
the UUID and whether the custom bundle can still be resolved:

```sh
bash Experiments/watchos27-device-face.sh preflight
```

Only if that result contains both `"candidateOrdered":true` and
`"customResolved":true` should selection be attempted:

```sh
bash Experiments/watchos27-device-face.sh select
```

Selection is refused when the custom bundle cannot be resolved. This protects
the current ClockFace from switching to an unreadable descriptor.

Rollback removes the recorded UUID and restores the previous selected UUID when
it is still present:

```sh
bash Experiments/watchos27-device-face.sh rollback
```

The most recent record can be fetched without rebuilding or launching:

```sh
bash Experiments/watchos27-device-face.sh result
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

The bootstrap gives the probe up to 25 seconds, rejects stale result files using
a per-run identifier, and fails when it cannot copy a matching JSON record from
the app data container. On timeout it prints the latest `SYSTEM_FACE_PROGRESS`
milestone and lists the app's `Documents` directory, distinguishing a launch,
framework-load, private-probe, or file-transfer failure. CoreDevice receives the
record into a concrete local file whose parent directory already exists. The
downloader accepts both relative and root-relative remote paths and prints any
JSON recovered by its failure path.

Transient CoreDevice disconnects during the idempotent app-install step are
retried up to three times. The bootstrap deliberately does not retry launch or
any collection mutation automatically, because their completion may be
ambiguous after a transport failure.
