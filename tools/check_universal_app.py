#!/usr/bin/env python3
"""Reject target-specific dependencies from a GEOBENCH-2 application build."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys


TARGET_TOKENS = (
    "GB_MSX2", "GB_PCW", "PLATFORM_MSX", "PLATFORM_CPC", "PLATFORM_PCW",
)
TARGET_INCLUDES = re.compile(
    r"#\s*include\s*[<\"](?:[^>\"\r\n]*[/\\])?(?:msx|cpc|pcw)"
    r"(?:[/\\._-]|[>\"])", re.IGNORECASE
)
INLINE_ASM = re.compile(r"\b(?:__asm|__endasm)\b|^\s*#\s*asm\b", re.MULTILINE)
DIRECT_POINTER = re.compile(
    r"\(\s*(?:volatile\s+)?(?:unsigned\s+|signed\s+)?"
    r"(?:char|short|int|long|void)\s*\*\s*\)\s*0x[0-9A-Fa-f]+"
)
DIRECT_IO = re.compile(r"\b(?:__sfr|__sbit)\b|\b(?:__at|inp|outp)\s*\(")
COMPILED_EXTENTS = re.compile(r"\b(?:GB_COLS|GB_LINES|GB_XPIX)\b")
FORBIDDEN_APIS = re.compile(
    r"\b(?:gb_pic_open|gb_pic_edit|gb_pic_blit|gb_pic_close|gb_exit)\s*\("
)
ASM_DIRECT_BRANCH = re.compile(
    r"^\s*(?:call|jp)\s+(?:#\s*)?0x[0-9A-Fa-f]+\b", re.MULTILINE
)
ASM_DIRECT_MEMORY = re.compile(
    r"\(\s*(?:#\s*)?0x[0-9A-Fa-f]{3,4}\s*\)", re.MULTILINE
)
ASM_IO = re.compile(r"^\s*(?:in|out)\s+", re.MULTILINE | re.IGNORECASE)
MAP_FILE_RE = re.compile(
    r"^(.+?\.rel)(?:[ \t]*\n[ \t]*)?[ \t]+\[\s*([^\]]+)\s*\][ \t]*$",
    re.MULTILINE,
)
FORBIDDEN_MODULE = re.compile(
    r"(?:^|[_-])(?:msx|cpc|pcw|unapi|bios|firmware|native)(?:$|[_-])",
    re.IGNORECASE,
)
REQUIRED_MODULES = {"crt0_v4", "gbuniversal", "gbsys", "gblib_subset", "main"}


def source_files(paths: list[Path]) -> list[Path]:
    files: list[Path] = []
    for path in paths:
        if path.is_dir():
            files.extend(
                item for item in sorted(path.rglob("*"))
                if item.is_file() and item.suffix.lower() in {".c", ".h", ".s", ".asm"}
            )
        else:
            files.append(path)
    return files


def line_for(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def add_match(path: Path, text: str, match: re.Match[str], reason: str,
              errors: list[str]) -> None:
    errors.append(f"{path}:{line_for(text, match.start())}: {reason}: {match.group(0)!r}")


def check_source(path: Path, errors: list[str]) -> None:
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        errors.append(f"{path}: source is not UTF-8 text")
        return
    for token in TARGET_TOKENS:
        for match in re.finditer(rf"\b{re.escape(token)}\b", text):
            add_match(path, text, match, "target build token", errors)
    for pattern, reason in (
        (TARGET_INCLUDES, "target backend include"),
        (INLINE_ASM, "inline assembly"),
        (DIRECT_POINTER, "direct absolute pointer"),
        (DIRECT_IO, "direct I/O/compiler address primitive"),
        (COMPILED_EXTENTS, "compile-time screen extent"),
        (FORBIDDEN_APIS, "legacy target-specific kernel API"),
    ):
        for match in pattern.finditer(text):
            add_match(path, text, match, reason, errors)


def check_generated_asm(path: Path, errors: list[str]) -> None:
    text = path.read_text(encoding="utf-8", errors="replace")
    for pattern, reason in (
        (ASM_DIRECT_BRANCH, "direct absolute branch in application object"),
        (ASM_DIRECT_MEMORY, "direct absolute memory operand in application object"),
        (ASM_IO, "direct Z80 I/O instruction in application object"),
    ):
        for match in pattern.finditer(text):
            add_match(path, text, match, reason, errors)


def check_map(path: Path, errors: list[str]) -> None:
    modules: set[str] = set()
    text = path.read_text(encoding="utf-8", errors="replace")
    for match in MAP_FILE_RE.finditer(text):
        module = match.group(2).strip()
        modules.add(module)
        if FORBIDDEN_MODULE.search(module):
            errors.append(f"{path}: target-specific linked module {module!r}")
    missing = sorted(REQUIRED_MODULES - modules)
    if missing:
        errors.append(f"{path}: missing universal SDK modules: {', '.join(missing)}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, action="append", default=[])
    parser.add_argument("--asm", type=Path, action="append", default=[])
    parser.add_argument("--map", dest="map_path", type=Path)
    args = parser.parse_args(argv)
    if not args.source:
        parser.error("at least one --source path is required")

    errors: list[str] = []
    for path in source_files(args.source):
        if not path.exists():
            errors.append(f"{path}: source path does not exist")
        else:
            check_source(path, errors)
    for path in args.asm:
        if not path.exists():
            errors.append(f"{path}: generated assembly does not exist")
        else:
            check_generated_asm(path, errors)
    if args.map_path:
        if not args.map_path.exists():
            errors.append(f"{args.map_path}: linker map does not exist")
        else:
            check_map(args.map_path, errors)

    if errors:
        print("universal application audit failed:", file=sys.stderr)
        for error in errors:
            print(f"  {error}", file=sys.stderr)
        return 1
    print(
        f"universal application audit: {len(source_files(args.source))} source file(s), "
        f"{len(args.asm)} generated object(s): ok"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
