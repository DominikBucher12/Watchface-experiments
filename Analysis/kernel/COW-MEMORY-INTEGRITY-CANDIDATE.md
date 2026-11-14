# CVE-2026-112576 — copy-on-write candidate

## Public record

Apple describes CVE-2026-112576 as a kernel memory-integrity issue where an
application may cause unexpected changes to copy-on-write memory.  The fix is
present in watchOS 27.2.  No public proof of concept or subsystem-level
description was found as of 2026-11-13.

Primary advisory: <https://support.apple.com/en-us/149525>

## Local patch evidence

The strongest watchOS kernel candidate is the beta 2 to beta 3 change in
`vm_fault_internal`:

- 24B5089g: `sub_fffffe000adf972c`, 3903 instructions
- 24B5099f: `sub_fffffe000ad8dd00`, 3842 instructions
- operation similarity: 0.731
- both functions retain the `vm_fault.c` and `vm_fault_internal` strings and
  the same VM-fault diagnostics

Most callee fingerprints are unchanged and were reordered.  One common
52-instruction helper is outlined in beta 3 and receives an additional input
to a COW-related decision.  Its operation fingerprint is
`9f7ccce3e41a828f`; it remains identical in 24B5110a, 24B115, and 24B119.
This persistence supports a real behavioral change, but the outlining means
the helper alone is not proof of CVE attribution.

The first 18 instructions of that outlined block are now attributable more
precisely from their two call sites in `vm_fault_internal`:

- `x1` is the fault `pmap`;
- `x2` and `x3` are VM objects from the active fault/shadow chain;
- one object-flag case is accepted only when `pmap == kernel_pmap`;
- the same case was rejected before the beta 3 change.

This rules out a plain user-pmap fault as the missing condition.  The likely
trigger must cause an app-controlled COW object to be consumed through an
indirect kernel mapping.  A nearby 182-instruction routine is independently
identified by its embedded diagnostic as
`vm_map_create_private_symmetric_object`; it is relevant to named memory
entries but is not itself the COW-defeatured enforcement routine.

The earlier `VM-MAP-REMAP-CANDIDATE.md` flag-validation change remains a
separate, lower-confidence candidate and is not being treated as this fix.

## First device probe

`WatchFaceLab/COWMemoryProbe.c` uses only the public `vm_remap` interface:

1. allocate one anonymous page;
2. create a same-task remap with `copy=TRUE`;
3. write each branch in turn and verify isolation;
4. map one sandbox-local temporary file twice with `MAP_PRIVATE`;
5. write one file-backed mapping and verify the other mapping and file do not
   change;
6. release all resources.

The second bounded revision also creates a named memory entry with
`mach_make_memory_entry_64(..., MAP_MEM_VM_COPY, ...)`, maps that entry, and
creates a second mapping from the entry with `copy=TRUE`.  It checks isolation
between the source, direct entry mapping, and copied entry mapping.  This
reaches a distinct memory-entry/private-object COW fault path without racing
or stressing the device.
Direct Mach OOL messaging was rejected as a probe route because Xcode 27.2
marks `mach_msg` unavailable on watchOS; no private syscall substitute was
used.

The probe is bounded, single-threaded, and opt-in through
`WATCHFACELAB_COW_PROBE=1`.  A clean result establishes reachability and a
semantic baseline only.  It cannot by itself prove that CVE-2026-112576 was
triggered; a reproducer will require the missing prerequisite identified by
the changed `vm_fault_internal` decision.

## Physical-device baseline

On 2026-11-13 the probe ran once on Watch7,4 / N208bAP with watchOS 27.0.1
(24R365):

The final bounded run covered both anonymous `vm_remap(copy=TRUE)` and
file-backed `MAP_PRIVATE` COW:

```text
[cow-memory] allocate=0 remap=0 file=0 checks=0x3f page=16384
[cow-memory] explicit integrity result=0
```

All six isolation checks passed and the device remained stable.  This confirms
that both public COW paths are reachable, but neither simple one-page case
reproduces the issue.

The first memory-entry revision then ran once on the same device:

```text
[cow-memory] allocate=0 remap=0 file=0 entry-create=0 entry-map=0 checks=0x1ff page=16384
[cow-memory] explicit integrity result=0
```

All nine checks passed.  `MAP_MEM_VM_COPY` and mapping the returned memory
entry are therefore available to the sandboxed watch app, and their ordinary
single-page behavior is intact on 27.0.1.  This is a stronger reachability
baseline, but still does not exercise the `kernel_pmap`-only branch or
reproduce CVE-2026-112576.

The final named-entry COW revision also succeeded:

```text
[cow-memory] allocate=0 remap=0 file=0 entry-create=0 entry-map=0 entry-copy-map=0 checks=0x7ff page=16384
[cow-memory] explicit integrity result=0
```

