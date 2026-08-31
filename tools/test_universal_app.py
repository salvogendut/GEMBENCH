#!/usr/bin/env python3
"""Integration checks for the compile-once application SDK and source audit."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
sys.path.insert(0, str(TOOLS))

from embed_app_icon import parse_manifest  # noqa: E402


BUILDER = TOOLS / "build_uapp.sh"
AUDITOR = TOOLS / "check_universal_app.py"
PROBE = ROOT / "build" / "universal" / "ABIPROBE.APP"


def run(command: list[str], *, env: dict[str, str] | None = None,
        expect: int = 0) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        command,
        cwd=ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if result.returncode != expect:
        raise AssertionError(
            f"command returned {result.returncode}, expected {expect}: "
            f"{' '.join(command)}\n{result.stdout}"
        )
    return result


def check_sdcc_layout(temp: Path) -> None:
    authority = json.loads(
        (ROOT / "abi" / "geobench-v2.json").read_text(encoding="utf-8")
    )
    assertions = [
        "typedef char total_size[sizeof(gb_sysinfo_v6_t) == 48 ? 1 : -1];"
    ]
    for field in authority["sysinfo"]["fields"]:
        assertions.append(
            f"typedef char off_{field['name']}["
            f"offsetof(gb_sysinfo_v6_t, {field['name']}) == "
            f"{field['offset']} ? 1 : -1];"
        )
    source = temp / "layout.c"
    source.write_text("\n".join((
        "#include <stddef.h>",
        "#define GB_UNIVERSAL 1",
        '#include "gbuniversal.h"',
        *assertions,
        "void layout_probe(void) {}",
        "",
    )), encoding="ascii")
    sdcc = shutil.which(os.environ.get("SDCC", "sdcc"))
    if sdcc is None:
        raise AssertionError("universal SDK layout test requires sdcc")
    run([
        sdcc, "-mz80", "--std-c99", "-I", str(ROOT / "lib" / "gb"),
        "-c", str(source), "-o", str(temp / "layout.rel"),
    ])


def check_auditor(temp: Path) -> None:
    good = temp / "good.c"
    good.write_text("void main(void) {}\n", encoding="ascii")
    good_map = temp / "good.map"
    good_map.write_text(
        "Files Linked [ module(s) ]\n\n"
        "obj/crt0.rel [ crt0_v4 ]\n"
        "obj/main.rel [ main ]\n"
        "obj/gbuniversal.rel\n"
        "                  [ gbuniversal ]\n"
        "obj/gbuniversal_draw.rel [ gbuniversal_draw ]\n"
        "obj/gbsys.rel [ gbsys ]\n"
        "obj/gblib.rel [ gblib_subset ]\n",
        encoding="ascii",
    )
    run([sys.executable, str(AUDITOR), "--source", str(good),
         "--map", str(good_map)])

    bad_sources = {
        "target-define": "#define GB_MSX2 1\n",
        "target-include-path": '#include "msx/bios.h"\n',
        "target-include-file": '#include "cpc_crtc.h"\n',
        "inline-assembly": "void f(void) { __asm nop __endasm; }\n",
        "absolute-pointer": "char f(void) { return *((char *)0x1234); }\n",
        "direct-io": "__sfr __at (0x99) vdp_port;\n",
        "fixed-geometry": "unsigned char width = GB_COLS;\n",
        "legacy-native-api": "void f(void) { gb_pic_open(); }\n",
    }
    for label, text in bad_sources.items():
        path = temp / f"bad-{label}.c"
        path.write_text(text, encoding="ascii")
        result = run(
            [sys.executable, str(AUDITOR), "--source", str(path)],
            expect=1,
        )
        if "universal application audit failed" not in result.stdout:
            raise AssertionError(f"auditor did not explain {label}")

    bad_asm = temp / "bad.asm"
    bad_asm.write_text(
        "call 0x800c\nld a,(0x1234)\nout (#0x99),a\n", encoding="ascii"
    )
    run([sys.executable, str(AUDITOR), "--source", str(good),
         "--asm", str(bad_asm)], expect=1)

    bad_map = temp / "bad.map"
    bad_map.write_text(
        good_map.read_text(encoding="ascii") +
        "obj/msx-bios.rel [ msx_bios ]\n",
        encoding="ascii",
    )
    run([sys.executable, str(AUDITOR), "--source", str(good),
         "--map", str(bad_map)], expect=1)


def check_builder_rejections(temp: Path) -> None:
    target_env = dict(os.environ)
    target_env["APP_CFLAGS"] = "-DGB_MSX2"
    run(["bash", str(BUILDER), "apps/abiprobe", str(temp / "bad.APP")],
        env=target_env, expect=2)

    address_env = dict(os.environ)
    address_env["DATA_LOC"] = "not-an-address"
    run(["bash", str(BUILDER), "apps/abiprobe", str(temp / "bad2.APP")],
        env=address_env, expect=2)


def main() -> None:
    run(["bash", str(BUILDER), "apps/abiprobe", str(PROBE)])
    baseline = PROBE.read_bytes()
    baseline_manifest = parse_manifest(baseline)
    assert baseline[7] == 4
    assert baseline_manifest["application_id"] == "ABIPROBE"
    assert baseline_manifest["platforms"] == 0x07

    with tempfile.TemporaryDirectory(prefix="universal-sdk-test-") as dirname:
        temp = Path(dirname)
        rebuilt_path = temp / "ABIPROBE.APP"
        run(["bash", str(BUILDER), "apps/abiprobe", str(rebuilt_path)])
        assert rebuilt_path.read_bytes() == baseline, \
            "the universal application build is not deterministic"
        check_sdcc_layout(temp)
        check_auditor(temp)
        check_builder_rejections(temp)

    print(
        "Universal SDK build is deterministic; v6 layout and portability "
        "audits passed."
    )


if __name__ == "__main__":
    main()
