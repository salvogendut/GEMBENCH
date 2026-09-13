"""Real shared launcher/transaction/cleanup, with controlled allocation/storage."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
CPU=Path(os.environ.get('MSX_1983_SOURCE',ROOT.parent/'1983'))/'src'


class DocumentLaunchTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('rasm') and shutil.which('cc') and (CPU/'z80.c').exists(),
                         'RASM, C compiler and read-only 1983 CPU source required')
    def test_real_launch_transaction(self):
        with tempfile.TemporaryDirectory(prefix='document-launch-') as directory:
            stage=Path(directory)
            (stage/'fixture.asm').write_text(f'''
WM_NWIN equ #3000
WM_MAXWIN equ 8
CORE_PENDING_OWNER equ #3002
bank_cur equ #3004
wm_open_page equ #3005
wm_open_back equ #3006
fs_req_name equ #3010
launch_arg equ #3020
fs_ent_name equ #3030
GB_PAGE_APPLICATION equ 1
APP_BASE equ #4000
APP_LOAD_AND_ADMIT equ fake_load
APP_LAUNCH_TRANSACTION equ document_launch
APP_LAUNCH_BIND equ document_bind
DOC_PENDING equ #3100
DOC_CURRENT_OWNER equ owner_current
DOC_LAUNCH_BODY equ wm_open_transaction
DOC_LAUNCH_ARG equ launch_arg
DOC_COPY_NAME equ copy11
DOC_RELEASING_OWNER equ #3008
DOC_WORKER equ #300A
CORE_FSCTX_TABLE equ #3200
CORE_FSCTX_MAX equ 4
CORE_FSCTX_ACTIVE equ 0
CORE_FSCTX_OWNER equ 2
CORE_FSCTX_RECORD_SIZE equ 144
CORE_ALLOC_OWNER equ DOC_RELEASING_OWNER
CORE_FSCTX_CLEANUP_TAIL equ document_owner_cleanup
org #8000
include "{ROOT}/kernel/core/app_launch.asm"
include "{ROOT}/kernel/core/document_launch.asm"
include "{ROOT}/kernel/core/fsctx_cleanup.asm"
copy11 ld bc,11
ldir
ret
bank_set ld (bank_cur),a
ret
owner_current ret
owner_alloc ret
page_alloc_owned ret
app_bind_code_page ret
owner_release ret
fake_load ret
save "fixture.bin",#8000,$-#8000
''')
            subprocess.run(['rasm',str(stage/'fixture.asm'),'-s','-sq','-o','fixture'],
                           cwd=stage,check=True,capture_output=True)
            names=dict(re.findall(r'^(\w+) #([0-9A-Fa-f]+)',(stage/'fixture.sym').read_text(),re.M))
            (stage/'fixture.h').write_text('\n'.join(f'#define {n} 0x{v}' for n,v in names.items()))
            exe=stage/'check'
            subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-I',str(CPU),'-I',str(stage),
                            str(ROOT/'tests/document_launch_z80.c'),str(CPU/'z80.c'),'-o',str(exe)],check=True)
            subprocess.run([str(exe),str(stage/'fixture.bin')],check=True)


if __name__=='__main__':unittest.main()
