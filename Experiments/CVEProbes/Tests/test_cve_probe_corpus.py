import json
import tempfile
import unittest
from pathlib import Path

from cve_probe_corpus import CorpusError, generate, resolve, verified_cases


class CVEProbeCorpusTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.image = self.root / "seed.gif"
        self.image.write_bytes(b"GIF89a" + bytes(range(64)))
        self.font = self.root / "seed.ttf"
        self.font.write_bytes(b"\x00\x01\x00\x00" + bytes(range(128)))

    def tearDown(self):
        self.temporary.cleanup()

    def test_generate_creates_three_bounded_probe_sets(self):
        corpus = self.root / "corpus"
        manifest = generate(corpus, self.image, self.font, None, False)
        self.assertEqual(manifest["caseCount"], 12)
        self.assertEqual(manifest["probes"], ["audio", "font", "imageio"])
        self.assertEqual(len(verified_cases(corpus)), 12)

    def test_resolve_rejects_unknown_case(self):
        corpus = self.root / "corpus"
        generate(corpus, self.image, self.font, None, False)
        with self.assertRaises(CorpusError):
            resolve(corpus, "missing")

    def test_verify_detects_modified_case(self):
        corpus = self.root / "corpus"
        generate(corpus, self.image, self.font, None, False)
        manifest = json.loads((corpus / "manifest.json").read_text())
        case_path = corpus / manifest["cases"][0]["path"]
        case_path.write_bytes(case_path.read_bytes() + b"changed")
        with self.assertRaises(CorpusError):
            verified_cases(corpus)


if __name__ == "__main__":
    unittest.main()
