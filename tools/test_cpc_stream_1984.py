#!/usr/bin/env python3
"""Private #84 single-open transport qualification, M4 only, no APP execution.

Use --app with the accepted MSX NOTEPAD.APP. Every preparation creates a new
image under build/notepad-84/evidence; no delivery media or source is changed.
--prepare-only supports distrobox builds followed by a host --stage run.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import queue
import subprocess
import tempfile
import threading
import time

from build_cpc_foundation import headed
from embed_app_icon import parse_manifest
from test_cpc_foundation_1984 import snapshot, symbols

ROOT = Path(__file__).resolve().parents[1]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def prepare(app, variant):
    data = app.read_bytes()
    manifest = parse_manifest(data)
    if manifest['version'] != 4 or len(manifest['segments']) != 2:
        raise ValueError('expected the accepted two-segment universal APP')
    primary = manifest['segments'][0]['stored_length']
    secondary = manifest['segments'][1]['stored_length']
    if primary+secondary != len(data):
        raise ValueError('expected canonical contiguous two-bank package')
    if (manifest['segments'][0]['offset'], manifest['segments'][1]['offset']) != (0, primary):
        raise ValueError('expected primary then secondary package ordering')
    evidence = ROOT/'build/notepad-84/evidence'
    evidence.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix=f'cpc-stream-{variant}-', dir=evidence))
    card = stage/'card'
    (card/'GBENCH').mkdir(parents=True)
    (stage/'accepted.APP').write_bytes(data)
    (stage/'stream_fixture.inc').write_text(
        f'APP_PRIMARY_SIZE equ {primary}\nAPP_SECONDARY_SIZE equ {secondary}\n')
    subprocess.run(['rasm', str(ROOT/'debug/cpc_foundation/stream_probe.asm'),
                    '-s', '-sq', '-o', 'stream', f'-I{stage}'], cwd=stage, check=True)
    raw = (stage/'STREAM.RAW').read_bytes()
    (card/'FOUND.BIN').write_bytes(headed(raw, 0x8000))
    (card/'BOOT.BAS').write_bytes(b'10 MEMORY &7FFF\r\n20 LOAD "FOUND.BIN",&8000\r\n30 CALL &8000\r\n')
    if variant != 'missing':
        payload = data[:-1] if variant == 'short' else data+b'!' if variant == 'extra' else data
        (card/'GBENCH/NOTEPAD.APP').write_bytes(payload)
    image = stage/'STREAM.IMG'
    with image.open('wb') as stream:
        stream.truncate(32*1024*1024)
    subprocess.run(['sfdisk', '-q', str(image)], input='label: dos\nstart=32, type=06\n',
                   text=True, check=True, stdout=subprocess.DEVNULL)
    subprocess.run(['mkfs.fat', '--invariant', '-F16', '--offset', '32', '-n',
                    'CPCSTREAM', str(image)], check=True)
    subprocess.run(['mcopy', '-s', '-i', str(image)+'@@16384', str(card/'BOOT.BAS'),
                    str(card/'FOUND.BIN'), str(card/'GBENCH'), '::/'], check=True,
                   env={**os.environ, 'MTOOLS_SKIP_CHECK': '1'})
    (stage/'1984.conf').write_text('[machine]\nmodel=6128\nmemory=512\n\n'
        '[hardware]\nmx4=true\nm4=true\nm4_path=\n'+f'm4_image={image}\n'
        'albireo=false\nsymbiface_ide=false\n\n[advanced]\ndebug=true\n')
    report = dict(variant=variant, app_sha256=sha(data), primary=primary, secondary=secondary,
                  image_sha256=sha(image.read_bytes()), raw_sha256=sha(raw),
                  source_sha256={name: sha((ROOT/name).read_bytes()) for name in (
                      'debug/cpc_foundation/stream_probe.asm', 'lib/cpc/m4_stream.asm',
                      'lib/cpc/m4.asm', 'lib/cpc/bank.asm', 'lib/cpc/irq.asm')})
    (stage/'build.json').write_text(json.dumps(report, indent=2)+'\n')
    print('Prepared '+str(stage), flush=True)
    return stage


def verify(data, stage, report):
    header, ram = snapshot(data)
    sym = symbols(stage/'stream.sym')
    def word(name):
        at = sym[name]
        return int.from_bytes(ram[at:at+2], 'little')
    if len(ram) != 512*1024 or ram[sym['cpc_result']:sym['cpc_result']+6] != b'CPS84\1':
        raise AssertionError('wrong memory or diagnostic signature')
    variant = report['variant']
    phase, error = (0xA5, 0) if variant == 'normal' else (0xFF, {'short': 8, 'extra': 9, 'missing': 3}[variant])
    if (ram[sym['probe_phase']], ram[sym['probe_error']]) != (phase, error):
        raise AssertionError(f"probe phase/error {ram[sym['probe_phase']]:02x}/{ram[sym['probe_error']]}")
    if any(ram[sym[n]] for n in ('io_busy', 'io_fd', 'io_offline', 'cs_owned', 'sched_current')):
        raise AssertionError('handle, lock or offline state leaked')
    if not ram[sym['sched_lock']] or ram[sym['ga_shadow']] != 0x8D or ram[sym['rom_shadow']] != 7:
        raise AssertionError('transaction context not restored')
    if header[0x1B:0x1D] != b'\0\0' or header[0x25] != 1 or header[0x40] != 0x0D or header[0x55] != 7:
        raise AssertionError('hardware IFF/IM/ROM state differs from shadow')
    if int.from_bytes(header[0x21:0x23], 'little') != sym['cpc_main_top']:
        raise AssertionError('unbalanced main stack')
    for stem in ('main', 'irq', 'tmp'):
        for address in (sym[f'cpc_{stem}_stack']-16, sym[f'cpc_{stem}_top']):
            if ram[address:address+16] != bytes([0xD7])*16:
                raise AssertionError(stem+' stack guard')
    raw = (stage/'STREAM.RAW').read_bytes()
    if sha(raw) != report['raw_sha256'] or sha((stage/'accepted.APP').read_bytes()) != report['app_sha256']:
        raise AssertionError('diagnostic or accepted APP changed since preparation')
    if ram[0x8000:0x8000+len(raw)] != raw:
        raise AssertionError('diagnostic code changed')
    if ram[0xC000:0x10000] != bytes((a>>8)^(a&255) for a in range(0xC000,0x10000)):
        raise AssertionError('framebuffer touched by storage')
    opens, reads, closes = (word('probe_'+name) for name in ('opens', 'reads', 'closes'))
    if opens != 1 or closes != (0 if variant=='missing' else 1):
        raise AssertionError('not exactly one open/close transaction')
    app = (stage/'accepted.APP').read_bytes()
    primary, secondary = report['primary'], report['secondary']
    wanted_primary, wanted_secondary = app[:primary], app[primary:]
    wanted_reads = (primary+127)//128+(secondary+127)//128+1
    if variant == 'missing':
        wanted_primary = wanted_secondary = b''
        wanted_reads = 0
    elif variant == 'short':
        # The probe copies only complete requested chunks. Its last partial
        # secondary read must not be copied into the bank, even on failure.
        wanted_secondary = wanted_secondary[:((secondary-1)//512)*512]
        wanted_reads -= 1                  # no EOF probe after truncated segment
    if reads != wanted_reads:
        raise AssertionError('unexpected READ2 count')
    for physical, expected in ((0x10000, wanted_primary), (0x14000, wanted_secondary)):
        page = ram[physical:physical+0x4000]
        if page != expected+bytes([0xA7])*(0x4000-len(expected)):
            raise AssertionError('segment bytes or untouched page tail differ')
    if variant == 'normal':
        if not word('cpc_irq_count'):
            raise AssertionError('no real fixed-time IRQ during transaction')
    expected_bank = 0xC4 if variant == 'missing' else 0xC5
    if ram[sym['bank_shadow']] != expected_bank or header[0x41] != expected_bank-0xC0:
        raise AssertionError('aperture changed unexpectedly')
    return dict(opens=opens, reads=reads, closes=closes, irq_ticks=word('cpc_irq_count'),
                primary_bytes=report['primary'], secondary_bytes=report['secondary'],
                app_sha256=report['app_sha256'], variant=variant)


def run(stage, emulator):
    report = json.loads((stage/'build.json').read_text())
    # A prepared image is read-only to this test; no write commands are issued.
    image = stage/'STREAM.IMG'
    if sha(image.read_bytes()) != report['image_sha256']:
        raise AssertionError('prepared image changed; prepare a fresh diagnostic')
    pilot = stage/'pilot'
    process = subprocess.Popen([str(emulator), f'--config={stage/"1984.conf"}',
        '--6128', '--memory=512', '--autostart=BOOT', f'--pilot={pilot}',
        '--pilot-replies-stderr', '--exit-after=12000'], cwd=ROOT,
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
        text=True, bufsize=1, env={**os.environ, 'SDL_VIDEODRIVER': 'dummy', 'SDL_AUDIODRIVER': 'dummy'})
    messages = queue.Queue()
    def pump():
        with (stage/'1984.log').open('w') as log:
            for line in process.stderr:
                log.write(line); log.flush(); messages.put(line.rstrip())
        messages.put(None)
    thread = threading.Thread(target=pump, daemon=True)
    thread.start()
    def receive(pattern, timeout=45):
        deadline = time.monotonic()+timeout
        while time.monotonic()<deadline:
            try:
                line = messages.get(timeout=min(0.2, max(0.01, deadline-time.monotonic())))
            except queue.Empty:
                continue
            if line is None:
                raise RuntimeError(f'1984 exited; see {stage}/1984.log')
            if pattern in line:
                return line
        raise TimeoutError(f'{pattern}; see {stage}/1984.log')
    def send(command):
        fd = os.open(pilot, os.O_WRONLY | os.O_NOCTTY)
        try:
            os.write(fd, (command+'\n').encode())
        finally:
            os.close(fd)
        reply = receive('1984: pilot reply: ').split('1984: pilot reply: ', 1)[1]
        if not reply.startswith('ok '):
            raise RuntimeError(reply)
    try:
        receive('pilot PTY:', 15)
        sym = symbols(stage/'stream.sym')
        for _ in range(30):
            send('wait frames 150 200')
            send(f'snapshot-save {stage/"result.sna"}')
            data = (stage/'result.sna').read_bytes()
            ram = snapshot(data)[1]
            if ram[sym['probe_phase']] in (0xA5, 0xFF):
                break
        else:
            raise AssertionError('diagnostic did not finish')
        result = verify(data, stage, report)
        send('wait frames 150 200')
        send(f'snapshot-save {stage/"stable.sna"}')
        stable = (stage/'stable.sna').read_bytes()
        verify(stable, stage, report)
        if snapshot(data)[1] != snapshot(stable)[1]:
            raise AssertionError('RAM changed after completion')
        if sha(image.read_bytes()) != report['image_sha256']:
            raise AssertionError('read-only diagnostic changed M4 media')
        result['emulator_sha256'] = sha(emulator.read_bytes())
        (stage/'result.json').write_text(json.dumps(result, indent=2)+'\n')
        print('PASS '+json.dumps(result, sort_keys=True), flush=True)
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill(); process.wait()
        thread.join(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path)
    parser.add_argument('--variant', choices=('normal', 'short', 'extra', 'missing'), default='normal')
    parser.add_argument('--stage', type=Path)
    parser.add_argument('--prepare-only', action='store_true')
    parser.add_argument('--emulator', type=Path, default=ROOT.parent/'1984/1984')
    args = parser.parse_args()
    if bool(args.app) == bool(args.stage):
        parser.error('specify exactly one of --app or --stage')
    stage = args.stage.resolve() if args.stage else prepare(args.app.resolve(), args.variant)
    if not args.prepare_only:
        run(stage, args.emulator.resolve())


if __name__ == '__main__':
    main()
