# Unix-domain `SCM_RIGHTS` lifetime candidate

Date: 2026-11-13

## Status

This is an app-reachable beta-1 candidate, not confirmed attribution to
CVE-2026-112474. The changed kernel function is the Unix-domain ancillary-data
internalization path (`unp_internalize`), reached when `sendmsg()` transfers
file descriptors with `SCM_RIGHTS`.

## Binary evidence

Between 27.0.1 (`24A446`) and 27.2 beta 1 (`24B5084k`), the function changes
from `sub_fffffe000b1b3998` (833 instructions) to
`sub_fffffe000b371024` (855 instructions), with instruction-shape similarity
0.957346. Both versions reference `fg_insertuipc`, `FG_INSMSGQ`, and
`uipc_usrreq.c` assertions, which identifies the file-descriptor
internalization path rather than the later socket send routine.

In the old binary, the descriptor lookup result's `fileglob` pointer is
authenticated conditionally and then stored into the internalized descriptor
array. The new binary adds a null check before the store, routes failure into
the existing cleanup/error path, and re-signs the authenticated pointer using
the destination slot as its pointer-authentication discriminator. The new
sequence around the store is:

```text
ldr     x16, [x26]
cbz     x16, <failure>
autda   x16, x23
movk    x17, #...        ; destination-derived discriminator
pacda   x16, x17
b       <store>
```

This is consistent with hardening descriptor close/reuse during ancillary
data internalization. Pointer-authentication changes can also be correctness
hardening rather than the advisory's UAF fix, so the binary change alone does
not settle the CVE mapping.

A companion change in `fg_removeuipc` has the same shape: the new code
authenticates a `fileglob` pointer with the source-slot discriminator and
re-signs it for the destination slot. That receive-side symmetry makes a broad
PAC storage-correctness update more likely than a narrowly targeted lifetime
fix. Together with the successful bounded replacement race below, this lowers
the attribution confidence for CVE-2026-112474; it does not make the old code
safe or disprove a rarer race.

## Bounded trigger

`Experiments/unix-scm-rights-probe.c` uses public APIs only. It creates an
`AF_UNIX` datagram socket pair and a pipe, then transfers the pipe descriptor
with `SCM_RIGHTS`. Sequential mode sends, receives, and closes in order. Race
mode starts `sendmsg()` and `close()` together and accepts either a successful
transfer or `EBADF`.

The probe is capped at 4,096 host rounds and 256 watch rounds. It has no heap
spray, unbounded descriptor churn, memory grooming, private API, or corruption
stage. Watch integration is explicitly gated by the
`WATCHFACELAB_SCM_RIGHTS_PROBE` environment variable.

## Local verification

- 256 sequential and 512 race rounds completed under AddressSanitizer and
  UBSan with no report; successful transfers produced valid received FDs and
  losing races returned `EBADF`.
- The source compiles cleanly with `-Wall -Wextra -Werror` for
  `arm64-apple-watchos27.0` against the installed watchOS 27.0 SDK.
- The Xcode project parses successfully after adding the source and header.

## Validation criterion

A normal successful/`EBADF` result only proves reachability and safe race
behavior. A panic stack in the mapped `unp_internalize`/`fg_insertuipc` path
would validate the trigger candidate. Even that would still need independent
mapping to distinguish CVE-2026-112474 from the other Kernel UAF entries in
the same advisory.

## Physical-watch result

The app was built, signed, installed, and launched through Xcode 27.2 on the
unchanged `Watch7,4` running build `24R365` (watchOS 27.0.1, XNU
`13432.4.5~1`). A one-shot 64-round race completed without a process or system
crash:

```text
[scm-rights] mode=race requested=64 completed=64 setup_failed=0 send_ok=56 send_ebadf=8 send_other=0 close_ok=64 close_ebadf=0 recv_ok=56 recv_failed=0
[scm-rights] one-shot result=0
```

This proves that the stock watch application sandbox can reach
`SCM_RIGHTS` internalization and race descriptor close against it. The two
observed outcomes are consistent with the close either losing (`send_ok`) or
winning (`EBADF`). It did not reproduce a fault in 64 rounds, so it does not
validate the UAF or the CVE attribution. The temporary automatic arm was
removed from the source after the run; future runs require the explicit
environment gate.

### Descriptor-replacement refinement

A second mode replaces the transferred descriptor atomically with `dup2()`
while `sendmsg()` internalizes the same numeric FD. The receiver classifies
the resulting descriptor with `fstat()`: the original object is a pipe and
the replacement is a Unix stream socket. This directly demonstrates both
sides of descriptor lookup/replacement rather than merely observing whether
`close()` won.

Host verification completed 1,024 replacement-race rounds under ASan/UBSan:
55 received the original pipe, 574 received the replacement socket, and 395
returned `EBADF`; no unexpected result or sanitizer report occurred.

The one-shot physical-watch run completed all 256 capped rounds:

```text
[scm-rights] mode=replace-race requested=256 completed=256 setup_failed=0 send_ok=248 send_ebadf=8 send_other=0 close_ok=0 close_ebadf=0 replace_ok=256 replace_failed=0 recv_ok=248 recv_failed=0 recv_fifo=199 recv_socket=49 recv_other=0
[scm-rights] replace one-shot result=0
```

The watch stayed running. Receiving both 199 original and 49 replacement
objects proves that the harness crosses the intended replacement window. The
absence of a fault remains a negative bounded result, not evidence that the
27.0.1 function is free of a rarer lifetime defect. The installed diagnostic
build has a persisted one-shot marker, and the automatic arm was removed from
repository source after the run.

Authoritative source reference:

- <https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/uipc_usrreq.c>

