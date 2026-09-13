"""Fixed MSX module composition and boot rejection, not streamed WM launch."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CORE = Path(os.environ.get('MSX_1983_SOURCE', ROOT.parent/'1983'))/'src'
sys.path.insert(0, str(ROOT/'tools'))
from build_msx_package_modules import compose, build


class PackageModulesTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('tclsh'), 'Tcl required')
    def test_stream_observer_cannot_pass_without_three_launches(self):
        with tempfile.TemporaryDirectory(prefix='msx-launch-observer-') as directory:
            stage = Path(directory)
            primary = stage/'primary.bin'; primary.write_bytes(bytes(256))
            secondary = stage/'secondary.bin'; secondary.write_bytes(bytes(16128))
            report = stage/'result.txt'
            env = {**os.environ, 'GEOBENCH_FS_STATE': '20000', 'GEOBENCH_FS_OUTPUT': str(report),
                   'GEOBENCH_LAUNCH_PRIMARY': str(primary), 'GEOBENCH_LAUNCH_SECONDARY': str(secondary),
                   'GEOBENCH_LAUNCH_CASE': 'good'}
            env.update({'GEOBENCH_LAUNCH_'+name: '1' for name in
                        ('MSX_APP_LOAD','MSX_APP_RETURN','PKG_SECONDARY_ENTRY','MSX_APP_PROGRESS_UPDATED')})
            script = '''
proc debug {args} {return {}}
proc after {args} {}
proc peek {at} {return 0}
rename exit real_exit
proc exit {args} {}
source debug/portable_launch_openmsx.tcl
if {![catch {fs_finish PASS}]} {real_exit 1}
set launch_cycles 3
fs_finish PASS
real_exit 0
'''
            subprocess.run(['tclsh'], input=script, text=True, env=env, cwd=ROOT,
                           check=True, capture_output=True)
            self.assertIn('STATUS=FAIL incomplete launch cycles\n', report.read_text())
            self.assertNotIn('STATUS=PASS', report.read_text())

    @unittest.skipUnless(shutil.which('tclsh'), 'Tcl required')
    def test_lifecycle_observer_is_fail_closed_and_waits_for_mapped_desktop(self):
        with tempfile.TemporaryDirectory(prefix='msx-package-observer-') as directory:
            report = Path(directory)/'result.txt'
            env = {**os.environ, 'GEOBENCH_FS_STATE': '20000', 'GEOBENCH_FS_OUTPUT': str(report)}
            script = '''
proc debug {args} {return {}}
proc after {args} {}
proc peek {at} {return 0}
rename exit real_exit
proc exit {args} {}
source debug/portable_pages_openmsx.tcl
fs_start
if {[info exists ::page_baseline]} {real_exit 1}
rename peek peek_unused
proc peek {at} {
    switch [expr {$at+0}] {1027 {return 71} 1028 {return 66} 1029 {return 86}
        1030 {return 52} 52992 {return 48} 4944 {return 1} default {return 0}}
}
proc fs_start_pages_input {} {set ::started 1}
fs_start
if {![info exists ::page_baseline] || ![info exists ::started]} {real_exit 2}
if {![catch {fs_finish "FAIL deliberate"; fs_finish PASS}]} {real_exit 3}
fs_finish PASS
real_exit 0
'''
            subprocess.run(['tclsh'], input=script, text=True, env=env, cwd=ROOT,
                           check=True, capture_output=True)
            self.assertIn('STATUS=FAIL deliberate\n', report.read_text())
            self.assertNotIn('STATUS=PASS', report.read_text())

    def test_composition_rejects_mixed_modules_and_state_overlap(self):
        parts = {name: (b'\xC3\0\0'+magic).ljust(size, b'\0')
                 for name, size, magic in [('GBAPV4.RAW', 2996, b'GBV4\4'),
                     ('GBPKIO.RAW', 293, b'GBIO\3'), ('GBDPAGE.RAW', 492, b'GBDP\1'),
                     ('GBPKLOAD.RAW', 747, b'GBPK\2')]}
        parts['GBPKCRC.RAW'] = bytes([0xC9])*186
        parts['GBPKEX.RAW'] = bytes([0xC9])*15
        good = compose(parts)
        self.assertEqual(len(good['GBPKFIX.MOD']), 1061)
        self.assertEqual(good['GBPKFIX.MOD'][-16:], bytes(16))
        self.assertEqual(good['GBPKFIX.MOD'][293:785], parts['GBDPAGE.RAW'])
        for name in parts:
            for data in (b'', parts[name][:-1] if name not in ('GBPKCRC.RAW','GBPKEX.RAW') else bytes(261),
                         parts[name]+bytes(300)):
                with self.subTest(name=name, size=len(data)), self.assertRaises(ValueError):
                    compose({**parts, name: data})
        with self.assertRaises(ValueError):
            compose({**parts, 'GBAPV4.RAW': parts['GBAPV4.RAW'][:7]+b'\2'+parts['GBAPV4.RAW'][8:]})

    @unittest.skipUnless(shutil.which('rasm') and shutil.which('cc') and (CORE/'z80.c').exists(),
                         'RASM, cc and read-only 1983 CPU source required')
    def test_real_boot_loader_faults_and_irq_install_boundary(self):
        with tempfile.TemporaryDirectory(prefix='msx-package-boot-') as directory:
            stage = Path(directory)
            build(stage)
            # Boot validation depends on size/header, not executable router
            # contents; actual router control flow has its own integration tests.
            (stage/'GBPKWM.MOD').write_bytes((b'\xC3\x0E\x1CGBWM\x36').ljust(256,b'\0'))
            fs = (ROOT/'lib/msx/fs.asm').read_text()
            probe = fs[fs.index('\nfsload_maxed\n')+1:fs.index('\nfsload_success\n')]
            (stage/'boot.asm').write_text(f'''
PORTABLE_DATA_PAGES equ 1
PORTABLE_PACKAGE_STREAM equ 1
MSX_PACKAGE_ROUTE_SIZE equ 256
MSX_SCREEN_MODE equ 6
include "{ROOT}/lib/msx/glue.inc"
fs_req_name equ #14EC
fs_load_dst equ #14F7
fs_load_max equ #14F9
fs_ent_size equ #14E8
org #9000
include "{ROOT}/kernel/msx_package_boot.asm"
copy11
ld bc,11
ldir
ret
fs_load_sys ret
BDOS equ 5
_READ equ #48
FS_XFLAGS equ #144F
fsmx_handle equ #2101
fsmx_probe equ #2102
{probe}
fsload_success scf
ret
fsload_readfail
fsload_toobig xor a
ret
save "boot.bin",#9000,$-#9000
''')
            subprocess.run(['rasm', str(stage/'boot.asm'), '-s', '-sq', '-o', 'boot'],
                           cwd=stage, check=True, capture_output=True)
            sym = {n: int(v, 16) for n, v in re.findall(r'^(\w+) #([0-9A-Fa-f]+)',
                   (stage/'boot.sym').read_text(), re.M)}
            (stage/'fixture.h').write_text('\n'.join(f'#define {n} {sym[n]}' for n in
                ('PACKAGE_MODULES_LOAD', 'FS_LOAD_SYS', 'FSLOAD_MAXED'))+'\n')
            exe = stage/'check'
            subprocess.run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-I', str(CORE),
                            '-I', str(stage), str(ROOT/'tests/msx_package_boot_z80.c'),
                            str(CORE/'z80.c'), '-o', str(exe)], check=True)
            subprocess.run([str(exe), str(stage/'boot.bin'), str(stage/'GBAPV4.MOD'),
                            str(stage/'GBPKFIX.MOD'), str(stage/'GBPKLOAD.MOD'),
                            str(stage/'GBPKWM.MOD')], check=True)


if __name__ == '__main__':
    unittest.main()
