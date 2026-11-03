#!/bin/bash
set -euo pipefail

experiment_dir="$(cd "$(dirname "$0")" && pwd)"
driver="$experiment_dir/test-system-discovery-overlay.sh"
requested_udid="${1:-${WATCHFACELAB_SIMULATOR_UDID:-}}"
cleanup_needed=0
simulator_udid=""

say() {
    printf '\n==> %s\n' "$1"
}

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

cleanup_on_failure() {
    status=$?
    if [[ "$status" -ne 0 && "$cleanup_needed" == "1" &&
          -n "$simulator_udid" ]]; then
        printf '\nQuickstart failed; restoring the research simulator...\n' >&2
        bash "$driver" rollback "$simulator_udid" >/dev/null 2>&1 || true
    fi
    exit "$status"
}
trap cleanup_on_failure EXIT

if [[ "$requested_udid" == "-h" || "$requested_udid" == "--help" ]]; then
    printf '%s\n' \
        "usage: $0 [research-simulator-uuid]" \
        "" \
        "Without an argument, auto-detects the available simulator named:" \
        "  WatchFaceLab27 Research (or another WatchFaceLab Research device)"
    trap - EXIT
    exit 0
fi

if [[ "${EUID:-$(id -u)}" == "0" ]]; then
    fail "run this as your normal macOS user, not with sudo"
fi
command -v xcrun >/dev/null || fail "xcrun is unavailable; install/select Xcode first"
[[ -x "$driver" ]] || fail "missing experiment driver: $driver"

if [[ -n "$requested_udid" ]]; then
    simulator_udid="$requested_udid"
else
    device_list="$(xcrun simctl list devices available)"
    matches="$(awk -F '[()]' '/WatchFaceLab27.*Research/ { print $2 }' \
        <<<"$device_list")"
    if [[ -z "$matches" ]]; then
        matches="$(awk -F '[()]' '/WatchFaceLab.*Research/ { print $2 }' \
            <<<"$device_list")"
    fi
    match_count="$(grep -c . <<<"$matches" || true)"
    if [[ "$match_count" -eq 0 ]]; then
        fail "no available WatchFaceLab Research simulator; install/boot the intended runtime or pass its UUID"
    fi
    if [[ "$match_count" -ne 1 ]]; then
        printf '%s\n' "$matches" >&2
        fail "multiple research simulators found; pass the desired UUID explicitly"
    fi
    simulator_udid="$matches"
fi

device_line="$(xcrun simctl list devices available |
    grep -F -- "$simulator_udid" | head -1 || true)"
[[ -n "$device_line" ]] || fail "simulator is unavailable: $simulator_udid"
if [[ "$device_line" != *Research* ]]; then
    fail "refusing a simulator not marked Research: $device_line"
fi

printf '%s\n' \
    "WatchFaceLab quickstart (simulator-only research)" \
    "Device: $device_line" \
    "Face title: ${WATCHFACELAB_FACE_TITLE:-VAULT BOY}" \
    "No Apple runtime file will be modified."

if [[ "$device_line" != *Booted* ]]; then
    say "Booting the research simulator"
    xcrun simctl boot "$simulator_udid"
    xcrun simctl bootstatus "$simulator_udid" -b
fi

say "Building the face and preparing a hybrid runtime overlay"
prepare_log="${WATCHFACELAB_PREPARE_LOG:-/tmp/WatchFaceLab-prepare-$simulator_udid.log}"
if ! bash "$driver" prepare "$simulator_udid" 2>&1 | tee "$prepare_log"; then
    fail "prepare failed; full output is saved in $prepare_log"
fi
prepare_output="$(<"$prepare_log")"
overlay_root="$(sed -n 's/^OVERLAY_ROOT=//p' <<<"$prepare_output" | tail -1)"
[[ -n "$overlay_root" && -d "$overlay_root" ]] ||
    fail "prepare did not return a usable overlay"

say "Loading the bundle in ClockFace and nanotimekitd"
bash "$driver" activate "$simulator_udid" "$overlay_root"
cleanup_needed=1

say "Adding and selecting the custom face"
set +e
install_output="$(bash "$driver" install "$simulator_udid" 2>&1)"
install_status=$?
set -e
printf '%s\n' "$install_output"
if [[ "$install_status" -ne 0 ]]; then
    if grep -Fq 'custom face already present' <<<"$install_output"; then
        printf 'The custom face is already installed; keeping it.\n'
        cleanup_needed=0
    else
        exit "$install_status"
    fi
fi
face_index="$(sed -nE 's/.*"index":([0-9]+).*/\1/p' \
    <<<"$install_output" | tail -1)"
[[ -n "$face_index" ]] ||
    fail "the collection probe did not report the custom face index"

say "Switching the live ClockFace UI to custom face index $face_index"
bash "$driver" show "$simulator_udid" "$face_index"

open -a Simulator >/dev/null 2>&1 || true
cleanup_needed=0
trap - EXIT

printf '\n%s\n' \
    "READY: the Pip-Boy face is installed, selected, and animating." \
    "The simulated display may be asleep after ClockFace restarts." \
    "Click the Crown button in Simulator once to wake it; press it again only if an app is covering the face." \
    "Change the title later with:" \
    "  bash Experiments/set-watchface-title.sh \"NEW TITLE\" $simulator_udid" \
    "Overlay: $overlay_root" \
    "" \
    "Clean rollback:" \
    "  bash Experiments/test-system-discovery-overlay.sh rollback $simulator_udid"
