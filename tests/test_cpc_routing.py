from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
from build_cpc_production import assemble
from cpc_production_routing import frame, check_state
from cpc_graphics_fixture import address

UNITS=("root_loop.asm","window_frame.asm","window_gestures.asm","menu_dispatch.asm","poll_publish.asm")
TOOLS=all(shutil.which(os.environ.get(k,k.lower())) for k in ("RASM","SDCC"))


class RoutingSourceTests(unittest.TestCase):
    def test_same_root_input_and_gesture_units_on_both_targets(self):
        msx=(ROOT/"kernel/gbkern.asm").read_text()+(ROOT/"kernel/input_api_msx.asm").read_text()
        cpc=(ROOT/"kernel/cpc_routing.asm").read_text()+(ROOT/"lib/cpc/poll.asm").read_text()
        for name in UNITS:
            for source in (msx,cpc): self.assertEqual(source.count(f'core/{name}"'),1)
            code="\n".join(l.split(";",1)[0] for l in (ROOT/"kernel/core"/name).read_text().splitlines())
            self.assertNotRegex(code,r"\b(?:PLATFORM_\w+|CPC_\w+|MSX_\w+)\b")
            self.assertNotRegex(code.lower(),r"\b(?:in|out|di|ei|halt|sp)\b")
        loop=(ROOT/"kernel/core/root_loop.asm").read_text()
        self.assertLess(loop.index("call  wm_map_focus"),loop.index("call  k_poll"))
        self.assertLess(loop.index("call  wm_focus_click"),loop.index('include "root_dispatch_phase.asm"'))
        self.assertIn("call  SCHED_YIELD_ENTRY",loop)
        self.assertIn("ROOT_LOOP_REPEAT",loop)

    def test_runner_drives_keys_and_never_injects_state(self):
        source=(ROOT/"tools/cpc_production_routing.py").read_text()
        self.assertIn('send("key-down SPACE")',source)
        self.assertIn('send("key-down ESCAPE")',source)
        self.assertIn('send("key-down F2")',source)
        self.assertNotIn('send("snapshot-load',source)
        self.assertNotRegex(source,r'send\(.*(?:poke|write-memory)')
        poll=(ROOT/"lib/cpc/poll.asm").read_text()
        self.assertIn("call cpc_input_scan",poll)
        self.assertIn("call cpc_window_pointer_hide",poll)
        self.assertIn("call cpc_window_pointer_show",poll)
        self.assertNotIn("wm_focus",poll)


@unittest.skipUnless(TOOLS,"RASM and SDCC required for native root-loop composition")
class RoutingAssemblyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory(prefix="geobench-routing-unit-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.work=Path(cls.temp.name)
        cls.sym=assemble(cls.work,"routing")

    def test_actual_link_budget_and_reproducibility(self):
        s=self.sym
        self.assertLessEqual(s["cpc_kernel_used_end"],0xC000)
        self.assertLess(s["cpc_routing_end"]-s["cpc_routing_begin"],1024)
        self.assertLessEqual(s["mwm_notify"]+1,s["core_lookup_class"])
        self.assertEqual(s["poll_flags"],s["core_input_flags"])
        self.assertEqual(s["app_handler"],s["core_focus_handler"])
        again=self.work/"again"
        assemble(again,"routing")
        for name in ("CORE.RAW","SUPPORT.RAW","SCHED.RAW","HARDWARE.RAW","BOOT.RAW","TIMER.BIN"):
            self.assertEqual((again/name).read_bytes(),(self.work/name).read_bytes())

    def test_contract_rejects_invalid_native_offsets_and_bounds(self):
        cells=dict(WM_ESZ=25,WM_FR_FRAME=5,WM_FR_FLAGS=13,SCR_COLS=80,SCR_LINES=200)
        for name,value in ((None,0),("WM_ESZ",24),("WM_FR_FRAME",6),("WM_FR_FLAGS",12),
                           ("SCR_COLS",256),("SCR_LINES",23)):
            values={**cells}
            if name: values[name]=value
            source="\n".join(f"{k} equ {v}" for k,v in values.items())
            source+=f'\ninclude "{ROOT}/kernel/core/input_routing_contract.inc"\norg #8000\nret\n'
            path=self.work/"contract.asm"
            path.write_text(source)
            result=subprocess.run([os.environ.get("RASM","rasm"),str(path)],cwd=self.work,capture_output=True)
            with self.subTest(name=name): self.assertEqual(result.returncode==0,name is None)

    def test_frame_oracle_rejects_stale_pixels_and_identity_corruption(self):
        # Host-only fixture for challenging the checker, not claimed execution.
        s=self.sym
        rects={0:(0,0,80,200),1:(8,20,24,30),2:(40,60,24,40)}
        ram=bytearray(512*1024)
        ram[s["wm_focus"]]=2
        ram[s["wm_nwin"]]=3
        ram[s["wm_z"]:s["wm_z"]+3]=bytes((0,1,2))
        for slot,rect in rects.items():
            at=s["wm_table"]+25*slot
            ram[at:at+5]=bytes((0xC4 if slot==1 else 0xC0,*rect))
        ram[s["sched_lock"]]=1
        ram[s["bank_cur"]]=0xC0
        ram[s["pointer_visible"]]=1
        ram[s["wm_clip_x"]:s["wm_clip_x"]+4]=bytes((0,0,80,200))
        ram[s["pointer_x"]]=8
        ram[s["poll_byte"]]=2
        ram[s["pointer_y"]]=ram[s["poll_line"]]=180
        font=(self.work/"DEFAULT.FNT").read_bytes()
        pixels=frame(rects,[0,1,2],8,180,font)
        ram[0xC000:0x10000]=pixels
        for name in ("cpc_reg_guard","cpc_reg_end","cpc_wm_guard","cpc_wm_end","cpc_draw_state_guard","cpc_draw_state_end"):
            ram[s[name]:s[name]+16]=b"\xD7"*16
        check_state(ram,s,self.work,rects,[0,1,2],2,"unit")
        for at in (s["bank_cur"],s["wm_focus"],s["wm_z"],s["wm_table"]+26,s["pointer_x"],
                   s["sched_current"],s["core_pointer_paintlock"],s["cpc_reg_guard"],
                   0xC000+address(8,180),0xC000+address(40*4,60),0xC7FE):
            bad=bytearray(ram)
            bad[at]^=1
            with self.subTest(at=at),self.assertRaises(AssertionError):
                check_state(bad,s,self.work,rects,[0,1,2],2,"unit")
        moved={**rects,2:(47,70,24,40)}
        after=frame(moved,[0,1,2],8,180,font)
        allowed={address(x*4,y) for x in range(40,71) for y in range(60,110)}
        changed={i for i,(a,b) in enumerate(zip(pixels,after)) if a!=b}
        self.assertTrue(changed)
        self.assertLessEqual(changed,allowed)


if __name__=="__main__": unittest.main()
