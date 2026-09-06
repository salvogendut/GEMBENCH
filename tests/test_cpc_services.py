from __future__ import annotations

import os
from pathlib import Path
import shutil
import struct
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
from build_cpc_production import assemble
from cpc_graphics_fixture import address
from cpc_production_services import expected, verify_services
from cpc_production_lifetime import NATIVES, physical

TOOLCHAIN=all(shutil.which(os.environ.get(k,k.lower())) for k in ("RASM","SDCC"))


class ServiceSourceTests(unittest.TestCase):
    def test_dispatch_and_lookup_policy_have_one_implementation(self):
        msx=(ROOT/"kernel/gbkern.asm").read_text()+(ROOT/"kernel/msx_page_pool.asm").read_text()
        msx+=(ROOT/"kernel/core/root_loop.asm").read_text().replace('include "root_dispatch_phase.asm"',
                                                                  'include "core/root_dispatch_phase.asm"')
        cpc=(ROOT/"kernel/cpc_services.asm").read_text()
        for name in ("deferred_api.asm","deferred_dispatch.asm","service_lookup.asm","root_dispatch_phase.asm"):
            for source in (msx,cpc):
                self.assertEqual(source.count(f'include "core/{name}"'),1)
            code="\n".join(line.split(";",1)[0] for line in (ROOT/"kernel/core"/name).read_text().splitlines())
            self.assertNotRegex(code,r"\b(?:PLATFORM_\w+|CPC_\w+|MSX_\w+)\b")
            self.assertNotRegex(code.lower(),r"\b(?:out|in|di|ei|halt|sp)\b")
        phase=(ROOT/"kernel/core/root_dispatch_phase.asm").read_text()
        self.assertEqual([line.split() for line in phase.splitlines() if line.lstrip().startswith("call")],
                         [["call","ROOT_DISPATCH_ONE"],["call","ROOT_MAP_FOCUS"],["call","ROOT_FULL_CLIP"]])

    def test_timer_is_app_linked_unmodified_sdas_and_worker_uses_public_policy(self):
        builder=(ROOT/"tools/cpc_production_services.py").read_text()
        for name in ("timer_collect.inc","timer_collect_contract.inc"):
            self.assertIn(f'.include "core/{name}"',builder)
        probe=(ROOT/"debug/cpc_production/services_probe.asm").read_text()
        worker=probe.split("cpc_service_worker_hook\n",1)[1].split("svc_yield\n",1)[0]
        self.assertEqual(worker.count("call universal_parameters"),2)
        self.assertNotIn("SCHED_CURRENT",worker)
        self.assertNotIn("wm_repaint",worker)


