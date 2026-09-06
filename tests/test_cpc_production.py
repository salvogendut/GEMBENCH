from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from build_cpc_production import VARIANTS, assemble, memory_regions, symbols
from test_cpc_production_1984 import verify

RASM = shutil.which(os.environ.get("RASM", "rasm"))


class ProductionSourceTests(unittest.TestCase):
    def test_common_hardware_leaves_have_one_source(self):
        for wrapper, leaf in (("bank.asm", "bank.asm"), ("graphics_driver.asm", "graphics.asm"),
                              ("storage_driver.asm", "m4.asm")):
            code = (ROOT / "debug/cpc_foundation" / wrapper).read_text()
            statements = [line.strip() for line in code.splitlines()
                          if line.strip() and not line.lstrip().startswith(";")]
            self.assertEqual(statements, [f'include "../../lib/cpc/{leaf}"'])
            self.assertTrue((ROOT / "lib/cpc" / leaf).is_file())

    def test_context_and_visibility_are_shared_policy(self):
        code = (ROOT / "kernel/cpc_scheduler.asm").read_text()
        includes = re.findall(r'include "core/([^\"]+)"', code)
        self.assertEqual(includes, ["context_contract.inc", "context_init.asm", "context_save.asm",
                                   "worker_select.asm", "context_restore.asm", "context_tasks.asm",
                                   "visibility_prepare.asm", "visible_regions.asm",
                                   "window_visibility.asm", "context_irq.asm"])
        for name in ("cpc_context.inc", "cpc_visibility.inc", "cpc_scheduler.asm"):
            self.assertNotRegex((ROOT / "kernel" / name).read_text(), r"\bMSX_[A-Z_]+")
        # A production-address fixture is not authority to restore a second WM.
        self.assertNotIn("wm_create", code)


