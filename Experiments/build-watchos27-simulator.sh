#!/usr/bin/env bash
set -euo pipefail
EXPERIMENTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME=MYCustomFaceExperiment
OUT="$EXPERIMENTS/Build/Simulator/$NAME.framework"
SDK="$(xcrun --sdk watchsimulator --show-sdk-path)"
mkdir -p "$OUT"
xcrun --sdk watchsimulator clang \
  -target arm64-apple-watchos27.0-simulator \
  -isysroot "$SDK" -dynamiclib -fobjc-arc -fblocks \
  -Wl,-undefined,dynamic_lookup \
  -Wl,-install_name,@rpath/$NAME.framework/$NAME \
  -framework Foundation \
  "$EXPERIMENTS/MYCustomFace.m" \
  "$EXPERIMENTS/MYBundleDiscovery.m" \
  "$EXPERIMENTS/MYArgonDescriptorV3.m" \
  "$EXPERIMENTS/MYArgonXPCReadOnlyProbe.m" \
  -o "$OUT/$NAME"
cat > "$OUT/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MYCustomFaceExperiment</string>
<key>CFBundleIdentifier</key><string>dev.develodom.MYCustomFaceExperiment</string>
<key>CFBundleName</key><string>MYCustomFaceExperiment</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleSupportedPlatforms</key><array><string>WatchSimulator</string></array>
<key>MinimumOSVersion</key><string>27.0</string>
</dict></plist>
PLIST
xcrun vtool -show-build "$OUT/$NAME" | grep -q 'platform WATCHOSSIMULATOR' || {
  echo 'ERROR: built binary is not WATCHOSSIMULATOR' >&2; exit 1;
}
xcrun nm -gU "$OUT/$NAME" | grep -q '_MYProbeArgonReadOnlyXPC$' || {
  echo 'ERROR: XPC probe export missing' >&2; exit 1;
}
echo
echo "=== EXPORTED EXPERIMENT SYMBOLS ==="
xcrun nm -gU "$OUT/$NAME" | grep -E 'MY|Argon' || true

echo
echo "=== UNRESOLVED PRIVATE SYMBOLS ==="
xcrun nm -u "$OUT/$NAME" | grep -E 'NTK|CLK' || true

echo "SIMULATOR BUILD OK: $OUT"