@unittest.skipUnless(TOOLCHAIN,"RASM and SDCC required for native service composition")
class ServiceAssemblyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory(prefix="geobench-service-unit-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.work=Path(cls.temp.name)
        cls.sym=assemble(cls.work,"services")
        cls.states=expected((cls.work/"DEFAULT.FNT").read_bytes())

    def test_link_budgets_and_determinism(self):
        s=self.sym
        self.assertEqual(len((self.work/"TIMER.BIN").read_bytes()),116)
        self.assertEqual(s["cpc_timer_collect"],0x4C00)
        self.assertLess(s["cpc_services_end"]-s["cpc_services_begin"],768)
        self.assertLessEqual(s["cpc_kernel_used_end"],0xC000)
        self.assertLessEqual(s["svc_cycles"]+1,s["cpc_reg_end"])
        self.assertLessEqual(s["svc_log"]+96,s["cpc_adapter_state_end"])
        again=self.work/"again"
        assemble(again,"services")
        for name in ("TIMER.BIN","CORE.RAW","SCHED.RAW","SUPPORT.RAW","BOOT.RAW"):
            self.assertEqual((again/name).read_bytes(),(self.work/name).read_bytes())

    def test_model_covers_fifo_and_effective_damage(self):
        states=self.states
        self.assertEqual([len(s["queue"]) for s in states[:8]],[0,8,8,7,4,3,0,0])
        self.assertEqual([len(s["log"])//12 for s in states[:8]],[0,0,1,2,2,3,3,4])
        self.assertEqual(states[2]["queue"][-1][4:],bytes((2,0xEE,0xDD,0xCC)))
        self.assertEqual(states[-1]["turns"],15)
        self.assertEqual(states[-1]["publishes"],6)
        for a,b in ((9,10),(12,13),(13,14)):
            self.assertEqual(states[a]["frame"],states[b]["frame"])
            self.assertEqual(states[a]["passes"],states[b]["passes"])
            self.assertFalse(states[b]["callbacks"])
        allowed={address(x*4,y) for x in range(18,20) for y in range(36,39)}
        changed={j for j,(a,b) in enumerate(zip(states[8]["frame"],states[9]["frame"])) if a!=b}
        self.assertEqual(changed,allowed)
        self.assertEqual(states[7]["order"],[0,2,1])

    def observation(self):
        """Host-only synthetic observations to challenge the checker, not execution."""
        ram=bytearray(512*1024)
        s=self.sym
        ram[s["svc_trace_tag"]]=0xC5
        ram[s["svc_done"]]=16
        for i,state in enumerate(self.states):
            record=bytearray(769)+bytearray(b"\xBD"*255)
            record[:11]=bytes((i,0,0,state["publishes"],len(state["log"])//12,state["turns"],
                              0 if i<2 else 0xC4 if i==7 else 0xC0,0xC5,NATIVES[i+3],0,5 if i>=8 else 0))
            record[12:16]=bytes((len(state["order"]),state["focus"],2 if i>=10 else 0,1 if i>=10 else 0))
            for slot in state["callbacks"]: record[16+slot]=1
            record[19:21]=bytes((state["recursions"],state["color"]))
            struct.pack_into("<HH",record,22,state["passes"],state["passes"]-1)
            record[26]=int(i>=11)
            def field(name,values):
                at=32+s[name]-0x2200
                record[at:at+len(values)]=bytes(values)
            field("core_defer_count",[len(state["queue"])])
            field("core_defer_queue",b"".join(state["queue"]))
            field("core_defer_current",state["current"])
            for name,v in (("core_defer_handler_lo",0x20),("core_defer_handler_hi",0x4B)):
                field(name,([v,v] if i<15 else [0,0])+[0]*6)
            for name,values in (("core_app_code_native",[0xC0,0xC4]),("core_owner_active",[1,1]),
                ("core_owner_gen",[1,1]),("core_app_window_count",[2 if i<15 else 1,1]),
                ("core_app_service",[0x40,0xA0]),("core_app_accessory",[0,7]),
                ("core_win_owner",[1,2,1 if i<15 else 0]),("core_win_owner_gen",[1,1,1 if i<15 else 0]),
                ("core_win_gen",[1,2 if i==12 else 1,1])):
                field(name,values+[0]*(8-len(values)))
            field("core_param_timer_rect",state["timer_rect"])
            field("core_param_timer_gen",[int(i>=8)])
            field("core_page_free",[24-i])
            for name,values in (("core_page_state",[1]*(i+4)),("core_page_gen",[1]*(i+4)),
                ("core_page_owner",[1,2]+[1]*(i+2)),("core_page_owner_gen",[1]*(i+4)),
                ("core_page_purpose",[1,1]+[6]*(i+2))):
                field(name,values+[0]*(32-len(values)))
            for slot,rect in state["rects"].items():
                at=544+slot*25
                record[at:at+5]=bytes((0xC4 if slot==1 else 0xC0,*rect))
                if slot==2:
                    record[at+5:at+7]=b"\0\x48"
                    record[at+13]=19
            record[619:619+len(state["order"])]=bytes(state["order"])
            record[627:631]=bytes(state["timer_rect"] if i==10 else (0,0,80,200))
            record[631:727]=state["log"].ljust(96,b"\0")
            record[727:759]=state["api"]
            record[759:769]=struct.pack("<5H",0x102,0x102,0,0,0x101)
            at=physical(0xC5)+i*1024
            ram[at:at+1024]=record
            at=physical(NATIVES[i+3])
            ram[at:at+16384]=state["frame"]
        ram[0xC000:0x10000]=self.states[-1]["frame"]
        for name in ("cpc_reg_guard","cpc_reg_end","cpc_wm_guard","cpc_wm_end","cpc_draw_state_guard","cpc_draw_state_end"):
            ram[s[name]:s[name]+16]=b"\xD7"*16
        code=(self.work/"SUPPORT.RAW").read_bytes()
        ram[s["cpc_support_base"]:s["cpc_support_base"]+len(code)]=code
        ram[0x4C00:0x4C74]=(self.work/"TIMER.BIN").read_bytes()
        font=(self.work/"DEFAULT.FNT").read_bytes()
        ram[0x7C000:0x80000]=font+b"\xA9"*(16384-len(font))
        ram[s["pointer_visible"]]=1
        ram[0x10202]=2
        return ram

    def test_checker_rejects_corruption(self):
        ram=self.observation()
        verify_services(ram,self.sym,self.work)
        trace=physical(0xC5)
        s=self.sym
        for label,at in (("delivery bank",trace+2*1024+631+8),
                         ("root context",trace+2*1024+631+10),
                         ("FIFO",trace+2*1024+32+s["core_defer_queue"]-0x2200),
                         ("busy",trace+2*1024+32+s["core_defer_busy"]-0x2200),
                         ("worker publish",trace+8*1024+3),
                         ("hidden paint",trace+10*1024+18),
                         ("hidden cursor",trace+10*1024+22),
                         ("hidden worker",trace+11*1024+26),
                         ("admission",trace+727),
                         ("lookup",trace+759),
                         ("generation",trace+12*1024+32+s["core_win_gen"]-0x2200+1),
                         ("timer code",0x4C00),
                         ("pixel",physical(NATIVES[12])+address(22*4,36)),
                         ("state guard",s["cpc_reg_end"]),
                         ("font",0x7C001)):
            with self.subTest(label=label):
                bad=bytearray(ram)
                bad[at]^=1
                with self.assertRaises(AssertionError): verify_services(bad,s,self.work)


if __name__=="__main__": unittest.main()
