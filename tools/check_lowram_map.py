#!/usr/bin/env python3
"""Validate GEOBENCH fixed low-RAM range ownership.

The kernel and paged modules share a number of absolute low-RAM cells. This
script checks `kernel/lowram.tsv` for accidental range overlaps in a selected
build profile. Deliberate overlays are allowed only when both ranges use the
same non-"-" overlay token.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MAP = ROOT / "kernel" / "lowram.tsv"
DEFAULT_PROFILE = "albireo"


@dataclass(frozen=True)
class Range:
    profiles: frozenset[str]
    start: int
    end: int
    name: str
    overlay: str
    notes: str
    line: int

    def active_in(self, profile: str) -> bool:
        return "base" in self.profiles or profile in self.profiles

    def overlaps(self, other: "Range") -> bool:
        return self.start <= other.end and other.start <= self.end

    def overlap_allowed(self, other: "Range") -> bool:
        return self.overlay != "-" and self.overlay == other.overlay


def parse_int(text: str) -> int:
    return int(text, 0)


def parse_map(path: Path) -> list[Range]:
    ranges: list[Range] = []
    for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(None, 5)
        if len(parts) < 5:
            raise SystemExit(f"{path}:{lineno}: expected at least 5 columns")
        profiles, start, end, name, overlay = parts[:5]
        notes = parts[5] if len(parts) == 6 else ""
        start_i = parse_int(start)
        end_i = parse_int(end)
        if end_i < start_i:
            raise SystemExit(f"{path}:{lineno}: end before start")
        ranges.append(
            Range(
                frozenset(profiles.split(",")),
                start_i,
                end_i,
                name,
                overlay,
                notes,
                lineno,
            )
        )
    return ranges


def available_profiles(ranges: list[Range]) -> list[str]:
    profiles = {DEFAULT_PROFILE}
    for item in ranges:
        profiles.update(item.profiles)
    profiles.discard("base")
    return sorted(profiles)


def check_profile(ranges: list[Range], profile: str, verbose: bool) -> int:
    active = [item for item in ranges if item.active_in(profile)]
    active.sort(key=lambda item: (item.start, item.end, item.name))

    errors: list[tuple[Range, Range]] = []
    allowed: list[tuple[Range, Range]] = []
    for i, left in enumerate(active):
        for right in active[i + 1 :]:
            if right.start > left.end:
                break
            if not left.overlaps(right):
                continue
            if left.overlap_allowed(right):
                allowed.append((left, right))
            else:
                errors.append((left, right))

    print(f"profile {profile}: {len(active)} ranges")
    if verbose:
        for item in active:
            print(
                f"  {item.start:04X}-{item.end:04X} "
                f"{item.name:<24} overlay={item.overlay:<12} {item.notes}"
            )
    if allowed:
        print(f"  allowed overlays: {len(allowed)}")
        if verbose:
            for left, right in allowed:
                print(
                    f"    {left.name} ({left.start:04X}-{left.end:04X}) "
                    f"<-> {right.name} ({right.start:04X}-{right.end:04X}) "
                    f"via {left.overlay}"
                )
    if errors:
        print(f"  unexpected overlaps: {len(errors)}", file=sys.stderr)
        for left, right in errors:
            start = max(left.start, right.start)
            end = min(left.end, right.end)
            print(
                f"    {start:04X}-{end:04X}: "
                f"{left.name} (line {left.line}, {left.start:04X}-{left.end:04X}) "
                f"overlaps {right.name} "
                f"(line {right.line}, {right.start:04X}-{right.end:04X})",
                file=sys.stderr,
            )
        return 1
    print("  ok")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--map",
        type=Path,
        default=DEFAULT_MAP,
        help="low-RAM map file",
    )
    parser.add_argument(
        "--profile",
        action="append",
        default=None,
        help=f"profile to check; may be repeated. default: {DEFAULT_PROFILE}",
    )
    parser.add_argument(
        "--list-profiles",
        action="store_true",
        help="print profiles present in the map",
    )
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args(argv)

    ranges = parse_map(args.map)
    if args.list_profiles:
        for profile in available_profiles(ranges):
            print(profile)
        return 0

    profiles = args.profile or [DEFAULT_PROFILE]
    valid = set(available_profiles(ranges))
    status = 0
    for profile in profiles:
        if profile not in valid:
            print(f"unknown profile: {profile}", file=sys.stderr)
            print(f"known profiles: {', '.join(sorted(valid))}", file=sys.stderr)
            status = 2
            continue
        status |= check_profile(ranges, profile, args.verbose)
    return status


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
