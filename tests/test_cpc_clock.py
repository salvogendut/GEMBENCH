from pathlib import Path
import sys
import unittest
import tempfile

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from cpc_runtime_pixels import frame
from cpc_graphics_fixture import address
import genfont


class ClockTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory(prefix='cpc-clock-unit-')
        cls.addClassCleanup(cls.temp.cleanup)
        path=Path(cls.temp.name)/'DEFAULT.FNT'
        genfont.main(['genfont',str(path)])
        cls.font=path.read_bytes()

    def test_shared_clock_and_collector_are_bound_not_forked(self):
        builder=(ROOT/'tools/build_cpc_runtime.py').read_text()
        self.assertIn('"apps/uclock"',builder)
        self.assertIn('"UNIVERSAL_TASK": "1"',builder)
        self.assertIn('compile_timer(work, initial, ROOT)',builder)
        boot=(ROOT/'kernel/cpc_runtime_boot.asm').read_text()
        self.assertLess(boot.index('call cpc_timer_collect'),boot.index('call cpc_bar_payload+3'))
        self.assertIn('and #40',boot.split('\ncpc_runtime_clock\n',1)[1].split('jp cpc_bar_payload+9',1)[0])
        keyboard=(ROOT/'lib/cpc/runtime_input.asm').read_text()
        self.assertEqual(keyboard.count("db 0,0,0,'8',0,'1',0,'0'"),2)
        for name in ('kernel/cpc_window_provider.inc','kernel/msx_window_damage.inc'):
            self.assertIn('CORE_PAINT_TIMER_OWNER equ',(ROOT/name).read_text())
        source=(ROOT/'apps/uclock/main.c').read_text()
        active=source.split('if (gb_timer_active_for(clock_window_handle)) {',1)[1].split('return;',1)[0]
        self.assertLess(active.index('draw_face();'),active.index('hands(h, m, s'))

    def test_oracle_has_no_changed_pixels_through_an_opaque_cover(self):
        font=self.font
        def image(cover,second):
            return frame({1:(26,20,28,122),2:cover},[0,1,2],{},(4,180),font,
                         titles={1:'Clock',2:'Calculator'},calculators={2:'0'},clocks={1:(0,0,second,1)})
        self.assertEqual(image((24,8,31,144),8),image((24,8,31,144),12))
        before,after=image((39,24,31,144),35),image((39,24,31,144),40)
        changes=[(x,y) for y in range(200) for x in range(80)
                 if before[address(x*4,y)]!=after[address(x*4,y)]]
        self.assertTrue(changes)
        self.assertTrue(all(26<=x<39 and 34<=y<141 for x,y in changes))

    def test_oracle_rejects_the_reproduced_dial_rim_gap(self):
        actual=frame({1:(26,20,28,122)},[0,1],{},(4,180),self.font,
                     titles={1:'Clock'},clocks={1:(0,0,12,1)})
        damaged=bytearray(actual)
        # Real pre-fix missing rim/tick pixel from the M4 background run.
        at=address(48*4,56)
        self.assertNotEqual(actual[at],0)
        damaged[at]=0
        self.assertNotEqual(bytes(damaged),actual)

    def test_hidden_clock_does_not_need_cpu_to_settle_a_pending_component(self):
        from cpc_runtime_clock import clock_cache_ready,clock_may_remain_parked
        values=dict(have_prev=1,timer_digit_due=1,ph=0,pm=0,ps=54,
                    dh=0,dm=0,ds=53,show_sec=1)
        self.assertFalse(clock_cache_ready(values.get))
        rects={2:(26,20,28,122),3:(25,9,31,144)}
        self.assertTrue(clock_may_remain_parked(rects,[0,2,3],2,0,0))
        for window,task in ((1,0),(0,1),(3,3)):
            self.assertFalse(clock_may_remain_parked(rects,[0,2,3],2,window,task))
        self.assertFalse(clock_may_remain_parked(rects,[0,3,2],2,0,0))
        rects[3]=(39,24,31,144) # exposed left side: stale caches are not accepted
        self.assertFalse(clock_may_remain_parked(rects,[0,2,3],2,0,0))


if __name__=='__main__': unittest.main()
