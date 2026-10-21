# Owned-app shared discovery milestone

Built artifact: `/tmp/WatchFaceLab26-NTK/MYOwnedDiscovery.dylib`.
Build with `bash Experiments/build-simulator.sh`.

Run in a fresh **WatchFaceLab** app process attached through Xcode, not the copied
ClockFace research app or a system process. The exact host identifier is
`dev.develodom.WatchFaceLab`. No SwiftUI entry-point changes are required.
The experiment also requires the inspected x86_64 NanoTimeKit UUID and matching
method encodings. It rejects other hosts/runtimes. It makes no persistent writes.

Pause the app and run:

```lldb
thread select 1
expr -l objc++ -- (int)[NSThread isMainThread]
process load /tmp/WatchFaceLab26-NTK/MYCustomFaceExperiment.dylib
process load /tmp/WatchFaceLab26-NTK/MYOwnedDiscovery.dylib
image lookup -n MYStartOwnedDiscoveryExperiment
expr -l objc++ -u false -- (int)MYStartOwnedDiscoveryExperiment(@"/tmp/WatchFaceLab26-NTK/FaceBundles")
continue
```

The main-thread check must return 1. Start must return 1 and log
`Owned discovery STARTED`; that means loading was scheduled, not that the gallery
has passed. Resume for a few seconds, then pause again and run:

```lldb
thread select 1
expr -l objc++ -u false -- (int)MYCheckOwnedDiscoveryExperiment()
```

Expected: return 1 and `Owned discovery CONSUMPTION PASS`. This verifies shared
manager enumeration/lookup and native gallery consumption of a style-44
MYCustomFace with the custom identifier, renderer, and native time label. It does
not present a new screen. A zero-face result may still be pending; preserve logs
and resume before rechecking. Other failures should be investigated.

Clean up on the main thread even if consumption fails:

```lldb
expr -l objc++ -u false -- (int)MYRemoveOwnedDiscoveryExperiment()
continue
```

Expected: return 1 and `restored=1; consumptionPassed=1; fullCyclePassed=1`.
Removal restores the original class and checks the sorted enumeration against
the pre-install snapshot and the custom identifier's absent lookup. A successful
removal without successful consumption is cleanup only, not a passed milestone.
If enumeration changes independently during the cycle, the baseline comparison
can fail even after the class is restored; preserve the evidence and restart the
app. Avoid unrelated gallery activity during this short experiment.

If any expression faults, **do not continue or switch threads** before collecting:

```lldb
thread list
thread backtrace all
frame info
register read rip rsp rbp
disassemble --frame
```

The `-u false` option preserves a fault's expression stack rather than unwinding
it. Start may have installed the bridge before a later failure. Restart the app
if cleanup cannot run reliably; nothing persists across process exit. Do not
unload either dylib: registered Objective-C classes remain in the process.

Implementation shares the bridge source at compile time with separately named
owned-host exports and runtime subclass. Inner bridge messages currently retain
the `ClockFace bridge` prefix; they describe this owned-app build when called
through these functions. The separately built MYClockFaceBridge.dylib still
accepts only `com.apple.clockface`; do not load it for this milestone.

Limitations: original enumeration is forwarded, one bundle is appended in memory,
and only the custom identifier gets a new lookup result. Native manager caches
and loader configuration are untouched. Pending native work is not cancelled by
removal; previously retained models/bundles can outlive it. This establishes
in-process shared discovery only, not system gallery visibility or installation.


## User-verified result — PID 10520

The reported LLDB cycle returned 1 from start, check, and removal. Native baseline
contained 58 bundles. The hook reported exactly one custom identifier and matching
lookup; the native gallery produced the identified custom model, renderer and
NTKDigitalTimeLabel. Removal reported original manager class restored and
`class/enumeration/absent-lookup restored=1; consumptionPassed=1; fullCyclePassed=1`.
The app resumed. This passes the owned-process milestone, not system visibility.

During native discovery, the framework logged missing ExtractedBundles/23T570
and AppleInternal paths, skipped NTKCharacterFaceBundle for missing NSPrincipalClass,
and reported a duplicate NTKTimeFontTypographicBounds class in Apple's Parmesan
and Warlock bundles. It also emitted a BigNumeralsDigital wrong-initializer warning.
These did not prevent this cycle's acceptance checks. Their broader effects are
unknown; do not delete/rename Apple classes or create missing system paths merely
to silence them. No crash was reported in this cycle, which does not resolve the
earlier intermittent expression fault.
