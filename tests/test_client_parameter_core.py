from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CC = shutil.which(os.environ.get("CC", "cc"))
RASM = shutil.which(os.environ.get("RASM", "rasm"))
SDAS = shutil.which(os.environ.get("SDAS", "sdasz80"))


class ClientParameterBoundaryTests(unittest.TestCase):
    def test_shared_policy_and_provider_selection(self):
        client = (ROOT / "lib/gembench/core/fsctx_client.inc").read_text()
        self.assertNotRegex(client, r"0x[0-9A-Fa-f]{4}|\bMSX_\w+")
        selection = (ROOT / "include/gembench/gbfsctx_platform.h").read_text()
        self.assertIn("#include GB_FSCTX_PLATFORM_HEADER", selection)
        self.assertIn("#ifdef GB_MSX2", selection)
        self.assertIn('#error "Select an explicit', selection)
        header = (ROOT / "include/gembench/gbfsctx.h").read_text()
        self.assertIn("((const gb_fsctx_entry_t *)GB_FSCTX_TRANSFER)", header)
        for path in ("kernel/core/parameters.asm", "lib/gembench/core/timer_publish.inc"):
            code = "\n".join(line.split(";", 1)[0] for line in (ROOT / path).read_text().splitlines())
            self.assertNotRegex(code, r"\b(?:MSX_\w+|SCHED_\w+|BANK_CUR|GLINE_\w+|GB_OWNER|GB_APP|GB_TEXT|GB_LINE)\b")
            self.assertNotRegex(code.lower(), r"\b(?:di|ei|in|out|halt)\b")

    def test_single_includes_and_incremental_dependencies(self):
        for wrapper, include in (("lib/gembench/gbfsctx.c", '"core/fsctx_client.inc"'),
                                 ("lib/gembench/gbtimer_damage.s", '"core/timer_publish.inc"'),
                                 ("kernel/msx_universal_parameters.asm", '"core/parameters.asm"')):
            self.assertEqual((ROOT / wrapper).read_text().count(include), 1)
        builder = (ROOT / "tools/build_capp.sh").read_text()
        deps = builder[builder.index('deps+='):builder.index('stamp="$OUT.stamp"')]
        for name in ("gbfsctx_platform.h", "gbfsctx_contract.h", "msx/gbfsctx_client.h",
                     "core/fsctx_client.inc", "msx_timer_publish.inc", "core/timer_publish.inc",
                     "core/timer_publish_contract.inc"):
            self.assertIn(name, deps)
        self.assertIn('"$SDAS" -I"$GBR_LIB" -o "$work/gbtimer_damage.rel"', builder)

    def test_bindings_agree_with_frozen_abi_and_state(self):
        abi = json.loads((ROOT / "abi/geobench-v2.json").read_text())
        self.assertEqual(abi["version"], [2, 1])
        slots = {slot["name"]: slot["address"] for slot in abi["jump_table"]["slots"]}
        self.assertEqual(slots["GB_FSCTX"], 0x80D2)
        self.assertEqual(slots["GB_PARAMS"], 0x80D5)
        # The already portable SDK bridge is intentionally not platform-selected.
        bridge = (ROOT / "lib/gb/gbuniversal_draw.s").read_text()
        self.assertIn("call 0x80D5", bridge)
        self.assertNotIn("PLATFORM", bridge)
        glue = (ROOT / "lib/msx/glue.inc").read_text()
        for path, pairs in (
            ("include/gembench/msx/gbfsctx_client.h", (("GB_FSCTX_REQUEST_ADDRESS", "MSX_FSCTX_REQ"),
                ("GB_FSCTX_TRANSFER_ADDRESS", "MSX_FSCTX_TRANSFER"))),
            ("lib/gembench/msx_timer_publish.inc", (("CORE_TIMER_OWNER", "MSX_TIMER_OWNER"),
                ("CORE_TIMER_RECT", "MSX_TIMER_RECT"), ("CORE_TIMER_GEN", "MSX_TIMER_GEN"),
                ("CORE_TIMER_WIN_GEN", "MSX_WIN_GEN")))):
            source = (ROOT / path).read_text()
            for shared, native in pairs:
                actual = int(re.search(rf"{shared}\s+(?:=\s*)?0x([0-9A-F]+)", source)[1], 16)
                expected = int(re.search(rf"^{native}\s+equ\s+#([0-9A-F]+)", glue, re.M)[1], 16)
                self.assertEqual(actual, expected, shared)