@unittest.skipUnless(RASM, "RASM required for production-address CPC adapter assembly")
class ProductionAssemblyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="geobench-cpc-production-unit-")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.root = Path(cls.temporary.name)
        cls.maps = {variant: assemble(cls.root / variant, variant) for variant in VARIANTS}

    def test_exact_allocations_and_linked_budgets(self):
        for variant, sym in self.maps.items():
            with self.subTest(variant=variant):
                work = self.root / variant
                regions = memory_regions(sym)
                self.assertEqual(sum(r["end"]-r["base"] for r in regions), 65536)
                self.assertEqual([(r["base"], r["end"]) for r in regions if r["name"] == "screen"],
                                 [(0xC000, 0x10000)])
                self.assertEqual(sym["cpc_pool_pages"], 28)
                self.assertEqual(sym["core_context_snapshot"], 0x7F00)
                self.assertEqual(sym["core_context_quantum_ticks"], 6)
                for file, begin, end, limit in (
                    ("SCHED.RAW", "cpc_scheduler_begin", "cpc_scheduler_end", "cpc_sched_end"),
                    ("HARDWARE.RAW", "cpc_hardware_begin", "cpc_hardware_used_end", "cpc_hardware_end"),
                    ("CORE.RAW", "cpc_kernel_begin", "cpc_kernel_used_end", "cpc_kernel_end"),
                ):
                    self.assertEqual(len((work / file).read_bytes()), sym[end]-sym[begin])
                    self.assertLessEqual(sym[end], sym[limit])
                self.assertLessEqual(len((work / "LOADER.RAW").read_bytes()), 0x300)
                self.assertLessEqual(len((work / "BOOT.RAW").read_bytes()), 0x1A00)
                loader = symbols(work / "loader.sym")
                boot = symbols(work / "boot.sym")
                for name in ("storage_gate", "foundation_bank_set", "storage_send"):
                    self.assertEqual(sym[name], loader[name])
                    self.assertEqual(sym[name], boot[name])
        normal = (self.root / "normal/CORE.RAW").read_bytes()
        padded = (self.root / "full-slot/CORE.RAW").read_bytes()
        self.assertEqual(len(padded), 16384)
        self.assertEqual(padded, normal+b"\xB9"*(16384-len(normal)))

    def test_linked_outputs_reassemble_identically(self):
        again = self.root / "again"
        assemble(again)
        for file in ("CORE.RAW", "SCHED.RAW", "HARDWARE.RAW", "LOADER.RAW", "BOOT.RAW"):
            self.assertEqual((again / file).read_bytes(), (self.root / "normal" / file).read_bytes())

    def test_unsafe_maps_and_overflow_rejected(self):
        for index, (option, message) in enumerate((
            ("CPC_SCHED_BASE=10240", "architecture/scheduler overlap"),  # 2800
            ("CPC_SCHED_BASE=11776", "CPC scheduler exceeds fixed allocation"),  # 2E00
            ("CPC_MAIN_STACK=13568", "staging/main stack overlap"),  # 3500
            ("CPC_IRQ_STACK=13840", "main/IRQ stack overlap"),  # 3610
            ("CPC_KERNEL_END=49408", "kernel/framebuffer overlap"),  # C100
            ("CPC_KERNEL_END=32896", "CPC kernel allocation overflow"),  # 8080
        )):
            work = self.root / f"invalid-{index}"
            work.mkdir()
            result = subprocess.run([RASM, str(ROOT / "kernel/cpc_adapter_image.asm"),
                                     "-o", "invalid", "-D"+option], cwd=work,
                                    capture_output=True, text=True)
            with self.subTest(option=option):
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stdout+result.stderr)

    def test_host_map_checker_rejects_gaps_and_overlays(self):
        sym = self.maps["normal"]
        for key, value in (("cpc_support_base", 0x401), ("cpc_adapter_state_end", 0x2100),
                           ("cpc_kernel_end", 0xC001), ("cpc_screen_end", 0xFFFF),
                           ("cpc_main_stack", 0x3500)):
            with self.subTest(key=key), self.assertRaises(ValueError):
                memory_regions({**sym, key: value})
        # A contiguous but displaced framebuffer may not legitimize code in VRAM.
        with self.assertRaisesRegex(ValueError, "framebuffer"):
            memory_regions({**sym, "cpc_kernel_end": 0xC100, "cpc_screen_base": 0xC100})

    def test_runtime_checker_rejects_mutations(self):
        # This synthetic SNA tests the HOST checker, not execution evidence.
        # Actual boot/IRQ/bank/input/M4 execution is the separate 1984 runner.
        work, sym = self.root / "normal", self.maps["normal"]
        header, ram = bytearray(256), bytearray(512*1024)
        header[:8] = b"MV - SNA"
        header[0x10], header[0x40], header[0x25] = 3, 0x0D, 1
        header[0x6B:0x6D] = (512).to_bytes(2, "little")
        header[0x21:0x23] = sym["cpc_main_top"].to_bytes(2, "little")
        ram[sym["cpc_result"]:sym["cpc_result"]+6] = b"CPR3D\x01"
        def byte(name, value): ram[sym[name]] = value
        def word(name, value): ram[sym[name]:sym[name]+2] = value.to_bytes(2, "little")
        for name, value in (("cpc_phase", 0xA5), ("bank_cur", 0xC0), ("wm_nwin", 2),
                            ("wm_focus", 1), ("sched_runnable", 2), ("sched_lock", 1),
                            ("cpc_wm_visibility", 1), ("sched_stack_max", 26)):
            byte(name, value)
        ram[sym["cpc_wm_visibility"]+1] = ram[sym["cpc_task_visibility"]+1] = 3
        for name, value in (("cpc_root_turns", 64), ("cpc_io_checks", 64),
                            ("cpc_irq_count", 926), ("cpc_hw_ticks", 926),
                            ("cpc_hw_seconds", 3), ("cpc_hw_divider", 274),
                            ("cpc_final_sp", sym["cpc_main_top"])):
            word(name, value)
        core = (work / "CORE.RAW").read_bytes()
        word("command_count", 1+4*((len(core)+127)//128)+64*4)
        for stem, used in (("main", 26), ("irq", 4), ("tmp", 6)):
            start, end = sym[f"cpc_{stem}_stack"], sym[f"cpc_{stem}_top"]
            ram[start-16:end+16] = b"\xD7"*(end-start+32)
            ram[start:end] = b"\xA6"*(end-start-used)+b"\x55"*used
        for file, base in (("SCHED.RAW", "cpc_sched_base"), ("HARDWARE.RAW", "cpc_hardware_base"),
                           ("CORE.RAW", "cpc_kernel_base"), ("LOADER.RAW", "cpc_loader_base")):
            code = (work / file).read_bytes()
            ram[sym[base]:sym[base]+len(code)] = code
        ram[0xC000:0x10000] = bytes((a>>8) ^ (a&255) for a in range(0xC000, 0x10000))
        ram[0x4340:0x4380] = bytes(range(64, 0, -1))
        worker = core[sym["worker_code"]-0x8000:sym["worker_code_end"]-0x8000]
        ram[0x10000:0x10000+len(worker)] = worker
        ram[0x7F00], ram[0x13F00] = 24, 26
        self.assertEqual(verify(bytes(header+ram), sym, work)["root_turns"], 64)
        for address, message in ((sym["cpc_result"], "did not boot"),
                                 (sym["cpc_root_turns"], "rounds"),
                                 (sym["cpc_irq_count"], "accounting"),
                                 (sym["cpc_hw_seconds"], "divider"),
                                 (sym["cpc_wm_visibility"], "visibility"),
                                 (sym["io_busy"], "unfinished"),
                                 (sym["command_count"], "command count"),
                                 (sym["bank_cur"], "bank/ROM"),
                                 (sym["cpc_final_sp"], "unbalanced"),
                                 (sym["cpc_main_stack"]-1, "guard damaged"),
                                 (sym["cpc_irq_top"], "guard damaged"),
                                 (sym["cpc_tmp_top"], "guard damaged"),
                                 (sym["cpc_hardware_base"], "code changed"),
                                 (sym["cpc_sched_base"], "code changed"),
                                 (0x10000, "worker code"), (0x13F00, "snapshots"),
                                 (0x4340, "M4 returned"),
                                 (0xC030, "framebuffer"), (0xFFFF, "framebuffer")):
            with self.subTest(address=address):
                damaged = bytearray(ram)
                damaged[address] ^= 1
                with self.assertRaisesRegex(AssertionError, message):
                    verify(bytes(header+damaged), sym, work)
        for offset, value, message in ((0x1B, 1, "IFF/IM"), (0x25, 2, "IFF/IM"),
                                       (0x41, 4, "bank/ROM"), (0x21, 0, "unbalanced")):
            damaged = bytearray(header)
            damaged[offset] = value
            with self.subTest(offset=offset), self.assertRaisesRegex(AssertionError, message):
                verify(bytes(damaged+ram), sym, work)
        ram[sym["cpc_key_observed"]] = 0xFF
        with self.assertRaisesRegex(AssertionError, "Right key"):
            verify(bytes(header+ram), sym, work)


if __name__ == "__main__":
    unittest.main()
