#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
experiments_dir="$repo_root/Experiments"
device_id="${WATCHFACELAB_DEVICE_ID:-}"
build_only=0
check_only=0

usage() {
    printf '%s\n' \
        "usage: $0 [--device COREDEVICE-ID] [--build-only] [--check]" \
        "" \
        "Builds, signs, installs and launches the app-contained watchOS 27 experiment." \
        "It does not modify ClockFace or register a persistent system watchface."
}

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --device)
            [[ $# -ge 2 ]] || fail '--device requires an identifier'
            device_id="$2"
            shift 2
            ;;
        --build-only)
            build_only=1
            shift
            ;;
        --check)
            check_only=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            fail "unknown option: $1"
            ;;
    esac
done

[[ "$(uname -s)" == "Darwin" ]] || fail 'macOS is required'
developer_dir="$(xcode-select -p 2>/dev/null || true)"
[[ -x "$developer_dir/usr/bin/xcodebuild" ]] ||
    fail 'select a full Xcode installation with xcode-select'
xcrun --sdk watchos --show-sdk-path >/dev/null
sdk_version="$(xcrun --sdk watchos --show-sdk-version)"
required_version="${WATCHOS_DEPLOYMENT_TARGET:-27.0}"
if awk -v sdk="$sdk_version" -v required="$required_version" \
    'BEGIN { exit !((sdk + 0) < (required + 0)) }'; then
    fail "active Xcode provides watchOS SDK $sdk_version, but this branch requires $required_version or newer"
fi

. "$experiments_dir/resolve-watchos-device-frameworks.sh"
watchfacelab_resolve_device_frameworks

device_table="$(xcrun devicectl list devices 2>&1 || true)"
printf '%s\n' "$device_table"
if [[ -z "$device_id" ]]; then
    available_watch_line="$(grep -E 'Apple Watch' <<<"$device_table" |
        grep -Ev 'unavailable' | head -1 || true)"
    device_id="$(grep -Eo '[[:xdigit:]]{8}(-[[:xdigit:]]{4}){3}-[[:xdigit:]]{12}' \
        <<<"$available_watch_line" | head -1 || true)"
fi

if [[ "$check_only" == "1" ]]; then
    printf 'CHECK=PASS SDK=%s DEVICE=%s\n' \
        "$sdk_version" "${device_id:-unavailable}"
    exit 0
fi

if [[ "$build_only" != "1" && -z "$device_id" ]]; then
    fail 'no available Apple Watch; unlock it, keep the paired iPhone nearby, and open Devices and Simulators in Xcode'
fi

derived_data="${WATCHFACELAB_DERIVED_DATA:-/tmp/WatchFaceLab27-DeviceDerived-${device_id:-build}}"
destination="generic/platform=watchOS"
if [[ -n "$device_id" ]]; then
    destination="platform=watchOS,id=$device_id"
fi

printf 'DEVICE_STEP=1/5 build native framework and face bundle\n'
bash "$experiments_dir/build-embedded-framework.sh"
bash "$experiments_dir/build-local-face-bundle.sh"

printf 'DEVICE_STEP=2/5 build and sign app-contained experiment\n'
xcodebuild \
    -project "$repo_root/WatchFaceLab.xcodeproj" \
    -scheme WatchFaceLab \
    -configuration Debug \
    -destination "$destination" \
    -destination-timeout 120 \
    -derivedDataPath "$derived_data" \
    -allowProvisioningUpdates \
    "WATCH_NTK_BINARY=$WATCH_NTK_BINARY" \
    "WATCH_CLOCKKITUI_BINARY=$WATCH_CLOCKKITUI_BINARY" \
    build

app_path="$derived_data/Build/Products/Debug-watchos/WatchFaceLab.app"
[[ -d "$app_path" ]] || fail "signed app was not produced: $app_path"
framework="$app_path/Frameworks/MYCustomFaceExperiment.framework/MYCustomFaceExperiment"
face_bundle="$app_path/MYLocalFaceBundle.bundle/MYLocalFaceBundle"
app_executable="$app_path/WatchFaceLab"
[[ -f "$app_executable" ]] || fail 'WatchFaceLab executable is missing'
[[ -f "$framework" ]] || fail 'embedded custom-face framework is missing'
[[ -f "$face_bundle" ]] || fail 'embedded local face bundle is missing'

printf 'DEVICE_STEP=3/5 verify packaged code signatures and platform\n'
codesign --verify --deep --strict "$app_path"
app_archs="$(xcrun lipo -archs "$app_executable")"
framework_archs="$(xcrun lipo -archs "$framework")"
bundle_archs="$(xcrun lipo -archs "$face_bundle")"
[[ "$app_archs" == "$framework_archs" && "$app_archs" == "$bundle_archs" ]] ||
    fail "architecture mismatch: app=[$app_archs] framework=[$framework_archs] bundle=[$bundle_archs]"
xcrun vtool -show-build "$framework" |
    grep -Eq 'platform[[:space:]]+WATCHOS([[:space:]]|$)' ||
    fail 'embedded framework is not a watchOS device binary'
xcrun otool -L "$framework" |
    grep -F '/System/Library/PrivateFrameworks/NanoTimeKit.framework/NanoTimeKit' >/dev/null ||
    fail 'embedded framework does not link NanoTimeKit'

if [[ "$build_only" == "1" ]]; then
    printf 'DEVICE_BUILD=PASS APP=%s\n' "$app_path"
    exit 0
fi

printf 'DEVICE_STEP=4/5 install signed app on %s\n' "$device_id"
xcrun devicectl device install app --device "$device_id" "$app_path"

printf 'DEVICE_STEP=5/5 launch WatchFaceLab\n'
xcrun devicectl device process launch --device "$device_id" \
    --terminate-existing dev.develodom.WatchFaceLab

printf '%s\n' \
    'DEVICE_RUN=PASS' \
    'The native Pip-Boy renderer is running inside WatchFaceLab.' \
    'Press the Digital Crown to confirm that it does not persist as the system ClockFace.'
