#!/usr/bin/env bash
set -euo pipefail

# Run after build-embedded-framework.sh. The path is independent of cwd/Xcode.
experiment_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

. "$experiment_dir/resolve-watchos-device-frameworks.sh"
watchfacelab_resolve_device_frameworks
ntk="$WATCH_NTK_BINARY"
deployment_target="${WATCHOS_DEPLOYMENT_TARGET:-$(
  xcrun vtool -show-build "$ntk" 2>/dev/null |
    awk '/minos/ { print $2; exit }'
)}"
[[ -n "$deployment_target" ]] || deployment_target="$(xcrun --sdk watchos --show-sdk-version)"

sdk="$(xcrun --sdk watchos --show-sdk-path)"
mkdir -p "$bundle"
cp "$plist" "$bundle/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleSupportedPlatforms:0 WatchOS' "$bundle/Info.plist"
/usr/libexec/PlistBuddy -c "Set :MinimumOSVersion $deployment_target" "$bundle/Info.plist"

xcrun --sdk watchos clang \
  -target "arm64-apple-watchos$deployment_target" -isysroot "$sdk" \
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
