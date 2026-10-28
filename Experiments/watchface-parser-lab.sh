#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
script_path="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
parser_tool="$repo_root/Experiments/WatchFaceParser/watchface_corpus.py"
generated_root="$repo_root/Experiments/WatchFaceParser/Corpus"
runs_root="$repo_root/Experiments/WatchFaceParser/Runs"
bundle_identifier='dev.develodom.WatchFaceLab.ComplicationHost'
result_name='WatchFaceLab-ParserResult.json'

usage() {
    printf '%s\n' \
        "usage:" \
        "  $0 capture [--downloads DIR] [--timeout SECONDS] [--output CORPUS-DIR]" \
        "  $0 inspect INPUT.watchface" \
        "  $0 generate INPUT.watchface [--output CORPUS-DIR]" \
        "  $0 list CORPUS-DIR" \
        "  $0 verify CORPUS-DIR" \
        "  $0 run CORPUS-DIR CASE-ID --owned-device [--device ID]" \
        "  $0 batch CORPUS-DIR [--plan] [--owned-device] [--device ID]" \
        "       [--cases ID,ID,...] [--cooldown SECONDS] [--rerun-completed]" \
        "  $0 result --owned-device [--device ID] [--output FILE]" \
        "  $0 diagnose --owned-device [--device ID] [--output DIR]" \
        "" \
        "The run command imports exactly one selected case. Batch runs a bounded" \
        "ordered set, skips completed hashes, and stops at the first anomaly."
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

    if [[ -n "$requested" ]]; then
        printf '%s\n' "$requested"
        return
    fi
    device_table="$(xcrun devicectl list devices 2>&1 || true)"
    printf '%s\n' "$device_table" >&2
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

case_has_complete_result() {
    local wanted_id="$1"
    local wanted_hash="$2"
    local run_metadata
    local run_directory
    local stored_result

    [[ -d "$runs_root" ]] || return 1
    while IFS= read -r run_metadata; do
        [[ -f "$run_metadata" ]] || continue
        if ! jq -e --arg caseID "$wanted_id" --arg caseSHA256 "$wanted_hash" \
            '.caseID == $caseID and .caseSHA256 == $caseSHA256' \
            "$run_metadata" >/dev/null 2>&1; then
            continue
        fi
        run_directory="$(dirname "$run_metadata")"
        stored_result="$run_directory/$result_name"
        if [[ -f "$stored_result" ]] && \
            jq -e --arg caseID "$wanted_id" \
                '.caseID == $caseID and .complete == true' \
                "$stored_result" >/dev/null 2>&1; then
            return 0
        fi
    done < <(find "$runs_root" -mindepth 2 -maxdepth 2 -type f \
        -name run.json -print 2>/dev/null)
    return 1
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
    capture)
        downloads_dir="$HOME/Downloads"
        capture_timeout=300
        output_dir=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --downloads)
                    [[ $# -ge 2 ]] || fail '--downloads requires a directory'
                    downloads_dir="$2"
                    shift 2
                    ;;
                --timeout)
                    [[ $# -ge 2 ]] || fail '--timeout requires seconds'
                    capture_timeout="$2"
                    [[ "$capture_timeout" =~ ^[1-9][0-9]*$ ]] || fail \
                        '--timeout must be a positive integer'
                    shift 2
                    ;;
                --output)
                    [[ $# -ge 2 ]] || fail '--output requires a directory'
                    output_dir="$2"
                    shift 2
                    ;;
                *) fail "unknown capture option: $1" ;;
            esac
        done
        [[ -d "$downloads_dir" ]] || fail \
            "download directory does not exist: $downloads_dir"
        require_command python3

        before_list="$(mktemp /tmp/WatchFaceLab-Capture-Before.XXXXXX)"
        current_list="$(mktemp /tmp/WatchFaceLab-Capture-Current.XXXXXX)"
        trap 'rm -f "$before_list" "$current_list"' EXIT
        find "$downloads_dir" -maxdepth 1 -type f -iname '*.watchface' -print |
            LC_ALL=C sort >"$before_list"

        printf '%s\n' \
            "CAPTURE_WAITING directory=$downloads_dir timeout=${capture_timeout}s" \
            'On iPhone: Watch app -> My Watch -> tap a built-in face -> Share -> AirDrop to this Mac.' \
            'Use an Apple face without third-party/development complications for the baseline.'

        captured_face=""
        deadline=$((SECONDS + capture_timeout))
        while (( SECONDS < deadline )); do
            find "$downloads_dir" -maxdepth 1 -type f -iname '*.watchface' -print |
                LC_ALL=C sort >"$current_list"
            captured_face="$(comm -13 "$before_list" "$current_list" | head -1 || true)"
            if [[ -n "$captured_face" && -f "$captured_face" ]]; then
                first_size="$(stat -f '%z' "$captured_face")"
                sleep 2
                second_size="$(stat -f '%z' "$captured_face")"
                if [[ "$first_size" == "$second_size" && "$second_size" != "0" ]]; then
                    break
                fi
                captured_face=""
            fi
            sleep 2
        done
        [[ -n "$captured_face" ]] || fail \
            "no new .watchface appeared in $downloads_dir within ${capture_timeout}s"

        if [[ -z "$output_dir" ]]; then
            input_name="$(basename "$captured_face" .watchface)"
            safe_name="$(tr -cd '[:alnum:]_.-' <<<"$input_name")"
            [[ -n "$safe_name" ]] || safe_name='OwnedFace'
            output_dir="$generated_root/$safe_name-$(date -u +%Y%m%d-%H%M%S)"
        fi
        printf 'CAPTURED_FACE=%s\n' "$captured_face"
        python3 "$parser_tool" inspect "$captured_face"
        python3 "$parser_tool" generate "$captured_face" "$output_dir"
        printf '%s\n' \
            "CORPUS=$output_dir" \
            "NEXT: $0 run '$output_dir' 000-baseline --owned-device"
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
    batch)
        [[ $# -ge 1 ]] || fail 'batch requires a corpus directory'
        corpus_dir="$1"
        shift
        device_id="${WATCHFACELAB_DEVICE_ID:-}"
        owned_device=0
        plan_only=0
        rerun_completed=0
        cooldown_seconds=5
        cases_csv=""
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
                --plan)
                    plan_only=1
                    shift
                    ;;
                --rerun-completed)
                    rerun_completed=1
                    shift
                    ;;
                --cases)
                    [[ $# -ge 2 ]] || fail '--cases requires comma-separated identifiers'
                    cases_csv="$2"
                    shift 2
                    ;;
                --cooldown)
                    [[ $# -ge 2 ]] || fail '--cooldown requires seconds'
                    cooldown_seconds="$2"
                    [[ "$cooldown_seconds" =~ ^[0-9]+$ ]] || fail \
                        '--cooldown must be a nonnegative integer'
                    shift 2
                    ;;
                *) fail "unknown batch option: $1" ;;
            esac
        done

        require_command python3
        require_command jq
        require_command shasum
        python3 "$parser_tool" verify "$corpus_dir" >/dev/null
        available_cases="$(python3 "$parser_tool" list "$corpus_dir" |
            awk -F '\t' '{print $1}')"

        if [[ -n "$cases_csv" ]]; then
            IFS=',' read -r -a selected_cases <<<"$cases_csv"
        else
            selected_cases=(
                000-baseline
                300-extra-unknown-entry
                104-metadata-unknown-key
                011-appended-tail
                010-truncated-tail
                102-metadata-bitflip
                101-metadata-truncated
                100-metadata-empty
                103-metadata-removed
                201-asset-bitflip
                200-asset-truncated
                202-asset-removed
            )
        fi
        (( ${#selected_cases[@]} <= 12 )) || fail \
            'batch is limited to 12 explicitly bounded cases'

        batch_plan="$(mktemp /tmp/WatchFaceLab-BatchPlan.XXXXXX)"
        trap 'rm -f "$batch_plan"' EXIT
        planned_count=0
        for case_id in "${selected_cases[@]}"; do
            if ! grep -Fqx "$case_id" <<<"$available_cases"; then
                if [[ -n "$cases_csv" ]]; then
                    fail "requested batch case is unavailable: $case_id"
                fi
                printf 'BATCH_CASE=OMIT case=%s reason=not-in-corpus\n' "$case_id"
                continue
            fi
            case_path="$(python3 "$parser_tool" resolve "$corpus_dir" "$case_id")"
            case_hash="$(shasum -a 256 "$case_path" | awk '{print $1}')"
            if [[ "$rerun_completed" != "1" ]] && \
                case_has_complete_result "$case_id" "$case_hash"; then
                printf 'BATCH_CASE=SKIP case=%s reason=complete hash=%s\n' \
                    "$case_id" "$case_hash"
                continue
            fi
            printf '%s\t%s\n' "$case_id" "$case_hash" >>"$batch_plan"
            planned_count=$((planned_count + 1))
            printf 'BATCH_CASE=PLAN case=%s hash=%s\n' "$case_id" "$case_hash"
        done
        if [[ "$plan_only" == "1" ]]; then
            batch_mode='plan'
        else
            batch_mode='run'
        fi
        printf 'BATCH_PLAN=PASS cases=%s mode=%s\n' "$planned_count" "$batch_mode"

        if [[ "$plan_only" == "1" || "$planned_count" == "0" ]]; then
            exit 0
        fi

        require_owned_device "$owned_device"
        require_command xcrun
        [[ "$(uname -s)" == "Darwin" ]] || fail 'device batches require macOS'
        device_id="$(discover_watch "$device_id")"
        [[ -n "$device_id" ]] || fail \
            'no available physical Apple Watch; unlock it and open Xcode Devices and Simulators'

        batch_id="batch-$(date -u +%Y%m%dT%H%M%SZ)-$$"
        batch_dir="$runs_root/$batch_id"
        mkdir -p "$batch_dir"
        summary_file="$batch_dir/summary.tsv"
        printf 'caseID\tstatus\tsuccess\tsha256\n' >"$summary_file"

        while IFS=$'\t' read -r case_id case_hash; do
            [[ -n "$case_id" ]] || continue
            case_log="$batch_dir/$case_id.log"
            printf 'BATCH_CASE=RUN case=%s device=%s\n' "$case_id" "$device_id"
            set +e
            bash "$script_path" run "$corpus_dir" "$case_id" \
                --owned-device --device "$device_id" 2>&1 | tee "$case_log"
            case_status=${PIPESTATUS[0]}
            set -e
            if [[ "$case_status" != "0" ]]; then
                printf '%s\tSTOP-%s\tunknown\t%s\n' \
                    "$case_id" "$case_status" "$case_hash" >>"$summary_file"
                printf '%s\n' \
                    "BATCH_STOP case=$case_id status=$case_status" \
                    "BATCH_EVIDENCE=$batch_dir" \
                    'Do not rerun the stopped case until its log has been reviewed.'
                exit "$case_status"
            fi

            result_json="$(sed -n 's/^PARSER_RESULT //p' "$case_log" | tail -1)"
            if [[ -z "$result_json" ]] || ! jq -e \
                --arg caseID "$case_id" \
                '.caseID == $caseID and .complete == true' \
                >/dev/null 2>&1 <<<"$result_json"; then
                printf '%s\tSTOP-invalid-result\tunknown\t%s\n' \
                    "$case_id" "$case_hash" >>"$summary_file"
                printf '%s\n' \
                    "BATCH_STOP case=$case_id status=invalid-result" \
                    "BATCH_EVIDENCE=$batch_dir"
                exit 3
            fi
            case_success="$(jq -r '.success // false' <<<"$result_json")"

            set +e
            xcrun devicectl device info processes --device "$device_id" \
                --quiet --timeout 15 >/dev/null 2>&1
            health_status=$?
            set -e
            if [[ "$health_status" != "0" ]]; then
                printf '%s\tSTOP-device-unavailable\t%s\t%s\n' \
                    "$case_id" "$case_success" "$case_hash" >>"$summary_file"
                printf '%s\n' \
                    "BATCH_STOP case=$case_id status=device-unavailable" \
                    "BATCH_EVIDENCE=$batch_dir"
                exit 3
            fi

            printf '%s\tPASS\t%s\t%s\n' \
                "$case_id" "$case_success" "$case_hash" >>"$summary_file"
            printf 'BATCH_CASE=PASS case=%s success=%s\n' \
                "$case_id" "$case_success"
            if [[ "$cooldown_seconds" != "0" ]]; then
                sleep "$cooldown_seconds"
            fi
        done <"$batch_plan"

        printf '%s\n' \
            "BATCH_RESULT=PASS cases=$planned_count" \
            "BATCH_EVIDENCE=$batch_dir" \
            "BATCH_SUMMARY=$summary_file"
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
            -quiet \
            "WATCHFACELAB_SEED_FACE=$case_path" \
            clean build 2>&1 | tee "$run_dir/build.log"

        app_path="$derived_data/Build/Products/Debug-watchos/WatchFaceLab.app"
        embedded_face="$app_path/PipBoy.watchface"
        [[ -d "$app_path" ]] || fail "Watch app was not produced: $app_path"
        [[ -f "$embedded_face" ]] || fail 'selected watchface was not embedded'
        embedded_hash="$(shasum -a 256 "$embedded_face" | awk '{print $1}')"
        [[ "$embedded_hash" == "$case_hash" ]] || fail \
            "embedded case hash mismatch: expected $case_hash, got $embedded_hash"
        codesign --verify --deep --strict "$app_path"
        printf 'PARSER_BUILD=PASS embeddedSHA256=%s\n' "$embedded_hash"

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
