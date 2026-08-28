#!/usr/bin/env python3
"""Check the frozen GEMBENCH-1 resource and managed-window ABI manifest."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "abi" / "gembench-v1.json"
GBR_HEADER = ROOT / "include" / "gembench" / "gbr.h"
GB_HEADER = ROOT / "lib" / "gb" / "gb.h"
LOWRAM_INC = ROOT / "kernel" / "lowram.inc"
GBAPP_INC = ROOT / "lib" / "gbapp.inc"
GBLIB = ROOT / "lib" / "gb" / "gblib.s"
GBWINDOW_KIND = ROOT / "lib" / "gb" / "gbwindow_kind.s"
GBLIB_BROWSER = ROOT / "lib" / "gb" / "gblib_browser.s"
KERNEL = ROOT / "kernel" / "gbkern.asm"

C_DEFINE_RE = re.compile(
    r"^\s*#define\s+([A-Z][A-Z0-9_]+)\s+(0x[0-9A-Fa-f]+|[0-9]+)u?\b",
    re.MULTILINE,
)
ASM_EQU_RE = re.compile(
    r"^\s*([A-Z][A-Z0-9_]+)\s+equ\s+(#[0-9A-Fa-f]+|[0-9]+)\b",
    re.MULTILINE,
)


def parse_c_constants(path: Path) -> dict[str, int]:
    return {
        name: int(value, 0)
        for name, value in C_DEFINE_RE.findall(path.read_text(encoding="utf-8"))
    }


def parse_asm_constants(path: Path) -> dict[str, int]:
    constants: dict[str, int] = {}
    for name, raw in ASM_EQU_RE.findall(path.read_text(encoding="utf-8")):
        constants[name] = int(raw[1:], 16) if raw.startswith("#") else int(raw)
    return constants


def compare_constants(
    expected: dict[str, int], actual: dict[str, int], source: Path, errors: list[str]
) -> None:
    for name, value in expected.items():
        if name not in actual:
            errors.append(f"{source}: missing frozen constant {name}")
        elif actual[name] != value:
            errors.append(
                f"{source}: {name} is {actual[name]}, frozen ABI requires {value}"
            )


def asm_function(text: str, label: str) -> str:
    match = re.search(
        rf"(?ms)^\s*{re.escape(label)}:\s*$\n(.*?)(?=^\s*_[A-Za-z0-9_]+:\s*$)",
        text,
    )
    if not match:
        raise ValueError(f"assembly label {label} not found")
    return match.group(1)


def check_registration(manifest: dict, errors: list[str]) -> None:
    slot = int(manifest["window"]["kernel_slot"])
    inc = GBAPP_INC.read_text(encoding="utf-8")
    base_match = re.search(r"^\s*GB_KERNEL\s+equ\s+#([0-9A-Fa-f]+)", inc, re.MULTILINE)
    managed_match = re.search(
        r"^\s*GB_WMMANAGED\s+equ\s+GB_KERNEL\+([0-9]+)", inc, re.MULTILINE
    )
    if not base_match or not managed_match:
        errors.append(f"{GBAPP_INC}: cannot resolve GB_WMMANAGED")
    else:
        actual_slot = int(base_match.group(1), 16) + int(managed_match.group(1))
        if actual_slot != slot:
            errors.append(
                f"{GBAPP_INC}: GB_WMMANAGED is 0x{actual_slot:04X}, "
                f"manifest requires 0x{slot:04X}"
            )

    gblib = GBLIB.read_text(encoding="utf-8")
    try:
        legacy = asm_function(gblib, "_gb_wm_managed")
    except ValueError as error:
        errors.append(f"{GBLIB}: {error}")
    else:
        if not re.search(r"^\s*xor\s+a\s*$", legacy, re.MULTILINE):
            errors.append(f"{GBLIB}: legacy registration must explicitly select A=0")
        if not re.search(r"^\s*jp\s+0x80B1\b", legacy, re.MULTILINE):
            errors.append(f"{GBLIB}: legacy registration no longer targets GB_WMMANAGED")
    kind_source = GBWINDOW_KIND.read_text(encoding="utf-8")
    try:
        kind = asm_function(kind_source + "\n_placeholder:\n", "_gb_wm_managed_kind")
    except ValueError as error:
        errors.append(f"{GBWINDOW_KIND}: {error}")
    else:
        selector = int(manifest["window"]["registration"]["kind_selector"])
        if not re.search(
            rf"^\s*ld\s+a,\s*#0x{selector:02X}\b", kind, re.MULTILINE | re.IGNORECASE
        ):
            errors.append(
                f"{GBWINDOW_KIND}: kind registration must explicitly select A=0x{selector:02X}"
            )
        if not re.search(r"^\s*jp\s+0x80B1\b", kind, re.MULTILINE):
            errors.append(
                f"{GBWINDOW_KIND}: kind registration no longer targets GB_WMMANAGED"
            )

    browser = GBLIB_BROWSER.read_text(encoding="utf-8")
    try:
        browser_legacy = asm_function(browser, "_gb_wm_managed")
    except ValueError as error:
        errors.append(f"{GBLIB_BROWSER}: {error}")
    else:
        if not re.search(r"^\s*xor\s+a\s*$", browser_legacy, re.MULTILINE):
            errors.append(f"{GBLIB_BROWSER}: legacy registration must select A=0")

    kernel = KERNEL.read_text(encoding="utf-8")
    kind_load = re.search(r"(?ms)^mw_kind_load\s*$\n(.*?)^mw_kind\s+db\b", kernel)
    managed = re.search(r"(?ms)^k_wm_managed\s*$\n(.*?)^; mw_publish:", kernel)
    if not kind_load:
        errors.append(f"{KERNEL}: mw_kind_load block not found")
    else:
        block = kind_load.group(1)
        if not re.search(r"\bbit\s+4,\(hl\)", block):
            errors.append(f"{KERNEL}: kind load must require the per-window v1 flag")
        if not re.search(r"\bld\s+de,12\b", block):
            errors.append(f"{KERNEL}: kind byte must remain at descriptor offset 12")
        if re.search(r"\bld\s+de,13\b", block):
            errors.append(f"{KERNEL}: legacy-unsafe descriptor offset 13 probe returned")
    if not managed:
        errors.append(f"{KERNEL}: k_wm_managed block not found")
    else:
        block = managed.group(1)
        if "cp    GB_WK_ABI_V1" not in block or not re.search(r"\bset\s+4,\(hl\)", block):
            errors.append(f"{KERNEL}: explicit kind selector is not persisted per window")


def check_target_layout(manifest: dict, errors: list[str]) -> None:
    sdcc_name = os.environ.get("SDCC", "sdcc")
    sdcc = shutil.which(sdcc_name)
    if sdcc is None:
        errors.append(f"target layout check requires {sdcc_name}")
        return
    layout = manifest["window"]["layout"]
    source = f"""
