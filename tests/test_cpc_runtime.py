from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from build_cpc_runtime import assemble
from cpc_runtime_pixels import frame, verify_pixels
from cpc_graphics_fixture import address


@unittest.skipUnless(all(shutil.which(os.environ.get(k,k.lower())) for k in ('RASM','SDCC')),'RASM/SDCC required')
class RuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory(prefix='cpc-runtime-unit-')
        cls.addClassCleanup(cls.temp.cleanup)
        cls.work=Path(cls.temp.name);cls.sym=assemble(cls.work)

    def test_unified_link_addresses_and_capability_limits(self):
        s=self.sym;raw=(self.work/'CORE.RAW').read_bytes()
        self.assertLessEqual(len(raw),16384)
        self.assertEqual(s['mw_rect'],0x1448)
        self.assertEqual(s['core_pointer_x'],0x1306)
        self.assertEqual(s['core_pointer_y'],0x1307)
        self.assertEqual(s['core_input_flags'],0x1308)
        self.assertFalse(any(k.startswith(('cpc_fixture_','cpc_probe_','lp_','rt_','fp_')) for k in s))
        for offset in range(0,0xD8,3): self.assertEqual(raw[offset],0xC3)
        for offset,target in ((0x0C,'gb_text_draw'),(0x33,'k_fill'),(0x36,'cpc_save_rect'),
                              (0x39,'cpc_restore_rect'),(0x45,'cpc_getkey'),(0x60,'k_wm_open'),
                              (0xB1,'k_wm_managed'),(0xC3,'cpc_sysinfo'),(0xD5,'universal_parameters')):
            self.assertEqual(int.from_bytes(raw[offset+1:offset+3],'little'),s[target])
        # No MSX framebuffer mailboxes or unqualified filesystem/timer promises.
        self.assertEqual(s['cpc_runtime_caps_low'] & (0x1000|0x4000|0x4|0x8),0)
        self.assertEqual(s['cpc_runtime_caps_high'] & 0x60,0)
        self.assertTrue(s['cpc_runtime_caps_high'] & 0x10)
        for name in ('wm_loop','wm_raise','wm_repaint_all','k_app','k_defer','k_fsctx','gbap4_validate_loaded'):
            self.assertIn(name,s)

    def test_repeatable_build_and_bad_budget_rejection(self):
        again=self.work/'again';assemble(again)
        for name in ('CORE.RAW','SUPPORT.RAW','SCHED.RAW','HARDWARE.RAW','FSCTX.BIN'):
            self.assertEqual((self.work/name).read_bytes(),(again/name).read_bytes())
        with self.assertRaises(subprocess.CalledProcessError):
            assemble(self.work/'too-small',('-DCPC_KERNEL_END=#A000',))

    def test_pixel_observer_rejects_content_chrome_exposure_and_bar_damage(self):
        # Synthetic host observations challenge the checker; never injected into CPC.
        s=self.sym;rects={1:(11,66,58,68),2:(17,74,58,68)};order=[0,1,2];accents={1:0,2:1}
        ram=bytearray(512*1024)
        ram[s['pointer_x']:s['pointer_x']+2]=(40).to_bytes(2,'little');ram[s['pointer_y']]=30
        ram[0xC000:0x10000]=frame(rects,order,accents,(40,30),(self.work/'DEFAULT.FNT').read_bytes())
        verify_pixels(ram,s,self.work,rects,order,accents)
        for x,y in ((1,0),(15,68),(22,100),(73,105),(80,150),(40,30)):
            bad=bytearray(ram);bad[0xC000+address(x,y)]^=1
            with self.subTest(x=x,y=y),self.assertRaises(AssertionError):
                verify_pixels(bad,s,self.work,rects,order,accents)


if __name__=='__main__':unittest.main()
