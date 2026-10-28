#!/usr/bin/env bash

# Source this file, then call watchfacelab_resolve_device_frameworks. Explicit
# WATCH_NTK_BINARY/WATCH_CLOCKKITUI_BINARY values always take precedence.
watchfacelab_resolve_device_frameworks() {
    if [[ -n "${WATCH_NTK_BINARY:-}" && -f "$WATCH_NTK_BINARY" &&
          -n "${WATCH_CLOCKKITUI_BINARY:-}" && -f "$WATCH_CLOCKKITUI_BINARY" ]]; then
        export WATCH_NTK_BINARY WATCH_CLOCKKITUI_BINARY
        return 0
    fi

    local developer_dir
    local support_filter="${WATCH_DEVICE_SUPPORT_FILTER:-}"
    local required_version="${WATCHOS_DEPLOYMENT_TARGET:-27.0}"
    local search_root
    local candidate
    local candidate_version
    local private_frameworks
    local clockkit
    local selected_ntk=""
    local selected_clockkit=""
    local -a search_roots=()

    developer_dir="$(xcode-select -p 2>/dev/null || true)"
    [[ -n "${WATCH_DEVICE_SUPPORT_ROOT:-}" ]] &&
        search_roots+=("$WATCH_DEVICE_SUPPORT_ROOT")
    search_roots+=(
        "$HOME/Library/Developer/Xcode/watchOS DeviceSupport"
        "/Library/Developer/Xcode/watchOS DeviceSupport"
    )
    [[ -n "$developer_dir" ]] &&
        search_roots+=("$developer_dir/Platforms/WatchOS.platform/DeviceSupport")

    while IFS= read -r candidate; do
        [[ -z "$candidate" ]] && continue
        if [[ -n "$support_filter" && "$candidate" != *"$support_filter"* ]]; then
            continue
        fi
        private_frameworks="$(dirname "$(dirname "$candidate")")"
        clockkit="$private_frameworks/ClockKitUI.framework/ClockKitUI"
        [[ -f "$clockkit" ]] || continue
        if ! xcrun vtool -show-build "$candidate" 2>/dev/null |
            grep -Eq 'platform[[:space:]]+WATCHOS([[:space:]]|$)'; then
            continue
        fi
        candidate_version="$(xcrun vtool -show-build "$candidate" 2>/dev/null |
            awk '/minos/ { print $2; exit }')"
        if [[ -z "$candidate_version" ]] ||
            awk -v candidate="$candidate_version" -v required="$required_version" \
                'BEGIN { exit !((candidate + 0) < (required + 0)) }'; then
            continue
        fi
        if ! xcrun vtool -show-build "$clockkit" 2>/dev/null |
            grep -Eq 'platform[[:space:]]+WATCHOS([[:space:]]|$)'; then
            continue
        fi
        selected_ntk="$candidate"
        selected_clockkit="$clockkit"
    done < <(
        for search_root in "${search_roots[@]}"; do
            [[ -d "$search_root" ]] || continue
            find "$search_root" -type f \
                -path '*/Symbols/System/Library/PrivateFrameworks/NanoTimeKit.framework/NanoTimeKit' \
                -print 2>/dev/null
        done | LC_ALL=C sort -V
    )

    if [[ -z "$selected_ntk" || -z "$selected_clockkit" ]]; then
        printf '%s\n' \
            "ERROR: matching watchOS $required_version DEVICE NanoTimeKit and ClockKitUI symbols were not found." \
            'Connect the Watch once in Xcode so DeviceSupport symbols are prepared, or export:' \
            '  WATCH_NTK_BINARY=/.../NanoTimeKit.framework/NanoTimeKit' \
            '  WATCH_CLOCKKITUI_BINARY=/.../ClockKitUI.framework/ClockKitUI' >&2
        return 2
    fi

    WATCH_NTK_BINARY="$selected_ntk"
    WATCH_CLOCKKITUI_BINARY="$selected_clockkit"
    export WATCH_NTK_BINARY WATCH_CLOCKKITUI_BINARY
    printf 'DEVICE_NTK=%s\n' "$WATCH_NTK_BINARY"
    printf 'DEVICE_CLOCKKITUI=%s\n' "$WATCH_CLOCKKITUI_BINARY"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    watchfacelab_resolve_device_frameworks
fi
