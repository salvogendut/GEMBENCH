#!/usr/bin/env python3
"""Validate a linked app's 16K bank layout and optional task-stack reserve."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys


AREA_RE = re.compile(
    r"^(_CODE|_HOME|_DATA|_BSS|_INITIALIZED|_GSINIT|_GSFINAL|_INITIALIZER)"
    r"\s+([0-9A-Fa-f]{8})\s+([0-9A-Fa-f]{8})"
)
LOADED_AREAS = ("_CODE", "_GSINIT", "_GSFINAL", "_HOME", "_INITIALIZER")
APP_PAGE_END = 0x8000


def parse_number(value: str) -> int:
    return int(value, 0)


def read_areas(path: Path) -> dict[str, tuple[int, int]]:
    areas: dict[str, tuple[int, int]] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = AREA_RE.match(line)
        if match:
            areas[match.group(1)] = (
                int(match.group(2), 16),
                int(match.group(3), 16),
            )
    if not areas:
        raise ValueError("no linked areas found")
    return areas


def validate_layout(
    areas: dict[str, tuple[int, int]],
    data_loc: int,
    load_limit: int,
    task_stack_reserve: int,
) -> tuple[int, int, int, list[str]]:
    if not 0 <= task_stack_reserve <= 0x1000:
        return 0, 0, 0, ["task stack reserve must be between 0 and 4096 bytes"]
    loaded = [areas[name] for name in LOADED_AREAS if name in areas]
    if not loaded:
        return 0, 0, 0, ["no loaded image areas found"]
    image_end = max(start + size for start, size in loaded)
    top = max(start + size for start, size in areas.values())
    task_limit = APP_PAGE_END - task_stack_reserve
    errors: list[str] = []
    if image_end > data_loc:
        errors.append(
            f"loaded image ends 0x{image_end:04X} > data-loc 0x{data_loc:04X} "
            "(gsinit/data overlap)"
        )
    if image_end > load_limit:
        errors.append(
            f"loaded image ends 0x{image_end:04X} > app loader limit 0x{load_limit:04X}"
        )
    if top > APP_PAGE_END:
        errors.append(f"data/bss ends 0x{top:04X} > kernel 0x8000")
    if task_stack_reserve and top > task_limit:
        errors.append(
            f"data/bss ends 0x{top:04X} > task limit 0x{task_limit:04X} "
            f"({task_stack_reserve}-byte stack snapshot reserve)"
        )
    return image_end, top, task_limit, errors


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("map", type=Path)
    parser.add_argument("--app", default="app")
    parser.add_argument("--data-loc", type=parse_number, required=True)
    parser.add_argument("--load-limit", type=parse_number, default=0x7F00)
    parser.add_argument("--task-stack-reserve", type=parse_number, default=0)
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args(argv)
    try:
        areas = read_areas(args.map)
    except (OSError, ValueError) as exc:
        print(f"FIT ERROR ({args.app}): {exc}", file=sys.stderr)
        return 1
    image_end, top, task_limit, errors = validate_layout(
        areas, args.data_loc, args.load_limit, args.task_stack_reserve
    )
    if errors:
        print(
            f"FIT ERROR ({args.app}): {'; '.join(errors)} - shrink it or lower DATA_LOC",
            file=sys.stderr,
        )
        return 1
    if args.verbose:
        print(
            f"{args.app}: image_end=0x{image_end:04X} top=0x{top:04X} "
            f"task_limit=0x{task_limit:04X}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
