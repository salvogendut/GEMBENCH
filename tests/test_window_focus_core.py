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
UNITS = ("window_zorder.asm", "window_focus_map.asm", "window_focus_click.asm",
         "window_hit_test.asm", "window_raise.asm")
FIELDS = (("CORE_Z_ORDER", 8), ("CORE_LIVE_WINDOWS", 1),
          ("CORE_FOCUS_SLOT", 1), ("CORE_PREVIOUS_FOCUS", 1),
          ("CORE_FOCUS_HANDLER", 2), ("CORE_INPUT_FLAGS", 1),
          ("CORE_POINTER_X", 1), ("CORE_POINTER_Y", 1),
          ("CORE_FOCUS_TARGET", 1), ("CORE_FOCUS_OLD", 1), ("CORE_HIT_CURSOR", 1))


class FocusBoundaryTests(unittest.TestCase):
    def test_shared_units_have_no_target_or_window_layout_dependencies(self):
        shared_symbols = set()
        for name in UNITS:
            source = (ROOT / "kernel/core" / name).read_text()
            code = "\n".join(line.split(";", 1)[0] for line in source.splitlines())
            self.assertNotRegex(code, r"\b(?:MSX_\w+|WM_\w+|PLATFORM_\w+|PREEMPTIVE\w*|POLL_\w+|bank_set|menu_install|menu_clear)\b", name)
            self.assertNotRegex(code.lower(), r"\b(?:out|in|di|ei|halt)\b", name)
            shared_symbols.update(re.findall(r"(?m)^(wm_\w+)\s*$", code))
        self.assertEqual(shared_symbols, {"wm_z_append", "wm_z_remove", "wm_focus_top",
                                         "wm_map_focus", "wm_focus_click", "wm_hit_test",
                                         "wm_raise"})

    def test_policy_is_included_once_and_damage_stays_in_provider(self):
        kernel = (ROOT / "kernel/gbkern.asm").read_text()
        for name in UNITS:
            self.assertEqual(kernel.count(f'include "core/{name}"'), 1)
        for symbol in ("wm_z_append", "wm_z_remove", "wm_raise", "wm_focus_top",
                       "wm_map_focus", "wm_focus_click", "wm_hit_test"):
            self.assertNotRegex(kernel, rf"(?m)^{symbol}\s*$")
        self.assertRegex(kernel, r"(?m)^wm_focus_damage\s*$")
        self.assertRegex(kernel, r"(?m)^wm_repaint_all\s*$")
        # These addresses were moved, not reallocated or copied in the provider.
        layout = (ROOT / "kernel/lowram.inc").read_text()
        provider = (ROOT / "kernel/msx_window_focus.inc").read_text()
        for name, address in (("wm_slot", "12F9"), ("wm_open_back", "12FB"), ("wm_hz", "12FC")):
            self.assertRegex(layout, rf"(?m)^{name}\s+equ\s+#{address}\b")
            self.assertNotRegex(kernel + provider, rf"(?m)^{name}\s+equ\b")


