# `ClockFace` process boundary and next investigation

## Actual running process

The sysdiagnose `ps.txt` identified the **real** face UI process:

```
/Applications/ClockFace.app/ClockFace
bundle identifier: com.apple.clockface
observed PID: 198 (sysdiagnose snapshot; not stable)
```

`taskinfo.txt` reported:

```
cs_flags (0x26003301): valid hard kill enforcement require_lv dyld_platform platform_binary signed
```

These flags provide evidence of platform code signing and enforced library validation. They do **not** independently prove every possible future load path is prohibited, but they make an app-signed framework being directly loaded by `ClockFace` a significant trust-boundary issue.

## Audit false lead

An earlier DeviceSupport filename search returned:

```
System/Library/AccessibilityBundles/ClockFace.axbundle/ClockFace
```

This is an **accessibility bundle**, **not** `/Applications/ClockFace.app/ClockFace`. Its dependencies cannot be used as evidence for the main ClockFace app. In that audit the accessibility bundle linked `ClockFaceSupport` and `NanoTimeKit`; those are facts about **the accessibility bundle only**.

`NanoTimeKit` loaded UUID `4EB0531F-4C9E-343F-9A9A-04C66F69934C` matched prior device observations.

## Process boundary matrix

| Action | WatchFaceLab | ClockFace |
| --- | --- | --- |
| Load app's embedded `MYCustomFaceExperiment.framework` | **Verified** | Not tested |
| Load app-local `MYLocalFaceBundle.bundle` | **Verified** | Not tested |
| Return app bundle from `NTKFaceBundleManager` via temporary manager subclass | **Verified** | Not tested |
| Read `/var/mobile/.../ExtractedBundles/24R365` | **Denied (`EPERM`)** | Permissions not examined |
| Persist custom native face as the watch's actual selected face | **Not achieved** | Not achieved |

The app-process manager experiment uses `object_setClass` only for its own `NTKFaceBundleManager` instance. It does **not** alter the separately running `ClockFace` process or system filesystem. `OWNED27 RESTORED class=1 absent=1` confirmed the custom identity was absent after restoring the manager's original class.

## Next work items

1. **Locate real `ClockFace` executable** in the watchOS DeviceSupport Symbols hierarchy or establish that the corresponding Mach-O is absent from locally available symbols. Do not substitute `ClockFace.axbundle`.
2. Inspect **actual** `ClockFace.app/ClockFace` dependencies, exported/imported symbols and applicable entitlements only if a suitable copy exists. `codesign` against a stripped symbol copy may not reflect running entitlements.
3. Map `ClockFace` creation and use of `NTKFaceBundleManager`, face-gallery providers, and the collection persistence path **statically**.
4. Examine FaceSupportServer's XPC contract and authorization checks. Distinguish accepted descriptor formats from permission to register/execute third-party code.
5. Only after the above, decide whether a controlled **app-local** experiment adds new information. Avoid retesting established app-local rendering/discovery.
6. Confirm any actual system-face claim by selecting the face in the system gallery, leaving WatchFaceLab, returning to the watch face and validating that `ClockFace` still renders it. None of this has been achieved yet.

## Scope and risk

No kernel modifications, jailbreak, entitlement spoofing, system app patching, or injection into `ClockFace` were performed during the documented successful experiments. The unresolved boundary concerns Apple private frameworks, sandbox separation, signature enforcement and process isolation. The research code is build-specific and unsupported by Apple.

## Last observed checkpoint

The user was about to run a device-symbol path/entitlement audit for `/Applications/ClockFace.app/ClockFace` and `ClockFaceSupport.framework`. Results of **that** audit have **not** yet been supplied, and should not be marked verified.
