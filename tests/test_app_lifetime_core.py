from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

from test_owner_page_core import STATE_FIELDS

ROOT = Path(__file__).resolve().parents[1]
RASM = shutil.which(os.environ.get("RASM", "rasm"))
UNITS = ("app_code.asm", "window_identity.asm", "owner_context.asm",
         "app_lifetime.asm", "window_close.asm")
EXTRA_FIELDS = (("CORE_APP_SLOT", 1), ("CORE_APP_REMAIN", 1),
                ("CORE_WINDOW_SLOT", 1), ("CORE_WINDOW_HANDLE", 2),
                ("CORE_WIN_GEN", 8), ("CORE_CLOSE_OWNER", 2),
                ("CORE_CALLER_BANK", 1), ("CORE_MAPPED_NATIVE", 1),
                ("CORE_FOCUS_SLOT", 1), ("CORE_PREVIOUS_FOCUS", 1),
                ("CORE_LIVE_WINDOWS", 1))


class LifetimeBoundaryTests(unittest.TestCase):
    def test_shared_units_do_not_depend_on_msx_or_window_table_layout(self):
        for name in UNITS:
            source = (ROOT / "kernel/core" / name).read_text()
            code = "\n".join(line.split(";", 1)[0] for line in source.splitlines())
            self.assertNotRegex(code, r"\b(?:MSX_\w+|WM_\w+|PREEMPTIVE\w*|bank_cur|bank_set)\b", name)
            self.assertNotRegex(code.lower(), r"\b(?:out|in|di|ei|halt|ldir)\b", name)
            # wm_free_page is the already-shared legacy page-release wrapper,
            # not a compositor helper. All renderer access must use the hooks.
            self.assertEqual(set(re.findall(r"\bwm_\w+", code)) - {"wm_free_page"}, set(), name)

    def test_existing_policy_is_included_once_not_copied_for_cpc(self):
        pool = (ROOT / "kernel/msx_page_pool.asm").read_text()
        kernel = (ROOT / "kernel/gbkern.asm").read_text()
        for unit in UNITS[:-1]:
            self.assertEqual(pool.count(f'include "core/{unit}"'), 1)
        self.assertEqual(kernel.count('include "core/window_close.asm"'), 1)
        for symbol in ("app_window_attach", "window_validate_owned", "kapp_quit"):
            self.assertNotRegex(pool, rf"(?m)^{symbol}\b")
        self.assertRegex(kernel, r'(?m)^msx_window_close_slot\n\s+include "core/window_close.asm"')


