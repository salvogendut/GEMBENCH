from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]


class NativeModuleTests(unittest.TestCase):
    def test_modal_clock_observer_does_not_wait_for_parked_work(self):
        sys.path.insert(0,str(ROOT/'tools'))
        from cpc_runtime_clock import clock_cache_ready
        state=dict(have_prev=1,timer_digit_due=1,ph=0,pm=1,ps=33,dh=0,dm=1,ds=32,show_sec=1)
        self.assertFalse(clock_cache_ready(state.__getitem__))
        self.assertTrue(clock_cache_ready(state.__getitem__,modal=True))
        state.update(timer_digit_due=0,ds=33)
        self.assertTrue(clock_cache_ready(state.__getitem__))
        state['have_prev']=0
        self.assertFalse(clock_cache_ready(state.__getitem__,modal=True))

    def test_modal_clock_oracle_checks_hand_and_digit_caches_separately(self):
        sys.path.insert(0,str(ROOT/'tools'))
        from cpc_runtime_clock import draw_clock
        def render(time):
            pixels=bytearray(16384);labels=[]
            draw_clock(pixels,(26,20,28,122),time,lambda *args:None,
                       lambda image,x,y,value,pen,paper:labels.append(value))
            return pixels,labels
        mixed=render((0,0,32,1,0,0,31))
        same_hands=render((0,0,32,1))
        same_digits=render((0,0,31,1))
        self.assertEqual(mixed[0],same_hands[0])
        self.assertNotEqual(mixed[0],same_digits[0])
        self.assertEqual(mixed[1],['00:00:31'])
        self.assertNotEqual(mixed[1],same_hands[1])

    @unittest.skipUnless(shutil.which(os.environ.get('CC','cc')),'C compiler required')
    def test_actual_ui_dispatch_and_bounded_profile(self):
        with tempfile.TemporaryDirectory(prefix='native-ui-') as tmp:
            output=Path(tmp)/'native-ui'
            subprocess.run([os.environ.get('CC','cc'),'-std=c99','-Wall','-Wextra','-Werror',
                            '-I',str(ROOT/'lib/gb'),str(ROOT/'tests/native_ui_test.c'),
                            '-o',str(output)],check=True)
            subprocess.run([str(output)],check=True)

    def test_common_module_transaction_and_explicit_provider(self):
        for name in ('kernel/modules.asm','kernel/cpc_native_modules.asm'):
            source=(ROOT/name).read_text()
            self.assertIn('include "core/data_module.asm"',source)
            self.assertIn('include "core/ui_module.asm"',source)
        source=(ROOT/'tools/cpc_native_modules.py').read_text()
        for name in ('kcfg_mod.c','kcfg.c','gbui_mod.c','gbdlg.c','gbprompt.c'):
            self.assertIn(name,source)
        self.assertIn('GBUI_BASIC_ONLY',source)
        self.assertNotIn('gbpick.c',source)
        self.assertIn('CPC_POOL_PAGES equ 27',(ROOT/'lib/cpc/production_layout.inc').read_text())


if __name__=='__main__': unittest.main()
