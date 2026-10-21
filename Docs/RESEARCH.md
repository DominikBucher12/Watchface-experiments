# Research log — watchOS 26.5 / Intel simulator

These observations are from the user's own `otool`/`llvm-objdump` output, **not** a proof that injection or custom face registration works.

- Simulator runtime: watchOS 26.5, build 23T570, x86_64 and arm64.
- `NanoTimeKit.framework/NanoTimeKit` exists in `RuntimeRoot/System/Library/PrivateFrameworks` as a universal Mach-O.
- `NTKFace` subclasses `NSObject`; `NTKFaceView` subclasses `UIView`.
- `-[NTKFace(ViewSupport) faceViewClass]` base implementation returns Nil.
- `+[NTKFaceView newFaceViewForFace:]` calls `_ViewClassForFace`.
- `_ViewClassForFace` first sends `faceViewClass` to the face. If non-Nil, it uses the returned Class; otherwise it falls back to bundle identifier/style lookup.
- The view factory calls `initWithFaceStyle:forDevice:clientIdentifier:` on the resulting class.
- `-[NTKFace _initWithFaceStyle:forDevice:]` calls super init, `_commonInit`, and complication observer setup.
- `_commonInit` creates internal state; no claim is made that arbitrary subclasses can initialize safely without further checks.

## Gate for next experiment

1. Confirm the public baseline app builds and launches in an **x86_64** watchOS 26.5 simulator.
2. Locate watch face hosting process (do not assume `Carousel` still hosts it).
3. Inspect loaded `NanoTimeKit` classes and Objective-C method signatures at runtime via LLDB.
4. Compile experimental Objective-C code as a separate simulator module.
5. Verify whether debugger injection is permitted, and whether an instance of `MYCustomFace` plus `MYCustomFaceView` can be instantiated.
6. Only then investigate actual face registration or UI presentation.

**Warning:** experimental code is not linked into the shipping-style watch app. A regular third-party watch app cannot thereby install a real system watch face. Private API is unsupported and not App Store-eligible.
