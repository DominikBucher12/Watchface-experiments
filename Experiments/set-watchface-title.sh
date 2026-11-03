#!/bin/bash
set -euo pipefail

experiment_dir="$(cd "$(dirname "$0")" && pwd)"
driver="$experiment_dir/test-system-discovery-overlay.sh"
face_title="${1:-}"
requested_udid="${2:-${WATCHFACELAB_SIMULATOR_UDID:-}}"

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

if [[ "$face_title" == "-h" || "$face_title" == "--help" ]]; then
    printf '%s\n' \
        "usage: $0 \"DISPLAY TITLE\" [research-simulator-uuid]" \
        "" \
        "Examples:" \
        "  bash Experiments/set-watchface-title.sh \"VAULT BOY\"" \
        "  bash Experiments/set-watchface-title.sh \"PIP-BOY 3000\" SIMULATOR-UUID" \
        "" \
        "Without a UUID, the script auto-detects the available WatchFaceLab Research simulator."
    exit 0
fi

[[ -n "$face_title" ]] || fail "pass the new display title; use --help for examples"
if [[ "$face_title" == *$'\n'* || "$face_title" == *$'\r'* || ${#face_title} -gt 64 ]]; then
    fail "title must contain 1-64 characters on one line"
fi
command -v xcrun >/dev/null || fail "xcrun is unavailable; install/select Xcode first"
[[ -x "$driver" ]] || fail "missing experiment driver: $driver"

if [[ -z "$requested_udid" ]]; then
    device_list="$(xcrun simctl list devices available)"
    matches="$(awk -F '[()]' '/WatchFaceLab27.*Research/ { print $2 }' <<<"$device_list")"
    if [[ -z "$matches" ]]; then
        matches="$(awk -F '[()]' '/WatchFaceLab.*Research/ { print $2 }' <<<"$device_list")"
    fi
    match_count="$(grep -c . <<<"$matches" || true)"
    [[ "$match_count" -gt 0 ]] || fail "no available WatchFaceLab Research simulator; run bootstrap first"
    [[ "$match_count" -eq 1 ]] || fail "multiple research simulators found; pass the desired UUID"
    requested_udid="$matches"
fi

device_line="$(xcrun simctl list devices available |
    grep -F -- "$requested_udid" | head -1 || true)"
[[ -n "$device_line" ]] || fail "simulator is unavailable: $requested_udid"
[[ "$device_line" == *Research* ]] || fail "refusing a simulator not marked Research: $device_line"
[[ "$device_line" == *Booted* ]] || fail "research simulator is not booted; run bootstrap first"

printf 'Changing custom face title on: %s\n' "$device_line"
bash "$driver" title "$requested_udid" "$face_title"
open -a Simulator >/dev/null 2>&1 || true
printf '%s\n' \
    "The custom face title is now: $face_title" \
    "If the display is asleep, click the Crown button once."
