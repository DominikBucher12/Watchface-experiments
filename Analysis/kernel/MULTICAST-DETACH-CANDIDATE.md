# IGMP/MLD deferred-detach lifetime candidate

Date: 2026-11-13

## Status

This is a real, paired IPv4/IPv6 lifetime-hardening change first visible
between watchOS 27.0.1 (`24A446`) and the 27.2 beta-1 kernel
(`24B5084k`). It is not yet attributable to CVE-2026-112474, and it is not
a useful stock-watch-app PoC target because the final-free path is tied to
network-interface detach rather than an ordinary multicast join or leave.

## Binary evidence

The stripped functions were named from their source strings and correlated
with Apple's published XNU source:

| Path | 24A446 | 24B5084k | Instructions |
|---|---|---|---:|
| `igi_remref` | `sub_fffffe000af91d54` | `sub_fffffe000b14be74` | 235 -> 281 |
| `mli_remref` | `sub_fffffe000b089e44` | `sub_fffffe000b24479c` | 235 -> 281 |
| `igmp_domifdetach` / `igi_delete` | `sub_fffffe000af9170c` | `sub_fffffe000b14b748` | 198 -> 240 |
| `mld_domifdetach` / `mli_delete` | `sub_fffffe000b08bb04` | `sub_fffffe000b246550` | 202 -> 244 |

Both new `remref` implementations add checks for a deferred-detach-list
entry and its counter:

```text
_inm->inm_in_dtle == true
_in6m->in6m_in_dtle == true
_dtlecnt != 0
```

The old functions only asserted that the deferred list was empty at final
free. The new functions explicitly track and drain deferred membership
records before the interface-info object can be released. The matching
IPv4 and IPv6 changes make an accidental compiler-only difference unlikely.
The relevant disassemblies are `igmp-ifinfo-24A446.txt`,
`igmp-ifinfo-24B5084k.txt`, `mld-ifinfo-24A446.txt`, and
`mld-ifinfo-24B5084k.txt`.

## Reachability boundary

Apple's published XNU source installs `igmp_domifdetach()` as the protocol
domain's interface-detach callback. That callback finds the `igmp_ifinfo`,
calls `igi_delete()`, and ultimately drops its reference through
`igi_remref()`. MLD has the same structure for IPv6.

A third-party application can create multicast memberships with public
socket options, but it cannot directly detach a system network interface.
Join/drop churn can populate and retire membership state; it does not by
itself establish execution of the changed final-free path. A device test
that merely races join and drop would therefore be ambiguous and was not
run.

## Attribution limit and next step

The change is consistent with preventing a stale deferred membership from
outliving its interface-info owner. It could be one of the Kernel UAF fixes
in watchOS 27.2, but the advisory does not map CVE-2026-112474 to IGMP or
MLD. The next triage target should be a changed lifetime path entered by a
normal application syscall without requiring interface teardown or a
private entitlement. The Unix-domain `SCM_RIGHTS` / `fileglob` path is the
current higher-priority candidate.

Authoritative source references:

- <https://github.com/apple-oss-distributions/xnu/blob/main/bsd/netinet/igmp.c>
- <https://github.com/apple-oss-distributions/xnu/blob/main/bsd/netinet6/mld6.c>

