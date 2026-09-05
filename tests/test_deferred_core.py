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
UNITS = ("deferred_api.asm", "deferred_queue.asm", "deferred_purge.asm",
         "deferred_dispatch.asm")
ARRAYS = ("CORE_DEFER_HANDLER_LO", "CORE_DEFER_HANDLER_HI", "CORE_APP_FLAGS",
          "CORE_APP_CODE_NATIVE", "CORE_APP_PRIMARY_WIN", "CORE_WIN_OWNER",
          "CORE_WIN_OWNER_GEN")
FIELDS = (*[(name, 8) for name in ARRAYS], ("CORE_DEFER_SEND", 6),
          ("CORE_DEFER_CURRENT", 8), ("CORE_DEFER_PURGE_OWNER", 2),
          ("CORE_DEFER_COUNT", 1), ("CORE_DEFER_BUSY", 1), ("CORE_DEFER_INDEX", 1),
          ("CORE_DEFER_ACTIVATE", 1), ("CORE_MESSAGE", 4), ("CORE_MAPPED_NATIVE", 1))


class DeferredBoundaryTests(unittest.TestCase):
    def test_policy_has_no_native_layout_pointer_checks_or_hardware(self):
        for name in UNITS:
            source = (ROOT / "kernel/core" / name).read_text()
            code = "\n".join(line.split(";", 1)[0] for line in source.splitlines())
            self.assertNotRegex(code, r"\b(?:MSX_\w+|WM_\w+|SCHED_\w+|PLATFORM_\w+|PREEMPTIVE\w*|BOOT_SP|bank_set|wm_entry|md_call|owner_current|owner_validate)\b", name)
            self.assertNotRegex(code.lower(), r"\b(?:di|ei|in|out|halt|sp)\b", name)

    def test_single_late_include_and_fifo_callback_boundaries(self):
        source = (ROOT / "kernel/msx_page_pool.asm").read_text()
        late = source.index("ifdef GB_DEFER_LATE")
        for name in UNITS:
            token = f'include "core/{name}"'
            self.assertEqual(source.count(token), 1)
            self.assertGreater(source.index(token), late)
        api = (ROOT / "kernel/core/deferred_api.asm").read_text()
        dispatch = (ROOT / "kernel/core/deferred_dispatch.asm").read_text()
        self.assertEqual(api.count("DEFER_REQUIRE_ROOT"), 3)
        self.assertLess(api.index("jp    z,kdefer_no_handler"), api.index("cp    CORE_DEFER_CAPACITY"))
        self.assertLess(dispatch.index("call  defer_remove_index"), dispatch.index("call  DEFER_VALIDATE_OWNER"))
        self.assertLess(dispatch.index("call  DEFER_VALIDATE_OWNER"), dispatch.index("call  DEFER_CALL"))
        provider = (ROOT / "kernel/msx_deferred.inc").read_text()
        self.assertIn("MSX_APP_FIXED_BOTTOM/256", provider)
        self.assertIn("ld    hl,(BOOT_SP)", provider)
        self.assertIn("jp    wm_repaint_top", provider)


