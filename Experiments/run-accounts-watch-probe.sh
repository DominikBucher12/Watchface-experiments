#!/usr/bin/env bash
# Build, install and launch the watchOS Accounts probe on the connected Apple
# Watch, then copy its log out of the app data container.
#
# The probe measures two October 2026 Accounts issues on watchOS 27.0.1:
#   CVE-2026-112446  missing entitlement checks (account metadata access)
#   CVE-2026-113898  insufficient log redaction (not observable from an app)
#
# This only records what the Accounts client hands an unentitled third-party
# app. It does not, and cannot, produce a jailbreak.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
device_id="${WATCHFACELAB_DEVICE_ID:-}"
wait_seconds="${WATCHFACELAB_ACCOUNTS_WAIT:-120}"

if [[ -z "$device_id" ]]; then
    device_id="$(xcrun devicectl list devices 2>/dev/null |
        awk '/Apple Watch/ && /connected/ && !/simulated/ {
            for (i = 1; i <= NF; i++)
                if ($i ~ /^[0-9A-F]+-[0-9A-F]+$/) { print $i; exit }
        }')"
fi
[[ -n "$device_id" ]] || {
    printf 'ERROR: no connected Apple Watch found; set WATCHFACELAB_DEVICE_ID\n' >&2
    exit 1
}

printf 'ACCOUNTS_DEVICE=%s\n' "$device_id"

if [[ "${WATCHFACELAB_SKIP_BUILD:-0}" != "1" ]]; then
    WATCHFACELAB_DEVICE_ID="$device_id" \
        bash "$repo_root/Experiments/bootstrap-watchos27-device.sh" --build-only >"${TMPDIR:-/tmp}/accounts-watch-build.log" 2>&1 || {
        tail -40 "${TMPDIR:-/tmp}/accounts-watch-build.log" >&2
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

out_dir="$(mktemp -d "${TMPDIR:-/tmp}/accounts-watch-probe.XXXXXX")"
printf 'ACCOUNTS_RESULT_DIR=%s\n' "$out_dir"

if [[ "${WATCHFACELAB_SKIP_INSTALL:-0}" != "1" ]]; then
    xcrun devicectl device install app --device "$device_id" "$app_path"
fi

run_id="accounts-${SECONDS}-$$"
env_json="$(printf '{"WATCHFACELAB_SYSTEM_ACTION":"accounts","WATCHFACELAB_SYSTEM_RUN_ID":"%s"}' "$run_id")"

launch_log="$out_dir/launch.log"
set +e
timeout 45 xcrun devicectl device process launch --device "$device_id" \
    --terminate-existing \
    --environment-variables "$env_json" \
    dev.develodom.WatchFaceLab >"$launch_log" 2>&1
launch_status=$?
set -e
if (( launch_status != 0 )); then
    printf 'ACCOUNTS_LAUNCH=FAIL status=%s\n' "$launch_status"
    tail -6 "$launch_log" >&2
    if grep -q 'Locked' "$launch_log"; then
        printf 'ACCOUNTS_HINT=unlock the Watch and keep the screen awake, then rerun\n' >&2
    fi
fi

printf 'ACCOUNTS_WAIT up to %s seconds for Documents/WatchFaceLab-AccountsResult.txt\n' "$wait_seconds"
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
        --source Documents/WatchFaceLab-AccountsResult.txt \
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
        printf 'ACCOUNTS_CAPTURE=PARTIAL (probe did not log COMPLETE)\n'
        local_log="$out_dir/log.partial.txt"
    else
        printf 'ACCOUNTS_CAPTURE=FAIL (no log for run %s; the app likely never became active)\n' "$run_id" >&2
        printf 'ACCOUNTS_HINT=unlock the Watch, open WatchFaceLab, keep the screen on, then rerun\n' >&2
        printf 'ACCOUNTS_CONTAINER_DOCUMENTS_BEGIN\n' >&2
        xcrun devicectl device info files --device "$device_id" \
            --domain-type appDataContainer \
            --domain-identifier dev.develodom.WatchFaceLab \
            --subdirectory Documents --no-recurse --timeout 15 >&2 || true
        printf 'ACCOUNTS_CONTAINER_DOCUMENTS_END\n' >&2
        exit 1
    fi
else
    printf 'ACCOUNTS_CAPTURE=PASS\n'
fi

printf 'ACCOUNTS_LOG_BEGIN\n'
cat "$local_log"
printf 'ACCOUNTS_LOG_END\n'

action_record="$out_dir/action.txt"
rm -f "$action_record"
if xcrun devicectl device copy from --device "$device_id" \
    --domain-type appDataContainer \
    --domain-identifier dev.develodom.WatchFaceLab \
    --source Documents/WatchFaceLab-SystemAction.txt \
    --destination "$action_record" >/dev/null 2>&1 && [[ -s "$action_record" ]]; then
    printf 'ACCOUNTS_ACTION_BEGIN\n'
    cat "$action_record"
    printf 'ACCOUNTS_ACTION_END\n'
fi
