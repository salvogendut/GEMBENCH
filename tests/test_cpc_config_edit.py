from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]

class ConfigEditTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which(os.environ.get('CC','cc')),'C compiler required')
    def test_actual_settings_edit_and_native_persistence(self):
        with tempfile.TemporaryDirectory(prefix='config-edit-') as tmp:
            exe=Path(tmp)/'config-edit'
            subprocess.run([os.environ.get('CC','cc'),'-std=c99','-Wall','-Wextra','-Werror',
                            '-I',str(ROOT/'lib/gb'),'-I',str(ROOT/'include/gembench'),
                            str(ROOT/'tests/config_edit_test.c'),'-o',str(exe)],check=True)
            subprocess.run([str(exe)],check=True)

    def test_shared_editor_and_explicit_build_dependency(self):
        for path in ('apps/settings/main.c','kernel/kc/cpc_config_edit.c'):
            source=(ROOT/path).read_text()
            for inc in ('config_keypos.inc','config_edit.inc'): self.assertIn(inc,source)
        self.assertIn('$APP/core/config_edit.inc',(ROOT/'tools/build_capp.sh').read_text())

if __name__=='__main__': unittest.main()
