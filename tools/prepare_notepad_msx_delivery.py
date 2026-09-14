#!/usr/bin/env python3
"""Freeze read-only-verified normal MSX payloads for Notepad acceptance.

The source image is never mounted writable or rebuilt. Each mode gets a copy
with only test configuration/documents changed. A second copy aliases CLOCK
to the same Notepad for the existing keyboard/chooser driver; the first keeps
all shipped apps intact for document handoff and Desk accessory regression.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

from embed_app_icon import parse_manifest

ROOT=Path(__file__).resolve().parents[1]


def prepare(output):
    source=ROOT/'QA/MSX/GBMSX.IMG';card=ROOT/'QA/MSX/CARD'
    if output.exists():raise ValueError('preserve existing evidence; use a fresh output directory')
    app=(ROOT/'build/universal/NOTEPAD.APP').read_bytes()
    package=parse_manifest(app)
    if package['version']!=4 or package['application_id']!='NOTEPAD' or len(package['segments'])!=2:
        raise ValueError('expected the real two-bank universal editor')
    originals={}
    for file in card.rglob('*'):
        if not file.is_file():continue
        name=file.relative_to(card).as_posix();raw=file.read_bytes()
        actual=subprocess.check_output(['mtype','-i',str(source)+'@@16384','::/'+name])
        if actual!=raw:raise ValueError('normal image and CARD differ: '+name)
        originals[name]=hashlib.sha256(raw).hexdigest()
    if (card/'GBENCH/NOTEPAD.APP').read_bytes()!=app:raise ValueError('native or stale Notepad in normal image')
    for mode in (6,7):
        route=(card/f'GBENCH/GBPKWM{mode}.MOD').read_bytes()
        if route[3:8]!=b'GBWM'+bytes([0x60|mode]):raise ValueError('wrong mode-specific routing module')
    source_hash=hashlib.sha256(source.read_bytes()).hexdigest()
    output.mkdir(parents=True)
    linked={k:int(v,16) for k,v in re.findall(r'^DEF (\w+) (0x[0-9A-Fa-f]+)',
                  (ROOT/'build/msx-obj/filemgr/app.noi').read_text(),re.M)}
    locals={n:linked['s__DATA' if area=='1' else 's__INITIALIZED']+int(v,16)
            for area,n,v in re.findall(r'^\s+([12])\s+(_\w+)\s+([0-9A-Fa-f]+)\s+R',
                         (ROOT/'build/msx-obj/filemgr/main.sym').read_text(),re.M)}
    for mode in (6,7):
        stage=output/f'mode{mode}';stage.mkdir();image=stage/'filesystem.img'
        shutil.copyfile(source,image)
        target=['-i',str(image)+'@@16384']
        def put(name,data):
            temp=stage/'transfer.tmp';temp.write_bytes(data)
            subprocess.run(['mcopy','-o',*target,str(temp),'::/'+name],check=True)
        cfg=(card/'GEOBENCH.CFG').read_bytes()
        cfg=re.sub(rb'MSXMODE=\d',f'MSXMODE={mode}'.encode(),cfg)
        put('GEOBENCH.CFG',cfg);put('AUTOEXEC.BAT',b'GBMSX\r\n')
        for name in ('ADOC','ADOC/SUB'):subprocess.run(['mmd',*target,'::/'+name],check=True)
        put('ADOC/EXACT.TXT',b'Chosen root document.\n')
        put('ADOC/SUB/EXACT.TXT',b'Chosen nested document.\n')
        (stage/'probe.APP').write_bytes(app)
        shutil.copyfile(ROOT/'build/universal/NOTEPAD.noi',stage/'probe.noi')
        (stage/'filemgr-symbols.json').write_text(json.dumps(locals,indent=2)+'\n')
        editor=stage/'editor';editor.mkdir()
        shutil.copyfile(image,editor/'filesystem.img')
        for name in ('probe.APP','probe.noi'):shutil.copyfile(stage/name,editor/name)
        subprocess.run(['mcopy','-o','-i',str(editor/'filesystem.img')+'@@16384',
                        str(stage/'probe.APP'),'::/GBENCH/CLOCK.APP'],check=True)
    if hashlib.sha256(source.read_bytes()).hexdigest()!=source_hash:raise AssertionError('source image changed')
    report=dict(source_image_sha256=source_hash,source_unchanged=True,files=originals,
                app_sha256=hashlib.sha256(app).hexdigest(),package=package)
    (output/'manifest.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS complete normal image/CARD inventory; fixtures: '+str(output))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    prepare(parser.parse_args().output.resolve())