@unittest.skipUnless(RASM, "RASM required for shared application lifetime contracts")
class LifetimeAssemblyTests(unittest.TestCase):
    def assemble(self, base, overrides=None):
        cells, cursor = {}, base
        for name, size in (*STATE_FIELDS, *EXTRA_FIELDS):
            if (cursor & 255)+size > 256:
                cursor = (cursor+255)&~255
            cells[name], cursor = cursor, cursor+size
        cells.update(CORE_PAGE_CAPACITY=32, CORE_OWNER_CAPACITY=8, CORE_WINDOW_MAX=8)
        cells.update(overrides or {})
        constants = dict(GB_OWNER_MAX=8, GB_PAGE_RESOURCE=2, GB_PAGE_ERR_STALE=2,
                         GB_PAGE_ERR_OWNER=3, GB_PAGE_ERR_FREE=4, GB_APP_OK=0,
                         GB_APP_ERR_STALE=2, GB_APP_ERR_OWNER=3, GB_APP_ERR_ROOT=5,
                         GB_APP_ERR_BADARG=6, GB_APP_F_PUBLISHED=1, GB_APP_F_ROOT=2,
                         GB_APP_F_WINDOWLESS=8)
        source = [*[f"{name} equ {value}" for name, value in {**cells, **constants}.items()],
                  "OWNER_PAGE_CURRENT_OWNER equ owner_current",
                  "OWNER_PAGE_PURGE_MESSAGES equ #F000",
                  "OWNER_PAGE_CLOSE_CONTEXTS equ #F003",
                  "LIFETIME_CURRENT_OWNER equ owner_current",
                  "LIFETIME_CLOSE_WINDOW equ app_window_close_slot",
                  "LIFETIME_SET_BANK equ #F006",
                  "LIFETIME_REMOVE_Z equ #F009",
                  "LIFETIME_FOCUS_TOP equ #F00C",
                  "LIFETIME_MAP_FOCUS equ #F00F",
                  "LIFETIME_REPAINT equ #F012",
                  "macro OWNER_PAGE_PUBLISH_FREE", f"ld ({base+0x3F0}),a", "mend",
                  # Different layout: one separate flags byte per slot, no
                  # MSX WM_TABLE stride or WM_FR_FLAGS offset in the provider.
                  "macro LIFETIME_TEST_WINDOW_ALIVE", f"ld hl,{base+0x300}",
                  "ld b,0", "add hl,bc", "bit 0,(hl)", "mend",
                  "macro LIFETIME_REGISTER_SLOT", f"ld a,({base+0x310})", "mend",
                  "macro LIFETIME_PREPARE_CLOSE", f"ld hl,{base+0x300}",
                  "ld b,0", "add hl,bc", "ld a,33", "ld (CORE_ALLOC_NATIVE),a", "mend",
                  "macro LIFETIME_DROP_WORKER", "nop", "mend",
                  "macro LIFETIME_DRAG_CURRENT", "call #F015", "mend",
                  f'include "{ROOT}/kernel/core/owner_page_contract.inc"',
                  f'include "{ROOT}/kernel/core/app_lifetime_contract.inc"',
                  "org #8000", "lifetime_begin"]
        for name in ("page_count.asm", "owner_identity.asm", "page_pool.asm",
                     "owner_reclaim.asm", *UNITS):
            source.append(f'include "{ROOT}/kernel/core/{name}"')
        source += ["lifetime_end", 'save "lifetime.bin",lifetime_begin,lifetime_end-lifetime_begin']
        with tempfile.TemporaryDirectory(prefix="geobench-lifetime-core-") as tmp:
            asm = Path(tmp)/"lifetime.asm"
            asm.write_text("\n".join(source)+"\n")
            result = subprocess.run([RASM, str(asm), "-s", "-sq", "-o", "lifetime"],
                                    cwd=tmp, text=True, capture_output=True)
            binary, sym = Path(tmp)/"lifetime.bin", Path(tmp)/"lifetime.sym"
            return (result, binary.read_bytes() if binary.exists() else None,
                    sym.read_text() if sym.exists() else "")

    def test_full_core_assembles_with_independent_low_and_high_state(self):
        low, high = self.assemble(0x2000), self.assemble(0xD800)
        for result, binary, symbols in (low, high):
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            self.assertIsNotNone(binary)
            for symbol in ("APP_WINDOW_ATTACH", "APP_WINDOW_DETACH", "OWNER_CURRENT",
                           "WINDOW_VALIDATE_OWNED", "KAPP_PUBLISH", "KAPP_QUIT",
                           "APP_WINDOW_CLOSE_SLOT"):
                self.assertRegex(symbols, rf"(?m)^{symbol} #")
        self.assertEqual(len(low[1]), len(high[1]))
        self.assertNotEqual(low[1], high[1], "relocated state must change operands")
        self.assertEqual(low[1], self.assemble(0x2000)[1])

    def test_window_generation_table_must_fit_index_page(self):
        result, binary, _ = self.assemble(0x2000, {"CORE_WIN_GEN": 0x20FC})
        self.assertIsNone(binary, result.stdout+result.stderr)
        self.assertIn("CORE_WIN_GEN crosses", result.stdout+result.stderr)

    def test_all_new_state_must_fit_fixed_ram(self):
        for field, size in EXTRA_FIELDS:
            for address in (0x4000, 0x10000-size+1):
                with self.subTest(field=field, address=address):
                    result, binary, _ = self.assemble(0x2000, {field: address})
                    self.assertIsNone(binary, result.stdout+result.stderr)
                    reason = " crosses" if field == "CORE_WIN_GEN" and address > 0xFFFF-8 else " must remain"
                    self.assertIn(field+reason, result.stdout+result.stderr)
        for field in ("CORE_WINDOW_HANDLE", "CORE_CLOSE_OWNER"):
            result, binary, _ = self.assemble(0x2000, {field: 0x3FFF})
            self.assertIsNone(binary, result.stdout+result.stderr)
            self.assertIn(field+" must remain", result.stdout+result.stderr)


if __name__ == "__main__":
    unittest.main()
