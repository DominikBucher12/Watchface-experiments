# Milestone: debuggable research target

## Strategy and observed blocker

The original ClockFace attach failed because the live target is hardened and
lacks get-task-allow, per the kernel policy log. Running LLDB with elevated
filesystem access did not change that. Apple's debugging-tool entitlement docs
explain that debugger permission alone does not grant access to such a target:
https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.debugger

Use a separately identified, debug-signed copy outside the runtime as the next
research target. This changes the copy's signature; it does not bypass attachment
policy for the original system ClockFace. It also does not preserve Apple's
signing identity, platform privileges or private service access. No claim is made
that copied ClockFace will work as a regular app or become the system face host.

Apple documents development/debug signing and get-task-allow here:
https://developer.apple.com/documentation/security/resolving-common-notarization-issues
Host executables govern in-process library entitlements:
https://developer.apple.com/documentation/security/hardened-runtime
These macOS references explain the host attach-policy mechanism. The corresponding
watchOS simulator behavior is an experiment, not guaranteed by those documents.

## Prepared artifact

Run `python3 Experiments/prepare-debug-target.py` to prepare a new copy (default
output must not already exist; use --output for a fresh directory). The first
prepared artifact is:

```text
/tmp/WatchFaceLab26-DebugTarget/ClockFaceResearch.app
```

Bundle identifier: dev.develodom.WatchFaceLab.ClockFaceResearch.
Executable basename remains ClockFace; identify processes by simulator/launch PID,
not by a broad `lldb -n ClockFace` attachment that might select the protected original.

The script copies only the current installed ClockFace app into temporary output;
no Apple binary or header enters the repository and no private framework is copied.
It changes the copied plist identifier/display name, removes SBMachServices and
hidden-app tags, and signs only the copy with a non-hardened ad-hoc debug signature (`--options 0`).
It supplies:

- com.apple.security.get-task-allow=true for the macOS host debugger policy.
- com.apple.security.cs.disable-library-validation=true for our ad-hoc test dylibs.

No guessed private service entitlement is supplied or inherited. Removing the
advertised service list does not prove the executable never requests hardcoded
services. It may fail early or attempt service access as soon as it runs.
Do not run this next to a valuable simulator state expecting complete isolation.

Validated locally on 2026-10-22:

- codesign --verify --strict --verbose succeeded.
- Signed entitlements display confirms both requested entries are true.
- codesign display reports adhoc (without runtime) and the unique identifier.
- Original executable and Info.plist SHA-256 values match before/after preparation.
- Preparation.json records the source, hashes, removed services and limitations.

Install, debugger attachment and initial launch have now been tested; see the result below. Full UI startup and bridge behavior are not established.

## What to do next

1. Create a **new disposable watchOS 26.5 simulator** in Xcode's Devices and
   Simulators window. Give it an obvious research name and copy its UDID.
   A new device has separate data but shares the original read-only runtime;
   it does not change the protected original ClockFace's signature.
2. In Terminal, substitute that UDID below. Do not use `booted`, because there
   may be multiple devices, including your existing working simulator.

```sh
RESEARCH_UDID='PASTE_NEW_SIMULATOR_UDID'
xcrun simctl boot "$RESEARCH_UDID"
xcrun simctl bootstatus "$RESEARCH_UDID" -b
xcrun simctl install "$RESEARCH_UDID" /tmp/WatchFaceLab26-DebugTarget/ClockFaceResearch.app
xcrun simctl launch --wait-for-debugger "$RESEARCH_UDID" dev.develodom.WatchFaceLab.ClockFaceResearch
```

The installed local simctl help verifies the install and launch switches, including
--wait-for-debugger. Although help advertises --arch, this installation rejected
that flag with Invalid device: --arch; architecture was verified in LLDB instead. If boot reports already booted, proceed to
bootstatus; if installation/launch fails, preserve the error and stop.

3. The launch command should print a PID. Attach to **that PID**, replacing the
   placeholder with the numeric result:

```sh
xcrun lldb -p RESEARCH_PID
```

4. Inside LLDB, collect the initial result before running application code:

```lldb
process status
image list -f
thread list
```

