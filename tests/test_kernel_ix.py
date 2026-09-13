"""Opt-in compact C profile: execute the generated real kernel trampolines."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[1]
CORE=ROOT.parent/'1983/src'
sys.path.insert(0,str(ROOT/'tools'))
from preserve_kernel_ix import generate
from gblib_subset import generate as subset

class KernelIXTests(unittest.TestCase):
    def test_only_frozen_vectors_are_transformed(self):
        self.assertEqual(generate('jp (hl)\ncall helper\n'), 'jp (hl)\ncall helper\n')
        with self.assertRaises(ValueError):generate(' jp 0x4008\n')
        with self.assertRaises(ValueError):generate(' call 0x8001\n')
        self.assertIn('push ix\n        call 0x8033',generate(' call 0x8033\n'))

    @unittest.skipUnless(shutil.which('sdcc') and shutil.which('cc') and (CORE/'z80.c').exists(),
                         'SDCC, cc and read-only 1983 CPU required')
    def test_generated_wrappers_with_clobbering_kernel_and_irqs(self):
        with tempfile.TemporaryDirectory(prefix='kernel-ix-') as directory:
            stage=Path(directory);binpath=Path(shutil.which('sdcc')).parent
            names=('fill','frame','saverect','restorerect','poll','getkey','menu','restore_parent')
            manifest=stage/'symbols';manifest.write_text('\n'.join('gb_'+n for n in names))
            sources={'gblib':subset(ROOT/'lib/gb/gblib.s',[manifest],interrupt_safe=True),
                     'gbsys':(ROOT/'lib/gb/gbsys.s').read_text(),
                     'kind':(ROOT/'lib/gb/gbwindow_kind.s').read_text()}
            for name,source in sources.items():
                (stage/f'{name}.s').write_text(generate(source)+'\n        .area _DATA\n')
                subprocess.run([str(binpath/'sdasz80'),'-o',str(stage/f'{name}.rel'),str(stage/f'{name}.s')],check=True)
            subprocess.run(['sdcc','-mz80','--no-std-crt0','--code-loc','0x4000','--data-loc','0x7000',
                *[str(stage/f'{n}.rel') for n in sources],'-o',str(stage/'test.ihx')],check=True)
            subprocess.run([str(binpath/'makebin'),'-p',str(stage/'test.ihx'),str(stage/'test.bin')],check=True)
            symbols={m[1]:int(m[2],16) for m in re.finditer(r'^DEF (_gb_\w+) (0x[0-9A-Fa-f]+)',
                (stage/'test.noi').read_text(),re.M)}
            (stage/'fixture.h').write_text('\n'.join(f'#define {n.upper()} {v}' for n,v in symbols.items())+'\n')
            exe=stage/'run'
            subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-I',str(stage),'-I',str(CORE),
                str(ROOT/'tests/kernel_ix_z80.c'),str(CORE/'z80.c'),'-o',str(exe)],check=True)
            subprocess.run([str(exe),str(stage/'test.bin')],check=True)
