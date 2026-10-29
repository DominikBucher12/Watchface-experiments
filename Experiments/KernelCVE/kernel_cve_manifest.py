#!/usr/bin/env python3
"""Build and compare read-only manifests of watchOS kernel-related artifacts.

This tool deliberately inventories identities and metadata only. It does not
modify a DeviceSupport tree, disassemble binaries, contact a Watch, or trigger
any kernel interface.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from typing import Any, Iterable


SCHEMA_VERSION = 1
SCRIPT_VERSION = "1.0"
MACHO_MAGICS = {
    bytes.fromhex("feedface"): "mach-o-32-be",
    bytes.fromhex("cefaedfe"): "mach-o-32-le",
    bytes.fromhex("feedfacf"): "mach-o-64-be",
    bytes.fromhex("cffaedfe"): "mach-o-64-le",
    bytes.fromhex("cafebabe"): "fat-be",
    bytes.fromhex("bebafeca"): "fat-le",
    bytes.fromhex("cafebabf"): "fat64-be",
    bytes.fromhex("bfbafeca"): "fat64-le",
}
UUID_PATTERN = re.compile(
    r"UUID:\s*([0-9A-Fa-f-]+)\s*\(([^)]+)\)\s*(.*)$"
)


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp-{os.getpid()}")
    with temporary.open("w", encoding="utf-8") as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write("\n")
    temporary.replace(path)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def scan_root_for(root: Path) -> Path:
    symbols = root / "Symbols"
    return symbols if symbols.is_dir() else root


def is_candidate_path(relative_path: str) -> bool:
    normalized = "/" + relative_path.lstrip("/")
    return any(
        (
            "/System/Library/Kernels/" in normalized,
            "/System/Library/KernelCollections/" in normalized,
            "/System/Library/Caches/com.apple.kernelcaches/" in normalized,
            "/System/Library/Extensions/" in normalized,
            normalized.endswith("/usr/lib/system/libsystem_kernel.dylib"),
            "/System/Library/Frameworks/IOKit.framework/" in normalized,
            "/System/Library/PrivateFrameworks/IOKit.framework/" in normalized,
            "/System/Library/Frameworks/IOSurface.framework/" in normalized,
            "/System/Library/PrivateFrameworks/IOSurface.framework/" in normalized,
        )
    )


def component_for(relative_path: str) -> str:
    normalized = "/" + relative_path.lstrip("/")
    if "/System/Library/Kernels/" in normalized:
        return "xnu-kernel"
    if "/System/Library/KernelCollections/" in normalized:
        return "kernel-collection"
    if "/System/Library/Caches/com.apple.kernelcaches/" in normalized:
        return "kernel-cache"
    if "/System/Library/Extensions/" in normalized:
        # DeviceSupport also places user-space bundles and plug-ins in this
        # tree. The path alone does not prove that a file is a loadable kext.
        return "extension-tree-binary"
    if normalized.endswith("/usr/lib/system/libsystem_kernel.dylib"):
        return "syscall-client"
    if "IOSurface.framework" in normalized:
        return "iosurface-client"
    if "IOKit.framework" in normalized:
        return "iokit-client"
    return "other"


def macho_magic(path: Path) -> str | None:
    try:
        with path.open("rb") as stream:
            return MACHO_MAGICS.get(stream.read(4))
    except OSError:
        return None


def may_be_opaque_kernel_artifact(relative_path: str) -> bool:
    normalized = "/" + relative_path.lstrip("/")
    basename = Path(relative_path).name.lower()
    if "/System/Library/Kernels/" in normalized:
        return basename == "kernel" or basename.startswith("kernel.")
    if "/System/Library/KernelCollections/" in normalized:
        return basename.endswith(".kc") or "kernel" in basename
    if "/System/Library/Caches/com.apple.kernelcaches/" in normalized:
        return basename.startswith("kernelcache")
    return basename.startswith("kernelcache")


def find_dwarfdump() -> str | None:
    direct = shutil.which("dwarfdump")
    if direct:
        return direct
    xcrun = shutil.which("xcrun")
    if not xcrun:
        return None
    try:
        result = subprocess.run(
            [xcrun, "--find", "dwarfdump"],
            check=True,
            capture_output=True,
            text=True,
            timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    candidate = result.stdout.strip()
    return candidate if candidate else None


def uuids_for(path: Path, dwarfdump: str | None) -> tuple[list[dict[str, str]], str | None]:
    if not dwarfdump:
        return [], "dwarfdump-unavailable"
    try:
        result = subprocess.run(
            [dwarfdump, "--uuid", str(path)],
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        return [], "dwarfdump-timeout"
    except OSError as error:
        return [], f"dwarfdump-error:{error.__class__.__name__}"
    records: list[dict[str, str]] = []
    for line in result.stdout.splitlines():
        match = UUID_PATTERN.search(line)
        if match:
            records.append(
                {
                    "uuid": match.group(1).upper(),
                    "architecture": match.group(2),
                }
            )
    if result.returncode != 0 and not records:
        return [], f"dwarfdump-exit:{result.returncode}"
    return records, None


def candidate_files(scan_root: Path) -> Iterable[tuple[str, Path, str]]:
    for directory, names, files in os.walk(scan_root, followlinks=False):
        names.sort()
        files.sort()
        directory_path = Path(directory)
        for name in files:
            path = directory_path / name
            if path.is_symlink() or not path.is_file():
                continue
            relative = path.relative_to(scan_root).as_posix()
            if not is_candidate_path(relative):
                continue
            artifact_format = macho_magic(path)
            if not artifact_format and may_be_opaque_kernel_artifact(relative):
                artifact_format = "opaque-kernel-artifact"
            if artifact_format:
                yield relative, path, artifact_format


def build_inventory(root: Path, label: str, with_uuids: bool) -> dict[str, Any]:
    root = root.expanduser().resolve()
    if not root.is_dir():
        raise ValueError(f"input root is not a directory: {root}")
    scan_root = scan_root_for(root)
    dwarfdump = find_dwarfdump() if with_uuids else None
    records: list[dict[str, Any]] = []
    uuid_warning_count = 0
    for index, (relative, path, magic) in enumerate(candidate_files(scan_root), start=1):
        print(f"MANIFEST_FILE={index} path={relative}", file=sys.stderr, flush=True)
        uuids: list[dict[str, str]] = []
        uuid_error: str | None = None
        if with_uuids and magic != "opaque-kernel-artifact":
            uuids, uuid_error = uuids_for(path, dwarfdump)
            if uuid_error:
                uuid_warning_count += 1
        stat = path.stat()
        record: dict[str, Any] = {
            "component": component_for(relative),
            "magic": magic,
            "path": relative,
            "sha256": sha256_file(path),
            "size": stat.st_size,
            "uuids": uuids,
        }
        if uuid_error:
            record["uuidWarning"] = uuid_error
        records.append(record)
    component_counts: dict[str, int] = {}
    for record in records:
        component = record["component"]
        component_counts[component] = component_counts.get(component, 0) + 1
    return {
        "schemaVersion": SCHEMA_VERSION,
        "tool": "kernel_cve_manifest.py",
        "toolVersion": SCRIPT_VERSION,
        "createdUTC": utc_now(),
        "label": label,
        "inputRoot": str(root),
        "scanRoot": str(scan_root),
        "withUUIDs": with_uuids,
        "uuidWarningCount": uuid_warning_count,
        "fileCount": len(records),
        "componentCounts": component_counts,
        "files": records,
    }


def load_manifest(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as stream:
        manifest = json.load(stream)
    if manifest.get("schemaVersion") != SCHEMA_VERSION or not isinstance(
        manifest.get("files"), list
    ):
        raise ValueError(f"unsupported manifest: {path}")
    return manifest


def kernel_artifact_count(manifest: dict[str, Any]) -> int:
    kernel_components = {"xnu-kernel", "kernel-collection", "kernel-cache"}
    return sum(
        1
        for record in manifest.get("files", [])
        if record.get("component") in kernel_components
    )


def comparison_record(old: dict[str, Any], fixed: dict[str, Any]) -> dict[str, Any]:
    return {
        "path": old["path"],
        "component": old.get("component", "other"),
        "old": {
            "sha256": old.get("sha256"),
            "size": old.get("size"),
            "uuids": old.get("uuids", []),
        },
        "fixed": {
            "sha256": fixed.get("sha256"),
            "size": fixed.get("size"),
            "uuids": fixed.get("uuids", []),
        },
    }


def compare_manifests(old: dict[str, Any], fixed: dict[str, Any]) -> dict[str, Any]:
    old_files = {record["path"]: record for record in old["files"]}
    fixed_files = {record["path"]: record for record in fixed["files"]}
    old_paths = set(old_files)
    fixed_paths = set(fixed_files)
    added = [fixed_files[path] for path in sorted(fixed_paths - old_paths)]
    removed = [old_files[path] for path in sorted(old_paths - fixed_paths)]
    changed: list[dict[str, Any]] = []
    unchanged: list[str] = []
    for path in sorted(old_paths & fixed_paths):
        if old_files[path].get("sha256") == fixed_files[path].get("sha256"):
            unchanged.append(path)
        else:
            changed.append(comparison_record(old_files[path], fixed_files[path]))
    changed_components: dict[str, int] = {}
    for record in changed:
        component = record["component"]
        changed_components[component] = changed_components.get(component, 0) + 1
    old_kernel_artifacts = kernel_artifact_count(old)
    fixed_kernel_artifacts = kernel_artifact_count(fixed)
    coverage_status = (
        "kernel-artifacts-present"
        if old_kernel_artifacts > 0 and fixed_kernel_artifacts > 0
        else "client-only-or-incomplete"
    )
    return {
        "schemaVersion": SCHEMA_VERSION,
        "tool": "kernel_cve_manifest.py",
        "toolVersion": SCRIPT_VERSION,
        "createdUTC": utc_now(),
        "old": {
            "label": old.get("label"),
            "inputRoot": old.get("inputRoot"),
            "fileCount": old.get("fileCount"),
        },
        "fixed": {
            "label": fixed.get("label"),
            "inputRoot": fixed.get("inputRoot"),
            "fileCount": fixed.get("fileCount"),
        },
        "counts": {
            "added": len(added),
            "removed": len(removed),
            "changed": len(changed),
            "unchanged": len(unchanged),
        },
        "changedComponentCounts": changed_components,
        "coverage": {
            "status": coverage_status,
            "oldKernelArtifacts": old_kernel_artifacts,
            "fixedKernelArtifacts": fixed_kernel_artifacts,
        },
        "added": added,
        "removed": removed,
        "changed": changed,
        "unchangedPaths": unchanged,
    }


def print_inventory_summary(manifest: dict[str, Any]) -> None:
    print(f"MANIFEST_LABEL={manifest.get('label', '')}")
    print(f"MANIFEST_FILES={manifest.get('fileCount', 0)}")
    print(f"MANIFEST_UUID_WARNINGS={manifest.get('uuidWarningCount', 0)}")
    print(f"MANIFEST_KERNEL_ARTIFACTS={kernel_artifact_count(manifest)}")
    for component, count in sorted(manifest.get("componentCounts", {}).items()):
        print(f"MANIFEST_COMPONENT component={component} files={count}")


def print_comparison_summary(comparison: dict[str, Any]) -> None:
    counts = comparison["counts"]
    print(
        "COMPARE_COUNTS "
        f"changed={counts['changed']} added={counts['added']} "
        f"removed={counts['removed']} unchanged={counts['unchanged']}"
    )
    coverage = comparison.get("coverage", {})
    print(
        "COMPARE_COVERAGE "
        f"status={coverage.get('status', 'unknown')} "
        f"old-kernel-artifacts={coverage.get('oldKernelArtifacts', 0)} "
        f"fixed-kernel-artifacts={coverage.get('fixedKernelArtifacts', 0)}"
    )
    for component, count in sorted(comparison["changedComponentCounts"].items()):
        print(f"COMPARE_COMPONENT component={component} changed={count}")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    subparsers = result.add_subparsers(dest="command", required=True)

    inventory = subparsers.add_parser("inventory", help="create a read-only artifact manifest")
    inventory.add_argument("root", type=Path)
    inventory.add_argument("output", type=Path)
    inventory.add_argument("--label", default="unlabeled")
    inventory.add_argument("--no-uuids", action="store_true")

    compare = subparsers.add_parser("compare", help="compare old and fixed manifests")
    compare.add_argument("old", type=Path)
    compare.add_argument("fixed", type=Path)
    compare.add_argument("output", type=Path)

    summarize = subparsers.add_parser("summarize", help="print a manifest or comparison summary")
    summarize.add_argument("input", type=Path)
    return result


def main() -> int:
    arguments = parser().parse_args()
    try:
        if arguments.command == "inventory":
            manifest = build_inventory(
                arguments.root, arguments.label, with_uuids=not arguments.no_uuids
            )
            write_json(arguments.output, manifest)
            print_inventory_summary(manifest)
            print(f"MANIFEST_OUTPUT={arguments.output.resolve()}")
            if manifest["fileCount"] == 0:
                print(
                    "ERROR: no kernel-related Mach-O artifacts were found under the supplied root",
                    file=sys.stderr,
                )
                return 3
            return 0
        if arguments.command == "compare":
            old = load_manifest(arguments.old)
            fixed = load_manifest(arguments.fixed)
            comparison = compare_manifests(old, fixed)
            write_json(arguments.output, comparison)
            print_comparison_summary(comparison)
            print(f"COMPARE_OUTPUT={arguments.output.resolve()}")
            return 0
        with arguments.input.open("r", encoding="utf-8") as stream:
            value = json.load(stream)
        if "counts" in value and "changed" in value:
            print_comparison_summary(value)
        else:
            print_inventory_summary(value)
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
