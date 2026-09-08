#!/usr/bin/env python3
"""Run the SAME filesystem APP from a private MSX hard disk, normal Desk launch."""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]


def run(mode):
    work=ROOT/'build/msx'
    work.mkdir(parents=True,exist_ok=True)
    stage=Path(tempfile.mkdtemp(prefix=f'portable-fs-{mode}-',dir=work))
    card=stage/'card';shutil.copytree(ROOT/'QA/MSX/CARD',card)
    app=ROOT/'build/universal/FSPROBE.APP'
    subprocess.run(['bash','tools/build_uapp.sh','apps/fsprobe',str(app)],cwd=ROOT,
                   env={**os.environ,'UNIVERSAL_FS':'1'},check=True)
    for name in ('UNAPINET.COM','UNAPI.TXT'):
        (card/name).unlink(missing_ok=True)
    (card/'AUTOEXEC.BAT').write_bytes(b'GBMSX\r\n')
    cfg=(card/'GEOBENCH.CFG').read_text()
    cfg='\n'.join(f'MSXMODE={mode}' if s.startswith('MSXMODE=') else s for s in cfg.splitlines())
    (card/'GEOBENCH.CFG').write_text(cfg+'\n')
    # The disposable CLOCK alias lets the actual Desktop launch the diagnostic
    # via Desk, without debugger-injected code/launches or release media changes.
    (card/'GBENCH/CLOCK.APP').write_bytes(app.read_bytes())
    fixture=card/'UFSTEST';(fixture/'SUB').mkdir(parents=True)
    (fixture/'SOURCE.BIN').write_bytes(bytes((i*13+7)&255 for i in range(1025)))
    (fixture/'SUB/SMALL.TXT').write_bytes(b'OK!')
    rasm=os.environ.get('RASM','rasm')
    subprocess.run([rasm,str(ROOT/'kernel/msx_gbap4.asm'),'-s','-sq','-o','gbapv4'],cwd=work,check=True)
    (card/'GBENCH/GBAPV4.MOD').write_bytes((work/'GBAPV4.RAW').read_bytes())
    args=['-DPLATFORM_MSX=1','-DPREEMPTIVE=1','-DPREEMPTIVE_CONTEXT=1','-DTITLEBAR_TILE=1']
    if mode==7: args+=['-DMSX_SCREEN7=1']
    subprocess.run([rasm,str(ROOT/'kernel/gbkern.asm'),'-s','-o',f'gbkernm{mode}',*args],cwd=work,check=True)
    subprocess.run([rasm,str(ROOT/'kernel/msx_stub.asm'),*(['-DMSX_SCREEN7=1'] if mode==7 else [])],cwd=work,check=True)
    child=(work/'GBMSX.COM').read_bytes()
    if len(child)>0x3F00: raise AssertionError('MSX child exceeds loader window')
    (card/f'GBMSX{mode}.COM').write_bytes(child)
    image=stage/'filesystem.img'
    subprocess.run(['bash','tools/build_msx_img.sh',str(card),str(image)],cwd=ROOT,check=True)
    result=stage/'result.txt'
    state=next(line.split()[2] for line in (ROOT/'build/universal-obj/fsprobe/app.noi').read_text().splitlines()
               if line.startswith('DEF _fsprobe_state '))
    env={**os.environ,'MSX_UNAPI':'0','MSX_MOUSE':'0','MSX_HEADLESS':'1',
         'MSX_SCRIPT':'debug/portable_fs_openmsx.tcl','GEOBENCH_FS_STATE':state,
         'GEOBENCH_FS_OUTPUT':str(result),'SDL_AUDIODRIVER':'dummy'}
    print(f'Portable FS Screen {mode}; artifacts: {stage}',flush=True)
    subprocess.run(['bash','tools/run_msx.sh',str(image)],cwd=ROOT,env=env,check=True,timeout=180)
    print(result.read_text())
    if 'STATUS=PASS\n' not in result.read_text(): raise AssertionError('MSX filesystem failed')
    data=subprocess.check_output(['mtype','-i',str(image)+'@@16384','::/UFSTEST/RESULT.BIN'])
    if data!=b'DONE': raise AssertionError('independent MSX media readback differs')
    if subprocess.check_output(['mtype','-i',str(image)+'@@16384','::/GBENCH/CLOCK.APP'])!=app.read_bytes():
        raise AssertionError('MSX APP is not byte-identical')
    print(f'PASS Screen {mode}: APP SHA256 {hashlib.sha256(app.read_bytes()).hexdigest()}',flush=True)
    return stage


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode',type=int,choices=(6,7),default=7)
    run(parser.parse_args().mode)
