# ClockFace session bridge — prepared, not executed

This supersedes the loader-getter interception candidate in INTEGRATION-PROPOSAL.md.
The reviewed implementation is Experiments/MYClockFaceBridge.m. Building it has
not attached to, loaded code into, or modified ClockFace.

## Exact intervention

A separate signed dylib exports four explicitly invoked functions. There are no
constructors or automatic hooks. It accepts only the main thread of bundle
com.apple.clockface, x86_64 watch simulator, with NanoTimeKit image UUID
BA6B817D-D837-37DA-9BD1-DB2D1FC9CAD3. It requires the unmodified runtime class
NTKFaceBundleManager and exact encodings for the two overridden methods.

Preflight obtains the shared manager and validates those conditions. That may
initialize the native singleton if not already initialized; it is not a mutation-
free operation in the strict sense, but installs no interception.

Install loads our unique local bundle via a separate explicit-directory loader,
verifies its actual NSBundle identity/path, captures the native method IMPs, and
creates a no-ivar subclass named MYClockFaceSessionBundleManager. It then changes
only the captured shared manager instance's class using object_setClass. Other
instances and the original class's method implementations are untouched.

The subclass overrides only:

- enumerateFaceBundlesOnDevice:includingLegacy:withBlock: — forwards native
  enumeration, suppresses duplicate custom identifiers, and appends the local
  bundle when it is not device-restricted.
- faceBundleForBundleIdentifier:onDevice:forMigration: — returns the local bundle
  only for its exact identifier; forwards all other lookups. Device restriction
  is respected for normal lookup, with the verified migration bypass behavior.

The bridge leaves the original loader, its URL set, and manager cache dictionaries
in place. Custom lookup is answered by the bridge rather than inserted in native
progressive caches. Native forwarded calls can populate native caches normally.
This is a shared-discovery adapter, not filesystem discovery of a new system path.

Check counts the custom identifier in shared enumeration and verifies shared
identifier lookup returns the same local bundle. It does not create a global
gallery UI or add/select a library entry. Native gallery objects already created
before installation may not refresh; no unverified reload selector is sent.

Remove restores the original manager class, disables the bridge and releases its
bundle ownership. It refuses to overwrite an unexpected current class. The
registered subclass and loaded images stay until process exit. Original IMP
pointers/manager ownership remain valid for in-flight calls; already-dispatched
calls may complete with a retained custom bundle. Removal does not retract
existing custom gallery collections or assert that every app cache is cleared.

## Build/validation completed

```sh
bash Experiments/build-simulator.sh
```

Creates /tmp/WatchFaceLab26-NTK/MYClockFaceBridge.dylib alongside the existing
module and local FaceBundles directory. Keep their layout: the local bundle
resolves its module dependency through `@loader_path/../..`. No Apple code is copied.

Build passed with warnings as errors. Strict signature verification passed;
vtool reports WATCHOSSIMULATOR minimum/SDK 26.5; nm confirms the four exports.
All private selectors used were verified in installed metadata/disassembly.
No runtime installation, forwarding or rollback result is claimed yet.

## Execution sequence — requires separate approval

Use a separate LLDB session attached to ClockFace, not the WatchFaceLab debugger
and not Carousel. Confirm the executable/process before loading anything. If
attachment is denied or another debugger owns ClockFace, stop; do not patch policy.

Pause on the main thread, then run individually:

```lldb
thread select 1
expr -l objc++ -- (int)[NSThread isMainThread]
process load /tmp/WatchFaceLab26-NTK/MYClockFaceBridge.dylib
expr -l objc++ -u false -- (int)MYClockFaceBridgePreflight()
expr -l objc++ -u false -- (int)MYClockFaceBridgeInstall(@"/tmp/WatchFaceLab26-NTK/FaceBundles")
expr -l objc++ -u false -- (int)MYClockFaceBridgeCheck()
expr -l objc++ -u false -- (int)MYClockFaceBridgeRemove()
```

Only proceed on a true main-thread check, successful load, and return 1 at each
stage. The first run installs/checks/removes while paused; it does not leave the
intervention active for normal system UI interaction. No persistence calls occur.
With -u false, capture thread list, all-thread backtrace, frame and instruction
at any fault before continuing. Do not invoke more helpers inside a faulted
expression. Preserve the earlier intermittent app-local crash as an open issue.

After successful removal, verify the class-restored log, detach cleanly and let
ClockFace continue. If removal fails or the process state is uncertain, restart
ClockFace after recording the failure. Do not kill/restart Carousel as fallback.
No persistent custom face is added, so process exit clears the bridge and custom
classes without leaving a library entry dependent on them. Ordinary framework
logging/cache side effects can still occur. Removing temporary files is optional
only after the affected process exits.

## What approval covers

Attach LLDB to the simulator ClockFace app, load our signed bridge and own bundle/
module, and run preflight/install/check/remove as above. This temporarily changes
one system-process object's class; it is not a passive read-only inspection.
It excludes runtime edits, system binary patches, Carousel injection, persistent
face-library addition, and unverified gallery refresh/selection. Actual live
gallery visibility would follow only after this reversible bridge cycle works.

## Execution result: attach denied

User approval was received, and the prescribed ClockFace attach was attempted.
macOS rejected debugserver's task-control-port request before any bridge load.
The kernel reported that ClockFace is hardened and lacks get-task-allow. Thus
preflight/install/check/remove remain unexecuted in this host. No system-process
or runtime modification occurred and no bridge rollback was needed.

The installed-runtime attach path cannot proceed under the observed policy. Do
not interpret this approval as permission to re-sign ClockFace, alter its
entitlements, disable protections, or patch runtime files. A different research
execution strategy must be prepared/reviewed separately. See RESEARCH.md for
exact evidence and the UTC timestamp.
