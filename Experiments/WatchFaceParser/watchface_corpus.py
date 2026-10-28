#!/usr/bin/env python3
"""Create a small, deterministic corpus from an owned .watchface export.

This tool intentionally stops at parser robustness testing. It does not create
executable payloads, attempt a sandbox escape, or automatically send every case
to a device. The companion shell runner installs exactly one explicitly chosen
case at a time.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import plistlib
import shutil
import stat
import sys
import zipfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Callable, Iterable


MAX_ARCHIVE_BYTES = 64 * 1024 * 1024
MAX_ENTRIES = 512
MAX_ENTRY_BYTES = 64 * 1024 * 1024
MAX_TOTAL_UNCOMPRESSED_BYTES = 256 * 1024 * 1024
MAX_COMPRESSION_RATIO = 200

METADATA_SUFFIXES = {".json", ".plist"}
ASSET_SUFFIXES = {
    ".gif",
    ".heic",
    ".heif",
    ".jpeg",
    ".jpg",
    ".pdf",
    ".png",
    ".tiff",
    ".webp",
}


class CorpusError(RuntimeError):
    pass


@dataclass
class Entry:
    info: zipfile.ZipInfo
    data: bytes


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def classify(name: str) -> str:
    suffix = PurePosixPath(name).suffix.lower()
    if suffix in METADATA_SUFFIXES:
        return "metadata"
    if suffix in ASSET_SUFFIXES:
        return "asset"
    return "other"


def validate_member(info: zipfile.ZipInfo) -> None:
    name = info.filename
    if not name or "\x00" in name or "\\" in name or name.startswith("/"):
        raise CorpusError(f"unsafe archive member name: {name!r}")

    path = PurePosixPath(name.rstrip("/"))
    if not path.parts or any(part in {"", ".", ".."} for part in path.parts):
        raise CorpusError(f"unsafe archive member path: {name!r}")
    if info.flag_bits & 0x1:
        raise CorpusError(f"encrypted archive member is unsupported: {name}")

    unix_mode = (info.external_attr >> 16) & 0xFFFF
    if unix_mode and stat.S_IFMT(unix_mode) == stat.S_IFLNK:
        raise CorpusError(f"symbolic-link archive member is unsupported: {name}")
    if info.file_size > MAX_ENTRY_BYTES:
        raise CorpusError(f"archive member exceeds {MAX_ENTRY_BYTES} bytes: {name}")
    if info.file_size > 0:
        ratio = info.file_size / max(info.compress_size, 1)
        if ratio > MAX_COMPRESSION_RATIO:
            raise CorpusError(
                f"archive member compression ratio {ratio:.1f} exceeds "
                f"{MAX_COMPRESSION_RATIO}: {name}"
            )


def read_archive(path: Path) -> list[Entry]:
    if not path.is_file():
        raise CorpusError(f"input is not a file: {path}")
    if path.suffix.lower() != ".watchface":
        raise CorpusError("input must have the .watchface extension")
    if path.stat().st_size > MAX_ARCHIVE_BYTES:
        raise CorpusError(f"input exceeds the {MAX_ARCHIVE_BYTES}-byte safety limit")
    if not zipfile.is_zipfile(path):
        raise CorpusError("input is not a ZIP-compatible .watchface export")

    entries: list[Entry] = []
    total_size = 0
    try:
        with zipfile.ZipFile(path, "r") as archive:
            infos = archive.infolist()
            if not infos:
                raise CorpusError("archive is empty")
            if len(infos) > MAX_ENTRIES:
                raise CorpusError(
                    f"archive contains more than {MAX_ENTRIES} entries"
                )
            for info in infos:
                validate_member(info)
                total_size += info.file_size
                if total_size > MAX_TOTAL_UNCOMPRESSED_BYTES:
                    raise CorpusError(
                        "archive exceeds the total uncompressed-size safety limit"
                    )
                data = b"" if info.is_dir() else archive.read(info)
                entries.append(Entry(info=copy.copy(info), data=data))
    except CorpusError:
        raise
    except (OSError, RuntimeError, NotImplementedError, zipfile.BadZipFile) as error:
        raise CorpusError(f"cannot safely read archive: {error}") from error
    return entries


def archive_summary(path: Path, entries: Iterable[Entry]) -> dict[str, object]:
    records = []
    for index, entry in enumerate(entries):
        records.append(
            {
                "index": index,
                "name": entry.info.filename,
                "classification": classify(entry.info.filename),
                "size": len(entry.data),
                "compressedSize": entry.info.compress_size,
                "sha256": sha256_bytes(entry.data),
            }
        )
    return {
        "schemaVersion": 1,
        "name": path.name,
        "size": path.stat().st_size,
        "sha256": sha256_file(path),
        "entryCount": len(records),
        "entries": records,
    }


def write_archive(path: Path, entries: Iterable[Entry]) -> None:
    with zipfile.ZipFile(path, "w", allowZip64=False) as archive:
        for entry in entries:
            info = copy.copy(entry.info)
            archive.writestr(info, entry.data)


def flipped(data: bytes) -> bytes:
    if not data:
        return data
    result = bytearray(data)
    index = len(result) // 2
    result[index] ^= 0x01
    return bytes(result)


def truncated(data: bytes) -> bytes:
    if len(data) <= 1:
        return b""
    return data[: max(1, len(data) // 2)]


def valid_metadata_with_unknown_key(name: str, data: bytes) -> bytes | None:
    suffix = PurePosixPath(name).suffix.lower()
    try:
        if suffix == ".json":
            value = json.loads(data.decode("utf-8"))
            if not isinstance(value, dict):
                return None
            value["_watchfacelabUnknownKey"] = "bounded-parser-test"
            return json.dumps(
                value, ensure_ascii=False, sort_keys=True, indent=2
            ).encode("utf-8")
        if suffix == ".plist":
            value = plistlib.loads(data)
            if not isinstance(value, dict):
                return None
            value["_watchfacelabUnknownKey"] = "bounded-parser-test"
            return plistlib.dumps(value, fmt=plistlib.FMT_BINARY, sort_keys=True)
    except (UnicodeDecodeError, ValueError, json.JSONDecodeError, plistlib.InvalidFileException):
        return None
    return None


def archive_test(path: Path) -> dict[str, object]:
    try:
        with zipfile.ZipFile(path, "r") as archive:
            bad_member = archive.testzip()
        return {"opensAsZip": True, "firstBadMember": bad_member}
    except (OSError, zipfile.BadZipFile, RuntimeError) as error:
        return {
            "opensAsZip": False,
            "archiveError": f"{type(error).__name__}: {error}",
        }


def generate_corpus(source: Path, output: Path) -> dict[str, object]:
    entries = read_archive(source)
    if output.exists():
        if not output.is_dir():
            raise CorpusError(f"output exists and is not a directory: {output}")
        if any(output.iterdir()):
            raise CorpusError(f"output directory is not empty: {output}")
    output.mkdir(parents=True, exist_ok=True)

    cases: list[dict[str, object]] = []

    def add_case(
        case_id: str,
        description: str,
        mutation: str,
        target: str | None,
        writer: Callable[[Path], None],
    ) -> None:
        path = output / f"{case_id}.watchface"
        writer(path)
        record: dict[str, object] = {
            "id": case_id,
            "file": path.name,
            "description": description,
            "mutation": mutation,
            "targetEntry": target,
            "size": path.stat().st_size,
            "sha256": sha256_file(path),
        }
        record.update(archive_test(path))
        cases.append(record)

    add_case(
        "000-baseline",
        "Byte-identical exported face used as the control.",
        "none",
        None,
        lambda path: shutil.copy2(source, path),
    )

    source_data = source.read_bytes()
    tail_count = min(22, max(1, len(source_data) // 10))
    add_case(
        "010-truncated-tail",
        f"Remove {tail_count} bytes from the archive tail.",
        "archive-tail-truncation",
        None,
        lambda path: path.write_bytes(source_data[:-tail_count]),
    )
    add_case(
        "011-appended-tail",
        "Append a fixed 16-byte marker after the ZIP end record.",
        "archive-tail-append",
        None,
        lambda path: path.write_bytes(source_data + b"WATCHFACELAB\x00\x00\x00\x00"),
    )

    metadata_indices = [
        index
        for index, entry in enumerate(entries)
        if classify(entry.info.filename) == "metadata" and not entry.info.is_dir()
    ]
    asset_indices = [
        index
        for index, entry in enumerate(entries)
        if classify(entry.info.filename) == "asset" and not entry.info.is_dir()
    ]

    def replaced_writer(index: int, replacement: bytes) -> Callable[[Path], None]:
        def writer(path: Path) -> None:
            changed = [Entry(copy.copy(item.info), item.data) for item in entries]
            changed[index].data = replacement
            write_archive(path, changed)

        return writer

    def removed_writer(index: int) -> Callable[[Path], None]:
        def writer(path: Path) -> None:
            changed = [
                Entry(copy.copy(item.info), item.data)
                for item_index, item in enumerate(entries)
                if item_index != index
            ]
            write_archive(path, changed)

        return writer

    if metadata_indices:
        index = metadata_indices[0]
        entry = entries[index]
        target = entry.info.filename
        add_case(
            "100-metadata-empty",
            "Replace the first metadata entry with zero bytes.",
            "entry-replacement-empty",
            target,
            replaced_writer(index, b""),
        )
        add_case(
            "101-metadata-truncated",
            "Truncate the first metadata entry to half its original size.",
            "entry-truncation-half",
            target,
            replaced_writer(index, truncated(entry.data)),
        )
        add_case(
            "102-metadata-bitflip",
            "Flip one low-order bit at the midpoint of the first metadata entry.",
            "entry-single-bit-flip",
            target,
            replaced_writer(index, flipped(entry.data)),
        )
        add_case(
            "103-metadata-removed",
            "Remove the first metadata entry while retaining the other entries.",
            "entry-removal",
            target,
            removed_writer(index),
        )
        unknown_key_data = valid_metadata_with_unknown_key(target, entry.data)
        if unknown_key_data is not None:
            add_case(
                "104-metadata-unknown-key",
                "Add one unknown key while keeping the metadata syntactically valid.",
                "metadata-unknown-key",
                target,
                replaced_writer(index, unknown_key_data),
            )

    if asset_indices:
        index = max(asset_indices, key=lambda item: len(entries[item].data))
        entry = entries[index]
        target = entry.info.filename
        add_case(
            "200-asset-truncated",
            "Truncate the largest recognized asset to half its original size.",
            "entry-truncation-half",
            target,
            replaced_writer(index, truncated(entry.data)),
        )
        add_case(
            "201-asset-bitflip",
            "Flip one low-order bit at the midpoint of the largest recognized asset.",
            "entry-single-bit-flip",
            target,
            replaced_writer(index, flipped(entry.data)),
        )
        add_case(
            "202-asset-removed",
            "Remove the largest recognized asset while retaining the other entries.",
            "entry-removal",
            target,
            removed_writer(index),
        )

    def extra_entry_writer(path: Path) -> None:
        changed = [Entry(copy.copy(item.info), item.data) for item in entries]
        info = zipfile.ZipInfo("WatchFaceLab-Unknown.json")
        info.compress_type = zipfile.ZIP_DEFLATED
        changed.append(Entry(info, b'{"purpose":"bounded-parser-test","version":1}\n'))
        write_archive(path, changed)

    add_case(
        "300-extra-unknown-entry",
        "Add one small unknown JSON entry to an otherwise valid archive.",
        "archive-extra-entry",
        "WatchFaceLab-Unknown.json",
        extra_entry_writer,
    )

    manifest: dict[str, object] = {
        "schemaVersion": 1,
        "createdAt": datetime.now(timezone.utc).isoformat(),
        "source": {
            "name": source.name,
            "size": source.stat().st_size,
            "sha256": sha256_file(source),
        },
        "limits": {
            "maxArchiveBytes": MAX_ARCHIVE_BYTES,
            "maxEntries": MAX_ENTRIES,
            "maxEntryBytes": MAX_ENTRY_BYTES,
            "maxTotalUncompressedBytes": MAX_TOTAL_UNCOMPRESSED_BYTES,
            "maxCompressionRatio": MAX_COMPRESSION_RATIO,
        },
        "caseCount": len(cases),
        "cases": cases,
    }
    (output / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return manifest


def read_manifest(corpus: Path) -> dict[str, object]:
    manifest_path = corpus / "manifest.json"
    try:
        value = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise CorpusError(f"cannot read corpus manifest: {error}") from error
    if value.get("schemaVersion") != 1 or not isinstance(value.get("cases"), list):
        raise CorpusError("unsupported or malformed corpus manifest")
    return value


def case_path(corpus: Path, case_id: str) -> Path:
    if not case_id or any(character not in "abcdefghijklmnopqrstuvwxyz0123456789-" for character in case_id):
        raise CorpusError(f"invalid case identifier: {case_id!r}")
    manifest = read_manifest(corpus)
    matches = [item for item in manifest["cases"] if item.get("id") == case_id]
    if len(matches) != 1:
        raise CorpusError(f"case does not exist exactly once: {case_id}")
    record = matches[0]
    filename = record.get("file")
    if not isinstance(filename, str) or Path(filename).name != filename:
        raise CorpusError(f"unsafe case filename in manifest: {filename!r}")
    path = (corpus / filename).resolve()
    corpus_root = corpus.resolve()
    if path.parent != corpus_root or not path.is_file():
        raise CorpusError(f"case file is missing or outside the corpus: {filename}")
    expected_hash = record.get("sha256")
    actual_hash = sha256_file(path)
    if actual_hash != expected_hash:
        raise CorpusError(
            f"case hash mismatch for {case_id}: expected {expected_hash}, got {actual_hash}"
        )
    return path


def verify_corpus(corpus: Path) -> dict[str, object]:
    manifest = read_manifest(corpus)
    verified = []
    for record in manifest["cases"]:
        case_id = record.get("id")
        if not isinstance(case_id, str):
            raise CorpusError("case without a string identifier")
        path = case_path(corpus, case_id)
        if path.stat().st_size != record.get("size"):
            raise CorpusError(f"case size mismatch for {case_id}")
        verified.append(case_id)
    return {"verified": True, "caseCount": len(verified), "cases": verified}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    inspect_parser = subparsers.add_parser("inspect", help="inspect an owned export")
    inspect_parser.add_argument("input", type=Path)

    generate_parser = subparsers.add_parser(
        "generate", help="generate a bounded deterministic corpus"
    )
    generate_parser.add_argument("input", type=Path)
    generate_parser.add_argument("output", type=Path)

    verify_parser = subparsers.add_parser("verify", help="verify corpus hashes")
    verify_parser.add_argument("corpus", type=Path)

    list_parser = subparsers.add_parser("list", help="list generated cases")
    list_parser.add_argument("corpus", type=Path)

    resolve_parser = subparsers.add_parser(
        "resolve", help="verify and print one case path"
    )
    resolve_parser.add_argument("corpus", type=Path)
    resolve_parser.add_argument("case_id")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        if args.command == "inspect":
            path = args.input.expanduser().resolve()
            print(json.dumps(archive_summary(path, read_archive(path)), indent=2))
        elif args.command == "generate":
            source = args.input.expanduser().resolve()
            output = args.output.expanduser().resolve()
            manifest = generate_corpus(source, output)
            print(
                json.dumps(
                    {
                        "generated": True,
                        "output": str(output),
                        "caseCount": manifest["caseCount"],
                    },
                    indent=2,
                )
            )
        elif args.command == "verify":
            print(
                json.dumps(
                    verify_corpus(args.corpus.expanduser().resolve()), indent=2
                )
            )
        elif args.command == "list":
            manifest = read_manifest(args.corpus.expanduser().resolve())
            for record in manifest["cases"]:
                print(
                    f"{record['id']}\t{record['mutation']}\t"
                    f"{record['description']}"
                )
        elif args.command == "resolve":
            print(
                case_path(
                    args.corpus.expanduser().resolve(), args.case_id
                )
            )
        return 0
    except CorpusError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
