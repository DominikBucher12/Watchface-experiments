#!/usr/bin/env bash
set -euo pipefail

# Read-only host-side audit of the watchOS system components that sit between a
# third-party app and a persistent ClockFace collection. Nothing is installed,
# launched, signed, or changed on the paired Watch.
experiments_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=resolve-watchos-device-frameworks.sh
source "$experiments_dir/resolve-watchos-device-frameworks.sh"

watchfacelab_resolve_device_frameworks

ntk_suffix='/System/Library/PrivateFrameworks/NanoTimeKit.framework/NanoTimeKit'
case "$WATCH_NTK_BINARY" in
    *"$ntk_suffix") symbols_root="${WATCH_NTK_BINARY%"$ntk_suffix"}" ;;
    *)
        printf 'ERROR: cannot derive DeviceSupport Symbols root from: %s\n' \
            "$WATCH_NTK_BINARY" >&2
        exit 2
        ;;
esac

first_exact_file() {
    local path_pattern="$1"
    find "$symbols_root" -type f -path "$path_pattern" -print -quit 2>/dev/null
}

print_matches() {
    local label="$1"
    local path_pattern="$2"
    local output
    output="$(find "$symbols_root" -type f -path "$path_pattern" -print 2>/dev/null |
        LC_ALL=C sort || true)"
    printf '\n=== %s ===\n' "$label"
    if [[ -n "$output" ]]; then
        printf '%s\n' "$output"
    else
        printf 'NOT_PRESENT_IN_DEVICE_SUPPORT\n'
    fi
}

audit_launchd_plists() {
    local plist
    local found=0
    printf '\n=== SYSTEM_SERVICE_PLISTS ===\n'
    while IFS= read -r plist; do
        [[ -z "$plist" ]] && continue
        found=1
        printf '\nPLIST=%s\n' "$plist"
        plutil -p "$plist" 2>&1 || true
    done < <(
        find "$symbols_root" -type f \( \
            -iname '*nanotimekit*.plist' -o \
            -iname '*clockface*.plist' -o \
            -iname '*facesupport*.plist' \
        \) -path '*/System/Library/LaunchDaemons/*' -print 2>/dev/null |
            LC_ALL=C sort
    )
    if [[ "$found" -eq 0 ]]; then
        printf 'NOT_PRESENT_IN_DEVICE_SUPPORT\n'
    fi
}

audit_binary() {
    local label="$1"
    local binary="$2"
    printf '\n============================================================\n'
    printf 'BINARY=%s\nPATH=%s\n' "$label" "$binary"

    printf '%s\n' '-- file --'
    file "$binary" 2>&1 || true

    printf '%s\n' '-- build --'
    xcrun vtool -show-build "$binary" 2>&1 || true

    printf '%s\n' '-- UUIDs --'
    xcrun dwarfdump --uuid "$binary" 2>&1 || true

    printf '%s\n' '-- signature flags --'
    codesign -dvvv "$binary" 2>&1 || true

    printf '%s\n' '-- entitlements --'
    codesign -d --entitlements :- "$binary" 2>&1 || true

    printf '%s\n' '-- linked images --'
    xcrun otool -L "$binary" 2>&1 || true

    printf '%s\n' '-- boundary-related strings (max 200) --'
    (/usr/bin/strings "$binary" 2>/dev/null |
        grep -Ei 'collectionserver|nanotimekit|clockface|facesupport|mach-lookup|entitlement' |
        LC_ALL=C sort -u | head -200) || true
}

clockface_binary="$(first_exact_file '*/Applications/ClockFace.app/ClockFace')"
nanotimekitd_binary="$(first_exact_file '*/usr/libexec/nanotimekitd')"
if [[ -z "$nanotimekitd_binary" ]]; then
    nanotimekitd_binary="$(first_exact_file '*/nanotimekitd')"
fi

printf '%s\n' \
    'WATCHFACELAB_SYSTEM_BOUNDARY_AUDIT_BEGIN' \
    "SYMBOLS_ROOT=$symbols_root" \
    "DEVICE_NTK=$WATCH_NTK_BINARY" \
    "DEVICE_CLOCKKITUI=$WATCH_CLOCKKITUI_BINARY" \
    'NOTE=DeviceSupport symbol copies may have stripped signatures or entitlements; absence here is not proof of absence on the running Watch.'

if [[ -n "$clockface_binary" ]]; then
    audit_binary 'ClockFace.app/ClockFace' "$clockface_binary"
else
    printf '\nCLOCKFACE_BINARY=NOT_PRESENT_IN_DEVICE_SUPPORT\n'
    printf '%s\n' \
        'Only the exact Applications/ClockFace.app/ClockFace path is accepted.' \
        'AccessibilityBundles/ClockFace.axbundle is intentionally ignored.'
fi

if [[ -n "$nanotimekitd_binary" ]]; then
    audit_binary 'nanotimekitd' "$nanotimekitd_binary"
else
    printf '\nNANOTIMEKITD_BINARY=NOT_PRESENT_IN_DEVICE_SUPPORT\n'
fi

audit_binary 'NanoTimeKit.framework/NanoTimeKit' "$WATCH_NTK_BINARY"

print_matches 'CLOCKFACE_SUPPORT_COMPONENTS' '*/ClockFaceSupport*'
print_matches 'FACE_SUPPORT_COMPONENTS' '*/*FaceSupport*'
audit_launchd_plists

printf '\nWATCHFACELAB_SYSTEM_BOUNDARY_AUDIT_END\n'
