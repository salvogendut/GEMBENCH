from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]


class DesktopMenuTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which(os.environ.get('CC','cc')), 'C compiler required')
    def test_actual_menu_component_and_desktop_actions(self):
        with tempfile.TemporaryDirectory(prefix='desktop-menu-') as temp:
            for target in ([],['-DGB_MSX2']):
                binary=Path(temp)/'menu'
                subprocess.run([os.environ.get('CC','cc'),'-std=c99','-Wall','-Wextra','-Werror',
                                *target,str(ROOT/'tests/desktop_menu_test.c'),'-o',str(binary)],check=True)
                subprocess.run([str(binary)],check=True)

    def test_shared_source_and_native_service_gates(self):
        for name in ('apps/desktop/main.c','kernel/kc/cpc_root_bar.c'):
            source=(ROOT/name).read_text()
            for fragment in ('accessory_menu.inc','menu_init.inc','accessory_pending.inc'):
                self.assertEqual(source.count(fragment),1)
        builder=(ROOT/'tools/cpc_runtime_bar.py').read_text()
        self.assertIn('gbdoc.c',builder)
        self.assertIn('gbdlg.c',builder)
        self.assertIn('GBDOC_MENU_ONLY',builder)
        self.assertIn('GB_POPUP_BUFFER',builder)
        root=(ROOT/'kernel/kc/cpc_root_bar.c').read_text()
        self.assertIn('#define DESKTOP_SYSTEM_MENU 0',root)
        self.assertNotIn('gb_universal_popup',root)
        self.assertIn('jp cpc_unavailable ; #80AE',(ROOT/'kernel/cpc_runtime_api.inc').read_text())

    def test_default_popup_keeps_native_msx_buffer(self):
        source=(ROOT/'lib/gb/gbdlg.c').read_text()
        self.assertIn('#define GB_POPUP_BUFFER gb_copybuf',source)
        self.assertIn('#define GB_POPUP_CAPACITY GB_COPYMAX',source)


if __name__=='__main__': unittest.main()
