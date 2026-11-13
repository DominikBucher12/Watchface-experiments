# `tty_ptmx` knote-detach candidate for CVE-2026-112474

Date: 2026-11-13

## Status

This is a strong cross-build UAF-hardening candidate, not a confirmed CVE
attribution. Apple's advisory does not name the affected Kernel subsystem and
several Kernel UAF fixes shipped in the same release. A normal third-party
watchOS application cannot reach the PTY allocation entry point on the tested
watchOS 27.0.1 device because the application sandbox rejects it with `EPERM`.

The reporter credit increases, but does not settle, the confidence: the two
researchers credited for CVE-2026-112474 are also among the reporters for
CVE-2026-112514 in the same advisory. The PTY path is directly reachable by an
app, which fits 112474's stated impact better than 112514's generic
"attacker" wording, but other app-reachable Kernel UAF entries were fixed in
the same train as well.

## Binary evidence

The material change first appears between iOS 27.2 beta 2 (`24B5089g`, XNU
`13432.40.162~93`) and beta 3 (`24B5099f`, XNU
`13432.40.177.0.3~16`). The final 27.2 release is identical to the RC at the
function-fingerprint level.

The changed function contains the panic string:

```text
invalid knote %p detach, filter: %d @%s:%d | tty_ptmx.c
```

The beta-2 implementation has 64 instructions. It authenticates the knote hook,
loads the associated `tty`, locks it, then removes the knote from the read or
write list through the originally captured PTY object.

The beta-3 implementation has 132 instructions and adds three relevant guards:

1. It accepts a null knote hook before pointer authentication.
2. It reloads the hook after acquiring the tty lock.
3. It takes the global PTY-table lock, derives the device minor, and looks up
   the current PTY object before unlinking the knote.

This is consistent with preventing a stale `ptmx_ioctl` pointer from being used
during concurrent PTY teardown and knote detach. The two disassemblies are in
`tty-knote-detach-24B5089g.txt` and `tty-knote-detach-24B5099f.txt`.

Apple's published `tty_ptmx.c` identifies this path as
`ptmx_kqops_detach()`: `ptmx_kqfilter()` stores a `ptmx_ioctl` pointer in the
knote hook, and the detach callback uses the embedded tty lock and removes the
knote from the master-side read/write lists. The published source is useful for
naming the binary path, but is older than the beta-3 implementation and does
not itself contain the hardening seen in the release binary.

## Safe trigger model

`Experiments/tty-ptmx-knote-probe.c` uses only public APIs:

1. open a PTY master/slave pair;
2. attach `EVFILT_READ` and `EVFILT_WRITE` knotes to the master;
3. race master `close()` against `EV_DELETE` on the kqueue;
4. join both workers and close the remaining descriptors.

The default mode performs the same operations sequentially. The race requires
an explicit `--race`, is capped at 4,096 rounds, and performs no heap spray,
memory grooming, private API calls, or corruption attempt.

## Local verification

The source was verified without a device:

- host build with Clang 21 and `-Wall -Wextra -Werror`;
- 256 sequential PTY/kqueue rounds under AddressSanitizer and UBSan, all
  completed with successful knote deletion and no reported error;
- static analyzer with no findings;
- watchOS compile for `arm64-apple-watchos27.0` against the installed watchOS
  27.0 SDK, producing a Mach-O arm64 object.

The `--race` mode was not run on the host or any watch during this offline
phase.

## Physical-watch reachability result

The harness was integrated into `WatchFaceLab`, signed through Xcode 27.2, and
launched on `Watch7,4` running build `24R365` (watchOS 27.0.1, XNU
`13432.4.5~1`). The first 64-round attempt reported 64 setup failures and never
entered the race. A second one-round diagnostic isolated the first failing
operation:

```text
[tty-ptmx] begin mode=sequential requested=1
[tty-ptmx] setup stage=posix_openpt error=1
[tty-ptmx] end mode=sequential requested=1 completed=0 setup_failed=1 ...
```

Error 1 is `EPERM`. The generated provisioning entitlements contain the
application identifier, team identifier, and `get-task-allow`; no PTY-specific
entitlement is present in the watchOS SDK or Xcode installation. No guessed
private entitlement or security-setting change was attempted.

Consequently, this path is not a viable PoC entry from a regularly provisioned
watch application. The result does not invalidate the binary UAF hardening: it
only establishes that this process class cannot allocate the required PTY
master on the tested device.

## Remaining attribution gap

A crash or sanitizer report in `ptmx_kqops_detach` from a process legitimately
permitted to allocate PTYs would strongly validate this trigger and candidate.
It still would not, by itself, prove that Apple assigned this exact fix
CVE-2026-112474. That needs an Apple or researcher mapping, or exclusive
correlation against the other Kernel UAF entries fixed in the same train.

Authoritative references:

- Apple watchOS 27.2 security content:
  <https://support.apple.com/en-us/149525>
- Apple XNU `tty_ptmx.c` source:
  <https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/tty_ptmx.c>
