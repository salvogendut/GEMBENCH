"""Portable data-page authority and actual shared-policy instruction tests."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from test_owner_page_core import STATE_FIELDS
ROOT=Path(__file__).resolve().parents[1]
CORE=Path(os.environ.get('MSX_1983_SOURCE',ROOT.parent/'1983'))/'src'
sys.path.insert(0,str(ROOT/'tools'))
from check_universal_app import check_source, check_generated_asm
from embed_app_icon import CAPABILITIES_V4, _read_v4_manifest_spec, make_v4_preamble, refresh_v4_crc

class DataPageTests(unittest.TestCase):
    def test_contract(self):
        abi=json.loads((ROOT/'abi/geobench-v2.json').read_text())
        self.assertEqual(abi['version'],[2,1])
        self.assertEqual(CAPABILITIES_V4['portable-data-pages'],0x02000000)
        spec=abi['portable_data_pages']
        self.assertEqual((spec['header_size'],spec['page_size'],spec['transfer_max']),(16,16384,512))
        self.assertEqual(abi['caller_parameters']['operations']['data-pages'],10)
        errors=[]
        for p in ('include/gembench/gbdatapage.h','lib/gembench/gbdatapage.c'):
            check_source(ROOT/p,errors)
        self.assertEqual(errors,[])
        for target in ('msx','cpc'):
            self.assertIn('include "core/data_pages.asm"',(ROOT/f'kernel/{target}_data_pages.asm').read_text())

    @unittest.skipUnless(shutil.which('sdcc'),'SDCC required')
    def test_sdk_cost_and_audit(self):
        with tempfile.TemporaryDirectory(prefix='data-pages-sdk-') as tmp:
            obj=Path(tmp)/'pages.rel'
            subprocess.run(['sdcc','-mz80','--std-c99','--opt-code-size','--fomit-frame-pointer',
                '-DGB_UNIVERSAL','-I',str(ROOT/'lib/gb'),'-I',str(ROOT/'include/gembench'),
                '-c',str(ROOT/'lib/gembench/gbdatapage.c'),'-o',str(obj)],check=True)
            areas={n:int(s,16) for n,s in re.findall(r'^A (\S+) size ([0-9A-Fa-f]+)',obj.read_text(),re.M)}
            self.assertEqual(areas['_DATA'],16);self.assertLessEqual(areas['_CODE'],512)
            errors=[];check_generated_asm(obj.with_suffix('.asm'),errors);self.assertEqual(errors,[])
            print('data-page SDK:',areas)

    @unittest.skipUnless(shutil.which('sdcc'),'SDCC required')
    def test_builder_requires_capability_and_boolean_flag(self):
        with tempfile.TemporaryDirectory(prefix='data-pages-flags-') as tmp:
            for flag, manifest, message in (
                ('1','apps/fsprobe/manifest.json','UNIVERSAL_DATA_PAGES requires portable-data-pages'),
                ('2','apps/pageprobe/manifest.json','feature flags must be 0 or 1')):
                result=subprocess.run(['bash','tools/build_uapp.sh','apps/pageprobe',str(Path(tmp)/'probe.APP')],
                    cwd=ROOT,env={**os.environ,'UNIVERSAL_DATA_PAGES':flag,'APP_MANIFEST':manifest,
                                 'APP_ICON':'apps/abiprobe/icon.asm'},
                    capture_output=True,text=True)
                self.assertNotEqual(result.returncode,0)
                self.assertIn(message,result.stdout+result.stderr)

    @unittest.skipUnless(shutil.which('rasm') and shutil.which('cc') and (CORE/'z80.c').exists(),
                         'RASM, cc and read-only 1983 CPU sources required')
    def test_actual_capability_gate_and_module_boot_validation(self):
        with tempfile.TemporaryDirectory(prefix='data-pages-gates-') as tmp:
            tmp=Path(tmp)
            for enabled in (False,True):
                subprocess.run(['rasm',str(ROOT/'kernel/msx_gbap4.asm'),
                                *(['-DPORTABLE_DATA_PAGES=1'] if enabled else [])],
                               cwd=tmp,check=True,capture_output=True)
                (tmp/'GBAPV4.RAW').rename(tmp/('on.bin' if enabled else 'off.bin'))
            source=f'''include "{ROOT}/lib/msx/glue.inc"
fs_req_name equ #14EC
fs_load_dst equ #14F7
fs_load_max equ #14F9
fs_ent_size equ #14E8
org #9000
include "{ROOT}/kernel/msx_data_pages_boot.asm"
copy11
ld bc,11
ldir
ret
fs_load_sys
ld a,(#2000)
or a
ret z
scf
ret
save "boot.bin",#9000,$-#9000
'''
            (tmp/'boot.asm').write_text(source)
            subprocess.run(['rasm',str(tmp/'boot.asm'),'-s','-sq','-o','boot'],cwd=tmp,
                           check=True,capture_output=True)
            symbols={n:int(v,16) for n,v in re.findall(r'^(\w+) #([0-9A-Fa-f]+)',(tmp/'boot.sym').read_text(),re.M)}
            (tmp/'gate_fixture.h').write_text(f'#define BOOT_ENTRY {symbols["DATA_PAGES_LOAD"]}\n'
                                            f'#define DATA_SIZE {symbols["MSX_DATA_PAGE_SIZE"]}\n')
            spec=_read_v4_manifest_spec(ROOT/'apps/pageprobe/manifest.json')
            exe=tmp/'test'
            subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-I',str(CORE),'-I',str(tmp),
                str(ROOT/'tests/data_page_gates_z80.c'),str(CORE/'z80.c'),'-o',str(exe)],check=True)
            for length,icon16 in ((365,None),(885,bytes(512))):
                app=bytearray(make_v4_preamble(bytes(256),spec,length,length,icon16=icon16)+b'\xC9')
                (tmp/'probe.APP').write_bytes(refresh_v4_crc(app))
                subprocess.run([str(exe),str(tmp/'off.bin'),str(tmp/'on.bin'),str(tmp/'boot.bin'),str(tmp/'probe.APP')],check=True)

    @unittest.skipUnless(shutil.which('rasm') and shutil.which('cc') and (CORE/'z80.c').exists(),
                         'RASM, cc and read-only 1983 CPU sources required')
    def test_actual_policy_at_two_fixed_layouts(self):
        for base in (0x2000,0xD800):
            cells={};cursor=base
            for name,size in STATE_FIELDS:
                if (cursor&255)+size>256:cursor=(cursor+255)&~255
                cells[name]=cursor;cursor+=size
            cells.update(CORE_PAGE_CAPACITY=32,CORE_OWNER_CAPACITY=8,CORE_WINDOW_MAX=8,
                GB_OWNER_MAX=8,GB_PAGE_RESOURCE=2,GB_PAGE_ERR_STALE=2,GB_PAGE_ERR_OWNER=3,GB_PAGE_ERR_FREE=4,
                DATA_CURRENT=base+0x400,DATA_MAPPED=base+0x401,OWNER=base+0x402,LOCK=base+0x404,
                DATA_REQUEST=base+0x410,DATA_TRANSFER=base+0x500)
            code=[*[f'{n} equ {v}' for n,v in cells.items()],
                'DATA_OWNER_CURRENT equ current_owner','OWNER_PAGE_CURRENT_OWNER equ current_owner',
                'DATA_MAP equ map_page','macro OWNER_PAGE_PUBLISH_FREE','mend',
                f'include "{ROOT}/kernel/core/owner_page_contract.inc"','org #8000',
                'entry','push ix','ld a,i','push af','di','ld a,(LOCK)','push af',
                'ld a,1','ld (LOCK),a','call data_page_dispatch','ld d,a','pop af','ld (LOCK),a',
                'pop af','ld a,d','pop ix','ret po','ei','ret',
                'current_owner','ld de,(OWNER)','ret',
                'map_page','ld (DATA_MAPPED),a','out (#FE),a','ret']
            for name in ('page_count.asm','owner_identity.asm','page_pool.asm','data_pages.asm'):
                code.append(f'include "{ROOT}/kernel/core/{name}"')
            code+=['save "pages.bin",#8000,$-#8000']
            with tempfile.TemporaryDirectory(prefix='data-pages-z80-') as tmp:
                tmp=Path(tmp);src=tmp/'test.asm';src.write_text('\n'.join(code)+'\n')
                subprocess.run(['rasm',str(src),'-s','-sq','-o','pages'],cwd=tmp,check=True,capture_output=True)
                symbols={n:int(v,16) for n,v in re.findall(r'^(\w+) #([0-9A-Fa-f]+)',(tmp/'pages.sym').read_text(),re.M)}
                (tmp/'fixture.h').write_text('\n'.join(f'#define {n} {v}' for n,v in {**cells,'ENTRY':symbols['ENTRY']}.items())+'\n')
                exe=tmp/'test'
                subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-I',str(CORE),'-I',str(tmp),
                    str(ROOT/'tests/data_pages_z80.c'),str(CORE/'z80.c'),'-o',str(exe)],check=True)
                subprocess.run([str(exe),str(tmp/'pages.bin')],check=True)

if __name__=='__main__':unittest.main()
