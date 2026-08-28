from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from tools import gembench_baseline as baseline


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

    def test_missing_state_is_rejected(self) -> None:
        with self.assertRaisesRegex(baseline.BaselineError, "no --dump-state"):
            baseline.parse_state("1246: E4 2C\n")

    def test_non_desktop_runtime_is_rejected(self) -> None:
        memory = bytearray(baseline.GLUE_DUMP_LENGTH)
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
        memory[baseline.MSX_TOTSEG - baseline.GLUE_DUMP_START] = 16
        memory[baseline.MSX_FREESEG - baseline.GLUE_DUMP_START] = 12
        memory[baseline.MSX_PAGE_DATA - baseline.GLUE_DUMP_START] = 4
        dump = "C018: " + " ".join(f"{value:02X}" for value in memory)
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


if __name__ == "__main__":
    unittest.main()
