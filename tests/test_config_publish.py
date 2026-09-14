"""Portable configuration-cache publication contract and real Z80 bounds."""
from pathlib import Path
import json
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
CORE=Path(os.environ.get('MSX_1983_SOURCE',ROOT.parent/'1983'))/'src'


class ConfigPublishTests(unittest.TestCase):
    def test_abi_and_platform_bindings(self):
        abi=json.loads((ROOT/'abi/geobench-v2.json').read_text())
        operation=abi['shell_service']['operations']['configuration-publish']
        self.assertEqual(operation,5)
        contract=abi['shell_service']['configuration_publish']
        self.assertEqual(contract['maximum_bytes'],512)
        self.assertEqual(contract['source_span'],'[0x4000,0x7F00)')
        self.assertIn('root',contract['context'])
        source=(ROOT/'kernel/core/shell_service.asm').read_text()
        self.assertIn('SHELL_CONFIG_PUBLISH',source)
        for platform in ('kernel/gbkern.asm','kernel/cpc_services.asm'):
            self.assertIn('include "core/config_publish.asm"',(ROOT/platform).read_text())
        self.assertEqual((ROOT/'apps/unotepad/main.c').read_text().count('gb_config_publish('),1)

    @unittest.skipUnless(shutil.which('rasm') and shutil.which('cc') and
                         (CORE/'z80.c').exists(),
                         'RASM, C compiler and read-only 1983 Z80 source required')
    def test_real_z80_copy_and_bounds(self):
        with tempfile.TemporaryDirectory(prefix='config-publish-z80-') as tmp:
            tmp=Path(tmp)
            source='\n'.join((
                'CONFIG_PUBLISH_TEXT equ #1000',
                'CONFIG_PUBLISH_LENGTH equ #1200',
                'org #8000',
                f'include "{ROOT}/kernel/core/config_publish.asm"',
                'save "publish.bin",#8000,$-#8000',''))
            (tmp/'publish.asm').write_text(source)
            subprocess.run(['rasm',str(tmp/'publish.asm'),'-s','-sq','-o','publish'],
                           cwd=tmp,check=True,capture_output=True)
            exe=tmp/'test'
            subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror',
                '-I',str(CORE),str(ROOT/'tests/config_publish_z80.c'),
                str(CORE/'z80.c'),'-o',str(exe)],check=True)
            subprocess.run([str(exe),str(tmp/'publish.bin')],check=True)


if __name__=='__main__':unittest.main()
