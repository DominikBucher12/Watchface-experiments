#!/usr/bin/env bash
set -euo pipefail

# Run from any directory. Put this file in Experiments/ next to MYCustomFace.m.
experiments="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
output="${1:-$experiments/Build/Device}"
name=MYCustomFaceExperiment
framework="$output/$name.framework"
ntk="${WATCH_NTK_BINARY:?export WATCH_NTK_BINARY with the device NanoTimeKit Mach-O path}"
clockkit="${WATCH_CLOCKKITUI_BINARY:?export WATCH_CLOCKKITUI_BINARY with the device ClockKitUI Mach-O path}"
sdk="$(xcrun --sdk watchos --show-sdk-path)"
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
<key>MinimumOSVersion</key><string>27.0</string>
<key>CFBundleSupportedPlatforms</key><array><string>WatchOS</string></array>
</dict></plist>
PLIST
xcrun --sdk watchos clang \
  -target arm64-apple-watchos27.0 -isysroot "$sdk" \
  -fobjc-arc -fno-modules -Wall -Wextra -Werror -g -dynamiclib \
  "$experiments/MYCustomFace.m" "$experiments/MYBundleDiscovery.m" "$experiments/MYArgonRuntimeProbe.m" "$experiments/MYArgonABIProbe.m" "$experiments/MYArgonDescriptorProbe.m" \
  "$ntk" "$clockkit" \
  -framework Foundation -framework UIKit -framework ClockKit \
  -framework CoreGraphics -framework ImageIO -framework QuartzCore \
  -Wl,-install_name,@rpath/MYCustomFaceExperiment.framework/MYCustomFaceExperiment \
  -o "$framework/$name"
file "$framework/$name"
xcrun otool -D "$framework/$name"
echo "Created $framework (unsigned). Embed & Sign in the watchOS executable target in Xcode."
