"""Stack-boundary model for native/compile-once trampoline safety (#79).

This is not a Z80 emulator. M4 Settings and stacking runs exercise generated
objects on 1984; this model checks every IRQ boundary, including the rare gap
which the instruction trace caught in the original POP HL / DEC SP wrapper.
"""
from pathlib import Path
import re
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from gblib_subset import generate, main


class NativeStackArgsTests(unittest.TestCase):
    def generated(self, safe):
        return generate(ROOT/'lib/gb/gblib.s',
                        [ROOT/'apps/filemgr/platform/cpc.symbols'],interrupt_safe=safe)

    def test_all_four_wrappers_opt_in_without_changing_legacy(self):
        legacy = self.generated(False)
        safe = self.generated(True)
        self.assertEqual(legacy, generate(ROOT/'lib/gb/gblib.s',
                                         [ROOT/'apps/filemgr/platform/cpc.symbols']))
        pattern = r'(?m)^        pop\s+hl[^\n]*\n        dec\s+sp[^\n]*\n'
        self.assertEqual(len(re.findall(pattern, legacy)), 4)
        self.assertNotRegex(safe, pattern)
        self.assertEqual(safe.count('interrupt-safe one-byte argument'), 4)
        # No unrelated ABI entry is rewritten.
        for name in ('gb_text', 'gb_wm_close'):
            pattern = r'(?ms)^_'+name+r':.*?(?=^_gb_|\Z)'
            self.assertEqual(re.search(pattern, safe)[0], re.search(pattern, legacy)[0])

    @staticmethod
    def model(ops, irq_boundary, caller=b'\xA7\x51\x12\x34', irq_pc=b'\x0D\x73'):
        mem = bytearray(32)
        mem[8:13] = b'\x55'+caller  # argument, live return address or caller data
        sp, hl = 8, 0x1234
        for boundary in range(len(ops)+1):
            if boundary == irq_boundary:
                # IM1 saves PC below SP; its handler preserves registers and
                # returns. Popping PC does not restore the overwritten bytes.
                mem[sp-2:sp] = irq_pc
            if boundary == len(ops): break
            op = ops[boundary]
            if op == 'pop hl': hl=int.from_bytes(mem[sp:sp+2],'little');sp+=2
            elif op == 'dec sp': sp-=1
            elif op == 'ld hl, #0': hl=0
            elif op == 'add hl, sp': hl=(hl+sp)&65535
            elif op == 'ld l, (hl)': hl=(hl&0xFF00)|mem[hl]
            elif op == 'inc sp': sp+=1
            else: raise AssertionError('unmodelled stack operation: '+op)
        return sp, hl&255, mem[9:13]

    def test_generated_read_survives_irq_at_every_instruction_boundary(self):
        block = self.generated(True).split('_gb_icon:\n')[1].split('_gb_icon_half:')[0]
        read = block[block.index('        ld      hl, #0'):block.index('        ld      c, l')]
        ops = [re.sub(r'\s+', ' ', line.split(';')[0].strip()) for line in read.splitlines()]
        self.assertEqual(len(ops), 4)
        for boundary in range(len(ops)+1):
            with self.subTest(boundary=boundary):
                self.assertEqual(self.model(ops,boundary), (9,0x55,b'\xA7\x51\x12\x34'))

    def test_model_reproduces_observed_legacy_return_address_corruption(self):
        ops = ['pop hl','dec sp']
        self.assertEqual(self.model(ops,0), (9,0x55,b'\xA7\x51\x12\x34'))
        self.assertEqual(self.model(ops,1), (9,0x55,b'\x73\x51\x12\x34'))

    def test_universal_builder_always_uses_the_same_safe_sdk(self):
        source = (ROOT/'tools/build_uapp.sh').read_text()
        self.assertIn('python3 tools/gblib_subset.py --interrupt-safe lib/gb/gblib.s', source)
        manifests = [ROOT/'lib/gb/gblib_universal.symbols', ROOT/'apps/uclock/gblib.symbols']
        with tempfile.TemporaryDirectory(prefix='universal-stack-') as tmp:
            output = Path(tmp)/'gblib.s'
            main(['gblib_subset.py', '--interrupt-safe', str(ROOT/'lib/gb/gblib.s'),
                  str(output), *map(str, manifests)])
            safe = output.read_text()
            self.assertEqual(safe, generate(ROOT/'lib/gb/gblib.s', manifests, interrupt_safe=True))
            self.assertNotRegex(safe, r'pop\s+hl[^\n]*\n\s*dec\s+sp')
            main(['gblib_subset.py', str(ROOT/'lib/gb/gblib.s'), str(output), *map(str, manifests)])
            self.assertEqual(output.read_text(), generate(ROOT/'lib/gb/gblib.s', manifests))

    def test_clock_saved_column_is_live_after_the_one_byte_argument(self):
        # SDCC draw_seconds saves BC (C=X) across gb_fill. The old wrapper's
        # overshoot lets IM1 replace C with the high byte of its PC, potentially
        # >=80. GB_PARAMS then correctly rejects that out-of-screen text call,
        # after the preceding fill has already erased the visible digits.
        caller = bytes((43,53,0x12,0x34))  # saved C=X and B=seconds
        irq_pc = b'\x73\x58'  # after POP HL in the observed Clock gb_fill at 0x5869
        for boundary in range(5):
            _, _, saved = self.model(['ld hl, #0','add hl, sp','ld l, (hl)','inc sp'],
                                     boundary, caller, irq_pc)
            self.assertEqual(saved, caller)
        old = self.model(['pop hl','dec sp'],1,caller,irq_pc)[2]
        self.assertEqual(old, bytes((0x58,53,0x12,0x34)))
        self.assertGreaterEqual(old[0],80)  # text validation rejects, after fill


if __name__ == '__main__': unittest.main()
