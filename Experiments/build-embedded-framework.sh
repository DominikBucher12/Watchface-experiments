#!/usr/bin/env bash
set -euo pipefail

# Run from any directory. Put this file in Experiments/ next to MYCustomFace.m.
experiments="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
output="${1:-$experiments/Build/Device}"
name=MYCustomFaceExperiment
framework="$output/$name.framework"
. "$experiments/resolve-watchos-device-frameworks.sh"
watchfacelab_resolve_device_frameworks
ntk="$WATCH_NTK_BINARY"
clockkit="$WATCH_CLOCKKITUI_BINARY"
sdk="$(xcrun --sdk watchos --show-sdk-path)"
deployment_target="${WATCHOS_DEPLOYMENT_TARGET:-$(
  xcrun vtool -show-build "$ntk" 2>/dev/null |
    awk '/minos/ { print $2; exit }'
)}"
[[ -n "$deployment_target" ]] || deployment_target="$(xcrun --sdk watchos --show-sdk-version)"

# Xcode treats a nested dSYM Mach-O as embedded code and fails while stripping
# it. Standalone clang -g can create this directory after linking, so relocate
# both a historical copy and the newly generated copy outside the framework.
dsym_sequence=0
relocate_nested_dsym() {
  nested_dsym="$framework/$name.dSYM"
  [[ -d "$nested_dsym" ]] || return 0
  dsym_sequence=$((dsym_sequence + 1))
  debug_archive="$output/DebugSymbols"
  mkdir -p "$debug_archive"
  archived_dsym="$debug_archive/$name-nested-$$-$dsym_sequence.dSYM"
  mv "$nested_dsym" "$archived_dsym"
  printf 'DEVICE_DSYM_RELOCATED=%s\n' "$archived_dsym"
}
relocate_nested_dsym
for f in "$ntk" "$clockkit"; do
  test -f "$f" || { echo "Not a file: $f" >&2; exit 2; }
  xcrun vtool -arch arm64e -show-build "$f" | grep -Eq 'platform[[:space:]]+WATCHOS([[:space:]]|$)' || {
    echo "Not a watchOS device Mach-O: $f" >&2; exit 2;
  }
done
mkdir -p "$framework"
cat > "$framework/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.develodom.WatchFaceLab.MYCustomFaceExperiment</string>
<key>CFBundleName</key><string>MYCustomFaceExperiment</string>
<key>CFBundleExecutable</key><string>MYCustomFaceExperiment</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>MinimumOSVersion</key><string>__WATCHFACELAB_MIN_OS__</string>
<key>CFBundleSupportedPlatforms</key><array><string>WatchOS</string></array>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Set :MinimumOSVersion $deployment_target" \
  "$framework/Info.plist"
xcrun --sdk watchos clang \
  -target "arm64-apple-watchos$deployment_target" -isysroot "$sdk" \
  -fobjc-arc -fno-modules -Wall -Wextra -Werror -g -dynamiclib \
  "$experiments/MYCustomFace.m" "$experiments/MYArgonDescriptorV3.m" "$experiments/MYBundleDiscovery.m" "$experiments/MYOwnedManagerWatch27.m" \
  "$ntk" "$clockkit" \
  -framework Foundation -framework UIKit -framework ClockKit \
  -framework CoreGraphics -framework ImageIO -framework QuartzCore \
  -Wl,-install_name,@rpath/MYCustomFaceExperiment.framework/MYCustomFaceExperiment \
  -o "$framework/$name"
relocate_nested_dsym
file "$framework/$name"
xcrun otool -D "$framework/$name"
printf 'DEVICE_FRAMEWORK_TARGET=arm64-apple-watchos%s\n' "$deployment_target"
echo "Created $framework (unsigned). Embed & Sign in the watchOS executable target in Xcode."
