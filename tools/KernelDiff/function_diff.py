#!/usr/bin/env python3
"""Compare stripped XNU functions using instruction-encoding fingerprints."""

from __future__ import annotations

import argparse
import difflib
import hashlib
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Function:
    name: str
    count: int
    encodings: tuple[str, ...]
    operations: tuple[str, ...]

    @property
    def address(self) -> int:
        return int(self.name.removeprefix("sub_"), 16)

    @property
    def fingerprint(self) -> str:
        material = "\0".join(self.encodings).encode()
        return hashlib.sha256(material).hexdigest()


def load(path: Path) -> list[Function]:
    functions: list[Function] = []
    with path.open(encoding="utf-8") as stream:
        for number, line in enumerate(stream, 1):
            fields = line.rstrip("\n").split("\t")
            if len(fields) != 4:
                raise ValueError(f"{path}:{number}: expected four TSV fields")
            name, count, encodings, operations = fields
            functions.append(
                Function(
                    name=name,
                    count=int(count),
                    encodings=tuple(encodings.split(",")) if encodings else (),
                    operations=tuple(operations.split(",")) if operations else (),
                )
            )
    return functions


def compact_delta(old: Function, new: Function) -> str:
    matcher = difflib.SequenceMatcher(
        None, old.operations, new.operations, autojunk=False
    )
    pieces: list[str] = []
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == "equal":
            continue
        before = ",".join(old.operations[i1:i2]) or "∅"
        after = ",".join(new.operations[j1:j2]) or "∅"
        pieces.append(f"{tag}: `{before}` → `{after}`")
        if len(pieces) == 3:
            break
    return "; ".join(pieces) or "operand/immediate-only change"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("old", type=Path)
    parser.add_argument("new", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--candidates", type=Path)
    args = parser.parse_args()

    old = load(args.old)
    new = load(args.new)
    matcher = difflib.SequenceMatcher(
        None,
        [function.fingerprint for function in old],
        [function.fingerprint for function in new],
        autojunk=False,
    )

    exact = sum(block.size for block in matcher.get_matching_blocks())
    changed: list[tuple[float, Function, Function]] = []
    inserted = 0
    deleted = 0
    blocks: list[tuple[str, int, int, int, int]] = []

    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == "equal":
            continue
        blocks.append((tag, i1, i2, j1, j2))
        old_block = old[i1:i2]
        new_block = new[j1:j2]
        paired = min(len(old_block), len(new_block))
        for offset in range(paired):
            before = old_block[offset]
            after = new_block[offset]
            similarity = difflib.SequenceMatcher(
                None, before.encodings, after.encodings, autojunk=False
            ).ratio()
            changed.append((similarity, before, after))
        deleted += len(old_block) - paired
        inserted += len(new_block) - paired

    changed.sort(key=lambda item: (item[0], abs(item[1].count - item[2].count)))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as report:
        report.write("# XNU function-start structural diff\n\n")
        report.write(f"- Old functions: {len(old):,}\n")
        report.write(f"- New functions: {len(new):,}\n")
        report.write(f"- Exact encoding-shape matches: {exact:,}\n")
        report.write(f"- Paired changed candidates: {len(changed):,}\n")
        report.write(f"- Unpaired deletions: {deleted:,}\n")
        report.write(f"- Unpaired insertions: {inserted:,}\n")
        report.write(f"- Non-equal sequence blocks: {len(blocks):,}\n\n")
        report.write(
            "Fingerprints use instruction encoding classes, not raw addresses, so "
            "address relocation alone does not mark a function as changed. Candidate "
            "pairing inside replacement blocks is positional and must be confirmed "
            "with local disassembly before attribution.\n\n"
        )
        report.write("## Lowest-similarity changed candidates\n\n")
        report.write("| Similarity | Old | New | Instructions | Operation delta |\n")
        report.write("|---:|---|---|---:|---|\n")
        for similarity, before, after in changed[:250]:
            report.write(
                f"| {similarity:.3f} | `{before.name}` | `{after.name}` | "
                f"{before.count} → {after.count} | {compact_delta(before, after)} |\n"
            )

    candidates = args.candidates or args.output.with_suffix(".candidates.tsv")
    with candidates.open("w", encoding="utf-8") as stream:
        stream.write("similarity\told_name\told_count\tnew_name\tnew_count\n")
        for similarity, before, after in changed:
            stream.write(
                f"{similarity:.6f}\t{before.name}\t{before.count}\t"
                f"{after.name}\t{after.count}\n"
            )

    print(f"old={len(old)} new={len(new)} exact={exact}")
    print(f"changed={len(changed)} deleted={deleted} inserted={inserted}")
    print(f"report={args.output}")
    print(f"candidates={candidates}")


if __name__ == "__main__":
    main()
