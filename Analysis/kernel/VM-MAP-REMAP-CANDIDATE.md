# `vm_map_remap` beta change

Date: 2026-11-13

## Status

Deprioritized as an application trigger for CVE-2026-112474. The changed
branch is an internal remap mode, not a user-selectable public remap flag, and
the binary delta is argument/policy validation rather than visible object
lifetime management.

## Binary evidence

The function changes from `sub_fffffe000acd2190` (418 instructions) in
27.0.1 to `sub_fffffe000ae8873c` (467 instructions) in 27.2 beta 1. It changes
again from `sub_fffffe000ae14714` (467 instructions) in beta 2 to
`sub_fffffe000ada8bf8` (482 instructions) in beta 3. The shared diagnostic
string identifies `vm_map_remap`.

The beta-3 addition tests bit `0x100` in the low word of
`vm_map_kernel_flags_t`. In that branch it rejects the internal
`vmkf_remap_prot_copy` bit and accepts only current and maximum protections no
greater than `VM_PROT_READ`; other combinations return an argument/protection
error. No new retain, release, map lock, or deferred-free sequence is visible
in the added block.

Apple's public XNU headers leave low bit `0x100` unused and exclude it from
`VM_FLAGS_USER_REMAP`. The public `mach_vm_remap_external()` wrapper rejects
flags outside that mask before constructing `vm_map_kernel_flags_t`.
Consequently, a normal application cannot select the new branch through
`mach_vm_remap()`.

## Decision

A same-task `mach_vm_remap()` versus `mach_vm_deallocate()` race would exercise
the general function but not the changed beta-3 branch. Running it on the watch
would therefore be weak, potentially misleading evidence, so no device harness
was added.

Authoritative source references:

- <https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/vm_statistics.h>
- <https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/vm/vm_user.c>
