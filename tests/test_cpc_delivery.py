import importlib.util
from contextlib import redirect_stdout
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
spec = importlib.util.spec_from_file_location('delivery_runner', ROOT/'tools/test_cpc_delivery_1984.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
from cpc_runtime_filemgr import popup_ready


class DeliveryTests(unittest.TestCase):
    def test_modal_request_during_module_load_is_not_a_drawn_popup(self):
        sym=dict(cpc_ui_status=0,cpc_ui_request=4,cpc_ui_text=16)
        ram=bytearray(64);ram[7]=2;ram[16:20]=b'A\0B\0'
        popup=dict(labels=('A','B'))
        for status in (1,2,3):
            ram[0]=status
            self.assertFalse(popup_ready(ram,sym,popup))
        ram[0]=0
        self.assertTrue(popup_ready(ram,sym,popup))
        ram[16]=ord('C')
        self.assertFalse(popup_ready(ram,sym,popup))

    def test_suite_has_unique_real_delivery_cases(self):
        cases = dict(runner.cases())
        self.assertEqual(len(cases), 20)
        self.assertEqual(len(cases), len(runner.cases()))
        self.assertEqual(cases['lifecycle'], ['--filemgr'])
        self.assertEqual(cases['services'], ['--filemgr-scenario', 'services'])
        self.assertEqual(cases['minute-cadence'], ['--filemgr-scenario', 'minute-cadence'])
        self.assertEqual(sum(name.startswith('filemgr-') for name in cases), 6)
        self.assertEqual(sum(name.startswith('root-') for name in cases), 6)
        self.assertNotIn('windows', cases)  # diagnostic-only probe applications

    def test_failure_is_retained_and_child_never_builds(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(runner.subprocess, 'run') as execute:
            execute.return_value = SimpleNamespace(returncode=7)
            output = io.StringIO()
            with redirect_stdout(output):
                result = runner.run_case(('cadence', ['--filemgr-scenario', 'cadence']),
                                         Path('/tmp/test-emulator'), Path(temp))
            self.assertIn('FAIL cadence', output.getvalue())
            self.assertEqual(result['exit_code'], 7)
            self.assertTrue(Path(result['log']).exists())
            command = execute.call_args.args[0]
            self.assertIn('--desktop-delivery', command)
            self.assertIn('--skip-build', command)
            self.assertNotIn('--seed-image', command)


if __name__ == '__main__':
    unittest.main()
