from __future__ import annotations

import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from cpc_graphics_fixture import (CURSOR, address, cases, emit_vectors,
                                  expected_frames, verify_graphics)
from test_cpc_foundation_1984 import symbols

RASM = shutil.which(os.environ.get("RASM", "rasm"))


class GraphicsOracleTests(unittest.TestCase):
    def test_screen_addresses_cover_only_display_bytes(self):
        addresses = {address(x * 4, y) for y in range(200) for x in range(80)}
        self.assertEqual(len(addresses), 16000)
        self.assertLess(max(addresses), 16384)
        self.assertEqual(address(0, 1), 2048)
        self.assertEqual(address(0, 8), 80)

    def test_clip_save_restore_and_pointer_checkpoints(self):
        frames, saved = expected_frames()
        by_name = dict(frames)
        self.assertEqual(len(frames), 24)
        self.assertEqual(len(saved), 56)
        self.assertGreater(len(set(saved)), 4, "save must test varied canonical bytes")
        self.assertEqual(by_name["save-clipped"], by_name["restore-clipped"])
        self.assertEqual(by_name["show-origin"], by_name["duplicate-show"])
        self.assertEqual(by_name["hide-updated"], by_name["duplicate-hide"])
        before, after = by_name["fill"], by_name["left-top-clip"]
        changed = {i for i, (a, b) in enumerate(zip(before, after)) if a != b}
        allowed = {address(x * 4, y) for y in range(15, 35) for x in range(10, 30)}
        self.assertTrue(changed)
        self.assertLessEqual(changed, allowed)


@unittest.skipUnless(RASM, "RASM required for CPC graphics assembly")
class GraphicsAssemblyTests(unittest.TestCase):
    @staticmethod
    def assemble(overrides=None):
        with tempfile.TemporaryDirectory(prefix="geobench-cpc-graphics-") as tmp:
            emit_vectors(Path(tmp) / "graphics_vectors.inc")
            command = [RASM, str(ROOT / "debug/cpc_foundation/graphics_probe.asm"),
                       "-s", "-sq", "-o", "foundation", f"-I{tmp}"]
            command += [f"-D{k}={v}" for k, v in (overrides or {}).items()]
            result = subprocess.run(command, cwd=tmp, capture_output=True, text=True)
            raw, table = Path(tmp) / "FOUND.RAW", Path(tmp) / "foundation.sym"
            return (result.stdout + result.stderr, raw.read_bytes() if raw.exists() else None,
                    symbols(table) if table.exists() else {})

    def test_all_fault_fixtures_fit_and_unsafe_map_rejected(self):
        for fault in (None, "FAULT_CLIP", "FAULT_CURSOR", "FAULT_COPY"):
            output, raw, sym = self.assemble({fault: 1} if fault else None)
            self.assertIsNotNone(raw, output)
            self.assertLess(sym["code_end"], sym["state_start"])
            self.assertLessEqual(sym["graphics_capture_count"], 27)
            self.assertLessEqual(sym["probe_end"], 0xA000)
        for override in ({"FOUNDATION_ORG": 0x4000}, {"FOUNDATION_STATE": 0xC000},
                         {"FOUNDATION_MAIN_STACK": 0x9D10}):
            output, raw, _ = self.assemble(override)
            self.assertIsNone(raw, output)

    def test_generated_cursor_phases_decode_to_pixels(self):
        output, raw, sym = self.assemble()
        self.assertIsNotNone(raw, output)
        offset = sym["cursor_phases"] - 0x8000
        for phase in range(4):
            for y in range(8):
                for x in range(12):
                    mask, ink = raw[offset + phase * 48 + y * 6 + (x // 4) * 2:
                                    offset + phase * 48 + y * 6 + (x // 4) * 2 + 2]
                    sub = x % 4
                    transparent = ((mask >> (7 - sub)) & 1, (mask >> (3 - sub)) & 1)
                    value = ((ink >> (7 - sub)) & 1) + 2 * ((ink >> (3 - sub)) & 1)
                    char = CURSOR[y][x - phase] if phase <= x < phase + 8 else "."
                    self.assertEqual(transparent, (1, 1) if char == "." else (0, 0))
                    self.assertEqual(value, 0 if char == "." else int(char))

    def test_checker_detects_mutations_not_just_completion_flag(self):
        # Synthetic fixture tests the checker; M4/1984 supplies execution evidence.
        output, raw, sym = self.assemble()
        self.assertIsNotNone(raw, output)
        header, ram = bytearray(256), bytearray(512 * 1024)
        header[0x40], header[0x25] = 0x0D, 1
        header[0x21:0x23] = sym["main_stack_top"].to_bytes(2, "little")
        ram[0x8000:0x8000 + len(raw)] = raw
        ram[sym["phase"]], ram[sym["rounds_done"]] = 0xA5, 50
        def word(name, value):
            ram[sym[name]:sym[name] + 2] = value.to_bytes(2, "little")
        word("request_count", len(cases()) * 50)
        word("irq_count", len(cases()) * 50)
        word("final_sp", sym["main_stack_top"])
        for stem, used in (("main", 16), ("irq", 4)):
            word(f"{stem}_stack_used", used)
            top = sym[f"{stem}_stack_top"]
            ram[top - used:top] = b"\x55" * used
        frames, saved = expected_frames()
        ram[sym["capture_count"]] = len(frames)
        for index, (name, frame) in enumerate(frames):
            ram[0x10000 + index * 16384:0x10000 + (index + 1) * 16384] = frame
            # Only selected trace relations are assertions; runtime records the actual counters.
            if name == "draw-under-pointer":
                start = sym["trace_records"] + index * 4
                ram[start:start + 4] = struct.pack("<HH", 1, 1)
        ram[0xC000:0x10000] = frames[-1][1]
        ram[0x7C000:0x80000] = b"\xA9" * 16384
        ram[0x4000:0x8000] = b"\x5A" * 16384
        ram[0x4000:0x4010] = cases()[-1]["record"]
        ram[0x7EF0:0x7F00] = cases()[-1]["record"]
        ram[0x4100:0x4100 + len(saved)] = saved
        self.assertEqual(verify_graphics(header, ram, sym, raw)["checkpoints"], 24)
        for cell, message in ((sym["request_guard_low"], "guard damaged"),
                              (0x10000 + 0x7FF, "framebuffer checkpoint initial"),
                              (0x7C010, "service page"), (0x4140, "caller page"),
                              (sym["request_count"], "request count"),
                              (sym["trace_records"] + 8 * 4, "unnecessary pointer")):
            with self.subTest(cell=cell):
                changed = bytearray(ram)
                changed[cell] ^= 1
                with self.assertRaisesRegex(AssertionError, message):
                    verify_graphics(header, changed, sym, raw)


if __name__ == "__main__":
    unittest.main()
