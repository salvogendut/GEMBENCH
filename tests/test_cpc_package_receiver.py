"""Full production-budget CPC composition checks, no desktop runtime claim."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zlib

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from build_cpc_runtime import bitmap_assets, build
from build_cpc_production import symbols, memory_regions
import genfont

def assemble(stage,package,handoff=False):
    stage.mkdir(parents=True)
    genfont.main(['genfont',str(stage/'DEFAULT.FNT')]);bitmap_assets(stage)
    (stage/'fsctx_size.inc').write_text('CPC_FS_MODULE_BYTES equ 1\n')
    (stage/'TIMER.BIN').write_bytes(bytes(116))
    (stage/'package_crc.inc').write_text('db 0,0,0,0\n')
    cmd=['rasm',str(ROOT/'kernel/cpc_runtime.asm'),'-s','-sq','-o','runtime',f'-I{stage}',
         '-DCPC_NATIVE_DESKTOP=1','-DCPC_NATIVE_FILEMGR=1','-DCPC_NATIVE_SETTINGS=1']
    if package:cmd+=['-DPORTABLE_PACKAGE_STREAM=1']
    if handoff:cmd+=['-DPORTABLE_FS_HANDOFF=1']
    subprocess.run(cmd,cwd=stage,check=True,capture_output=True)
    if package:
        module=(stage/'GBPKLOAD.MOD').read_bytes()
        (stage/'package_crc.inc').write_text('db '+','.join(str(b) for b in zlib.crc32(module).to_bytes(4,'little'))+'\n')
        subprocess.run(cmd,cwd=stage,check=True,capture_output=True)
        if (stage/'GBPKLOAD.MOD').read_bytes()!=module:raise AssertionError('CRC/body circularity')
    sym=symbols(stage/'runtime.sym');memory_regions(sym)
    (stage/'boot_symbols.inc').write_text('\n'.join(f'{name} equ {sym[name]}' for name in (
        'foundation_bank_set','storage_gate','storage_ga_set','storage_rom_set','storage_command','storage_send'))+'\n')
    for source,out in (('cpc_m4_loader.asm','loader'),('cpc_m4_boot.asm','boot')):
        subprocess.run(['rasm',str(ROOT/'kernel'/source),'-s','-sq','-o',out,f'-I{stage}',
                        '-DCPC_DRAWING=1',f'-DCPC_LOAD_BYTES={(stage/"CORE.RAW").stat().st_size}'],
                       cwd=stage,check=True,capture_output=True)
    return sym,cmd

@unittest.skipUnless(shutil.which('rasm'),'RASM required')
class CPCPackageReceiverTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory(prefix='cpc-package-receiver-')
        cls.addClassCleanup(cls.temp.cleanup)
        cls.work=Path(cls.temp.name)
        cls.baseline,_=assemble(cls.work/'default',False)
        cls.sym,cls.command=assemble(cls.work/'package',True)
        cls.handoff,_=assemble(cls.work/'handoff',True,True)

    def test_full_budget_default_is_not_promoted(self):
        for s in (self.baseline,self.sym,self.handoff):
            for begin,end,limit in (
                ('cpc_support_begin','cpc_support_used_end','cpc_support_end'),
                ('cpc_hardware_begin','cpc_hardware_used_end','cpc_hardware_end'),
                ('cpc_kernel_begin','cpc_kernel_used_end','cpc_kernel_end'),
                ('cpc_scheduler_begin','cpc_scheduler_end','cpc_sched_end')):
                self.assertLessEqual(s[end],s[limit]);self.assertGreater(s[end],s[begin])
        self.assertNotIn('secondary_call',self.baseline)
        self.assertNotIn('package_load',self.baseline)
        self.assertNotIn('param_secondary_call',self.baseline)
        self.assertEqual(self.baseline['cpc_runtime_caps_high'],0x1DF)
        self.assertEqual(self.sym['cpc_runtime_caps_high'],0x5DF)
        for name in ('default','package','handoff'):
            self.assertLessEqual((self.work/name/'BOOT.RAW').stat().st_size,0x9A00-0x8000)

    def test_private_handoff_binds_shared_policy_and_removes_only_unused_launcher(self):
        s=self.handoff
        self.assertEqual(s['app_launch_transaction'],s['document_launch'])
        self.assertEqual(s['app_launch_bind'],s['document_bind'])
        self.assertEqual(s['core_fsctx_cleanup_tail'],s['document_owner_cleanup'])
        self.assertEqual(s['doc_pending'],s['cpc_fs_pending'])
        self.assertEqual(s['param_fs_identity'],1)
        raw=(self.work/'handoff/CORE.RAW').read_bytes()
        self.assertEqual(raw[s['cpc_sysinfo_template']-0x8000+31],3)
        self.assertIn('cpc_runtime_config',s)  # real Settings reload retained
        self.assertIn('cpc_desktop_collect',s)
        self.assertNotIn('cpc_runtime_fsprobe',s)
        self.assertIn('cpc_runtime_fsprobe',self.sym)
        self.assertNotIn('document_launch',self.sym)
        self.assertNotIn('cpc_text_mode',self.sym)

    @unittest.skipUnless(shutil.which('cc') and (ROOT.parent/'1983/src/z80.c').exists(),'C compiler and read-only CPU source required')
    def test_executed_cpc_text_and_pointer_routing(self):
        work=self.work/'handoff';s=self.handoff;cpu=ROOT.parent/'1983/src'
        (work/'text_fixture.h').write_text('\n'.join(f'#define {k.upper()} {v}' for k,v in s.items())+'\n')
        exe=work/'input-test'
        subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-O2',
            '-I',str(cpu),'-I',str(work),str(ROOT/'tests/cpc_text_input_z80.c'),
            str(cpu/'z80.c'),'-o',str(exe)],check=True)
        subprocess.run([str(exe),str(work)],check=True)

    def test_checked_fixed_module_and_real_shared_hooks(self):
        s=self.sym;work=self.work/'package'
        module=(work/'GBPKLOAD.MOD').read_bytes();kernel=(work/'CORE.RAW').read_bytes()
        self.assertEqual(len(module),768);self.assertEqual(module[3:8],b'CPK4\1')
        self.assertEqual(int.from_bytes(module[1:3],'little'),s['package_load'])
        self.assertLessEqual(s['cpc_package_module_used_end'],0x400)
        at=s['cpc_package_crc']-0x8000
        self.assertEqual(kernel[at:at+4],zlib.crc32(module).to_bytes(4,'little'))
        for name in ('cpc_package_guard','cpc_package_read'):
            self.assertTrue(0x3800<=s[name]<0x3E00)
        for name in ('secondary_call','secondary_seal_bind','cpc_secondary_parameters'):
            self.assertTrue(0x400<=s[name]<0x1000)
        self.assertEqual(s['param_secondary_call'],s['cpc_secondary_parameters'])
        self.assertEqual(s['page_seal_release'],s['secondary_seal_page_release'])
        self.assertEqual(s['owner_seal_release'],s['secondary_seal_clear'])
        self.assertEqual(s['sec_transfer'],s['cpc_fs_xfer'])
        self.assertLessEqual(s['cpc_edit_state_end'],s['cpc_stream_state'])
        self.assertLessEqual(s['sec_table']+64,0x2000)
        self.assertEqual(s['app_load_and_admit'],s['cpc_package_launch'])
        # Root context is explicitly set before the stream's boot guard runs.
        start=s['cpc_runtime_start']-0x8000
        before=kernel[start:kernel.index(bytes([0xCD])+s['cpc_package_boot'].to_bytes(2,'little'),start)]
        self.assertIn(b'\xAF\x32'+s['sched_current'].to_bytes(2,'little'),before)

    def test_unqualified_combinations_fail_before_media_writes(self):
        for options in ({'package_stream':True},
                        {'handoff':True},
                        {'package_stream':True,'settings':True,'delivery':True},
                        {'package_stream':True,'settings':True,'data_pages':True}):
            with self.assertRaises(ValueError):build(**options)
        result=subprocess.run(self.command+['-DPORTABLE_DATA_PAGES=1'],cwd=self.work/'package',
                              capture_output=True,text=True)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('combined receiver is not qualified',result.stdout+result.stderr)

if __name__=='__main__':unittest.main()
