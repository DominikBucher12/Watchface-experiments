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
  "$experiment_dir/MYCustomFace.m" "$ntk_binary" \
  -F"$runtime_root/System/Library/PrivateFrameworks" \
  -framework Foundation -framework UIKit -framework ClockKit -framework CoreGraphics \
  -install_name @rpath/MYCustomFaceExperiment.dylib \
  -o "$output_dir/MYCustomFaceExperiment.dylib"
codesign --force --sign - "$output_dir/MYCustomFaceExperiment.dylib"
printf '%s\n' "$output_dir/MYCustomFaceExperiment.dylib"
