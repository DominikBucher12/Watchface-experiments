# System library and persistence boundary

Status: installed-runtime static trace, read-only. No persistent face was added
and no server request was sent by this investigation.

## Verified client path

`+[NTKPersistentFaceCollection sharedLibraryCollection]` creates the library
collection with the `LibraryFaces` collection identifier. Its initializer
`-[NTKPersistentFaceCollection _initWithCollectionIdentifier:deviceUUID:]`
creates an `NSXPCConnection` for the compiled-in
`com.apple.nanotimekit.collectionserver` Mach service, configures the verified
`NTKCollectionServer` remote interface and `NTKCollectionClient` exported
interface, resumes the connection, and registers the collection.

The installed runtime's `System/Library/LaunchDaemons/com.apple.nanotimekitd.plist`
maps `com.apple.nanotimekit.collectionserver` to
`/System/Library/PrivateFrameworks/NanoTimeKit.framework/nanotimekitd`. This
identifies the service owner for watchOS 26.5 Simulator. It does not prove which
client processes are authorized, what durable files the daemon writes, or which
daemon-side checks reject a custom bundle.

The XPC protocol carries a full ordered UUID list, selected UUID, and a dictionary
of face instance descriptors when it loads the collection. Client callbacks
reconstruct `NTKFace` instances from descriptors and update the in-memory
collection. The client exposes separate mutations for add, remove, reorder,
configuration/resource updates, and selected UUID. For example,
`addFaceInstanceDescriptor:forUUID:seqId:` sends update type 1 through the queued
update path; the daemon callback later resolves the descriptor to a face and
updates client state. `updateSelectedFaceUUID:seqId:` sends update type 5. The
callback side maintains sequence identifiers and can enqueue updates while daemon
notifications are suspended. The XPC server therefore owns the authoritative
library state and feeds copies back to clients.

The client configures concrete `NSXPCInterface` class allowlists. For the server
callback that loads a full collection, the faces-by-UUID argument allows an
`NSDictionary` containing `NSUUID` keys and `NTKFaceInstanceDescriptor` values;
the ordered UUID list allows `NSArray` and `NSUUID`. This documents the expected
wire object types, not which processes are authorized to connect.

The addable collection is a separate client staging path. Its initializer uses
collection identifier `AddableFaces`, loads content from the shared face bundle
manager, tracks existing library faces and their descriptors, and observes bundle
updates. It is not the persistent library itself. A passing shared-manager hook
in WatchFaceLab cannot make this staging data appear in ClockFace because the
manager hook is process-local.

## Meaning for integration

Persistent insertion requires a unique UUID, a descriptor that round-trips in
other participating processes, and coordination with the daemon's sequence/update
protocol. Selection is a separate durable update. The `NTKFace` descriptor is
only known to round-trip locally so far; no cross-process reconstruction or
server acceptance has been tested. The descriptor also references an Objective-C
class supplied by a bundle image. Any client asked to reconstruct it must have
loaded the matching class and resolve its bundle identity. Whether the collection
server also validates bundle eligibility is not known from the client code.

Do not call the persistent add/remove/select methods as a probe. They send state
changes to the daemon and can alter the simulator's durable face library. The
daemon listener accepts a new connection in
`NTKDCollectionCoordinator`'s `listener:shouldAcceptNewConnection:` method. Its
accept path creates an `NTKDCollectionClient` for that connection, installs an
invalidation handler, tracks the client, assigns the coordinator queue, and
resumes the connection. The client registration callback dispatches to the
coordinator's `checkoutStoreForCollectionIdentifier:deviceUUID:withHandler:`.
The inspected listener method contains no sender identity check. This is a
method-local observation only: it does not establish that launchd, XPC interface
validation, registration, or individual store operations lack authorization.
The disassembly of this method shows it queues connection setup and returns
`YES`; `NTKDCollectionClient registerForCollectionIdentifier:deviceUUID:withSeqId:`
then dispatches the checkout through the coordinator. No sender-entitlement branch
was visible in those inspected methods. This is still only a method-local result.
The launchd plist exposes several NanoTimeKit Mach services but has no explicit
client allowlist key. A `codesign -d --entitlements` inspection of this simulator
daemon emitted an invalid-entitlements-blob warning, so it did not establish the
daemon's effective entitlements or the service's client policy.

