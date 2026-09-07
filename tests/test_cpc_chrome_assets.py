from pathlib import Path
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from cpc_runtime_chrome import CHROME_CASES, fixture
from cpc_runtime_pixels import DEFAULT_THEME, frame
import genfont


class ChromeAssetTests(unittest.TestCase):
    def test_shared_selection_and_renderer_are_used_by_both_targets(self):
        for name in ('apps/desktop/main.c','kernel/kc/cpc_chrome_config.inc'):
            source=(ROOT/name).read_text()
            for shared in ('config_value.inc','chrome_select.inc','chrome_keys.inc'):
                self.assertIn(shared,source)
        self.assertIn('core/title_pattern.asm',(ROOT/'kernel/modules/gbtitle.asm').read_text())
        self.assertIn('core/title_pattern.asm',(ROOT/'kernel/cpc_title_module.asm').read_text())
        self.assertIn('core/window_chrome.asm',(ROOT/'kernel/cpc_registration.asm').read_text())
        self.assertIn('jp cpc_unavailable ; #80BA',(ROOT/'kernel/cpc_runtime_api.inc').read_text())

    def test_admission_fixtures_preserve_independent_asset_precedence(self):
        module=DEFAULT_THEME+bytes(384-106)
        fixtures={c:fixture(c,ROOT,module) for c in CHROME_CASES}
        self.assertEqual(len(fixtures),len(CHROME_CASES))
        for f in fixtures.values(): self.assertEqual(len(f['theme']),106)
        self.assertEqual(fixtures['legacy']['theme'],fixtures['custom']['theme'])
        self.assertNotEqual(fixtures['legacy-no-gadgets']['theme'][56:],fixtures['legacy']['theme'][56:])
        for name in ('title-short','title-trailing','legacy-short','legacy-trailing','title-oversized'):
            self.assertEqual(fixtures[name]['theme'][:56],DEFAULT_THEME[:56])
        for name in ('module-missing','module-short','module-trailing'):
            self.assertFalse(fixtures[name]['ready'])
            self.assertEqual(fixtures[name]['theme'],DEFAULT_THEME)
        full=fixtures['full-config']
        self.assertEqual(len(full['files']['/GEOBENCH.CFG']),512)
        self.assertEqual(full['names'][0],b'LAST    TBR')
        self.assertEqual(fixtures['unsafe-name']['names'][0],b'        TBR')

    def test_pixel_oracle_distinguishes_tile_gadgets_phase_and_plain_recovery(self):
        with tempfile.TemporaryDirectory(prefix='chrome-oracle-') as tmp:
            path=Path(tmp)/'DEFAULT.FNT';genfont.main(['genfont',str(path)])
            font=path.read_bytes()
        args=dict(rects={1:(11,66,58,68),2:(14,70,58,68)},order=[0,1,2],accents={1:0,2:0},
                  pointer=(303,190),font=font)
        default=frame(**args)
        custom=fixture('custom',ROOT,DEFAULT_THEME+bytes(278))['theme']
        self.assertNotEqual(default,frame(**args,theme=custom))
        self.assertNotEqual(default,frame(**args,theme=DEFAULT_THEME[:56]+custom[56:]))
        self.assertNotEqual(default,frame(**args,theme=custom[:56]+DEFAULT_THEME[56:]))
        self.assertNotEqual(default,frame(**args,title_ready=False))
        phased=bytes(custom[y*4+(x+1)%4] for y in range(14) for x in range(4))+custom[56:]
        self.assertNotEqual(frame(**args,theme=custom),frame(**args,theme=phased))


if __name__=='__main__': unittest.main()
