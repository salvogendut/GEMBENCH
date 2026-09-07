from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CC = shutil.which(os.environ.get('CC', 'cc'))
sys.path.insert(0, str(ROOT/'tools'))
from cpc_production_fsctx import expected, inputs


class ReadOracleTests(unittest.TestCase):
    def test_missing_file_is_not_eof_and_retry_preserves_offset(self):
        cases = inputs()
        rows, _ = expected()
        self.assertEqual(len(rows), 48)
        failed = next(i for i,c in enumerate(cases) if c['name']=='missing-read-is-error')
        self.assertEqual(rows[failed][1], 6)
        self.assertEqual(rows[failed][10:12], bytes(2))
        self.assertEqual(rows[failed][32:608], rows[failed-1][32:608])
        self.assertEqual(rows[failed][672:1184], b'\xA5'*512)
        retry = next(i for i,c in enumerate(cases) if c['name']=='fresh-read')
        self.assertEqual(rows[retry][1], 0)
        self.assertEqual(rows[retry][10:16], b'\x80\0\x80\0\0\0')
        self.assertEqual(rows[retry][672:800], bytes((i*7+3)&255 for i in range(128)))


@unittest.skipUnless(CC, 'host C compiler required')
class ReadProviderTests(unittest.TestCase):
    def compile(self, source, *flags):
        with tempfile.TemporaryDirectory(prefix='cpc-read-') as temp:
            exe = Path(temp)/'test'
            subprocess.run([CC, '-std=c99', '-Wall', '-Wextra', '-Werror',
                            *flags, str(ROOT/'tests'/source), '-o', str(exe)], check=True)
            subprocess.run([str(exe)], check=True)

    def test_actual_transport_error_retry_and_bounds(self):
        self.compile('test_cpc_fsread.c')

    def test_shared_policy_only_commits_successful_reads(self):
        for base in ('0x2000', '0xC000'):
            with self.subTest(base=base):
                self.compile('test_fsctx_core.c', '-DTEST_FS_READ_STATUS',
                             '-DTEST_FS_DIRECTORY_STATUS', '-DFIXTURE_BASE='+base)


if __name__ == '__main__':
    unittest.main()