The installed daemon was rechecked directly from its Objective-C metadata and
x86_64 disassembly. `NTKDCollectionCoordinator` implements
`listener:shouldAcceptNewConnection:` with encoding `B32@0:8@16@24` at IMP
0x10000fd84. The method retains the incoming connection, queues its setup on the
coordinator queue, and returns `YES`; the method body does not extract an audit
token, signing identifier, or entitlement before accepting. The registration
selector on `NTKDCollectionClient` is `registerForCollectionIdentifier:deviceUUID:withSeqId:`
with encoding `v40@0:8@16@24@32` at IMP 0x1000249c8; its front half retains the
arguments and dispatches registration work asynchronously. This narrows the
answer to “no explicit check in the inspected accept method,” not “any app is
authorized”: launchd/Mach-service policy, NSXPC interface checks, asynchronous
registration/store validation, and operation-specific policy remain unverified.
Do not test those boundaries by opening a client connection or issuing a
collection request; that would move from static inspection into service use.

The `NTKDCollectionClient` exposes registration and separate queued mutation
methods for add, remove, reorder, configuration/resource updates, and selection.
The curator's `collectionStore:didAddFace:forUUID:seqId:` callback forwards the
provided face and UUID to the store and updates the backup sequence preference.
The curator helper `_addFace:toStore:andSelect:` generates an NSUUID, adds the
face, and selects it only when its `andSelect` argument is true. This confirms
that storage insertion and selection are distinct operations. The daemon's
curation path checks whether initial setup is complete and otherwise loads its
backup before continuing; this is bootstrap/recovery behavior, not evidence of a
custom-face eligibility check.

The concrete `NTKDCollectionStore` class is present in the daemon. Its initializer
is keyed by collection identifier and device UUID. The queued add operation asks
the manifest to add the UUID with the face's style before creating the face's
resource directory and serializing the face's `JSONObjectRepresentation` to
stored face data. The manifest tracks ordered UUIDs and boxed face styles; its
`addUUID:withFaceStyle:` returns false when that UUID is already present, which
gates the queued add. The store writes selected UUID state to a file named
`selected-uuid.string`, and its path-building helper appends `Faces/<UUID>` below
a store directory. The initializer builds this directory below
`_NTKHomeDirectory()/CollectionStores/<device UUID>/<collection identifier>`;
the nil-device branch uses `CollectionStores/GlobalStores/<collection
identifier>`. Each face stores `Faces/<UUID>/face.json`; the manifest file is
`manifest.plist`. The home directory helper's fully resolved on-disk location
depends on the daemon's runtime context and was not evaluated.

