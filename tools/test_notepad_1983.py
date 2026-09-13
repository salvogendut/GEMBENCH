#!/usr/bin/env python3
"""Real Desk/keyboard/file-chooser workflow for the private two-bank Notepad.

Read-only debugger observations; input travels through the keyboard matrix.
Only a fresh copy of the supplied hard-disk image is written by the guest.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

from test_msx_stability_1983 import Driver, constants


class NotepadDriver(Driver):
    def move(self, x, y, held=0):
        # Ctrl+arrows remains available even when a mouse is configured, whereas
        # joystick direction bits would be interpreted as mouse nibble replies.
        end = self.frame + 6000
        while self.frame < end:
            px, py = self.read(self.layout['POLL_MX'], 2)
            if abs(px-x) <= 1 and abs(py-y) <= 3:
                self.call(f'keys 6 2 8 {held}'); self.frames(8)
                px, py = self.read(self.layout['POLL_MX'], 2)
                if abs(px-x) <= 1 and abs(py-y) <= 3:
                    return
                continue
            mask = 128 if px < x-1 else 16 if px > x+1 else 64 if py < y-3 else 32
            self.call(f'keys 6 2 8 {mask | held}'); self.frames(1)
        raise AssertionError(f'keyboard pointer timeout: {px},{py} -> {x},{y}')

    def click(self, x, y):
        self.move(x, y)
        # A real joystick trigger does not also enqueue a typed Space in BIOS.
        # Keep keyboard-pointer failures as separate evidence, not text input.
        self.call('joystick 0 16')
        for _ in range(150):
            self.frames(1)
            if self.value('POLL_FLAGS') & 4:
                break
        else:
            self.call('joystick 0 0')
            raise AssertionError('joystick click not polled within three seconds')
        self.call('joystick 0 0'); self.key(); self.frames(60)

    def application(self, symbol, size=1):
        bank = self.entry(1)[0]
        return self.call(f'ram {bank*0x4000+self.symbols[symbol]-0x4000} {size}')

    def editor(self):
        return self.application('_editor', 19)

    def mode(self):
        return self.application('_mode')[0]

    def type_keys(self, keys):
        for row, mask in keys:
            self.key(row, mask); self.frames(6)
            self.key(row, 0); self.frames(18)
        self.frames(80)

    def launch(self):
        self.click(11, 4); self.click(12, 14)
        self.wait(lambda: self.value('WM_NWIN') == 2 and self.value('WM_FOCUS') == 1,
                  'Notepad launch/focus')
        self.frames(100)
        self.expect(self.mode() == 0 and self.editor()[:2] == [0, 0], 'fresh editor')
        self.border(1)

    def menu(self, row):
        self.click(11, 4); self.click(12, 14+row*10)

    def picker_ready(self):
        return self.mode() == 1 and self.application('_scratch', 9)[8] == 5

    def load_file(self, name=b'SAVED   TXT', result=0):
        self.menu(1)
        for _ in range(32):
            self.wait(self.picker_ready, 'file chooser ready')
            picker = self.application('_scratch', 161)
            for row in range(picker[10]):
                if bytes(picker[89+row*12:100+row*12]) == name:
                    self.click(10, 48+row*10)
                    self.wait(lambda: self.mode() == result, 'document load outcome')
                    self.frames(100)  # chooser-click debounce, not edited text input
                    return
            self.expect(picker[11], 'saved file is present in chooser')
            self.click(22, 112)
        raise AssertionError('chooser page bound exceeded')

    def exercise(self, args):
        self.symbols = {n: int(v, 16) for n, v in re.findall(
            r'^DEF (\w+) (0x[0-9A-Fa-f]+)', args.symbols.read_text(), re.M)}
        glue = constants(args.worktree/'lib/msx/glue.inc')
        self.wait(lambda: self.read(0xCF00, 2) == [48, 6] and self.value('WM_NWIN') == 1,
                  'desktop boot', 6000)
        self.bank = self.frames(100)['p0']
        self.expect(self.read(0xCF05)[0] == args.mode, 'requested Screen mode')
        before = self.read(glue['MSX_PAGE_STATE'], 32)
        free = self.read(glue['MSX_PAGE_FREE'])
        self.launch()
        self.type_keys([(2, 64), (2, 128), (3, 1), (7, 128)])
        self.expect(self.editor()[:2] == [4, 0] and self.editor()[13] == 1, 'typed abc newline')
        pointer = self.read(self.layout['POLL_MX'], 2)
        for key, index in [((8, 32), 0), ((8, 128), 1), ((8, 64), 4),
                           ((8, 16), 3), ((8, 128), 4)]:
            self.type_keys([key])
            view = self.editor()
            self.expect(view[2]+256*view[3] == index, 'arrow caret index')
            self.expect(view[:2] == [4, 0] and view[13] == 1, 'arrow leaves document unchanged')
        self.type_keys([(8, 1)])
        self.expect(self.editor()[:2] == [5, 0], 'Space types instead of clicking')
        self.type_keys([(7, 32)])
        self.expect(self.editor()[:4] == [4, 0, 4, 0], 'backspace removes typed Space')
        self.expect(self.read(self.layout['POLL_MX'], 2) == pointer, 'typing and arrows do not move pointer')
        self.call(f"ppm {args.output.resolve()/'editing.ppm'}")
        saved_view=self.editor()
        self.focus_desktop()
        pointer=self.read(self.layout['POLL_MX'],2)
        self.key(8,128);self.frames(6);self.key();self.frames(20)
        self.expect(self.read(self.layout['POLL_MX'],2)[0]>pointer[0],
                    'unfocused editor restores ordinary keyboard pointer')
        self.expect(self.editor()==saved_view,'background editor ignores pointer arrows')
        self.click(30,20)
        self.wait(lambda:self.value('WM_FOCUS')==1,'return focus to editor')
        self.menu(3)
        self.wait(self.picker_ready, 'save chooser')
        self.type_keys([(5, 1), (2, 64), (5, 8), (3, 4), (3, 2),
                        (2, 8), (5, 2), (5, 32), (5, 2), (7, 128)])
        self.wait(lambda: self.mode() == 9, 'explicit overwrite confirmation')
        self.type_keys([(5, 1)])
        self.wait(lambda: self.mode() == 0, 'save completed')
        self.expect(self.editor()[13] == 0, 'saved document clean')
        self.close(1, 1)
        self.launch(); self.load_file()
        self.expect(self.editor()[:2] == [4, 0] and self.editor()[13] == 0,
                    'saved document reopened in fresh owner')
        # A real edit, then dirty close / Cancel / close / Discard.
        self.type_keys([(3, 2)])
        self.click(4, 18)
        self.expect(self.mode() == 2 and self.value('WM_NWIN') == 2, 'dirty close confirmation')
        self.type_keys([(7, 4)])  # Escape
        self.expect(self.mode() == 0 and self.editor()[13] == 1, 'cancel retains dirty document')
        self.click(4, 18); self.type_keys([(3, 2)])
        self.wait(lambda: self.value('WM_NWIN') == 1, 'discard closes')
        if args.boundary:
            self.launch(); self.load_file(b'MAXIMUM TXT')
            self.expect(self.editor()[:2] == [0, 16] and self.editor()[13] == 0, 'full 4096-byte load')
            self.type_keys([(5, 32)])  # X cannot exceed capacity.
            self.expect(self.editor()[:2] == [0, 16] and self.editor()[13] == 0, 'capacity retains full document')
            self.menu(3); self.wait(self.picker_ready, 'boundary save chooser')
            # FULL.TXT; file chooser starts with an empty edit field.
            self.type_keys([(3, 8), (5, 4), (4, 2), (4, 2), (2, 8),
                            (5, 2), (5, 32), (5, 2), (7, 128)])
            self.wait(lambda: self.mode() == 9, 'boundary save confirmation')
            self.type_keys([(5, 1)])
            self.wait(lambda: self.mode() == 0, 'full save completed')
            self.load_file(b'TOOLARGETXT', result=7)
            self.expect(self.editor()[:2] == [0, 16] and self.editor()[13] == 0,
                        '4097-byte input rejected with old document retained')
            self.type_keys([(7, 128)])
            self.expect(self.mode() == 0, 'load error acknowledged')
            self.close(1, 1)
        self.expect(self.read(glue['MSX_PAGE_STATE'], 32) == before and
                    self.read(glue['MSX_PAGE_FREE']) == free, 'exact page-pool reclamation')
        self.expect(self.read(0x2180, 64) == [0]*64 and self.read(0x21C0) == [0], 'seals reclaimed')
        self.expect(self.value('SCHED_FAULT') == 0, 'scheduler guard')
        return dict(status='PASS', checks=self.checks, frames=self.frame,
                    boundary=args.boundary, click_input='joystick port 1 trigger',
                    stack_max=self.value('SCHED_STACK_MAX'),
                    final_windows=self.value('WM_NWIN'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('bridge', 'omega', 'sunrise', 'image', 'worktree', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--mode', type=int, choices=(6, 7), required=True)
    parser.add_argument('--bios', type=Path)
    parser.add_argument('--subrom', type=Path)
    parser.add_argument('--boundary', action='store_true', help='also round-trip 4096 bytes and reject 4097')
    args = parser.parse_args()
    if bool(args.bios) != bool(args.subrom): parser.error('supply both BIOS and subROM')
    if args.output.exists(): parser.error('output exists; choose a fresh evidence directory')
    args.symbols = args.image.parent/'probe.noi'
    app = (args.image.parent/'probe.APP').read_bytes()
    if subprocess.check_output(['mtype', '-i', str(args.image)+'@@16384', '::/GBENCH/CLOCK.APP']) != app:
        parser.error('image and staged APP differ')
    original = args.image
    original_hash = hashlib.sha256(original.read_bytes()).hexdigest()
    args.output.mkdir(parents=True)
    args.image = args.output/'filesystem.img'
    shutil.copyfile(original, args.image)
    full = (b'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ\n'*111)[:4096]
    if args.boundary:
        for name, data in [('MAXIMUM.TXT', full), ('TOOLARGE.TXT', full+b'!')]:
            fixture = args.output/name
            fixture.write_bytes(data)
            subprocess.run(['mcopy', '-o', '-i', str(args.image)+'@@16384', str(fixture), '::/'+name], check=True)
    args.short_desk_stress = False
    driver = None
    try:
        with (args.output/'bridge.log').open('w') as log:
            driver = NotepadDriver(args, log)
            report = driver.exercise(args)
    except Exception as error:
        report = dict(status='FAIL', error=str(error), frame=driver.frame if driver else 0)
        if driver:
            try:
                report.update(machine=driver.frames(0), windows=driver.value('WM_NWIN'),
                              editor=driver.editor(), editor_mode=driver.mode())
            except Exception as observation_error:
                report['observation_error'] = str(observation_error)
    finally:
        if driver:
            try: driver.call(f"ppm {args.output.resolve()/'screen.ppm'}")
            finally: driver.process.terminate(); driver.process.wait(timeout=10)
    if report['status'] == 'PASS':
        data = subprocess.check_output(['mtype', '-i', str(args.image)+'@@16384', '::/SAVED.TXT'])
        if data != b'abc\n': report.update(status='FAIL', error=f'disk readback differs: {data!r}')
        if args.boundary:
            data = subprocess.check_output(['mtype', '-i', str(args.image)+'@@16384', '::/FULL.TXT'])
            if data != full: report.update(status='FAIL', error='4096-byte saved file differs')
    unchanged = hashlib.sha256(original.read_bytes()).hexdigest() == original_hash
    if not unchanged: report.update(status='FAIL', error='source image changed')
    report.update(mode=args.mode, app_sha256=hashlib.sha256(app).hexdigest(),
                  source_image_sha256=original_hash, source_image_unchanged=unchanged,
                  bridge_sha256=hashlib.sha256(args.bridge.read_bytes()).hexdigest())
    (args.output/'result.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report, indent=2))
    return 0 if report['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
