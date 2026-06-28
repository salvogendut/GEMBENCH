#!/usr/bin/env python3
"""Validate the GEOBENCH kernel jump table against lib/gbapp.inc."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
KERNEL = ROOT / "kernel" / "gbkern.asm"
ABI_INC = ROOT / "lib" / "gbapp.inc"

KERNEL_SLOT_RE = re.compile(r";\s*(GB_[A-Z0-9_]+)\s+#([0-9A-Fa-f]{4})\b")
INC_BASE_RE = re.compile(r"^\s*GB_KERNEL\s+equ\s+#([0-9A-Fa-f]+)\b")
INC_EQU_RE = re.compile(r"^\s*(GB_[A-Z0-9_]+)\s+equ\s+GB_KERNEL\+([0-9]+)\b")


@dataclass(frozen=True)
class Slot:
    name: str
    address: int
    line: int


def parse_kernel_slots(path: Path) -> list[Slot]:
    slots: list[Slot] = []
    in_table = False
    for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not in_table:
            if re.search(r"\borg\s+GB_KERNEL\b", raw):
                in_table = True
            continue
        if raw.startswith("kernel_main"):
            break
        match = KERNEL_SLOT_RE.search(raw)
        if match:
            slots.append(Slot(match.group(1), int(match.group(2), 16), lineno))
    if not slots:
        raise SystemExit(f"{path}: no jump-table slots found")
    return slots


def parse_inc_equates(path: Path) -> tuple[int, dict[str, tuple[int, int]]]:
    base: int | None = None
    equates: dict[str, tuple[int, int]] = {}
    for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if match := INC_BASE_RE.match(raw):
            base = int(match.group(1), 16)
            continue
        if match := INC_EQU_RE.match(raw):
            if base is None:
                raise SystemExit(f"{path}:{lineno}: GB_KERNEL must be defined first")
            equates[match.group(1)] = (base + int(match.group(2)), lineno)
    if base is None:
        raise SystemExit(f"{path}: GB_KERNEL equate not found")
    return base, equates


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--kernel", type=Path, default=KERNEL)
    parser.add_argument("--abi", type=Path, default=ABI_INC)
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args(argv)

    slots = parse_kernel_slots(args.kernel)
    base, equates = parse_inc_equates(args.abi)
    errors: list[str] = []

    for index, slot in enumerate(slots):
        expected = base + index * 3
        if slot.address != expected:
            errors.append(
                f"{args.kernel}:{slot.line}: {slot.name} comment says "
                f"#{slot.address:04X}, expected #{expected:04X}"
            )
        if slot.name not in equates:
            errors.append(f"{args.abi}: missing {slot.name} for #{slot.address:04X}")
            continue
        inc_address, inc_line = equates[slot.name]
        if inc_address != slot.address:
            errors.append(
                f"{args.abi}:{inc_line}: {slot.name} is #{inc_address:04X}, "
                f"kernel table says #{slot.address:04X}"
            )

    slot_names = {slot.name for slot in slots}
    slot_start = slots[0].address
    slot_end = slots[-1].address
    for name, (address, line) in equates.items():
        if name == "GB_KERNEL":
            continue
        if slot_start <= address <= slot_end and name not in slot_names:
            errors.append(
                f"{args.abi}:{line}: {name} points inside the jump table "
                f"(#{address:04X}) but no kernel slot has that name"
            )

    if errors:
        print(f"checked {len(slots)} ABI slots", file=sys.stderr)
        for error in errors:
            print(f"  {error}", file=sys.stderr)
        return 1

    print(f"checked {len(slots)} ABI slots: ok")
    if args.verbose:
        for slot in slots:
            print(f"  {slot.address:04X} {slot.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