The store read path is also present: it reads `face.json` as data, parses JSON,
then calls NanoTimeKit's verified
`+[NTKFace faceWithJSONObjectRepresentation:forDevice:forMigration:allowFallbackFromInvalidFaceStyle:]`
with `+[CLKDevice currentDevice]`, migration enabled, and fallback from invalid
face style enabled. It then sets the face resource directory. For bundle-style
representations, this factory consults `NTKFaceBundleManager`'s shared manager
using the serialized bundle identifier and device, and obtains `faceClass` from
the matching bundle (the migration path uses the manager's migration lookup).
The manager first checks its bundle cache, then calls its loader's verified
`loadFaceBundleWithIdentifier:` method on a cache miss and caches a returned
bundle. Thus daemon-side reconstruction depends on the custom bundle being
discoverable by the daemon's loader and its principal class being available.
The loader's search roots have now been traced statically. The manager builds a
directory list from `NTKBundleLoader rootDirectory`, which returns the
`IPHONE_SIMULATOR_ROOT` environment value (or an empty string when unset),
appending `/System/Library/NanoTimeKit/FaceBundles/`; when the
`NanoTimeKitExtras/internal_face_bundles` feature is enabled, it also adds
`/AppleInternal/Library/NanoTimeKit/FaceBundles/`. Internal builds can add
`/AppleInternal/Library/NanoTimeKit/FaceSupport/UnencryptedBundles/` when the
corresponding feature is enabled. Otherwise, the manager adds the Argon
extractor path plus its build version. These URLs are passed to
`NTKFaceBundleLoader initWithURLs:`. The loader enumerates bundles from each
supplied directory; no app container, arbitrary injected directory, or `/tmp`
path is added by this manager. Thus the app-local bundle used by WatchFaceLab
is not shown to be discoverable by the daemon's normal manager. Cross-process
custom subclass reconstruction remains unproven and is not expected for a
bundle placed solely under `/tmp` using the traced default roots.

This static pass has not identified a collection-server sender authorization
rule or evaluated the daemon's home directory on disk. The simulator daemon's
embedded entitlements could not be reliably decoded by `codesign`. A separate entitlement
check found in `NTKComplicationPushManager` applies to its complication-push
listener and checks `aps-environment`; it is not evidence of collection-server
authorization. Nor does this show whether the persisted
representation can resolve a third-party custom subclass. The remaining safe
step is to determine whether a supported, non-system-modifying path can make a
custom bundle visible to a separate watchOS process, and to continue static
inspection of collection-server authorization. The original ClockFace attach
restriction still prevents direct observation; the disposable renamed host is
not equivalent, since its ClockKit identity gate already failed during scene
startup. Before any future persistence experiment, first identify a reversible
daemon operation or a complete simulator snapshot/restore procedure and verify
every consumer's class-loading path.

## Static evidence and limits

- NanoTimeKit disassembly: `sharedLibraryCollection` at 0xc2754;
  XPC initializer at 0xc27ca; XPC service connection at 0xc2935;
  descriptor add at 0xc5c63; selection update at 0x1731e; full collection load in the persistent collection at 0xc3e94; the XPC client proxy
  forwards it at 0xc1d99.
- Collection initialization sets the service and interface, resumes, and calls
  `_register`; mutation helpers use `_performOrEnqueueUpdateOfType:forFaceUUID:block:`
  and forward to `_serverProxy` methods.
- Addable collection initialization at 0xa39d7 uses `AddableFaces`, creates
  addable content and reads face preferences. Its data path is distinct from the
  XPC-backed library collection.
- Daemon Objective-C metadata identifies `NTKDCollectionCoordinator`,
  `NTKDCollectionClient`, `NTKDLibraryFacesCurator`, and `NTKDCollectionStore`.
  The listener accepts and configures XPC clients, registration checks out a store
  through the coordinator, and curator callbacks forward mutations to storage.
- Listener method: `listener:shouldAcceptNewConnection:` at 0xfd84.
  Registration dispatch: `registerForCollectionIdentifier:deviceUUID:withSeqId:`
  at 0x249c8; coordinator checkout at 0xff93. Curator add callback at 0x4885;
  helper that optionally selects after adding at 0x4a1c. Addresses are unslid
  x86_64 addresses from the installed `nanotimekitd` executable.
- The collection-server listener method queues setup and returns `YES`; its
  registration method dispatches store checkout, with no sender-entitlement
  branch visible in those inspected methods. The launchd plist exposes the
  collectionserver Mach service without a client allowlist key. `codesign` could
  not reliably decode the daemon's embedded entitlements. The entitlement check
  in the separate complication-push listener is unrelated. Global or
  per-operation authorization remains unverified. The
  manifest rejects duplicate
  UUIDs and records face styles. The add path serializes a face JSON
  representation. Store root is derived from `_NTKHomeDirectory()` and uses
  `CollectionStores/<device UUID>/<collection identifier>` (or the
  `GlobalStores` branch when device UUID is nil); each face uses
  `Faces/<UUID>/face.json`. Reload parses the JSON and calls the verified
  `NTKFace` reconstruction selector with the current device, migration, and
  invalid-style fallback options. Whether a custom subclass can resolve remains
  unverified. Selected UUID data uses `selected-uuid.string`.
- XPC interface allowlists full-collection replies as arrays of UUIDs and a
  dictionary mapping UUIDs to `NTKFaceInstanceDescriptor` objects. The face JSON
  factory consults the shared `NTKFaceBundleManager` by bundle identifier and
  device before using a bundle's `faceClass`; a cache miss invokes the manager
  loader's `loadFaceBundleWithIdentifier:`. Its directory list is based on
  `NTKBundleLoader rootDirectory` (the `IPHONE_SIMULATOR_ROOT` environment value)
  plus `/System/Library/NanoTimeKit/FaceBundles/`,
  with feature- and build-dependent AppleInternal/Argon roots. The normal list
  contains no arbitrary app container or `/tmp` path, so discovery of an
  app-local-only test bundle by the daemon is not supported by this trace.
- Launchd plist: service runs as `mobile`, with `POSIXSpawnType=Adaptive`,
  `RunAtLoad=true`, and the collectionserver Mach service enabled. The plist has
  no client allowlist key; this does not rule out launchd/XPC entitlement or
  code-signing checks enforced elsewhere.

All addresses refer to the installed watchOS 26.5 x86_64 simulator runtime.
The observations were originally derived from the historical `mrdka.txt`
disassembly dump. That generated dump has been removed from the clean repository;
the conclusions and relevant addresses are preserved in this document. No Apple
binary or header is required in the project.