@unittest.skipUnless(RASM, "RASM required for shared focus contracts")
class FocusAssemblyTests(unittest.TestCase):
    def assemble(self, base, flags=(1, 1), overrides=None):
        cells, cursor = {}, base
        for name, size in FIELDS:
            cells[name], cursor = cursor, cursor + size
        cells.update(CORE_WINDOW_MAX=8, CORE_Z_PRESERVE_SLOT=flags[0],
                     CORE_FOCUS_VISIBLE_DAMAGE=flags[1])
        cells.update(overrides or {})
        source = [*[f"{name} equ {value}" for name, value in cells.items()],
                  "FOCUS_SET_BANK equ #F000", "FOCUS_MENU_CLEAR equ #F003",
                  "FOCUS_MENU_INSTALL equ #F006", "FOCUS_BUILD_DAMAGE equ #F009",
                  "FOCUS_REPAINT equ #F00C", "FOCUS_SET_CLIP equ #F00F",
                  "FOCUS_REPAINT_TOP equ #F012",
                  # Independent provider: 16-byte records, native tag at +7,
                  # event/menu pointers at +0/+2, rectangle at +10 (not MSX).
                  "macro FOCUS_NATIVE_CELL", "ld l,a", "ld h,0",
                  *["add hl,hl"] * 4, f"ld de,{base + 0x107}", "add hl,de", "mend",
                  "macro FOCUS_RECT", "FOCUS_NATIVE_CELL", "ld de,3", "add hl,de", "mend"]
        for name, offset in (("FOCUS_EVENT_POINTER", -7), ("FOCUS_MENU_POINTER", -5)):
            source += [f"macro {name}", f"ld de,{offset}", "add hl,de", "ld a,(hl)",
                       "inc hl", "ld h,(hl)", "ld l,a", "mend"]
        source += [f'include "{ROOT}/kernel/core/window_focus_contract.inc"',
                   "org #8000", "focus_begin"]
        source += [f'include "{ROOT}/kernel/core/{name}"' for name in UNITS]
        source += ["focus_end", 'save "focus.bin",focus_begin,focus_end-focus_begin']
        with tempfile.TemporaryDirectory(prefix="geobench-focus-core-") as tmp:
            asm = Path(tmp) / "focus.asm"
            asm.write_text("\n".join(source) + "\n")
            result = subprocess.run([RASM, str(asm), "-s", "-sq", "-o", "focus"],
                                    cwd=tmp, text=True, capture_output=True)
            binary, sym = Path(tmp) / "focus.bin", Path(tmp) / "focus.sym"
            return (result, binary.read_bytes() if binary.exists() else None,
                    sym.read_text() if sym.exists() else "")

    def test_full_policy_assembles_with_independent_state_and_window_layouts(self):
        for flags in ((0, 0), (1, 0), (1, 1)):
            with self.subTest(flags=flags):
                low, high = self.assemble(0x2000, flags), self.assemble(0xD800, flags)
                for result, binary, symbols in (low, high):
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIsNotNone(binary)
                    for symbol in ("WM_Z_APPEND", "WM_Z_REMOVE", "WM_RAISE", "WM_FOCUS_TOP",
                                   "WM_MAP_FOCUS", "WM_FOCUS_CLICK", "WM_HIT_TEST"):
                        self.assertRegex(symbols, rf"(?m)^{symbol} #")
                self.assertEqual(len(low[1]), len(high[1]))
                self.assertNotEqual(low[1], high[1])
                self.assertEqual(low[1], self.assemble(0x2000, flags)[1])

    def test_invalid_count_capacity_and_index_page_are_rejected(self):
        for overrides, reason in (({"CORE_Z_ORDER": 0x20FC}, "CORE_Z_ORDER crosses"),
                                  ({"CORE_WINDOW_MAX": 0}, "invalid CORE_WINDOW_MAX"),
                                  ({"CORE_WINDOW_MAX": 256}, "invalid CORE_WINDOW_MAX")):
            result, binary, _ = self.assemble(0x2000, overrides=overrides)
            self.assertIsNone(binary)
            self.assertIn(reason, result.stdout + result.stderr)

    def test_fixed_state_spans_and_boolean_options_are_checked(self):
        for field, size in FIELDS:
            for address in (0x4000, 0x10000 - size + 1, -1):
                with self.subTest(field=field, address=address):
                    result, binary, _ = self.assemble(0x2000, overrides={field: address})
                    self.assertIsNone(binary)
                    self.assertIn(field, result.stdout + result.stderr)
        result, binary, _ = self.assemble(0x2000, overrides={"CORE_FOCUS_HANDLER": 0x3FFF})
        self.assertIsNone(binary)
        self.assertIn("CORE_FOCUS_HANDLER must remain", result.stdout + result.stderr)
        for field in ("CORE_Z_PRESERVE_SLOT", "CORE_FOCUS_VISIBLE_DAMAGE"):
            result, binary, _ = self.assemble(0x2000, overrides={field: 2})
            self.assertIsNone(binary)
            self.assertIn(field + " must be boolean", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
