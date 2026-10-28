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

# Older simulator runtimes ship private framework Mach-Os as ordinary files.
# Newer runtimes can keep the same install names exclusively in the dyld shared
# cache. In the latter case, link against a narrow local text stub; dyld still
# resolves the original install name from the selected runtime's cache.
private_link_inputs=()
private_link_mode="files"
if [[ -f "$ntk_binary" && -f "$clockkitui_binary" ]]; then
    private_link_inputs=("$ntk_binary" "$clockkitui_binary")
else
    private_link_mode="dyld-cache-stub"
fi

runtime_reference=""
if [[ -f "$ntk_binary" ]]; then
    runtime_reference="$ntk_binary"
else
    face_bundles="$runtime_root/System/Library/NanoTimeKit/FaceBundles"
    while IFS= read -r -d '' candidate; do
        candidate_build="$(xcrun vtool -show-build "$candidate" 2>/dev/null || true)"
        if grep -Eq 'platform[[:space:]]+WATCHOSSIMULATOR' <<<"$candidate_build"; then
            runtime_reference="$candidate"
            break
        fi
    done < <(find "$face_bundles" -maxdepth 3 -type f -print0 2>/dev/null)
fi

runtime_archs=""
if [[ -n "$runtime_reference" ]]; then
    runtime_archs="$(lipo -archs "$runtime_reference")"
fi
host_arch="$(uname -m)"
target_arch="${WATCH_SIMULATOR_ARCH:-}"
if [[ -z "$target_arch" ]]; then
    if [[ -z "$runtime_archs" || " $runtime_archs " == *" $host_arch "* ]]; then
        target_arch="$host_arch"
    elif [[ "$(wc -w <<<"$runtime_archs" | tr -d ' ')" == "1" ]]; then
        target_arch="$runtime_archs"
    else
        printf 'ERROR: cannot choose an architecture from: %s\n' "$runtime_archs" >&2
        exit 65
    fi
fi
if [[ -n "$runtime_archs" && " $runtime_archs " != *" $target_arch "* ]]; then
    printf 'ERROR: runtime does not contain architecture %s (%s)\n' \
        "$target_arch" "$runtime_archs" >&2
    exit 66
fi

runtime_build=""
if [[ -n "$runtime_reference" ]]; then
    runtime_build="$(xcrun vtool -arch "$target_arch" -show-build "$runtime_reference")"
    if ! grep -Eq 'platform[[:space:]]+WATCHOSSIMULATOR' <<<"$runtime_build"; then
        printf 'ERROR: runtime reference is not a watchOS Simulator binary: %s\n' \
            "$runtime_reference" >&2
        exit 67
    fi
fi
deployment_target="${WATCH_SIMULATOR_DEPLOYMENT_TARGET:-$(
    awk '/minos/ { print $2; exit }' <<<"$runtime_build")}"
if [[ -z "$deployment_target" ]]; then
    system_version="$runtime_root/System/Library/CoreServices/SystemVersion.plist"
    if [[ -f "$system_version" ]]; then
        deployment_target="$(/usr/libexec/PlistBuddy -c 'Print :ProductVersion' \
            "$system_version" 2>/dev/null || true)"
    fi
fi
if [[ -z "$deployment_target" ]]; then
    deployment_target="$sdk_version"
fi
target="$target_arch-apple-watchos$deployment_target-simulator"

printf 'BUILD_TARGET=%s SDK=%s RUNTIME=%s PRIVATE_FRAMEWORKS=%s\n' \
    "$target" "$sdk_version" "$runtime_root" "$private_link_mode"
if [[ -n "$runtime_reference" ]]; then
    printf 'BUILD_RUNTIME_REFERENCE=%s\n' "$runtime_reference"
fi
mkdir -p "$output_dir"

if [[ "$private_link_mode" == "dyld-cache-stub" ]]; then
    private_stub_root="$output_dir/PrivateFrameworkStubs"
    ntk_stub_dir="$private_stub_root/NanoTimeKit.framework"
    mkdir -p "$ntk_stub_dir"
    cat >"$ntk_stub_dir/NanoTimeKit.tbd" <<EOF
--- !tapi-tbd
tbd-version:     4
targets:         [ $target_arch-watchos-simulator ]
install-name:    '/System/Library/PrivateFrameworks/NanoTimeKit.framework/NanoTimeKit'
exports:
  - targets:         [ $target_arch-watchos-simulator ]
    symbols:         [ _NTKFaceBundleFaceTypeKey, _NTKFaceBundleIdentifierKey ]
    objc-classes:    [ NTKDigitalTimeLabel, NTKFace, NTKFaceBundle,
                       NTKFaceBundleLoader, NTKFaceBundleManager,
                       NTKFaceInstanceDescriptor, NTKFacesArrayGalleryCollection,
                       NTKFacesBundleArrayGalleryCollection, NTKGalleryCollection,
                       NTKFaceView, NTKFaceViewController ]
...
EOF
    private_link_inputs=(-F"$private_stub_root" -framework NanoTimeKit)
    printf 'BUILD_PRIVATE_STUB=%s\n' "$ntk_stub_dir/NanoTimeKit.tbd"
    printf 'BUILD_NOTE=NanoTimeKit is expected in the simulator dyld shared cache\n'
fi

common_flags=(
    -target "$target" -isysroot "$sdk_path"
    -fobjc-arc -fno-modules -Wall -Wextra -Werror
    -F"$private_frameworks"
)

step "1/7 custom renderer"
xcrun --sdk watchsimulator clang "${common_flags[@]}" -g -dynamiclib \
    "$experiment_dir/MYCustomFace.m" \
    "$experiment_dir/MYBundleDiscovery.m" \
    "${private_link_inputs[@]}" \
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
    "$output_dir/MYCustomFaceExperiment.dylib" "${private_link_inputs[@]}" \
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
    "$experiment_dir/SystemDiscoveryProbe.m" "${private_link_inputs[@]}" \
    -framework Foundation -framework UIKit -framework ClockKit \
    -o "$output_dir/SystemDiscoveryProbe"
codesign --force --sign - "$output_dir/SystemDiscoveryProbe"
printf '%s\n' "$output_dir/SystemDiscoveryProbe"

step "4/7 collection read probe"
xcrun --sdk watchsimulator clang "${common_flags[@]}" -fblocks \
    "$experiment_dir/CollectionReadProbe.m" "${private_link_inputs[@]}" \
    -framework Foundation -framework ClockKit \
    -o "$output_dir/CollectionReadProbe"
codesign --force --sign - "$output_dir/CollectionReadProbe"
printf '%s\n' "$output_dir/CollectionReadProbe"

step "5/7 collection mutation probe"
xcrun --sdk watchsimulator clang "${common_flags[@]}" -fblocks \
    "$experiment_dir/CollectionMutationProbe.m" "${private_link_inputs[@]}" \
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