All eleven checks passed, including writes through the `copy=TRUE` mapping in
both isolation directions.  This reaches an actual COW fault over a named
memory entry, but still faults through the app's user `pmap`; it remains a
negative baseline for the `kernel_pmap`-only condition.

## IOSurface-backed COW follow-up

A third bounded revision dynamically loaded the watchOS IOSurface framework
and attempted to create a one-page surface with the copied named-entry address
using the non-public `IOSurfaceAddress` property.  The probe separately checks
that surface creation and locking succeed, that `IOSurfaceGetBaseAddress()`
returns the exact COW mapping, and that a write through that address remains
isolated from both the source and direct named-entry mapping.

The confirmed physical-device result was:

```text
[cow-memory] allocate=0 remap=0 file=0 entry-create=0 entry-map=0 entry-copy-map=0 surface-create=0 surface-lock=0 checks=0x3fff page=16384
[cow-memory] explicit integrity result=0
```

All fourteen checks passed and the device remained stable.  This demonstrates
that watchOS 27.0.1 accepts an app-controlled named-entry COW mapping as the
backing address of a locked IOSurface.  It is the strongest current indirect
kernel-I/O reachability result, but without tracing the kernel fault it does
not prove that the changed `vm_fault_internal` helper observed
`pmap == kernel_pmap`, nor does the clean isolation result reproduce the CVE.

The final bounded variant called public `mlock()` on the copied named-entry
page before creating and locking the IOSurface.  This combines COW state,
wiring, and an IOSurface/IOMemoryDescriptor consumer while retaining the same
single-page, single-threaded operation:

```text
[cow-memory] allocate=0 remap=0 file=0 entry-create=0 entry-map=0 entry-copy-map=0 surface-create=0 surface-lock=0 mlock=0 checks=0x7fff page=16384
[cow-memory] explicit integrity result=0
```

All fifteen checks passed.  This rules out the ordinary one-page wired
IOSurface form as a reproducer on watchOS 27.0.1.  It strengthens the case
that the CVE requires another object-state prerequisite, ordering condition,
or a kernel consumer that actually faults the mapping through `kernel_pmap`.

`IOSurfacePrefetchPages` was then resolved dynamically on watchOS and invoked
before `mlock()` and `IOSurfaceLock()`, so the I/O framework touched the still
shared COW mapping before the explicit user wiring step:

```text
[cow-memory] allocate=0 remap=0 file=0 entry-create=0 entry-map=0 entry-copy-map=0 surface-create=0 surface-lock=0 surface-prefetch=0 mlock=0 checks=0xffff page=16384
[cow-memory] explicit integrity result=0
```

All sixteen checks passed.  The ordinary one-page prefetch/wire/lock/write
sequence therefore remains isolated.  Further device permutations are not
justified until the object flags read at offsets `0x75` and `0xa8` in the
outlined beta 3 helper are identified more precisely.

## Object flags and external vnode follow-up

The public XNU `vm_object` layout resolves the byte at object offset `0x75`:
bit 2 is `pager_trusted` and bit 4 is `internal`.  The outlined helper's
`0x14` mask therefore excludes trusted-pager and internal objects.  The byte
at object offset `0xa8` aligns with `wimg_bits`; public XNU initializes normal
objects with `VM_WIMG_USE_DEFAULT`.  This makes an anonymous named-entry
source a poor match for the new helper condition and motivates an external
vnode-backed object instead.

The probe was extended to create a named entry over a `MAP_SHARED` temporary
file mapping without `MAP_MEM_VM_COPY`, then create both direct and
`copy=TRUE` mappings from that entry.  The copied mapping was passed through
the same IOSurface prefetch, `mlock`, lock, and write sequence.  The confirmed
physical-device result was:

```text
[cow-memory] allocate=0 remap=0 file=0 entry-create=0 entry-map=0 entry-copy-map=0 surface-create=0 surface-lock=0 surface-prefetch=0 mlock=0 file-entry-create=0 file-entry-map=0 file-entry-copy-map=0 checks=0x3fffff page=16384
[cow-memory] explicit integrity result=0
```

All 22 checks passed, including preservation of the original `MAP_SHARED`
mapping, the direct named-entry mapping, and the underlying file after the
IOSurface-backed COW write.  The Stop-time LLDB `k`-packet warning occurred
after the result and was confined to host debugger detachment.

This negative result covers the strongest bounded external-object form now
supported by the evidence.  It does not establish that the fault used
`kernel_pmap`, and it does not disprove CVE-2026-112576.  Without a newly
identified kernel consumer or ordering condition, further local permutations
would be speculative; the candidate is therefore parked as not reproduced
on watchOS 27.0.1.
