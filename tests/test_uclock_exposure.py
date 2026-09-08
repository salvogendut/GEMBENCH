from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]


class UclockExposureTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which(os.environ.get('CC','cc')),'C compiler required')
    def test_actual_clock_clipped_exposure_and_pending_digits(self):
        with tempfile.TemporaryDirectory(prefix='uclock-exposure-') as tmp:
            exe=Path(tmp)/'clock'
            subprocess.run([os.environ.get('CC','cc'),'-std=c99','-Wall','-Wextra','-Werror',
                            '-Wno-unused-function','-ffunction-sections','-fdata-sections','-Wl,--gc-sections',
                            '-I',str(ROOT/'lib/gb'),'-I',str(ROOT/'include/gembench'),
                            str(ROOT/'tests/uclock_exposure_test.c'),'-o',str(exe)],check=True)
            subprocess.run([str(exe)],check=True)
