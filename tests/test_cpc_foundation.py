from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from build_cpc_foundation import headed
from test_cpc_foundation_1984 import snapshot, symbols, verify

RASM = shutil.which(os.environ.get("RASM", "rasm"))


class HeaderTests(unittest.TestCase):
    def test_amsdos_header(self) -> None:
        raw = b"\xC3\x00\x80"
        data = headed(raw, 0x8000)
        self.assertEqual(data[1:12], b"FOUND   BIN")
        self.assertEqual(data[18], 2)
        self.assertEqual(data[21:23], b"\x00\x80")
        self.assertEqual(data[26:28], b"\x00\x80")
        self.assertEqual(int.from_bytes(data[64:67], "little"), len(raw))
        self.assertEqual(int.from_bytes(data[67:69], "little"), sum(data[:67]))
        self.assertEqual(data[128:], raw)

    def test_unloadable_binary_rejected(self) -> None:
        for raw, address in ((b"", 0x8000), (b"123", 0xFFFF), (b"1", -1)):
            with self.assertRaises(ValueError):
                headed(raw, address)

    def test_incomplete_snapshot_rejected(self) -> None:
        for value in (b"", b"MV - SNA" + bytes(248)):
            with self.assertRaises(AssertionError):
                snapshot(value)


@unittest.skipUnless(RASM, "RASM is required for CPC diagnostic assembly")
class FoundationTests(unittest.TestCase):
    @staticmethod
    def assemble(overrides: dict[str, int] | None = None
                 ) -> tuple[str, bytes | None, dict[str, int]]:
        with tempfile.TemporaryDirectory(prefix="geobench-cpc-asm-") as tmp:
            command = [RASM, str(ROOT / "debug/cpc_foundation/probe.asm"),
                       "-s", "-sq", "-o", "foundation"]
            command += [f"-D{key}={value}" for key, value in (overrides or {}).items()]
            result = subprocess.run(command, cwd=tmp, capture_output=True, text=True)
            binary, table = Path(tmp) / "FOUND.RAW", Path(tmp) / "foundation.sym"
            return (result.stdout + result.stderr,
                    binary.read_bytes() if binary.exists() else None,
                    symbols(table) if table.exists() else {})

    def test_map_and_fault_fixtures_assemble(self) -> None:
        for fault in (None, "FAULT_RESTORE", "FAULT_REGISTER", "FAULT_STACK"):
            output, raw, sym = self.assemble({fault: 1} if fault else None)
            self.assertIsNotNone(raw, output)
            self.assertEqual(len(raw), sym["probe_end"] - sym["probe_start"])
            self.assertEqual(sym["page_count"], 29)
            self.assertLess(sym["code_end"], sym["state_start"])
            self.assertLess(sym["probe_end"], 0xA000)

    def test_unsafe_maps_rejected(self) -> None:
        for override, message in (
            ({"FOUNDATION_ORG": 0x4000}, "code must be fixed RAM"),
            ({"FOUNDATION_STATE": 0x8001}, "probe code/state overlap"),
            ({"FOUNDATION_STATE": 0xC000}, "state/IRQ stack overlap"),
            ({"FOUNDATION_IRQ_STACK": 0x4000}, "state/IRQ stack overlap"),
            ({"FOUNDATION_MAIN_STACK": 0x9B00}, "stack overlap"),
            ({"FOUNDATION_MAIN_STACK": 0xBF00}, "firmware workspace"),
        ):
            with self.subTest(override=override):
                output, raw, _ = self.assemble(override)
                self.assertIsNone(raw, output)
                self.assertIn(message, output)

    def test_result_checker_requires_data_not_just_pass_flag(self) -> None:
        # Synthetic snapshot tests the HOST checker, not CPC execution.
        # Runtime evidence is produced separately by the real M4/1984 harness.
        output, raw, sym = self.assemble()
        self.assertIsNotNone(raw, output)
        header = bytearray(256)
        header[:8] = b"MV - SNA"
        header[0x10] = 3
        header[0x6B:0x6D] = (512).to_bytes(2, "little")
        header[0x40] = 0x0D
        header[0x25] = 1
        header[0x21:0x23] = sym["main_stack_top"].to_bytes(2, "little")
        ram = bytearray(512 * 1024)
        ram[0x8000:0x8000 + len(raw)] = raw
        def word(name: str, value: int) -> None:
            ram[sym[name]:sym[name] + 2] = value.to_bytes(2, "little")
        ram[sym["phase"]] = 0xA5
        ram[sym["rounds_done"]] = 50
        word("page_checks", 1450)
        word("irq_count", 1450)
        word("final_sp", sym["main_stack_top"])
        ram[sym["irq_per_page"]:sym["irq_per_page"] + 29] = bytes([50]) * 29
        ram[sym["observed"]:sym["observed"] + 20] = ram[
            sym["expected_registers"]:sym["expected_registers"] + 20]
        for stem, count in (("main", 4), ("irq", 24)):
            word(f"{stem}_stack_used", count)
            top = sym[f"{stem}_stack_top"]
            ram[top - count:top] = b"\xA7" * count
        tags = [0xC0] + [0xC4 + g * 8 + b for g in range(7) for b in range(4)]
        for index, tag in enumerate(tags):
            base = 0x4000 if index == 0 else 0x10000 + (index - 1) * 0x4000
            ram[base:base + 0x4000] = bytes(tag ^ (a >> 8) ^ (a & 255)
                                          for a in range(0x4000, 0x8000))
        ram[0xC000:0x10000] = bytes((a >> 8) ^ (a & 255) for a in range(0xC000, 0x10000))
        self.assertEqual(verify(bytes(header + ram), sym, raw)["interrupts"], 1450)
        for address, message in (
            (sym["page_checks"], "incomplete bank"),
            (sym["irq_per_page"] + 28, "coverage"),
            (sym["irq_guard_low"], "guard damaged"),
            (sym["main_guard_high"], "guard damaged"),
            (sym["observed"], "register/flag"),
            (0x8010, "probe code changed"),
            (0x70023, "physical page"),
            (0xC030, "framebuffer"),
            (0xFFFF, "framebuffer"),
        ):
            with self.subTest(address=address):
                damaged = bytearray(ram)
                damaged[address] ^= 1
                with self.assertRaisesRegex(AssertionError, message):
                    verify(bytes(header + damaged), sym, raw)


if __name__ == "__main__":
    unittest.main()