Verify that the executable path belongs to the installed research copy, not the
runtime's Applications/ClockFace.app. Successful attachment passes the first gate.
Use `continue` to test launch only after confirming that identity. If the copy
crashes or fails due to service/entitlement issues, capture thread backtrace all
and the console output. Do not respond by signing with invented private privileges.

5. Send the install/launch/attach output. The existing bridge intentionally accepts
only com.apple.clockface, so it **will reject this research identifier**. Do not
remove all host checks or call its install function in the copy yet. Once basic
launch/attach is established, add an explicit research-host mode restricted to
this identifier and its prepared executable path.

## Completion and next decision

Milestone completion means the separate app installs, attaches under LLDB, and
runs far enough to inspect NanoTimeKit. It does not mean system ClockFace was
made debuggable, that the private services work, or that a watch face is installed.

If the copy cannot operate without its original privileges, the alternative is
an owned debug-signed native host using the installed NanoTimeKit runtime, followed
by explicit analysis of the required system-service boundary. The current SwiftUI
app already proves many of those in-process APIs; additional owned-host work
would focus on shared discovery integration, not repeat renderer checks.

To undo this copy experiment, stop its debugger/process and uninstall only the
unique identifier from the disposable simulator:

```sh
xcrun simctl uninstall "$RESEARCH_UDID" dev.develodom.WatchFaceLab.ClockFaceResearch
```

The original system ClockFace and runtime signatures do not need restoration.
Temporary output can remain until all processes using it exit. No sudo, SIP/AMFI
disabling, runtime remounting, original-app re-signing or Carousel injection is
part of this strategy. Getting the actual original system host under debugger
would be a different security/environment change, not an outcome promised here.


## Execution result — 2026-10-22

Disposable simulator: WatchFaceLab26 Research,
E8757D97-8E48-479E-AD1C-9D8ADC8F5E5D, Series 11 (46mm), watchOS 26.5.

Installation initially required adding WKApplication=true and WKWatchOnly=true
to the copy. The preparation script now includes them. The initial mixed
entitlement set caused AMFI restricted-entitlement rejection; removing the
unprefixed get-task-allow entry allowed launch. Hardened signing then caused a
debugger-modified dyld page fault (KERN code 50 / Invalid Page). Re-signing only
the copy with --options 0 cleared that startup fault. No global protection or
original runtime signature was changed.

The revised copy installed, launched waiting for debugger, and accepted LLDB
attachment as x86_64-apple-watchos-simulator. It reached UIApplicationMain and
then native NTKClockViewController initialization. Full scene startup traps at
ComplicationServicesServer.init(device:) + 525, unslid NanoTimeKit address
0x3ec00d, instruction ud2. Reproduced under LLDB in PID 10178 after initial run
PID 10139. The branch to that trap follows a nil return from
NTKSharedRemoteComplicationProvider at 0x3ebe60. That function delegates to
NTKRemoteComplicationManager.sharedInstance. Why that singleton is nil in this
copy is not yet established; do not label it a particular missing entitlement
without tracing further. No forced non-nil return, instruction patch, service
entitlement addition or identity spoof was applied.

Milestone result: a separately signed attachable target that executes installed
NanoTimeKit is established. A fully usable ClockFace UI/system replacement is
not. The next research question is the remote-complication singleton's setup
requirements, or an owned native host that avoids full system-server startup.
The bridge remains unexecuted in this copy and its host guard still rejects the
research identifier. The original protected ClockFace remains unchanged.


## Startup boundary resolved

The read-only trace now identifies the immediate cause: the remote manager's
sharedInstance once-block permits unit tests or CLKRunningInProcess(0x38).
ClockKit resolves that mask to Carousel, ClockFace or NanoSettings and compares
main-bundle identifiers. The research identifier matches none. See RESEARCH.md
for instruction addresses and resolved string/selector references. Adding debug
entitlements cannot make that identifier comparison pass.

Continue with an owned-host shared-manager discovery milestone, avoiding full
ClockFace scene/server startup. Keep the copied target available as an attachable
research artifact; do not treat it as a working replacement face host. No further
security changes are required for this owned-host milestone. Success there still
will not establish system gallery installation or persistence.
