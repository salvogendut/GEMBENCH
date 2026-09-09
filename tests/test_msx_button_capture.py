"""Instruction-level MSX input tests; UI qualification uses full emulators."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CORE = Path(os.environ.get('MSX_1983_SOURCE', ROOT.parent/'1983'))/'src'


class ButtonCaptureTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('rasm') and shutil.which('cc') and (CORE/'z80.c').exists(),
                         'RASM, C compiler and 1983 Z80 source required')
    def test_real_assembled_capture_and_filter(self):
        with tempfile.TemporaryDirectory(prefix='msx-buttons-') as tmp:
            subprocess.run(['rasm', str(ROOT/'kernel/msx_gbap4.asm'), '-s', '-o', 'gate'],
                           cwd=tmp, check=True, capture_output=True)
            exe = Path(tmp)/'check'
            subprocess.run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror',
                            '-I', str(CORE), str(ROOT/'tests/msx_button_capture_test.c'),
                            str(CORE/'z80.c'), '-o', str(exe)], check=True)
            subprocess.run([str(exe), str(Path(tmp)/'GBAPV4.RAW')], check=True)

    def test_capture_is_msx_private(self):
        self.assertIn('call MSX_BUTTON_IRQ', (ROOT/'kernel/scheduler.asm').read_text())
        self.assertNotIn('MSX_BUTTON', (ROOT/'kernel/cpc_scheduler.asm').read_text())
        self.assertNotIn('MSX_BUTTON', (ROOT/'kernel/core/poll_publish.asm').read_text())
        self.assertIn('POLL_MENU_DISPATCH equ msx_input_dispatch',
                      (ROOT/'kernel/msx_root_services.inc').read_text())


if __name__ == '__main__':
    unittest.main()
