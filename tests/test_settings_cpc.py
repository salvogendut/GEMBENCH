from pathlib import Path
import os
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from build_cpc_settings import compile_settings, requirements, FILESYSTEM
from build_cpc_runtime import assemble
from build_cpc_runtime import build
from build_cpc_filemgr import bind_runtime


class SettingsCpcTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which(os.environ.get('CC', 'cc')), 'C compiler required')
    def test_config_asset_extensions_are_explicit_and_legacy_is_unchanged(self):
        with tempfile.TemporaryDirectory(prefix='settings-config-') as tmp:
            exe=Path(tmp)/'names'
            for flags in ([],['-DGB_CFG_ASSET_EXTENSIONS']):
                subprocess.run([os.environ.get('CC','cc'),'-std=c99','-Wall','-Wextra','-Werror',*flags,
                                str(ROOT/'tests/settings_config_names_test.c'),str(ROOT/'kernel/kc/kcfg.c'),
                                '-o',str(exe)],check=True)
                subprocess.run([str(exe)],check=True)
    def test_settings_delivery_still_requires_explicit_desktop(self):
        with self.assertRaisesRegex(ValueError, 'explicit Desktop'):
            build(settings=True,delivery=True)

    def test_settings_uses_checked_shared_native_contract(self):
        with tempfile.TemporaryDirectory(prefix='settings-contract-') as tmp:
            work=Path(tmp);app=work/'app';app.mkdir()
            raw=b'\xC3\x03\x40'+bytes(range(30))
            (app/'SETTINGS.native.bin').write_bytes(raw)
            (app/'report.json').write_text(json.dumps(dict(code_bytes=len(raw),code_sha256=hashlib.sha256(raw).hexdigest())))
            kernel=b'\xAA'*10+bytes(6)+b'\xBB'*10
            (work/'CORE.RAW').write_bytes(kernel)
            sym=dict(cpc_settings_profile=1,cpc_settings_contract=0x800A,cpc_kernel_begin=0x8000)
            args=dict(name='settings',title='Settings',filename='SETTINGS.native.bin')
            with self.assertRaisesRegex(AssertionError,'private runtime profile'):
                bind_runtime(work,app,{**sym,'cpc_settings_profile':0},**args)
            report=bind_runtime(work,app,sym,**args)
            self.assertEqual((work/'CORE.RAW').read_bytes(),kernel[:10]+bytes.fromhex(report['contract'])+kernel[16:])
            self.assertEqual(bind_runtime(work,app,sym,**args),report)
            for payload in (b'',raw[:-1],raw[:-1]+b'X',raw.ljust(0x3801,b'\0')):
                (app/'SETTINGS.native.bin').write_bytes(payload)
                with self.assertRaisesRegex(AssertionError,'differs from checked link'):
                    bind_runtime(work,app,sym,**args)

    @unittest.skipUnless(shutil.which(os.environ.get('CC', 'cc')), 'C compiler required')
    def test_shared_settings_with_owned_cpc_provider(self):
        with tempfile.TemporaryDirectory(prefix='settings-cpc-host-') as tmp:
            exe = Path(tmp)/'settings'
            subprocess.run([os.environ.get('CC', 'cc'), '-std=c99', '-Wall', '-Wextra',
                            '-Werror', '-Wno-unused-function', '-Wno-unused-variable',
                            '-Wno-unused-but-set-variable', '-I', str(ROOT/'lib/gb'),
                            '-I', str(ROOT/'include/gembench'),
                            f'-DGB_SETTINGS_BINDINGS="{ROOT/"tests/settings_cpc_bindings.h"}"',
                            str(ROOT/'tests/settings_cpc_test.c'),
                            str(ROOT/'lib/gb/gbselect.c'), '-o', str(exe)], check=True)
            subprocess.run([str(exe)], check=True)

    def test_native_dependency_review_fails_closed(self):
        obj = ''.join('S _'+name+' Ref00000000\n' for name in
                      ('settings_commit', 'settings_begin', 'gb_wm_managed_kind'))
        self.assertEqual(len(requirements(obj)), 3)
        for name in ('gb_fs_save', 'gb_drag_window', 'gb_reload', 'gb_wm_damage',
                     'gb_restore_parent', 'gb_copybuf', 'settings_run_saver', 'gb_new_call'):
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'unreviewed'):
                requirements(obj+'S _'+name+' Ref00000000\n')
        with self.assertRaisesRegex(ValueError, 'wrong Settings'):
            requirements('S _gb_fill Ref00000000\n')


@unittest.skipUnless(all(shutil.which(os.environ.get(k, k.lower())) for k in ('RASM', 'SDCC')),
                     'RASM/SDCC required')
class SettingsCpcLayoutTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='settings-cpc-link-')
        cls.addClassCleanup(cls.temp.cleanup)
        cls.work = Path(cls.temp.name)
        cls.runtime = cls.work/'runtime'
        cls.sym = assemble(cls.runtime)

    def test_actual_link_and_boundaries_without_admission(self):
        kernel = (self.runtime/'CORE.RAW').read_bytes()
        report = compile_settings(self.work/'app', self.runtime, self.sym)
        self.assertFalse(report['staged'])
        self.assertFalse(report['runtime_qualified'])
        self.assertLessEqual(report['code_bytes'], report['code_budget'])
        self.assertLessEqual(report['data_bytes'], report['data_budget'])
        self.assertEqual(report['snapshot_base'], 0x7F00)
        self.assertEqual(len(report['settings']), 6)
        self.assertEqual(set(report['owned_filesystem_calls']), FILESYSTEM)
        self.assertEqual(report['icon_header_read_bytes'], 16)
        self.assertEqual(report['picker_max_text_bytes'], 182)
        self.assertIn('_settings_commit', report['main_requirements'])
        self.assertIn('_gb_wm_managed_kind', report['main_requirements'])
        self.assertEqual((self.runtime/'CORE.RAW').read_bytes(), kernel)
        for pattern in ('*.APP', '*.IMG', '*.DSK'):
            self.assertFalse(list(self.work.rglob(pattern)))

    def test_native_layout_and_popup_capacity_drift_rejected(self):
        for name in ('gb_msg', 'poll_mx', 'poll_my', 'poll_flags', 'mw_rect', 'cpc_app_limit'):
            bad = {**self.sym, name: self.sym[name]+1}
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'layout changed'):
                compile_settings(self.work/'bad', self.runtime, bad)
        bad = {**self.sym, 'cpc_ui_request_end': self.sym['cpc_ui_text']+181}
        with self.assertRaisesRegex(ValueError, 'UI capacity'):
            compile_settings(self.work/'bad', self.runtime, bad)


if __name__ == '__main__':
    unittest.main()
