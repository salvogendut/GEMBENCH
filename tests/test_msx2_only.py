from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class ActiveTargetTests(unittest.TestCase):
    def test_pcw_artifacts_remain_absent(self) -> None:
        retired = [
            "QA/PCW",
            "lib/pcw",
            "tools/build_kernel_pcw.sh",
            "tools/mkpcwdsk.py",
            "docs/PCW.md",
        ]
        for relative in retired:
            self.assertFalse((ROOT / relative).exists(), relative)

    def test_top_level_make_exposes_msx_and_cpc(self) -> None:
        source = (ROOT / "Makefile").read_text()
        self.assertRegex(source, r"(?m)^all:\s+msx\s*$")
        self.assertRegex(source, r"(?m)^cpc:")
        self.assertRegex(source, r"(?m)^cpc-1984:")
        self.assertIsNone(re.search(r"(?m)^pcw(?:[-\w]*):", source))
        self.assertNotIn("-DGB_PCW", source)

    def test_bundled_basic_exposes_only_msx(self) -> None:
        source = (ROOT / "components/gb-basic/Makefile").read_text()
        self.assertRegex(source, r"(?m)^all:\s+msx\s*$")
        self.assertIsNone(re.search(r"(?m)^(?:cpc|pcw)(?:[-\w]*):", source))
        self.assertNotIn("-DGB_PCW", source)

    def test_build_helpers_expose_the_cpc_bootstrap_only(self) -> None:
        app_builder = (ROOT / "tools/build_capp.sh").read_text()
        scheduler_builder = (ROOT / "tools/build_scheduler.sh").read_text()
        kernel = (ROOT / "kernel/gbkern.asm").read_text()
        self.assertIn("-DGB_MSX2 or -DGB_CPC", app_builder)
        self.assertIn('if [ "$target" != msx ]', scheduler_builder)
        self.assertIn("no longer builds a PCW target", kernel)

    def test_policy_records_the_cpc_gate_and_archival_branch(self) -> None:
        policy = (ROOT / "docs/MSX2-ONLY.md").read_text()
        self.assertIn("archive/cpc-pcw-targets", policy)
        self.assertIn("CPC", policy)


if __name__ == "__main__":
    unittest.main()
