#!/bin/bash
set -euo pipefail

experiment_dir="$(cd "$(dirname "$0")" && pwd)"
quickstart="$experiment_dir/quickstart-system-face.sh"
runtime_major="${WATCHFACELAB_RUNTIME_MAJOR:-27}"
runtime_id="${WATCHFACELAB_RUNTIME_ID:-}"
device_type="${WATCHFACELAB_DEVICE_TYPE:-}"
device_name="${WATCHFACELAB_DEVICE_NAME:-WatchFaceLab27 Research}"
face_title="${WATCHFACELAB_FACE_TITLE:-VAULT BOY}"
mode="run"

usage() {
    cat <<'EOF'
usage: bootstrap-watchos27-simulator.sh [options]

Creates (or reuses) a disposable watchOS 27 research simulator, then builds,
loads, installs, and displays the custom Pip-Boy face.

Options:
  --check                 Validate Xcode/runtime and print the selected setup.
  --create-only           Create and boot the simulator, but do not load a face.
  --runtime IDENTIFIER    Use this CoreSimulator runtime identifier.
  --device-type ID        Use this CoreSimulator Apple Watch device type.
  --name NAME             Override the dedicated simulator name.
  --title TITLE           Set the custom face's displayed title.
  -h, --help              Show this help.

Environment equivalents:
  WATCHFACELAB_RUNTIME_ID, WATCHFACELAB_DEVICE_TYPE,
  WATCHFACELAB_DEVICE_NAME, WATCHFACELAB_RUNTIME_MAJOR,
  WATCHFACELAB_FACE_TITLE

Run as the logged-in macOS user. Never use sudo.
EOF
}

say() {
    printf '\n==> %s\n' "$1"
}

