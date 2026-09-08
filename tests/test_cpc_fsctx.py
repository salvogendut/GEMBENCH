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
from cpc_production_fsctx import expected, inputs, files, TRACE_PAGES, verify_fsctx
from cpc_production_lifetime import physical

TOOLS=all(shutil.which(os.environ.get(k,k.lower())) for k in ("RASM","SDCC"))


class FsctxSourceTests(unittest.TestCase):
    def test_same_context_policy_and_caller_gate(self):
        for name in ("gbfsctx_mod.c","gbfsctx_cpc.c"):
            text=(ROOT/"kernel/kc"/name).read_text()
            self.assertEqual(text.count('#include "../core/fsctx_policy.inc"'),1)
            self.assertEqual(text.count('#include "../core/fsctx_contract.h"'),1)
        for name in ("msx_page_pool.asm","cpc_fsctx.asm"):
            self.assertEqual((ROOT/"kernel"/name).read_text().count('include "core/fsctx_gate.asm"'),1)
        gate=(ROOT/"kernel/core/fsctx_gate.asm").read_text()
        self.assertLess(gate.index("FSCTX_CHECK_WORKER"),gate.index("call  owner_current"))
        self.assertLess(gate.index("call  owner_current"),gate.index("call  FSCTX_MODULE_RUN"))
        code="\n".join(l.split(';',1)[0] for l in gate.splitlines())
        self.assertNotRegex(code,r"\b(?:MSX_\w+|CPC_\w+|PLATFORM_\w+)\b")
        self.assertNotRegex(code.lower(),r"\b(?:in|out|di|ei|halt)\b")

    def test_private_read_only_boundary(self):
        cpc=(ROOT/"kernel/cpc_fsctx.asm").read_text()
        for op in (5,6,9,10,14): self.assertRegex(cpc,rf"cp {op}\n\s+jr z,cpc_fs_unsupported")
        self.assertIn("call storage_send",cpc)
        self.assertIn("call storage_gate",cpc)
        self.assertNotIn('incbin "FSCTX',cpc)
        self.assertIn("call cpc_fs_load_module",(ROOT/"debug/cpc_production/fsctx_probe.asm").read_text())
        backend=(ROOT/"kernel/kc/gbfsctx_cpc.c").read_text()
        self.assertIn("exchange(0x13u,0u)",backend)  # verify CD via returned path
        self.assertIn("copy_bytes(CPC_FILE,CPC_PATH,i)",backend)
        self.assertIn('#include "cpc_fsread.inc"',backend)
        reader=(ROOT/"kernel/kc/cpc_fsread.inc").read_text()
        self.assertIn("amount>128u",reader)
        self.assertIn("offset>0xFFFFFFFFUL-(unsigned long)REQ_LENGTH",reader)


@unittest.skipUnless(TOOLS,"RASM and SDCC required for CPC module composition")
class FsctxAssemblyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory(prefix="geobench-fsctx-unit-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.work=Path(cls.temp.name)
        cls.sym=assemble(cls.work,"fsctx")

    def test_reproducibility_and_actual_memory_budgets(self):
        s=self.sym
        self.assertLessEqual(s["cpc_kernel_used_end"],0xC000)
        self.assertLessEqual(0x4400+len((self.work/"FSCTX.BIN").read_bytes()),0x6000)
        self.assertEqual(s["cpc_fs_module_limit"],s["cpc_app_io_request"])
        self.assertLessEqual(len(inputs()),len(TRACE_PAGES)*12)
        again=self.work/"again"
        assemble(again,"fsctx")
        for name in ("CORE.RAW","HARDWARE.RAW","SUPPORT.RAW","FSCTX.BIN","BOOT.RAW"):
            self.assertEqual((again/name).read_bytes(),(self.work/name).read_bytes())
        header=(ROOT/"kernel/kc/cpc_fsctx.h").read_text()
        for name,symbol in (("REQUEST","cpc_fs_request"),("TRANSFER","cpc_fs_xfer"),
                            ("TABLE","core_fsctx_table"),("PENDING","cpc_fs_pending"),
                            ("CURSOR","cpc_fs_cursor"),("DIAG","cpc_fs_diag")):
            address=int(re.search(rf"#define FSCTX_{name}_ADDRESS 0x([0-9A-F]+)u",header)[1],16)
            self.assertEqual(address,s[symbol])

    def test_bad_module_budget_is_rejected(self):
        with self.assertRaises(subprocess.CalledProcessError):
            assemble(self.work/"small","fsctx",("-DCPC_KERNEL_END=45056",))

    def test_oracle_rejects_identity_data_and_bank_corruption(self):
        # Self-test of the checker only; this is never used as emulator input.
        s=self.sym;ram=bytearray(512*1024);rows,commands=expected()
        ram[s["fp_done"]]=len(rows)
        for page in TRACE_PAGES: ram[physical(page):physical(page)+16384]=b"\xD7"*16384
        for i,row in enumerate(rows):
            at=physical(TRACE_PAGES[i//12])+i%12*1280
            ram[at:at+len(row)]=row
        ram[s["fp_commands"]:s["fp_commands"]+2]=commands.to_bytes(2,'little')
        ram[0x10204]=7
        ram[s["core_page_free"]]=26
        ram[s["core_page_state"]:s["core_page_state"]+2]=bytes((1,1))
        for name,at in (("FSCTX.BIN",0x7C400),("DEFAULT.FNT",0x7C000),("SUPPORT.RAW",0x400)):
            data=(self.work/name).read_bytes();ram[at:at+len(data)]=data
        ram[0xC000:0x10000]=bytes((a>>8)^(a&255) for a in range(0xC000,0x10000))
        verify_fsctx(ram,s,self.work)
        base=physical(TRACE_PAGES[0])+7*1280
        for at in (base+4,base+10,base+40,base+672,base+1185,base+1192,
                   s["fp_commands"],0x10204,0x7C400,0xC7FF,s["core_page_free"]):
            bad=bytearray(ram);bad[at]^=1
            with self.subTest(address=at),self.assertRaises(AssertionError): verify_fsctx(bad,s,self.work)


if __name__=="__main__": unittest.main()
