from pathlib import Path
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from build_cpc_production import assemble
from cpc_production_fsctx import expected,verify_fsctx,TRACE_PAGES
from cpc_production_lifetime import physical
from cpc_fswrite_cases import inputs,space


class WriteProviderTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which(os.environ.get('CC','cc')),'C compiler required')
    def test_real_provider_failure_prefix_and_saturating_parser(self):
        with tempfile.TemporaryDirectory(prefix='cpc-write-c-') as temp:
            exe=Path(temp)/'provider'
            subprocess.run([os.environ.get('CC','cc'),'-std=c99','-Wall','-Wextra','-Werror',
                            str(ROOT/'tests/test_cpc_fswrite.c'),'-o',str(exe)],check=True)
            subprocess.run([str(exe)],check=True)

    def test_oracle_requires_geometry_and_exact_media_bytes(self):
        with self.assertRaises(ValueError): expected(True,True)
        media={};rows,_=expected(True,True,32760,2,media)
        self.assertEqual(len(rows),45)
        self.assertEqual(media['DOCS/SUB/OUT.BIN'],b'')
        self.assertEqual(media['ALT/EMPTY.BIN'],b'')
        self.assertEqual(media['ALT/OUT.BIN'],b'OTHER-129'+b'\xA5'*120+b'OTHER-300'+b'\xA5'*291)
        self.assertEqual(int.from_bytes(rows[19][16:20],'little'),642)
        self.assertEqual(int.from_bytes(rows[29][10:12],'little'),32758)
        with tempfile.TemporaryDirectory(prefix='cpc-write-bad-image-') as temp:
            image=Path(temp)/'invalid.img';image.write_bytes(bytes(1024))
            with self.assertRaises(AssertionError): space(image)


@unittest.skipUnless(all(shutil.which(os.environ.get(k,k.lower())) for k in ('RASM','SDCC')),'RASM/SDCC required')
class WriteAssemblyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory(prefix='cpc-write-unit-');cls.addClassCleanup(cls.temp.cleanup)
        cls.work=Path(cls.temp.name);cls.sym=assemble(cls.work,'fsctx-write')
        (cls.work/'fswrite_geometry.json').write_text(json.dumps(dict(free_kib=32760,cluster_kib=2)))

    def test_repeatable_link_and_budget(self):
        s=self.sym;self.assertIn('cpc_fs_write_enabled',s)
        self.assertLessEqual(s['cpc_hardware_used_end'],0x3E00)
        self.assertLessEqual(s['cpc_kernel_used_end'],0xC000)
        self.assertLessEqual(0x4400+len((self.work/'FSCTX.BIN').read_bytes()),0x6000)
        again=self.work/'again';assemble(again,'fsctx-write')
        for name in ('CORE.RAW','FSCTX.BIN','HARDWARE.RAW','SUPPORT.RAW'):
            self.assertEqual((self.work/name).read_bytes(),(again/name).read_bytes())

    def test_observer_rejects_write_readback_free_space_and_bank_corruption(self):
        # Synthetic observations exercise the checker only, never emulated RAM.
        s=self.sym;ram=bytearray(512*1024);rows,commands=expected(True,True,32760,2)
        ram[s['fp_done']]=len(rows)
        for page in TRACE_PAGES:ram[physical(page):physical(page)+16384]=b'\xD7'*16384
        for i,row in enumerate(rows):
            at=physical(TRACE_PAGES[i//12])+i%12*1280;ram[at:at+len(row)]=row
        ram[s['fp_commands']:s['fp_commands']+2]=commands.to_bytes(2,'little')
        ram[0x10204]=7;ram[s['core_page_free']]=26
        ram[s['core_page_state']:s['core_page_state']+2]=bytes((1,1))
        for name,at in (('FSCTX.BIN',0x7C400),('DEFAULT.FNT',0x7C000),('SUPPORT.RAW',0x400)):
            data=(self.work/name).read_bytes();ram[at:at+len(data)]=data
        ram[0xC000:0x10000]=bytes((a>>8)^(a&255) for a in range(0xC000,0x10000))
        verify_fsctx(ram,s,self.work)
        for i,offset in ((6,10),(7,32+8),(11,672),(19,16),(29,10),(35,1185),(43,1192)):
            at=physical(TRACE_PAGES[i//12])+i%12*1280+offset
            bad=bytearray(ram);bad[at]^=1
            with self.subTest(case=inputs()[i]['name']),self.assertRaises(AssertionError):verify_fsctx(bad,s,self.work)


if __name__=='__main__':unittest.main()
