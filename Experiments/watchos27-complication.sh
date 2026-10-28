#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
device_id="${WATCHFACELAB_DEVICE_ID:-}"
build_only=0
check_only=0

usage() {
    printf '%s\n' \
        "usage: $0 [--device COREDEVICE-ID] [--build-only] [--check]" \
        "" \
        "Builds, signs, installs, and launches the public WidgetKit complication." \
        "No DeviceSupport private frameworks or system-face XPC services are used."
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

device_table="$(xcrun devicectl list devices 2>&1 || true)"
printf '%s\n' "$device_table"
if [[ -z "$device_id" ]]; then
    available_watch_line="$(grep -Ei 'watch' <<<"$device_table" |
        grep -E 'physical[[:space:]]*$' |
        grep -E 'available|connected' | head -1 || true)"
    device_id="$(awk '{ for (i = 1; i < NF; i++) if ($(i + 1) == "(UDID)") { print $i; exit } }' \
        <<<"$available_watch_line")"
fi

if [[ "$check_only" == "1" ]]; then
    printf 'COMPLICATION_CHECK=PASS SDK=%s DEVICE=%s\n' \
        "$sdk_version" "${device_id:-unavailable}"
    exit 0
fi

if [[ "$build_only" != "1" && -z "$device_id" ]]; then
    fail 'no available physical Apple Watch; unlock it and keep the paired iPhone nearby'
fi

derived_data="${WATCHFACELAB_COMPLICATION_DERIVED_DATA:-/tmp/WatchFaceLab-Complication-${device_id:-build}}"
destination='generic/platform=watchOS'
if [[ -n "$device_id" ]]; then
    destination="platform=watchOS,id=$device_id"
fi

printf 'COMPLICATION_STEP=1/3 build public Watch app and WidgetKit extension\n'
xcodebuild \
    -project "$repo_root/WatchFaceLab.xcodeproj" \
    -scheme WatchFaceLab \
    -configuration Debug \
    -destination "$destination" \
    -destination-timeout 120 \
    -derivedDataPath "$derived_data" \
    -allowProvisioningUpdates \
    build

app_path="$derived_data/Build/Products/Debug-watchos/WatchFaceLab.app"
app_executable="$app_path/WatchFaceLab"
extension_path="$app_path/PlugIns/PipBoyComplication.appex"
extension_executable="$extension_path/PipBoyComplication"
[[ -f "$app_executable" ]] || fail "Watch app was not produced: $app_executable"
[[ -f "$extension_executable" ]] || fail "complication was not embedded: $extension_executable"

printf 'COMPLICATION_STEP=2/3 verify package and public-only boundary\n'
codesign --verify --deep --strict "$app_path"
extension_point="$(plutil -extract NSExtension.NSExtensionPointIdentifier raw -o - \
    "$extension_path/Info.plist" 2>/dev/null || true)"
[[ "$extension_point" == 'com.apple.widgetkit-extension' ]] ||
    fail "unexpected extension point: ${extension_point:-missing}"
app_archs="$(xcrun lipo -archs "$app_executable")"
extension_archs="$(xcrun lipo -archs "$extension_executable")"
[[ "$app_archs" == "$extension_archs" ]] ||
    fail "architecture mismatch: app=[$app_archs] extension=[$extension_archs]"
if find "$app_path" -path '*MYCustomFaceExperiment*' -o -path '*MYLocalFaceBundle*' |
    grep -q .; then
    fail 'private experiment artifacts leaked into the complication package'
fi
if xcrun otool -L "$app_executable" "$extension_executable" 2>/dev/null |
    grep -Eq 'NanoTimeKit|ClockKitUI|MYCustomFaceExperiment'; then
    fail 'private framework dependency leaked into the complication package'
fi

if [[ "$build_only" == "1" ]]; then
    printf 'COMPLICATION_BUILD=PASS APP=%s\n' "$app_path"
    exit 0
fi

printf 'COMPLICATION_STEP=3/3 install and launch on %s\n' "$device_id"
install_status=1
for install_attempt in 1 2 3; do
    set +e
    xcrun devicectl device install app --device "$device_id" "$app_path"
    install_status=$?
    set -e
    [[ "$install_status" == "0" ]] && break
    if [[ "$install_attempt" != "3" ]]; then
        printf 'COMPLICATION_INSTALL_RETRY attempt=%s/3 status=%s\n' \
            "$install_attempt" "$install_status"
        sleep 3
    fi
done
[[ "$install_status" == "0" ]] || fail 'complication app installation failed'

xcrun devicectl device process launch --device "$device_id" \
    --terminate-existing dev.develodom.WatchFaceLab.ComplicationHost

printf '%s\n' \
    'COMPLICATION_INSTALL=PASS' \
    'On the Watch: press and hold the current face, tap Edit, open Complications,' \
    'select a compatible slot, and choose Pip-Boy Monitor.'
