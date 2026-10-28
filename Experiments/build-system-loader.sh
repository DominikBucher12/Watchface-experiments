#!/bin/bash
set -euo pipefail

experiment_dir="$(cd "$(dirname "$0")" && pwd)"
runtime_root="${WATCH_RUNTIME_ROOT:-}"
output_dir="${1:-/tmp/WatchFaceLab-SystemLoaderBuild}"

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

step() {
    printf 'BUILD_STEP=%s\n' "$1"
}

if [[ -z "$runtime_root" ]]; then
    printf 'ERROR: WATCH_RUNTIME_ROOT must point at the selected simulator RuntimeRoot\n' >&2
    exit 64
fi

sdk_path="$(xcrun --sdk watchsimulator --show-sdk-path)"
sdk_version="$(xcrun --sdk watchsimulator --show-sdk-version)"
private_frameworks="$runtime_root/System/Library/PrivateFrameworks"
ntk_binary="$private_frameworks/NanoTimeKit.framework/NanoTimeKit"
clockkitui_binary="$private_frameworks/ClockKitUI.framework/ClockKitUI"
[[ -f "$ntk_binary" ]] || fail "NanoTimeKit binary is missing: $ntk_binary"
[[ -f "$clockkitui_binary" ]] || fail "ClockKitUI binary is missing: $clockkitui_binary"

runtime_archs="$(lipo -archs "$ntk_binary")"
host_arch="$(uname -m)"
target_arch="${WATCH_SIMULATOR_ARCH:-}"
if [[ -z "$target_arch" ]]; then
    if [[ " $runtime_archs " == *" $host_arch "* ]]; then
        target_arch="$host_arch"
    elif [[ "$(wc -w <<<"$runtime_archs" | tr -d ' ')" == "1" ]]; then
        target_arch="$runtime_archs"
    else
        printf 'ERROR: cannot choose an architecture from: %s\n' "$runtime_archs" >&2
        exit 65
    fi
fi
if [[ " $runtime_archs " != *" $target_arch "* ]]; then
    printf 'ERROR: runtime does not contain architecture %s (%s)\n' \
        "$target_arch" "$runtime_archs" >&2
    exit 66
fi

runtime_build="$(xcrun vtool -arch "$target_arch" -show-build "$ntk_binary")"
if ! grep -Eq 'platform[[:space:]]+WATCHOSSIMULATOR' <<<"$runtime_build"; then
    printf 'ERROR: NanoTimeKit is not a watchOS Simulator binary\n' >&2
    exit 67
fi
deployment_target="${WATCH_SIMULATOR_DEPLOYMENT_TARGET:-$(
    awk '/minos/ { print $2; exit }' <<<"$runtime_build")}"
if [[ -z "$deployment_target" ]]; then
    printf 'ERROR: could not derive the runtime deployment target\n' >&2
    exit 68
fi
target="$target_arch-apple-watchos$deployment_target-simulator"

printf 'BUILD_TARGET=%s SDK=%s RUNTIME=%s\n' \
    "$target" "$sdk_version" "$runtime_root"
mkdir -p "$output_dir"

common_flags=(
    -target "$target" -isysroot "$sdk_path"
    -fobjc-arc -fno-modules -Wall -Wextra -Werror
    -F"$private_frameworks"
)

step "1/7 custom renderer"
xcrun --sdk watchsimulator clang "${common_flags[@]}" -g -dynamiclib \
    "$experiment_dir/MYCustomFace.m" \
    "$experiment_dir/MYBundleDiscovery.m" \
    "$ntk_binary" "$clockkitui_binary" \
    -framework Foundation -framework UIKit -framework ClockKit \
    -framework CoreGraphics -framework ImageIO -framework QuartzCore \
    -install_name @rpath/MYCustomFaceExperiment.dylib \
    -o "$output_dir/MYCustomFaceExperiment.dylib"
codesign --force --sign - "$output_dir/MYCustomFaceExperiment.dylib"
printf '%s\n' "$output_dir/MYCustomFaceExperiment.dylib"

