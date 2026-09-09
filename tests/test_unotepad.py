"""Actual Notepad integration policy; a passing host test does not qualify an APP."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from check_universal_app import check_source
CC = os.environ.get('CC', 'cc')


class UnifiedNotepadTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which(CC), 'host C compiler required')
    def test_editor_and_document_controller(self):
        with tempfile.TemporaryDirectory(prefix='geobench-unotepad-') as tmp:
            binary = Path(tmp) / 'test'
            subprocess.run([CC, '-std=c99', '-Wall', '-Wextra', '-Werror',
                            '-DGB_UNIVERSAL', '-DGB_UNIVERSAL_HOST_TEST',
                            '-I', str(ROOT / 'lib/gb'), '-I', str(ROOT / 'include/gembench'),
                            str(ROOT / 'tests/test_unotepad.c'),
                            str(ROOT / 'lib/gembench/gbdocio.c'),
                            str(ROOT / 'lib/gembench/gbfilepick.c'),
                            str(ROOT / 'lib/gembench/gbfilepick_ui.c'),
                            '-o', str(binary)], check=True)
            subprocess.run([str(binary)], check=True)

    def test_portability_and_capacity(self):
        errors = []
        for source in (ROOT / 'apps/unotepad').glob('*.[ch]'):
            check_source(source, errors)
        self.assertEqual(errors, [])
        self.assertIn('#define NP_MAX 4096u', (ROOT / 'apps/unotepad/editor.h').read_text())
        self.assertNotIn('0x4010', (ROOT / 'apps/unotepad/main.c').read_text())


if __name__ == '__main__':
    unittest.main()