@unittest.skipUnless(RASM, "RASM required for actual shared deferred assembly")
class DeferredAssemblyTests(unittest.TestCase):
    def assemble(self, base, root_check=1, overrides=None):
        cells, cursor = {}, base
        for name, size in FIELDS:
            cells[name], cursor = cursor, cursor + size
        cells.update(CORE_DEFER_QUEUE=base+0x80, CORE_DEFER_CAPACITY=8,
                     CORE_OWNER_CAPACITY=8, CORE_WINDOW_MAX=8,
                     GB_DEFER_RECORD_SIZE=8, CORE_DEFER_EVENT=12,
                     CORE_APP_TERMINATING_BIT=2)
        cells.update(overrides or {})
        source = [f"{name} equ {value}" for name, value in cells.items()]
        for name, value in (("STALE", 2), ("NO_HANDLER", 3), ("FULL", 4),
                            ("BADARG", 5), ("CONTEXT", 6)):
            source.append(f"GB_DEFER_ERR_{name} equ {value}")
        for index, name in enumerate(("DEFER_CURRENT_OWNER", "DEFER_VALIDATE_OWNER",
                                      "DEFER_SET_BANK", "DEFER_CALL", "DEFER_FIND_SERVICE",
                                      "DEFER_FIND_ACCESSORY")):
            source.append(f"{name} equ {0xF000+index*3}")
        # Independent fixed state and provider hooks, not an executed emulator.
        source += ["macro DEFER_REQUIRE_ROOT"]
        if root_check:
            source += [f"ld a,({base+0xFE})", "or a", "jp nz,kdefer_context"]
        source += ["mend", "macro DEFER_CHECK_CALLBACK", "ld a,h", "cp #40",
                   "jr c,kdefer_bad", "cp #80", "jr nc,kdefer_bad", "mend",
                   "macro DEFER_CHECK_SEND_RECORD", "call fixture_input",
                   "jp c,kdefer_bad", "mend",
                   "macro DEFER_ACTIVATE_WINDOW", "jp #F020", "mend",
                   f'include "{ROOT}/kernel/core/deferred_contract.inc"',
                   "org #8000", "deferred_begin"]
        source += [f'include "{ROOT}/kernel/core/{name}"' for name in UNITS]
        source += ["fixture_input", "or a", "ret", "deferred_end",
                   'save "deferred.bin",deferred_begin,deferred_end-deferred_begin']
        with tempfile.TemporaryDirectory(prefix="geobench-deferred-core-") as tmp:
            asm = Path(tmp) / "deferred.asm"
            asm.write_text("\n".join(source) + "\n")
            result = subprocess.run([RASM, str(asm), "-s", "-sq", "-o", "deferred"],
                                    cwd=tmp, text=True, capture_output=True)
            binary, sym = Path(tmp) / "deferred.bin", Path(tmp) / "deferred.sym"
            return (result, binary.read_bytes() if binary.exists() else None,
                    sym.read_text() if sym.exists() else "")

    def test_independent_low_high_state_and_context_variants(self):
        for root_check in (0, 1):
            low, high = self.assemble(0x2000, root_check), self.assemble(0xD800, root_check)
            for result, binary, symbols in (low, high):
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIsNotNone(binary)
                for symbol in ("K_DEFER", "KDEFER_REGISTER", "KDEFER_SEND",
                               "DEFER_REMOVE_INDEX", "DEFER_PURGE_OWNER",
                               "DEFER_CANCEL_SENDER", "DEFER_DISPATCH_ONE"):
                    self.assertRegex(symbols, rf"(?m)^{symbol} #")
            self.assertEqual(len(low[1]), len(high[1]))
            self.assertNotEqual(low[1], high[1])
            self.assertEqual(low[1], self.assemble(0x2000, root_check)[1])

    def test_queue_pointer_high_byte_is_not_rounded_up(self):
        # RASM / uses floating-point arithmetic: mask low byte before division.
        for address in (0x2000, 0x2080, 0x20C0, 0xD880):
            result, binary, symbols = self.assemble(0x2000, overrides={"CORE_DEFER_QUEUE": address})
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            offset = int(re.search(r"(?m)^DEFER_RECORD_PTR #([0-9A-F]+)", symbols)[1], 16)-0x8000
            self.assertEqual(binary[offset:offset+9], bytes((0x87, 0x87, 0x87, 0xC6,
                             address & 255, 0x6F, 0x26, address >> 8, 0xC9)))

    def test_fixed_spans_and_index_pages_are_checked(self):
        for name, size in (*FIELDS, ("CORE_DEFER_QUEUE", 64)):
            for address in (-1, 0x4000, 0x10000-size+1):
                result, binary, _ = self.assemble(0x2000, overrides={name: address})
                self.assertIsNone(binary)
                self.assertIn("ASSERT", (result.stdout + result.stderr).upper())
        for name in ARRAYS:
            result, binary, _ = self.assemble(0x2000, overrides={name: 0x20FC})
            self.assertIsNone(binary)
            self.assertIn(name + " crosses", result.stdout + result.stderr)
        for name, address in (("CORE_DEFER_SEND", 0x3FFD), ("CORE_DEFER_CURRENT", 0x3FFC)):
            result, binary, _ = self.assemble(0x2000, overrides={name: address})
            self.assertIsNone(binary)
            self.assertIn(name + " must remain", result.stdout + result.stderr)

    def test_capacity_record_and_flag_contracts_are_checked(self):
        for name, values in (("CORE_DEFER_CAPACITY", (0, 33)),
                             ("CORE_OWNER_CAPACITY", (0, 256)),
                             ("CORE_WINDOW_MAX", (0, 256)),
                             ("CORE_APP_TERMINATING_BIT", (-1, 8)),
                             ("CORE_DEFER_EVENT", (0, 256)),
                             ("GB_DEFER_RECORD_SIZE", (7, 9))):
            for value in values:
                result, binary, _ = self.assemble(0x2000, overrides={name: value})
                self.assertIsNone(binary)
                self.assertIn("ASSERT", (result.stdout + result.stderr).upper())
        result, binary, _ = self.assemble(0x2000, overrides={"CORE_DEFER_QUEUE": 0x20C8})
        self.assertIsNone(binary)
        self.assertIn("deferred queue crosses", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