bundle_dir="$output_dir/FaceBundles/MYLocalFaceBundle.bundle"
step "2/7 local face bundle"
if [[ -d "$bundle_dir" ]]; then
    rm -rf "$bundle_dir"
fi
mkdir -p "$bundle_dir/Assets"
cp "$experiment_dir/LocalFaceBundle/Info.plist" "$bundle_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Set :MinimumOSVersion $deployment_target" \
    "$bundle_dir/Info.plist"
# The branch's historical Argon dictionary names a deliberately fake payload.
# It is irrelevant to direct simulator discovery and could make newer loaders
# choose the wrong ingestion path.
/usr/libexec/PlistBuddy -c 'Delete :Argon' "$bundle_dir/Info.plist" \
    >/dev/null 2>&1 || true
animation_source="$experiment_dir/../WatchFaceLab/Resources/pip-boy-reference.gif"
[[ -f "$animation_source" ]] || fail "animation resource is missing: $animation_source"
cp "$animation_source" "$bundle_dir/Assets/pip-boy-reference.gif"
xcrun --sdk watchsimulator clang "${common_flags[@]}" -g -bundle \
    "$experiment_dir/LocalFaceBundle/MYLocalFaceBundle.m" \
    "$output_dir/MYCustomFaceExperiment.dylib" "$ntk_binary" \
    -framework Foundation -framework UIKit \
    -Wl,-rpath,@loader_path/../.. \
    -o "$bundle_dir/MYLocalFaceBundle"
codesign --force --sign - "$bundle_dir"
codesign --verify --deep --strict "$bundle_dir"
codesign -d --verbose=4 "$bundle_dir" 2>&1 |
    grep 'Info.plist entries=' >/dev/null
printf '%s\n' "$bundle_dir"

step "3/7 discovery probe"
xcrun --sdk watchsimulator clang "${common_flags[@]}" -fblocks \
    "$experiment_dir/SystemDiscoveryProbe.m" "$ntk_binary" \
    -framework Foundation -framework UIKit -framework ClockKit \
    -o "$output_dir/SystemDiscoveryProbe"
codesign --force --sign - "$output_dir/SystemDiscoveryProbe"
printf '%s\n' "$output_dir/SystemDiscoveryProbe"

step "4/7 collection read probe"
xcrun --sdk watchsimulator clang "${common_flags[@]}" -fblocks \
    "$experiment_dir/CollectionReadProbe.m" "$ntk_binary" \
    -framework Foundation -framework ClockKit \
    -o "$output_dir/CollectionReadProbe"
codesign --force --sign - "$output_dir/CollectionReadProbe"
printf '%s\n' "$output_dir/CollectionReadProbe"

step "5/7 collection mutation probe"
xcrun --sdk watchsimulator clang "${common_flags[@]}" -fblocks \
    "$experiment_dir/CollectionMutationProbe.m" "$ntk_binary" \
    -framework Foundation -framework UIKit -framework ClockKit \
    -o "$output_dir/CollectionMutationProbe"
codesign --force --sign - "$output_dir/CollectionMutationProbe"
printf '%s\n' "$output_dir/CollectionMutationProbe"

step "6/7 runtime-root bootstrap"
xcrun --sdk watchsimulator clang "${common_flags[@]}" -dynamiclib \
    "$experiment_dir/SystemRootBootstrap.m" \
    -framework Foundation \
    -install_name @rpath/SystemRootBootstrap.dylib \
    -o "$output_dir/SystemRootBootstrap.dylib"
codesign --force --sign - "$output_dir/SystemRootBootstrap.dylib"
printf '%s\n' "$output_dir/SystemRootBootstrap.dylib"

step "7/7 active-face selector"
xcrun --sdk watchsimulator clang "${common_flags[@]}" -fblocks -dynamiclib \
    "$experiment_dir/ActiveFaceSelector.m" \
    -framework Foundation -framework UIKit \
    -install_name @rpath/ActiveFaceSelector.dylib \
    -o "$output_dir/ActiveFaceSelector.dylib"
codesign --force --sign - "$output_dir/ActiveFaceSelector.dylib"
printf '%s\n' "$output_dir/ActiveFaceSelector.dylib"