fail() {
    printf '\nERROR: %s\n' "$1" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)
            mode="check"
            shift
            ;;
        --create-only)
            mode="create"
            shift
            ;;
        --runtime)
            [[ $# -ge 2 ]] || fail "--runtime needs an identifier"
            runtime_id="$2"
            shift 2
            ;;
        --device-type)
            [[ $# -ge 2 ]] || fail "--device-type needs an identifier"
            device_type="$2"
            shift 2
            ;;
        --name)
            [[ $# -ge 2 ]] || fail "--name needs a value"
            device_name="$2"
            shift 2
            ;;
        --title)
            [[ $# -ge 2 ]] || fail "--title needs a value"
            face_title="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            fail "unknown option: $1"
            ;;
    esac
done

if [[ "${EUID:-$(id -u)}" == "0" ]]; then
    fail "run this as your normal macOS user, not with sudo"
fi
[[ "$runtime_major" =~ ^[0-9]+$ ]] ||
    fail "WATCHFACELAB_RUNTIME_MAJOR must be a numeric major version"
if [[ -z "$face_title" || "$face_title" == *$'\n'* ||
      "$face_title" == *$'\r'* || ${#face_title} -gt 64 ]]; then
    fail "face title must contain 1-64 characters on one line"
fi
[[ "$(uname -s)" == "Darwin" ]] || fail "this experiment requires macOS"
command -v xcrun >/dev/null 2>&1 ||
    fail "xcrun is unavailable; install Xcode and select it with xcode-select"
command -v xcodebuild >/dev/null 2>&1 ||
    fail "xcodebuild is unavailable; install the full Xcode application"
[[ -x "$quickstart" ]] || fail "missing quickstart: $quickstart"

developer_dir="$(xcode-select -p 2>/dev/null || true)"
if [[ -z "$developer_dir" || "$developer_dir" == *CommandLineTools* ]]; then
    fail "select the full Xcode app, for example: sudo xcode-select -s /Applications/Xcode.app"
fi

simctl_path="$(xcrun --find simctl 2>/dev/null || true)"
[[ -n "$simctl_path" ]] || fail "simctl is unavailable in the selected Xcode"
sdk_version="$(xcrun --sdk watchsimulator --show-sdk-version 2>/dev/null || true)"
[[ -n "$sdk_version" ]] ||
    fail "the selected Xcode does not provide a watchOS Simulator SDK"
sdk_major="${sdk_version%%.*}"
if [[ ! "$sdk_major" =~ ^[0-9]+$ || "$sdk_major" -lt "$runtime_major" ]]; then
    fail "watchOS Simulator SDK $runtime_major or newer is required; selected SDK is $sdk_version"
fi

runtime_list="$(xcrun simctl list runtimes available 2>&1)" || {
    printf '%s\n' "$runtime_list" >&2
    fail "CoreSimulator is unavailable; open Xcode once and finish first-launch setup"
}

if [[ -n "$runtime_id" ]]; then
    runtime_line="$(grep -F -- "- $runtime_id" <<<"$runtime_list" | head -1 || true)"
    [[ -n "$runtime_line" ]] ||
        fail "requested runtime is not installed or unavailable: $runtime_id"
    if [[ "$runtime_line" != watchOS\ "$runtime_major"* ]]; then
        fail "requested runtime is not watchOS $runtime_major.x: $runtime_line"
    fi
else
    runtime_matches="$(awk -v major="$runtime_major" \
        '$1 == "watchOS" && $2 ~ ("^" major "([.]|$)") { print }' \
        <<<"$runtime_list")"
    [[ -n "$runtime_matches" ]] || {
        printf '\nInstalled watchOS runtimes:\n%s\n' \
            "$(awk '$1 == "watchOS" { print "  " $0 }' <<<"$runtime_list")" >&2
        fail "no watchOS $runtime_major.x Simulator runtime is installed. Install it in Xcode > Settings > Components, then rerun this script"
    }
    # simctl lists runtimes in version order. Prefer the newest available 27.x.
    runtime_line="$(tail -1 <<<"$runtime_matches")"
    runtime_id="${runtime_line##* - }"
fi
runtime_name="${runtime_line%% (*}"

device_type_list="$(xcrun simctl list devicetypes 2>&1)" || {
    printf '%s\n' "$device_type_list" >&2
    fail "could not enumerate Simulator device types"
}
watch_device_types="$(sed -n \
    's/.*(\(com\.apple\.CoreSimulator\.SimDeviceType\.Apple-Watch[^)]*\))$/\1/p' \
    <<<"$device_type_list")"
[[ -n "$watch_device_types" ]] || fail "Xcode contains no Apple Watch device type"
if [[ -n "$device_type" ]] && ! grep -Fxq "$device_type" <<<"$watch_device_types"; then
    fail "requested device type is not an installed Apple Watch type: $device_type"
fi

runtime_devices="$(xcrun simctl list devices "$runtime_name" 2>&1)" || {
    printf '%s\n' "$runtime_devices" >&2
    fail "could not enumerate devices for $runtime_id"
}
existing_udids="$(grep -F "    $device_name (" <<<"$runtime_devices" |
    sed -E 's/.*\(([0-9A-Fa-f-]{36})\).*/\1/' || true)"
existing_count="$(grep -c . <<<"$existing_udids" || true)"
if [[ "$existing_count" -gt 1 ]]; then
    printf '%s\n' "$existing_udids" >&2
    fail "multiple simulators named '$device_name' exist in the selected runtime"
fi
simulator_udid="$(head -1 <<<"$existing_udids")"

printf '%s\n' \
    "WatchFaceLab watchOS $runtime_major bootstrap" \
    "Host: $(uname -m)" \
    "Xcode: $developer_dir" \
    "SDK: watchsimulator $sdk_version" \
    "Runtime: $runtime_line" \
    "Device name: $device_name" \
    "Face title: $face_title"

if [[ "$mode" == "check" ]]; then
    if [[ -n "$simulator_udid" ]]; then
        printf 'Existing device: %s\n' "$simulator_udid"
    else
        printf 'Existing device: none (it will be created on the full run)\n'
    fi
    if [[ -n "$device_type" ]]; then
        printf 'Requested device type: %s\n' "$device_type"
    else
        printf 'Preferred device type: %s\n' "$(head -1 <<<"$watch_device_types")"
    fi
    printf '\nCHECK=PASS\n'
    exit 0
fi

if [[ -z "$simulator_udid" ]]; then
    say "Creating dedicated research simulator"
    create_error=""
    if [[ -n "$device_type" ]]; then
        set +e
        create_output="$(xcrun simctl create "$device_name" "$device_type" \
            "$runtime_id" 2>&1)"
        create_status=$?
        set -e
        if [[ "$create_status" -eq 0 ]]; then
            simulator_udid="$(sed -nE \
                's/.*([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}).*/\1/p' \
                <<<"$create_output" | tail -1)"
        else
            create_error="$create_output"
        fi
    else
        while IFS= read -r candidate; do
            [[ -n "$candidate" ]] || continue
            set +e
            create_output="$(xcrun simctl create "$device_name" "$candidate" \
                "$runtime_id" 2>&1)"
            create_status=$?
            set -e
            if [[ "$create_status" -eq 0 ]]; then
                created_udid="$(sed -nE \
                    's/.*([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}).*/\1/p' \
                    <<<"$create_output" | tail -1)"
                if [[ -n "$created_udid" ]]; then
                    simulator_udid="$created_udid"
                    device_type="$candidate"
                    break
                fi
            fi
            create_error="$create_output"
        done <<<"$watch_device_types"
    fi
    if [[ -z "$simulator_udid" ]]; then
        [[ -n "$create_error" ]] && printf '%s\n' "$create_error" >&2
        fail "none of the installed Apple Watch device types is compatible with $runtime_id"
    fi
    printf 'Created: %s (%s)\n' "$simulator_udid" "$device_type"
else
    say "Reusing dedicated research simulator $simulator_udid"
fi

device_line="$(xcrun simctl list devices available |
    grep -F "$simulator_udid" | head -1 || true)"
[[ -n "$device_line" ]] || fail "created simulator is not available: $simulator_udid"
if [[ "$device_line" != *Booted* ]]; then
    say "Booting watchOS $runtime_major simulator"
    xcrun simctl boot "$simulator_udid"
    xcrun simctl bootstatus "$simulator_udid" -b
fi

if [[ "$mode" == "create" ]]; then
    printf '\n%s\n' \
        "CREATE=PASS udid=$simulator_udid" \
        "Run the face loader later with:" \
        "  bash Experiments/quickstart-system-face.sh $simulator_udid"
    exit 0
fi

say "Building and loading the Pip-Boy face"
WATCHFACELAB_FACE_TITLE="$face_title" bash "$quickstart" "$simulator_udid"

printf '\n%s\n' \
    "BOOTSTRAP=PASS udid=$simulator_udid" \
    "This simulator is dedicated to the experiment. To delete it later:" \
    "  xcrun simctl delete $simulator_udid"
