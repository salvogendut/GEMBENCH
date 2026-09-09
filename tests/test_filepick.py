"""Portable document chooser contracts; emulator UI acceptance is separate."""
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
SOURCES = [ROOT / "lib/gembench" / name for name in ("gbfilepick.c", "gbfilepick_ui.c")]
INCLUDES = ["-I", str(ROOT / "lib/gb"), "-I", str(ROOT / "include/gembench")]


class FilePickerTests(unittest.TestCase):
    def test_builder_requires_filesystem_for_document_helpers(self):
        for feature in ('UNIVERSAL_DOCIO', 'UNIVERSAL_FILEPICK'):
            env={**os.environ, 'UNIVERSAL_FS':'0', 'UNIVERSAL_DOCIO':'0',
                 'UNIVERSAL_FILEPICK':'0', feature:'1', 'APP_ICON':'apps/fsprobe/icon.asm'}
            result=subprocess.run(['bash','tools/build_uapp.sh','apps/filepickprobe'],
                                  cwd=ROOT,env=env,capture_output=True,text=True)
            self.assertEqual(result.returncode,2)
            self.assertIn('require UNIVERSAL_FS=1',result.stderr)

    @unittest.skipUnless(shutil.which(CC), "C compiler required")
    def test_model_ui_and_document_handoff(self):
        with tempfile.TemporaryDirectory(prefix="geobench-filepick-") as tmp:
            binary = Path(tmp) / "check"
            subprocess.run([CC, "-std=c99", "-Wall", "-Wextra", "-Werror",
                            "-DGB_UNIVERSAL", "-DGB_UNIVERSAL_HOST_TEST", *INCLUDES,
                            '-DGB_FSCTX_PLATFORM_HEADER="filepick_client_provider.h"',
                            "-I", str(ROOT / "tests/fixtures"),
                            str(ROOT / "tests/test_gbfilepick.c"), *map(str, SOURCES),
                            str(ROOT / "lib/gembench/gbdocio.c"), "-o", str(binary)], check=True)
            subprocess.run([str(binary)], check=True)

    def test_portable_sources(self):
        errors = []
        for file in [*SOURCES, ROOT / "include/gembench/gbfilepick.h",
                     ROOT / "include/gembench/gbfilepick_ui.h"]:
            check_source(file, errors)
        self.assertEqual(errors, [])

    @unittest.skipUnless(shutil.which(SDCC), "SDCC required")
    def test_z80_cost_and_owned_state(self):
        with tempfile.TemporaryDirectory(prefix="geobench-filepick-z80-") as tmp:
            for source in SOURCES:
                obj = Path(tmp) / (source.stem + ".rel")
                frame = ["--fomit-frame-pointer"] if source.stem.endswith('_ui') else []
                subprocess.run([SDCC, "-mz80", "--std-c99", "--opt-code-size",
                                "--max-allocs-per-node", "100000", *frame,
                                "-DGB_UNIVERSAL", *INCLUDES,
                                "-c", str(source), "-o", str(obj)], check=True)
                areas = {n: int(s, 16) for n, s in re.findall(
                    r"^A (\S+) size ([0-9A-Fa-f]+)", obj.read_text(), re.M)}
                for name in ("_DATA", "_BSS", "_INITIALIZED", "_INITIALIZER"):
                    self.assertEqual(areas.get(name, 0), 0, name)
                self.assertLessEqual(areas['_CODE'], 3200 if not frame else 2000)
                errors = []
                check_generated_asm(obj.with_suffix('.asm'), errors)
                self.assertEqual(errors, [])
                if not frame:
                    # IX frame is safe only while all external kernel-bound
                    # calls go through the preserving filesystem bridge.
                    refs=re.findall(r'^S (_gb_\w+) Ref',obj.read_text(),re.M)
                    self.assertTrue(refs)
                    self.assertTrue(all(name.startswith('_gb_fsctx_') or name == '_gb_ufs_transfer'
                                        for name in refs),refs)
                print(f"{source.stem}: {areas['_CODE']} code bytes, no persistent library data")
            subprocess.run([SDCC, "-mz80", "--std-c99", "-DGB_UNIVERSAL", *INCLUDES,
                            "-c", str(ROOT / "tests/test_filepick_layout.c"),
                            "-o", str(Path(tmp) / "layout.rel")], check=True)


if __name__ == '__main__':
    unittest.main()
