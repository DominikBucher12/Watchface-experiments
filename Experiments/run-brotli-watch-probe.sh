#!/usr/bin/env bash
# Build, install and launch the watchOS brotli probe (CVE-2026-111497) on the
# connected Apple Watch, then copy its log out of the app data container.
#
# This only measures what the in-process brotli decoder does on watchOS.
# It does not, and cannot, produce a jailbreak.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
device_id="${WATCHFACELAB_DEVICE_ID:-}"
mode="${WATCHFACELAB_BROTLI_MODE:-jetengine}"
d15="${WATCHFACELAB_BROTLI_D15:-0x7FFFFFFF}"
d19="${WATCHFACELAB_BROTLI_D19:-0}"
d23="${WATCHFACELAB_BROTLI_D23:-0}"
b7="${WATCHFACELAB_BROTLI_B7:-0}"
body="${WATCHFACELAB_BROTLI_BODY:-0x123}"
drain="${WATCHFACELAB_BROTLI_DRAIN:-8}"
s2extra="${WATCHFACELAB_BROTLI_S2EXTRA:-0}"
wait_seconds="${WATCHFACELAB_BROTLI_WAIT:-90}"

if [[ -z "$device_id" ]]; then
    device_id="$(xcrun devicectl list devices 2>/dev/null |
        awk '/Apple Watch/ && /connected/ && !/simulated/ {
            for (i = 1; i <= NF; i++)
                if ($i ~ /^[0-9A-F]+-[0-9A-F]+$/) {
                    print $i;
                    exit;
                }
        }')"
fi
[[ -n "$device_id" ]] || {
    printf 'ERROR: no connected Apple Watch found; set WATCHFACELAB_DEVICE_ID\n' >&2
    exit 1
}

printf 'BROTLI_DEVICE=%s mode=%s d15=%s d19=%s d23=%s b7=%s body=%s drain=%s s2extra=%s\n' \
    "$device_id" "$mode" "$d15" "$d19" "$d23" "$b7" "$body" "$drain" "$s2extra"

if [[ "${WATCHFACELAB_SKIP_BUILD:-0}" != "1" ]]; then
    WATCHFACELAB_DEVICE_ID="$device_id" \
        bash "$repo_root/Experiments/bootstrap-watchos27-device.sh" --build-only >"${TMPDIR:-/tmp}/brotli-watch-build.log" 2>&1 || {
        tail -40 "${TMPDIR:-/tmp}/brotli-watch-build.log" >&2
        printf 'ERROR: device build failed\n' >&2
        exit 1
    }
fi

derived_data="${WATCHFACELAB_DERIVED_DATA:-/tmp/WatchFaceLab27-DeviceDerived-$device_id}"
app_path="$derived_data/Build/Products/Debug-watchos/WatchFaceLab.app"
[[ -d "$app_path" ]] || {
    printf 'ERROR: built app missing at %s\n' "$app_path" >&2
    exit 1
}

out_dir="$(mktemp -d "${TMPDIR:-/tmp}/brotli-watch-probe.XXXXXX")"
printf 'BROTLI_RESULT_DIR=%s\n' "$out_dir"

if [[ "${WATCHFACELAB_SKIP_INSTALL:-0}" != "1" ]]; then
    xcrun devicectl device install app --device "$device_id" "$app_path"
fi

extra_env=""
if [[ -n "${WATCHFACELAB_BROTLI_NOSIG:-}" ]]; then
    extra_env=",\"WATCHFACELAB_BROTLI_NOSIG\":\"$WATCHFACELAB_BROTLI_NOSIG\""
