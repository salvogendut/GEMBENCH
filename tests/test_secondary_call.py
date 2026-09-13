"""Execute sealed-call policy, real ownership/page teardown and a banked leaf."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
import sys
from test_owner_page_core import STATE_FIELDS

ROOT = Path(__file__).resolve().parents[1]
CORE = Path(os.environ.get('MSX_1983_SOURCE', ROOT.parent/'1983'))/'src'
sys.path.insert(0,str(ROOT/'tools'))
from check_secondary_app import audit


class SecondaryCallTests(unittest.TestCase):
    def test_binary_stamp_requires_object_and_link_audit(self):
        with tempfile.TemporaryDirectory(prefix='secondary-stamp-') as directory:
            stage=Path(directory);src=stage/'main.c';binary=stage/'leaf.bin'
            src.write_text('void secondary_main(void) {}')
            binary.write_bytes(b'\xC3\x08\x40GBS4\1\xC9')
            result=subprocess.run([sys.executable,str(ROOT/'tools/check_secondary_app.py'),
                '--source',str(src),'--binary',str(binary)],capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertIn('--binary requires',result.stderr)
            self.assertFalse(binary.with_suffix('.bin.audit.json').exists())

    def test_restricted_source_and_generated_code_audit(self):
        with tempfile.TemporaryDirectory(prefix='secondary-audit-') as directory:
            stage=Path(directory);src=stage/'main.c';asm=stage/'main.asm';link=stage/'leaf.map'
            src.write_text('void secondary_main(unsigned char *p, unsigned int n) { while(n--) ++*p++; }')
            asm.write_text(' ld a,(hl)\n inc a\n ld (hl),a\n ret\n')
            link.write_text('crt0_secondary.rel [ crt0_secondary ]\nmain.rel [ main ]\nmemcpy.rel [ memcpy ]\n')
            self.assertEqual(audit([src],[asm],link),[])
            for text in ('void f(void) { gb_poll(); }','void f(void) { malloc(42); }',
                         'void f(void) { __asm nop __endasm; }',
                         'unsigned char p = *(unsigned char *)0x8000;'):
                src.write_text(text)
                self.assertTrue(audit([src],[],None),text)
            src.write_text('void secondary_main(void) {}')
            for text in (' ei\n',' di\n',' halt\n',' out (c),a\n',' call _gb_poll\n',
                         ' call 0x8000\n',' ld a,(0xC400)\n'):
                asm.write_text(text)
                self.assertTrue(audit([src],[asm],None),text)
            asm.write_text(' ret\n')
            link.write_text(link.read_text()+'file.rel [ fopen ]\n')
            self.assertTrue(audit([src],[asm],link))

    @unittest.skipUnless(shutil.which('rasm'),'RASM required')
    def test_capability_only_in_opt_in_msx_receiver(self):
        with tempfile.TemporaryDirectory(prefix='secondary-caps-') as directory:
            stage=Path(directory)
            for definitions,expected in (('',False),('PORTABLE_DATA_PAGES equ 1\n',False),
                    ('PORTABLE_DATA_PAGES equ 1\nPORTABLE_PACKAGE_STREAM equ 1\n',True)):
                (stage/'caps.asm').write_text(definitions+
                    f'include "{ROOT}/kernel/msx_capabilities.inc"\norg 0\n'
                    'dw GB_CAPS_HIGH_MSX_V6\nsave "caps.bin",0,2\n')
                subprocess.run(['rasm',str(stage/'caps.asm')],cwd=stage,check=True,capture_output=True)
                self.assertEqual(bool(int.from_bytes((stage/'caps.bin').read_bytes(),'little')&0x400),expected)

    @unittest.skipUnless(shutil.which('rasm') and shutil.which('cc') and (CORE/'z80.c').exists(),
                         'RASM, cc and read-only 1983 CPU sources required')
    def test_shared_seals_calls_and_reuse_at_two_fixed_layouts(self):
        for base in (0x2000, 0xD800):
            cells = {}; cursor = base
            for name, size in STATE_FIELDS:
                if (cursor & 255)+size > 256: cursor = (cursor+255)&~255
                cells[name] = cursor; cursor += size
            cells.update(CORE_PAGE_CAPACITY=32,CORE_OWNER_CAPACITY=8,CORE_WINDOW_MAX=8,
                GB_OWNER_MAX=8,GB_PAGE_RESOURCE=2,GB_PAGE_ERR_STALE=2,GB_PAGE_ERR_OWNER=3,GB_PAGE_ERR_FREE=4,
                SEC_OWNER_MAX=8,SEC_TABLE=base+0x480,SEC_STATE=base+0x440,SEC_TRANSFER=base+0x500,
                SEC_CURRENT=base+0x450,SEC_MAPPED=base+0x451,SEC_LOCK=base+0x452,OWNER=base+0x454,
                BIND_RECORD=base+0x460,SEC_ALLOW_IRQ=1)
            code = [*[f'{n} equ {v}' for n,v in cells.items()],
                'SEC_OWNER_CURRENT equ current_owner','OWNER_PAGE_CURRENT_OWNER equ current_owner',
                'SEC_MAP equ map_page','PAGE_SEAL_RELEASE equ secondary_seal_page_release',
                'OWNER_SEAL_RELEASE equ secondary_seal_clear',
                'macro OWNER_PAGE_PUBLISH_FREE','mend',
                'OWNER_PAGE_PURGE_MESSAGES equ nothing','OWNER_PAGE_CLOSE_CONTEXTS equ nothing',
                f'include "{ROOT}/kernel/core/owner_page_contract.inc"',
                f'include "{ROOT}/kernel/core/secondary_contract.inc"', 'org #8000',
                'current_owner','ld de,(OWNER)','ret','nothing ret',
                'map_page','ld (SEC_MAPPED),a','out (#FE),a','ret',
                'irq_handler','push af','out (#FB),a','pop af','ei','reti']
            for name in ('page_count.asm','owner_identity.asm','page_pool.asm','owner_reclaim.asm','secondary_call.asm'):
                code.append(f'include "{ROOT}/kernel/core/{name}"')
            code += ['save "calls.bin",#8000,$-#8000',
                'org #4008','leaf',
                'push hl','ld a,(SEC_BUSY)','cp 1','jp nz,leaf_bad',
                'ld a,(SEC_LOCK)','or a','jp z,leaf_bad',
                'ld a,i','jp po,leaf_bad',
                'ld a,(hl)','or a','jr nz,leaf_mutate',
                # Real nested gate call must fail without disturbing the outer operation.
                'push bc','call secondary_call','cp 5','jp nz,leaf_bad','pop bc',
                'leaf_mutate','pop hl','leaf_loop','inc (hl)','inc hl','dec bc','ld a,b','or c',
                'jr nz,leaf_loop','ld ix,#7654','ld iy,#3210','ret',
                'leaf_bad','halt','jr leaf_bad','save "leaf.bin",#4008,$-#4008']
            with tempfile.TemporaryDirectory(prefix='secondary-call-') as directory:
                stage=Path(directory); (stage/'test.asm').write_text('\n'.join(code)+'\n')
                result=subprocess.run(['rasm',str(stage/'test.asm'),'-s','-sq','-o','calls'],
                                      cwd=stage, text=True, capture_output=True)
                self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                sym={n:int(v,16) for n,v in re.findall(r'^(\w+) #([0-9A-Fa-f]+)',(stage/'calls.sym').read_text(),re.M)}
                names=('SECONDARY_CALL','SECONDARY_SEAL_BIND','SECONDARY_SEAL_CLEAR',
                       'OWNER_RELEASE','PAGE_FREE_OWNED','PAGE_ALLOC_OWNED','OWNER_ALLOC','IRQ_HANDLER')
                (stage/'fixture.h').write_text('\n'.join(f'#define {n} {v}' for n,v in
                    {**cells,**{n:sym[n] for n in names}}.items())+'\n')
                exe=stage/'check'
                subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-I',str(CORE),'-I',str(stage),
                                str(ROOT/'tests/secondary_call_z80.c'),str(CORE/'z80.c'),'-o',str(exe)],check=True)
                subprocess.run([str(exe),str(stage/'calls.bin'),str(stage/'leaf.bin')],check=True)
                print('secondary fixed policy bytes:',(stage/'calls.bin').stat().st_size)


if __name__=='__main__':unittest.main()
