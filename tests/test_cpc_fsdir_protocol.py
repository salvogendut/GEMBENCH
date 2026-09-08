from __future__ import annotations

from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from cpc_fsdir_protocol import BIG_SIZE, TRACE, STRIDE, observe, transactions


def observation_fixture():
    """Checker self-test only. Never loaded into a CPC or used by its driver."""
    sym = {"dp_done": 0x3354, "dp_commands": 0x3356}
    ram = bytearray(512*1024)
    ram[sym["dp_done"]] = len(transactions())
    ram[sym["dp_commands"]:sym["dp_commands"]+2] = len(transactions()).to_bytes(2, "little")

    def stat(name, size, attr):
        return (b"\0" + size.to_bytes(4, "little") + bytes(4) + bytes((attr,)) +
                name + bytes(13-len(name)) + name + b"\0")

    payloads = {"path": b"/CATALOG\0", "restored-path": b"/\0",
                "legacy-directory": b">EIGHTCH.     DIR\0\0\0",
                "extended-directory": b">EIGHTCHR\0",
                "stat-directory": stat(b"EIGHTCHR", 0, 0x10),
                "stat-file": stat(b"BIG.BIN", BIG_SIZE, 0x20),
                "stat-missing": b"\x04", "open-file": b"\x03\0",
                "size-file": BIG_SIZE.to_bytes(4, "little"), "close-file": b"\0"}
    for i, (name, command, _) in enumerate(transactions()):
        at = TRACE+i*STRIDE
        data = payloads.get(name, b"")
        frame = bytes((len(data)+2, command, 0x43)) + data
        ram[at:at+136] = frame + b"\xD7"*(136-len(frame))
        ram[at+136:at+STRIDE] = bytes((0, 0xF7, 0x8D, 0, 0, 0, 1, 0))
    return ram, sym


class DirectoryProtocolTests(unittest.TestCase):
    def test_full_metadata_is_required_for_qualification(self):
        ram, sym = observation_fixture()
        report = observe(ram, sym)
        self.assertTrue(report["directory_protocol_qualified"])
        self.assertEqual(report["missing_requirements"], [])
        self.assertEqual(report["directory_protocol_commands"], 15)
        # A 16-bit-only file size is not accepted as full metadata.
        ram[TRACE+8*STRIDE+6] = 0
        report = observe(ram, sym)
        self.assertFalse(report["directory_protocol_qualified"])
        self.assertIn("stat-file", report["missing_requirements"][0])

    def test_old_catalog_and_absent_fstat_are_not_a_pass(self):
        ram, sym = observation_fixture()
        for case in (7, 8, 9):
            at = TRACE+case*STRIDE
            ram[at:at+136] = b"\x02\x16\x43" + b"\xD7"*133
        at = TRACE+6*STRIDE
        ram[at:at+136] = ram[TRACE+4*STRIDE:TRACE+4*STRIDE+136]
        report = observe(ram, sym)
        self.assertFalse(report["directory_protocol_qualified"])
        self.assertEqual(len(report["missing_requirements"]), 4)

    def test_transport_controls_and_guards_fail_before_capability_report(self):
        ram, sym = observation_fixture()
        for at in (sym["dp_done"], sym["dp_commands"], TRACE+1, TRACE+130,
                   TRACE+136, TRACE+137, TRACE+138, TRACE+139, TRACE+140,
                   TRACE+141, TRACE+142, TRACE+143, TRACE+11*STRIDE+3):
            bad = bytearray(ram)
            bad[at] ^= 1
            with self.subTest(address=at), self.assertRaises(AssertionError):
                observe(bad, sym)

    def test_probe_does_not_enable_unqualified_services(self):
        gate = (ROOT/"kernel/cpc_fsctx.asm").read_text()
        for operation in (5, 6, 9, 10, 14):
            self.assertIn(f"cp {operation}\n                jr z,cpc_fs_unsupported", gate)
        probe = (ROOT/"debug/cpc_production/fsdir_protocol.asm").read_text()
        self.assertIn("call cpc_fs_exchange", probe)
        self.assertNotIn("call k_fsctx", probe)
        runner = (ROOT/"tools/test_cpc_production_1984.py").read_text()
        self.assertIn('"PROTOCOL BLOCKED "', runner)
        self.assertIn("if not qualified:\n            raise SystemExit(2)", runner)


if __name__ == "__main__":
    unittest.main()