#include <stddef.h>
#define GB_MSX2 1
#include "gb.h"
typedef char abi_legacy_size[
    sizeof(gb_mwin_t) == {layout['legacy_descriptor_size']} ? 1 : -1];
typedef char abi_kind_offset[
    offsetof(gb_mwin_kind_t, kind) == {layout['kind_offset']} ? 1 : -1];
typedef char abi_kind_size[
    sizeof(gb_mwin_kind_t) == {layout['kind_descriptor_size']} ? 1 : -1];
"""
    with tempfile.TemporaryDirectory(prefix="gembench-abi-") as temp:
        source_path = Path(temp) / "layout.c"
        output_path = Path(temp) / "layout.rel"
        source_path.write_text(source, encoding="ascii")
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
            errors.append("target window layout differs from manifest:\n" + result.stdout)


def check_manifest_invariants(manifest: dict, errors: list[str]) -> None:
    if manifest.get("abi") != "GEMBENCH-1" or manifest.get("status") != "frozen":
        errors.append("manifest must identify the frozen GEMBENCH-1 ABI")
    resource = manifest["resource"]
    all_types = {
        name
        for name in resource["binary_constants"]
        if name.startswith("GBR_TYPE_")
    }
    rendered = set(resource["rendered_types"])
    format_only = set(resource["format_only_types"])
    if rendered & format_only:
        errors.append("rendered_types and format_only_types overlap")
    if rendered | format_only != all_types:
        errors.append("every frozen GBR object type must have one runtime classification")

    for group_name in ("GBR_FLAG_", "GBR_STATE_"):
        values = [
            value
            for name, value in resource["binary_constants"].items()
            if name.startswith(group_name) and not name.endswith("_MASK")
        ]
        if any(value == 0 or value & (value - 1) for value in values):
            errors.append(f"{group_name} values must remain single-bit masks")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    args = parser.parse_args(argv)
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    errors: list[str] = []

    check_manifest_invariants(manifest, errors)
    gbr_constants = parse_c_constants(GBR_HEADER)
    compare_constants(
        manifest["resource"]["binary_constants"], gbr_constants, GBR_HEADER, errors
    )
    compare_constants(
        manifest["resource"]["reader_results"], gbr_constants, GBR_HEADER, errors
    )
    compare_constants(
        manifest["resource"]["runtime_constants"], gbr_constants, GBR_HEADER, errors
    )
    compare_constants(
        manifest["window"]["c_constants"], parse_c_constants(GB_HEADER), GB_HEADER, errors
    )
    compare_constants(
        manifest["window"]["assembly_constants"],
        parse_asm_constants(LOWRAM_INC),
        LOWRAM_INC,
        errors,
    )
    check_registration(manifest, errors)
    check_target_layout(manifest, errors)

    if errors:
        print("GEMBENCH-1 ABI check failed:", file=sys.stderr)
        for error in errors:
            print(f"  {error}", file=sys.stderr)
        return 1
    resource_count = (
        len(manifest["resource"]["binary_constants"])
        + len(manifest["resource"]["reader_results"])
        + len(manifest["resource"]["runtime_constants"])
    )
    window_count = len(manifest["window"]["c_constants"])
    print(
        f"GEMBENCH-1 ABI: {resource_count} resource constants, "
        f"{window_count} window constants, target layouts and selectors: ok"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
