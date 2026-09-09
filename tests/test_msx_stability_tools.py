"""Host checks for the baseline tooling; emulator assertions remain separate."""
import hashlib
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT/"tools"/(name+".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class StabilityToolsTests(unittest.TestCase):
    def test_layout_uses_source_constants(self):
        layout = load("test_msx_stability_1983").constants(ROOT/"kernel/lowram.inc")
        self.assertEqual(layout["POLL_MX"], 0x1306)
        self.assertEqual(layout["WM_ESZ"], 25)
        self.assertEqual(layout["SCHED_FAULT"], 0x1347)

    def test_inventory_does_not_treat_app_suffix_as_universal(self):
        with tempfile.TemporaryDirectory() as tmp:
            card = Path(tmp)
            (card/"GBENCH").mkdir()
            native = b"\xc3\x00\x40" + b"NATIVE"*3
            portable = b"\xc3\x00\x40GBAP\x04" + b"\x00"*8
            for name, data in [("NATIVE.APP", native), ("PROBE.APP", portable),
                               ("SAVER.SAV", native), ("DATA.TXT", b"ignored")]:
                (card/"GBENCH"/name).write_bytes(data)
            rows = {row["name"]: row for row in load("prepare_msx_stability").inventory(card)}
            self.assertEqual(set(rows), {"NATIVE.APP", "PROBE.APP", "SAVER.SAV"})
            self.assertFalse(rows["NATIVE.APP"]["universal_candidate"])
            self.assertTrue(rows["PROBE.APP"]["universal_candidate"])
            self.assertEqual(rows["PROBE.APP"]["sha256"], hashlib.sha256(portable).hexdigest())
            self.assertEqual(rows["PROBE.APP"]["size"], len(portable))

    def test_existing_media_directory_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)/"accepted"
            out.mkdir()
            marker = out/"keep"
            marker.write_text("user media")
            result = subprocess.run([sys.executable, str(ROOT/"tools/prepare_msx_stability.py"),
                                     "--built-root", str(ROOT), "--output", str(out), "--mode", "6"],
                                    text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("output already exists", result.stderr)
            self.assertEqual(marker.read_text(), "user media")

    def test_1983_driver_rejects_partial_firmware_override(self):
        result = subprocess.run([sys.executable, str(ROOT/"tools/test_msx_stability_1983.py"),
                                 "--bridge", "missing", "--omega", "missing", "--sunrise", "missing",
                                 "--image", "missing", "--worktree", str(ROOT), "--mode", "6",
                                 "--output", "unused", "--bios", "missing"],
                                text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must be supplied together", result.stderr)

    def test_1983_driver_preserves_previous_evidence(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = subprocess.run([sys.executable, str(ROOT/"tools/test_msx_stability_1983.py"),
                                     "--bridge", "missing", "--omega", "missing", "--sunrise", "missing",
                                     "--image", "missing", "--worktree", str(ROOT), "--mode", "6",
                                     "--output", tmp], text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("output already exists", result.stderr)

    def test_observers_wait_for_ram_and_popup_input(self):
        window = (ROOT/"debug/window_kinds_openmsx.tcl").read_text()
        desk = (ROOT/"debug/desk_accessories_openmsx.tcl").read_text()
        settings = (ROOT/"debug/msx_settings_stability.tcl").read_text()
        self.assertIn("proc wk_confirm_rect", window)
        self.assertIn("after time 1.0 [list wk_confirm_rect", window)
        self.assertIn("$::da_popup_polled", desk)
        self.assertIn("debug set_bp 0x801E", desk)
        self.assertIn("$::ss_popup_ready", settings)

    def test_clock_key_is_bounded_and_waits_for_input(self):
        clock = (ROOT/"debug/clock_runtime_openmsx.tcl").read_text()
        self.assertIn("debug set_bp $cr_getkey_address", clock)
        self.assertIn("if {$::cr_key_ready}", clock)
        self.assertIn("after time 0.30 {keymatrixup 5 0x01}", clock)
        self.assertIn("[peek $::cr_seconds_address] == 1", clock)


if __name__ == "__main__":
    unittest.main()
