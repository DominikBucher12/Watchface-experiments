#!/usr/bin/env bash
set -euo pipefail

# Build watchOS DEVICE (not simulator) dylibs and a face bundle.
# This script intentionally does not inject into any process or modify watchOS.
experiment_dir="$(cd "$(dirname "$0")" && pwd)"
output_dir="${1:-/tmp/WatchFaceLab27-Device}"
deployment_target="${WATCHOS_DEPLOYMENT_TARGET:-27.0}"
sdk_path="$(xcrun --sdk watchos --show-sdk-path)"
target="arm64-apple-watchos${deployment_target}"
# UUID validation for system bridge is deliberately NOT enabled by this script.

# Private dependencies must be binaries for the *device* platform.
# Do not supply libraries from WatchSimulator.runtime: those have an incompatible platform.
ntk_binary="${WATCH_NTK_BINARY:-}"
clockkitui_binary="${WATCH_CLOCKKITUI_BINARY:-}"

if [[ -z "$ntk_binary" || ! -f "$ntk_binary" ]]; then
  echo 'ERROR: Set WATCH_NTK_BINARY to an existing DEVICE watchOS NanoTimeKit binary.' >&2
  echo 'Simulator NanoTimeKit is NOT a suitable link input for a device target.' >&2
  exit 2
fi
if [[ -z "$clockkitui_binary" || ! -f "$clockkitui_binary" ]]; then
  echo 'ERROR: Set WATCH_CLOCKKITUI_BINARY to an existing DEVICE watchOS ClockKitUI binary.' >&2
  exit 2
fi

check_device_binary() {
  local binary="$1"
  local label="$2"
  local platforms
  platforms="$(xcrun vtool -show-build -arch arm64e "$binary" 2>&1)" || {
    echo "ERROR: Cannot inspect $label ($binary)." >&2
    echo "$platforms" >&2
    exit 2
  }
  if ! grep -Eq 'platform[[:space:]]+WATCHOS([[:space:]]|$)' <<< "$platforms"; then
    echo "ERROR: $label does not declare WATCHOS as its platform:" >&2
    echo "$platforms" >&2
    exit 2
  fi
}
check_device_binary "$ntk_binary" NanoTimeKit
check_device_binary "$clockkitui_binary" ClockKitUI

echo "NOTE: arm64 device build; loading is not guaranteed. NTK method ABI on watchOS 27 is unverified." >&2
echo "NOTE: system bridge remains disabled until device image UUID/encodings are validated." >&2

mkdir -p "$output_dir"
common=( -target "$target" -isysroot "$sdk_path" -fobjc-arc -fno-modules -Wall -Wextra -Werror -g )

xcrun --sdk watchos clang "${common[@]}" -dynamiclib \
  "$experiment_dir/MYCustomFace.m" "$experiment_dir/MYBundleDiscovery.m" \
  "$ntk_binary" "$clockkitui_binary" \
  -framework Foundation -framework UIKit -framework ClockKit -framework CoreGraphics \
  -framework ImageIO -framework QuartzCore \
  -Wl,-install_name,@rpath/MYCustomFaceExperiment.dylib \
  -o "$output_dir/MYCustomFaceExperiment.dylib"

bundle_dir="$output_dir/FaceBundles/MYLocalFaceBundle.bundle"
mkdir -p "$bundle_dir"
cp "$experiment_dir/LocalFaceBundle/Info.plist" "$bundle_dir/Info.plist"
xcrun --sdk watchos clang "${common[@]}" -bundle \
  "$experiment_dir/LocalFaceBundle/MYLocalFaceBundle.m" \
  "$output_dir/MYCustomFaceExperiment.dylib" "$ntk_binary" \
  -framework Foundation -framework UIKit \
  -Wl,-rpath,@loader_path/../.. \
  -o "$bundle_dir/MYLocalFaceBundle"

xcrun --sdk watchos clang "${common[@]}" -dynamiclib \
  "$experiment_dir/MYClockFaceBridge.m" "$ntk_binary" \
  -framework Foundation -framework ClockKit \
  -Wl,-install_name,@rpath/MYClockFaceBridge.dylib \
  -o "$output_dir/MYClockFaceBridge.dylib"

xcrun --sdk watchos clang "${common[@]}" -dynamiclib \
  "$experiment_dir/MYOwnedDiscovery.m" "$output_dir/MYCustomFaceExperiment.dylib" "$ntk_binary" \
  -framework Foundation -framework UIKit -framework ClockKit \
  -Wl,-rpath,@loader_path \
  -Wl,-install_name,@rpath/MYOwnedDiscovery.dylib \
  -o "$output_dir/MYOwnedDiscovery.dylib"

# Deliberately leave signing to the containing Watch app's Xcode build/sign phase.
# Ad-hoc signing is not sufficient for physical Apple Watch deployment.
printf 'DEVICE build outputs (unsigned; embed/sign with Xcode):\n'
find "$output_dir" -maxdepth 3 -type f \( -name '*.dylib' -o -name MYLocalFaceBundle \) -print
