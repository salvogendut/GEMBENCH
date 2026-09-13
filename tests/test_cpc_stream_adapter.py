"""Execute the real private CPC stream adapter and M4 wire protocol on a Z80.

This is transport qualification, not a claim that CPC launches Notepad yet.
The bus model supplies device replies only, never loader/adapter decisions.
"""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
import sys

ROOT = Path(__file__).resolve().parents[1]
CPU = Path(os.environ.get('MSX_1983_SOURCE', ROOT.parent/'1983'))/'src'
sys.path.insert(0, str(ROOT/'tools'))
from test_cpc_stream_1984 import verify, sha
from test_cpc_foundation_1984 import symbols as lower_symbols


def assemble(stage, overrides=()):
    source = stage/'stream.asm'
    source.write_text(f'''
include "{ROOT}/lib/cpc/production_layout.inc"
CPC_STREAM_STATE equ #1F00
CPC_STREAM_BUFFER equ #1500
CPC_STREAM_PATH equ #2840
CPC_STREAM_PATH_BYTES equ #2888
FAULT_STORAGE_BANK equ 0
FAULT_STORAGE_ROM equ 0
FAULT_STORAGE_COPY equ 0
CPC_FSCTX equ 1
org #8000
include "{ROOT}/lib/cpc/bank.asm"
include "{ROOT}/lib/cpc/m4.asm"
storage_command_fault
storage_header_fault
storage_response_fault
ret
include "{ROOT}/lib/cpc/m4_stream.asm"
irq_handler
push af
push bc
push de
push hl
push ix
push iy
ld a,(#1F20)
inc a
ld (#1F20),a
pop iy
pop ix
pop hl
pop de
pop bc
pop af
ei
reti
save "stream.bin",#8000,$-#8000
''')
    result = subprocess.run(['rasm', str(source), '-s', '-sq', '-o', 'stream',
                             *overrides], cwd=stage, text=True, capture_output=True)
    if result.returncode:
        raise AssertionError(result.stdout+result.stderr)
    return {n: int(v, 16) for n, v in re.findall(
        r'^(\w+) #([0-9A-Fa-f]+)', (stage/'stream.sym').read_text(), re.M)}


class CPCStreamTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('rasm'), 'RASM required')
    def test_real_m4_observer_rejects_damaged_bytes_context_and_cleanup(self):
        # Synthetic observer negatives, not additional emulated hardware runs.
        with tempfile.TemporaryDirectory(prefix='cpc-stream-observer-') as tmp:
            stage = Path(tmp)
            (stage/'stream_fixture.inc').write_text(
                'APP_PRIMARY_SIZE equ 385\nAPP_SECONDARY_SIZE equ 9\n')
            subprocess.run(['rasm', str(ROOT/'debug/cpc_foundation/stream_probe.asm'),
                            '-s', '-sq', '-o', 'stream', f'-I{stage}'],
                           cwd=stage, check=True, capture_output=True)
            sym = lower_symbols(stage/'stream.sym')
            raw = (stage/'STREAM.RAW').read_bytes()
            self.assertLessEqual(sym['probe_end'], 0x9A00)
            app = bytes(i%256 for i in range(394))
            (stage/'accepted.APP').write_bytes(app)
            report = dict(variant='normal', primary=385, secondary=9,
                          app_sha256=sha(app), raw_sha256=sha(raw))
            header, ram = bytearray(256), bytearray(512*1024)
            header[:8] = b'MV - SNA'
            header[0x10], header[0x25], header[0x40], header[0x41], header[0x55] = 3,1,13,5,7
            header[0x6B:0x6D] = (512).to_bytes(2, 'little')
            header[0x21:0x23] = sym['cpc_main_top'].to_bytes(2, 'little')
            ram[sym['cpc_result']:sym['cpc_result']+6] = b'CPS84\1'
            ram[sym['probe_phase']] = 0xA5
            for name, value in (('sched_lock',1), ('ga_shadow',0x8D), ('rom_shadow',7),
                                ('bank_shadow',0xC5), ('probe_opens',1), ('probe_reads',6),
                                ('probe_closes',1), ('cpc_irq_count',1)):
                ram[sym[name]] = value
            for stem in ('main', 'irq', 'tmp'):
                for address in (sym[f'cpc_{stem}_stack']-16, sym[f'cpc_{stem}_top']):
                    ram[address:address+16] = bytes([0xD7])*16
            ram[0x8000:0x8000+len(raw)] = raw
            ram[0xC000:0x10000] = bytes((a>>8)^(a&255) for a in range(0xC000,0x10000))
            ram[0x10000:0x14000] = app[:385]+bytes([0xA7])*(0x4000-385)
            ram[0x14000:0x18000] = app[385:]+bytes([0xA7])*(0x4000-9)
            self.assertEqual(verify(header+ram, stage, report)['reads'], 6)
            for address in (0x10000, 0x10181, 0x14000, 0x14009, 0x8000, 0xC123,
                            sym['probe_opens'], sym['probe_reads'], sym['probe_closes'],
                            sym['probe_phase'], sym['probe_error'], sym['io_busy'],
                            sym['io_fd'], sym['io_offline'], sym['cs_owned'],
                            sym['sched_current'], sym['bank_shadow'], sym['cpc_irq_count'],
                            sym['cpc_main_stack']-1, sym['cpc_irq_top'], sym['cpc_tmp_top']):
                damaged = bytearray(ram); damaged[address] ^= 1
                with self.subTest(address=hex(address)), self.assertRaises(AssertionError):
                    verify(header+damaged, stage, report)
            for address in (0x1B, 0x1C, 0x21, 0x25, 0x40, 0x41, 0x55):
                damaged = bytearray(header); damaged[address] ^= 1
                with self.subTest(header=hex(address)), self.assertRaises(AssertionError):
                    verify(damaged+ram, stage, report)
            (stage/'accepted.APP').write_bytes(app+b'!')
            with self.assertRaisesRegex(AssertionError, 'changed since preparation'):
                verify(header+ram, stage, report)

    @unittest.skipUnless(shutil.which('rasm') and shutil.which('cc') and
                         (CPU/'z80.c').exists(), 'RASM, cc and read-only Z80 core required')
    def test_sequential_wire_reads_faults_and_context_restoration(self):
        with tempfile.TemporaryDirectory(prefix='cpc-stream-') as tmp:
            stage = Path(tmp)
            symbols = assemble(stage)
            names = ('CPC_STREAM_OPEN', 'CPC_STREAM_READ', 'CPC_STREAM_CLOSE',
                     'CPC_STREAM_STATE', 'CPC_STREAM_BUFFER', 'CPC_STREAM_PATH',
                     'CPC_STREAM_PATH_BYTES', 'SCHED_LOCK', 'SCHED_CURRENT',
                     'GA_SHADOW', 'ROM_SHADOW', 'BANK_SHADOW', 'IO_BUSY',
                     'IO_OFFLINE', 'IO_FD', 'STORAGE_GATE', 'IRQ_HANDLER')
            (stage/'stream_fixture.h').write_text('\n'.join(
                f'#define {n} {symbols[n]}' for n in names)+'\n')
            binary = stage/'test'
            subprocess.run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2',
                            '-I', str(CPU), '-I', str(stage),
                            str(ROOT/'tests/cpc_stream_z80.c'), str(CPU/'z80.c'),
                            '-o', str(binary)], check=True)
            subprocess.run([str(binary), str(stage/'stream.bin')], check=True)
            print('private CPC sequential adapter:',
                  symbols['CPC_STREAM_END']-symbols['CPC_STREAM_OPEN'], 'bytes')


if __name__ == '__main__':
    unittest.main()
