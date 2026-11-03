#!/bin/bash
set -euo pipefail

experiments_dir="$(cd "$(dirname "$0")" && pwd)"
action="${1:-}"
simulator_udid="${2:-}"
overlay_root="${3:-}"
build_root="${WATCHFACELAB_BUILD_ROOT:-/tmp/WatchFaceLab-SystemLoaderBuild-$simulator_udid}"

usage() {
    printf '%s\n' \
        "usage: $0 prepare <research-simulator-udid>" \
        "       $0 activate <research-simulator-udid> <overlay-root>" \
        "       $0 install <research-simulator-udid>" \
        "       $0 show <research-simulator-udid> <face-index>" \
        "       $0 remove <research-simulator-udid>" \
        "       $0 status <research-simulator-udid>" \
        "       $0 title <research-simulator-udid> <display-title>" \
        "       $0 rollback <research-simulator-udid>"
}

if [[ -z "$action" || -z "$simulator_udid" ]]; then
    usage >&2
    exit 64
fi

device_line="$(xcrun simctl list devices | grep "$simulator_udid" | head -1 || true)"
if [[ -z "$device_line" ]]; then
    printf 'ERROR: simulator not found: %s\n' "$simulator_udid" >&2
    exit 65
fi
if [[ "$device_line" != *Research* && "${WATCHFACELAB_ALLOW_NON_RESEARCH:-0}" != "1" ]]; then
    printf 'ERROR: refusing non-research simulator: %s\n' "$device_line" >&2
    exit 66
fi

runtime_root() {
    # watchOS 27.2 rejects spawning /usr/bin/env with LaunchdSimError 111,
    # while simctl getenv still exposes the runtime root reliably.
    local runtime=""
    runtime="$(xcrun simctl spawn "$simulator_udid" /usr/bin/env 2>/dev/null |
        sed -n 's/^IPHONE_SIMULATOR_ROOT=//p' | head -1 || true)"
    if [[ -n "$runtime" ]]; then
        printf '%s\n' "$runtime"
        return
    fi
    xcrun simctl getenv "$simulator_udid" IPHONE_SIMULATOR_ROOT
}

job_pid() {
    pattern="$1"
    xcrun simctl spawn "$simulator_udid" launchctl list |
        awk -v pattern="$pattern" 'index($0, pattern) { print $1; exit }'
}

link_children_except() {
    source_dir="$1"
    destination_dir="$2"
    excluded_name="$3"
    mkdir -p "$destination_dir"
    while IFS= read -r -d '' entry; do
        name="$(basename "$entry")"
        if [[ "$name" != "$excluded_name" ]]; then
            ln -s "$entry" "$destination_dir/$name"
        fi
    done < <(find "$source_dir" -mindepth 1 -maxdepth 1 -print0)
}

