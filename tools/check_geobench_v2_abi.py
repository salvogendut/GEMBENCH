#!/usr/bin/env python3
"""Validate the proposed GEOBENCH-2 universal application ABI authority."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
AUTHORITY = ROOT / "abi" / "geobench-v2.json"
INHERITED = ROOT / "abi" / "gembench-v1.json"
GB_HEADER = ROOT / "lib" / "gb" / "gb.h"
GBAPP_INC = ROOT / "lib" / "gbapp.inc"
KERNEL_TABLE = ROOT / "kernel" / "api_table.inc"

SLOT_RE = re.compile(r";\s*(GB_[A-Z0-9_]+)\s+#([0-9A-Fa-f]{4})\b")
BASE_RE = re.compile(r"^\s*GB_KERNEL\s+equ\s+#([0-9A-Fa-f]+)\b", re.MULTILINE)
EQU_RE = re.compile(
    r"^\s*(GB_[A-Z0-9_]+)\s+equ\s+GB_KERNEL\+([0-9]+)\b", re.MULTILINE
)
DEFINE_RE = re.compile(
    r"^\s*#define\s+([A-Z][A-Z0-9_]+)\s+(0x[0-9A-Fa-f]+|[0-9]+)u?\b",
    re.MULTILINE,
)


V5_PREFIX = [
    ("size", 0, 1),
    ("version", 1, 1),
    ("abi_major", 2, 1),
    ("abi_minor", 3, 1),
    ("platform", 4, 1),
    ("video_mode", 5, 1),
    ("width_pixels", 6, 2),
    ("height_pixels", 8, 2),
    ("packing", 10, 1),
    ("colours", 11, 1),
    ("memory_pages", 12, 1),
    ("pool_pages", 13, 1),
    ("free_pages", 14, 1),
    ("max_windows", 15, 1),
    ("capabilities_low", 16, 2),
    ("reserved", 18, 2),
    ("max_applications", 20, 1),
    ("application_record_version", 21, 1),
    ("max_windows_per_application", 22, 1),
    ("reserved2", 23, 1),
    ("message_queue_capacity", 24, 1),
    ("message_inline_bytes", 25, 1),
    ("message_api_version", 26, 1),
    ("reserved3", 27, 1),
    ("filesystem_contexts", 28, 1),
    ("filesystem_transfer_bytes", 29, 2),
    ("filesystem_api_version", 31, 1),
]

C_PREFIX_NAMES = {
    "capabilities_low": "capabilities",
}

LOW_CAP_DEFINES = {
    "windows": "GB_CAP_WINDOWS",
    "events": "GB_CAP_EVENTS",
    "filesystem": "GB_CAP_FILESYSTEM",
    "shell": "GB_CAP_SHELL",
    "network": "GB_CAP_NETWORK",
    "gbr": "GB_CAP_GBR",
    "page-allocator": "GB_CAP_PAGE_ALLOC",
    "owner-identity": "GB_CAP_OWNER_ID",
    "runtime-video": "GB_CAP_RUNTIME_VIDEO",
    "applications": "GB_CAP_APPLICATIONS",
    "multi-window": "GB_CAP_MULTI_WINDOW",
    "deferred-messages": "GB_CAP_DEFERRED_MSG",
    "filesystem-contexts": "GB_CAP_FS_CONTEXTS",
    "secondary-code": "GB_CAP_SECONDARY_CODE",
    "service-manager": "GB_CAP_SERVICE_MANAGER",
}


def contiguous(fields: list[dict], size: int, label: str, errors: list[str]) -> None:
    cursor = 0
    names: set[str] = set()
    for field in fields:
        name = field["name"]
        if name in names:
            errors.append(f"{label}: duplicate field {name}")
        names.add(name)
        if field["offset"] != cursor:
            errors.append(
                f"{label}.{name}: offset {field['offset']} leaves a gap/overlap at {cursor}"
            )
        if field["size"] <= 0:
            errors.append(f"{label}.{name}: size must be positive")
        cursor = field["offset"] + field["size"]
    if cursor != size:
        errors.append(f"{label}: fields end at {cursor}, declared size is {size}")


def check_target_layout(authority: dict, errors: list[str]) -> None:
    sdcc_name = os.environ.get("SDCC", "sdcc")
    sdcc = shutil.which(sdcc_name)
    if sdcc is None:
        errors.append(f"target layout check requires {sdcc_name}")
        return
    fields = authority["sysinfo"]["fields"]
    assertions = ["typedef char v5_size[sizeof(gb_sysinfo_t) == 32 ? 1 : -1];"]
    for field in fields:
        if field["offset"] >= authority["sysinfo"]["legacy_prefix_size"]:
            break
        c_name = C_PREFIX_NAMES.get(field["name"], field["name"])
        assertions.append(
            f"typedef char off_{c_name}[offsetof(gb_sysinfo_t, {c_name}) == "
            f"{field['offset']} ? 1 : -1];"
        )
    source = "\n".join(
        ["#include <stddef.h>", "#define GB_MSX2 1", '#include "gb.h"', *assertions]
    )
    with tempfile.TemporaryDirectory(prefix="geobench-v2-abi-") as temp:
        source_path = Path(temp) / "layout.c"
        output_path = Path(temp) / "layout.rel"
        source_path.write_text(source + "\n", encoding="ascii")
        result = subprocess.run(
            [
                sdcc,
                "-mz80",
                "--std-c99",
                "-I",
                str(ROOT / "lib" / "gb"),
                "-c",
                str(source_path),
                "-o",
                str(output_path),
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        if result.returncode:
            errors.append("the implemented v5 sysinfo prefix changed:\n" + result.stdout)


def check_slots(authority: dict, errors: list[str]) -> None:
    execution = authority["execution"]
    slots = authority["jump_table"]["slots"]
    names: set[str] = set()
    for index, slot in enumerate(slots):
        expected = execution["kernel_table_base"] + index * execution["kernel_slot_bytes"]
        if slot["address"] != expected:
            errors.append(
                f"jump_table.{slot['name']}: address 0x{slot['address']:04X}, "
                f"expected 0x{expected:04X}"
            )
        if slot["name"] in names:
            errors.append(f"jump_table: duplicate slot {slot['name']}")
        names.add(slot["name"])
    if slots[-1]["address"] != execution["kernel_table_last_v1_slot"]:
        errors.append("execution.kernel_table_last_v1_slot does not match the slot list")

    table_slots = [
        (name, int(address, 16))
        for name, address in SLOT_RE.findall(KERNEL_TABLE.read_text(encoding="utf-8"))
    ]
    expected_slots = [(slot["name"], slot["address"]) for slot in slots]
    if table_slots != expected_slots:
        errors.append(
            f"{KERNEL_TABLE}: inherited slot order differs from GEOBENCH-2 authority"
        )

    inc = GBAPP_INC.read_text(encoding="utf-8")
    base_match = BASE_RE.search(inc)
    if not base_match:
        errors.append(f"{GBAPP_INC}: GB_KERNEL base missing")
        return
    base = int(base_match.group(1), 16)
    equates = {name: base + int(offset) for name, offset in EQU_RE.findall(inc)}
    for name, address in expected_slots:
        if equates.get(name) != address:
            errors.append(f"{GBAPP_INC}: {name} is not fixed at 0x{address:04X}")

    forbidden = authority["jump_table"]["universal_source_forbidden_slots"]
    unknown = sorted(set(forbidden) - names)
    if unknown:
        errors.append(f"jump_table: forbidden list names unknown slots: {unknown}")


def check_capabilities(authority: dict, errors: list[str]) -> None:
    capabilities = authority["capabilities"]
    all_values: list[int] = []
    for group_name, group in capabilities.items():
        for name, value in group.items():
            if value <= 0 or value & (value - 1):
                errors.append(f"capabilities.{group_name}.{name}: not a single bit")
            all_values.append(value)
    if len(all_values) != len(set(all_values)):
        errors.append("capabilities: bit assignments overlap")
    if any(value > 0xFFFF for value in capabilities["low_word_inherited"].values()):
        errors.append("capabilities.low_word_inherited contains a high-word bit")
    if any(value <= 0xFFFF for value in capabilities["high_word_v2"].values()):
        errors.append("capabilities.high_word_v2 contains a low-word bit")

    defines = {
        name: int(value, 0)
        for name, value in DEFINE_RE.findall(GB_HEADER.read_text(encoding="utf-8"))
    }
    for name, define in LOW_CAP_DEFINES.items():
        if defines.get(define) != capabilities["low_word_inherited"].get(name):
            errors.append(f"{GB_HEADER}: inherited capability {define} changed")


def main() -> int:
    authority = json.loads(AUTHORITY.read_text(encoding="utf-8"))
    inherited = json.loads(INHERITED.read_text(encoding="utf-8"))
    errors: list[str] = []

    if authority.get("abi") != "GEOBENCH-2" or authority.get("status") != "proposed":
        errors.append("authority must identify the proposed GEOBENCH-2 ABI")
    if inherited.get("abi") != authority["inherits"]["abi"]:
        errors.append("inherits.abi does not identify the frozen manifest")
    if inherited.get("status") != "frozen":
        errors.append("the inherited GEMBENCH-1 authority is no longer frozen")

    execution = authority["execution"]
    if (
        execution["application_base"] + execution["maximum_primary_image_bytes"]
        != execution["application_limit_exclusive"]
    ):
        errors.append("execution primary image does not end at the application limit")
    if execution["application_limit_exclusive"] > execution["kernel_table_base"]:
        errors.append("execution primary image overlaps the kernel table")

    platforms = authority["platforms"]
    ids = [platform["id"] for platform in platforms.values()]
    masks = [platform["package_mask"] for platform in platforms.values()]
    if len(ids) != len(set(ids)) or len(masks) != len(set(masks)):
        errors.append("platform IDs and package masks must be unique")
    if any(mask <= 0 or mask & (mask - 1) for mask in masks):
        errors.append("every platform package mask must be one bit")
    if sum(masks) != authority["package"]["required_platform_mask"]:
        errors.append("package.required_platform_mask is not the three-platform union")

    sysinfo = authority["sysinfo"]
    contiguous(sysinfo["fields"], sysinfo["record_size"], "sysinfo", errors)
    prefix = [
        (field["name"], field["offset"], field["size"])
        for field in sysinfo["fields"]
        if field["offset"] < sysinfo["legacy_prefix_size"]
    ]
    if prefix != V5_PREFIX:
        errors.append("sysinfo: the 32-byte v5 prefix is not preserved exactly")

    package = authority["package"]
    contiguous(
        package["base_header_fields"], package["base_header_size"], "GBAP header", errors
    )
    contiguous(
        package["manifest_fields"], package["manifest_size"], "GBM4 manifest", errors
    )
    contiguous(
        package["segment_fields"], package["segment_entry_size"], "GBM4 segment", errors
    )
    if len(package["abi_id"].encode("ascii")) != 8:
        errors.append("package.abi_id must be exactly eight ASCII bytes")
    if package["version"] != 4 or package["profile_value"] != 3:
        errors.append("package must reserve GBAP v4 profile 3 for universal-z80")
    if package["manifest_size"] > 255 or package["segment_entry_size"] > 255:
        errors.append("package record sizes do not fit their encoded one-byte fields")

    mailbox = authority["mailbox"]["regions"]
    occupied: set[int] = set()
    for region in mailbox:
        addresses = set(range(region["address"], region["address"] + region["size"]))
        if occupied & addresses:
            errors.append(f"mailbox.{region['name']}: overlaps another public region")
        occupied |= addresses
        if max(addresses) >= execution["application_base"]:
            errors.append(f"mailbox.{region['name']}: is not resident below the app page")

    check_slots(authority, errors)
    check_capabilities(authority, errors)
    check_target_layout(authority, errors)

    if errors:
        print("GEOBENCH-2 ABI design check failed:", file=sys.stderr)
        for error in errors:
            print(f"  {error}", file=sys.stderr)
        return 1
    print(
        f"GEOBENCH-2 ABI design: {len(authority['jump_table']['slots'])} inherited slots, "
        f"{sysinfo['record_size']}-byte sysinfo v{sysinfo['record_version']}, "
        f"GBAP v{package['version']}: ok"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
