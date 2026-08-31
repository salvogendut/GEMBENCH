from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from tools import gembench_baseline as baseline


def seed_architecture(
    memory: bytearray, *, memory_pages: int = 32, pool_pages: int = 8, free_pages: int = 7
) -> None:
    def put(address: int, value: int) -> None:
        memory[address - baseline.GLUE_DUMP_START] = value & 0xFF

    def put_word(address: int, value: int) -> None:
        put(address, value)
        put(address + 1, value >> 8)

    put(baseline.MSX_PAGE_TOTAL, pool_pages)
    put(baseline.MSX_PAGE_FREE, free_pages)
    put(baseline.MSX_SYSINFO, baseline.MSX_SYSINFO_SIZE)
    put(baseline.MSX_SYSINFO + 1, 6)
    put(baseline.MSX_SYSINFO + 2, 1)
    put(baseline.MSX_SYSINFO + 4, 1)
    put(baseline.MSX_SYSINFO + 5, 7)
    put_word(baseline.MSX_SYSINFO + 6, 512)
    put_word(baseline.MSX_SYSINFO + 8, 212)
    put(baseline.MSX_SYSINFO + 10, 4)
    put(baseline.MSX_SYSINFO + 11, 16)
    put(baseline.MSX_SYSINFO + 12, memory_pages)
    put(baseline.MSX_SYSINFO + 13, pool_pages)
    put(baseline.MSX_SYSINFO + 14, free_pages)
    put(baseline.MSX_SYSINFO + 15, baseline.WM_MAXWIN)
    put_word(baseline.MSX_SYSINFO + 16, baseline.MSX_M7_REQUIRED_CAPABILITIES)
    put(baseline.MSX_SYSINFO + 20, 8)
    put(baseline.MSX_SYSINFO + 21, 1)
    put(baseline.MSX_SYSINFO + 22, baseline.WM_MAXWIN)
    put(baseline.MSX_SYSINFO + 24, 8)
    put(baseline.MSX_SYSINFO + 25, 4)
    put(baseline.MSX_SYSINFO + 26, 1)
    put(baseline.MSX_SYSINFO + 28, 4)
    put_word(baseline.MSX_SYSINFO + 29, 512)
    put(baseline.MSX_SYSINFO + 31, 1)
    put_word(baseline.MSX_SYSINFO + 32, 0x000F)
    put(baseline.MSX_SYSINFO + 34, 128)
    put(baseline.MSX_SYSINFO + 35, 212)
    put(baseline.MSX_SYSINFO + 36, 4)
    put(baseline.MSX_SYSINFO + 37, 4)
    put_word(baseline.MSX_SYSINFO + 38, baseline.APP_BANK_START)
    put_word(baseline.MSX_SYSINFO + 40, baseline.APP_LOAD_LIMIT)
    put_word(baseline.MSX_SYSINFO + 42, 0x8000)
    put(baseline.MSX_SYSINFO + 44, 2)
    put(baseline.MSX_SYSINFO + 46, 3)


