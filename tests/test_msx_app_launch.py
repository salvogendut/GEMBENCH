"""Actual normal-launch router with controlled storage/admission boundaries."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
CORE=Path(os.environ.get('MSX_1983_SOURCE',ROOT.parent/'1983'))/'src'


class MSXLaunchTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('rasm') and shutil.which('cc') and (CORE/'z80.c').exists(),
                         'RASM, cc and read-only 1983 CPU sources required')
    def test_real_router_and_early_guards(self):
        with tempfile.TemporaryDirectory(prefix='msx-launch-') as directory:
            stage=Path(directory)
            (stage/'test.asm').write_text(f'''
PLATFORM_MSX equ 1
PREEMPTIVE equ 1
PORTABLE_DATA_PAGES equ 1
PORTABLE_PACKAGE_STREAM equ 1
include "{ROOT}/lib/gbapp.inc"
include "{ROOT}/lib/msx/glue.inc"
include "{ROOT}/kernel/lowram.inc"
CORE_PENDING_OWNER equ MSX_PENDING_OWNER
fs_load_dst equ #14F7
fs_load_max equ #14F9
fs_ent_size equ #14E8
fsmx_total equ #3010
FSMX_IOBUF equ #1800
cursor_x equ #3012
cursor_y equ #3014
poll_byte equ #14A2
poll_line equ #14A3
org #1C00
include "{ROOT}/kernel/msx_app_launch.asm"
save "route.bin",#1C00,$-#1C00
org #9000
fs_load_sys
xor a
jr fake_fs
fs_load_cur_sys
ld a,1
fake_fs
ld (#3000),a
ld a,(#3001)
inc a
ld (#3001),a
ld a,(#3002)
or a
ret z
ei
ld hl,(#3003)
ld c,9
call msx_app_probe
ret c
scf
ret
input_poll ret
poll_move ret
cursor_move_to ret
msx_secondary_commit
ld a,(#3006)
inc a
ld (#3006),a
ld a,(#3007)
or a
ret nz
scf
ret
save "stubs.bin",#9000,$-#9000
''')
            subprocess.run(['rasm',str(stage/'test.asm'),'-s','-sq','-o','route'],cwd=stage,
                           check=True,capture_output=True)
            symbols={n:int(v,16) for n,v in re.findall(r'^(\w+) #([0-9A-Fa-f]+)',
                     (stage/'route.sym').read_text(),re.M)}
            names=('MSX_APP_LOAD','MSX_APP_CAN_LAUNCH','MSX_APP_PROBE','MSX_PENDING_OWNER')
            (stage/'fixture.h').write_text('\n'.join(f'#define {n} {symbols[n]}' for n in names)+'\n')
            exe=stage/'check'
            subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-I',str(CORE),'-I',str(stage),
                            str(ROOT/'tests/msx_app_launch_z80.c'),str(CORE/'z80.c'),'-o',str(exe)],check=True)
            subprocess.run([str(exe),str(stage/'route.bin'),str(stage/'stubs.bin')],check=True)


if __name__=='__main__':unittest.main()
