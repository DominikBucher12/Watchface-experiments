#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
experiments_dir="$repo_root/Experiments"
device_id="${WATCHFACELAB_DEVICE_ID:-}"
build_only=0
check_only=0
system_action=""
result_only=0

usage() {
    printf '%s\n' \
        "usage: $0 [--device COREDEVICE-ID] [--build-only] [--check]" \
        "          [--system-action boundary|preflight|install|select|rollback]" \
        "          [--result-only]" \
        "" \
        "Builds, signs, installs and launches the watchOS 27 experiment." \
        "Without --system-action it only runs the app-contained preview." \
        "install/select/rollback explicitly mutate the persistent LibraryFaces collection."
}

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

copy_system_result_from_device() {
    local target_device="$1"
    local local_file="$2"
    local copy_timeout="$3"
    local quiet_mode="$4"
    local remote_file
    local copy_status

    for remote_file in \
        'Documents/WatchFaceLab-SystemFaceResult.json' \
        '/Documents/WatchFaceLab-SystemFaceResult.json'; do
        rm -f "$local_file"
        set +e
        if [[ "$quiet_mode" == "1" ]]; then
            xcrun devicectl device copy from --device "$target_device" \
                --domain-type appDataContainer \
                --domain-identifier dev.develodom.WatchFaceLab \
                --source "$remote_file" --destination "$local_file" \
                --quiet --timeout "$copy_timeout" >/dev/null 2>&1
        else
            xcrun devicectl device copy from --device "$target_device" \
                --domain-type appDataContainer \
                --domain-identifier dev.develodom.WatchFaceLab \
                --source "$remote_file" --destination "$local_file" \
                --timeout "$copy_timeout"
        fi
        copy_status=$?
        set -e
        if [[ "$copy_status" == "0" && -f "$local_file" ]]; then
            return 0
        fi
    done
    return 1
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
        --system-action)
            [[ $# -ge 2 ]] || fail '--system-action requires a value'
            system_action="$2"
            case "$system_action" in
                boundary|preflight|install|select|rollback) ;;
                *) fail "invalid system action: $system_action" ;;
            esac
            shift 2
            ;;
        --result-only)
            result_only=1
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

if [[ "$result_only" == "1" &&
      ( -n "$system_action" || "$build_only" == "1" || "$check_only" == "1" ) ]]; then
    fail '--result-only cannot be combined with build, check, or system-action options'
fi

[[ "$(uname -s)" == "Darwin" ]] || fail 'macOS is required'
developer_dir="$(xcode-select -p 2>/dev/null || true)"
[[ -x "$developer_dir/usr/bin/xcodebuild" ]] ||
    fail 'select a full Xcode installation with xcode-select'
sdk_version="not-checked"
if [[ "$result_only" != "1" ]]; then
    xcrun --sdk watchos --show-sdk-path >/dev/null
    sdk_version="$(xcrun --sdk watchos --show-sdk-version)"
    required_version="${WATCHOS_DEPLOYMENT_TARGET:-27.0}"
    if awk -v sdk="$sdk_version" -v required="$required_version" \
        'BEGIN { exit !((sdk + 0) < (required + 0)) }'; then
        fail "active Xcode provides watchOS SDK $sdk_version, but this branch requires $required_version or newer"
    fi

    . "$experiments_dir/resolve-watchos-device-frameworks.sh"
    watchfacelab_resolve_device_frameworks
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
    printf 'CHECK=PASS SDK=%s DEVICE=%s\n' \
        "$sdk_version" "${device_id:-unavailable}"
    exit 0
fi

if [[ "$build_only" != "1" && -z "$device_id" ]]; then
    fail 'no available Apple Watch; unlock it, keep the paired iPhone nearby, and open Devices and Simulators in Xcode'
fi

if [[ "$result_only" == "1" ]]; then
    stored_result_dir="$(mktemp -d /tmp/WatchFaceLab-StoredResult.XXXXXX)"
    stored_result_file="$stored_result_dir/WatchFaceLab-SystemFaceResult.json"
    copy_system_result_from_device "$device_id" "$stored_result_file" 15 0 ||
        fail 'CoreDevice could not download the stored result JSON'
    stored_result_json="$(<"$stored_result_file")"
    printf 'SYSTEM_FACE_STORED_RESULT %s\n' "$stored_result_json"
    printf 'DEVICE_RESULT_FETCH=PASS TEMP=%s\n' "$stored_result_dir"
    exit 0
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
install_status=1
for install_attempt in 1 2 3; do
    set +e
    xcrun devicectl device install app --device "$device_id" "$app_path"
    install_status=$?
    set -e
    [[ "$install_status" == "0" ]] && break
    if [[ "$install_attempt" != "3" ]]; then
        printf 'DEVICE_INSTALL_RETRY attempt=%s/3 status=%s; keep the Watch unlocked and nearby\n' \
            "$install_attempt" "$install_status"
        sleep 3
    fi
done
[[ "$install_status" == "0" ]] ||
    fail 'app installation failed after 3 attempts; unlock the Watch and reopen Xcode Devices and Simulators'

