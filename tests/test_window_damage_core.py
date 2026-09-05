from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
RASM = shutil.which(os.environ.get("RASM", "rasm"))
UNITS = ("window_geometry.asm", "window_focus_damage.asm",
         "window_repaint.asm", "window_damage.asm")
FIELDS = (("CORE_Z_ORDER", 8), ("CORE_LIVE_WINDOWS", 1),
          ("CORE_FOCUS_SLOT", 1), ("CORE_FOCUS_TARGET", 1), ("CORE_FOCUS_OLD", 1),
          ("CORE_MOVE_X", 1), ("CORE_MOVE_Y", 1), ("CORE_SIZE_W", 1),
          ("CORE_SIZE_H", 1), ("CORE_REPAINT_INDEX", 1), ("CORE_REPAINT_BANK", 1),
          ("CORE_MAPPED_NATIVE", 1), ("CORE_CLIP_X", 4), ("CORE_DAMAGE_EXTRA", 4),
          ("CORE_DAMAGE_EXTRA_PENDING", 1), ("CORE_REGION_SLOT", 1),
          ("CORE_POINTER_SUPPRESSED", 1), ("CORE_POINTER_PAINTLOCK", 1))


class DamageBoundaryTests(unittest.TestCase):
    def test_shared_units_have_no_platform_layout_or_hardware_instructions(self):
        for name in UNITS:
            source = (ROOT / "kernel/core" / name).read_text()
            code = "\n".join(line.split(";", 1)[0] for line in source.splitlines())
            self.assertNotRegex(code, r"\b(?:MSX_\w+|WM_\w+|SCHED_\w+|PLATFORM_\w+|PREEMPTIVE\w*|SCR_\w+|wm_entry|wm_chrome_draw|bank_set|cursor_\w+|cur_\w+|rect_cull|md_call)\b", name)
            self.assertNotRegex(code.lower(), r"\b(?:di|ei|in|out|halt|reti|retn|sp)\b", name)

    def test_single_includes_preserve_entrypoints_and_bind_effects(self):
        kernel = (ROOT / "kernel/gbkern.asm").read_text()
        shared = "\n".join((ROOT / "kernel/core" / name).read_text() for name in UNITS)
        for name in UNITS:
            self.assertEqual(kernel.count(f'include "core/{name}"'), 1)
        for symbol in ("k_wm_setpos", "k_wm_setsize", "damage_axis", "wm_focus_damage",
                       "wm_repaint_all", "wm_repaint_top", "k_wm_damage",
                       "clip_set_full", "wm_set_clip"):
            self.assertNotRegex(kernel, rf"(?m)^{symbol}\s*$")
            self.assertRegex(shared, rf"(?m)^{symbol}\s*$")
        self.assertRegex(kernel, r"(?m)^wm_entry\s*$")
        provider = (ROOT / "kernel/msx_window_damage.inc").read_text()
        for macro, instruction in (("PAINT_IRQ_ENTER", "di"), ("PAINT_IRQ_LEAVE", "ei")):
            self.assertRegex(provider, rf"macro {macro}\s+{instruction}\s+mend")
        self.assertIn("PAINT_PREPARE equ SCHED_VIS_REFRESH_ENTRY", provider)
        scheduler = (ROOT / "kernel/scheduler.asm").read_text()
        self.assertIn("jp    sched_compositor_prepare", scheduler)

    def test_msx_state_aliases_match_drivers_without_reallocating_scratch(self):
        kernel = (ROOT / "kernel/gbkern.asm").read_text()
        layout = (ROOT / "kernel/lowram.inc").read_text()
        provider = (ROOT / "kernel/msx_window_damage.inc").read_text()
        for name, address in (("sp_x", "124B"), ("sp_y", "124C"), ("ss_w", "124D"),
                              ("ss_h", "124E"), ("wm_rp_back", "12FD"), ("wm_rp_i", "12FE")):
            self.assertRegex(layout, rf"(?m)^{name}\s+equ\s+#{address}\b")
            self.assertNotRegex(kernel + provider, rf"(?m)^{name}\s+equ\b")
        for axis, address in zip("XYWH", range(0x1338, 0x133C)):
            self.assertRegex(provider, rf"(?m)^CORE_CLIP_{axis} equ #{address:04X}\b")
            self.assertIn(f"assert CORE_CLIP_{axis}==clip_{axis.lower()}", kernel)
            for mode in (6, 7):
                driver = (ROOT / f"lib/msx/screen{mode}.asm").read_text()
                self.assertRegex(driver, rf"(?m)^clip_{axis.lower()}\s+equ\s+#{address:04X}\b")


