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
UNITS = ("context_init.asm", "context_save.asm", "context_restore.asm",
         "context_tasks.asm", "context_irq.asm")


class ContextBoundaryTests(unittest.TestCase):
    def test_shared_mechanism_has_no_platform_addresses_or_hardware_leaves(self):
        for name in UNITS:
            source = (ROOT / "kernel/core" / name).read_text()
            code = "\n".join(line.split(";", 1)[0] for line in source.splitlines())
            self.assertNotRegex(code, r"\b(?:MSX_\w+|WM_\w+|SCHED_\w+|PLATFORM_\w+|PREEMPTIVE\w*|BOOT_SP|BANK_CUR|sched_wm_entry|sched_bank_set)\b", name)
            self.assertNotRegex(code.lower(), r"\b(?:di|ei|in|out|im|reti|retn|halt)\b", name)
            self.assertNotRegex(code, r"#[0-9A-Fa-f]{4}", name)

    def test_one_shared_priority_algorithm_and_ordered_context_composition(self):
        wrapper = (ROOT / "kernel/scheduler.asm").read_text()
        includes = re.findall(r'include "([^"]+)"', wrapper)
        for name in UNITS:
            self.assertEqual(includes.count("core/" + name), 1)
        self.assertLess(includes.index("core/context_save.asm"), includes.index("core/worker_select.asm"))
        self.assertLess(includes.index("core/worker_select.asm"), includes.index("core/context_restore.asm"))
        self.assertNotIn("sched_next_slot", wrapper)
        self.assertNotIn("CPC_FW_IRQ", wrapper)
        hw = (ROOT / "kernel/msx_context_irq.asm").read_text()
        self.assertIn("ld (sched_irq_chain+1),hl", hw)
        self.assertIn("ld hl,(sched_irq_chain+1)", hw)
        helper = (ROOT / "kernel/msx_context_helpers.asm").read_text()
        self.assertIn("ld (BANK_CUR),a", helper)
        self.assertIn("ld hl,(MSX_PUTP1)", helper)
        self.assertIn('"$TASK_RUNTIME_RAW"', (ROOT / "tools/build_capp.sh").read_text())


