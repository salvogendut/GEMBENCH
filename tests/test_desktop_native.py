from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from build_cpc_desktop import compile_desktop
from build_cpc_runtime import assemble


class DesktopNativeTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which(os.environ.get('CC','cc')),'C compiler required')
    def test_actual_desktop_and_native_leaves(self):
        with tempfile.TemporaryDirectory(prefix='desktop-native-') as temp:
            exe=Path(temp)/'desktop'
            for ready,settings in ((0,0),(1,0),(1,1)):
                with self.subTest(filemgr_ready=ready,settings_ready=settings):
                    subprocess.run([os.environ.get('CC','cc'),'-std=c99','-Wall','-Wextra','-Werror',
                                    '-Wno-unused-function',f'-DDESKTOP_FILEMGR_READY={ready}',f'-DDESKTOP_SETTINGS_READY={settings}',
                                    '-I',str(ROOT/'lib/gb'),'-I',str(ROOT/'include/gembench'),
                                    f'-DGB_DESKTOP_BINDINGS="{ROOT/"tests/desktop_binding_provider.h"}"',
                                    str(ROOT/'tests/desktop_native_test.c'),'-o',str(exe)],check=True)
                    subprocess.run([str(exe)],check=True)


@unittest.skipUnless(all(shutil.which(os.environ.get(k,k.lower())) for k in ('RASM','SDCC')),
                     'RASM/SDCC required')
class DesktopNativeLayoutTests(unittest.TestCase):
    def test_complete_link_and_profile_guards(self):
        with tempfile.TemporaryDirectory(prefix='desktop-native-link-') as temp:
            work=Path(temp);runtime=work/'runtime'
            sym=assemble(runtime,('-DCPC_NATIVE_DESKTOP=1',))
            report=compile_desktop(work/'app',runtime,sym)
            self.assertEqual(report['source'],'apps/desktop/main.c')
            self.assertLessEqual(report['used'],report['budget'])
            self.assertLessEqual(report['data_used'],report['data_budget'])
            self.assertEqual(report['snapshot_base'],0x7F00)
            self.assertFalse(list(work.rglob('*.APP')))
            for name in ('gb_msg','poll_mx','wm_table','mw_rect'):
                bad=dict(sym);bad[name]+=1
                with self.assertRaisesRegex(AssertionError,'native SDK binding changed'):
                    compile_desktop(work/'bad',runtime,bad)
            bad=dict(sym);bad['cpc_bar_data_end']=0x6020
            with self.assertRaisesRegex(AssertionError,'outside owned allocation'):
                compile_desktop(work/'overflow',runtime,bad)
            bad=dict(sym);bad.pop('cpc_desktop_profile')
            with self.assertRaisesRegex(AssertionError,'private native boot profile'):
                compile_desktop(work/'wrong-profile',runtime,bad)
            result=subprocess.run([os.environ.get('SDCC','sdcc'),'-mz80','-DGB_CPC_RESTART',
                                   '-I',str(ROOT/'lib/gb'),'-E',str(ROOT/'apps/desktop/main.c')],
                                   stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
            self.assertNotEqual(result.returncode,0)
            self.assertIn(b'requires an explicit native provider',result.stderr)
