from __future__ import annotations

import os
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT / "tools"))
from build_cpc_production import assemble
from cpc_graphics_fixture import address
from cpc_production_registration import INPUTS, expected, verify_registration
from cpc_production_lifetime import NATIVES, physical
import check_gembench_abi as abi_check

UNITS=("window_register.asm","window_slot.asm","managed_window.asm",
       "window_chrome.asm","frame_draw.asm")
RASM=shutil.which(os.environ.get("RASM","rasm"))


class RegistrationSourceTests(unittest.TestCase):
    def test_frozen_abi_audit_follows_shared_units_and_rejects_unsafe_changes(self):
        manifest=json.loads(abi_check.DEFAULT_MANIFEST.read_text())
        errors=[]
        abi_check.check_registration(manifest,errors)
        self.assertEqual(errors,[])
        with tempfile.TemporaryDirectory(prefix="geobench-native-abi-") as tmp:
            for name,before,after in (("MANAGED_CORE","bit   4,(hl)","bit   3,(hl)"),
                                      ("MANAGED_CORE","de,12","de,13"),
                                      ("REGISTER_CORE","set   4,(hl)","set   3,(hl)")):
                source=getattr(abi_check,name).read_text()
                self.assertIn(before,source)
                altered=Path(tmp)/"unit.asm"
                altered.write_text(source.replace(before,after))
                with patch.object(abi_check,name,altered):
                    errors=[]
                    abi_check.check_registration(manifest,errors)
                    self.assertTrue(errors)

    def test_msx_and_cpc_use_the_same_registration_and_chrome(self):
        msx=(ROOT / "kernel/gbkern.asm").read_text()
        cpc=(ROOT / "kernel/cpc_registration.asm").read_text()
        for name in UNITS:
            for link in (msx,cpc):
                self.assertEqual(link.count(f'include "core/{name}"'),1)
            source=(ROOT / "kernel/core" / name).read_text()
            code="\n".join(line.split(";",1)[0] for line in source.splitlines())
            self.assertNotRegex(code,r"\b(?:PLATFORM_\w+|CPC_\w+|MSX_\w+)\b")
            self.assertNotRegex(code.lower(),r"\b(?:out|in|di|ei|halt|sp)\b")
        managed=(ROOT / "kernel/core/managed_window.asm").read_text()
        kind=managed.split("mw_kind_load\n",1)[1].split("CHROME_KIND_STORAGE",1)[0]
        self.assertNotIn("WM_FOCUS",kind)
        self.assertIn("CHROME_ENTRY_FLAGS",kind)
        self.assertIn("ret   z",kind)       # opt-in before reading desc+12
        provider=(ROOT / "kernel/cpc_support.asm").read_text()
        self.assertIn("ld a,(wm_slot)",provider)  # owner binding precedes focus assignment


