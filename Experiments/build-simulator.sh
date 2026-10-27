#!/bin/bash
set -euo pipefail
experiment_dir="$(cd "$(dirname "$0")" && pwd)"
runtime_root="${WATCH_RUNTIME_ROOT:-/Library/Developer/CoreSimulator/Volumes/watchOS_23T570/Library/Developer/CoreSimulator/Profiles/Runtimes/watchOS 26.5.simruntime/Contents/Resources/RuntimeRoot}"
output_dir="${1:-/tmp/WatchFaceLab26-NTK}"
sdk_path="$(xcrun --sdk watchsimulator --show-sdk-path)"
ntk_binary="$runtime_root/System/Library/PrivateFrameworks/NanoTimeKit.framework/NanoTimeKit"
test -f "$ntk_binary"
mkdir -p "$output_dir"
xcrun --sdk watchsimulator clang \
  -target x86_64-apple-watchos26.5-simulator -isysroot "$sdk_path" \
  -fobjc-arc -fno-modules \
  -Wall -Wextra -Werror -g -dynamiclib \
  "$experiment_dir/MYCustomFace.m" "$experiment_dir/MYBundleDiscovery.m" "$ntk_binary" \
  "$runtime_root/System/Library/PrivateFrameworks/ClockKitUI.framework/ClockKitUI" \
  -F"$runtime_root/System/Library/PrivateFrameworks" \
  -framework Foundation -framework UIKit -framework ClockKit -framework CoreGraphics \
  -framework ImageIO -framework QuartzCore \
  -install_name @rpath/MYCustomFaceExperiment.dylib \
  -o "$output_dir/MYCustomFaceExperiment.dylib"
codesign --force --sign - "$output_dir/MYCustomFaceExperiment.dylib"
printf '%s\n' "$output_dir/MYCustomFaceExperiment.dylib"

bundle_dir="$output_dir/FaceBundles/MYLocalFaceBundle.bundle"
if [[ -d "$bundle_dir" ]]; then
  rm -rf "$bundle_dir"
fi
mkdir -p "$bundle_dir"
cp "$experiment_dir/LocalFaceBundle/Info.plist" "$bundle_dir/Info.plist"
animation_source="$experiment_dir/../WatchFaceLab/Resources/pip-boy-reference.gif"
test -f "$animation_source"
mkdir -p "$bundle_dir/Assets"
cp "$animation_source" "$bundle_dir/Assets/pip-boy-reference.gif"
xcrun --sdk watchsimulator clang \
  -target x86_64-apple-watchos26.5-simulator -isysroot "$sdk_path" \
  -fobjc-arc -fno-modules -Wall -Wextra -Werror -g -bundle \
  "$experiment_dir/LocalFaceBundle/MYLocalFaceBundle.m" \
  "$output_dir/MYCustomFaceExperiment.dylib" "$ntk_binary" \
  -F"$runtime_root/System/Library/PrivateFrameworks" \
  -framework Foundation -framework UIKit \
  -Wl,-rpath,@loader_path/../.. \
  -o "$bundle_dir/MYLocalFaceBundle"
codesign --force --sign - "$bundle_dir"
codesign --verify --deep --strict "$bundle_dir"
codesign -d --verbose=4 "$bundle_dir" 2>&1 |
  grep 'Info.plist entries=' >/dev/null
printf '%s\n' "$bundle_dir"

# Separate opt-in system-host bridge; never loaded or executed by this script.
xcrun --sdk watchsimulator clang \
  -target x86_64-apple-watchos26.5-simulator -isysroot "$sdk_path" \
  -fobjc-arc -fno-modules -Wall -Wextra -Werror -g -dynamiclib \
  "$experiment_dir/MYClockFaceBridge.m" "$ntk_binary" \
  -F"$runtime_root/System/Library/PrivateFrameworks" \
  -framework Foundation -framework ClockKit \
  -install_name @rpath/MYClockFaceBridge.dylib \
  -o "$output_dir/MYClockFaceBridge.dylib"
codesign --force --sign - "$output_dir/MYClockFaceBridge.dylib"
printf '%s\n' "$output_dir/MYClockFaceBridge.dylib"

