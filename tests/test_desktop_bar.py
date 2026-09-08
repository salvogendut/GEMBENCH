from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DesktopBarTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which(os.environ.get('CC', 'cc')), 'C compiler required')
    def test_shared_renderer_at_both_native_widths(self):
        with tempfile.TemporaryDirectory(prefix='desktop-bar-') as temp:
            for columns in (80, 128):
                with self.subTest(columns=columns):
                    output = Path(temp) / f'bar-{columns}'
                    subprocess.run([os.environ.get('CC', 'cc'), '-std=c99', '-Wall', '-Wextra', '-Werror',
                                    f'-DTEST_COLUMNS={columns}', str(ROOT/'tests/desktop_bar_test.c'),
                                    '-o', str(output)], check=True)
                    subprocess.run([str(output)], check=True)

    def test_msx_and_cpc_use_identical_fragments(self):
        for name in ('apps/desktop/main.c', 'kernel/kc/cpc_root_bar.c'):
            text = (ROOT/name).read_text()
            for fragment in ('bar_render.inc', 'bar_refresh.inc'):
                # The actual Desktop additionally runs the same refresh policy
                # inside its native clipped-damage callback, preserving caches.
                expected = 2 if name=='apps/desktop/main.c' and fragment=='bar_refresh.inc' else 1
                self.assertEqual(text.count(fragment), expected)
            self.assertNotIn('static void bar_menu(', text)
        for name in ('kernel/gbkern.asm', 'kernel/cpc_runtime_services.asm'):
            self.assertIn('include "core/menu_state.asm"', (ROOT/name).read_text())
        deps = (ROOT/'tools/build_capp.sh').read_text()
        for fragment in ('bar_render.inc', 'bar_refresh.inc'):
            self.assertIn(fragment, deps)


if __name__ == '__main__': unittest.main()
