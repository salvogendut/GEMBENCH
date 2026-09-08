from __future__ import annotations

import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from cpc_storage_fixture import (STORAGE_VARIANTS, INPUT, PAYLOAD, TRACE_START,
                                 TRACE_SIZE, cases, descriptor, emit_vectors,
                                 expected_page, rounds, verify_storage)
from test_cpc_foundation_1984 import symbols

RASM = shutil.which(os.environ.get("RASM", "rasm"))


class StorageVectorTests(unittest.TestCase):
    def test_record_layout_and_boundary_cases(self):
        record = descriptor(offset=0x12345678)
        self.assertEqual(len(record), 16)
        self.assertEqual(record[10:14], b"\x78\x56\x34\x12")
        vectors = {c["name"]: c for c in cases()}
        self.assertEqual(vectors["short-tail"]["expected"], INPUT[250:])
        self.assertEqual(vectors["readback-17"]["expected"], PAYLOAD[:17])
        self.assertEqual(vectors["zero-read"]["commands"], 0)
        self.assertEqual(vectors["create-empty"]["commands"], 2)
        for case in vectors.values():
            page = expected_page(case)
            self.assertEqual(len(page), 16384, case["name"])
            self.assertEqual(page[0x3F00:], b"\x5A"*256, case["name"])
        self.assertEqual(expected_page(vectors["last-buffer"])[0x3E80:0x3F00], INPUT[:128])

    def test_failure_coverage_and_terminal_offline_cases(self):
        vectors = cases()
        self.assertEqual({c["fault"] for c in vectors}, {0, 1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 13})
        self.assertEqual({c["ga"] for c in vectors}, {0x8D, 0x85, 0x8C, 0x84, 0x8E, 0x86, 0x8F})
        for variant in ("storage-close-error", "storage-open-error"):
            terminal = cases(variant)[-2:]
            self.assertEqual(rounds(variant), 1)
            self.assertEqual([c["offline"] for c in terminal], [1, 1])
            self.assertEqual((terminal[-1]["status"], terminal[-1]["commands"]), (7, 0))


