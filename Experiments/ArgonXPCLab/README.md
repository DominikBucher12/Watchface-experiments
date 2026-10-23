# Argon XPC Laboratory

An independent **macOS-only** read-only XPC contract test. The program uses an
anonymous `NSXPCListener` and `NSXPCConnection` to exchange a
`knownKeyDescriptors:` request and an array reply.

This does **not** connect to `com.apple.nanotimekit.facesupportserver`, execute
Apple's `nanotimekitd`, reproduce its private interface, bypass entitlements,
or validate watchOS Simulator bootstrap access. Both XPC endpoints reside in
one test process. It only establishes that the modeled asynchronous request,
reply, and NSXPCInterface wiring work on macOS.

Run: `bash setup-argon-xpc-lab.sh` from the repository root, or pass an output
folder. For the real watchOS probe, retain your existing read-only code.