@unittest.skipUnless(RASM, "RASM required for actual shared damage/repaint assembly")
class DamageAssemblyTests(unittest.TestCase):
    def assemble(self, base, regions=1, erase=1, screen=(80, 200), overrides=None):
        cells, cursor = {}, base
        for name, size in FIELDS:
            cells[name], cursor = cursor, cursor + size
        cells.update(CORE_CLIP_Y=cells["CORE_CLIP_X"] + 1,
                     CORE_CLIP_W=cells["CORE_CLIP_X"] + 2,
                     CORE_CLIP_H=cells["CORE_CLIP_X"] + 3,
                     CORE_WINDOW_MAX=8, CORE_SCREEN_COLS=screen[0],
                     CORE_SCREEN_LINES=screen[1], CORE_WINDOW_DAMAGE_PAD=4,
                     CORE_REPAINT_REGIONS=regions, CORE_REPAINT_ERASE_POINTER=erase,
                     CORE_PAINT_ALIVE_BIT=4, CORE_PAINT_MANAGED_BIT=5)
        cells.update(overrides or {})
        source = [f"{name} equ {value}" for name, value in cells.items()]
        for i, hook in enumerate(("PAINT_PREPARE", "PAINT_REGION_BEGIN", "PAINT_REGION_NEXT",
                                  "PAINT_SET_BANK", "PAINT_CHROME_DRAW", "PAINT_CALL",
                                  "PAINT_POINTER_ERASE", "PAINT_POINTER_SHOW", "PAINT_RECT_CULL")):
            source.append(f"{hook} equ {0xF000 + 3*i}")
        # Independent 16-byte records: repaint +0, flags +4, tag +7, rect +10.
        # Hook calls keep branch distances bounded. This fixture assembles,
        # not executes; openMSX regressions execute the real MSX provider.
        hooks = {"PAINT_WINDOW_TOKEN": ["call fixture_entry"],
                 "PAINT_WINDOW_RECT": ["call fixture_rect"],
                 "PAINT_CLOSE_RECT": ["call fixture_close"],
                 "PAINT_WINDOW_FLAGS": ["call fixture_flags"],
                 "PAINT_WINDOW_NATIVE": ["call fixture_native"],
                 "PAINT_RECT_ARGUMENTS": ["call fixture_arguments"],
                 "PAINT_REPAINT_POINTER": ["ld a,(hl)", "inc hl", "ld h,(hl)", "ld l,a"],
                 "PAINT_IRQ_ENTER": ["nop"], "PAINT_IRQ_LEAVE": ["nop"]}
        for name, body in hooks.items():
            source += [f"macro {name}", *body, "mend"]
        source += [f'include "{ROOT}/kernel/core/window_damage_contract.inc"',
                   "org #8000", "damage_begin"]
        source += [f'include "{ROOT}/kernel/core/{name}"' for name in UNITS]
        source += ["fixture_entry", "ld l,a", "ld h,0", *["add hl,hl"]*4,
                   f"ld de,{base + 0x100}", "add hl,de", "ret",
                   "fixture_rect", "call fixture_entry", "ld de,10", "add hl,de", "ret",
                   "fixture_close", "call fixture_entry", "push hl", "ld de,7",
                   "add hl,de", "ld b,(hl)", "pop hl", "ld de,10", "add hl,de", "ret",
                   "fixture_flags", "push hl", "ld de,4", "add hl,de", "ld a,(hl)", "pop hl", "ret",
                   "fixture_native", "push hl", *["inc hl"]*7, "ld a,(hl)", "pop hl", "ret",
                   "fixture_arguments", "ld de,10", "add hl,de", "ld b,(hl)",
                   "inc hl", "ld c,(hl)", "inc hl", "ld d,(hl)", "inc hl", "ld e,(hl)", "ret",
                   "damage_end", 'save "damage.bin",damage_begin,damage_end-damage_begin']
        with tempfile.TemporaryDirectory(prefix="geobench-damage-core-") as tmp:
            asm = Path(tmp) / "damage.asm"
            asm.write_text("\n".join(source) + "\n")
            result = subprocess.run([RASM, str(asm), "-s", "-sq", "-o", "damage"],
                                    cwd=tmp, text=True, capture_output=True)
            binary, sym = Path(tmp) / "damage.bin", Path(tmp) / "damage.sym"
            return (result, binary.read_bytes() if binary.exists() else None,
                    sym.read_text() if sym.exists() else "")

    def test_actual_core_assembles_with_independent_layout_geometry_and_pointer(self):
        for regions in (0, 1):
            for erase in (0, 1):
                for screen in ((80, 200), (128, 212)):
                    with self.subTest(regions=regions, erase=erase, screen=screen):
                        low = self.assemble(0x2000, regions, erase, screen)
                        high = self.assemble(0xD800, regions, erase, screen)
                        for result, binary, symbols in (low, high):
                            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                            self.assertIsNotNone(binary)
                            for symbol in ("K_WM_SETPOS", "K_WM_SETSIZE", "DAMAGE_AXIS",
                                           "WM_REPAINT_ALL", "WM_REPAINT_TOP", "WRA_DONE",
                                           "K_WM_DAMAGE", "CLIP_SET_FULL", "WM_SET_CLIP"):
                                self.assertRegex(symbols, rf"(?m)^{symbol} #")
                            self.assertEqual(bool(re.search(r"(?m)^WM_FOCUS_DAMAGE #", symbols)), bool(regions))
                        self.assertEqual(len(low[1]), len(high[1]))
                        self.assertNotEqual(low[1], high[1])
                        self.assertEqual(low[1], self.assemble(0x2000, regions, erase, screen)[1])

    def test_all_state_spans_must_remain_fixed(self):
        for field, size in FIELDS:
            for address in (0x4000, -1, 0x10000-size+1):
                with self.subTest(field=field, address=address):
                    result, binary, _ = self.assemble(0x2000, overrides={field: address})
                    self.assertIsNone(binary)
                    self.assertIn("ASSERT", (result.stdout + result.stderr).upper())
        result, binary, _ = self.assemble(0x2000, overrides={"CORE_DAMAGE_EXTRA": 0x3FFE})
        self.assertIsNone(binary)
        self.assertIn("CORE_DAMAGE_EXTRA must remain", result.stdout + result.stderr)
        # Preserve tuple adjacency so only the fixed-span guard can reject it.
        result, binary, _ = self.assemble(0x2000, overrides={
            "CORE_CLIP_X": 0x3FFE, "CORE_CLIP_Y": 0x3FFF,
            "CORE_CLIP_W": 0x4000, "CORE_CLIP_H": 0x4001})
        self.assertIsNone(binary)
        self.assertIn("CORE_CLIP_X must remain", result.stdout + result.stderr)

    def test_invalid_capacities_geometry_options_and_flag_bits_are_rejected(self):
        cases = {"CORE_WINDOW_MAX": (0, 256), "CORE_SCREEN_COLS": (0, 256),
                 "CORE_SCREEN_LINES": (0, 256), "CORE_WINDOW_DAMAGE_PAD": (-1, 256),
                 "CORE_REPAINT_REGIONS": (-1, 2), "CORE_REPAINT_ERASE_POINTER": (-1, 2),
                 "CORE_PAINT_ALIVE_BIT": (-1, 8), "CORE_PAINT_MANAGED_BIT": (-1, 8)}
        for field, values in cases.items():
            for value in values:
                with self.subTest(field=field, value=value):
                    result, binary, _ = self.assemble(0x2000, overrides={field: value})
                    self.assertIsNone(binary)
                    self.assertIn(field, result.stdout + result.stderr)
        result, binary, _ = self.assemble(0x2000, overrides={"CORE_PAINT_ALIVE_BIT": 5})
        self.assertIsNone(binary)
        self.assertIn("paint flag bits must differ", result.stdout + result.stderr)

    def test_clip_adjacency_and_z_index_page_are_enforced(self):
        for field in ("CORE_CLIP_Y", "CORE_CLIP_W", "CORE_CLIP_H"):
            result, binary, _ = self.assemble(0x2000, overrides={field: 0x2300})
            self.assertIsNone(binary)
            self.assertIn("clip bytes must be contiguous", result.stdout + result.stderr)
        result, binary, _ = self.assemble(0x2000, overrides={"CORE_Z_ORDER": 0x20FC})
        self.assertIsNone(binary)
        self.assertIn("CORE_Z_ORDER crosses", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