printf 'DEVICE_STEP=5/5 launch WatchFaceLab\n'
if [[ -n "$system_action" ]]; then
    set +e
    process_table="$(xcrun devicectl device info processes --device "$device_id" \
        --timeout 15 2>&1)"
    process_status=$?
    set -e
    [[ "$process_status" == "0" ]] ||
        fail 'could not enumerate Watch processes before launch; refusing to reuse an ambiguous app process'
    watchfacelab_pids="$(awk '/WatchFaceLab|dev\.develodom\.WatchFaceLab/ {
        for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/) { print $i; break }
    }' <<<"$process_table" | sort -u)"
    if [[ -n "$watchfacelab_pids" ]]; then
        while IFS= read -r watchfacelab_pid; do
            xcrun devicectl device process terminate --device "$device_id" \
                --pid "$watchfacelab_pid" --kill --timeout 15
            printf 'DEVICE_PROCESS_TERMINATED pid=%s\n' "$watchfacelab_pid"
        done <<<"$watchfacelab_pids"
        sleep 1
    else
        printf 'DEVICE_PROCESS_TERMINATED not-running\n'
    fi
    system_run_id="$(date +%s)-$$-$system_action"
    result_dir="$(mktemp -d /tmp/WatchFaceLab-SystemFaceResult.XXXXXX)"
    result_file=""
    progress_file=""
    xcrun devicectl device process launch --device "$device_id" \
        --environment-variables "{\"WATCHFACELAB_SYSTEM_ACTION\":\"$system_action\",\"WATCHFACELAB_SYSTEM_RUN_ID\":\"$system_run_id\"}" \
        dev.develodom.WatchFaceLab
    printf 'DEVICE_RESULT_WAIT run=%s (up to 25 seconds)\n' "$system_run_id"
    result_deadline=$((SECONDS + 25))
    attempt=0
    while (( SECONDS < result_deadline )); do
        attempt=$((attempt + 1))
        copied_file="$result_dir/result-$attempt.json"
        if copy_system_result_from_device "$device_id" "$copied_file" 3 1; then
            copied_run_id="$(plutil -extract runID raw -o - "$copied_file" 2>/dev/null || true)"
            if [[ "$copied_run_id" == "$system_run_id" ]]; then
                progress_file="$copied_file"
                copied_complete="$(plutil -extract complete raw -o - "$copied_file" 2>/dev/null || true)"
                case "$copied_complete" in
                    true|YES|1)
                        result_file="$copied_file"
                        break
                        ;;
                esac
            fi
        fi
        sleep 1
    done
    if [[ -z "$result_file" ]]; then
        diagnostic_file="$result_dir/diagnostic-result.json"
        printf 'DEVICE_RESULT_DIAGNOSTIC_COPY_BEGIN\n'
        if copy_system_result_from_device "$device_id" "$diagnostic_file" 10 0; then
            diagnostic_copy_status=0
            diagnostic_json="$(<"$diagnostic_file")"
            printf 'SYSTEM_FACE_DIAGNOSTIC %s\n' "$diagnostic_json"
            diagnostic_run_id="$(plutil -extract runID raw -o - \
                "$diagnostic_file" 2>/dev/null || true)"
            diagnostic_complete="$(plutil -extract complete raw -o - \
                "$diagnostic_file" 2>/dev/null || true)"
            if [[ "$diagnostic_run_id" == "$system_run_id" ]]; then
                case "$diagnostic_complete" in
                    true|YES|1) result_file="$diagnostic_file" ;;
                esac
            fi
        else
            diagnostic_copy_status=$?
        fi
        printf 'DEVICE_RESULT_DIAGNOSTIC_COPY_END status=%s\n' "$diagnostic_copy_status"
        if [[ -z "$result_file" ]]; then
            if [[ -n "$progress_file" ]]; then
                progress_json="$(<"$progress_file")"
                printf 'SYSTEM_FACE_PROGRESS %s\n' "$progress_json"
            fi
            printf 'DEVICE_RESULT_CAPTURE=FAIL TEMP=%s\n' "$result_dir"
            printf 'DEVICE_CONTAINER_DOCUMENTS_BEGIN\n'
            set +e
            xcrun devicectl device info files --device "$device_id" \
                --domain-type appDataContainer \
                --domain-identifier dev.develodom.WatchFaceLab \
                --subdirectory Documents --no-recurse --timeout 10
            container_status=$?
            set -e
            printf 'DEVICE_CONTAINER_DOCUMENTS_END status=%s\n' "$container_status"
            fail 'the app launched, but no matching system-face result was copied from its data container'
        fi
    fi
    result_json="$(<"$result_file")"
    printf 'SYSTEM_FACE_RESULT %s\n' "$result_json"
    printf 'DEVICE_RESULT_CAPTURE=PASS TEMP=%s\n' "$result_dir"
    launch_result='PASS'
else
    xcrun devicectl device process launch --device "$device_id" \
        --terminate-existing dev.develodom.WatchFaceLab
    launch_result='PASS'
fi

printf '%s\n' \
    "DEVICE_LAUNCH=$launch_result" \
    "SYSTEM_ACTION=${system_action:-none}" \
    'The SYSTEM_FACE_RESULT line above is the authoritative probe result.'
