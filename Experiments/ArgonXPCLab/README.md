# Argon XPC Laboratory

An independent **macOS-only** read-only XPC contract test. The program uses an
anonymous `NSXPCListener` and `NSXPCConnection` to exchange a
`knownKeyDescriptors:` request and an array reply.

This does **not** connect to `com.apple.nanotimekit.facesupportserver`, execute
Apple's `nanotimekitd`, reproduce its private interface, bypass entitlements,
or validate watchOS Simulator bootstrap access. Both XPC endpoints reside in
one test process. It only establishes that the modeled asynchronous request,
reply, and NSXPCInterface wiring work on macOS.

The compiled lab binary is intentionally not checked in. Build and run it from
the repository root without writing a product into the source tree:

```sh
xcrun clang -fobjc-arc -framework Foundation \
  Experiments/ArgonXPCLab/ArgonXPCLab.m \
  -o /tmp/WatchFaceLab-ArgonXPCLab
/tmp/WatchFaceLab-ArgonXPCLab
```

For the real watchOS probe, retain your existing read-only code. General
artifact and cleanup policy is in
[`Docs/REPOSITORY_CLEANUP.md`](../../Docs/REPOSITORY_CLEANUP.md).
