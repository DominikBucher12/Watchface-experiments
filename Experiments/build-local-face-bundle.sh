#!/usr/bin/env bash
set -euo pipefail

# Run from the repository root after build-embedded-framework.sh.
repo="$(pwd)"
experiment_dir="$repo/Experiments"
framework_root="$experiment_dir/Build/Device"
framework="$framework_root/MYCustomFaceExperiment.framework/MYCustomFaceExperiment"
source="$experiment_dir/LocalFaceBundle/MYLocalFaceBundle.m"
plist="$experiment_dir/LocalFaceBundle/Info.plist"
bundle="$framework_root/FaceBundles/MYLocalFaceBundle.bundle"

for file in "$framework" "$source" "$plist"; do
  if [[ ! -f "$file" ]]; then
    printf 'ERROR: missing input: %s\n' "$file" >&2
    exit 2
  fi
done

ntk="${WATCH_NTK_BINARY:-$HOME/Library/Developer/Xcode/watchOS DeviceSupport/27.0.1 (24R365) universal/Symbols/System/Library/PrivateFrameworks/NanoTimeKit.framework/NanoTimeKit}"
if [[ ! -f "$ntk" ]]; then
  printf 'ERROR: missing device NanoTimeKit binary: %s\n' "$ntk" >&2
  exit 2
fi

sdk="$(xcrun --sdk watchos --show-sdk-path)"
mkdir -p "$bundle"
cp "$plist" "$bundle/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleSupportedPlatforms:0 WatchOS' "$bundle/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :MinimumOSVersion 27.0' "$bundle/Info.plist"

xcrun --sdk watchos clang \
  -target arm64-apple-watchos27.0 -isysroot "$sdk" \
  -fobjc-arc -fno-modules -Wall -Wextra -Werror \
  -bundle "$source" \
  -F "$framework_root" -framework MYCustomFaceExperiment \
  "$ntk" -framework Foundation -framework UIKit \
  -Wl,-rpath,@loader_path/../../Frameworks \
  -o "$bundle/MYLocalFaceBundle"

printf '\nBundle created (unsigned, for Xcode embedding/signing):\n%s\n' "$bundle"
xcrun vtool -show-build "$bundle/MYLocalFaceBundle"
xcrun otool -L "$bundle/MYLocalFaceBundle"
echo 'NOTE: Do not deploy loose unsigned bundle. Embed/sign using Xcode.'