@unittest.skipUnless(RASM, "RASM required for actual shared context assembly")
class ContextAssemblyTests(unittest.TestCase):
    def assemble(self, base=0x2000, overrides=None):
        # Independent records (16-byte stride, flags +8, direct worker +10),
        # fixed state and IRQ finish. These assemble real shared instructions;
        # stub bank/IRQ leaves are NOT CPC hardware execution evidence.
        cells = dict(CORE_CONTEXT_LOCK=base, CORE_CONTEXT_IRQ_PENDING=base+1,
                     CORE_CONTEXT_CURRENT=base+2, CORE_CONTEXT_QUANTUM=base+3,
                     CORE_CONTEXT_RUNNABLE=base+4, CORE_CONTEXT_LAST=base+5,
                     CORE_CONTEXT_STACK_MAX=base+6, CORE_CONTEXT_FAULT=base+7,
                     CORE_CONTEXT_BOOT_SP=base+8, CORE_CONTEXT_BANK=base+10,
                     CORE_CONTEXT_FOCUS=base+11, CORE_CONTEXT_TMP_BOTTOM=base+0x100,
                     CORE_CONTEXT_TMP_TOP=base+0x140, CORE_CONTEXT_SNAPSHOT=0x7F00,
                     CORE_CONTEXT_STACK_DATA=0x7F01, CORE_CONTEXT_STACK_CAP=255,
                     CORE_CONTEXT_APP_FIRST_HI=0x40, CORE_CONTEXT_APP_END_HI=0x80,
                     CORE_CONTEXT_QUANTUM_TICKS=6, CORE_CONTEXT_TIMER=1,
                     CORE_CONTEXT_SWITCH=1, CORE_CONTEXT_RUN_BIT=3,
                     CORE_CONTEXT_MANAGED_BIT=1, CORE_CONTEXT_CODE_BASE=0xA000,
                     CORE_CONTEXT_CODE_END=0xB000, CORE_WORKER_CURRENT=base+2,
                     CORE_WORKER_LAST=base+5, CORE_WORKER_READY=9,
                     CORE_WINDOW_MAX=8, CORE_VIS_FOCUSED=3,
                     CORE_REGION_OWNER_MAX=base+12, CORE_REGION_SLOT_SCAN=base+13,
                     CORE_WORKER_VISIBILITY=base+0x20)
        cells.update(overrides or {})
        macros = {
            "CTX_DI": ["di"], "CTX_EI": ["ei"],
            "CTX_IRQ_INSTALL": ["call fixture_irq_install"],
            "CTX_IRQ_FINISH": ["pop af", "ei", "reti"],
            "CTX_WINDOW_ENTRY": ["call fixture_entry"],
            "CTX_FLAGS_FROM_ENTRY": ["ld de,8", "add hl,de"],
            "CTX_ENTRY_FROM_FLAGS": ["ld de,-8", "add hl,de"],
            "CTX_WORKER_POINTER": ["ld de,10", "add hl,de", "ld a,(hl)",
                                   "inc hl", "ld h,(hl)", "ld l,a"],
            "CTX_CALL_WORKER": ["call fixture_call"],
            "CTX_MAP_BANK": ["call fixture_bank"],
            "CTX_SAMPLE_STACK": [], "CTX_SAMPLE_FAULT": [],
            "VIS_ROOT_FLAGS": [f"ld hl,{base+0x208}"],
            "VIS_WINDOW_FLAGS": ["call fixture_entry", "ld de,8", "add hl,de"],
        }
        source = [*[f"{k} equ {v}" for k, v in cells.items()],
                  "VIS_RESTORE_CONTEXT equ sched_restore_slot",
                  "VIS_RESUME_CONTEXT equ sched_resume_old"]
        for name, code in macros.items():
            source += [f"macro {name}", *code, "mend"]
        source += [f'include "{ROOT}/kernel/core/context_contract.inc"',
                   "org CORE_CONTEXT_CODE_BASE", "fixture_begin"]
        for name in ("context_init.asm", "context_save.asm", "worker_select.asm",
                     "context_restore.asm", "context_tasks.asm", "context_irq.asm"):
            source += [f'include "{ROOT}/kernel/core/{name}"']
        source += ["fixture_entry", "ld l,a", "ld h,0", *["add hl,hl"]*4,
                   f"ld de,{base+0x200}", "add hl,de", "ret", "fixture_call", "jp (hl)",
                   "fixture_bank", "ld (CORE_CONTEXT_BANK),a", "ret",
                   "fixture_irq_install", "ret", "fixture_end",
                   'assert fixture_end<=CORE_CONTEXT_CODE_END,"context image exceeds fixed allocation"',
                   'save "context.bin",fixture_begin,fixture_end-fixture_begin']
        with tempfile.TemporaryDirectory(prefix="geobench-context-core-") as tmp:
            asm = Path(tmp) / "context.asm"
            asm.write_text("\n".join(source) + "\n")
            result = subprocess.run([RASM, str(asm), "-s", "-sq", "-o", "context"],
                                    cwd=tmp, text=True, capture_output=True)
            binary, symbols = Path(tmp) / "context.bin", Path(tmp) / "context.sym"
            return (result, binary.read_bytes() if binary.exists() else None,
                    symbols.read_text() if symbols.exists() else "")

    def test_real_shared_context_with_relocated_state_records_and_irq_finish(self):
        low, high = self.assemble(), self.assemble(0xD800)
        for result, binary, symbols in (low, high):
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            for name in ("SCHED_SWITCH_CONTEXT", "SCHED_RESTORE_SLOT", "SCHED_YIELD",
                         "SCHED_IRQ_BODY", "SCHED_IRQ_RESTORE", "K_TASK_ENABLE"):
                self.assertRegex(symbols, rf"(?m)^{name} #")
            # The actual assembled yield frame saves ALL ten register pairs.
            self.assertIn(bytes.fromhex("f3 f5 c5 d5 e5 dd e5 fd e5 08 f5 08 d9 c5 d5 e5 d9"), binary)
            # Restoring alternates, IY/IX and the main registers is symmetrical.
            self.assertIn(bytes.fromhex("d9 e1 d1 c1 d9 08 f1 08 fd e1 dd e1 e1 d1 c1"), binary)
        self.assertEqual(len(low[1]), len(high[1]))
        self.assertNotEqual(low[1], high[1])
        self.assertEqual(low[1], self.assemble()[1])

    def test_contiguous_state_and_visibility_binding_are_enforced(self):
        for field in ("IRQ_PENDING", "CURRENT", "QUANTUM", "RUNNABLE", "LAST", "STACK_MAX", "FAULT"):
            self.reject({"CORE_CONTEXT_"+field: 0x2300}, "context state must be contiguous")
        for field in ("CORE_WORKER_CURRENT", "CORE_WORKER_LAST"):
            self.reject({field: 0x2300}, "mismatch")
        self.reject({"CORE_WORKER_READY": 5}, "ready mismatch")

    def test_abi_quantum_modes_and_bits_are_bounded(self):
        for field in ("CORE_CONTEXT_SNAPSHOT", "CORE_CONTEXT_STACK_DATA", "CORE_CONTEXT_STACK_CAP"):
            self.reject({field: 0}, "snapshot ABI is frozen")
        for field in ("CORE_CONTEXT_APP_FIRST_HI", "CORE_CONTEXT_APP_END_HI"):
            self.reject({field: 0}, "app aperture is frozen")
        for value in (0, 256):
            self.reject({"CORE_CONTEXT_QUANTUM_TICKS": value}, "invalid context quantum")
        for field in ("CORE_CONTEXT_TIMER", "CORE_CONTEXT_SWITCH"):
            self.reject({field: 2}, "invalid context")
        self.reject({"CORE_CONTEXT_RUN_BIT": 0}, "invalid context runnable bit")
        for value in (0, 3, 8):
            self.reject({"CORE_CONTEXT_MANAGED_BIT": value}, "invalid context managed bit")

    def test_fixed_spans_and_local_overlap_are_rejected(self):
        for field in ("CORE_CONTEXT_BOOT_SP", "CORE_CONTEXT_BANK", "CORE_CONTEXT_FOCUS"):
            for address in (-1, 0x4000, 0x10000):
                self.reject({field: address}, field + " must remain fixed")
        self.reject({"CORE_CONTEXT_BOOT_SP": 0x3FFF}, "must remain fixed")
        self.reject({"CORE_CONTEXT_TMP_BOTTOM": 0x3FFF, "CORE_CONTEXT_TMP_TOP": 0x4010}, "must remain fixed")
        self.reject({"CORE_CONTEXT_TMP_TOP": 0x2105}, "temporary stack too small")
        self.reject({"CORE_CONTEXT_CODE_BASE": 0x4000, "CORE_CONTEXT_CODE_END": 0x5000}, "must remain fixed")
        self.reject({"CORE_CONTEXT_CODE_END": 0xA010}, "image exceeds fixed allocation")
        self.reject({"CORE_CONTEXT_BANK": 0x2007}, "overlaps")
        self.reject({"CORE_CONTEXT_TMP_BOTTOM": 0x2000}, "overlaps")
        self.reject({"CORE_CONTEXT_CODE_BASE": 0x2000, "CORE_CONTEXT_CODE_END": 0x3000}, "overlaps")

    def reject(self, overrides, reason):
        with self.subTest(overrides=overrides):
            result, binary, _ = self.assemble(overrides=overrides)
            self.assertIsNone(binary)
            self.assertIn(reason, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
