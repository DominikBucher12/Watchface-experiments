#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
parser_tool="$repo_root/Experiments/WatchFaceParser/watchface_corpus.py"
generated_root="$repo_root/Experiments/WatchFaceParser/Corpus"
runs_root="$repo_root/Experiments/WatchFaceParser/Runs"
bundle_identifier='dev.develodom.WatchFaceLab.ComplicationHost'
result_name='WatchFaceLab-ParserResult.json'

usage() {
    printf '%s\n' \
        "usage:" \
        "  $0 inspect INPUT.watchface" \
        "  $0 generate INPUT.watchface [--output CORPUS-DIR]" \
        "  $0 list CORPUS-DIR" \
        "  $0 verify CORPUS-DIR" \
        "  $0 run CORPUS-DIR CASE-ID --owned-device [--device ID]" \
        "  $0 result --owned-device [--device ID] [--output FILE]" \
        "  $0 diagnose --owned-device [--device ID] [--output DIR]" \
        "" \
        "The run command builds and imports exactly one selected case. It never" \
        "loops over the corpus and never retries an import after a possible crash."
}

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 2
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "required command is unavailable: $1"
}

discover_watch() {
    local requested="$1"
    local device_table
    local available_watch_line

    device_table="$(xcrun devicectl list devices 2>&1 || true)"
    printf '%s\n' "$device_table" >&2
    if [[ -n "$requested" ]]; then
        printf '%s\n' "$requested"
        return
    fi
    available_watch_line="$(grep -Ei 'watch' <<<"$device_table" |
        grep -E 'physical[[:space:]]*$' |
        grep -E 'available|connected' | head -1 || true)"
    awk '{ for (i = 1; i < NF; i++) if ($(i + 1) == "(UDID)") { print $i; exit } }' \
        <<<"$available_watch_line"
}

copy_result_from_device() {
    local target_device="$1"
    local local_file="$2"
    local quiet_mode="${3:-0}"
    local remote_file
    local status

    for remote_file in "Documents/$result_name" "/Documents/$result_name"; do
        rm -f "$local_file"
        set +e
        if [[ "$quiet_mode" == "1" ]]; then
            xcrun devicectl device copy from --device "$target_device" \
                --domain-type appDataContainer \
                --domain-identifier "$bundle_identifier" \
                --source "$remote_file" --destination "$local_file" \
                --quiet --timeout 5 >/dev/null 2>&1
        else
            xcrun devicectl device copy from --device "$target_device" \
                --domain-type appDataContainer \
                --domain-identifier "$bundle_identifier" \
                --source "$remote_file" --destination "$local_file" \
                --timeout 15
        fi
        status=$?
        set -e
        if [[ "$status" == "0" && -f "$local_file" ]]; then
            return 0
        fi
    done
    return 1
}

require_owned_device() {
    [[ "$1" == "1" ]] || fail \
        'physical-device actions require --owned-device to confirm this is your test device'
}

