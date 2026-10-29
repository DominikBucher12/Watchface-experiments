# watchOS 27 kernel-CVE research branch

This branch is the isolated workspace for the following public watchOS 27.2
kernel advisories on an owned Apple Watch Series 9:

| Order | CVE | Apple's published impact | Initial evidence goal |
| --- | --- | --- | --- |
| 1 | CVE-2026-112665 | An app may determine kernel memory layout | Locate the fixed code path and determine whether a normal app can reach it. |
| 2 | CVE-2026-112576 | An app may unexpectedly change copy-on-write memory | Locate the VM/COW fix and design an app-owned-memory invariant test. |
| 3 | CVE-2026-84495 | An app may terminate the system or write kernel memory | Identify the patched interface before considering a bounded crash reproducer. |
| 4 | CVE-2026-112474 | An app may terminate the system or write kernel memory | Identify the patched interface before considering a bounded crash reproducer. |

Apple groups the last two identifiers under one public use-after-free entry.
The advisory does not identify the affected object, function, syscall, or
driver, so an identifier alone is not enough to construct a meaningful test.

References:

- [watchOS 27.2 security content](https://support.apple.com/en-us/149525)
- [Apple Security Bounty guidelines](https://security.apple.com/bounty/guidelines/)
- [Apple Security Bounty categories](https://security.apple.com/bounty/categories/)

## Branch boundary

The first phase is deliberately read-only. It records build identities and
selects patch-diff candidates. It does not contain allocator grooming,
arbitrary kernel read/write construction, PAC or code-signing bypasses,
persistence, or a jailbreak payload. A later device test must be added as a
separate, reviewed commit with a fixed iteration bound and a stop-on-first-
panic rule.

The exact public CVEs are already fixed and are therefore useful for learning
and variant analysis, not as new bounty submissions. A bounty candidate must
be independently reproducible on the newest public watchOS or current beta.

## First run on the research Mac

```sh
git fetch origin
git switch research/watchos27-kernel-cves
git pull --ff-only

bash Experiments/watchos27-kernel-cve-lab.sh plan
bash Experiments/watchos27-kernel-cve-lab.sh doctor
```

`doctor` performs no device operation. Confirm that it prints paths for both
`LAB_OLD_ROOT` and `LAB_FIXED_ROOT`. Then run the one-command read-only audit:

```sh
bash Experiments/watchos27-kernel-cve-lab.sh bootstrap 2>&1 | \
  tee ~/Desktop/watchos27-kernel-cve-bootstrap.txt
```

The command prints progress for every selected Mach-O so a long hash or UUID
pass is never silent. Results are written below the ignored
`Experiments/KernelCVE/Runs/` directory. It inventories only these families:

- XNU kernels and kernel collections;
- kernel caches and Mach-O binaries found in extension trees (the latter may
  be user-space plug-ins; their path is not treated as proof of a loaded kext);
- `libsystem_kernel` and the IOKit/IOSurface client frameworks used for reachability mapping.

It does not copy, modify, thin, disassemble, or redistribute Apple binaries.
`COMPARE_COVERAGE=client-only-or-incomplete` means the roots did not provide a
kernel/kernel-collection/cache pair; do not mistake a client-framework diff
for the kernel fix.

## Explicit DeviceSupport roots

Auto-discovery prefers Series 9 (`Watch7,4`) directories named for watchOS
27.0.1 and 27.2. If the Mac uses another layout, pass the roots explicitly:

```sh
bash Experiments/watchos27-kernel-cve-lab.sh bootstrap \
  --old-root "$HOME/Library/Developer/Xcode/watchOS DeviceSupport/Watch7,4 27.0.1 (BUILD)" \
  --fixed-root "$HOME/Library/Developer/Xcode/watchOS DeviceSupport/Watch7,4 27.2 (BUILD)"
```

Each root may be either the DeviceSupport directory, its `Symbols`
subdirectory, or a separately obtained/extracted build root containing kernel
collections or kernel caches. DeviceSupport sometimes contains only user-space
symbols; in that case its comparison is useful for reachability mapping but is
not an XNU patch diff. Use `--no-uuids` only to diagnose a broken `dwarfdump`;
hashes are always calculated. Opaque kernel containers are hash-identified but
do not receive a Mach-O UUID until separately decoded by an appropriate tool.

## Optional physical-device baseline

This command only asks CoreDevice for device metadata. It requires an explicit
identifier to prevent selecting the wrong paired device, and installs or
launches nothing:

```sh
xcrun devicectl list devices
bash Experiments/watchos27-kernel-cve-lab.sh baseline \
  --owned-device --device 'COREDEVICE-ID'
```

Do not commit generated manifests or device logs: they contain local paths,
device metadata, binary identities, and possibly personal identifiers.

## Evidence and decision gates

1. Preserve `doctor.txt`, both manifests, and `comparison.json` together.
2. Confirm the old and fixed manifests represent the intended build numbers;
   a version string in a directory name is not proof by itself.
3. Do not interpret every changed kernel binary as one of the four CVEs. The
   27.2 update contains many unrelated fixes.
4. Select a candidate only after the changed code can be tied to an interface
   reachable by an ordinary sandboxed watchOS app.
5. If the path requires an unavailable entitlement, record it as unreachable
   instead of weakening signing or entitlement checks.
6. Any future device reproducer must stop after one panic or missing result and
   collect the crash/panic log before another run.
7. A result present only on 27.0.1 confirms historical behavior; a possible
   bounty variant must also be tested nondestructively on the current release.

## Local validation

```sh
bash -n Experiments/watchos27-kernel-cve-lab.sh
PYTHONPATH=Experiments/KernelCVE python3 -m unittest discover \
  -s Experiments/KernelCVE/Tests -v
```
