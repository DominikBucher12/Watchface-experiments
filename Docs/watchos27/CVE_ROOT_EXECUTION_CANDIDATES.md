# watchOS 27.0.1 root-execution CVE candidates

Target: Apple Watch Series 9 (`Watch7,4`) running watchOS 27.0.1
(`24R365`). These are research candidates, not demonstrated watchOS jailbreaks.

| Priority | CVE | Why it matters | Current reality |
| --- | --- | --- | --- |
| 1 | **CVE-2026-112459** | IOMobileFrameBuffer race with possible kernel-memory corruption. | The surface, owned client, and Begin/Cancel/End lifecycles are reachable, and firmware diffing attributes the fix to `IOMobileFramebufferUserClient::stop`. Both Cancel/close and End/close were tested as a one-shot plus a bounded independent-client matrix without a crash, reboot, or corruption signal. Park both exact pairs; the next test requires patched `stop` disassembly or evidence for a different state/resource. |
| 2 | **CVE-2022-26704** | Spotlight symlink flaw explicitly described as allowing elevated privileges. The original macOS research achieved unprivileged-to-root escalation, and Apple lists the same CVE as fixed in watchOS 27.2. | Spotlight components are present, but the known trigger requires attacker-controlled mounted-volume metadata/cache entries. The watch image instead exposes a protected `/private/var/db/Spotlight-V100/%s-%s` root; a stock app cannot establish the required mount or precreate the symlink. Park the published trigger unless a watch-specific path is found. |
| 3 | **CVE-2026-112474** | Kernel use-after-free; Apple says an app may write kernel memory. | Excellent kernel-primitive candidate; no credible public watchOS proof of concept was found. |
| 3 | **CVE-2026-84495** | Another kernel use-after-free with the same stated kernel-write impact. | Equally promising, but publicly undocumented beyond Apple's advisory. |
| 3 | **CVE-2026-112665** | Discloses the kernel memory layout. | The bounded `mach_port_kobject` gate reached five legitimate port types on physical `Watch7,4` / `24R365`; all returned a zero address. This exact route is parked as not reproduced. |
| 3 | **CVE-2026-113910** | An application may disclose kernel memory. | The physical inline-zlib decmpfs test activated successfully and zero-filled all 64,512 bytes beyond the 1024-byte stream output; no other bytes or pointer-like words appeared. This exact route is parked as not reproduced. |
| 3 | **CVE-2026-112466** | AVEVideoEncoder OOB read may disclose kernel memory. | A no-frame physical H.264 capability query reached the generic H.264 encoder and returned 134 properties. A bounded name inventory found eight ordinary encoder/DPB keys but no MCTF, LRME, or temporal-layer property. The iPhone temporal-layer route is parked for this watch surface; no CVE trigger is attributed. |
| 4 | **CVE-2026-112477** | Reachable IOSurface race that may corrupt kernel memory. | The repository's research localized and reached it, but did not reproduce corruption; therefore it is not presently usable. |
| 5 | **CVE-2026-65350**, **CVE-2026-112679**, **CVE-2026-112517** | Kernel use-after-free bugs with possible kernel corruption. | Possible alternatives, but Apple's published information is insufficient to rank exploitability. |

## Unattributed patch candidates

- A beta3-to-beta4 delta fixes a process-workqueue lifetime window in
  `fill_procworkqueue`. The old code reads `proc->p_wqptr` without retaining it;
  the new code retains it under the proc lock before reading. The public read
  candidate is `proc_pidinfo(..., PROC_PIDWORKQUEUEINFO, ...)`, and crash-info
  emits the same 16-byte structure as `TASK_CRASHINFO_WORKQUEUEINFO`. Keep this
  unattributed until a stock watch app can query a separate process whose exit
  it controls or until the internal crash-info path supplies both sides.

## Sources

- [Apple: security content of watchOS 27.2](https://support.apple.com/en-asia/149525)
- [CVE-2022-26704 Spotlight research](https://gergelykalman.com/no-CVE-batsignal-a-macos-lpe.html)