class BaselineTests(unittest.TestCase):
    def make_tree(self, root: Path) -> None:
        card = root / "QA" / "MSX" / "CARD"
        apps = card / "GBENCH"
        apps.mkdir(parents=True)
        (card / "GEOBENCH.CFG").write_text("MSXMOUSE=TRUE\nMSXMODE=7\n", encoding="ascii")
        (apps / "SMALL.APP").write_bytes(b"a" * 100)
        (apps / "LARGE.APP").write_bytes(b"b" * 16000)
        (card / "GBMSX7.COM").write_bytes(b"kernel")

    def test_static_report_records_headroom_and_screen_mode(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_tree(root)
            report = baseline.collect_report(root)

        static = report["static"]
        self.assertEqual(static["target"]["screen_mode"], 7)
        apps = {app["name"]: app for app in static["applications"]}
        self.assertEqual(apps["SMALL"]["load_headroom_bytes"], 16028)
        self.assertEqual(apps["LARGE"]["load_headroom_bytes"], 128)
        self.assertEqual(static["vram_model"]["screen7_framebuffer_bytes"], 54272)
        self.assertEqual(static["vram_model"]["persistent_pointer_resource_bytes"], 105)

    def test_runtime_parser_reads_1983_state_and_low_ram(self) -> None:
        memory = bytearray(baseline.GLUE_DUMP_LENGTH)
        seed_architecture(memory)

        def put(address: int, value: int) -> None:
            memory[address - baseline.GLUE_DUMP_START] = value

        put(baseline.MSX_TPASEG, 3)
        put(baseline.MSX_TOTSEG, 32)
        put(baseline.MSX_FREESEG, 28)
        put(baseline.MSX_PAGE_DATA, 4)
        lines = []
        for offset in range(0, len(memory), 16):
            chunk = memory[offset : offset + 16]
            lines.append(
                f"{baseline.GLUE_DUMP_START + offset:04X}: "
                + " ".join(f"{value:02X}" for value in chunk)
            )
        lines.append(
            "state frame=6001 pc=247A sp=F100 slot=F0 subslot=00 "
            "mapper=03,04,05,06 cycles=429496 instructions=123456 "
            "vram_nonzero=6742 vdp_r0=0A vdp_r1=62"
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "1983.log"
            path.write_text("\n".join(lines) + "\n", encoding="ascii")
            runtime = baseline.collect_runtime(path)

        self.assertEqual(runtime["mapper_total_segments"], 32)
        self.assertEqual(runtime["mapper_free_segments_at_entry"], 28)
        self.assertEqual(runtime["app_pool_pages"], 8)
        self.assertEqual(runtime["idle_busy_app_pages"], 1)
        self.assertEqual(runtime["mapper_segments_held_by_gembench"], 8)
        self.assertTrue(runtime["screen7_register_baseline"])
        self.assertIsNone(runtime["diagnostic_probes"])

    def test_runtime_parser_reads_diagnostic_probes(self) -> None:
        memory = bytearray(baseline.GLUE_DUMP_LENGTH)
        seed_architecture(memory)

        def put(address: int, value: int) -> None:
            memory[address - baseline.GLUE_DUMP_START] = value

        def put_clock(address: int, seconds: int) -> None:
            def bcd(value: int) -> int:
                return (value // 10 << 4) | value % 10

            seconds %= 24 * 60 * 60
            put(address, bcd(seconds % 60))
            put(address + 1, bcd(seconds // 60 % 60))
            put(address + 2, bcd(seconds // 3600))

        put(baseline.MSX_TOTSEG, 32)
        put(baseline.MSX_FREESEG, 25)
        put(baseline.MSX_PAGE_DATA, 4)
        put(baseline.BASELINE_COOKIE, baseline.BASELINE_COOKIE_VALUE)
        put(baseline.BASELINE_PHASE, 4)
        put(baseline.BASELINE_STACK_MAX, 42)
        put(baseline.BASELINE_STACK_FAULT, 0)
        put_clock(baseline.BASELINE_FULL_START, 0)
        put_clock(baseline.BASELINE_FULL_END, 18432)
        put_clock(baseline.BASELINE_DAMAGE_START, 86000)
        put_clock(baseline.BASELINE_DAMAGE_END, 86000 + 1843)
        lines = []
        for offset in range(0, len(memory), 16):
            chunk = memory[offset : offset + 16]
            lines.append(
                f"{baseline.GLUE_DUMP_START + offset:04X}: "
                + " ".join(f"{value:02X}" for value in chunk)
            )
        lines.append(
            "state frame=6001 pc=247A sp=F100 slot=F0 subslot=00 "
            "mapper=03,04,05,06 cycles=429496 instructions=123456 "
            "vram_nonzero=6742 vdp_r0=0A vdp_r1=62"
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "1983.log"
            path.write_text("\n".join(lines) + "\n", encoding="ascii")
            runtime = baseline.collect_runtime(path, require_probes=True)

        probes = runtime["diagnostic_probes"]
        self.assertEqual(probes["scheduler_stack_high_water_bytes"], 42)
        self.assertEqual(probes["full_repaint_ticks"], 18432)
        self.assertEqual(probes["full_repaint_microseconds"], 1125000.0)
        self.assertAlmostEqual(probes["damage_repaint_microseconds"], 112487.79)

    def test_runtime_parser_measures_injected_keyboard_response(self) -> None:
        memory = bytearray(baseline.GLUE_DUMP_LENGTH)
        seed_architecture(memory)

        def put(address: int, value: int) -> None:
            memory[address - baseline.GLUE_DUMP_START] = value

        def put_word(address: int, value: int) -> None:
            put(address, value & 0xFF)
            put(address + 1, value >> 8)

        def put_clock(address: int, seconds: int) -> None:
            def bcd(value: int) -> int:
                return (value // 10 << 4) | value % 10

            put(address, bcd(seconds % 60))
            put(address + 1, bcd(seconds // 60 % 60))
            put(address + 2, bcd(seconds // 3600))

        put(baseline.MSX_TOTSEG, 32)
        put(baseline.MSX_FREESEG, 25)
        put(baseline.MSX_PAGE_DATA, 4)
        put(baseline.BASELINE_COOKIE, baseline.BASELINE_COOKIE_VALUE)
        put(baseline.BASELINE_PHASE, 4)
        put(baseline.BASELINE_STACK_MAX, 32)
        put(baseline.BASELINE_INPUT_FLAGS, 5)
        put(baseline.BASELINE_INPUT_KEY, ord("b"))
        put(baseline.BASELINE_RUNNABLE, 3)
        put_word(baseline.MSX_TICK, 5800)
        put_word(baseline.BASELINE_KEY_ARM, 4700)
        put_word(baseline.BASELINE_KEY_ACK, 4800)
        put_clock(baseline.BASELINE_FULL_START, 0)
        put_clock(baseline.BASELINE_FULL_END, 10)
        put_clock(baseline.BASELINE_DAMAGE_START, 20)
        put_clock(baseline.BASELINE_DAMAGE_END, 25)
        lines = []
        for offset in range(0, len(memory), 16):
            chunk = memory[offset : offset + 16]
            lines.append(
                f"{baseline.GLUE_DUMP_START + offset:04X}: "
                + " ".join(f"{value:02X}" for value in chunk)
            )
        lines.append(
            "state frame=6001 pc=247A sp=F100 slot=F0 subslot=00 "
            "mapper=03,04,05,06 cycles=429496 instructions=123456 "
            "vram_nonzero=6742 vdp_r0=0A vdp_r1=62"
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "1983.log"
            path.write_text("\n".join(lines) + "\n", encoding="ascii")
            runtime = baseline.collect_runtime(
                path,
                require_probes=True,
                require_input_keyboard=True,
                keyboard_injection_frame=5000,
            )

        response = runtime["input_response"]
        self.assertTrue(response["keyboard_acknowledged"])
        self.assertFalse(response["pointer_acknowledged"])
        self.assertEqual(response["keyboard_injection_tick_estimate"], 4799)
        self.assertEqual(response["keyboard_response_frames"], 1)
        self.assertEqual(response["keyboard_response_milliseconds"], 20.0)

    def test_required_diagnostic_probes_are_rejected_when_missing(self) -> None:
        memory = bytearray(baseline.GLUE_DUMP_LENGTH)
        seed_architecture(memory)
        memory[baseline.MSX_TOTSEG - baseline.GLUE_DUMP_START] = 32
        memory[baseline.MSX_FREESEG - baseline.GLUE_DUMP_START] = 25
        memory[baseline.MSX_PAGE_DATA - baseline.GLUE_DUMP_START] = 4
        dump = f"{baseline.GLUE_DUMP_START:04X}: " + " ".join(
            f"{value:02X}" for value in memory
        )
        state = (
            "state frame=6001 pc=247A sp=F100 slot=F0 subslot=00 "
            "mapper=03,04,05,06 cycles=1 instructions=1 "
            "vram_nonzero=6742 vdp_r0=0A vdp_r1=62"
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "1983.log"
            path.write_text(f"{dump}\n{state}\n", encoding="ascii")
            with self.assertRaisesRegex(baseline.BaselineError, "probe cookie"):
                baseline.collect_runtime(path, require_probes=True)

    def test_missing_state_is_rejected(self) -> None:
        with self.assertRaisesRegex(baseline.BaselineError, "no --dump-state"):
            baseline.parse_state("1246: E4 2C\n")

    def test_non_desktop_runtime_is_rejected(self) -> None:
        memory = bytearray(baseline.GLUE_DUMP_LENGTH)
        seed_architecture(memory)
        memory[baseline.MSX_TOTSEG - baseline.GLUE_DUMP_START] = 32
        memory[baseline.MSX_FREESEG - baseline.GLUE_DUMP_START] = 28
        memory[baseline.MSX_PAGE_DATA - baseline.GLUE_DUMP_START] = 4
        lines = []
        for offset in range(0, len(memory), 16):
            chunk = memory[offset : offset + 16]
            lines.append(
                f"{baseline.GLUE_DUMP_START + offset:04X}: "
                + " ".join(f"{value:02X}" for value in chunk)
            )
        lines.append(
            "state frame=6001 pc=0459 sp=F380 slot=FC subslot=AC "
            "mapper=03,02,01,00 cycles=1 instructions=1 "
            "vram_nonzero=7271 vdp_r0=02 vdp_r1=00"
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "1983.log"
            path.write_text("\n".join(lines) + "\n", encoding="ascii")
            with self.assertRaisesRegex(baseline.BaselineError, "healthy GEMBENCH desktop"):
                baseline.collect_runtime(path)

    def test_wrong_mapper_size_is_rejected(self) -> None:
        memory = bytearray(baseline.GLUE_DUMP_LENGTH)
        seed_architecture(memory, memory_pages=16)
        memory[baseline.MSX_TOTSEG - baseline.GLUE_DUMP_START] = 16
        memory[baseline.MSX_FREESEG - baseline.GLUE_DUMP_START] = 12
        memory[baseline.MSX_PAGE_DATA - baseline.GLUE_DUMP_START] = 4
        dump = f"{baseline.GLUE_DUMP_START:04X}: " + " ".join(
            f"{value:02X}" for value in memory
        )
        state = (
            "state frame=6001 pc=247A sp=D8EA slot=FC subslot=AA "
            "mapper=03,02,01,00 cycles=1 instructions=1 "
            "vram_nonzero=6484 vdp_r0=0A vdp_r1=62"
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "1983.log"
            path.write_text(f"{dump}\n{state}\n", encoding="ascii")
            with self.assertRaisesRegex(baseline.BaselineError, "expected 32"):
                baseline.collect_runtime(path)

    def test_markdown_calls_out_uninstrumented_repaint_timing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_tree(root)
            markdown = baseline.render_markdown(baseline.collect_report(root))
        self.assertIn("Status: **not-instrumented**", markdown)
        self.assertIn("Application-bank headroom", markdown)

    def test_markdown_renders_captured_repaint_timing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_tree(root)
            report = baseline.collect_report(root)
        report["runtime"] = {
            "frame": 6001,
            "pc": 0x247A,
            "sp": 0xF100,
            "vdp_r0": 0x0A,
            "vdp_r1": 0x62,
            "screen7_register_baseline": True,
            "tpa_segment": 2,
            "page_data_segment": 4,
            "mapper_segments_held_by_gembench": 8,
            "mapper_total_segments": 32,
            "mapper_free_segments_at_entry": 25,
            "app_pool_pages": 8,
            "free_app_pool_pages": 7,
            "idle_busy_app_pages": 1,
            "sysinfo": None,
            "vram_nonzero_bytes": 6484,
            "diagnostic_probes": {
                "phase": 4,
                "scheduler_stack_high_water_bytes": 42,
                "scheduler_stack_fault": 0,
            },
        }
        report["repaint_timing"] = {
            "status": "captured",
            "timer_hz": baseline.BASELINE_TIMER_HZ,
            "timer": "test timer",
            "full_ticks": 18432,
            "full_microseconds": 1125000.0,
            "damage_ticks": 1843,
            "damage_microseconds": 112487.79,
            "damage_rect": baseline.BASELINE_DAMAGE_RECT,
            "notes": "Diagnostic sample.",
        }
        markdown = baseline.render_markdown(report)
        self.assertIn("Status: **captured**", markdown)
        self.assertIn("Scheduler stack high-water: 42 bytes", markdown)
        self.assertIn("Full desktop: 18,432 ticks (1,125,000.00 us)", markdown)


if __name__ == "__main__":
    unittest.main()
