#!/usr/bin/env python3
"""Annotate changed stripped-kernel functions with strings and call targets."""

from __future__ import annotations

import argparse
import csv
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path


QUOTED = re.compile(r';\s+"((?:[^"\\]|\\.)*)"')
CALL = re.compile(r"\bbl(?:raa)?\s+(0x[0-9a-f]+)")


@dataclass(frozen=True)
class Candidate:
    similarity: str
    old_name: str
    old_count: int
    new_name: str
    new_count: int


def disassemble(ipsw: Path, binary: Path, name: str, count: int) -> str:
    address = name.removeprefix("sub_")
    command = [
        str(ipsw),
        "macho",
        "disass",
        str(binary),
        "--vaddr",
        f"0x{address}",
        "--count",
        str(count),
        "--demangle",
        "--no-color",
    ]
    result = subprocess.run(
        command,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    return result.stdout


def annotations(text: str) -> tuple[str, str]:
    strings = sorted({match.group(1) for match in QUOTED.finditer(text)})
    calls = [match.group(1) for match in CALL.finditer(text)]
    return " | ".join(strings), ",".join(calls)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("candidates", type=Path)
    parser.add_argument("old", type=Path)
    parser.add_argument("new", type=Path)
    parser.add_argument("--ipsw", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    candidates: list[Candidate] = []
    with args.candidates.open(newline="", encoding="utf-8") as stream:
        for row in csv.DictReader(stream, delimiter="\t"):
            candidates.append(
                Candidate(
                    similarity=row["similarity"],
                    old_name=row["old_name"],
                    old_count=int(row["old_count"]),
                    new_name=row["new_name"],
                    new_count=int(row["new_count"]),
                )
            )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="", encoding="utf-8") as stream:
        fields = [
            "similarity",
            "old_name",
            "old_count",
            "new_name",
            "new_count",
            "old_strings",
            "new_strings",
            "old_calls",
            "new_calls",
        ]
        writer = csv.DictWriter(stream, fieldnames=fields, delimiter="\t")
        writer.writeheader()
        for index, candidate in enumerate(candidates, 1):
            old_text = disassemble(
                args.ipsw, args.old, candidate.old_name, candidate.old_count
            )
            new_text = disassemble(
                args.ipsw, args.new, candidate.new_name, candidate.new_count
            )
            old_strings, old_calls = annotations(old_text)
            new_strings, new_calls = annotations(new_text)
            writer.writerow(
                {
                    **candidate.__dict__,
                    "old_strings": old_strings,
                    "new_strings": new_strings,
                    "old_calls": old_calls,
                    "new_calls": new_calls,
                }
            )
            if index % 50 == 0 or index == len(candidates):
                print(f"annotated={index}/{len(candidates)}", flush=True)


if __name__ == "__main__":
    main()
