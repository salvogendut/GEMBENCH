from pathlib import Path
import tempfile
import sys
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from build_cpc_runtime import bitmap_assets, ICON_SOURCES
from cpc_runtime_bitmaps import fixture, BITMAP_CASES
from cpc_runtime_pixels import frame, cursor_grid, cursor_phases
import genfont


class BitmapAssetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp=tempfile.TemporaryDirectory(prefix='bitmap-assets-')
        cls.addClassCleanup(cls.tmp.cleanup)
        cls.work=Path(cls.tmp.name)
        bitmap_assets(cls.work)
        genfont.main(['genfont',str(cls.work/'DEFAULT.FNT')])

    def test_shared_policy_and_canonical_packaging(self):
        for target in ('kernel/assets.asm','kernel/cpc_bitmap_assets.asm'):
            self.assertIn('include "core/icon_asset.asm"',(ROOT/target).read_text())
        for target in ('kernel/gbkern.asm','kernel/cpc_bitmap_assets.asm'):
            for name in ('icon_full_geom.asm','icon_half_geom.asm'):
                self.assertIn('include "core/'+name+'"',(ROOT/target).read_text())
        self.assertEqual(len(ICON_SOURCES),21)
        msx=(ROOT/'tools/build_kernel_msx.sh').read_text().split('build/msx/DEFAULT.IST',1)[1].split('python3 tools/packicons.py',1)[0]
        import re
        self.assertEqual(tuple(re.findall(r'lib/icon_(\w+)\.asm',msx)),ICON_SOURCES)
        self.assertEqual((self.work/'REFINED.IST').read_bytes(),(ROOT/'assets/iconsets/REFINED.IST').read_bytes())
        self.assertEqual(len((self.work/'DEFAULT.SPR').read_bytes()),256)
        # A subset of native assets does not enable the complete reload ABI.
        self.assertIn('jp cpc_unavailable ; #80BA',(ROOT/'kernel/cpc_runtime_api.inc').read_text())

    def test_every_phase_preserves_masks_and_canonical_phase_two(self):
        for case in ('default','custom'):
            sprite=fixture(case,self.work,ROOT)['cursor'];phases=cursor_phases(sprite)
            self.assertEqual(phases[:128],sprite[:128])
            self.assertEqual(phases[256:384],sprite[128:])
            self.assertEqual(len(phases),512)
            for mask,ink in zip(phases[::2],phases[1::2]):
                self.assertEqual(mask&ink,0)
                self.assertEqual(mask&15,mask>>4)
        self.assertNotEqual(cursor_grid(fixture('default',self.work,ROOT)['cursor']),
                            cursor_grid(fixture('custom',self.work,ROOT)['cursor']))

    def test_oracle_sees_tile_phase_icons_transparency_and_cursor_changes(self):
        f=fixture('custom',self.work,ROOT)
        args=dict(rects={},order=[0],accents={},pointer=(319,199),font=(self.work/'DEFAULT.FNT').read_bytes(),
                  cursor=f['cursor'],backdrop=f['backdrop'],icons=f['icons'])
        reference=frame(**args)
        for field in ('cursor','backdrop','icons'):
            changed=dict(args);changed[field]=None
            self.assertNotEqual(reference,frame(**changed),field)
        changed=dict(args);changed['pointer']=(318,198)
        self.assertNotEqual(reference,frame(**changed))
        # Raster holes retain their boot sentinel even with a full tiled fill.
        self.assertEqual(reference[2000:2048],bytes((a>>8)^(a&255) for a in range(0xC7D0,0xC800)))

    def test_fixture_failure_matrix_has_explicit_fallbacks(self):
        self.assertEqual(len(set(BITMAP_CASES)),len(BITMAP_CASES))
        for case in BITMAP_CASES:
            f=fixture(case,self.work,ROOT)
            self.assertEqual(len(f['cursor']),256)
            self.assertTrue(f['backdrop'] is None or len(f['backdrop'])==64)
            self.assertTrue(f['icons'] is None or f['icons'][:5]==b'GBIS\x02')
            if case.startswith('icon-'):
                self.assertEqual(f['status'][0],2 if case=='icon-no-default' else 1)
            if case.startswith('cursor-'):
                self.assertEqual(f['status'][1],2 if case=='cursor-no-default' else 1)
            if case.startswith('tile-'): self.assertEqual(f['status'][2],1)


if __name__=='__main__': unittest.main()
