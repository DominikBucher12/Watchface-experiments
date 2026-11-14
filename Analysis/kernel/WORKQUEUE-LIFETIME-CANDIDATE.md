# Reclassified process-workqueue lifetime candidate

Target: physical Apple Watch Series 9 (`Watch7,4`) on watchOS 27.0.1
(`24R365`). This is a static candidate for one of the Kernel UAF fixes in
watchOS 27.2, not confirmed CVE attribution.

## Binary delta

Between 27.2 beta 3 (`24B5099f`) and beta 4 (`24B5110a`), a workqueue
information helper grows from 85 to 202 instructions. The old function at
`0xfffffe000b1b4638` loads a subordinate object from offset `0x638`, locks the
object, copies four result words, and unlocks it. The new function at
`0xfffffe000b1b8674` additionally:

- serializes access to the parent before loading the subordinate object;
- increments a reference count on that subordinate object;
- releases the parent serialization before copying the information;
- decrements the reference afterwards and performs final cleanup when it was
  the last reference.

That is concrete lifetime hardening around a read-only information path.
Call-site and field mapping after the physical access test identifies the
parent as a `proc` and the subordinate at `0x638` as `p_wqptr`, a process
workqueue. The 16-byte result exactly matches `struct proc_workqueueinfo`.
The large caller serializes it as `TASK_CRASHINFO_WORKQUEUEINFO` (`0x817`), and
the small wrapper is `proc_pidworkqueueinfo`, which zeroes the result and maps
failure to `ESRCH` (`3`). The changed helper is `fill_procworkqueue`.

The old implementation loads `p_wqptr`, then try-locks and reads it without
holding a lifetime reference. Process exit atomically clears `p_wqptr` and
releases the workqueue's last reference. The beta4 implementation instead
locks the proc, loads and retains the workqueue, unlocks the proc, reads it,
then releases the workqueue. This is concrete UAF hardening around
`fill_procworkqueue`; the exact CVE attribution remains unknown.

## Bounded validation

`WorkqueueInfoProbe.c` provides an opt-in access gate. Because the watchOS SDK
does not ship `libproc.h`, it resolves `proc_pidinfo` from the process at
runtime, then requests exactly one `PROC_PIDWORKQUEUEINFO` record for its own
PID. It performs no exit, concurrency, spray, malformed input, or
memory-corruption stage. Success establishes only that a normally signed watch
app reaches the self-read path.

The earlier `TCPInfoProbe.c` run was based on a false attribution and is kept
only as a negative research record. It does not exercise `fill_procworkqueue`.

### Physical access result

On `Watch7,4` running watchOS 27.0.1 (`24R365`), the first call from app
initialization returned `length=0`, `error=3` (`ESRCH`). At that point the
process did not yet have a workqueue, so this was not a sandbox denial. Running
the same single read from a global dispatch worker returned:

```text
[workqueue-info] self pid=4114 length=16 error=0 threads=1 running=1 blocked=0 state=0x0
[workqueue-info] explicit access result=0
```

The app and watch remained stable. This confirms that a normally signed,
sandboxed watch app can reach `proc_pidworkqueueinfo` for its own live process.
It does not demonstrate a UAF, cross-process observation, sandbox escape, or
privilege escalation. The scheme gate was disabled after this one successful
run.

Do not implement a TCP close/read overlap. The public read candidate is
`proc_pidinfo(pid, PROC_PIDWORKQUEUEINFO, ...)`, while the destructive side is
the target process's workqueue teardown during exit. First establish whether a
normally signed watch app can query its own workqueue and a separate process it
is allowed to observe. The app cannot race its own final exit from userspace,
so a distinct observable child/extension process or an independently triggered
crash-info path is a prerequisite for a bounded race. The scheme gate must
otherwise stay disabled.

## Rejected TCP access result

On `Watch7,4` running watchOS 27.0.1 (`24R365`), a normally signed WatchFaceLab process created one loopback TCP connection. `getsockopt(IPPROTO_TCP, TCP_CONNECTION_INFO)` succeeded on both endpoints and returned 112-byte structures with TCP state 4. The app and device stayed stable.

This confirms public, sandbox-reachable access to a connection-info export
path. Subsequent call-site mapping shows that it does **not** validate the
reclassified process-workqueue helper. The TCP device gate is disabled after
the one sequential run.

## Source correspondence

- XNU's `proc_pidworkqueueinfo` zeroes the 16-byte record, calls
  `fill_procworkqueue`, and maps any failure to `ESRCH`.
- `fill_procworkqueue` loads `p_wqptr`, try-locks the workqueue, and fills the
  same four fields observed in the old binary.
- `workq_exit` atomically clears `p_wqptr` and releases the workqueue. This is
  the freeing side protected by the beta4 retain/release.
- `TASK_CRASHINFO_WORKQUEUEINFO` is defined as `0x817`, matching the large
  serializer caller.

Authoritative source references:

- https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/proc_info.c
- https://github.com/apple-oss-distributions/xnu/blob/main/bsd/pthread/pthread_workqueue.c
- https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/proc_info.h
- https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kcdata.h

