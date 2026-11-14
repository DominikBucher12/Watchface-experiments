# BPF `BIOCSETUP` detach-state candidate

Date: 2026-11-13

## Status

Promising beta-1 lifetime candidate, not confirmed attribution to
CVE-2026-112474. The access-only probe ran on the physical watch, but a
normally signed third-party application could not open a BPF descriptor, so
the `BIOCSETUP` path is not reachable from this process class.

## Binary evidence

The changed function grows from `sub_fffffe000ae42030` (686 instructions) in
27.0.1 to `sub_fffffe000affb328` (697 instructions) in 27.2 beta 1, with
instruction-shape similarity 0.863341. Its strings identify `bpf.c`,
`bpf_setup`, `bpf_release_d`, and the source/destination validation performed
for `BIOCSETUP`.

The patched binary adds two distinct rejection diagnostics:

```text
%s: d_from detach pending error %d
%s: d_to detach pending error %d
```

The older binary already rejects closing or detached descriptors. The new
checks specifically cover the intermediate detach-pending state for both BPF
descriptors before setup copies buffers and attaches the destination. This is
consistent with closing a state-transition window in which `BIOCSETUP` could
operate on an object being detached. Static evidence alone does not prove a
UAF or map the change to this CVE.

## Reachability gate

`WatchFaceLab/BPFOpenProbe.c` only calls `open()` on `/dev/bpf` and
`/dev/bpf0` through `/dev/bpf3`, prints the result, and immediately closes a
successful descriptor. It is explicitly gated by
`WATCHFACELAB_BPF_OPEN_PROBE=1`; the normal app launch does nothing.

No `BIOCSETUP` ioctl or race will be added unless a signed third-party watch
application can open at least two BPF descriptors. The installed watchOS SDK
does not expose the private `BIOCSETUP` structure, so any later harness must
first verify the ABI against authoritative XNU source rather than guess it.

## Physical-device reachability result

Xcode 27.2 built, signed, installed, and launched the gated probe on the
unchanged `Watch7,4` running build `24R365` (watchOS 27.0.1). The bounded run
reported:

```text
[bpf-open] path=/dev/bpf error=2 (No such file or directory)
[bpf-open] path=/dev/bpf0 error=1 (Operation not permitted)
[bpf-open] explicit accessibility result=1
```

The app and watch remained running. `/dev/bpf` was absent and `/dev/bpf0`
was denied with `EPERM`; the probe stopped at that first permission failure.
No ioctl or race was attempted. This is a sandbox reachability failure, not a
negative result for the suspected kernel lifetime bug. Per the bounded-testing
rule, this path will not be repeated from the same process class.

Authoritative source reference:

- <https://github.com/apple-oss-distributions/xnu/blob/main/bsd/net/bpf.c>
