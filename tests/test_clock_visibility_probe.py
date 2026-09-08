from pathlib import Path
import re
import shutil
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
TCL = shutil.which("tclsh")
SOURCE = ROOT / "debug/multi_event_openmsx.tcl"


def procedure(name):
    match = re.search(rf"(?ms)^proc {name} .*?^}}$", SOURCE.read_text())
    if match is None:
        raise AssertionError(f"missing Tcl procedure {name}")
    return match.group(0)


@unittest.skipUnless(TCL, "tclsh required for actual Clock probe predicates")
class ClockProbeTests(unittest.TestCase):
    def run_tcl(self, script):
        result = subprocess.run([TCL], input=script, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        return result.stdout.strip()

    def restore(self, change=""):
        return self.run_tcl("""
set me_in_poll 1
set me_filemgr_slot 1
set me_clock_slot 2
set me_paintlock 0x130A
set me_restore_rect {4 26 56 158}
set actual_rect $me_restore_rect
set me_draw_hits 11
set me_restore_draw_start 10
array set mem {}
proc peek {address} { return $::mem([expr {$address + 0}]) }
proc me_rect {slot} { return $::actual_rect }
set mem(4944) 3   ;# WM_NWIN 0x1350
set mem(4945) 1   ;# WM_FOCUS 0x1351
set mem(4874) 0   ;# paint lock 0x130A
set mem(49602) 1  ;# Clock surface visibility 0xC1C2
""" + procedure("me_restore_ready") + "\n" + change + "\nputs [me_restore_ready]\n")

    def test_success_requires_real_restoration_and_a_fresh_draw(self):
        self.assertEqual(self.restore(), "1")

    def test_rom_aliases_and_incomplete_restoration_cannot_pass(self):
        for change in (
            "set me_in_poll 0",
            "set actual_rect {203 162 203 170}",  # observed DOS-mapped bytes
            "set actual_rect {0 8 128 204}",
            "set me_draw_hits $me_restore_draw_start",
            "set mem(4944) 112",  # observed aliased live-window count
            "set mem(4945) 0",
            "set mem(4874) 1",
            "set mem(49602) 0",
        ):
            with self.subTest(change=change):
                self.assertEqual(self.restore(change), "0")

    def test_poll_dispatch_brackets_all_state_sampling(self):
        result = self.run_tcl("""
set me_poll_bp test_breakpoint
set me_in_poll 0
set me_poll_samples 0
set me_poll_events {{lappend ::seen $::me_in_poll} {lappend ::seen $::me_in_poll}}
set seen {}
proc debug {args} {}
proc me_finish {status} { error $status }
""" + procedure("me_poll_tick") + """
me_poll_tick
puts [list $seen $me_in_poll $me_poll_samples $me_poll_events $me_poll_bp]
""")
        self.assertEqual(result, "{1 1} 0 1 {} {}")


if __name__ == "__main__":
    unittest.main()