fi
run_id="brotli-${SECONDS}-$$"
env_json="$(printf '{"WATCHFACELAB_SYSTEM_ACTION":"brotli","WATCHFACELAB_SYSTEM_RUN_ID":"%s","WATCHFACELAB_BROTLI_MODE":"%s","WATCHFACELAB_BROTLI_D15":"%s","WATCHFACELAB_BROTLI_D19":"%s","WATCHFACELAB_BROTLI_D23":"%s","WATCHFACELAB_BROTLI_B7":"%s","WATCHFACELAB_BROTLI_BODY":"%s","WATCHFACELAB_BROTLI_DRAIN":"%s","WATCHFACELAB_BROTLI_S2EXTRA":"%s"%s}' \
    "$run_id" "$mode" "$d15" "$d19" "$d23" "$b7" "$body" "$drain" "$s2extra" "$extra_env")"

launch_log="$out_dir/launch.log"
set +e
timeout 45 xcrun devicectl device process launch --device "$device_id" \
    --terminate-existing \
    --environment-variables "$env_json" \
    dev.develodom.WatchFaceLab >"$launch_log" 2>&1
launch_status=$?
set -e
if (( launch_status != 0 )); then
    printf 'BROTLI_LAUNCH=FAIL status=%s\n' "$launch_status"
    tail -6 "$launch_log" >&2
    if grep -q 'Locked' "$launch_log"; then
        printf 'BROTLI_HINT=unlock the Watch and keep the screen awake (Wake Screen 70s), then rerun\n' >&2
    fi
fi

printf 'BROTLI_WAIT up to %s seconds for Documents/WatchFaceLab-BrotliResult.txt\n' "$wait_seconds"
deadline=$((SECONDS + wait_seconds))
local_log=""
attempt=0
while (( SECONDS < deadline )); do
    attempt=$((attempt + 1))
    candidate="$out_dir/log-$attempt.txt"
    rm -f "$candidate"
    if xcrun devicectl device copy from --device "$device_id" \
        --domain-type appDataContainer \
        --domain-identifier dev.develodom.WatchFaceLab \
        --source Documents/WatchFaceLab-BrotliResult.txt \
        --destination "$candidate" >/dev/null 2>&1; then
        if grep -q "RUN $run_id" "$candidate" 2>/dev/null; then cp "$candidate" "$out_dir/log.partial.txt" || true; fi
        if grep -q "RUN $run_id" "$candidate" 2>/dev/null && grep -q 'COMPLETE rc=' "$candidate"; then
            local_log="$candidate"
            break
        fi
    fi
    sleep 2
done

if [[ -z "$local_log" ]]; then
    if [[ -s "$out_dir/log.partial.txt" ]]; then
        printf 'BROTLI_CAPTURE=PARTIAL (probe did not log COMPLETE)\n'
        local_log="$out_dir/log.partial.txt"
    else
        printf 'BROTLI_CAPTURE=FAIL (no log for run %s; the app likely never became active)\n' "$run_id" >&2
        printf 'BROTLI_HINT=unlock the Watch, open WatchFaceLab, keep the screen on, then rerun\n' >&2
        printf 'BROTLI_CONTAINER_DOCUMENTS_BEGIN\n' >&2
        xcrun devicectl device info files --device "$device_id" \
            --domain-type appDataContainer \
            --domain-identifier dev.develodom.WatchFaceLab \
            --subdirectory Documents --no-recurse --timeout 15 >&2 || true
        printf 'BROTLI_CONTAINER_DOCUMENTS_END\n' >&2
        exit 1
    fi
else
    printf 'BROTLI_CAPTURE=PASS\n'
fi

printf 'BROTLI_LOG_BEGIN\n'
cat "$local_log"
printf 'BROTLI_LOG_END\n'

trace_copy="$out_dir/trace.txt"
rm -f "$trace_copy"
if xcrun devicectl device copy from --device "$device_id" \
    --domain-type appDataContainer \
    --domain-identifier dev.develodom.WatchFaceLab \
    --source Documents/WatchFaceLab-BrotliTrace.txt \
    --destination "$trace_copy" >/dev/null 2>&1 && [[ -s "$trace_copy" ]]; then
    printf 'BROTLI_TRACE_BEGIN\n'
    cat "$trace_copy"
    printf 'BROTLI_TRACE_END\n'
fi