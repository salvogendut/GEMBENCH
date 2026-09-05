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
UNITS = ("worker_select.asm", "visibility_prepare.asm",
         "visible_regions.asm", "window_visibility.asm")
# Independent state, including the adjacency required by the real instructions.
FIELDS = (
    ("CORE_Z_ORDER", 8),
    ("CORE_SURFACE_VISIBILITY", 8),
    ("CORE_WORKER_VISIBILITY", 8),
    ("CORE_APP_WORKER_WIN", 8),
    ("CORE_WIN_OWNER", 8),
    ("CORE_LIVE_WINDOWS", 1),
    ("CORE_FOCUS_SLOT", 1),
    ("CORE_WORKER_CURRENT", 1),
    ("CORE_WORKER_LAST", 1),
    ("CORE_CLIP_X", 1),
    ("CORE_CLIP_Y", 1),
    ("CORE_CLIP_W", 1),
    ("CORE_CLIP_H", 1),
    ("CORE_REGION_SLOT", 1),
    ("CORE_REGION_Z", 1),
    ("CORE_REGION_LEFT", 1),
    ("CORE_REGION_TOP", 1),
    ("CORE_REGION_RIGHT", 1),
    ("CORE_REGION_BOTTOM", 1),
    ("CORE_REGION_Y", 1),
    ("CORE_REGION_BAND_END", 1),
    ("CORE_REGION_X", 1),
    ("CORE_REGION_COVERED", 1),
    ("CORE_REGION_SCAN_Z", 1),
    ("CORE_REGION_SAVED_CLIP", 4),
    ("CORE_REGION_FRAGMENT_COUNT", 1),
    ("CORE_REGION_TEST_X", 1),
    ("CORE_REGION_REFRESH_Z", 1),
    ("CORE_REGION_OWNER_INDEX", 1),
    ("CORE_REGION_OWNER_ID", 1),
    ("CORE_REGION_WORKER_SLOT", 1),
    ("CORE_REGION_OWNER_MAX", 1),
    ("CORE_REGION_SLOT_SCAN", 1),
    ("CORE_COMPOSITOR_DAMAGE", 4),
    ("CORE_COMPOSITOR_EXTRA", 4),
    ("CORE_COMPOSITOR_EXTRA_PENDING", 1),
    ("CORE_COMPOSITOR_EXTRA_ACTIVE", 1),
    ("CORE_COMPOSITOR_SOURCE", 1),
)


class VisibilityBoundaryTests(unittest.TestCase):
    def test_shared_policy_has_no_msx_layout_or_context_switch_instructions(self):
        for name in UNITS:
            source = (ROOT / "kernel/core" / name).read_text()
            code = "\n".join(line.split(";", 1)[0] for line in source.splitlines())
            self.assertNotRegex(code, r"\b(?:MSX_\w+|WM_\w+|SCHED_\w+|PLATFORM_\w+|PREEMPTIVE\w*|sched_wm_entry|sched_bank_set)\b", name)
            self.assertNotRegex(code.lower(), r"\b(?:di|ei|in|out|halt|reti|retn|sp)\b", name)

    def test_ordered_single_includes_leave_context_and_drawing_in_provider(self):
        scheduler = (ROOT / "kernel/scheduler.asm").read_text()
        for name in UNITS:
            self.assertEqual(scheduler.count(f'include "core/{name}"'), 1)
        for symbol in ("sched_region_begin", "sched_region_prepare_band",
                       "sched_visibility_refresh", "sched_m9_select_worker"):
            self.assertNotRegex(scheduler, rf"(?m)^{symbol}\s*$")
        for symbol in ("sched_switch_context", "sched_restore_slot", "sched_wm_entry"):
            self.assertRegex(scheduler, rf"(?m)^{symbol}\s*$")
        kernel = (ROOT / "kernel/gbkern.asm").read_text()
        self.assertIn('include "core/window_repaint.asm"', kernel)
        self.assertIn('include "core/window_focus_damage.asm"', kernel)