case "$action" in
    prepare)
        printf 'PREPARE_STEP=1/3 resolve simulator runtime\n'
        runtime="$(runtime_root)"
        if [[ -z "$runtime" || ! -d "$runtime/System/Library/NanoTimeKit/FaceBundles" ]]; then
            printf 'ERROR: face bundle root unavailable for %s\n' "$runtime" >&2
            exit 67
        fi
        printf 'PREPARE_RUNTIME=%s\n' "$runtime"
        printf 'PREPARE_STEP=2/3 build loader artifacts\n'
        WATCH_RUNTIME_ROOT="$runtime" \
            bash "$experiments_dir/build-system-loader.sh" "$build_root"
        printf 'PREPARE_STEP=3/3 clone face bundles into temporary overlay\n'
        overlay_root="$(mktemp -d /tmp/WatchFaceLabSystemRoot.XXXXXX)"
        overlay_faces="$overlay_root/System/Library/NanoTimeKit/FaceBundles"
        # IPHONE_SIMULATOR_ROOT affects framework/resource lookup process-wide,
        # not just NTKBundleLoader. Keep the complete runtime reachable while
        # replacing only FaceBundles with a real directory. Bundle entries in
        # FaceBundles cannot themselves be symlinks because NTKBundleLoader
        # skips them.
        link_children_except "$runtime" "$overlay_root" System
        link_children_except "$runtime/System" "$overlay_root/System" Library
        link_children_except "$runtime/System/Library" \
            "$overlay_root/System/Library" NanoTimeKit
        link_children_except "$runtime/System/Library/NanoTimeKit" \
            "$overlay_root/System/Library/NanoTimeKit" FaceBundles
        mkdir -p "$overlay_faces"
        # NTKBundleLoader ignores symlinked bundle entries. APFS clone-copy keeps
        # the original bundles visible without modifying the runtime volume.
        cp -cR "$runtime/System/Library/NanoTimeKit/FaceBundles/." "$overlay_faces/"
        cp -R "$build_root/FaceBundles/MYLocalFaceBundle.bundle" "$overlay_faces/"
        cp "$build_root/MYCustomFaceExperiment.dylib" \
            "$overlay_root/System/Library/NanoTimeKit/"
        system_count="$(find "$runtime/System/Library/NanoTimeKit/FaceBundles" \
            -maxdepth 1 -name '*.bundle' | wc -l | tr -d ' ')"
        overlay_count="$(find "$overlay_faces" -maxdepth 1 -name '*.bundle' |
            wc -l | tr -d ' ')"
        if [[ "$overlay_count" -ne $((system_count + 1)) ]]; then
            printf 'ERROR: overlay count %s, expected %s\n' \
                "$overlay_count" "$((system_count + 1))" >&2
            exit 68
        fi
        printf 'OVERLAY_ROOT=%s\n' "$overlay_root"
        printf 'SYSTEM_BUNDLES=%s OVERLAY_BUNDLES=%s\n' "$system_count" "$overlay_count"
        ;;

    activate)
        if [[ -z "$overlay_root" || ! -d "$overlay_root/System/Library/NanoTimeKit/FaceBundles/MYLocalFaceBundle.bundle" ]]; then
            printf 'ERROR: invalid overlay root: %s\n' "$overlay_root" >&2
            exit 69
        fi
        bootstrap="$build_root/SystemRootBootstrap.dylib"
        if [[ ! -f "$bootstrap" ]]; then
            printf 'ERROR: missing root bootstrap; run prepare first\n' >&2
            exit 70
        fi
        activation_complete=0
        cleanup_failed_activation() {
            if [[ "$activation_complete" != "1" ]]; then
                xcrun simctl spawn "$simulator_udid" launchctl unsetenv \
                    DYLD_INSERT_LIBRARIES || true
                xcrun simctl spawn "$simulator_udid" launchctl unsetenv \
                    WATCHFACELAB_SYSTEM_DISCOVERY_PROBE || true
                xcrun simctl spawn "$simulator_udid" launchctl unsetenv \
                    WATCHFACELAB_OVERLAY_ROOT || true
                xcrun simctl spawn "$simulator_udid" launchctl unsetenv \
                    WATCHFACELAB_FACE_TITLE || true
                xcrun simctl spawn "$simulator_udid" launchctl kickstart -k \
                    system/com.apple.nanotimekitd || true
                xcrun simctl terminate "$simulator_udid" \
                    com.apple.clockface || true
            fi
        }
        trap cleanup_failed_activation EXIT
        xcrun simctl spawn "$simulator_udid" launchctl setenv \
            WATCHFACELAB_OVERLAY_ROOT "$overlay_root"
        xcrun simctl spawn "$simulator_udid" launchctl setenv \
            WATCHFACELAB_SYSTEM_DISCOVERY_PROBE 1
        xcrun simctl spawn "$simulator_udid" launchctl setenv \
            WATCHFACELAB_FACE_TITLE "${WATCHFACELAB_FACE_TITLE:-VAULT BOY}"
        xcrun simctl spawn "$simulator_udid" launchctl setenv \
            DYLD_INSERT_LIBRARIES "$bootstrap"
        xcrun simctl spawn "$simulator_udid" launchctl kickstart -k \
            system/com.apple.nanotimekitd
        xcrun simctl terminate "$simulator_udid" com.apple.clockface
        sleep 4
        # New processes have already inherited and loaded the bootstrap.
        xcrun simctl spawn "$simulator_udid" launchctl unsetenv \
            DYLD_INSERT_LIBRARIES
        activation_logs=""
        for _attempt in {1..12}; do
            clockface_pid="$(job_pid 'UIKitApplication:com.apple.clockface')"
            nanotimekitd_pid="$(job_pid 'com.apple.nanotimekitd')"
            activation_logs="$(xcrun simctl spawn "$simulator_udid" log show \
                --last 1m --info --debug --style compact \
                --predicate 'eventMessage CONTAINS "WATCHFACELAB_ROOT_BOOTSTRAP" OR eventMessage CONTAINS "WATCHFACELAB_SYSTEM_BUNDLE_LOADED"')"
            if [[ -n "$clockface_pid" && -n "$nanotimekitd_pid" ]] &&
                grep -Fq "WATCHFACELAB_SYSTEM_BUNDLE_LOADED pid=$clockface_pid host=com.apple.clockface" \
                    <<<"$activation_logs" &&
                grep -Fq "WATCHFACELAB_SYSTEM_BUNDLE_LOADED pid=$nanotimekitd_pid host=com.apple.nanotimekitd" \
                    <<<"$activation_logs"; then
                break
            fi
            sleep 1
        done
        sleep 2
        stable_clockface_pid="$(job_pid 'UIKitApplication:com.apple.clockface')"
        stable_nanotimekitd_pid="$(job_pid 'com.apple.nanotimekitd')"
        if [[ -z "$clockface_pid" || -z "$nanotimekitd_pid" ||
              "$clockface_pid" != "$stable_clockface_pid" ||
              "$nanotimekitd_pid" != "$stable_nanotimekitd_pid" ]] ||
            ! grep -Fq "WATCHFACELAB_SYSTEM_BUNDLE_LOADED pid=$clockface_pid host=com.apple.clockface" \
                <<<"$activation_logs" ||
            ! grep -Fq "WATCHFACELAB_SYSTEM_BUNDLE_LOADED pid=$nanotimekitd_pid host=com.apple.nanotimekitd" \
                <<<"$activation_logs"; then
            printf 'ERROR: injected jobs did not remain stable or load the custom bundle\n' >&2
            printf 'ClockFace: %s -> %s; nanotimekitd: %s -> %s\n' \
                "$clockface_pid" "$stable_clockface_pid" \
                "$nanotimekitd_pid" "$stable_nanotimekitd_pid" >&2
            exit 73
        fi
        printf 'ACTIVATED ClockFace=%s nanotimekitd=%s overlay=%s\n' \
            "$clockface_pid" "$nanotimekitd_pid" "$overlay_root"
        activation_complete=1
        trap - EXIT
        "$0" status "$simulator_udid"
        ;;

    status)
        overlay_root="$(xcrun simctl spawn "$simulator_udid" launchctl getenv WATCHFACELAB_OVERLAY_ROOT || true)"
        printf 'WATCHFACELAB_OVERLAY_ROOT=%s\n' "$overlay_root"
        printf 'WATCHFACELAB_SYSTEM_DISCOVERY_PROBE=%s\n' \
            "$(xcrun simctl spawn "$simulator_udid" launchctl getenv WATCHFACELAB_SYSTEM_DISCOVERY_PROBE || true)"
        printf 'WATCHFACELAB_FACE_TITLE=%s\n' \
            "$(xcrun simctl spawn "$simulator_udid" launchctl getenv WATCHFACELAB_FACE_TITLE || true)"
        xcrun simctl spawn "$simulator_udid" launchctl list |
            grep -E 'com.apple.nanotimekitd|UIKitApplication:com.apple.clockface' || true
        probe="$build_root/SystemDiscoveryProbe"
        runtime="$(runtime_root)"
        if [[ -x "$probe" && -n "$overlay_root" ]]; then
            SIMCTL_CHILD_DYLD_ROOT_PATH="$runtime" \
                SIMCTL_CHILD_WATCHFACELAB_OVERLAY_ROOT="$overlay_root" \
                SIMCTL_CHILD_WATCHFACELAB_SYSTEM_DISCOVERY_PROBE=1 \
                xcrun simctl spawn "$simulator_udid" \
                "$probe" 2>/tmp/WatchFaceLabSystemDiscoveryProbe.stderr || true
        fi
        xcrun simctl spawn "$simulator_udid" log show \
            --last 5m --info --debug --style compact \
            --predicate 'eventMessage CONTAINS "WATCHFACELAB_ROOT_BOOTSTRAP" OR eventMessage CONTAINS "WATCHFACELAB_SYSTEM_BUNDLE_LOADED" OR eventMessage CONTAINS "MYLocalFaceBundle"' |
            tail -40 || true
        ;;

    install|remove)
        mutation_probe="$build_root/CollectionMutationProbe"
        if [[ ! -x "$mutation_probe" ]]; then
            printf 'ERROR: missing mutation probe; run prepare first\n' >&2
            exit 71
        fi
        overlay_root="$(xcrun simctl spawn "$simulator_udid" launchctl getenv WATCHFACELAB_OVERLAY_ROOT || true)"
        runtime="$(runtime_root)"
        if [[ -z "$overlay_root" ]]; then
            printf 'ERROR: overlay is not active\n' >&2
            exit 72
        fi
        SIMCTL_CHILD_DYLD_ROOT_PATH="$runtime" \
            SIMCTL_CHILD_WATCHFACELAB_OVERLAY_ROOT="$overlay_root" \
            SIMCTL_CHILD_WATCHFACELAB_SYSTEM_DISCOVERY_PROBE=1 \
            xcrun simctl spawn "$simulator_udid" \
            "$mutation_probe" "$action"
        ;;

    show)
        face_index="${3:-}"
        if [[ ! "$face_index" =~ ^[0-9]+$ || "$face_index" -gt 31 ]]; then
            printf 'ERROR: invalid face index: %s\n' "$face_index" >&2
            exit 74
        fi
        overlay_root="$(xcrun simctl spawn "$simulator_udid" launchctl getenv WATCHFACELAB_OVERLAY_ROOT || true)"
        bootstrap="$build_root/SystemRootBootstrap.dylib"
        selector="$build_root/ActiveFaceSelector.dylib"
        if [[ -z "$overlay_root" || ! -f "$bootstrap" || ! -f "$selector" ]]; then
            printf 'ERROR: active overlay or selector build is missing\n' >&2
            exit 75
        fi
        cleanup_show() {
            xcrun simctl spawn "$simulator_udid" launchctl unsetenv \
                DYLD_INSERT_LIBRARIES || true
            xcrun simctl spawn "$simulator_udid" launchctl unsetenv \
                WATCHFACELAB_SELECT_FACE_INDEX || true
        }
        trap cleanup_show EXIT
        xcrun simctl spawn "$simulator_udid" launchctl setenv \
            WATCHFACELAB_SELECT_FACE_INDEX "$face_index"
        xcrun simctl spawn "$simulator_udid" launchctl setenv \
            DYLD_INSERT_LIBRARIES "$bootstrap:$selector"
        xcrun simctl terminate "$simulator_udid" com.apple.clockface
        sleep 2
        cleanup_show
        trap - EXIT
        clockface_pid=""
        show_logs=""
        for _attempt in {1..15}; do
            clockface_pid="$(job_pid 'UIKitApplication:com.apple.clockface')"
            show_logs="$(xcrun simctl spawn "$simulator_udid" log show \
                --last 1m --info --debug --style compact \
                --predicate 'eventMessage CONTAINS "WATCHFACELAB_ACTIVE_FACE_"')"
            if [[ -n "$clockface_pid" ]] &&
                grep -Fq "WATCHFACELAB_ACTIVE_FACE_SELECTED pid=$clockface_pid index=$face_index" \
                <<<"$show_logs"; then
                break
            fi
            sleep 1
        done
        printf '%s\n' "$show_logs"
        if ! grep -Fq "WATCHFACELAB_ACTIVE_FACE_SELECTED pid=$clockface_pid index=$face_index" \
            <<<"$show_logs"; then
            printf 'ERROR: active face selection was not confirmed\n' >&2
            exit 76
        fi
        ;;

    title)
        face_title="$overlay_root"
        if [[ -z "$face_title" || "$face_title" == *$'\n'* ||
              "$face_title" == *$'\r'* || ${#face_title} -gt 64 ]]; then
            printf 'ERROR: title must contain 1-64 characters on one line\n' >&2
            exit 77
        fi
        active_overlay="$(xcrun simctl spawn "$simulator_udid" launchctl getenv WATCHFACELAB_OVERLAY_ROOT || true)"
        bootstrap="$build_root/SystemRootBootstrap.dylib"
        if [[ -z "$active_overlay" || ! -d "$active_overlay" || ! -f "$bootstrap" ]]; then
            printf 'ERROR: active overlay or bootstrap build is missing; run quickstart first\n' >&2
            exit 75
        fi
        cleanup_title() {
            xcrun simctl spawn "$simulator_udid" launchctl unsetenv \
                DYLD_INSERT_LIBRARIES || true
        }
        trap cleanup_title EXIT
        xcrun simctl spawn "$simulator_udid" launchctl setenv \
            WATCHFACELAB_FACE_TITLE "$face_title"
        xcrun simctl spawn "$simulator_udid" launchctl setenv \
            DYLD_INSERT_LIBRARIES "$bootstrap"
        xcrun simctl spawn "$simulator_udid" launchctl kickstart -k \
            system/com.apple.nanotimekitd
        xcrun simctl terminate "$simulator_udid" com.apple.clockface
        sleep 2
        cleanup_title
        trap - EXIT
        title_logs=""
        for _attempt in {1..15}; do
            title_logs="$(xcrun simctl spawn "$simulator_udid" log show \
                --last 1m --info --debug --style compact \
                --predicate 'eventMessage CONTAINS "WATCHFACELAB_FACE_TITLE"')"
            if grep -Fq "WATCHFACELAB_FACE_TITLE key=FACE_STYLE_44_IN_TITLE_CASE value=$face_title" \
                <<<"$title_logs"; then
                break
            fi
            sleep 1
        done
        if ! grep -Fq "WATCHFACELAB_FACE_TITLE key=FACE_STYLE_44_IN_TITLE_CASE value=$face_title" \
            <<<"$title_logs"; then
            printf 'ERROR: ClockFace did not confirm the requested title\n' >&2
            exit 78
        fi
        printf 'TITLE=PASS value=%s\n' "$face_title"
        ;;

    rollback)
        mutation_probe="$build_root/CollectionMutationProbe"
        overlay_root="$(xcrun simctl spawn "$simulator_udid" launchctl getenv WATCHFACELAB_OVERLAY_ROOT || true)"
        runtime="$(runtime_root)"
        if [[ -x "$mutation_probe" && -n "$overlay_root" ]]; then
            SIMCTL_CHILD_DYLD_ROOT_PATH="$runtime" \
                SIMCTL_CHILD_WATCHFACELAB_OVERLAY_ROOT="$overlay_root" \
                SIMCTL_CHILD_WATCHFACELAB_SYSTEM_DISCOVERY_PROBE=1 \
                xcrun simctl spawn "$simulator_udid" \
                "$mutation_probe" remove || true
        fi
        xcrun simctl spawn "$simulator_udid" launchctl unsetenv \
            DYLD_INSERT_LIBRARIES || true
        xcrun simctl spawn "$simulator_udid" launchctl unsetenv \
            WATCHFACELAB_SYSTEM_DISCOVERY_PROBE || true
        xcrun simctl spawn "$simulator_udid" launchctl unsetenv \
            WATCHFACELAB_OVERLAY_ROOT || true
        xcrun simctl spawn "$simulator_udid" launchctl unsetenv \
            WATCHFACELAB_FACE_TITLE || true
        xcrun simctl spawn "$simulator_udid" launchctl unsetenv \
            WATCHFACELAB_TEST || true
        xcrun simctl spawn "$simulator_udid" launchctl kickstart -k \
            system/com.apple.nanotimekitd
        xcrun simctl terminate "$simulator_udid" com.apple.clockface || true
        sleep 3
        "$0" status "$simulator_udid"
        ;;

    *)
        usage >&2
        exit 64
        ;;
esac
