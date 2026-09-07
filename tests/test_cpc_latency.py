from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from cpc_runtime_latency import check_latency


class LatencyTests(unittest.TestCase):
    def test_checker_rejects_stalls_slow_movement_and_disabled_seconds(self):
        baseline = dict(case='idle', steps_per_second=49., max_gap_ticks=6,
                        seconds=False, draws=0, still_frames=0, irq_frame_ratio=1.)
        ticking = dict(case='ticking', steps_per_second=48., max_gap_ticks=10,
                       seconds=True, draws=30, still_frames=0, irq_frame_ratio=1.)
        check_latency([baseline, ticking])
        for change in ({'max_gap_ticks': 36}, {'max_gap_ticks': 70},
                       {'steps_per_second': 22.4}, {'draws': 0},
                       {'still_frames': 3}):
            with self.subTest(change=change), self.assertRaises(AssertionError):
                check_latency([baseline, {**ticking, **change}])
        # A software IRQ clock may lose ticks during native critical sections.
        # Never use that slower clock to inflate the measured pointer rate.
        check_latency([baseline, {**ticking, 'irq_frame_ratio': .95}])
        with self.assertRaises(AssertionError):
            check_latency([baseline, {**ticking, 'steps_per_second': 43.94,
                                      'irq_frame_ratio': .89}])

    def test_safe_point_does_not_reenter_policy_or_move_input_into_irq(self):
        poll = (ROOT/'lib/cpc/poll.asm').read_text()
        service = poll.split('\ncpc_pointer_service\n', 1)[1].split('\ncpc_pointer_sample\n', 1)[0]
        for cell in ('SCHED_CURRENT', 'SCHED_LOCK', 'CORE_POINTER_SUPPRESSED',
                     'CORE_POINTER_PAINTLOCK', 'pointer_visible'):
            self.assertIn(cell, service)
        for forbidden in ('wm_raise', 'wm_focus', 'menu_dispatch', 'bank_set'):
            self.assertNotIn(forbidden, service)
        self.assertLess(service.index('ld (SCHED_LOCK),a'), service.index('ei\n'))
        self.assertLess(service.index('ei\n'), service.index('call cpc_pointer_sample'))
        irq = (ROOT/'lib/cpc/irq.asm').read_text()
        self.assertNotIn('cpc_input_scan', irq)
        self.assertNotIn('pointer_', irq)
        provider = (ROOT/'lib/cpc/window.asm').read_text()
        callback = provider.split('\ncpc_window_call\n', 1)[1].split('\ncpc_window_pointer_hide\n', 1)[0]
        self.assertLess(callback.index('ei\n'), callback.index('jp (hl)'))
        root = (ROOT/'kernel/cpc_runtime_boot.asm').read_text().split('\ncpc_root_bar\n', 1)[1]
        self.assertLess(root.index('call cpc_timer_collect'), root.index('call clip_set_full'))
        self.assertLess(root.index('call clip_set_full'), root.index('call cpc_bar_payload+3'))
        parameters = (ROOT/'kernel/cpc_parameter_provider.inc').read_text()
        self.assertIn('call cpc_pointer_service', parameters)
        enter = parameters.split('macro PARAM_ENTER', 1)[1].split('mend', 1)[0]
        self.assertLess(enter.index('ld (CORE_PARAM_LOCK),a'), enter.index('ei\n'))
        sample = poll.split('\ncpc_pointer_sample\n', 1)[1]
        self.assertIn('CORE_COMPOSITOR_DAMAGE', sample)
        self.assertNotIn('ld (WM_CLIP_', sample)

    @unittest.skipUnless(shutil.which('cc'), 'host C compiler required')
    def test_actual_clock_geometry_cache_preserves_rounding_and_translation(self):
        # Compile the actual pure geometry functions from the universal APP,
        # without mocking Z80 ABI record sizes or reimplementing the cache.
        source = (ROOT/'apps/uclock/main.c').read_text()
        declarations = 'static int cx'+source.split('static int cx', 1)[1].split(
            'static unsigned char binary_time', 1)[0]
        functions = 'static void relayout(void)'+source.split('static void relayout(void)', 1)[1].split(
            'static char digits', 1)[0]
        harness = r'''
#include <assert.h>
#include <string.h>
#define TITLE_H 14u
#define GB_UI_SURFACE 1u
static unsigned char win_x, win_y, win_w, win_h;
static unsigned lines;
static void gb_line(unsigned int x, unsigned int y, unsigned int xx,
                    unsigned int yy, unsigned char pen) {
    (void)x; (void)y; (void)xx; (void)yy; (void)pen; ++lines;
}
'''+declarations+functions+r'''
static void check_point(clock_point p, unsigned k, unsigned rad) {
    assert(p.x == (long)SIN64[k] * rad * aspect_x / 16384L);
    assert(p.y == -(int)COS64[k] * (int)rad / 64);
}
int main(void) {
    static const unsigned aspects[] = {128,256,384,461,512};
    unsigned aspect, width, height, k;
    for (aspect=0; aspect<sizeof(aspects)/sizeof(aspects[0]); ++aspect)
    for (width=22; width<=80; width+=29)
    for (height=96; height<=192; height+=48) {
        clock_point saved[30];
        aspect_x=aspects[aspect]; win_w=width; win_h=height; win_x=0; win_y=8;
        geometry_ready=0; relayout();
        for (k=0; k<30; ++k) check_point(rim[k], k*2, rr);
        for (k=0; k<12; ++k) {
            check_point(ticks[k*2], k*5, rr);
            check_point(ticks[k*2+1], k*5, tick_in);
        }
        for (k=0; k<60; ++k) {
            check_point(hand_points[0][k], k, l_hour);
            check_point(hand_points[1][k], k, l_min);
            check_point(hand_points[2][k], k, l_sec);
        }
        /* Sentinel proves a position-only relayout does not recompute it. */
        rim[0].x=1234; memcpy(saved,rim,sizeof saved);
        win_x=4; win_y=10; relayout();
        assert(!memcmp(saved,rim,sizeof saved));
        assert(cx == win_x*4+win_w*2);
        geometry_ready=0; relayout();
        lines=0; draw_face(); assert(lines==42);
        hands(11,59,59,1,1,3); assert(lines==45);
        /* A resize really must invalidate the cached radius. */
        win_h=64; relayout();
        for (k=0; k<30; ++k) check_point(rim[k], k*2, rr);
    }
    return 0;
}
'''
        with tempfile.TemporaryDirectory(prefix='clock-geometry-') as dirname:
            work = Path(dirname)
            (work/'check.c').write_text(harness)
            subprocess.run(['cc', '-std=c99', '-Wall', '-Wextra', str(work/'check.c'),
                            '-o', str(work/'check')], check=True)
            subprocess.run([str(work/'check')], check=True)


if __name__ == '__main__': unittest.main()