@unittest.skipUnless(RASM, "RASM required for actual shared visibility assembly")
class VisibilityAssemblyTests(unittest.TestCase):
    def assemble(self, base, screen=(80, 200), overrides=None):
        cells, cursor = {}, base
        for name, size in FIELDS:
            cells[name], cursor = cursor, cursor + size
        cells.update(CORE_WINDOW_MAX=8, CORE_OWNER_CAPACITY=8,
                     CORE_SCREEN_COLS=screen[0], CORE_SCREEN_LINES=screen[1],
                     CORE_WORKER_READY=9)
        cells.update(overrides or {})
        source = [*[f"{name} equ {value}" for name, value in cells.items()],
                  "VIS_RESTORE_CONTEXT equ fixture_restore",
                  "VIS_RESUME_CONTEXT equ fixture_resume",
                  # A different record: stride 16, rect at +0, flags at +8.
                  # The hooks only assemble here; emulator tests use MSX glue.
                  "macro VIS_WINDOW_RECT", "call fixture_entry", "mend",
                  "macro VIS_WINDOW_FLAGS", "call fixture_entry",
                  "ld de,8", "add hl,de", "mend",
                  "macro VIS_ROOT_FLAGS", f"ld hl,{base + 0x208}", "mend",
                  f'include "{ROOT}/kernel/core/visibility_contract.inc"',
                  "org #8000", "visibility_begin",
                  f'include "{ROOT}/kernel/core/worker_select.asm"',
                  "fixture_resume", "ret", "fixture_restore", "ret"]
        source += [f'include "{ROOT}/kernel/core/{name}"' for name in UNITS[1:]]
        source += ["fixture_entry", "ld l,a", "ld h,0", *["add hl,hl"] * 4,
                   f"ld de,{base + 0x200}", "add hl,de", "ret", "visibility_end",
                   'save "visibility.bin",visibility_begin,visibility_end-visibility_begin']
        with tempfile.TemporaryDirectory(prefix="geobench-visibility-core-") as tmp:
            asm = Path(tmp) / "visibility.asm"
            asm.write_text("\n".join(source) + "\n")
            result = subprocess.run([RASM, str(asm), "-s", "-sq", "-o", "visibility"],
                                    cwd=tmp, text=True, capture_output=True)
            binary, sym = Path(tmp) / "visibility.bin", Path(tmp) / "visibility.sym"
            return (result, binary.read_bytes() if binary.exists() else None,
                    sym.read_text() if sym.exists() else "")

    def test_actual_policy_assembles_with_independent_state_and_native_geometry(self):
        for screen in ((80, 200), (128, 212)):
            with self.subTest(screen=screen):
                low, high = self.assemble(0x2000, screen), self.assemble(0xD800, screen)
                for result, binary, symbols in (low, high):
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIsNotNone(binary)
                    for symbol in ("SCHED_M9_SELECT_WORKER", "SCHED_COMPOSITOR_PREPARE",
                                   "SCHED_REGION_BEGIN", "SCHED_REGION_NEXT",
                                   "SCHED_REGION_TEST", "SCHED_VISIBILITY_REFRESH"):
                        self.assertRegex(symbols, rf"(?m)^{symbol} #")
                self.assertEqual(len(low[1]), len(high[1]))
                self.assertNotEqual(low[1], high[1])
                self.assertEqual(low[1], self.assemble(0x2000, screen)[1])

    def test_invalid_geometry_capacity_and_ready_mask_are_rejected(self):
        cases = {"CORE_WINDOW_MAX": (0, 1, 255),
                 "CORE_OWNER_CAPACITY": (0, 256),
                 "CORE_SCREEN_COLS": (0, 256), "CORE_SCREEN_LINES": (0, 256),
                 "CORE_WORKER_READY": (0, 256)}
        for field, values in cases.items():
            for value in values:
                with self.subTest(field=field, value=value):
                    result, binary, _ = self.assemble(0x2000, overrides={field: value})
                    self.assertIsNone(binary)
                    self.assertIn("invalid " + field, result.stdout + result.stderr)

    def test_all_state_spans_are_fixed_and_index_arrays_fit_a_byte_page(self):
        for field, size in FIELDS:
            for address in (0x4000, -1, 0x10000-size+1):
                with self.subTest(field=field, address=address):
                    result, binary, _ = self.assemble(0x2000, overrides={field: address})
                    self.assertIsNone(binary, result.stdout + result.stderr)
                    # Adjacency checks may reject a corrupt clip/flag/table first.
                    self.assertIn("ASSERT", (result.stdout + result.stderr).upper())
        for field in ("CORE_Z_ORDER", "CORE_APP_WORKER_WIN", "CORE_WIN_OWNER"):
            result, binary, _ = self.assemble(0x2000, overrides={field: 0x20FC})
            self.assertIsNone(binary)
            self.assertIn(field + " crosses", result.stdout + result.stderr)
        for field in ("CORE_REGION_SAVED_CLIP", "CORE_COMPOSITOR_DAMAGE",
                      "CORE_COMPOSITOR_EXTRA"):
            result, binary, _ = self.assemble(0x2000, overrides={field: 0x3FFE})
            self.assertIsNone(binary)
            self.assertIn(field + " must remain", result.stdout + result.stderr)

    def test_bulk_copy_adjacency_is_enforced(self):
        for field, reason in (("CORE_CLIP_Y", "clip bytes must be contiguous"),
                              ("CORE_CLIP_W", "clip bytes must be contiguous"),
                              ("CORE_CLIP_H", "clip bytes must be contiguous"),
                              ("CORE_WORKER_VISIBILITY", "visibility arrays must be contiguous"),
                              ("CORE_COMPOSITOR_EXTRA_ACTIVE", "extra flags must be adjacent")):
            result, binary, _ = self.assemble(0x2000, overrides={field: 0x2300})
            self.assertIsNone(binary)
            self.assertIn(reason, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
