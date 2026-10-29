import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


MODULE_ROOT = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = MODULE_ROOT.parents[1]
sys.path.insert(0, str(MODULE_ROOT))

from kernel_cve_manifest import build_inventory, compare_manifests  # noqa: E402


MACHO64_LE = bytes.fromhex("cffaedfe")


class KernelCVEManifestTests(unittest.TestCase):
    def write_binary(self, root: Path, relative: str, payload: bytes) -> Path:
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(MACHO64_LE + payload)
        return path

    def test_inventory_only_includes_selected_macho_artifacts(self):
        with tempfile.TemporaryDirectory() as temporary:
            support = Path(temporary) / "27.0.1 (TEST) universal"
            symbols = support / "Symbols"
            self.write_binary(symbols, "System/Library/Kernels/kernel", b"old-kernel")
            self.write_binary(
                symbols,
                "System/Library/Extensions/Test.kext/Contents/MacOS/Test",
                b"old-driver",
            )
            opaque = symbols / "System/Library/Caches/com.apple.kernelcaches/kernelcache.release"
            opaque.parent.mkdir(parents=True, exist_ok=True)
            opaque.write_bytes(b"opaque-test-container")
            ignored = symbols / "System/Library/Kernels/notes.txt"
            ignored.parent.mkdir(parents=True, exist_ok=True)
            ignored.write_text("not Mach-O", encoding="utf-8")
            self.write_binary(symbols, "usr/lib/libIgnored.dylib", b"ignored")

            manifest = build_inventory(support, "old", with_uuids=False)

            self.assertEqual(manifest["fileCount"], 3)
            self.assertEqual(
                [entry["path"] for entry in manifest["files"]],
                [
                    "System/Library/Caches/com.apple.kernelcaches/kernelcache.release",
                    "System/Library/Extensions/Test.kext/Contents/MacOS/Test",
                    "System/Library/Kernels/kernel",
                ],
            )
            self.assertEqual(manifest["componentCounts"]["xnu-kernel"], 1)
            self.assertEqual(manifest["componentCounts"]["kernel-cache"], 1)
            self.assertEqual(
                manifest["componentCounts"]["extension-tree-binary"], 1
            )

    def test_compare_reports_changed_added_removed_and_unchanged(self):
        old = {
            "schemaVersion": 1,
            "label": "27.0.1",
            "inputRoot": "/old",
            "fileCount": 3,
            "files": [
                {"path": "kernel", "component": "xnu-kernel", "sha256": "a", "size": 1},
                {"path": "same", "component": "extension-tree-binary", "sha256": "b", "size": 2},
                {"path": "removed", "component": "extension-tree-binary", "sha256": "c", "size": 3},
            ],
        }
        fixed = {
            "schemaVersion": 1,
            "label": "27.2",
            "inputRoot": "/fixed",
            "fileCount": 3,
            "files": [
                {"path": "kernel", "component": "xnu-kernel", "sha256": "d", "size": 4},
                {"path": "same", "component": "extension-tree-binary", "sha256": "b", "size": 2},
                {"path": "added", "component": "extension-tree-binary", "sha256": "e", "size": 5},
            ],
        }

        comparison = compare_manifests(old, fixed)

        self.assertEqual(
            comparison["counts"],
            {"added": 1, "removed": 1, "changed": 1, "unchanged": 1},
        )
        self.assertEqual(comparison["changed"][0]["path"], "kernel")
        self.assertEqual(comparison["changedComponentCounts"], {"xnu-kernel": 1})
        self.assertEqual(comparison["coverage"]["status"], "kernel-artifacts-present")

    def test_bootstrap_wrapper_handles_device_support_paths_with_spaces(self):
        with tempfile.TemporaryDirectory() as temporary:
            temporary_root = Path(temporary)
            old = temporary_root / "Watch7,4 27.0.1 (TEST)" / "Symbols"
            fixed = temporary_root / "Watch7,4 27.2 (TEST)" / "Symbols"
            output = temporary_root / "Run With Spaces"
            self.write_binary(old, "System/Library/Kernels/kernel", b"old")
            self.write_binary(fixed, "System/Library/Kernels/kernel", b"fixed")

            result = subprocess.run(
                [
                    "bash",
                    str(REPOSITORY_ROOT / "Experiments/watchos27-kernel-cve-lab.sh"),
                    "bootstrap",
                    "--old-root",
                    str(old.parent),
                    "--fixed-root",
                    str(fixed.parent),
                    "--output",
                    str(output),
                    "--no-uuids",
                ],
                check=False,
                capture_output=True,
                text=True,
                timeout=30,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("KERNEL_CVE_BOOTSTRAP=INVENTORY_PASS", result.stdout)
            comparison = json.loads((output / "comparison.json").read_text())
            self.assertEqual(comparison["counts"]["changed"], 1)
            self.assertEqual(
                comparison["coverage"]["status"], "kernel-artifacts-present"
            )


if __name__ == "__main__":
    unittest.main()
