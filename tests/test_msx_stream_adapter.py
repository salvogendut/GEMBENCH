"""Checks for the private MSX stream diagnostic; no production-launch claim."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MSXStreamDiagnosticTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('rasm'), 'RASM required')
    def test_real_diagnostic_assembles_and_component_spans_fit_candidates(self):
        with tempfile.TemporaryDirectory(prefix='msx-stream-') as directory:
            stage = Path(directory)
            subprocess.run(['rasm', str(ROOT/'debug/package_stream_msx.asm'),
                            '-s', '-sq', '-o', 'diag'], cwd=stage, check=True, capture_output=True)
            sym = {n: int(v, 16) for n, v in re.findall(r'^(\w+) #([0-9A-Fa-f]+)',
                   (stage/'diag.sym').read_text(), re.M)}
            transaction = sym['PACKAGE_LOAD_END']-sym['PACKAGE_LOAD']
            provider = sym['MSX_PKG_END']-sym['MSX_PKG_OPEN']
            # Component budgets only. They do NOT prove the admission module,
            # bootstrap wiring, storage path resolution or full receiver fit.
            self.assertLessEqual(transaction, 0x400-0x100)
            self.assertLessEqual(provider+3+22, 0xD400-(0xD100+492))
            self.assertLessEqual(sym['DIAG_END'], 0xC000)

    @unittest.skipUnless(shutil.which('tclsh'), 'Tcl required')
    def test_observer_cannot_overwrite_failure_with_pass_after_async_exit(self):
        with tempfile.TemporaryDirectory(prefix='msx-stream-observer-') as directory:
            stage = Path(directory)
            data = stage/'data.bin'
            data.write_bytes(b'probe')
            env = {**os.environ, 'GB_STREAM_PRIMARY': str(data), 'GB_STREAM_SECONDARY': str(data),
                   'GB_STREAM_RESULT': str(stage/'result.txt')}
            for name in ('DOS', 'DOS_RETURN', 'SECONDARY_ENTRY', 'CLEANUP', 'DONE'):
                env['GB_STREAM_'+name] = '32768'
            # openMSX exit schedules shutdown instead of terminating Tcl.
            script = '''
proc debug {args} {}
proc after {args} {}
proc peek {address} {return 0}
rename exit real_exit
proc exit {args} {}
'''+f'source {{{ROOT}/debug/package_stream_openmsx.tcl}}\n'+'''
set stopped [catch {ps_check 0 deliberately_failed; ps_finish PASS}]
if {!$stopped} {real_exit 1}
catch {ps_finish PASS}
real_exit 0
'''
            subprocess.run(['tclsh'], input=script, text=True, env=env, check=True, capture_output=True)
            report = (stage/'result.txt').read_text()
            self.assertIn('STATUS=FAIL deliberately_failed\n', report)
            self.assertNotIn('STATUS=PASS', report)


if __name__ == '__main__':
    unittest.main()