# Owned-app shared discovery; separate exports and host guard from the system bridge.
xcrun --sdk watchsimulator clang \
  -target x86_64-apple-watchos26.5-simulator -isysroot "$sdk_path" \
  -fobjc-arc -fno-modules -Wall -Wextra -Werror -g -dynamiclib \
  "$experiment_dir/MYOwnedDiscovery.m" "$output_dir/MYCustomFaceExperiment.dylib" "$ntk_binary" \
  -F"$runtime_root/System/Library/PrivateFrameworks" \
  -framework Foundation -framework UIKit -framework ClockKit \
  -Wl,-rpath,@loader_path \
  -install_name @rpath/MYOwnedDiscovery.dylib \
  -o "$output_dir/MYOwnedDiscovery.dylib"
codesign --force --sign - "$output_dir/MYOwnedDiscovery.dylib"
printf '%s\n' "$output_dir/MYOwnedDiscovery.dylib"

# Fresh-process probe for the default NTKFaceBundleManager discovery path.
xcrun --sdk watchsimulator clang \
  -target x86_64-apple-watchos26.5-simulator -isysroot "$sdk_path" \
  -fobjc-arc -fblocks -fno-modules -Wall -Wextra -Werror \
  "$experiment_dir/SystemDiscoveryProbe.m" "$ntk_binary" \
  -F"$runtime_root/System/Library/PrivateFrameworks" \
  -framework Foundation -framework UIKit -framework ClockKit \
  -o "$output_dir/SystemDiscoveryProbe"
codesign --force --sign - "$output_dir/SystemDiscoveryProbe"
printf '%s\n' "$output_dir/SystemDiscoveryProbe"

# Read-only authorization probe for com.apple.nanotimekit.collectionserver.
xcrun --sdk watchsimulator clang \
  -target x86_64-apple-watchos26.5-simulator -isysroot "$sdk_path" \
  -fobjc-arc -fblocks -fno-modules -Wall -Wextra -Werror \
  "$experiment_dir/CollectionReadProbe.m" "$ntk_binary" \
  -F"$runtime_root/System/Library/PrivateFrameworks" \
  -framework Foundation -framework ClockKit \
  -o "$output_dir/CollectionReadProbe"
codesign --force --sign - "$output_dir/CollectionReadProbe"
printf '%s\n' "$output_dir/CollectionReadProbe"

# Opt-in persistent add/remove/select client. Building it performs no mutation.
xcrun --sdk watchsimulator clang \
  -target x86_64-apple-watchos26.5-simulator -isysroot "$sdk_path" \
  -fobjc-arc -fblocks -fno-modules -Wall -Wextra -Werror \
  "$experiment_dir/CollectionMutationProbe.m" "$ntk_binary" \
  -F"$runtime_root/System/Library/PrivateFrameworks" \
  -framework Foundation -framework UIKit -framework ClockKit \
  -o "$output_dir/CollectionMutationProbe"
codesign --force --sign - "$output_dir/CollectionMutationProbe"
printf '%s\n' "$output_dir/CollectionMutationProbe"

# Early-process root switch for original ClockFace and nanotimekitd only.
xcrun --sdk watchsimulator clang \
  -target x86_64-apple-watchos26.5-simulator -isysroot "$sdk_path" \
  -fobjc-arc -fno-modules -Wall -Wextra -Werror -dynamiclib \
  "$experiment_dir/SystemRootBootstrap.m" \
  -framework Foundation \
  -install_name @rpath/SystemRootBootstrap.dylib \
  -o "$output_dir/SystemRootBootstrap.dylib"
codesign --force --sign - "$output_dir/SystemRootBootstrap.dylib"
printf '%s\n' "$output_dir/SystemRootBootstrap.dylib"

# One-shot, ABI-guarded active-face switch for the original ClockFace UI.
xcrun --sdk watchsimulator clang \
  -target x86_64-apple-watchos26.5-simulator -isysroot "$sdk_path" \
  -fobjc-arc -fblocks -fno-modules -Wall -Wextra -Werror -dynamiclib \
  "$experiment_dir/ActiveFaceSelector.m" \
  -framework Foundation -framework UIKit \
  -install_name @rpath/ActiveFaceSelector.dylib \
  -o "$output_dir/ActiveFaceSelector.dylib"
codesign --force --sign - "$output_dir/ActiveFaceSelector.dylib"
printf '%s\n' "$output_dir/ActiveFaceSelector.dylib"
