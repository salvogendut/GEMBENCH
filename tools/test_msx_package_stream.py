#!/usr/bin/env python3
"""Private real-Nextor stream diagnostic; not production launch qualification."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import select
import subprocess
import tempfile

from embed_app_icon import _read_v4_manifest_spec, make_v4_preamble, refresh_v4_crc

ROOT = Path(__file__).resolve().parents[1]


def prepare():
    work = ROOT / 'build/notepad-84/evidence'
    work.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix='stream-nextor-', dir=work))
    card = stage / 'card'
    system = card / 'GBENCH'
    system.mkdir(parents=True)
    spec = json.loads((ROOT / 'apps/pageprobe/manifest.json').read_text())
    spec['required_capabilities'].remove('portable-data-pages')
    spec.update(minimum_pages=2, preferred_pages=2, secondary_code={'required': True})
    manifest = stage / 'manifest.json'
    manifest.write_text(json.dumps(spec))
    spec = _read_v4_manifest_spec(manifest)
    secondary = b'\xC3\x08\x40GBS4\x01' + bytes((i*19+5)&255 for i in range(0x3F00-8))
    preamble = make_v4_preamble(bytes(256), spec, 0x3F00, 0x7E00,
                                icon16=bytes(512), secondary=secondary)
    primary = preamble + bytes((i*13+7)&255 for i in range(0x3F00-len(preamble)))
    package = bytearray(primary + secondary)
    refresh_v4_crc(package)
    (stage / 'primary.bin').write_bytes(package[:0x3F00])
    (stage / 'secondary.bin').write_bytes(package[0x3F00:])
    (system / 'GOOD.APP').write_bytes(package)
    bad = bytearray(package)
    bad[-1] ^= 1
    (system / 'BADCRC.APP').write_bytes(bad)
    (system / 'SHORT.APP').write_bytes(package[:-1])
    (system / 'EXTRA.APP').write_bytes(package + b'!')
    rasm = os.environ.get('RASM', 'rasm')
    subprocess.run([rasm, str(ROOT/'debug/package_stream_msx.asm'), '-s', '-sq', '-o', 'stream'],
                   cwd=stage, check=True)
    symbols = {n: int(v, 16) for n, v in re.findall(r'^(\w+) #([0-9A-Fa-f]+)',
               (stage/'stream.sym').read_text(), re.M)}
    # Copy the small COM payload out of its bootstrap storage before touching
    # the diagnostic's private low RAM or mapping another application page.
    boot = stage/'boot.asm'
    boot.write_text('org #100\nld hl,payload\nld de,#8000\nld bc,finish-payload\n'
                    'ldir\njp #8000\npayload incbin "stream-diag.bin"\nfinish\n'
                    'assert finish<=#1800,"diagnostic COM overlaps transfer scratch"\n'
                    'save "STREAM.COM",#100,$-#100\n')
    subprocess.run([rasm, str(boot)], cwd=stage, check=True)
    (card/'STREAM.COM').write_bytes((stage/'STREAM.COM').read_bytes())
    (card/'AUTOEXEC.BAT').write_bytes(b'STREAM\r\n')
    image = stage/'stream.img'
    subprocess.run(['bash', 'tools/build_msx_img.sh', str(card), str(image)], cwd=ROOT, check=True)
    report = dict(image=str(image), app_sha256=hashlib.sha256(package).hexdigest(),
                  image_sha256=hashlib.sha256(image.read_bytes()).hexdigest(),
                  symbols=symbols, diagnostic_bytes=len((stage/'stream-diag.bin').read_bytes()))
    (stage/'build.json').write_text(json.dumps(report, indent=2)+'\n')
    return stage, report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare-only', action='store_true')
    parser.add_argument('--check-1983', type=Path, metavar='EXISTING_STAGE')
    parser.add_argument('--bridge', type=Path)
    parser.add_argument('--omega', type=Path)
    parser.add_argument('--sunrise', type=Path)
    args = parser.parse_args()
    if args.check_1983:
        if not all((args.bridge, args.omega, args.sunrise)):
            parser.error('--check-1983 requires --bridge, --omega and --sunrise')
        return check_1983(args)
    stage, report = prepare()
    print(f'Private Nextor stream diagnostic: {stage}', flush=True)
    if args.prepare_only:
        return 0
    symbols = report['symbols']
    env = {**os.environ, 'MSX_UNAPI': '0', 'MSX_MOUSE': '0', 'MSX_HEADLESS': '1',
           'MSX_SCRIPT': str(ROOT/'debug/package_stream_openmsx.tcl'),
           'SDL_AUDIODRIVER': 'dummy', 'GB_STREAM_RESULT': str(stage/'result.txt'),
           'GB_STREAM_PRIMARY': str(stage/'primary.bin'),
           'GB_STREAM_SECONDARY': str(stage/'secondary.bin')}
    for suffix, symbol in [('DOS', 'MSX_PKG_BDOS'), ('DOS_RETURN', 'MSX_PKG_BDOS_RETURN'), ('SECONDARY_ENTRY', 'PKG_SECONDARY_ENTRY'),
                           ('CLEANUP', 'DIAG_CLEANUP'), ('DONE', 'DIAG_DONE')]:
        env['GB_STREAM_'+suffix] = str(symbols[symbol])
    subprocess.run(['bash', 'tools/run_msx.sh', report['image']], cwd=ROOT,
                   env=env, check=True, timeout=180)
    result = (stage/'result.txt').read_text()
    print(result)
    unchanged = hashlib.sha256(Path(report['image']).read_bytes()).hexdigest() == report['image_sha256']
    if 'STATUS=PASS\n' not in result or not unchanged:
        raise AssertionError('Nextor stream diagnostic failed or changed media')
    print(f"PASS: real Nextor, unchanged image; APP SHA256 {report['app_sha256']}")
    return 0


def check_1983(args):
    stage = args.check_1983.resolve()
    report = json.loads((stage/'build.json').read_text())
    image = Path(report['image'])
    output = stage/'1983-result.json'
    if output.exists():
        raise ValueError('preserve existing 1983 evidence; use a fresh stage')
    with (stage/'1983-bridge.log').open('w') as log:
        process = subprocess.Popen([str(args.bridge.resolve()), str(args.omega.resolve()),
            str(args.sunrise.resolve()), str(image)], stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=log, text=True, bufsize=1)
        def response(command=None):
            if command:
                process.stdin.write(command+'\n')
                process.stdin.flush()
            if not select.select([process.stdout], [], [], 60)[0]:
                raise TimeoutError('1983 bridge response')
            data = json.loads(process.stdout.readline())
            if isinstance(data, dict) and 'error' in data:
                raise RuntimeError(data['error'])
            return data
        result = dict(status='FAIL')
        try:
            if response() != {'ready': True}:
                raise RuntimeError('1983 bridge startup')
            for _ in range(360):
                state = response('frames 25')
                # Physical mapper RAM, even when BIOS ROM covers page zero.
                raw = response(f"ram {state['p0']*0x4000+0x2030} 11")
                if response('read 32768 3') != [0x2A, 6, 0]:
                    continue
                if raw[0] == 0xEE:
                    raise AssertionError(f'guest failed: {raw}')
                if raw[0] == 0x55:
                    ticks = raw[4]+256*raw[5]
                    if raw[1:4] != [5, 0, 6] or ticks < 100:
                        raise AssertionError(f'incomplete diagnostic: {raw}')
                    result.update(status='PASS', cases=6, last_load_ticks=ticks,
                                  frame=state['frame'], result=raw)
                    break
            else:
                raise TimeoutError('1983 diagnostic deadline')
        except Exception as error:
            result['error'] = str(error)
        finally:
            process.terminate()
            process.wait(timeout=10)
    unchanged = hashlib.sha256(image.read_bytes()).hexdigest() == report['image_sha256']
    result.update(image_unchanged=unchanged, app_sha256=report['app_sha256'],
                  bridge_sha256=hashlib.sha256(args.bridge.read_bytes()).hexdigest(),
                  omega_sha256=hashlib.sha256(args.omega.read_bytes()).hexdigest(),
                  sunrise_sha256=hashlib.sha256(args.sunrise.read_bytes()).hexdigest())
    if not unchanged:
        result.update(status='FAIL', error='diagnostic changed media')
    output.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result, indent=2))
    return 0 if result['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
