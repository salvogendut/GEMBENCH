from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]


class CpcPath83Tests(unittest.TestCase):
    def test_production_grammar_matches_portable_chooser(self):
        with tempfile.TemporaryDirectory(prefix='cpc-path83-') as tmp:
            exe=Path(tmp)/'test'
            subprocess.run([os.environ.get('CC','cc'),'-std=c99','-Wall','-Wextra',
                            '-Werror',str(ROOT/'tests/cpc_path83_test.c'),'-o',str(exe)],
                           check=True)
            subprocess.run([str(exe)],check=True)
        provider=(ROOT/'kernel/kc/gbfsctx_cpc.c').read_text()
        self.assertIn('#include "cpc_path83.h"',provider)
        self.assertIn('cpc_path83_length(CPC_PATH,CTX_PATH_CAP)',provider)
        self.assertIn('cpc_path83_char(ch)',provider)


if __name__=='__main__':unittest.main()
