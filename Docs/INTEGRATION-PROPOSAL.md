# Next phase: session-only system discovery

Status: proposal only. No system process attached or altered, no shared manager
changed, no runtime file copied/patched, and no persistent face added.

## We have enough local evidence

Stop extending local PoC checks. Completed: cold bundle discovery; identified
style-44 face creation; native JSON/descriptor restoration; restored-model native
presentation, activation and dismissal; local gallery methods; and one clean
native asynchronous gallery collection cycle. The earlier intermittent
EXC_BAD_ACCESS remains unexplained and must stay in the research record.

There are two integration gates, not another open-ended local test sequence:

1. Shared discovery and the system gallery see the custom bundle in one session.
2. Library addition/selection and restoration resolve the bundle across all
   participating processes. This requires a separate persistence design.

## New read-only evidence

`+[NTKGalleryCollection galleryCollectionsForDevice:]` references the shared
NTKFaceBundleManager at 0x2cdb0d and its bundle enumeration at 0x2cdb9e. Its block
checks a nonempty gallery title and `_isInternalOnlyForDevice:` and constructs
NTKFacesBundleArrayGalleryCollection at 0x2ce4eb. The base internal-only method at
0x11d7c6 returns NO, inherited by MYCustomFace. Other root/hardware/ordering logic
exists; these observations are not proof of full eligibility in ClockFace.

Installed metadata confirms NTKFaceBundleLoader `_urls` is an NSSet and manager
`_loader` is an NTKFaceBundleLoader. The manager exposes a readonly loader property,
not a verified setter. Any future bridge must preserve all current URL entries,
including runtime/Argon paths, instead of replacing them with just our directory.
Use runtime ivar lookup for inspection; do not hardcode the observed offset 40.

`-[NTKFaceBundleManager _resetCaches]` at 0x165d8c clears only `_cachedLookup` under
its lock. It does NOT clear `_progressiveBundleIDLookup` or
`_progressiveStyleLookup`. It is not a complete rollback operation.

`-[NTKPersistentFaceCollection _initWithCollectionIdentifier:deviceUUID:]` at
0xc2883 creates/configures/resumes an NSXPCConnection and registers with a server.
Therefore adding an in-process face or placing a bundle in one client's loader
is insufficient evidence for safe persistent library installation.

## Proposed first system experiment

Prepare a separate opt-in bridge, restricted to the simulator ClockFace process
(identifier com.apple.clockface), with version/architecture checks. Do not reuse
the WatchFaceLab-only helper entry points as though their guards permit this.
Keep the current working app and artifacts available as a baseline.

The bridge should temporarily expose a new loader containing the original
loader's URL set plus the external directory of our own signed bundle. One
candidate is a tightly scoped interception of the verified manager loader getter,
returning the alternate loader only for the captured shared-manager instance and
forwarding other receivers to the original implementation. Exact method encodings,
existing interception state and cache ownership must be checked before producing
executable install/remove functions. Do not patch framework machine code or write
private ivars by guessed offset. This is a proposed in-memory intervention, not
an already implemented or validated mechanism.

Proposed execution sequence:

1. Read-only ClockFace preflight: confirm process identity, loaded NTK image UUID,
   debugger attach policy, live shared-manager loader/getter signatures, URL set,
   and gallery ownership. Detach on policy/identity mismatch; do not escalate to
   Carousel injection or runtime patching as a fallback.
2. Explicitly load only our own bridge/module and signed local bundle; no Apple
   code is copied. Retain the original loader, getter implementation, and relevant
   manager cache state for comparison and rollback. Abort on unexpected layout.
3. Enable the temporary loader intervention, refresh only the necessary verified
   discovery state, and inspect shared enumeration/gallery construction for the
   unique identifier. Do not add/select a persistent library face in this run.
4. If the active gallery is already constructed, first inspect the live refresh
   path. Do not send guessed reload selectors or broad system notifications.
5. Remove the intervention and verify original discovery behavior. Restart the
   ClockFace app process if caches cannot be restored confidently; do not restart
   or modify Carousel. Keep artifacts until the process exits because Objective-C
   images are not safely unloaded.

## Rollback and limits

Primary rollback is removal of the scoped getter interception, restoration of the
original loader/discovery state using verified ownership/locking, and gallery
refresh through a verified path. Process restart is the fallback because no
persistent library entry is added. It also clears loaded custom Objective-C
classes. Do not claim `_resetCaches` alone clears every lookup.

Our experiment files remain outside the runtime under /tmp. Removing those files
is optional after the affected process exits. No simulator runtime snapshot or
binary needs restoration because none is modified. Ordinary framework logging
or cache side effects may occur during gallery operations; a session-only bridge
does not imply every framework operation is free of incidental disk writes.

A successful first gate means shared/session gallery discovery, not a durable
installed face. The second gate must identify server ownership, reconstructor
processes, storage and rollback of a uniquely identified entry before any library
mutation. Avoid creating a persistent entry that becomes unresolvable on restart.

## Authorization boundary

The user's original instructions explicitly excluded system process injection,
system binary patching and runtime modification at this stage. The proposed
ClockFace attach/load/getter intervention crosses from app-local research into a
system process. Prepare and review the bridge/preflight/rollback implementation
before requesting specific approval to execute it. Do not interpret a passing
local test or a generic request to continue research as approval for that action.
