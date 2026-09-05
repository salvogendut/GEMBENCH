"""ABI 2.1 authority/SDK regression checks (runtime checks use openMSX)."""
from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


class UniversalParameterTests(unittest.TestCase):
    def test_append_only_and_parameter_layout(self):
        abi = json.loads((ROOT / "abi/geobench-v2.json").read_text())
        self.assertEqual(abi["version"], [2, 1])
        self.assertEqual(abi["jump_table"]["slots"][-2],
                         {"name": "GB_FSCTX", "address": 0x80D2})
        self.assertEqual(abi["jump_table"]["slots"][-1],
                         {"name": "GB_PARAMS", "address": 0x80D5})
        self.assertEqual(abi["caller_parameters"]["record_size"], 16)
        self.assertEqual(abi["sysinfo"]["record_size"], 48)
        self.assertTrue(all(r["address"] < 0x4000 for r in abi["mailbox"]["regions"]))

    def test_sdk_no_page3_mailboxes_and_separate_stack_bridge(self):
        source = (ROOT / "lib/gb/gbuniversal.c").read_text()
        bridge = (ROOT / "lib/gb/gbuniversal_draw.s").read_text()
        self.assertIsNone(re.search(r"0xC[0-9A-Fa-f]{3}", source + bridge))
        self.assertIn("gb_params_t request;", source)
        self.assertLess(bridge.index("di"), bridge.index("ldir"))
        self.assertIn("ld hl, #u_text", bridge)
        self.assertIn("call 0x80D5", bridge)

    def test_new_apps_cannot_enter_old_kernel(self):
        for name in ("abiprobe", "uclock", "ucalculator"):
            spec = json.loads((ROOT / f"apps/{name}/manifest.json").read_text())
            self.assertEqual(spec["minimum_abi"], [2, 1])
            self.assertIn("caller-parameters", spec["required_capabilities"])
        builder = (ROOT / "tools/build_uapp.sh").read_text()
        self.assertIn('this SDK requires minimum_abi [2, 1] and caller-parameters', builder)

    def test_module_bounds_and_legacy_ram_preserved(self):
        source = (ROOT / "lib/msx/glue.inc").read_text()
        for name, value in {"MSX_GBAP4_GATE": 0x400,
                            "MSX_GBAP4_GATE_LIMIT": 0x1000,
                            "MSX_APP_FIXED_BOTTOM": 0xD400,
                            "MSX_SYSINFO": 0xCF00}.items():
            actual = re.search(rf"^{name}\s+equ\s+#([0-9A-F]+)", source, re.M)
            self.assertEqual(int(actual[1], 16), value)
        collector = (ROOT / "lib/gembench/gbtimer_collect.s").read_text()
        self.assertIn('.include "core/timer_collect.inc"', collector)
        shared = (ROOT / "lib/gembench/core/timer_collect.inc").read_text()
        provider = (ROOT / "lib/gembench/msx_timer_collect.inc").read_text()
        self.assertIn("ld      (CORE_TIMER_DROPPED_GEN), a", shared)
        self.assertRegex(provider, r"CORE_TIMER_DROPPED_GEN\s*=\s*0xC03F")


if __name__ == "__main__":
    unittest.main()
