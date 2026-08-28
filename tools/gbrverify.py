#!/usr/bin/env python3
"""Validate canonical GEMBENCH GBR v1 binaries."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import gbrc


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="verify GEMBENCH GBR v1 binaries")
    parser.add_argument("resources", nargs="+", type=Path, help="input .gbr files")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    failed = False
    for path in args.resources:
        try:
            blob = path.read_bytes()
            header = gbrc.verify_blob(blob)
        except (OSError, gbrc.ResourceError) as exc:
            print(f"gbrverify: {path}: {exc}", file=sys.stderr)
            failed = True
            continue
        print(
            f"GBR1: {path}: {len(blob)} bytes, "
            f"{header['tree_count']} tree(s), {header['object_count']} object(s)"
        )
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