@unittest.skipUnless(RASM, "RASM required for CPC storage assembly")
class StorageAssemblyTests(unittest.TestCase):
    @staticmethod
    def assemble(variant="storage", overrides=None):
        with tempfile.TemporaryDirectory(prefix="geobench-cpc-storage-") as tmp:
            emit_vectors(Path(tmp) / "storage_vectors.inc", variant)
            command = [RASM, str(ROOT / "debug/cpc_foundation/storage_probe.asm"),
                       "-s", "-sq", "-o", "foundation", f"-I{tmp}"]
            defs = dict(overrides or {})
            if STORAGE_VARIANTS[variant]:
                defs[STORAGE_VARIANTS[variant]] = 1
            command += [f"-D{k}={v}" for k, v in defs.items()]
            result = subprocess.run(command, cwd=tmp, capture_output=True, text=True)
            raw, table = Path(tmp) / "FOUND.RAW", Path(tmp) / "foundation.sym"
            return (result.stdout + result.stderr, raw.read_bytes() if raw.exists() else None,
                    symbols(table) if table.exists() else {})

    def test_variants_fit_and_reassemble_deterministically(self):
        for variant in STORAGE_VARIANTS:
            output, raw, sym = self.assemble(variant)
            self.assertIsNotNone(raw, output)
            self.assertEqual(raw, self.assemble(variant)[1])
            self.assertEqual(sym["storage_case_count"], len(cases(variant)))
            self.assertLess(sym["code_end"], sym["state_start"])
            self.assertLessEqual(sym["probe_end"], 0xA000)
            self.assertLessEqual(sym["trace_guard_high"]+16, 0x4000)
            self.assertEqual(sym["transfer_guard_high"]-sym["transfer_buffer"], 128)
            self.assertEqual(sym["command_guard_high"]-sym["command_buffer"], 132)
            self.assertEqual(sym["response_guard_high"]-sym["response_buffer"], 136)

    def test_unsafe_memory_maps_rejected(self):
        for override in ({"FOUNDATION_ORG": 0x4000}, {"FOUNDATION_STATE": 0x8400},
                         {"FOUNDATION_MAIN_STACK": 0x9D10}):
            output, raw, _ = self.assemble(overrides=override)
            self.assertIsNone(raw, output)

    def synthetic(self, variant):
        # Host checker fixture, not claimed as emulated Z80 execution.
        output, raw, sym = self.assemble(variant)
        self.assertIsNotNone(raw, output)
        header, ram = bytearray(256), bytearray(512*1024)
        header[0x40], header[0x25], header[0x55] = 0x0D, 1, 7
        header[0x21:0x23] = sym["main_stack_top"].to_bytes(2, "little")
        ram[0x8000:0x8000+len(raw)] = raw
        ram[0x18000:] = b"\xA9"*(len(ram)-0x18000)
        ram[0xC000:0x10000] = bytes((a>>8) ^ (a&255) for a in range(0xC000, 0x10000))
        vectors, count = cases(variant), rounds(variant)
        ram[sym["phase"]], ram[sym["rounds_done"]] = 0xA5, count
        def word(name, value):
            ram[sym[name]:sym[name]+2] = value.to_bytes(2, "little")
        word("request_count", count*len(vectors))
        word("command_count", 1+count*sum(c["commands"] for c in vectors))
        word("irq_count", len(vectors)*(count//2))
        word("final_sp", sym["main_stack_top"])
        for stem, used in (("main", 24), ("irq", 4 if count > 1 else 0)):
            word(f"{stem}_stack_used", used)
            top = sym[f"{stem}_stack_top"]
            ram[top-used:top] = b"\x55"*used
        for name in ("trace_guard_low", "trace_guard_high"):
            ram[sym[name]:sym[name]+16] = b"\xD7"*16
        for i, case in enumerate(vectors):
            row = bytes((case["status"], (count-1)&1, case["bank"], case["ga"],
                         case["slot"], 0, case["offline"], case["busy"]))
            row += struct.pack("<HH", case["actual"], case["commands"])
            page = expected_page(case)
            offset = case["observe"]-0x4000
            row += page[offset:offset+128]+b"\x5A"*4
            start = TRACE_START+i*TRACE_SIZE
            ram[start:start+TRACE_SIZE] = row
            physical = {0xC0: 0x4000, 0xC4: 0x10000, 0xC5: 0x14000}[case["bank"]]
            ram[physical:physical+16384] = page
        ram[sym["io_offline"]] = vectors[-1]["offline"]
        return header, ram, sym, raw

    def test_checker_requires_bytes_guards_and_context(self):
        header, ram, sym, raw = self.synthetic("storage")
        self.assertEqual(verify_storage(header, ram, sym, raw)["requests"], 8*len(cases()))
        for addr, error in ((sym["request_count"], "requests"),
                            (sym["command_count"], "command count"),
                            (sym["request_guard_low"], "guard damaged"),
                            (sym["transfer_guard_high"], "guard damaged"),
                            (sym["main_guard_low"], "guard damaged"),
                            (sym["trace_guard_high"], "guard damaged"),
                            (sym["storage_gate"]+20, "code changed"),
                            (TRACE_START+1, "trace state"),
                            (TRACE_START+5, "handle leaked"),
                            (TRACE_START+8, "transfer/commands"),
                            (TRACE_START+12, "storage bytes"),
                            (TRACE_START+143, "caller boundary"),
                            (0x4020, "caller page"),
                            (0x7C020, "service/unused"),
                            (0xC030, "framebuffer"), (0xFFFF, "framebuffer")):
            with self.subTest(addr=addr):
                damaged = bytearray(ram)
                damaged[addr] ^= 1
                with self.assertRaisesRegex(AssertionError, error):
                    verify_storage(header, damaged, sym, raw)

    def test_checker_accepts_only_documented_offline_failure(self):
        for variant in ("storage-close-error", "storage-open-error"):
            header, ram, sym, raw = self.synthetic(variant)
            self.assertEqual(verify_storage(header, ram, sym, raw, variant)["offline"], 1)
            ram[TRACE_START+(len(cases(variant))-1)*TRACE_SIZE+6] = 0
            with self.assertRaisesRegex(AssertionError, "lock/offline"):
                verify_storage(header, ram, sym, raw, variant)


if __name__ == "__main__":
    unittest.main()
