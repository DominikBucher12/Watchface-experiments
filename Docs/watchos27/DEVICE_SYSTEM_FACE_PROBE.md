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

The watchOS 27.0.1 run reached `NSXPCConnection`, successfully enqueued the
registration message, and received neither collection state nor an explicit
transport error before timeout. Repeating the app preflight cannot distinguish
service identity, entitlement, sandbox, or server-policy rejection. Inspect the
static system side next:

```sh
bash Experiments/watchos27-device-face.sh audit
```

`audit` is host-only and non-mutating. It resolves the matching DeviceSupport
tree, accepts only the exact `/Applications/ClockFace.app/ClockFace` binary
(never the similarly named accessibility bundle), and reports when ClockFace,
`nanotimekitd`, FaceSupport components, launchd plists, signatures, or
entitlements are absent from the symbol set. DeviceSupport copies may have
stripped code signatures or entitlements, so absence there is not proof of
absence on the running Watch.

The physical audit identified `nanotimekitd` as the collection-server host. Its
embedded entitlements include Mach lookup for
`com.apple.nanotimekit.collectionserver`, platform-application status,
FaceSupport storage access, and a separate NanoTimeKit library-replicator
entitlement. The last entitlement may belong to snapshot replication and is not
yet proven to gate `LibraryFaces`. The exact `ClockFace.app/ClockFace` binary
and launchd plist were not present in this DeviceSupport set, while
`ClockFaceSupport.framework` was present.

The next probe checks the decisive client-side boundary without attempting an
XPC connection:

```sh
bash Experiments/watchos27-device-face.sh boundary
```

`boundary` rebuilds and launches WatchFaceLab, calls `sandbox_check` for the
collection-server Mach name, and reads only WatchFaceLab's own signed
entitlements. Its JSON explicitly records `"xpcRequestSent":false`.

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

Do not run `install` after a preflight collection-load timeout. A sent XPC
message is not evidence that the server accepted it, and mutation completion
would be ambiguous without a loaded reference collection.

The bootstrap gives the probe up to 25 seconds, rejects stale result files using
a per-run identifier, and fails when it cannot copy a matching JSON record from
the app data container. On timeout it prints the latest `SYSTEM_FACE_PROGRESS`
milestone and lists the app's `Documents` directory, distinguishing a launch,
framework-load, private-probe, or file-transfer failure. CoreDevice receives the
record into a concrete local file whose parent directory already exists. The
downloader accepts both relative and root-relative remote paths and prints any
JSON recovered by its failure path.

Before an action launch, the bootstrap enumerates device processes and
force-terminates only a running `WatchFaceLab` PID. This is required because
watchOS did not reliably honor `devicectl --terminate-existing`; reusing the old
process also reused its environment and one-shot action guard.

Transient CoreDevice disconnects during the idempotent app-install step are
retried up to three times. The bootstrap deliberately does not retry launch or
any collection mutation automatically, because their completion may be
ambiguous after a transport failure.