command_name="${1:-help}"
if [[ $# -gt 0 ]]; then
    shift
fi

case "$command_name" in
    help|--help|-h)
        usage
        exit 0
        ;;
    inspect)
        [[ $# -eq 1 ]] || fail 'inspect requires exactly one .watchface path'
        exec python3 "$parser_tool" inspect "$1"
        ;;
    generate)
        [[ $# -ge 1 ]] || fail 'generate requires an input .watchface path'
        input_face="$1"
        shift
        output_dir=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --output)
                    [[ $# -ge 2 ]] || fail '--output requires a directory'
                    output_dir="$2"
                    shift 2
                    ;;
                *) fail "unknown generate option: $1" ;;
            esac
        done
        if [[ -z "$output_dir" ]]; then
            input_name="$(basename "$input_face" .watchface)"
            safe_name="$(tr -cd '[:alnum:]_.-' <<<"$input_name")"
            [[ -n "$safe_name" ]] || safe_name='OwnedFace'
            output_dir="$generated_root/$safe_name-$(date -u +%Y%m%d-%H%M%S)"
        fi
        python3 "$parser_tool" generate "$input_face" "$output_dir"
        printf 'NEXT: %s list %q\n' "$0" "$output_dir"
        ;;
    list)
        [[ $# -eq 1 ]] || fail 'list requires exactly one corpus directory'
        exec python3 "$parser_tool" list "$1"
        ;;
    verify)
        [[ $# -eq 1 ]] || fail 'verify requires exactly one corpus directory'
        exec python3 "$parser_tool" verify "$1"
        ;;
    run)
        [[ $# -ge 2 ]] || fail 'run requires CORPUS-DIR and CASE-ID'
        corpus_dir="$1"
        case_id="$2"
        shift 2
        device_id="${WATCHFACELAB_DEVICE_ID:-}"
        owned_device=0
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --device)
                    [[ $# -ge 2 ]] || fail '--device requires an identifier'
                    device_id="$2"
                    shift 2
                    ;;
                --owned-device)
                    owned_device=1
                    shift
                    ;;
                *) fail "unknown run option: $1" ;;
            esac
        done
        require_owned_device "$owned_device"
        require_command python3
        require_command jq
        require_command xcrun
        require_command shasum
        [[ "$(uname -s)" == "Darwin" ]] || fail 'device runs require macOS'

        case_path="$(python3 "$parser_tool" resolve "$corpus_dir" "$case_id")"
        case_hash="$(shasum -a 256 "$case_path" | awk '{print $1}')"
        device_id="$(discover_watch "$device_id")"
        [[ -n "$device_id" ]] || fail \
            'no available physical Apple Watch; unlock it and open Xcode Devices and Simulators'

        developer_dir="$(xcode-select -p 2>/dev/null || true)"
        [[ -x "$developer_dir/usr/bin/xcodebuild" ]] || fail \
            'select a full Xcode installation with xcode-select'
        sdk_version="$(xcrun --sdk watchos --show-sdk-version)"
        required_version="${WATCHOS_DEPLOYMENT_TARGET:-27.0}"
        if awk -v sdk="$sdk_version" -v required="$required_version" \
            'BEGIN { exit !((sdk + 0) < (required + 0)) }'; then
            fail "active watchOS SDK is $sdk_version; $required_version or newer is required"
        fi

        run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$-$case_id"
        run_dir="$runs_root/$run_id"
        mkdir -p "$run_dir"
        derived_data="${WATCHFACELAB_PARSER_DERIVED_DATA:-/tmp/WatchFaceLab-Parser-$device_id}"
        destination="platform=watchOS,id=$device_id"
        jq -n \
            --arg runID "$run_id" \
            --arg caseID "$case_id" \
            --arg casePath "$case_path" \
            --arg caseSHA256 "$case_hash" \
            --arg deviceID "$device_id" \
            --arg sdkVersion "$sdk_version" \
            '{schemaVersion:1, runID:$runID, caseID:$caseID,
              casePath:$casePath, caseSHA256:$caseSHA256,
              deviceID:$deviceID, sdkVersion:$sdkVersion}' \
            >"$run_dir/run.json"

        printf 'PARSER_STEP=1/4 build one selected case id=%s sha256=%s\n' \
            "$case_id" "$case_hash"
        xcodebuild \
            -project "$repo_root/WatchFaceLab.xcodeproj" \
            -scheme WatchFaceLab \
            -configuration Debug \
            -destination "$destination" \
            -destination-timeout 120 \
            -derivedDataPath "$derived_data" \
            -allowProvisioningUpdates \
            "WATCHFACELAB_SEED_FACE=$case_path" \
            build 2>&1 | tee "$run_dir/build.log"

        app_path="$derived_data/Build/Products/Debug-watchos/WatchFaceLab.app"
        embedded_face="$app_path/PipBoy.watchface"
        [[ -d "$app_path" ]] || fail "Watch app was not produced: $app_path"
        [[ -f "$embedded_face" ]] || fail 'selected watchface was not embedded'
        embedded_hash="$(shasum -a 256 "$embedded_face" | awk '{print $1}')"
        [[ "$embedded_hash" == "$case_hash" ]] || fail \
            "embedded case hash mismatch: expected $case_hash, got $embedded_hash"
        codesign --verify --deep --strict "$app_path"

        printf 'PARSER_STEP=2/4 install signed test host on owned Watch %s\n' "$device_id"
        install_status=1
        for install_attempt in 1 2 3; do
            set +e
            xcrun devicectl device install app --device "$device_id" "$app_path" \
                --log-output "$run_dir/install-$install_attempt.log"
            install_status=$?
            set -e
            [[ "$install_status" == "0" ]] && break
            [[ "$install_attempt" == "3" ]] || sleep 3
        done
        [[ "$install_status" == "0" ]] || fail \
            'app installation failed; no import was launched'

        printf 'PARSER_STEP=3/4 launch exactly once and request public API import\n'
        launch_environment="$(jq -cn \
            --arg runID "$run_id" --arg caseID "$case_id" \
            '{WATCHFACELAB_IMPORT_ON_LAUNCH:"1",
              WATCHFACELAB_IMPORT_RUN_ID:$runID,
              WATCHFACELAB_IMPORT_CASE_ID:$caseID}')"
        xcrun devicectl device process launch --device "$device_id" \
            --environment-variables "$launch_environment" \
            --terminate-existing \
            --json-output "$run_dir/launch.json" \
            --log-output "$run_dir/launch.log" \
            "$bundle_identifier"

        printf 'PARSER_STEP=4/4 wait for the matching app result (no relaunch)\n'
        result_file="$run_dir/$result_name"
        progress_file=""
        deadline=$((SECONDS + 30))
        attempt=0
        while (( SECONDS < deadline )); do
            attempt=$((attempt + 1))
            candidate="$run_dir/result-$attempt.json"
            if copy_result_from_device "$device_id" "$candidate" 1; then
                candidate_run_id="$(jq -r '.runID // empty' "$candidate" 2>/dev/null || true)"
                if [[ "$candidate_run_id" == "$run_id" ]]; then
                    progress_file="$candidate"
                    if [[ "$(jq -r '.complete // false' "$candidate" 2>/dev/null || true)" == "true" ]]; then
                        cp "$candidate" "$result_file"
                        break
                    fi
                fi
            fi
            sleep 1
        done

        if [[ ! -f "$result_file" ]]; then
            if [[ -n "$progress_file" && -f "$progress_file" ]]; then
                cp "$progress_file" "$run_dir/last-progress.json"
                printf 'PARSER_LAST_PROGRESS %s\n' "$(jq -c . "$progress_file")"
            fi
            set +e
            xcrun devicectl device info processes --device "$device_id" \
                --timeout 15 >"$run_dir/processes-after-timeout.txt" 2>&1
            process_status=$?
            set -e
            printf '%s\n' \
                "PARSER_RESULT=TIMEOUT case=$case_id processStatus=$process_status" \
                "EVIDENCE=$run_dir" \
                "Do not rerun this case yet. If the Watch recovered, collect diagnostics with:" \
                "  $0 diagnose --owned-device --device $device_id --output '$run_dir/sysdiagnose'"
            exit 3
        fi

        printf 'PARSER_RESULT %s\n' "$(jq -c . "$result_file")"
        printf '%s\n' \
            "PARSER_RUN=PASS case=$case_id evidence=$run_dir" \
            'Run 000-baseline first. Advance to one additional case only after reviewing this result.'
        ;;
    result)
        device_id="${WATCHFACELAB_DEVICE_ID:-}"
        output_file=""
        owned_device=0
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --device)
                    [[ $# -ge 2 ]] || fail '--device requires an identifier'
                    device_id="$2"
                    shift 2
                    ;;
                --output)
                    [[ $# -ge 2 ]] || fail '--output requires a file path'
                    output_file="$2"
                    shift 2
                    ;;
                --owned-device)
                    owned_device=1
                    shift
                    ;;
                *) fail "unknown result option: $1" ;;
            esac
        done
        require_owned_device "$owned_device"
        device_id="$(discover_watch "$device_id")"
        [[ -n "$device_id" ]] || fail 'no available physical Apple Watch'
        if [[ -z "$output_file" ]]; then
            mkdir -p "$runs_root"
            output_file="$runs_root/stored-result-$(date -u +%Y%m%dT%H%M%SZ).json"
        fi
        mkdir -p "$(dirname "$output_file")"
        copy_result_from_device "$device_id" "$output_file" 0 || fail \
            'CoreDevice could not download the stored parser result'
        jq . "$output_file"
        printf 'PARSER_RESULT_FETCH=PASS FILE=%s\n' "$output_file"
        ;;
    diagnose)
        device_id="${WATCHFACELAB_DEVICE_ID:-}"
        output_dir=""
        owned_device=0
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --device)
                    [[ $# -ge 2 ]] || fail '--device requires an identifier'
                    device_id="$2"
                    shift 2
                    ;;
                --output)
                    [[ $# -ge 2 ]] || fail '--output requires a directory'
                    output_dir="$2"
                    shift 2
                    ;;
                --owned-device)
                    owned_device=1
                    shift
                    ;;
                *) fail "unknown diagnose option: $1" ;;
            esac
        done
        require_owned_device "$owned_device"
        device_id="$(discover_watch "$device_id")"
        [[ -n "$device_id" ]] || fail 'no available physical Apple Watch'
        if [[ -z "$output_dir" ]]; then
            output_dir="$runs_root/sysdiagnose-$(date -u +%Y%m%dT%H%M%SZ)"
        fi
        mkdir -p "$output_dir"
        printf '%s\n' \
            'A sysdiagnose may contain private device and account metadata.' \
            "Store it securely and review it before sharing: $output_dir"
        xcrun devicectl device sysdiagnose --device "$device_id" \
            --destination "$output_dir" --timeout 600 \
            --json-output "$output_dir/devicectl.json" \
            --log-output "$output_dir/devicectl.log"
        printf 'PARSER_SYSDIAGNOSE=PASS DIR=%s\n' "$output_dir"
        ;;
    *)
        fail "unknown command: $command_name"
        ;;
esac
