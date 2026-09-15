#!/usr/bin/env python3
"""Create disposable Screen 6/7 images for portable GBRDEMO qualification."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

from embed_app_icon import parse_manifest

ROOT=Path(__file__).resolve().parents[1]
CASES=('good','checksum','truncated','oversized')


def put(image: Path, source: Path, target: str) -> None:
    subprocess.run(['mcopy','-o','-i',str(image)+'@@16384',str(source),'::/'+target],check=True)


def prepare(output: Path) -> None:
    source=ROOT/'QA/MSX/GBMSX.IMG'
    card=ROOT/'QA/MSX/CARD'
    app=ROOT/'build/universal/GBRDEMO.APP'
    resource=ROOT/'build/examples/hello-dialog.gbr'
    for path in (source,card/'GBENCH/FILEMGR.APP',app,resource):
        if not path.exists(): raise ValueError('missing prerequisite: '+str(path))
    package=parse_manifest(app.read_bytes())
    if (package['version'],package['application_id'],len(package['segments']))!=(4,'GBRDEMO',1):
        raise ValueError('expected the compile-once primary-only GBRDEMO')
    if output.exists(): raise ValueError('preserve existing evidence; choose a fresh output directory')
    source_hash=hashlib.sha256(source.read_bytes()).hexdigest()
    canonical=resource.read_bytes()
    if hashlib.sha256(canonical).hexdigest()!='49b42e9268ad4f4208d70f591f9d3f6b6ad7bee2dcf6f008a773ece968febf12':
        raise ValueError('HELLO.GBR differs from the frozen fixture')
    output.mkdir(parents=True)
    files={}
    for mode in (6,7):
        for case in CASES:
            stage=output/f'mode{mode}-{case}';stage.mkdir()
            image=stage/'filesystem.img';shutil.copyfile(source,image)
            cfg=(card/'GEOBENCH.CFG').read_bytes()
            cfg=re.sub(rb'MSXMODE=\d',f'MSXMODE={mode}'.encode(),cfg)
            (stage/'GEOBENCH.CFG').write_bytes(cfg)
            (stage/'AUTOEXEC.BAT').write_bytes(b'GBMSX\r\n')
            payload=(canonical if case=='good' else
                     canonical[:-1]+bytes((canonical[-1]^1,)) if case=='checksum' else
                     canonical[:-1] if case=='truncated' else canonical.ljust(513,b'\0'))
            (stage/'HELLO.GBR').write_bytes(payload)
            put(image,stage/'GEOBENCH.CFG','GEOBENCH.CFG')
            put(image,stage/'AUTOEXEC.BAT','AUTOEXEC.BAT')
            put(image,app,'GBENCH/GBRDEMO.APP')
            put(image,stage/'HELLO.GBR','HELLO.GBR')
            if subprocess.check_output(['mtype','-i',str(image)+'@@16384','::/GBENCH/GBRDEMO.APP'])!=app.read_bytes():
                raise AssertionError('staged APP differs')
            files[f'mode{mode}-{case}']=dict(
                image=str(image),resource_bytes=len(payload),
                resource_sha256=hashlib.sha256(payload).hexdigest())
    if hashlib.sha256(source.read_bytes()).hexdigest()!=source_hash:
        raise AssertionError('normal MSX image changed')
    (output/'manifest.json').write_text(json.dumps(dict(
        profile='msx-gbrdemo-private-v1',source_image=str(source),
        source_image_sha256=source_hash,source_unchanged=True,
        app_sha256=hashlib.sha256(app.read_bytes()).hexdigest(),
        canonical_resource_sha256=hashlib.sha256(canonical).hexdigest(),
        files=files),indent=2)+'\n')
    print('PASS private Screen 6/7 GBRDEMO fixtures: '+str(output))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();prepare(args.output.resolve())
