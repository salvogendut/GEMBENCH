from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]


class AccessoryTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which(os.environ.get('CC','cc')),'C compiler required')
    def test_same_desktop_activation_policy(self):
        with tempfile.TemporaryDirectory(prefix='desktop-accessory-') as temp:
            output=Path(temp)/'accessory'
            subprocess.run([os.environ.get('CC','cc'),'-std=c99','-Wall','-Wextra','-Werror',
                            str(ROOT/'tests/desktop_accessory_test.c'),'-o',str(output)],check=True)
            subprocess.run([str(output)],check=True)

    def test_shared_source_and_capability_gates(self):
        for name in ('apps/desktop/main.c','kernel/kc/cpc_root_bar.c'):
            self.assertIn('core/accessory_open.inc',(ROOT/name).read_text())
        for name in ('kernel/gbkern.asm','kernel/cpc_services.asm'):
            self.assertIn('include "core/shell_service.asm"',(ROOT/name).read_text())
        shared=(ROOT/'kernel/core/shell_service.asm').read_text()
        self.assertNotIn('MSX_APP_',shared)
        self.assertIn('CORE_APP_SERVICE',shared)
        self.assertIn('CORE_APP_ACCESSORY',shared)
        self.assertIn('accessory_open.inc',(ROOT/'tools/build_capp.sh').read_text())


if __name__=='__main__': unittest.main()