@unittest.skipUnless(RASM,"RASM required for actual native registration/chrome link")
class RegistrationAssemblyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory(prefix="geobench-registration-unit-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.work=Path(cls.temp.name)
        cls.sym=assemble(cls.work,"registration")
        cls.states=expected((cls.work / "DEFAULT.FNT").read_bytes())

    def test_link_budget_state_separation_and_reassembly(self):
        s=self.sym
        self.assertLess(s["cpc_registration_end"]-s["cpc_registration_begin"],1024)
        self.assertLessEqual(s["cpc_kernel_used_end"],0xC000)
        self.assertEqual(s["wm_slot"],s["core_focus_target"])
        self.assertEqual(s["kw_title"]+49,s["gf_x"])
        self.assertLessEqual(s["cpc_wm_end"]+16,s["cpc_reg_guard"])
        self.assertLessEqual(s["cpc_reg_end"]+16,s["cpc_future_state_end"])
        again=self.work / "again"
        assemble(again,"registration")
        for name in ("CORE.RAW","SUPPORT.RAW","SCHED.RAW","BOOT.RAW"):
            self.assertEqual((again/name).read_bytes(),(self.work/name).read_bytes())

    def test_native_contract_rejects_layout_drift(self):
        cells=dict(WM_ESZ=25,WM_FR_FRAME=5,WM_FR_EVENT=9,WM_FR_FLAGS=13,
                   WM_MAXWIN=8,CORE_WINDOW_MAX=8)
        for changed in (None,"WM_ESZ","WM_FR_FRAME","WM_FR_EVENT","WM_FR_FLAGS","WM_MAXWIN"):
            values={**cells}
            if changed: values[changed]-=1
            source="\n".join(f"{k} equ {v}" for k,v in values.items())
            source+=f'\ninclude "{ROOT}/kernel/core/window_registration_contract.inc"\norg #8000\nret\n'
            path=self.work/"contract.asm"
            path.write_text(source)
            result=subprocess.run([RASM,str(path)],cwd=self.work,capture_output=True)
            with self.subTest(changed=changed):
                self.assertEqual(result.returncode==0,changed is None)

    def test_oracle_covers_damage_kind_and_capacity_boundaries(self):
        states=self.states
        self.assertEqual(states[6]["order"],list(range(8)))
        self.assertEqual(states[6]["frame"],states[7]["frame"])
        self.assertEqual(states[7]["frame"],states[8]["frame"])
        self.assertEqual(states[13]["generations"][5],2)
        self.assertEqual(states[13]["windows"][5]["native"],0xC4)
        self.assertEqual(states[15]["order"],[0,1])
        self.assertEqual(states[14]["callbacks"],{2})
        self.assertIn(2,states[2]["callbacks"])   # background legacy under explicit titleless focus
        allowed={address(x*4,y) for x in range(19,21) for y in range(43,46)}
        changed={i for i,(a,b) in enumerate(zip(states[13]["frame"],states[14]["frame"])) if a!=b}
        self.assertLessEqual(changed,allowed)
        gaps=set(range(16384))-{address(x*4,y) for x in range(80) for y in range(200)}
        for state in states:
            for i in gaps:
                self.assertEqual(state["frame"][i],((i+0xC000)>>8)^(i&255))

    def observation(self):
        """Synthetic HOST records to challenge the checker, not Z80 execution."""
        ram=bytearray(512*1024)
        s=self.sym
        ram[s["reg_trace_tag"]]=0xC5
        ram[s["reg_done"]]=16
        for i,state in enumerate(self.states):
            record=bytearray(b"\xBD"*1024)
            record[:756]=bytes(756)
            record[:6]=bytes((i,0,state["bank"],NATIVES[i+3],len(state["order"]),state["focus"]))
            record[8:12]=bytes(state["publication"])
            for slot in state["callbacks"]: record[12+slot]=1
            def field(name,values):
                at=32+s[name]-0x2200
                record[at:at+len(values)]=bytes(values)
            field("core_win_gen",state["generations"])
            for suffix in ("","_gen"):
                want=[0]*8
                for slot,w in state["windows"].items():
                    want[slot]=1 if suffix else (1 if w["native"]==0xC0 else 2)
                field("core_win_owner"+suffix,want)
            counts=[sum(w["native"]==n for w in state["windows"].values()) for n in (0xC0,0xC4)]
            field("core_app_window_count",counts+[0]*6)
            field("core_app_primary_win",[0,1])
            field("core_owner_active",[1,1]+[0]*6)
            field("core_page_free",[24-i])
            for name,values in (("core_page_state",[1]*(i+4)),("core_page_gen",[1]*(i+4)),
                ("core_page_owner",[1,2]+[1]*(i+2)),("core_page_owner_gen",[1]*(i+4)),
                ("core_page_purpose",[1,1]+[6]*(i+2))):
                field(name,values+[0]*(32-len(values)))
            for slot,w in state["windows"].items():
                at=544+slot*25
                record[at:at+5]=bytes((w["native"],*w["rect"]))
                if slot>=2:
                    record[at+5:at+25]=struct.pack("<HHHHB",0x4800+w["index"]*16,
                        0x4B00,0x4B00,0,w["flags"])+b"CHROME  TST"
            record[744:744+len(state["order"])]=bytes(state["order"])
            record[752:756]=bytes((0,0,80,200))
            at=physical(0xC5)+i*1024
            ram[at:at+1024]=record
            at=physical(NATIVES[i+3])
            ram[at:at+16384]=state["frame"]
        ram[0xC000:0x10000]=self.states[-1]["frame"]
        for name in ("cpc_reg_guard","cpc_reg_end","cpc_wm_guard","cpc_wm_end","cpc_draw_state_guard","cpc_draw_state_end"):
            ram[s[name]:s[name]+16]=b"\xD7"*16
        code=(self.work / "SUPPORT.RAW").read_bytes()
        ram[s["cpc_support_base"]:s["cpc_support_base"]+len(code)]=code
        font=(self.work / "DEFAULT.FNT").read_bytes()
        ram[0x7C000:0x80000]=font+b"\xA9"*(16384-len(font))
        ram[s["pointer_visible"]]=1
        ram[0x10202]=2
        ram[s["reg_long_title"]:s["reg_long_title"]+25]=b"01234567890123456789012\0\xD7"
        return ram

    def test_checker_rejects_descriptor_owner_pixel_and_guard_corruption(self):
        ram=self.observation()
        verify_registration(ram,self.sym,self.work)
        first=physical(0xC5)+1024
        s=self.sym
        for label,at in (("owner",first+32+s["core_win_owner"]-0x2200+2),
                         ("kind opt-in",first+544+2*25+13),
                         ("descriptor",first+544+2*25+5),
                         ("publication",first+8),
                         ("generation",first+32+s["core_win_gen"]-0x2200+2),
                         ("argument",first+544+2*25+14),
                         ("frame",physical(NATIVES[4])+address(10*4,60)),
                         ("capture tail",first+756),
                         ("title scratch guard",s["cpc_reg_guard"]+15),
                         ("title length",s["reg_long_title"]+23),
                         ("font page",0x7C020),
                         ("root lock",s["core_pointer_paintlock"])):
            with self.subTest(label=label):
                bad=bytearray(ram)
                bad[at]^=1
                with self.assertRaises(AssertionError): verify_registration(bad,s,self.work)


if __name__=="__main__":
    unittest.main()
