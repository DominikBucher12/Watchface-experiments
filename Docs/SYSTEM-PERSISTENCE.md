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
a store directory. The binary also contains the `CollectionStores` directory
component, but this pass has not established the complete absolute backing path.
The inspected add path persists the representation; it does not itself show the
daemon reconstructing an `NTKFace` from the custom class.

This static pass has not identified a sender authorization rule or the complete
durable backing path. Nor does it show whether the persisted descriptor can be
reconstructed by an unrelated client process. The next safe step is to finish
tracing store initialization and the client-side descriptor reconstruction path,
then inspect the normal ClockFace registration/load path using only read-only
observation. The original ClockFace attach restriction still prevents direct
observation; the disposable renamed host is not equivalent, since its ClockKit
identity gate already failed during scene startup. Before any future persistence
experiment, first identify a reversible daemon operation or a complete simulator
snapshot/restore procedure and verify every consumer's class-loading path.

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
- The listener method itself has no visible sender identity check. Global or
  per-operation authorization remains unverified. The manifest rejects duplicate
  UUIDs and records face styles. The add path serializes a face JSON
  representation. Complete durable path and cross-process descriptor
  reconstruction remain unverified. Identified path components are
  `CollectionStores`, `Faces`, and the per-face UUID; selected UUID data uses
  `selected-uuid.string`.

All addresses refer to the installed watchOS 26.5 x86_64 simulator runtime.
Historical `mrdka.txt` is used only as a disassembly text file; no Apple binary or
header was copied into the project.
