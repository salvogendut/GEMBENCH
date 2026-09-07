from pathlib import Path
import os
import json
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
                              (0xAE,'cpc_ui'),(0xB1,'k_wm_managed'),(0xC0,'cpc_shell'),(0xC3,'cpc_sysinfo'),(0xD5,'universal_parameters')):
            self.assertEqual(int.from_bytes(raw[offset+1:offset+3],'little'),s[target])
        # No MSX framebuffer mailboxes or unqualified filesystem/timer promises.
        self.assertEqual(s['cpc_runtime_caps_low'] & (0x1000|0x4000|0x4|0x40),0)
        abi=json.loads((ROOT/'abi/geobench-v2.json').read_text())
        # The shell mask is frozen by the ABI; do not admit Calculator by
        # advertising an unrelated service or weakening its package manifest.
        self.assertTrue(s['cpc_runtime_caps_low'] & abi['capabilities']['low_word_inherited']['shell'])
        self.assertEqual(s['cpc_runtime_caps_high'] & 0x20,0)
        self.assertTrue(s['cpc_runtime_caps_high'] & 0x40)
        self.assertEqual(raw[s['cpc_timer_collect']-0x8000:s['cpc_timer_payload_end']-0x8000],
                         (self.work/'TIMER.BIN').read_bytes())
        self.assertTrue(s['cpc_runtime_caps_high'] & 0x10)
        for name in ('wm_loop','wm_raise','wm_repaint_all','k_app','k_defer','k_fsctx','gbap4_validate_loaded'):
            self.assertIn(name,s)
        self.assertEqual(s['menu_def'],0x1310)
        self.assertEqual(s['cpc_set_menu'],s['k_menu'])
        self.assertEqual(s['cpc_menu_install'],s['menu_install'])
        self.assertLessEqual(s['menu_def']+37,s['wm_clip_x'])
        bar=json.loads((self.work/'bar_layout.json').read_text())
        self.assertLessEqual(bar['used'],bar['budget'])
        self.assertLessEqual(bar['data_used'],bar['data_budget'])
        self.assertEqual(bar['data_base'],0x6000) # root C0, separate from code and F7 I/O
        self.assertEqual(bar['base'],0x4000)
        self.assertEqual(len((self.work/'ROOTBAR.BIN').read_bytes()),s['cpc_bar_end']-s['cpc_bar_payload'])
        self.assertLessEqual(s['cpc_bar_end'],s['cpc_bar_data'])
        self.assertLessEqual(s['cpc_bar_data_end'],0x6100)
        self.assertGreaterEqual(s['cpc_root_popup'],0x6300)
        self.assertLessEqual(s['cpc_root_popup_end'],0x7F00)
        self.assertEqual(s['cpc_pool_pages'],27)
        pool=raw[s['cpc_memory_pages']-0x8000:s['cpc_memory_pages']-0x8000+s['cpc_pool_pages']]
        self.assertNotIn(s['cpc_system_page'],pool)
        self.assertNotIn(s['cpc_data_page'],pool)
        self.assertEqual(s['cpc_ui_request'],0x1700)
        self.assertLessEqual(s['cpc_ui_request_end'],s['cpc_cfg_output'])
        self.assertLessEqual(s['cpc_cfg_text_end'],0x1200)
        self.assertLessEqual(s['cpc_native_module_state_end'],s['cpc_font_status'])
        self.assertLessEqual(s['cpc_visual_state_end'],s['cpc_native_state_end'])
        self.assertEqual(s['cpc_font_base'],0x4000)
        self.assertGreaterEqual(s['data_icons'],s['cpc_app_io_end'])
        self.assertLessEqual(s['cpc_icon_limit'],s['cpc_app_limit'])
        self.assertLessEqual(s['cpc_bd_tile']+64,s['pointer_background'])
        self.assertLessEqual(s['pointer_background']+64,s['cpc_native_state_end'])
        self.assertEqual((s['cpc_pointer_width'],s['cpc_pointer_height']),(4,16))
        self.assertLessEqual(s['cpc_font_limit'],s['cpc_fs_module'])
        self.assertLessEqual(s['cpc_font_end']-s['cpc_font_payload'],s['cpc_font_limit']-s['cpc_font_base'])
        self.assertLessEqual(s['cpc_module_code_end'],s['cpc_module_data'])
        self.assertLessEqual(s['cpc_module_data_end'],s['cpc_ui_under'])
        self.assertLessEqual(s['cpc_ui_under_end'],s['cpc_ui_popup'])
        self.assertLessEqual(s['cpc_ui_popup_end'],0x7F00)
        for name in ('GBCFG','GBUI'):
            self.assertEqual(len((self.work/(name+'.MOD')).read_bytes()),
                             s['cpc_module_code_end']-s['cpc_module_base'])

    def test_repeatable_build_and_bad_budget_rejection(self):
        again=self.work/'again';assemble(again)
        for name in ('CORE.RAW','SUPPORT.RAW','SCHED.RAW','HARDWARE.RAW','FSCTX.BIN','ROOTBAR.BIN','GBCFG.MOD','GBUI.MOD'):
            self.assertEqual((self.work/name).read_bytes(),(again/name).read_bytes())
        with self.assertRaises(subprocess.CalledProcessError):
            assemble(self.work/'too-small',(f'-DCPC_KERNEL_END={0xA000}',))
        with self.assertRaises(AssertionError):
            assemble(self.work/'root-too-small',(f'-DCPC_ROOT_CODE_END={0x4400}',))
        with self.assertRaises(subprocess.CalledProcessError):
            assemble(self.work/'root-overlap',(f'-DCPC_ROOT_CODE_END={0x6100}',))
        with self.assertRaises(subprocess.CalledProcessError):
            assemble(self.work/'module-overlap',(f'-DCPC_MODULE_CODE_END={0x5900}',))
        with self.assertRaises(subprocess.CalledProcessError):
            assemble(self.work/'font-overlap',(f'-DCPC_FONT_LIMIT={0x4500}',))
        with self.assertRaises(subprocess.CalledProcessError):
            assemble(self.work/'icon-overlap',(f'-DCPC_ICON_LIMIT={0x8000}',))
        with self.assertRaises(subprocess.CalledProcessError):
            assemble(self.work/'icons-too-small',(f'-DCPC_ICON_LIMIT={0x7000}',))

    def test_pixel_observer_rejects_content_chrome_exposure_and_bar_damage(self):
        # Synthetic host observations challenge the checker; never injected into CPC.
        s=self.sym;rects={1:(11,66,58,68),2:(17,74,58,68)};order=[0,1,2];accents={1:0,2:1}
        ram=bytearray(512*1024)
        ram[s['pointer_x']:s['pointer_x']+2]=(40).to_bytes(2,'little');ram[s['pointer_y']]=30
        ram[0xC000:0x10000]=frame(rects,order,accents,(40,30),(self.work/'DEFAULT.FNT').read_bytes(),
                                 cursor=(self.work/'DEFAULT.SPR').read_bytes())
        verify_pixels(ram,s,self.work,rects,order,accents)
        for x,y in ((1,0),(15,68),(22,100),(73,105),(80,150),(40,30)):
            bad=bytearray(ram);bad[0xC000+address(x,y)]^=1
            with self.subTest(x=x,y=y),self.assertRaises(AssertionError):
                verify_pixels(bad,s,self.work,rects,order,accents)


if __name__=='__main__':unittest.main()
