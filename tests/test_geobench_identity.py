from __future__ import annotations

import hashlib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class GeobenchIdentityTests(unittest.TestCase):
    def test_canonical_identity_assets_are_unchanged(self) -> None:
        expected = {
            "logo.png": "9f0a1d4f071065473424f28f1d90207c90b12e93d9c5caf432fae6ef54d90bd2",
            "assets/SPLASH.png": "ba2a897de9df1df78c41897eda46e45fe8743bacc12d5043bb23ece047b28c03",
            "assets/pictures/LOGO.PIC": "2cb6ee4d16b24fe163ee45ec9d6617bbd227d70c1a702b9580b27fd800f4589d",
            "lib/icon_geobench.asm": "428504e9f05f52d9b6d5bf2ff519d65ebb3c2fa05ea6b48f4d62beb4dfff142a",
        }
        for relative, digest in expected.items():
            payload = (ROOT / relative).read_bytes()
            self.assertEqual(hashlib.sha256(payload).hexdigest(), digest, relative)

    def test_superseded_identity_assets_are_absent(self) -> None:
        retired = (
            "assets/GEMBENCH_KERNEL.png",
            "assets/GEMBENCH_LOGO.png",
            "assets/GEMBENCH_ORIGINAL_LOGO.png",
            "assets/msx/GEMLOGO.PIC",
            "screenshots/GEMBENCH-Mode7.png",
        )
        for relative in retired:
            self.assertFalse((ROOT / relative).exists(), relative)

    def test_build_stages_geobench_palette_and_art(self) -> None:
        builder = (ROOT / "tools/build_kernel_msx.sh").read_text()
        self.assertIn("assets/SPLASH.png", builder)
        self.assertIn("INKS=1,26,0,6,1", builder)
        self.assertNotIn("--gembench", builder)
        self.assertNotIn("GEMLOGO.PIC", builder)

        kernel = (ROOT / "kernel/gbkern.asm").read_text()
        self.assertIn("INK_DESKTOP     equ   1", kernel)
        self.assertIn("INK_DARK        equ   0", kernel)

    def test_public_entry_point_and_demo_use_geobench(self) -> None:
        makefile = (ROOT / "Makefile").read_text()
        readme = (ROOT / "README.md").read_text()
        example = (ROOT / "examples/hello-dialog.json").read_text()
        self.assertIn("geobench-msx: msx", makefile)
        self.assertTrue(readme.startswith("# GEOBENCH\n"))
        self.assertIn("Welcome to GEOBENCH", example)

    def test_archive_branch_is_documented(self) -> None:
        visual = (ROOT / "docs/gembench/VISUAL-DIRECTION.md").read_text()
        self.assertIn("archive/gembench-msx2-identity", visual)


if __name__ == "__main__":
    unittest.main()
