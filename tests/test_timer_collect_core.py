from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SDAS = shutil.which(os.environ.get("SDAS", "sdasz80"))
FIELDS = (("CORE_TIMER_OWNER", 1), ("CORE_TIMER_RECT", 4), ("CORE_TIMER_GEN", 1),
          ("CORE_TIMER_DROPPED", 1), ("CORE_TIMER_DROPPED_GEN", 1),
          ("CORE_TIMER_FULLSCREEN", 1), ("CORE_TIMER_WIN_OWNER", 8),
          ("CORE_TIMER_WIN_GEN", 8), ("CORE_TIMER_VISIBILITY", 8))


class TimerBoundaryTests(unittest.TestCase):
    def test_shared_collector_has_no_native_layout_and_stays_app_linked(self):
        shared = (ROOT / "lib/gembench/core/timer_collect.inc").read_text()
        code = "\n".join(line.split(";", 1)[0] for line in shared.splitlines())
        self.assertNotRegex(code, r"\b(?:MSX_\w+|GB_TIMER_\w+|WM_FULLSCREEN|GB_RESTPAR|GB_WMDAMAGE|GB_DAMAGE_VISIBLE)\b")
        self.assertNotRegex(code.lower(), r"\b(?:di|ei|in|out|halt|sp)\b")
        wrapper = (ROOT / "lib/gembench/gbtimer_collect.s").read_text()
        self.assertEqual(wrapper.count('.include "core/timer_collect.inc"'), 1)
        self.assertIn('.include "msx_timer_collect.inc"', wrapper)
        self.assertIn('.include "core/timer_collect_contract.inc"', wrapper)
        builder = (ROOT / "tools/build_capp.sh").read_text()
        dependencies = builder[builder.index('deps+=') : builder.index('stamp="$OUT.stamp"')]
        for name in ("msx_timer_collect.inc", "core/timer_collect.inc", "core/timer_collect_contract.inc"):
            self.assertIn(f'"$GBR_LIB/{name}"', dependencies)
        self.assertIn('"$SDAS" -I"$GBR_LIB" -o "$work/gbtimer_collect.rel"', builder)
        self.assertIn("gb_timer_collect();", (ROOT / "apps/desktop/main.c").read_text())

    def test_msx_bindings_match_authoritative_state(self):
        provider = (ROOT / "lib/gembench/msx_timer_collect.inc").read_text()
        glue = (ROOT / "lib/msx/glue.inc").read_text()
        for short, native in (("OWNER", "MSX_TIMER_OWNER"), ("RECT", "MSX_TIMER_RECT"),
                               ("GEN", "MSX_TIMER_GEN"), ("DROPPED", "MSX_TIMER_DROPPED"),
                               ("DROPPED_GEN", "MSX_TIMER_DROPPED_GEN"),
                               ("WIN_OWNER", "MSX_WIN_OWNER"), ("WIN_GEN", "MSX_WIN_GEN"),
                               ("VISIBILITY", "MSX_WM_VISIBILITY")):
            actual = int(re.search(rf"^CORE_TIMER_{short}\s*=\s*0x([0-9A-F]+)", provider, re.M)[1], 16)
            expected = int(re.search(rf"^{native}\s+equ\s+#([0-9A-F]+)", glue, re.M)[1], 16)
            self.assertEqual(actual, expected, short)


@unittest.skipUnless(SDAS, "SDAS required for actual shared timer collection assembly")
class TimerAssemblyTests(unittest.TestCase):
    def assemble(self, base, overrides=None):
        cells, cursor = {}, base
        for name, size in FIELDS:
            cells[name], cursor = cursor, cursor + size
        cells.update(CORE_TIMER_WINDOW_MAX=8, TIMER_REPAINT=0xF000,
                     TIMER_SET_DAMAGE=0xF003, TIMER_TEST_VISIBLE=0xF006)
        cells.update(overrides or {})
        source = [".module gbtimer_collect", ".globl _gb_timer_collect",
                  *[f"{name} = {value}" for name, value in cells.items()],
                  '.include "core/timer_collect_contract.inc"', '.area _CODE',
                  '.include "core/timer_collect.inc"']
        with tempfile.TemporaryDirectory(prefix="geobench-timer-core-") as tmp:
            asm, rel = Path(tmp) / "timer.s", Path(tmp) / "timer.rel"
            asm.write_text("\n".join(source) + "\n")
            result = subprocess.run([SDAS, f"-I{ROOT}/lib/gembench", "-o", str(rel), str(asm)],
                                    text=True, capture_output=True)
            return result, rel.read_text() if rel.exists() else ""

    def test_independent_low_high_state_keeps_collector_size_and_determinism(self):
        low, high = self.assemble(0x2000), self.assemble(0xD800)
        for result, obj in (low, high):
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("A _CODE size 74", obj)  # 116 Z80 bytes, unchanged
            self.assertIn("S _gb_timer_collect Def00000000", obj)
        self.assertNotEqual(low[1], high[1])
        self.assertEqual(low[1], self.assemble(0x2000)[1])

    def test_invalid_state_spans_index_pages_and_active_bit_capacity_fail(self):
        for name, size in FIELDS:
            for address in (-1, 0x4000, 0x10000-size+1):
                with self.subTest(name=name, address=address):
                    result, _ = self.assemble(0x2000, {name: address})
                    self.assertNotEqual(result.returncode, 0)
        result, _ = self.assemble(0x2000, {"CORE_TIMER_RECT": 0x3FFE})
        self.assertNotEqual(result.returncode, 0)
        for name in ("CORE_TIMER_WIN_OWNER", "CORE_TIMER_WIN_GEN", "CORE_TIMER_VISIBILITY"):
            result, _ = self.assemble(0x2000, {name: 0x20FC})
            self.assertNotEqual(result.returncode, 0)
        for capacity in (0, 128):
            result, _ = self.assemble(0x2000, {"CORE_TIMER_WINDOW_MAX": capacity})
            self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
