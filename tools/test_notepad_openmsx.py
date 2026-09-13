#!/usr/bin/env python3
"""Repeat the actual editor workflow without rebuilding; use a fresh image copy."""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image', type=Path, required=True, help='private fixture with matching probe.noi/APP')
    parser.add_argument('--output', type=Path, required=True, help='new evidence directory')
    args = parser.parse_args()
    if args.output.exists(): parser.error('output exists; preserve prior evidence')
    args.output.mkdir(parents=True)
    image = args.output.resolve()/'filesystem.img'
    original_hash = hashlib.sha256(args.image.read_bytes()).hexdigest()
    shutil.copyfile(args.image, image)
    linked = {v[1]: v[2] for line in (args.image.parent/'probe.noi').read_text().splitlines()
              if len(v := line.split()) == 3 and v[0] == 'DEF'}
    result = args.output.resolve()/'result.txt'
    env = {**os.environ, 'MSX_UNAPI':'0', 'MSX_MOUSE':'0', 'MSX_HEADLESS':'1',
           'MSX_SCRIPT':'debug/notepad_openmsx.tcl', 'SDL_AUDIODRIVER':'dummy',
           'GEOBENCH_FS_OPERATION':'11', 'GEOBENCH_FS_STATE':linked['_mode'],
           'GEOBENCH_FS_OUTPUT':str(result), 'GEOBENCH_NOTEPAD_VIEW':linked['_editor'],
           'GEOBENCH_NOTEPAD_PICKER':linked['_scratch'], 'GEOBENCH_FS_PENDING_VDP':'1',
           'GEOBENCH_FS_DEADLINE':'600'}
    subprocess.run(['bash', 'tools/run_msx.sh', str(image)], cwd=ROOT, env=env, check=True, timeout=180)
    print(result.read_text())
    assert 'STATUS=PASS\n' in result.read_text(), 'editor workflow failed'
    assert subprocess.check_output(['mtype', '-i', str(image)+'@@16384', '::/SAVED.TXT']) == b'abc\n'
    assert subprocess.check_output(['mtype', '-i', str(image)+'@@16384', '::/GBENCH/CLOCK.APP']) == (args.image.parent/'probe.APP').read_bytes()
    assert hashlib.sha256(args.image.read_bytes()).hexdigest() == original_hash
    print('PASS independent saved bytes, unchanged application and source image')


if __name__ == '__main__':
    main()
