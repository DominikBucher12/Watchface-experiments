#!/usr/bin/env python3

import json
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path


TOOL = Path(__file__).resolve().parents[1] / "watchface_corpus.py"


class WatchFaceCorpusTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.source = self.root / "Owned.watchface"
        with zipfile.ZipFile(self.source, "w") as archive:
            archive.writestr(
                "face.json",
                json.dumps({"face": "test", "version": 1}).encode("utf-8"),
            )
            archive.writestr("assets/preview.png", b"\x89PNG\r\n\x1a\n" + b"A" * 64)
            archive.writestr("notes/readme.txt", b"fixture")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def run_tool(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(TOOL), *arguments],
            check=False,
            text=True,
            capture_output=True,
        )

    def test_inspect_generate_verify_and_resolve(self) -> None:
        inspection = self.run_tool("inspect", str(self.source))
        self.assertEqual(inspection.returncode, 0, inspection.stderr)
        self.assertEqual(json.loads(inspection.stdout)["entryCount"], 3)

        corpus = self.root / "Corpus"
        generation = self.run_tool("generate", str(self.source), str(corpus))
        self.assertEqual(generation.returncode, 0, generation.stderr)
        generated = json.loads(generation.stdout)
        self.assertGreaterEqual(generated["caseCount"], 10)

        verification = self.run_tool("verify", str(corpus))
        self.assertEqual(verification.returncode, 0, verification.stderr)
        self.assertTrue(json.loads(verification.stdout)["verified"])

        resolution = self.run_tool("resolve", str(corpus), "000-baseline")
        self.assertEqual(resolution.returncode, 0, resolution.stderr)
        self.assertEqual(Path(resolution.stdout.strip()).name, "000-baseline.watchface")

    def test_rejects_path_traversal_member(self) -> None:
        unsafe = self.root / "Unsafe.watchface"
        with zipfile.ZipFile(unsafe, "w") as archive:
            archive.writestr("../outside.json", b"{}")
        result = self.run_tool("inspect", str(unsafe))
        self.assertEqual(result.returncode, 2)
        self.assertIn("unsafe archive member", result.stderr)

    def test_detects_case_tampering(self) -> None:
        corpus = self.root / "Corpus"
        generation = self.run_tool("generate", str(self.source), str(corpus))
        self.assertEqual(generation.returncode, 0, generation.stderr)
        (corpus / "000-baseline.watchface").write_bytes(b"changed")
        verification = self.run_tool("verify", str(corpus))
        self.assertEqual(verification.returncode, 2)
        self.assertIn("hash mismatch", verification.stderr)


if __name__ == "__main__":
    unittest.main()
