"""Explicit historical/document boot profiles; no signature auto-detection."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from embed_app_icon import (_read_v4_manifest_spec,parse_icon,make_v4_preamble,
                            v4_preamble_size,refresh_v4_crc)


def app(name,secondary=None):
    spec=_read_v4_manifest_spec(ROOT/f'apps/{name}/manifest.json')
    icon=parse_icon(ROOT/'apps/abiprobe/icon.asm');body=b'\xC9'
    size=v4_preamble_size(False,2 if secondary else 1)+len(body)
    data=bytearray(make_v4_preamble(icon,spec,size,size+len(secondary or b''),secondary=secondary)+body+(secondary or b''))
    refresh_v4_crc(data);return data


@unittest.skipUnless(shutil.which('rasm'),'RASM required')
class DeliveryGateTests(unittest.TestCase):
    def test_explicit_profiles_reject_mixed_validator_and_mode_modules(self):
        with tempfile.TemporaryDirectory(prefix='msx-delivery-gate-') as tmp:
            stage=Path(tmp);probe=stage/'ABIPROBE.APP';probe.write_bytes(app('abiprobe'))
            cmd=[sys.executable,str(ROOT/'tools/test_geobench_v2_msx_gate.py'),
                 '--gate',str(stage/'GBAPV4.RAW'),'--app',str(probe)]
            for profile in ('primary','document'):
                flags=[] if profile=='primary' else ['-DPORTABLE_DATA_PAGES=1',
                       '-DPORTABLE_PACKAGE_STREAM=1','-DPORTABLE_FS_IDENTITY=1','-DPORTABLE_FS_HANDOFF=1']
                subprocess.run(['rasm',str(ROOT/'kernel/msx_gbap4.asm'),*flags],
                               cwd=stage,check=True,capture_output=True)
                subprocess.run(cmd+['--receiver',profile],check=True,capture_output=True)
                bad='primary' if profile=='document' else 'document'
                self.assertNotEqual(subprocess.run(cmd+['--receiver',bad],capture_output=True).returncode,0)
            (stage/'NOTEPAD.APP').write_bytes(app('unotepad',b'\xC3\x08\x40GBS4\x01\xC9'))
            for name,size,magic in [('GBPKFIX.MOD',1061,b'GBIO\x03'),
                                    ('GBPKLOAD.MOD',747,b'GBPK\x02'),
                                    ('GBPKWM6.MOD',1496,b'GBWM\x66'),
                                    ('GBPKWM7.MOD',1496,b'GBWM\x67')]:
                (stage/name).write_bytes((b'\xC3\x08\x04'+magic).ljust(size,b'\0'))
            subprocess.run(cmd+['--staged',str(probe)],check=True,capture_output=True)
            path=stage/'GBPKWM7.MOD';original=path.read_bytes()
            for changed in (original[:-1],original[:7]+b'\x66'+original[8:]):
                path.write_bytes(changed)
                result=subprocess.run(cmd+['--staged',str(probe)],capture_output=True,text=True)
                self.assertNotEqual(result.returncode,0)
                self.assertIn('mixed/incomplete document receiver: GBPKWM7.MOD',result.stderr)


if __name__=='__main__':unittest.main()
