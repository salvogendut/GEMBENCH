"""Bounded document I/O foundation, not Notepad or runtime acceptance."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_universal_app import check_source, check_generated_asm

CC = os.environ.get("CC", "cc")
SDCC = os.environ.get("SDCC", "sdcc")
SOURCE = ROOT / "lib/gembench/gbdocio.c"
HEADER = ROOT / "include/gembench/gbdocio.h"
INCLUDES = ["-I", str(ROOT / "lib/gb"), "-I", str(ROOT / "include/gembench")]


class DocumentIOTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which(CC), "host C compiler required")
    def test_real_helper_and_shared_client(self):
        with tempfile.TemporaryDirectory(prefix="geobench-docio-") as temp:
            binary = Path(temp) / "docio"
            subprocess.run([CC, "-std=c99", "-Wall", "-Wextra", "-Werror",
                            "-DGB_UNIVERSAL", *INCLUDES,
                            "-I", str(ROOT / "tests/fixtures"),
                            str(ROOT / "tests/test_gbdocio.c"), str(SOURCE),
                            "-o", str(binary)], check=True)
            subprocess.run([str(binary)], check=True)

    def test_source_passes_existing_portability_audit(self):
        errors = []
        for source in (SOURCE, HEADER):
            check_source(source, errors)
        self.assertEqual(errors, [])

    @unittest.skipUnless(shutil.which(SDCC), "SDCC required for Z80 size check")
    def test_z80_layout_and_no_hidden_persistent_buffers(self):
        with tempfile.TemporaryDirectory(prefix="geobench-docio-z80-") as temp:
            obj = Path(temp) / "gbdocio.rel"
            subprocess.run([SDCC, "-mz80", "--std-c99", "--opt-code-size",
                            "--max-allocs-per-node", "100000", "-DGB_UNIVERSAL",
                            *INCLUDES, "-c", str(SOURCE), "-o", str(obj)], check=True)
            areas = {name: int(size, 16) for name, size in
                     re.findall(r"^A (\S+) size ([0-9A-Fa-f]+)",
                                obj.read_text(), re.M)}
            self.assertLessEqual(areas["_CODE"], 1536)
            for name in ("_DATA", "_BSS", "_INITIALIZED", "_INITIALIZER"):
                self.assertEqual(areas.get(name, 0), 0, name)
            errors = []
            check_generated_asm(obj.with_suffix(".asm"), errors)
            self.assertEqual(errors, [])
            # Compile-time target size check; host pointers/ints differ.
            subprocess.run([SDCC, "-mz80", "--std-c99", "-DGB_UNIVERSAL",
                            *INCLUDES, "-c", str(ROOT / "tests/test_docio_layout.c"),
                            "-o", str(Path(temp) / "layout.rel")], check=True)
            print(f"document I/O: {areas['_CODE']} Z80 code bytes, "
                  "11 bytes per caller-owned job, no persistent library buffers")


if __name__ == "__main__":
    unittest.main()
