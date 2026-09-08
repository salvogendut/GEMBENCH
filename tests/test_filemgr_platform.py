from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import zlib

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from build_cpc_filemgr import compile_filemgr, bind_runtime
from build_cpc_runtime import assemble


class FilemgrPlatformTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which(os.environ.get('CC','cc')),'C compiler required')
    def test_actual_application_and_native_binding(self):
        with tempfile.TemporaryDirectory(prefix='filemgr-host-') as tmp:
            exe=Path(tmp)/'filemgr'
            subprocess.run([os.environ.get('CC','cc'),'-std=c99','-Wall','-Wextra','-Werror',
                            '-Wno-unused-function','-I',str(ROOT/'lib/gb'),
                            '-I',str(ROOT/'include/gembench'),
                            f'-DGB_FILEMGR_BINDINGS="{ROOT/"tests/filemgr_binding_provider.h"}"',
                            str(ROOT/'tests/filemgr_platform_test.c'),str(ROOT/'lib/gb/gbscroll.c'),
                            str(ROOT/'lib/gembench/gbr_menu.c'),'-o',str(exe)],check=True)
            subprocess.run([str(exe)],check=True)

    def test_native_staging_requires_separate_explicit_profile(self):
        build=(ROOT/'tools/build_cpc_runtime.py').read_text()
        self.assertIn('def build(desktop=False, filemgr=False, *, delivery=False, settings=False)',build)
        self.assertIn("if filemgr: overrides+=('-DCPC_NATIVE_FILEMGR=1',)",build)
        self.assertIn("'filemgr-contract' if filemgr",build)
        self.assertIn('cp 4',(ROOT/'kernel/cpc_runtime_services.asm').read_text())
        self.assertIn('$APP/platform.h',(ROOT/'tools/build_capp.sh').read_text())


class FilemgrContractTests(unittest.TestCase):
    def setUp(self):
        tmp=tempfile.TemporaryDirectory(prefix='filemgr-contract-');self.addCleanup(tmp.cleanup)
        self.work=Path(tmp.name);self.app=self.work/'app';self.app.mkdir()
        self.raw=b'\xC3\x03\x40'+bytes(range(100))
        (self.app/'FILEMGR.native.bin').write_bytes(self.raw)
        (self.app/'report.json').write_text(json.dumps(dict(
            code_bytes=len(self.raw),code_sha256=hashlib.sha256(self.raw).hexdigest(),staged=False)))
        self.kernel=b'\xA5'*20+bytes(6)+b'\x5A'*30
        (self.work/'CORE.RAW').write_bytes(self.kernel)
        self.sym=dict(cpc_filemgr_profile=1,cpc_kernel_begin=0x8000,cpc_filemgr_contract=0x8014)

    def test_only_six_contract_bytes_change_and_rebind_is_idempotent(self):
        report=bind_runtime(self.work,self.app,self.sym)
        contract=len(self.raw).to_bytes(2,'little')+zlib.crc32(self.raw).to_bytes(4,'little')
        expected=self.kernel[:20]+contract+self.kernel[26:]
        self.assertEqual((self.work/'CORE.RAW').read_bytes(),expected)
        self.assertEqual(report['contract'],contract.hex())
        self.assertTrue(report['private_integration'])
        self.assertFalse(report['staged'])
        self.assertEqual(bind_runtime(self.work,self.app,self.sym),report)
        self.assertEqual((self.work/'CORE.RAW').read_bytes(),expected)

    def test_unchecked_image_cannot_bind(self):
        for raw in (b'',self.raw[:-1],self.raw[:-1]+b'\xFF',self.raw.ljust(0x3801,b'\0')):
            with self.subTest(size=len(raw)):
                (self.app/'FILEMGR.native.bin').write_bytes(raw)
                with self.assertRaisesRegex(AssertionError,'differs from checked link'):
                    bind_runtime(self.work,self.app,self.sym)
                self.assertEqual((self.work/'CORE.RAW').read_bytes(),self.kernel)

    def test_wrong_profile_or_patch_site_cannot_modify_kernel(self):
        for change in (dict(cpc_filemgr_profile=0),dict(cpc_filemgr_contract=0x7FFF),
                       dict(cpc_filemgr_contract=0x8000),dict(cpc_filemgr_contract=0x8033)):
            with self.subTest(change=change):
                with self.assertRaises(AssertionError):
                    bind_runtime(self.work,self.app,{**self.sym,**change})
                self.assertEqual((self.work/'CORE.RAW').read_bytes(),self.kernel)


@unittest.skipUnless(all(shutil.which(os.environ.get(k,k.lower())) for k in ('RASM','SDCC')),
                     'RASM/SDCC required')
class FilemgrLayoutTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory(prefix='filemgr-link-');cls.addClassCleanup(cls.temp.cleanup)
        cls.work=Path(cls.temp.name);cls.runtime=cls.work/'runtime';cls.sym=assemble(cls.runtime)

    def test_complete_native_link_fits_without_legacy_calls(self):
        self.assertNotIn('cpc_filemgr_profile',self.sym)
        with self.assertRaisesRegex(AssertionError,'private runtime profile'):
            bind_runtime(self.runtime,self.work/'app',self.sym)
        report=compile_filemgr(self.work/'app',self.runtime,self.sym)
        self.assertFalse(report['staged'])
        self.assertLessEqual(report['code_bytes'],report['code_budget'])
        self.assertLessEqual(report['data_bytes'],report['data_budget'])
        self.assertEqual(report['snapshot_base'],0x7F00)
        self.assertIn('_gb_wm_managed_kind',report['main_requirements'])
        self.assertIn('_gb_fsctx_dir_batch',report['main_requirements'])
        self.assertIn('_gb_app_quit',report['main_requirements'])
        self.assertFalse(list(self.work.rglob('*.APP')))
        for name in ('mw_rect','poll_mx','gb_msg'):
            bad=dict(self.sym);bad[name]+=1
            with self.assertRaisesRegex(AssertionError,'native SDK binding changed'):
                compile_filemgr(self.work/'bad',self.runtime,bad)
        bad=dict(self.sym);bad['cpc_app_limit']=0x7900
        with self.assertRaisesRegex(AssertionError,'outside owned allocation'):
            compile_filemgr(self.work/'overflow',self.runtime,bad)

    def test_provider_is_required(self):
        result=subprocess.run([os.environ.get('SDCC','sdcc'),'-mz80','-DGB_CPC_RESTART',
                               '-I',str(ROOT/'lib/gb'),'-c',str(ROOT/'apps/filemgr/main.c'),
                               '-o',str(self.work/'unbound.rel')],capture_output=True,text=True)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('requires an explicit native provider',result.stderr)
