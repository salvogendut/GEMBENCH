"""Optional API-v2 identity SDK, default-profile compatibility and Z80 layout."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]


class FilesystemIdentityTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('cc'),'host compiler required')
    def test_checked_client_preserves_output_on_error(self):
        with tempfile.TemporaryDirectory(prefix='fs-identity-') as directory:
            binary=Path(directory)/'test'
            subprocess.run(['cc','-std=c99','-Wall','-Wextra','-Werror',
                '-DGB_UNIVERSAL','-DGB_UNIVERSAL_HOST_TEST','-I',str(ROOT/'lib/gb'),
                '-I',str(ROOT/'include/gembench'),str(ROOT/'tests/test_fsctx_identity.c'),
                '-o',str(binary)],check=True)
            subprocess.run([str(binary)],check=True)

    @unittest.skipUnless(shutil.which(os.environ.get('SDCC','sdcc')),'SDCC required')
    def test_z80_wire_layout_and_portable_source(self):
        with tempfile.TemporaryDirectory(prefix='fs-identity-z80-') as directory:
            path=Path(directory)
            source=path/'layout.c'
            source.write_text('#include "gbfsctx.h"\n#include <stddef.h>\n'
                'typedef char size_ok[sizeof(gb_fsctx_identity_t)==60?1:-1];\n'
                'typedef char name_ok[offsetof(gb_fsctx_identity_t,name)==1?1:-1];\n'
                'typedef char path_ok[offsetof(gb_fsctx_identity_t,path)==12?1:-1];\n')
            command=[os.environ.get('SDCC','sdcc'),'-mz80','--std-c99','--opt-code-size',
                     '-DGB_UNIVERSAL','-I',str(ROOT/'lib/gb'),'-I',str(ROOT/'include/gembench'),'-c']
            subprocess.run(command+[str(source),'-o',str(path/'layout.rel')],check=True)
            subprocess.run(command+[str(ROOT/'lib/gembench/gbfsctx_identity.c'),'-o',str(path/'identity.rel')],check=True)
            subprocess.run(['python3',str(ROOT/'tools/check_universal_app.py'),
                '--source',str(ROOT/'lib/gembench/gbfsctx_identity.c'),'--asm',str(path/'identity.asm')],check=True)

    def test_existing_profiles_do_not_enable_identity(self):
        builder=(ROOT/'tools/build_fsctxmod.sh').read_text()
        self.assertIn('${PORTABLE_FS_IDENTITY:-0}',builder)
        self.assertIn('"IDENTITY=$identity"',builder)
        self.assertIn('ifdef PORTABLE_FS_IDENTITY',(ROOT/'kernel/msx_sysinfo_init.asm').read_text())
        self.assertNotIn('PARAM_FS_IDENTITY equ',(ROOT/'kernel/cpc_parameter_provider.inc').read_text())
