#!/usr/bin/env python3
"""Static conformance checks for the MSX2 Gate-2 GBAP v4 runtime."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from embed_app_icon import parse_manifest  # noqa: E402


def equ(text: str, name: str) -> int:
    match = re.search(rf"^{re.escape(name)}\s+equ\s+#([0-9A-Fa-f]+)",
                      text, re.MULTILINE)
    if not match:
        raise AssertionError(f"missing hexadecimal constant {name}")
    return int(match.group(1), 16)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--gate", type=Path,
                        default=ROOT / "build/msx/GBAPV4.RAW")
    parser.add_argument("--app", type=Path,
                        default=ROOT / "build/universal/ABIPROBE.APP")
    parser.add_argument("--staged", type=Path)
    args = parser.parse_args()

    glue = (ROOT / "lib/msx/glue.inc").read_text(encoding="utf-8")
    kernel = (ROOT / "kernel/gbkern.asm").read_text(encoding="utf-8")
    pool = (ROOT / "kernel/msx_page_pool.asm").read_text(encoding="utf-8")
    pool += (ROOT / "kernel/msx_capabilities.inc").read_text(encoding="utf-8")
    abi = json.loads((ROOT / "abi/geobench-v2.json").read_text())

    gate_base = equ(glue, "MSX_GBAP4_GATE")
    gate_limit = equ(glue, "MSX_GBAP4_GATE_LIMIT")
    gate_size_match = re.search(r"^MSX_GBAP4_GATE_SIZE\s+equ\s+([0-9]+)",
                                glue, re.MULTILINE)
    if not gate_size_match:
        raise AssertionError("missing decimal constant MSX_GBAP4_GATE_SIZE")
    gate_size = int(gate_size_match.group(1))
    sysinfo = equ(glue, "MSX_SYSINFO")
    app_bottom = equ(glue, "MSX_APP_FIXED_BOTTOM")
    if (sysinfo, gate_base, gate_limit, app_bottom) != (
            0xCF00, 0x0400, 0x1000, 0xD400):
        raise AssertionError("unexpected v6/gate fixed-memory layout")
    if abi["sysinfo"]["record_version"] != 6 \
            or abi["sysinfo"]["record_size"] != 48:
        raise AssertionError("ABI source does not describe GB_SYSINFO v6/48")
    if "GB_CAPS_HIGH_MSX_V6" not in pool or "GB_SYSINFO_V6" not in pool:
        raise AssertionError("MSX kernel does not publish the Gate-2 sysinfo suffix")

    gate = args.gate.read_bytes()
    if len(gate) != gate_size or len(gate) > gate_limit - gate_base:
        raise AssertionError("GBAPV4.MOD does not fit its reserved low-TPA region")
    if gate[0] != 0xC3 or gate[3:8] != b"GBV4\x02":
        raise AssertionError("GBAPV4.MOD boot signature is invalid")
    entry = struct.unpack_from("<H", gate, 1)[0]
    if not gate_base + 8 <= entry < gate_base + len(gate):
        raise AssertionError("GBAPV4.MOD entry is outside the module")

    validate = kernel.index("call  MSX_GBAP4_GATE")
    rollback = kernel.index("jr    nc,wmo_fail", validate)
    enter = kernel.index("call  APP_BASE", rollback)
    if not validate < rollback < enter:
        raise AssertionError("GBAP v4 gate is not ordered before app entry/rollback")

    package = args.app.read_bytes()
    manifest = parse_manifest(package)
    required = manifest["required_capabilities"]
    if manifest["version"] != 4 or manifest["profile"] != 3:
        raise AssertionError("ABIPROBE is not a universal GBAP v4 package")
    if required & 0x000F0000 != 0x000F0000:
        raise AssertionError("ABIPROBE does not require the four proved high capabilities")
    if manifest["minimum_sysinfo"] != (6, 48):
        raise AssertionError("ABIPROBE does not require the complete v6 suffix")
    if manifest["minimum_abi"] != (2, 1) or not required & 0x00800000:
        raise AssertionError("ABIPROBE must require the caller-parameter service")
    if len(manifest["segments"]) != 1 or manifest["image_size"] != len(package):
        raise AssertionError("Gate-2 ABIPROBE must be one primary-only transaction")

    if args.staged is not None and args.staged.read_bytes() != package:
        raise AssertionError("staged ABIPROBE.APP differs from the SDK output")

    print(
        f"MSX2 Gate 2: sysinfo v6/48, {len(gate)}-byte validator, "
        f"{len(package)}-byte ABIPROBE.APP: ok"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
