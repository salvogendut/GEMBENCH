"""Execute the shared two-page stream loader; no receiver/emulator claim."""
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
from embed_app_icon import _read_v4_manifest_spec, make_v4_preamble, refresh_v4_crc, parse_manifest


class PackageStreamTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('rasm') and shutil.which('cc') and (CORE/'z80.c').exists(),
                         'RASM, cc and read-only 1983 CPU source required')
    def test_shared_stream_transaction_at_two_fixed_layouts(self):
        with tempfile.TemporaryDirectory(prefix='package-stream-') as directory:
            temp=Path(directory)
            spec=json.loads((ROOT/'apps/pageprobe/manifest.json').read_text())
            spec['required_capabilities'].remove('portable-data-pages')
            spec.update(minimum_pages=2,preferred_pages=2,secondary_code={'required':True})
            manifest=temp/'manifest.json';manifest.write_text(json.dumps(spec))
            spec=_read_v4_manifest_spec(manifest)
            # Include payloads greater than an entire primary window as well as
            # small/unaligned ones; the primary and secondary have different data.
            for number,(primary,secondary,icons) in enumerate(((385,9,1),(4097,8201,1),
                                                               (0x3F00,0x3F00,2))):
                sec=bytes((0xC3,0x08,0x40))+b'GBS4\1'+bytes((i*19+5)&255 for i in range(secondary-8))
                pre=make_v4_preamble(bytes(256),spec,primary,primary+secondary,
                                    icon16=bytes(512) if icons==2 else None,secondary=sec)
                app=bytearray(pre+bytes((i*13+7)&255 for i in range(primary-len(pre)))+sec)
                refresh_v4_crc(app);self.assertEqual(len(parse_manifest(app)['segments']),2)
                (temp/f'case{number}.APP').write_bytes(app)
            for base in (0x2000,0xD800):
                cells={};cursor=base
                for name,size in STATE_FIELDS:
                    if (cursor&255)+size>256:cursor=(cursor+255)&~255
                    cells[name]=cursor;cursor+=size
                cells.update(CORE_PAGE_CAPACITY=32,CORE_OWNER_CAPACITY=8,CORE_WINDOW_MAX=8,
                    GB_OWNER_MAX=8,GB_PAGE_RESOURCE=2,GB_PAGE_ERR_STALE=2,GB_PAGE_ERR_OWNER=3,
                    GB_PAGE_ERR_FREE=4,PKG_STATE=base+0x400,PKG_BUFFER=base+0x500,
                    PKG_CURRENT=base+0x420,PKG_LOCK=base+0x421,PKG_MAPPED=base+0x422,
                    PKG_CAPS_LOW=base+0x430,PKG_CAPS_HIGH=base+0x432,
                    APP_BASE=0x4000,ADMISSION_SYSINFO_SIZE=48,ADMISSION_TYPED_CLIPBOARD=1,
                    ADMISSION_STREAMED=1)
                code=[*[f'{n} equ {v}' for n,v in cells.items()],
                    'PKG_MAP equ map_page','PKG_READ equ read_stream','PKG_CLOSE equ close_stream',
                    'OWNER_PAGE_CURRENT_OWNER equ unused','OWNER_PAGE_PURGE_MESSAGES equ unused',
                    'OWNER_PAGE_CLOSE_CONTEXTS equ unused','macro OWNER_PAGE_PUBLISH_FREE','mend',
                    f'include "{ROOT}/kernel/core/owner_page_contract.inc"',
                    f'include "{ROOT}/kernel/core/package_stream_contract.inc"',
                    'macro ADMISSION_STORAGE','gb4_file_size ds 2','gb4_manifest_offset ds 2',
                    'gb4_resource_offset ds 2','gb4_icon_count ds 1','gb4_expected_crc ds 4',
                    'gb4_crc_value ds 4','mend','org #8000','fixture_begin',
                    'map_page','ld (PKG_MAPPED),a','out (#FE),a','ret',
                    'read_stream','out (#FD),a','ret','close_stream','out (#FC),a','ret',
                    'unused','ret']
                for unit in ('page_count.asm','owner_identity.asm','page_pool.asm','owner_reclaim.asm',
                             'app_admission.asm','package_stream.asm'):
                    code.append(f'include "{ROOT}/kernel/core/{unit}"')
                code+=['fixture_end','save "stream.bin",#8000,$-#8000']
                src=temp/'stream.asm';src.write_text('\n'.join(code)+'\n')
                result=subprocess.run(['rasm',str(src),'-s','-sq','-o','stream'],cwd=temp,
                                      capture_output=True,text=True)
                self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                symbols={n:int(v,16) for n,v in re.findall(r'^(\w+) #([0-9A-Fa-f]+)',(temp/'stream.sym').read_text(),re.M)}
                public={**cells,**{n:symbols[n] for n in (
                    'PKG_PAGE','PKG_ENTRY','PKG_SECONDARY_SIZE','PKG_STATUS','PKG_BUSY',
                    'PKG_BACK','PACKAGE_LOAD','OWNER_RELEASE','PAGE_FREE_OWNED','PAGE_CHECK_OWNED')}}
                (temp/'stream_fixture.h').write_text('\n'.join(f'#define {n} {v}' for n,v in public.items())+'\n')
                exe=temp/'test'
                subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-O2',
                    '-I',str(CORE),'-I',str(temp),str(ROOT/'tests/package_stream_z80.c'),
                    str(CORE/'z80.c'),'-o',str(exe)],check=True)
                subprocess.run([str(exe),str(temp/'stream.bin'),*[str(temp/f'case{n}.APP') for n in range(3)]],check=True)
                print(f'stream policy bytes: transaction={symbols["FIXTURE_END"]-symbols["PACKAGE_LOAD"]}, '
                      f'admission+CRC={symbols["PACKAGE_LOAD"]-symbols["GBAP4_VALIDATE_STREAMED_PRIMARY"]}; '
                      f'fixed state layout={base:04X}')
                for name,value,message in (
                    ('PKG_STATE',0x4000,'package state must remain fixed'),
                    ('PKG_BUFFER',0x7EFF,'package transfer must remain fixed'),
                    ('PKG_BUFFER',cells['PKG_STATE']+16,'package state/transfer overlap'),
                    ('PKG_CAPS_LOW',0x7FFF,'package low capabilities must remain fixed')):
                    bad='\n'.join(code).replace(f'{name} equ {cells[name]}',f'{name} equ {value}')
                    src.write_text(bad+'\n')
                    rejected=subprocess.run(['rasm',str(src)],cwd=temp,capture_output=True,text=True)
                    self.assertNotEqual(rejected.returncode,0)
                    self.assertIn(message,rejected.stdout+rejected.stderr)

    def test_not_advertised_or_wired_before_receiver_acceptance(self):
        for unit in ('kernel/msx_gbap4.asm','kernel/cpc_loading.asm'):
            source=(ROOT/unit).read_text()
            self.assertNotIn('ADMISSION_STREAMED equ',source)
            self.assertNotIn('include "core/package_stream.asm"',source)
        contract=(ROOT/'docs/PORTABLE-SECONDARY-CODE.md').read_text()
        self.assertIn('not yet implemented',contract)


if __name__=='__main__':unittest.main()
