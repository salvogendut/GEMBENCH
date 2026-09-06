"""Portable FS ABI/client checks; actual hardware paths use 1984/openMSX."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]


class PortableFilesystemTests(unittest.TestCase):
    def test_authority_and_shared_receiver_bindings(self):
        authority=json.loads((ROOT/'abi/geobench-v2.json').read_text())
        fs=authority['portable_filesystem']
        self.assertEqual(authority['version'],[2,1])
        self.assertEqual(authority['caller_parameters']['operations']['filesystem'],8)
        self.assertEqual((fs['header_size'],fs['transfer_size']),(32,512))
        self.assertEqual(sorted(fs['operations'].values()),list(range(15)))
        positions=[i for f in fs['header_fields'] for i in range(f['offset'],f['offset']+f['size'])]
        self.assertEqual(positions,list(range(32)))
        for machine,call in (('msx','GB_FSCTX'),('cpc','cpc_fsctx_call')):
            provider=(ROOT/f'kernel/{machine}_parameter_provider.inc').read_text()
            self.assertIn('PARAM_FS_CALL equ '+call,provider)
        core=(ROOT/'kernel/core/parameters_fs.asm').read_text()
        self.assertLess(core.index('call up_span'),core.index('up_fs_copy\n'))
        self.assertLess(core.index('CORE_PARAM_CURRENT'),core.index('ldir'))
        self.assertNotIn('#C400',core)
        self.assertNotIn('#1500',core)

    def test_universal_client_reuses_policy_not_native_addresses(self):
        client=(ROOT/'lib/gembench/gbfsctx_universal.c').read_text()
        self.assertIn('gb_uparam_call(&request)',client)
        self.assertNotIn('0x80D2',client)
        self.assertNotIn('0xC400',client)
        self.assertIn('#include "core/fsctx_client.inc"',(ROOT/'lib/gembench/gbfsctx.c').read_text())
        builder=(ROOT/'tools/build_uapp.sh').read_text()
        self.assertIn('UNIVERSAL_FS requires portable-filesystem',builder)
        self.assertIn('gbfsctx gbfsctx_universal',builder)

    @unittest.skipUnless(shutil.which(os.environ.get('SDCC','sdcc')),'SDCC required')
    def test_target_client_layout_and_optional_link_are_deterministic(self):
        with tempfile.TemporaryDirectory(prefix='portable-fs-unit-') as name:
            temp=Path(name)
            source=temp/'layout.c'
            source.write_text('#include "gbfsctx.h"\n'
                              'typedef char entry_size[sizeof(gb_fsctx_entry_t)==16?1:-1];\n'
                              'typedef char handle_size[sizeof(gb_fsctx_t)==2?1:-1];\n')
            subprocess.run([os.environ.get('SDCC','sdcc'),'-mz80','--std-c99','-DGB_UNIVERSAL',
                            '-I',str(ROOT/'lib/gb'),'-I',str(ROOT/'include/gembench'),
                            '-c',str(source),'-o',str(temp/'layout.rel')],check=True)
            env={**os.environ,'UNIVERSAL_FS':'1'}
            for output in ('one.app','two.app'):
                subprocess.run(['bash','tools/build_uapp.sh','apps/fsprobe',str(temp/output)],
                               cwd=ROOT,env=env,check=True,stdout=subprocess.DEVNULL)
            self.assertEqual((temp/'one.app').read_bytes(),(temp/'two.app').read_bytes())
            bad=subprocess.run(['bash','tools/build_uapp.sh','apps/abiprobe',str(temp/'bad.app')],
                               cwd=ROOT,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
            self.assertNotEqual(bad.returncode,0)
            self.assertIn('UNIVERSAL_FS requires portable-filesystem',bad.stdout)
