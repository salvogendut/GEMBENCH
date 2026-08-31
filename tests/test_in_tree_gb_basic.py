from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
COMPONENT = ROOT / "components" / "gb-basic"


class InTreeGbBasicTests(unittest.TestCase):
    def test_complete_build_inputs_are_bundled(self) -> None:
        required = [
            "LICENSE",
            "PROVENANCE.md",
            "Makefile",
            "apps/basic/main.c",
            "apps/basic/icon.asm",
            "apps/basrun/main.c",
            "apps/basrun/interp.c",
            "apps/basrun/expr.c",
            "apps/basrun/fac.s",
            "apps/basrun/gfx.s",
            "tools/build_app.sh",
            "tools/build_engine.sh",
            "examples/HELLO.BAS",
        ]
        for relative in required:
            self.assertTrue((COMPONENT / relative).is_file(), relative)

    def test_production_builds_cannot_redirect_to_a_sibling_checkout(self) -> None:
        scripts = [
            ROOT / "tools" / "build_kernel_msx.sh",
        ]
        for script in scripts:
            source = script.read_text()
            self.assertNotIn("../GB-BASIC", source, script.name)
            self.assertIn('GB_BASIC_DIR="components/gb-basic"', source, script.name)

    def test_component_defaults_to_the_enclosing_checkout(self) -> None:
        makefile = (COMPONENT / "Makefile").read_text()
        builder = (COMPONENT / "tools" / "build_app.sh").read_text()
        self.assertIn("GEOBENCH ?= ../..", makefile)
        self.assertIn('GEOBENCH="${GEOBENCH:-../..}"', builder)


if __name__ == "__main__":
    unittest.main()
