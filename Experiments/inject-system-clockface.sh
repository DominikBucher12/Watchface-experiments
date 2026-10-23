#!/bin/bash
set -euo pipefail

SIM="4E768962-9FDF-4EBD-BE25-2A2A9E257143"
LIB="$PWD/Experiments/Build/Simulator/ClockFaceInjectionProbe.dylib"

if [[ ! -f "$LIB" ]]; then
    echo "ERROR: missing injection library: $LIB"
    exit 1
fi

echo "=== Find original ClockFace ==="

ENTRY="$(xcrun simctl spawn "$SIM" launchctl list |
    grep 'UIKitApplication:com.apple.clockface\[' |
    head -1)"

if [[ -z "$ENTRY" ]]; then
    echo "ERROR: original ClockFace launchd job not found"
    exit 1
fi

PID="$(printf '%s\n' "$ENTRY" | awk '{print $1}')"
LABEL="$(printf '%s\n' "$ENTRY" | awk '{print $3}')"

echo "PID:   $PID"
echo "Job:   $LABEL"
echo "Dylib: $LIB"

echo
echo "=== Resolve launchd service domain ==="

TARGET=""

for DOMAIN in system "gui/$(id -u)" "user/$(id -u)"; do
    CANDIDATE="$DOMAIN/$LABEL"

    if xcrun simctl spawn "$SIM" launchctl print \
        "$CANDIDATE" >/dev/null 2>&1; then
        TARGET="$CANDIDATE"
        break
    fi
done

if [[ -z "$TARGET" ]]; then
    echo "ERROR: launchd service target could not be resolved"
    echo "No process was restarted and no injection was attempted."
    exit 2
fi

echo "Target: $TARGET"

echo
echo "=== Configure one-shot injection ==="

xcrun simctl spawn "$SIM" launchctl debug \
    "$TARGET" \
    --environment "DYLD_INSERT_LIBRARIES=$LIB"

echo
echo "=== Restart original ClockFace service ==="

xcrun simctl spawn "$SIM" launchctl kickstart \
    -kp "$TARGET"

echo
echo "=== Injection result ==="

xcrun simctl spawn "$SIM" log show \
    --last 2m --info --style compact \
    --predicate 'eventMessage CONTAINS "CLOCKFACE_ORIGINAL_INJECTION"' \
    | tail -15

echo
echo "=== Current original ClockFace ==="

xcrun simctl spawn "$SIM" launchctl list |
    grep 'UIKitApplication:com.apple.clockface\[' || true
