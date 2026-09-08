#!/usr/bin/env python3
"""One built Desktop, independent disposable M4 runs, retained per-case logs."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

from cpc_desktop_media import validate

ROOT = Path(__file__).resolve().parents[1]


def cases(settings=False):
    result = [('desktop', []), ('lifecycle', ['--filemgr'])]
    result += [(name, ['--filemgr-scenario', name]) for name in
               ('workflow', 'services', 'contexts', 'stacking', 'minute-cadence', 'cadence')]
    result += [('filemgr-'+name, ['--filemgr-case', name]) for name in
               ('missing', 'short', 'oversized', 'corrupt', 'unbound', 'no-register')]
    result += [('root-'+name, ['--root-fault', name]) for name in
               ('missing', 'short', 'oversized', 'cfg-missing', 'cfg-short', 'cfg-oversized')]
    if settings:
        result += [('settings-'+name,['--settings-case',name]) for name in
                   ('normal','mixed','contexts','missing','short','corrupt','unbound','edit-missing')]
    return result


def run_case(case, emulator, artifacts):
    name, options = case
    command = [sys.executable, str(ROOT/'tools/test_cpc_runtime_1984.py'),
               '--desktop-delivery', '--skip-build', '--emulator', str(emulator), *options]
    log = artifacts/(name+'.log')
    print('START '+name, flush=True)
    with log.open('w') as output:
        completed = subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT)
    result = dict(case=name, exit_code=completed.returncode, log=str(log))
    print(('PASS ' if completed.returncode == 0 else 'FAIL ')+name, flush=True)
    return result


def run(emulator, jobs=1, skip_build=False):
    emulator = emulator.resolve()
    if not skip_build:
        subprocess.run([sys.executable, str(ROOT/'tools/build_cpc.py')], cwd=ROOT, check=True)
    media = ROOT/'QA/CPC-Desktop'
    manifest = validate(media, pristine=True)
    if manifest['profile'] not in ('cpc-desktop-m4-v2','cpc-desktop-m4-v3'):
        raise ValueError('combined acceptance requires Desktop plus File Manager')
    artifact_root=ROOT/'build/cpc-delivery-runtime';artifact_root.mkdir(parents=True,exist_ok=True)
    artifacts = Path(tempfile.mkdtemp(prefix='geobench-cpc-delivery-',dir=artifact_root))
    print('Delivery acceptance logs: '+str(artifacts), flush=True)
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        results = list(pool.map(lambda case: run_case(case, emulator, artifacts), cases('settings' in manifest['sections'])))
    # Each child verifies the actual FAT payload before using a private image.
    # Verify the source manifest/staging/image remained pristine after ALL runs.
    if validate(media, pristine=True) != manifest:
        raise AssertionError('acceptance changed the source delivery')
    report = dict(profile=manifest['profile'], image_sha256=manifest['image_sha256'],
                  files=manifest['files'], emulator_sha256=hashlib.sha256(emulator.read_bytes()).hexdigest(),
                  cases=results, passed=all(r['exit_code'] == 0 for r in results))
    (artifacts/'result.json').write_text(json.dumps(report, indent=2)+'\n')
    print(('PASS' if report['passed'] else 'FAIL')+' combined Desktop acceptance: '+str(artifacts), flush=True)
    return report['passed']


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--emulator', type=Path, default=ROOT.parent/'1984/1984')
    parser.add_argument('--jobs', type=int, choices=range(1, 5), default=1,
                        help='independent emulator processes; no parallel builds')
    parser.add_argument('--skip-build', action='store_true')
    sys.exit(0 if run(**vars(parser.parse_args())) else 1)
