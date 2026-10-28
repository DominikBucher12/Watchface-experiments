#!/usr/bin/env python3
"""Create and verify a small deterministic media-parser corpus.

The corpus contains only four bounded variants per supplied seed. It is not a
coverage-guided fuzzer and never communicates with a device.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
import shutil
import struct
import subprocess
import sys
import tempfile
import wave
from datetime import datetime, timezone
from pathlib import Path


MAX_SEED_BYTES = 8 * 1024 * 1024
PROBE_EXTENSIONS = {
    "imageio": {".gif", ".heic", ".heif", ".jpeg", ".jpg", ".png", ".tif", ".tiff", ".webp"},
    "font": {".otf", ".ttc", ".ttf"},
    "audio": {".aif", ".aiff", ".caf", ".m4a", ".wav"},
    "video": {".m4v", ".mov", ".mp4"},
}


class CorpusError(RuntimeError):
    pass


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_seed(path: Path, probe: str) -> bytes:
    if not path.is_file():
        raise CorpusError(f"{probe} seed is not a file: {path}")
    if path.suffix.lower() not in PROBE_EXTENSIONS[probe]:
        supported = ", ".join(sorted(PROBE_EXTENSIONS[probe]))
        raise CorpusError(f"unsupported {probe} extension {path.suffix!r}; use {supported}")
    size = path.stat().st_size
    if size < 1 or size > MAX_SEED_BYTES:
        raise CorpusError(f"{probe} seed must contain 1...{MAX_SEED_BYTES} bytes")
    return path.read_bytes()


def make_audio_seed() -> bytes:
    sample_rate = 8_000
    frame_count = sample_rate // 4
    output = io.BytesIO()
    with wave.open(output, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(sample_rate)
        frames = bytearray()
        for index in range(frame_count):
            value = int(8_000 * math.sin(2 * math.pi * 440 * index / sample_rate))
            frames.extend(struct.pack("<h", value))
        wav.writeframes(bytes(frames))
    return output.getvalue()


def default_font() -> Path | None:
    candidates = (
        Path("/System/Library/Fonts/SFNSMono.ttf"),
        Path("/System/Library/Fonts/Symbol.ttf"),
        Path("/System/Library/Fonts/Menlo.ttc"),
    )
    return next((candidate for candidate in candidates if candidate.is_file()), None)


def make_video_seed(image: Path, destination: Path) -> bool:
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        return False
    commands = (
        [
            ffmpeg,
            "-y", "-v", "error", "-i", str(image), "-t", "1",
            "-vf", "scale=64:64:force_original_aspect_ratio=decrease,pad=64:64:(ow-iw)/2:(oh-ih)/2:black",
            "-an", "-c:v", "libx264", "-pix_fmt", "yuv420p",
            "-movflags", "+faststart", str(destination),
        ],
        [
            ffmpeg,
            "-y", "-v", "error", "-i", str(image), "-t", "1",
            "-vf", "scale=64:64:force_original_aspect_ratio=decrease,pad=64:64:(ow-iw)/2:(oh-ih)/2:black",
            "-an", "-c:v", "h264_videotoolbox", "-pix_fmt", "yuv420p",
            "-movflags", "+faststart", str(destination),
        ],
    )
    for command in commands:
        completed = subprocess.run(
            command,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        if completed.returncode == 0 and destination.is_file() and destination.stat().st_size:
            return True
        destination.unlink(missing_ok=True)
    return False


def variants(data: bytes) -> list[tuple[str, str, bytes, bool]]:
    flipped = bytearray(data)
    flip_index = min(len(flipped) - 1, max(16, len(flipped) // 2))
    flipped[flip_index] ^= 0x01

    trim_count = max(1, min(64, len(data) // 16))
    truncated = data[:-trim_count] if trim_count < len(data) else data[:1]
    return [
        ("000-baseline", "byte-identical control", data, True),
        ("010-appended-tail", "append sixteen fixed nonzero bytes", data + b"WFLAB-TAIL-00001", False),
        ("020-middle-bitflip", "flip one bit near the middle", bytes(flipped), False),
        ("030-tail-truncated", f"remove the final {trim_count} bytes", truncated, False),
    ]


def generate(
    output: Path,
    image: Path,
    font: Path | None,
    video: Path | None,
    auto_video: bool,
) -> dict[str, object]:
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise CorpusError(f"output must be a missing or empty directory: {output}")
    cases_dir = output / "Cases"
    cases_dir.mkdir(parents=True, exist_ok=True)

    seeds: list[tuple[str, str, bytes]] = [
        ("imageio", image.suffix.lower(), read_seed(image, "imageio")),
        ("audio", ".wav", make_audio_seed()),
    ]

    selected_font = font or default_font()
    if selected_font is not None:
        seeds.append(("font", selected_font.suffix.lower(), read_seed(selected_font, "font")))

    generated_video: Path | None = None
    temporary: tempfile.TemporaryDirectory[str] | None = None
    try:
        if video is not None:
            seeds.append(("video", video.suffix.lower(), read_seed(video, "video")))
        elif auto_video:
            temporary = tempfile.TemporaryDirectory(prefix="WatchFaceLab-CVEVideo-")
            generated_video = Path(temporary.name) / "baseline.mp4"
            if make_video_seed(image, generated_video):
                seeds.append(("video", ".mp4", read_seed(generated_video, "video")))

        cases: list[dict[str, object]] = []
        for probe, extension, seed_data in seeds:
            seed_hash = sha256_bytes(seed_data)
            for suffix, description, case_data, baseline in variants(seed_data):
                case_id = f"{probe}-{suffix}"
                relative_path = Path("Cases") / f"{case_id}{extension}"
                case_path = output / relative_path
                case_path.write_bytes(case_data)
                cases.append(
                    {
                        "caseID": case_id,
                        "probe": probe,
                        "description": description,
                        "baseline": baseline,
                        "path": relative_path.as_posix(),
                        "bytes": len(case_data),
                        "sha256": sha256_bytes(case_data),
                        "seedSHA256": seed_hash,
                    }
                )
    finally:
        if temporary is not None:
            temporary.cleanup()

    manifest: dict[str, object] = {
        "schemaVersion": 1,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "maximumInputBytes": MAX_SEED_BYTES,
        "caseCount": len(cases),
        "probes": sorted({str(case["probe"]) for case in cases}),
        "cases": cases,
    }
    (output / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return manifest


def load_manifest(corpus: Path) -> dict[str, object]:
    manifest_path = corpus / "manifest.json"
    try:
        value = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise CorpusError(f"cannot read manifest: {error}") from error
    if value.get("schemaVersion") != 1 or not isinstance(value.get("cases"), list):
        raise CorpusError("unsupported or malformed manifest")
    return value


def verified_cases(corpus: Path) -> list[dict[str, object]]:
    manifest = load_manifest(corpus)
    cases = manifest["cases"]
    assert isinstance(cases, list)
    seen: set[str] = set()
    verified: list[dict[str, object]] = []
    for raw in cases:
        if not isinstance(raw, dict):
            raise CorpusError("manifest case must be an object")
        case_id = raw.get("caseID")
        relative = raw.get("path")
        expected_hash = raw.get("sha256")
        probe = raw.get("probe")
        if not all(isinstance(value, str) and value for value in (case_id, relative, expected_hash, probe)):
            raise CorpusError("manifest case has missing string fields")
        if case_id in seen:
            raise CorpusError(f"duplicate case ID: {case_id}")
        seen.add(case_id)
        path = Path(relative)
        if path.is_absolute() or ".." in path.parts:
            raise CorpusError(f"unsafe case path: {relative}")
        absolute = corpus / path
        if not absolute.is_file():
            raise CorpusError(f"case file is missing: {relative}")
        if absolute.stat().st_size > MAX_SEED_BYTES + 16:
            raise CorpusError(f"case exceeds the bounded size: {case_id}")
        actual_hash = sha256_file(absolute)
        if actual_hash != expected_hash:
            raise CorpusError(f"hash mismatch for {case_id}")
        verified.append(raw)
    return verified


def resolve(corpus: Path, case_id: str) -> Path:
    for case in verified_cases(corpus):
        if case["caseID"] == case_id:
            return corpus / str(case["path"])
    raise CorpusError(f"unknown case ID: {case_id}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    generate_parser = subparsers.add_parser("generate")
    generate_parser.add_argument("output", type=Path)
    generate_parser.add_argument("--image", required=True, type=Path)
    generate_parser.add_argument("--font", type=Path)
    generate_parser.add_argument("--video", type=Path)
    generate_parser.add_argument("--auto-video", action="store_true")

    for command in ("list", "verify"):
        command_parser = subparsers.add_parser(command)
        command_parser.add_argument("corpus", type=Path)
    resolve_parser = subparsers.add_parser("resolve")
    resolve_parser.add_argument("corpus", type=Path)
    resolve_parser.add_argument("case_id")

    args = parser.parse_args(argv)
    try:
        if args.command == "generate":
            manifest = generate(args.output, args.image, args.font, args.video, args.auto_video)
            print(f"CORPUS={args.output}")
            print(f"CASES={manifest['caseCount']}")
            print(f"PROBES={','.join(manifest['probes'])}")
        elif args.command == "list":
            for case in verified_cases(args.corpus):
                print(
                    f"{case['caseID']}\t{case['probe']}\t{case['bytes']}\t"
                    f"{case['sha256']}\t{case['description']}"
                )
        elif args.command == "verify":
            cases = verified_cases(args.corpus)
            print(f"VERIFY=PASS CASES={len(cases)}")
        elif args.command == "resolve":
            print(resolve(args.corpus, args.case_id))
    except CorpusError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
