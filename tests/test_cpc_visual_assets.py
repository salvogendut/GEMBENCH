from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from cpc_runtime_assets import ASSET_CASES, HW_RGB, asset_fixture, firmware_rgb
from cpc_runtime_pixels import frame
import genfont


class VisualAssetTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which(os.environ.get('CC','cc')),'C compiler required')
    def test_clipped_bar_repaint_cannot_publish_full_menu_cache(self):
        with tempfile.TemporaryDirectory(prefix='bar-damage-') as tmp:
            output=Path(tmp)/'bar-damage'
            subprocess.run([os.environ.get('CC','cc'),'-std=c99','-Wall','-Wextra','-Werror',
                            str(ROOT/'tests/cpc_bar_damage_test.c'),'-o',str(output)],check=True)
            subprocess.run([str(output)],check=True)

    def test_hardware_palette_matches_all_canonical_colours(self):
        source=(ROOT/'kernel/cpc_visual_assets.asm').read_text().split('cpc_firmware_inks db ',1)[1]
        table=[int(n,16) for n in re.findall(r'#([0-9A-F]{2})',source)]
        self.assertEqual(len(table),27)
        self.assertEqual([HW_RGB[command&31] for command in table],
                         [firmware_rgb(i) for i in range(27)])
        self.assertTrue(all(0x40<=command<=0x5F for command in table))

    def test_same_font_policy_and_renderer_not_a_second_desktop(self):
        for name in ('kernel/assets.asm','kernel/cpc_visual_assets.asm'):
            self.assertIn('include "core/font_asset.asm"',(ROOT/name).read_text())
        source=(ROOT/'kernel/core/font_asset.asm').read_text()
        self.assertIn('call  load_or_default',source)
        self.assertIn('call  FONT_APPLY',source)
        api=(ROOT/'kernel/cpc_runtime_api.inc').read_text()
        self.assertIn('jp cpc_unavailable ; #80BA',api) # partial asset family, no false GB_RELOAD

    def test_font_frame_oracle_and_fault_fixtures_are_distinct(self):
        with tempfile.TemporaryDirectory(prefix='font-oracle-') as tmp:
            path=Path(tmp)/'DEFAULT.FNT'
            genfont.main(['genfont',str(path)])
            default=path.read_bytes()
        normal=asset_fixture('default',default)
        custom=asset_fixture('custom',default)
        kwargs=dict(rects={1:(11,66,58,68)},order=[0,1],accents={1:0},pointer=(40,30))
        a=frame(**kwargs,font=normal['font'],frame_pen=2)
        self.assertNotEqual(a,frame(**kwargs,font=custom['font'],frame_pen=2))
        self.assertNotEqual(a,frame(**kwargs,font=normal['font'],frame_pen=1))
        self.assertNotEqual(a,frame(**kwargs,font=normal['font'],frame_pen=3))
        fixtures=[asset_fixture(case,default) for case in ASSET_CASES]
        self.assertEqual(len(fixtures),19)
        for fixture in fixtures:
            self.assertEqual(len(fixture['font']),816)
            self.assertEqual(fixture['font'][:10],b'GBFN\x01\x20\x83\x06\x08\x01')
        self.assertGreater(len(asset_fixture('reader-oversized',default)['files']['/GBENCH/ALTERN.FNT']),0x3F00)


if __name__=='__main__': unittest.main()
