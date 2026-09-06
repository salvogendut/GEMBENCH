from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/"tools"))
from build_cpc_production import assemble
from cpc_production_fsctx import expected, TRACE_PAGES, verify_fsctx
from cpc_production_lifetime import physical


class DirectoryPolicyTests(unittest.TestCase):
    def test_bounded_provider_and_default_error_semantics(self):
        core=(ROOT/"kernel/core/fsctx_policy.inc").read_text()
        self.assertIn("#define FSCTX_DIRECTORY_STATUS() OK",core)
        self.assertEqual(core.count("status(FSCTX_DIRECTORY_STATUS())"),2)
        provider=(ROOT/"kernel/kc/cpc_fsdir.inc").read_text()
        self.assertIn("ordinal>=CPC_DIR_LIMIT",provider)
        self.assertIn("FSCTX_CURSOR[2]!=0xD1u",provider)
        self.assertIn("exchange(0x16u,len)",provider)
        self.assertNotIn("XFER",provider)
        self.assertIn("copy_bytes(CPC_DIR_ENTRY+12u,CPC_RESPONSE+4u,4u)",provider)

    @unittest.skipUnless(shutil.which(os.environ.get("CC","cc")),"C compiler required")
    def test_shared_policy_distinguishes_eof_and_failed_partial_batch(self):
        with tempfile.TemporaryDirectory(prefix="fsdir-errors-") as temp:
            for base in (0x2000,0xD800):
                binary=Path(temp)/f"policy-{base}"
                subprocess.run([os.environ.get("CC","cc"),"-std=c99","-Wall","-Wextra","-Werror",
                    "-DTEST_FS_DIRECTORY_STATUS",f"-DFIXTURE_BASE={base}",
                    str(ROOT/"tests/test_fsctx_core.c"),"-o",str(binary)],check=True)
                subprocess.run([str(binary)],check=True)


@unittest.skipUnless(all(shutil.which(os.environ.get(k,k.lower())) for k in ("RASM","SDCC")),"RASM/SDCC required")
class DirectoryAssemblyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory(prefix="cpc-fsdir-unit-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.work=Path(cls.temp.name)
        cls.sym=assemble(cls.work,"fsctx-directory")

    def test_repeatable_link_and_reservations(self):
        self.assertIn("cpc_fs_directory_enabled",self.sym)
        self.assertLessEqual(self.sym["cpc_kernel_used_end"],0xC000)
        self.assertLessEqual(0x4400+len((self.work/"FSCTX.BIN").read_bytes()),0x6000)
        again=self.work/"again";assemble(again,"fsctx-directory")
        for name in ("CORE.RAW","FSCTX.BIN","SUPPORT.RAW","HARDWARE.RAW"):
            self.assertEqual((self.work/name).read_bytes(),(again/name).read_bytes())

    def test_oracle_detects_metadata_cursor_and_transfer_corruption(self):
        # Observer self-test; never supplied to an emulator.
        s=self.sym;ram=bytearray(512*1024);rows,commands=expected(True)
        ram[s["fp_done"]]=len(rows)
        for page in TRACE_PAGES: ram[physical(page):physical(page)+16384]=b"\xD7"*16384
        for i,row in enumerate(rows):
            at=physical(TRACE_PAGES[i//12])+i%12*1280;ram[at:at+len(row)]=row
        ram[s["fp_commands"]:s["fp_commands"]+2]=commands.to_bytes(2,"little")
        ram[0x10204]=7;ram[s["core_page_free"]]=26
        ram[s["core_page_state"]:s["core_page_state"]+2]=bytes((1,1))
        for name,at in (("FSCTX.BIN",0x7C400),("DEFAULT.FNT",0x7C000),("SUPPORT.RAW",0x400)):
            data=(self.work/name).read_bytes();ram[at:at+len(data)]=data
        ram[0xC000:0x10000]=bytes((a>>8)^(a&255) for a in range(0xC000,0x10000))
        verify_fsctx(ram,s,self.work)
        base=physical(TRACE_PAGES[0])+7*1280
        for offset in (1,18,20,32+76,32+78,32+92,672,1185,1192):
            bad=bytearray(ram);bad[base+offset]^=1
            with self.subTest(offset=offset),self.assertRaises(AssertionError): verify_fsctx(bad,s,self.work)


if __name__=="__main__": unittest.main()
