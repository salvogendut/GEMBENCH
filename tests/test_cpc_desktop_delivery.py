from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import zlib
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from build_cpc_runtime import build
from cpc_desktop_media import check_destination, validate


class DesktopDeliveryTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix='cpc delivery ')
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.media = self.root/'QA/CPC-Desktop'
        (self.media/'CARD/GBENCH').mkdir(parents=True)
        self.files = {name: b'fixture: '+name.encode() for name in (
            'BOOT.BIN', 'CORE.BIN', 'GEOBENCH.CFG', 'GBENCH/ROOTUI.BIN',
            'GBENCH/CLOCK.APP', 'GBENCH/CALC.APP')}
        for name, data in self.files.items():
            (self.media/'CARD'/name).write_bytes(data)
        self.image = self.media/'GEOBENCH.IMG'
        self.image.write_bytes(b'private test image')
        self.manifest = dict(profile='cpc-desktop-m4-v1', storage='m4',
            directories=['GBENCH'], image=str(self.image),
            image_sha256=hashlib.sha256(self.image.read_bytes()).hexdigest(),
            files={n: hashlib.sha256(data).hexdigest() for n, data in self.files.items()},
            sections={'bar': dict(staged=True, source='apps/desktop/main.c')})
        self.save()

    def save(self):
        (self.media/'manifest.json').write_text(json.dumps(self.manifest))

    def test_valid_delivery_and_pristine_acceptance_boundary(self):
        self.assertEqual(validate(self.media, pristine=True), self.manifest)
        self.image.write_bytes(b'user-edited private image')
        validate(self.media)  # manual use may change the disk, never auto-reset it
        with self.assertRaisesRegex(ValueError, 'freshly built'):
            validate(self.media, pristine=True)

    def test_wrong_profiles_and_native_or_diagnostic_apps_are_rejected(self):
        original = json.dumps(self.manifest)
        for change in ('profile', 'storage', 'extra-app', 'filemgr', 'directories', 'source'):
            with self.subTest(change=change):
                self.manifest = json.loads(original)
                if change in ('profile', 'storage'): self.manifest[change] = 'diagnostic'
                elif change == 'extra-app': self.manifest['files']['GBENCH/ABIPROBE.APP'] = 'unused'
                elif change == 'filemgr': self.manifest['sections']['filemgr'] = {}
                elif change == 'directories': self.manifest['directories'].append('UFSTEST')
                else: self.manifest['sections']['bar']['source'] = 'diagnostic-root'
                self.save()
                with self.assertRaises(ValueError): validate(self.media)

    def test_stale_user_card_files_are_preserved_and_rejected(self):
        extra = self.media/'CARD/PERSONAL.TXT'
        extra.write_text('keep this')
        with self.assertRaisesRegex(ValueError, 'unmanaged'):
            check_destination(self.media, self.files, ['GBENCH'])
        self.assertEqual(extra.read_text(), 'keep this')

    def test_symlinked_output_is_never_followed(self):
        outside = self.root/'personal-card'
        outside.mkdir()
        link = self.media/'CARD/LINK'
        link.symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'unmanaged'):
            validate(self.media)
        self.assertEqual(list(outside.iterdir()), [])

    def test_corrupt_staged_payload_and_foreign_image_are_rejected(self):
        name = 'GBENCH/CLOCK.APP'
        (self.media/'CARD'/name).write_bytes(b'wrong')
        with self.assertRaisesRegex(ValueError, 'staged Desktop file differs'):
            validate(self.media)
        (self.media/'CARD'/name).write_bytes(self.files[name])
        self.manifest['image'] = str(self.root/'personal.img'); self.save()
        with self.assertRaisesRegex(ValueError, 'does not belong'):
            validate(self.media)

    def test_invalid_delivery_combination_does_not_build_anything(self):
        with patch('build_cpc_runtime.assemble') as assemble:
            for options in (dict(delivery=True), dict(filemgr=True, delivery=True)):
                with self.assertRaisesRegex(ValueError, 'explicit Desktop'):
                    build(**options)
            assemble.assert_not_called()

    def filemgr_profile(self):
        payload=b'build-matched native File Manager'
        contract=len(payload).to_bytes(2,'little')+zlib.crc32(payload).to_bytes(4,'little')
        for name,data in {'GBENCH/FILEMGR.BIN':payload,'CORE.BIN':b'core'+contract+b'end'}.items():
            (self.media/'CARD'/name).write_bytes(data)
            self.manifest['files'][name]=hashlib.sha256(data).hexdigest()
        self.manifest['profile']='cpc-desktop-m4-v2'
        self.manifest['sections']['filemgr']=dict(staged=True,private_integration=True,
            source='apps/filemgr/main.c',code_bytes=len(payload),
            code_sha256=hashlib.sha256(payload).hexdigest(),contract=contract.hex(),runtime_contract=0x8004)
        self.save()

    def test_native_delivery_requires_matching_private_contract(self):
        self.filemgr_profile()
        self.assertEqual(validate(self.media,pristine=True),self.manifest)
        original=json.dumps(self.manifest)
        for key,value in (('staged',False),('private_integration',False),('source','other.c'),
                          ('code_bytes',1),('code_sha256','wrong'),('contract','000000000000'),
                          ('runtime_contract',0x7FFF),('runtime_contract',0xFFFF)):
            with self.subTest(key=key,value=value):
                self.manifest=json.loads(original)
                self.manifest['sections']['filemgr'][key]=value;self.save()
                with self.assertRaises(ValueError): validate(self.media)

    def test_native_delivery_rejects_changed_kernel_even_with_updated_file_hash(self):
        self.filemgr_profile()
        changed=b'core'+bytes(6)+b'end'
        (self.media/'CARD/CORE.BIN').write_bytes(changed)
        self.manifest['files']['CORE.BIN']=hashlib.sha256(changed).hexdigest();self.save()
        with self.assertRaisesRegex(ValueError,'admission contract'): validate(self.media)

    def settings_profile(self):
        self.filemgr_profile()
        payload=b'build-matched appearance Settings'
        contract=len(payload).to_bytes(2,'little')+zlib.crc32(payload).to_bytes(4,'little')
        core=(self.media/'CARD/CORE.BIN').read_bytes();at=0x8000+len(core)
        for name,data in {'GBENCH/SETTINGS.BIN':payload,'CORE.BIN':core+contract}.items():
            (self.media/'CARD'/name).write_bytes(data)
            self.manifest['files'][name]=hashlib.sha256(data).hexdigest()
        self.manifest['profile']='cpc-desktop-m4-v3'
        self.manifest['sections']['settings']=dict(staged=True,private_integration=True,
            source='apps/settings/main.c',code_bytes=len(payload),code_sha256=hashlib.sha256(payload).hexdigest(),
            contract=contract.hex(),runtime_contract=at,
            settings=['FONT','ICONS','CURSOR','TITLEBAR','GADGETS','BACKDROP'])
        self.save()

    def test_settings_delivery_requires_both_checked_native_contracts(self):
        self.settings_profile()
        self.assertEqual(validate(self.media,pristine=True),self.manifest)
        original=json.dumps(self.manifest)
        for key,value in (('staged',False),('private_integration',False),('source','other.c'),
                          ('settings',['PALETTE']),('code_bytes',1),('code_sha256','wrong'),
                          ('contract','000000000000'),('runtime_contract',0x7FFF)):
            with self.subTest(key=key):
                self.manifest=json.loads(original)
                self.manifest['sections']['settings'][key]=value;self.save()
                with self.assertRaises(ValueError):validate(self.media)
        self.manifest=json.loads(original)
        self.manifest['sections']['filemgr']['contract']='000000000000';self.save()
        with self.assertRaisesRegex(ValueError,'File Manager.*admission contract'):validate(self.media)

    def test_settings_cannot_be_smuggled_into_an_older_delivery_profile(self):
        self.settings_profile()
        self.manifest['profile']='cpc-desktop-m4-v2';self.save()
        with self.assertRaisesRegex(ValueError,'Settings requires'):validate(self.media)

    def test_settings_rejects_unbound_kernel_even_with_correct_staging_hash(self):
        self.settings_profile()
        core=bytearray((self.media/'CARD/CORE.BIN').read_bytes());core[-6:]=bytes(6)
        (self.media/'CARD/CORE.BIN').write_bytes(core)
        self.manifest['files']['CORE.BIN']=hashlib.sha256(core).hexdigest();self.save()
        with self.assertRaisesRegex(ValueError,'Settings.*admission contract'):validate(self.media)

    def test_manual_launcher_uses_only_generated_m4_configuration(self):
        (self.root/'tools').mkdir()
        runner = self.root/'tools/run_cpc.sh'
        shutil.copyfile(ROOT/'tools/run_cpc.sh', runner)
        config = self.media/'1984.conf'; config.write_text('generated M4 config')
        emulator = self.root/'mock 1984'
        emulator.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\n')
        emulator.chmod(0o700)
        env = {**os.environ, 'CPC_EMULATOR': str(emulator)}
        result = subprocess.run(['bash', str(runner), '--exit-after=10'], cwd='/',
                                env=env, text=True, capture_output=True, check=True)
        self.assertEqual(result.stdout.splitlines(), [f'--config={config}', '--6128',
                         '--memory=512', '--autostart=BOOT', '--exit-after=10'])
        self.assertEqual(config.read_text(), 'generated M4 config')
        self.image.unlink()
        result = subprocess.run(['bash', str(runner)], env=env, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('make cpc first', result.stderr)
        self.assertEqual(result.stdout, '')


if __name__ == '__main__':
    unittest.main()