@unittest.skipUnless(CC, "host C compiler required for actual filesystem client tests")
class FilesystemClientExecutionTests(unittest.TestCase):
    def compile(self, base, extra=(), execute=True):
        with tempfile.TemporaryDirectory(prefix="geobench-fsclient-") as tmp:
            binary = Path(tmp) / "test"
            cmd = [CC, "-std=c99", "-Wall", "-Wextra", "-Werror", f"-DFIXTURE_BASE={base}", *extra,
                   "-I", str(ROOT / "lib/gb"), "-I", str(ROOT / "include/gembench"),
                   "-I", str(ROOT / "tests/fixtures"), str(ROOT / "tests/test_fsctx_client.c"),
                   "-o", str(binary)]
            result = subprocess.run(cmd, text=True, capture_output=True)
            if execute:
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                result = subprocess.run([str(binary)], text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("filesystem client: PASS", result.stdout)
            return result

    def test_actual_full_directory_batch_profiles_at_low_and_high_addresses(self):
        for base in ("0x2000", "0xD800"):
            for flags in ((), ("-DGB_FSCTX_DIRECTORY_ONLY",), ("-DGB_FSCTX_BATCH_ONLY",),
                          ("-DGB_FSCTX_DIRECTORY_ONLY", "-DGB_FSCTX_BATCH_ONLY")):
                self.compile(base, flags)

    def test_fixed_spans_and_overlap_are_rejected(self):
        for base in ("-1", "0x3FF0", "0x4000", "0xFF00"):
            result = self.compile(base, execute=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("must remain fixed", result.stderr)
        result = self.compile("0x2000", ("-DGB_FSCTX_TRANSFER_ADDRESS=0x2010",), execute=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("overlaps transfer", result.stderr)


@unittest.skipUnless(SDAS, "SDAS required for native timer provider fixtures")
class TimerPublisherAssemblyTests(unittest.TestCase):
    def assemble(self, base=0x2000, overrides=None):
        values = dict(CORE_TIMER_OWNER=base, CORE_TIMER_RECT=base+1, CORE_TIMER_GEN=base+5,
                      CORE_TIMER_FULLSCREEN=base+6, CORE_TIMER_CURRENT=base+7,
                      CORE_TIMER_WIN_GEN=base+8, CORE_TIMER_WINDOW_MAX=8)
        values.update(overrides or {})
        source = [".module gbtimer_damage", ".globl _gb_timer_damage",
                  *[f"{key} = {value}" for key, value in values.items()],
                  '.include "core/timer_publish_contract.inc"', '.area _CODE',
                  '.include "core/timer_publish.inc"']
        with tempfile.TemporaryDirectory(prefix="geobench-timer-publisher-") as tmp:
            asm, rel = Path(tmp) / "timer.s", Path(tmp) / "timer.rel"
            asm.write_text("\n".join(source) + "\n")
            result = subprocess.run([SDAS, f"-I{ROOT}/lib/gembench", "-o", str(rel), str(asm)],
                                    text=True, capture_output=True)
            return result, rel.read_text() if rel.exists() else ""

    def test_independent_fixed_state_keeps_75_byte_publisher(self):
        low, high = self.assemble(), self.assemble(0xD800)
        for result, obj in (low, high):
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("A _CODE size 4B", obj)
        self.assertNotEqual(low[1], high[1])
        self.assertEqual(low[1], self.assemble()[1])

    def test_span_index_page_and_active_bit_guards(self):
        for name, size in (("CORE_TIMER_OWNER", 1), ("CORE_TIMER_RECT", 4), ("CORE_TIMER_GEN", 1),
                           ("CORE_TIMER_FULLSCREEN", 1), ("CORE_TIMER_CURRENT", 1), ("CORE_TIMER_WIN_GEN", 8)):
            for address in (-1, 0x4000, 0x10000-size+1):
                result, _ = self.assemble(overrides={name: address})
                self.assertNotEqual(result.returncode, 0, (name, address))
        for name, value in (("CORE_TIMER_RECT", 0x3FFE), ("CORE_TIMER_WIN_GEN", 0x20FC),
                            ("CORE_TIMER_WINDOW_MAX", 0), ("CORE_TIMER_WINDOW_MAX", 128)):
            result, _ = self.assemble(overrides={name: value})
            self.assertNotEqual(result.returncode, 0, (name, value))


@unittest.skipUnless(RASM, "RASM required for parameter provider fixtures")
class ParameterAssemblyTests(unittest.TestCase):
    def assemble(self, base=0x2000, columns=128, height=212, overrides=None, origin=0x8000):
        values = dict(CORE_PARAM_APP_NATIVE=base, CORE_PARAM_OWNER_MAX=8,
                      CORE_PARAM_MAPPED_NATIVE=base+8, CORE_PARAM_CURRENT=base+9,
                      CORE_PARAM_LOCK=base+10, CORE_PARAM_TIMER_OWNER=base+11,
                      CORE_PARAM_TIMER_RECT=base+12, CORE_PARAM_TIMER_GEN=base+16,
                      CORE_PARAM_DROPPED=base+17, CORE_PARAM_DROPPED_GEN=base+18,
                      CORE_PARAM_COLUMNS=columns, CORE_PARAM_WIDTH=columns*4, CORE_PARAM_HEIGHT=height,
                      PARAM_CURRENT_OWNER=0xF000, PARAM_WINDOW_CALL=0xF003, PARAM_DRAW_TEXT=0xF006)
        values.update(overrides or {})
        source = [*[f"{key} equ {value}" for key, value in values.items()],
                  # Independent provider, no MSX include; same Z80 critical-section promises.
                  "macro PARAM_ENTER", "push ix", "ld a,i", "push af", "di",
                  "ld a,(CORE_PARAM_LOCK)", "push af", "ld a,1", "ld (CORE_PARAM_LOCK),a", "mend",
                  "macro PARAM_LEAVE", "ld d,a", "di", "pop af", "ld (CORE_PARAM_LOCK),a",
                  "pop af", "ld a,d", "pop ix", "jp po,up_return", "ei", "mend",
                  "macro PARAM_DRAW_LINE", "call #F009", "mend", f"org {origin}",
                  f'include "{ROOT}/kernel/core/parameters.asm"',
                  f'include "{ROOT}/kernel/core/parameter_contract.inc"',
                  f'save "parameters.bin",{origin},$-{origin}']
        with tempfile.TemporaryDirectory(prefix="geobench-parameters-core-") as tmp:
            asm = Path(tmp) / "parameters.asm"
            asm.write_text("\n".join(source) + "\n")
            result = subprocess.run([RASM, str(asm), "-s", "-sq", "-o", "parameters"],
                                    cwd=tmp, text=True, capture_output=True)
            binary = Path(tmp) / "parameters.bin"
            return result, binary.read_bytes() if binary.exists() else None

    def test_independent_state_and_common_profile_geometries(self):
        variants = [self.assemble(base, columns, height)
                    for base in (0x2000, 0xD800) for columns, height in ((128, 212), (80, 200), (90, 248))]
        for result, binary in variants:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIsNotNone(binary)
        self.assertEqual(len({len(v[1]) for v in variants}), 1)
        self.assertEqual(len({v[1] for v in variants}), 6)
        self.assertEqual(variants[0][1], self.assemble()[1])

    def test_invalid_state_geometry_and_code_placement_fail(self):
        for name, values in (("CORE_PARAM_APP_NATIVE", (-1, 0x4000, 0xFFFF, 0x20FC)),
                             ("CORE_PARAM_TIMER_RECT", (0x3FFE, 0xFFFE)),
                             ("CORE_PARAM_LOCK", (0x4000, 0x10000)),
                             ("CORE_PARAM_OWNER_MAX", (0, 128)),
                             ("CORE_PARAM_COLUMNS", (0, 255)),
                             ("CORE_PARAM_WIDTH", (0, 320)),
                             ("CORE_PARAM_HEIGHT", (0, 255))):
            for value in values:
                result, binary = self.assemble(overrides={name: value})
                self.assertIsNone(binary, (name, value))
                self.assertIn("ASSERT", (result.stdout + result.stderr).upper())
        for origin in (0x3F00, 0x4000, 0x7F00, 0xFF00):
            result, binary = self.assemble(origin=origin)
            self.assertIsNone(binary, origin)
            # RASM rejects 64-KiB output overflow before reaching assertions.
            self.assertRegex((result.stdout + result.stderr).upper(),
                             r"ASSERT|OUTPUT EXCEED LIMIT")


if __name__ == "__main__":
    unittest.main()
