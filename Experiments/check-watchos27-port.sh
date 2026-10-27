#!/bin/bash
set -euo pipefail

experiment_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$experiment_dir/.." && pwd)"
sdk_path="$(xcrun --sdk watchsimulator --show-sdk-path)"
target="${WATCHOS27_COMPILE_TARGET:-arm64-apple-watchos27.0-simulator}"
output_dir="${1:-/tmp/WatchFaceLab27-CompileCheck}"
mkdir -p "$output_dir"

sources=(
    MYCustomFace.m
    MYBundleDiscovery.m
    LocalFaceBundle/MYLocalFaceBundle.m
    SystemDiscoveryProbe.m
    CollectionReadProbe.m
    CollectionMutationProbe.m
    SystemRootBootstrap.m
    ActiveFaceSelector.m
)

for relative_source in "${sources[@]}"; do
    source_path="$experiment_dir/$relative_source"
    object_name="$(basename "$relative_source" .m).o"
    xcrun --sdk watchsimulator clang \
        -target "$target" -isysroot "$sdk_path" \
        -fobjc-arc -fblocks -fno-modules \
        -Wall -Wextra -Werror -I"$experiment_dir" \
        -c "$source_path" -o "$output_dir/$object_name"
done

historical_binary="$repo_root/Experiments/Build/Simulator/MYCustomFaceExperiment.framework/MYCustomFaceExperiment"
if [[ -f "$historical_binary" ]]; then
    printf '%s\n' '=== Historical watchOS 27 simulator build metadata ==='
    xcrun vtool -show-build "$historical_binary"
fi

printf '%s\n' '=== New port compile objects ==='
file "$output_dir"/*.o
printf 'PORT_COMPILE_CHECK=PASS target=%s sdk=%s\n' \
    "$target" "$(xcrun --sdk watchsimulator --show-sdk-version)"
