#!/usr/bin/env bash
set -euo pipefail
ROOT="${WATCH_DEVICE_PRIVATE_FRAMEWORKS:-$HOME/Library/Developer/Xcode/watchOS DeviceSupport/27.0.1 (24R365) universal/Symbols/System/Library/PrivateFrameworks}"
for FRAMEWORK in NanoTimeKit ClockKitUI; do
  BINARY="$ROOT/$FRAMEWORK.framework/$FRAMEWORK"
  echo "=== $FRAMEWORK ==="
  test -f "$BINARY" || { echo "Missing: $BINARY" >&2; exit 2; }
  xcrun lipo -detailed_info "$BINARY"
  xcrun vtool -arch arm64e -show-build "$BINARY"
done
