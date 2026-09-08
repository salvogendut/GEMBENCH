from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from audit_cpc_settings import audit, inspect_object


class SettingsPlatformTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which(os.environ.get('CC', 'cc')), 'C compiler required')
    def test_actual_settings_and_widgets_with_relocated_state(self):
        with tempfile.TemporaryDirectory(prefix='settings-platform-') as tmp:
            exe = Path(tmp)/'settings'
            subprocess.run([os.environ.get('CC', 'cc'), '-std=c99', '-Wall', '-Wextra',
                            '-Werror', '-Wno-unused-function', '-Wno-unused-variable',
                            '-ffunction-sections', '-fdata-sections', '-Wl,--gc-sections',
                            '-I', str(ROOT/'lib/gb'), '-I', str(ROOT/'apps/settings'),
                            str(ROOT/'tests/settings_platform_test.c'),
                            *(str(ROOT/'lib/gb'/name) for name in
                              ('gbselect.c', 'gbstepper.c', 'gbactions.c')),
                            '-o', str(exe)], check=True)
            subprocess.run([str(exe)], check=True)

    @unittest.skipUnless(shutil.which(os.environ.get('SDCC', 'sdcc')), 'SDCC required')
    def test_cpc_audit_and_provider_required(self):
        with tempfile.TemporaryDirectory(prefix='settings-audit-') as tmp:
            report = audit(tmp)
            self.assertFalse(report['executable'])
            self.assertGreater(report['legacy_data_overrun_bytes'], 0)
            self.assertIn('_gb_fs_save', report['requirements']['native_filesystem_binding_required'])
            self.assertIn('_settings_run_saver', report['requirements']['platform_calls_required'])
            self.assertEqual(list(Path(tmp).glob('*.APP')), [])
            self.assertEqual(list(Path(tmp).glob('*.ihx')), [])
            result = subprocess.run([os.environ.get('SDCC', 'sdcc'), '-mz80',
                                     '-DGB_CPC_RESTART', '-I', str(ROOT/'lib/gb'),
                                     '-E', str(ROOT/'apps/settings/main.c')],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('requires an explicit platform provider', result.stderr)

    def test_audit_rejects_unreviewed_dependency_or_absolute_access(self):
        obj = 'S _gb_fill Ref00000000\nA _CODE size 10 flags 0\nA _DATA size 2 flags 0\n'
        self.assertEqual(inspect_object(obj, 'call _gb_fill')[0]['_CODE'], 16)
        with self.assertRaisesRegex(ValueError, 'unreviewed'):
            inspect_object(obj+'S _gb_new_dependency Ref00000000\n', '')
        for instruction in ('call 0xBC32', 'jp #0x80AE', 'ld a,(0x1290)', 'ld (4668),hl'):
            with self.subTest(instruction=instruction), self.assertRaisesRegex(ValueError, 'absolute'):
                inspect_object(obj, instruction)

    def test_build_cache_tracks_native_profile(self):
        source = (ROOT/'tools/build_capp.sh').read_text()
        for name in ('legacy.h', 'ink_legacy.inc', 'saver_legacy.inc'):
            self.assertIn('$APP/platform/'+name, source)


if __name__ == '__main__':
    unittest.main()
