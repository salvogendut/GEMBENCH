from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from build_cpc_production import VARIANTS, assemble, memory_regions, symbols
from test_cpc_production_1984 import verify
from cpc_production_drawing import DRAWING_VARIANTS, cases, expected_frames, verify_drawing
from cpc_graphics_fixture import address
from cpc_production_windows import (WINDOW_VARIANTS, cases as window_cases,
    expected_frames as window_frames, verify_windows, NATIVES)

RASM = shutil.which(os.environ.get("RASM", "rasm"))


class ProductionSourceTests(unittest.TestCase):
    def test_window_integration_uses_shared_policy_and_software_pointer(self):
        code = (ROOT / "kernel/cpc_window_policy.asm").read_text()
        self.assertEqual(re.findall(r'include "core/([^\"]+)"', code), [
            "window_hit_test.asm", "window_focus_click.asm", "window_focus_map.asm",
            "window_raise.asm", "window_zorder.asm", "window_damage.asm",
            "window_focus_damage.asm", "window_geometry.asm", "window_repaint.asm"])
        provider = (ROOT / "kernel/cpc_window_provider.inc").read_text()
        self.assertIn("CORE_REPAINT_ERASE_POINTER equ 1", provider)
        self.assertIn("CORE_REPAINT_REGIONS equ 1", provider)
        self.assertNotIn("MSX_", provider)
        adapter = (ROOT / "lib/cpc/window.asm").read_text()
        self.assertEqual(adapter.count("call clip_axis"), 2)
        self.assertEqual(adapter.count("ld a,(CORE_POINTER_PAINTLOCK)"), 2)

    def test_window_oracle_tracks_only_effective_damage(self):
        frames = {f["name"]: f for f in window_frames()}
        self.assertEqual(len(frames), 16)
        self.assertEqual(frames["initial"]["writes"][4], 0)  # completely covered
        self.assertEqual(frames["same-focus"]["writes"], [0]*5)
        self.assertEqual(frames["no-hit"]["writes"], [0]*5)
        self.assertEqual(frames["empty-damage"]["writes"], [0]*5)
        self.assertEqual(frames["tiny-damage"]["writes"], [20,0,0,0,0])
        self.assertEqual(frames["sibling-focus"]["flags"], 0)
        self.assertEqual(frames["cross-page-focus"]["flags"], 1)
        self.assertEqual(frames["return-sibling"]["focus"], 2)
        self.assertEqual(frames["exposed-focus"]["focus"], 4)
        self.assertGreater(frames["move-expose"]["writes"][4], 0)
        gaps = set(range(16384)) - {address(x*4,y) for x in range(80) for y in range(200)}
        for f in frames.values():
            for offset in gaps:
                self.assertEqual(f["frame"][offset], ((offset+0xC000)>>8) ^ (offset&255))

    def test_common_hardware_leaves_have_one_source(self):
        for wrapper, leaf in (("bank.asm", "bank.asm"), ("graphics_driver.asm", "graphics.asm"),
                              ("storage_driver.asm", "m4.asm"), ("graphics_gate.asm", "graphics_gate.asm")):
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

    def test_drawing_uses_shared_identity_and_parameter_policy(self):
        code = (ROOT / "kernel/cpc_support.asm").read_text()
        for name in ("page_count", "owner_identity", "page_pool", "app_code",
                     "window_identity", "owner_context", "parameters"):
            self.assertEqual(code.count(f'include "core/{name}.asm"'), 1)
        provider = (ROOT / "kernel/cpc_parameter_provider.inc").read_text()
        self.assertNotIn("MSX_", provider)
        self.assertIn("PARAM_CURRENT_OWNER equ owner_current", provider)
        self.assertIn("jp window_validate_owned", code)
        renderer = (ROOT / "lib/cpc/text.asm").read_text()
        self.assertNotIn("equ   #14", renderer)
        self.assertIn("call cpc_byte_visible", renderer)
        self.assertIn("ld hl,font_last", renderer)

    def test_drawing_oracle_clips_bytes_and_covers_gap_bytes(self):
        frames, _ = expected_frames()
        named = dict(frames)
        self.assertEqual(len(frames), 26)
        self.assertLessEqual(len(cases()), 64)
        gaps = set(range(16384)) - {address(x*4,y) for x in range(80) for y in range(200)}
        self.assertEqual(len(gaps), 384)
        for _, frame in frames:
            for offset in gaps:
                self.assertEqual(frame[offset], ((offset+0xC000)>>8) ^ (offset&255))
        before, after = named["point"], named["clipped-line"]
        changed = {i for i, (a,b) in enumerate(zip(before,after)) if a != b}
        allowed = {address(x*4,y) for x in range(13,43) for y in range(22,62)}
        self.assertTrue(changed)
        self.assertLessEqual(changed, allowed)
        self.assertEqual(named["clipped-line"], named["empty-clip-line"])
        before, after = named["text-pointer-hide"], named["partial-glyph-clip"]
        changed = {i for i, (a,b) in enumerate(zip(before,after)) if a != b}
        self.assertTrue(changed)
        self.assertLessEqual(changed, {address(x*4,y) for x in range(10,17) for y in range(58,61)})


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

    def test_window_link_budgets_guards_and_determinism(self):
        for variant in WINDOW_VARIANTS:
            sym = self.maps[variant]
            self.assertLess(sym["cpc_window_policy_end"]-sym["cpc_window_policy_begin"], 1024)
            self.assertLessEqual(sym["cpc_draw_trace_end"], sym["cpc_wm_guard"])
            self.assertLessEqual(sym["cpc_wm_end"]+16, sym["cpc_future_state_end"])
            self.assertLessEqual(sym["cpc_wm_trace"]+32*len(window_cases()), sym["cpc_wm_trace_end"])
            self.assertLessEqual(sym["cpc_wm_trace_end"], sym["cpc_adapter_state_end"])
        again = self.root / "windows-again"
        assemble(again, "windows")
        for file in ("CORE.RAW", "SUPPORT.RAW", "SCHED.RAW", "BOOT.RAW"):
            self.assertEqual((again / file).read_bytes(), (self.root / "windows" / file).read_bytes())

    def test_window_checker_rejects_pixels_overdraw_callback_and_state_faults(self):
        # Synthetic HOST checker test only; M4 runner supplies execution evidence.
        sym, work = self.maps["windows"], self.root / "windows"
        ram = bytearray(512*1024)
        frames = window_frames()
        ram[sym["wm_fixture_done"]] = ram[sym["draw_capture_count"]] = len(frames)
        for i, f in enumerate(frames):
            ram[0x14000+i*16384:0x14000+(i+1)*16384] = f["frame"]
            focus, order = f["focus"], f["order"]
            trace = struct.pack("<5H", *f["writes"]) + bytes(bool(v) for v in f["writes"])
            trace += bytes((focus,f["flags"],*order,*([0]*(5-len(order))),NATIVES[focus]))
            trace += struct.pack("<HHBHH",0x4500+focus*16,0 if not focus else 0x4600+focus*16,
                                 len(order),f["saves"],f["restores"])
            ram[sym["cpc_wm_trace"]+32*i:sym["cpc_wm_trace"]+32*(i+1)] = trace
        ram[0xC000:0x10000] = frames[-1]["frame"]
        for name in ("cpc_wm_guard","cpc_wm_end","cpc_draw_state_guard","cpc_draw_state_end"):
            ram[sym[name]:sym[name]+16] = b"\xD7"*16
        ram[sym["pointer_visible"]] = 1
        ram[sym["core_clip_x"]:sym["core_clip_x"]+4] = bytes((0,0,80,200))
        raw = (work / "SUPPORT.RAW").read_bytes()
        ram[sym["cpc_support_base"]:sym["cpc_support_base"]+len(raw)] = raw
        font = (work / "DEFAULT.FNT").read_bytes()
        ram[0x7C000:0x80000] = font+b"\xA9"*(16384-len(font))
        ram[sym["core_page_total"]], ram[sym["core_page_free"]] = 28,10
        for name, values in (("core_page_state", [1]*18), ("core_page_gen", [1]*18),
                             ("core_page_owner", [1,2]+[1]*16), ("core_page_owner_gen", [1]*18),
                             ("core_page_purpose", [1,1]+[6]*16)):
            ram[sym[name]:sym[name]+32] = bytes(values+[0]*14)
        ram[0x10202] = 2
        ram[sym["draw_irq_total"]] = 1
        self.assertEqual(verify_windows(ram,sym,work)["window_checkpoints"],16)
        for at, message in ((0x14000,"pixels"),(sym["cpc_wm_trace"],"damage writes"),
                            (sym["cpc_wm_trace"]+14,"callback visibility"),
                            (sym["cpc_wm_trace"]+15,"focus/z-order"),
                            (sym["cpc_wm_trace"]+22,"mapping/menu"),
                            (sym["cpc_wm_trace"]+28,"pointer pass lock"),
                            (sym["cpc_wm_end"],"guard"),(sym["core_pointer_paintlock"],"pointer state"),
                            (sym["core_clip_x"],"full clip"),(sym["universal_parameters"],"SUPPORT.RAW"),
                            (sym["core_page_owner"],"metadata"),(sym["core_page_free"],"accounting"),
                            (0x7C020,"font/service"),(0x10202,"actual worker"),
                            (0x10200,"worker ran"),
                            (sym["draw_irq_total"],"IRQ coverage")):
            damaged = bytearray(ram)
            damaged[at] ^= 1
            with self.subTest(at=at), self.assertRaisesRegex(AssertionError,message):
                verify_windows(damaged,sym,work)

    def test_drawing_sections_and_profile_are_bounded(self):
        for variant in DRAWING_VARIANTS:
            sym, work = self.maps[variant], self.root / variant
            raw = (work / "SUPPORT.RAW").read_bytes()
            self.assertEqual(len(raw), sym["cpc_support_used_end"]-sym["cpc_support_base"])
            self.assertLessEqual(sym["cpc_support_used_end"], sym["cpc_support_end"])
            self.assertLessEqual(sym["cpc_draw_state_end"]+16, sym["cpc_draw_trace"])
            self.assertLessEqual(sym["cpc_draw_trace_end"], sym["cpc_future_state_end"])
            self.assertEqual(sym["core_param_app_native"], sym["core_app_code_native"])
            self.assertEqual(sym["core_param_width"], 320)
            self.assertEqual(sym["core_param_columns"], 80)
            self.assertEqual(sym["core_param_height"], 200)
            self.assertLess(sym["universal_parameters"], 0x4000)
            self.assertEqual((work / "DEFAULT.FNT").read_bytes()[:10], b"GBFN\1\x20\x83\6\10\1")
            for name in ("core_page_native", "core_owner_active", "core_app_code_native", "core_win_gen"):
                self.assertTrue(0x2000 <= sym[name] < 0x2900)
        again = self.root / "drawing-again"
        assemble(again, "drawing")
        for file in ("CORE.RAW", "SUPPORT.RAW", "BOOT.RAW"):
            self.assertEqual((again / file).read_bytes(), (self.root / "drawing" / file).read_bytes())

    def test_drawing_checker_rejects_corrupt_pixels_state_and_code(self):
        # Host-only synthetic observation: real execution is the M4 runner.
        sym, work = self.maps["drawing"], self.root / "drawing"
        ram = bytearray(512*1024)
        frames, saved = expected_frames()
        def byte(name, value): ram[sym[name]] = value
        def word(name, value): ram[sym[name]:sym[name]+2] = value.to_bytes(2,"little")
        byte("draw_case_count_done", len(cases()))
        byte("draw_capture_count", len(frames))
        for i, (_, frame) in enumerate(frames):
            ram[0x14000+i*16384:0x14000+(i+1)*16384] = frame
        ram[0xC000:0x10000] = frames[-1][1]
        ram[0x4100:0x4100+len(saved)] = saved
        raw = (work / "SUPPORT.RAW").read_bytes()
        ram[sym["cpc_support_base"]:sym["cpc_support_base"]+len(raw)] = raw
        for at in (sym["cpc_draw_state_guard"], sym["cpc_draw_state_end"]):
            ram[at:at+16] = b"\xD7"*16
        font = (work / "DEFAULT.FNT").read_bytes()
        ram[0x7C000:0x80000] = font+b"\xA9"*(16384-len(font))
        byte("core_page_total",28)
        byte("core_page_free",26-len(frames))
        for name, values in (("core_page_state",[1]*28), ("core_page_gen",[1]*28),
                             ("core_page_owner",[1,2]+[1]*26), ("core_page_owner_gen",[1]*28),
                             ("core_page_purpose",[1,1]+[6]*26)):
            ram[sym[name]:sym[name]+32] = bytes(values+[0]*4)
        word("draw_root_owner",0x0101)
        word("draw_worker_owner",0x0102)
        ram[sym["core_win_gen"]:sym["core_win_gen"]+2] = b"\1\1"
        ram[sym["core_app_code_native"]:sym["core_app_code_native"]+2] = b"\xC0\xC4"
        ram[0x10202] = 2
        word("draw_irq_total",1)
        for name, trace in (("phase-3",(4,3)), ("draw-under-pointer",(5,4)),
                            ("empty-clip-line",(6,6)), ("text-under-pointer",(8,7))):
            index = [n for n, _ in frames].index(name)
            at = sym["cpc_draw_trace"]+index*4
            ram[at:at+4] = struct.pack("<HH",*trace)
        self.assertEqual(verify_drawing(ram,sym,work)["drawing_cases"], len(cases()))
        for at, message in ((0x14000+0x7FF,"drawing checkpoint"), (0xFFFF,"final framebuffer"),
                            (0x4100,"canonical"), (sym["universal_parameters"],"SUPPORT.RAW"),
                            (sym["cpc_draw_state_end"],"guard"), (0x7C015,"font/service"),
                            (sym["core_page_free"],"accounting"), (sym["core_win_gen"],"generations"),
                            (0x10202,"actual worker"), (sym["core_param_timer_owner"],"timer"),
                            (sym["core_page_owner"],"metadata"), (sym["draw_irq_total"],"no interrupts"),
                            (sym["draw_root_owner"],"owner allocation")):
            damaged = bytearray(ram)
            damaged[at] ^= 1
            with self.subTest(at=at), self.assertRaisesRegex(AssertionError,message):
                verify_drawing(damaged,sym,work)

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
