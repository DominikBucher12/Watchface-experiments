# watchOS 27.0.1 root-execution CVE candidates

Target: Apple Watch Series 9 (`Watch7,4`) running watchOS 27.0.1
(`24R365`). These are research candidates, not demonstrated watchOS jailbreaks.

| Priority | CVE | Why it matters | Current reality |
| --- | --- | --- | --- |
| 1 | **CVE-2022-26704** | Spotlight symlink flaw explicitly described as allowing elevated privileges. The original macOS research achieved unprivileged-to-root escalation, and Apple lists the same CVE as fixed in watchOS 27.2. | Best direct root-userland lead, but the macOS exploit will not automatically port. First verify Spotlight reachability and patch differences on watchOS. |
| 2 | **CVE-2026-112474** | Kernel use-after-free; Apple says an app may write kernel memory. | Excellent kernel-primitive candidate; no credible public watchOS proof of concept was found. |
| 2 | **CVE-2026-84495** | Another kernel use-after-free with the same stated kernel-write impact. | Equally promising, but publicly undocumented beyond Apple's advisory. |
| 3 | **CVE-2026-112665** | Discloses the kernel memory layout. | Likely a KASLR-leak helper, not privilege escalation alone. |
| 3 | **CVE-2026-113910** | An application may disclose kernel memory. | Potential information-leak helper; the repository contains a probe, but no usable leak is documented. |
| 4 | **CVE-2026-112477** | Reachable IOSurface race that may corrupt kernel memory. | The repository's research localized and reached it, but did not reproduce corruption; therefore it is not presently usable. |
| 4 | **CVE-2026-112459** | IOMobileFrameBuffer race with possible kernel corruption. | Worth patch-diffing for sandbox reachability; no public exploit details are available. |
| 5 | **CVE-2026-65350**, **CVE-2026-112679**, **CVE-2026-112517** | Kernel use-after-free bugs with possible kernel corruption. | Possible alternatives, but Apple's published information is insufficient to rank exploitability. |

## Sources

- [Apple: security content of watchOS 27.2](https://support.apple.com/en-asia/149525)
- [CVE-2022-26704 Spotlight research](https://gergelykalman.com/no-CVE-batsignal-a-macos-lpe.html)

