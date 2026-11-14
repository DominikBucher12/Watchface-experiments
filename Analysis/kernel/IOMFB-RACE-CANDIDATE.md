# CVE-2026-112459 IOMobileFramebuffer race candidate

Target: physical Apple Watch Series 9 (`Watch7,4`) on watchOS 27.0.1
(`24R365`). The installed SDK is 27.2; the binary analyzed below comes from the
matching 27.0.1 DeviceSupport symbols.

## Verified reachability

The opt-in `WATCHFACELAB_IOMFB_OPEN_PROBE` loaded the private framework on the
physical watch. `IOMobileFramebufferGetMainDisplay` returned `0`, a non-null
framebuffer object, and `IOMobileFramebufferGetServiceObject` returned service
26371. The application remained alive. This probe did not begin a swap, submit
frame data, race calls, or attempt memory corruption.

This is a positive access gate for CVE-2026-112459: the third-party application
sandbox can reach the affected framework surface. It is not proof that this
specific device reproduces the vulnerability.

## 24R365 userspace ABI notes

Static disassembly of the matching arm64e framework shows:

| API | IOConnect operation | Relevant data |
| --- | --- | --- |
| `IOMobileFramebufferSwapBegin` | scalar selector `4` | returns a swap ID and clears a 0x6e0-byte userspace transaction buffer |
| `IOMobileFramebufferSwapEnd` | struct selector `5` | sends that 0x6e0-byte transaction buffer |
| `IOMobileFramebufferSwapCancel` | scalar selector `0x34` | sends one scalar swap ID |
| `IOMobileFramebufferSwapCancelAll` | scalar selector `0x51` | sends two scalars derived from the current task/thread identity |

The framework also contains the diagnostic string `IOMFB: ignoring cancelled
swap`. Together with Apple's description of improved state handling, this makes
the lifecycle around begin/end/cancel the leading hypothesis. It does not yet
identify which two operations must overlap or whether the vulnerable object is
owned by the userspace framework, the IOMFB user client, or a downstream display
component.

The public iOS firmware diff from 27.0 (24A437) to the first 27.2 beta
(24B5084k) narrows `com.apple.iokit.IOMobileGraphicsFamily` to two changed
functions. The relevant change is
`IOMobileFramebufferUserClient::stop(IOService*)`, whose reported size changes
from 580 to 572 bytes. The 27.0 to 27.0.1 firmware diff reports no kernel or
kext change, so 27.0.1 retains the pre-fix implementation. The repaired macOS
27.2 userspace Begin/End/Cancel wrappers are instruction-equivalent to the
24R365 watch wrappers, further locating the fix on the user-client teardown
side rather than in the framework wrapper.

## Next bounded step

The first sequential lifecycle is now verified on the physical watch:
`SwapBegin` returned `0` with swap ID 1237807 and `SwapCancel` returned `0` for
that ID. The app and device stayed stable.

An explicitly owned client is also verified: `IOMobileFramebufferOpen` returned
`0` for service 26883, `SwapBegin` returned ID 1238384, `SwapCancel` returned
`0`, and releasing the object cleanly closed the client. This establishes a
controllable `IOMobileFramebufferUserClient::stop` path without concurrency.

The first attributed race pair has now been bounded. One one-shot run and a
second matrix of 128 independent raw clients overlapped selector `0x34`
(`SwapCancel`) with `IOServiceClose`. All 128 close calls succeeded; 126 cancel
calls succeeded and two returned a non-success result. There was no app crash,
watch reboot, or other corruption signal. The two cancel misses are consistent
with close winning the connection-lifetime race. This exact conflict is parked
after two negative attempts.

1. Run one sequential `Begin -> End` lifecycle with the framework-owned zeroed
   transaction buffer to determine whether an empty transaction is valid on
   this display path.
2. Recover the pre-fix and patched `IOMobileFramebufferUserClient::stop`
   implementations to identify the exact state or resource whose ordering
   changed.
3. Do not repeat the `Cancel`/close pair. Consider `End`/teardown concurrency
   only if the sequential lifecycle is accepted and the state-machine evidence
   supports that distinct transition.

The opt-in sequential end harness subsequently ran on the physical watch. An
explicitly owned client opened service 27907, `SwapBegin` returned swap ID
1243170, `SwapEnd` returned `0`, and releasing the client completed cleanly.
The app and watch remained stable. This verifies that the empty transaction is
accepted and that `End` is a reachable transition distinct from the parked
cancel/close pair. The scheme gate was returned to disabled after the run.

A subsequent one-shot raw-client overlap raced selector 5 against
`IOServiceClose` using the verified zeroed 0x6e0 transaction layout and swap ID
offset 0x98. Begin returned swap ID 1243976, and both End and close returned
`0`; the app and watch stayed stable.

The capped follow-up used 64 independent raw clients. All 64 close calls
succeeded; 63 concurrent End calls succeeded and one returned `0xe00002bc`,
which the installed SDK defines as the generic `kIOReturnError`. There was no
app crash, watch reboot, or other corruption signal. The one-shot and matrix
therefore park this exact End/teardown pair after two negative attempts, just
as the earlier Cancel/teardown pair is parked. A further device run requires a
new premise from the pre/post-fix `stop` instructions or evidence for a
different state/resource; selector timing alone is insufficient.

The launch-scheme opt-in must remain disabled outside an explicit device run.
