#!/usr/bin/env python3
"""Run the same portable FS/clipboard APP from a private disk via normal Desk input."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]


def run(mode, clipboard=False, chooser=False, data_pages=False, package_modules=False, two_segment=False, launch_case='good'):
    if package_modules and not data_pages:
        raise ValueError('package module qualification currently requires --data-pages')
    if two_segment and not package_modules:
        raise ValueError('two-segment qualification requires --package-modules')
    if launch_case!='good' and not two_segment:
        raise ValueError('launch faults require --two-segment')
    service = 'data-pages' if data_pages else 'chooser' if chooser else 'clipboard' if clipboard else 'filesystem'
    work=ROOT/'build/msx'
    work.mkdir(parents=True,exist_ok=True)
    stage=Path(tempfile.mkdtemp(prefix=f'portable-{service}-{mode}-',dir=work))
    card=stage/'card';shutil.copytree(ROOT/'QA/MSX/CARD',card)
    app=ROOT/('build/universal/SCRAPPRB.APP' if clipboard else 'build/universal/FSPROBE.APP')
    source='apps/scrapprobe' if clipboard else 'apps/fsprobe'
    features={'UNIVERSAL_SCRAP':'1','APP_ICON':'apps/abiprobe/icon.asm'} if clipboard else {'UNIVERSAL_FS':'1'}
    if chooser:
        from filepick_scenario import FEATURES
        source='apps/filepickprobe';app=ROOT/'build/universal/PICKPRB.APP';features=FEATURES
    if data_pages:
        source='apps/pageprobe';app=ROOT/'build/universal/PAGEPRB.APP'
        features={'UNIVERSAL_DATA_PAGES':'1','UNIVERSAL_SCRAP':'1','APP_ICON':'apps/abiprobe/icon.asm'}
    if os.environ.get('PORTABLE_PROBE_ICON16'):
        features['APP_ICON16']=os.environ['PORTABLE_PROBE_ICON16']
    if two_segment:
        spec=json.loads((ROOT/'apps/pageprobe/manifest.json').read_text())
        spec.update(minimum_pages=2,preferred_pages=4,secondary_code={'required':True})
        (stage/'manifest.json').write_text(json.dumps(spec))
        # A full second bank exercises real streaming/CRC; no secondary entry
        # is called until the separate sealed-call service is implemented.
        (stage/'secondary.bin').write_bytes(b'\xC3\x08\x40GBS4\x01\xC9'+bytes(0x3F00-9))
        features.update(APP_MANIFEST=str(stage/'manifest.json'),APP_SECONDARY=str(stage/'secondary.bin'))
    subprocess.run(['bash','tools/build_uapp.sh',source,str(app)],cwd=ROOT,
                   env={**os.environ,**features},check=True)
    shutil.copyfile(app,stage/'probe.APP')
    delivery=app.read_bytes()
    if two_segment:
        (stage/'primary.bin').write_bytes(delivery[:-0x3F00])
    if launch_case=='badcrc': delivery=delivery[:-1]+bytes([delivery[-1]^1])
    elif launch_case=='short': delivery=delivery[:-1]
    elif launch_case=='extra': delivery+=b'!'
    (stage/'launch.APP').write_bytes(delivery)
    for name in ('UNAPINET.COM','UNAPI.TXT'):
        (card/name).unlink(missing_ok=True)
    (card/'AUTOEXEC.BAT').write_bytes(b'GBMSX\r\n')
    cfg=(card/'GEOBENCH.CFG').read_text()
    cfg='\n'.join(f'MSXMODE={mode}' if s.startswith('MSXMODE=') else s for s in cfg.splitlines())
    (card/'GEOBENCH.CFG').write_text(cfg+'\n')
    # The disposable CLOCK alias lets the actual Desktop launch the diagnostic
    # via Desk, without debugger-injected code/launches or release media changes.
    (card/'GBENCH/CLOCK.APP').write_bytes(delivery)
    fixture=card/'UFSTEST';(fixture/'SUB').mkdir(parents=True)
    (fixture/'SOURCE.BIN').write_bytes(bytes((i*13+7)&255 for i in range(1025)))
    (fixture/'SUB/SMALL.TXT').write_bytes(b'OK!')
    if chooser:
        from filepick_scenario import fixture as chooser_fixture
        chooser_fixture(stage/'DOCUI')
    rasm=os.environ.get('RASM','rasm')
    experimental=['-DPORTABLE_DATA_PAGES=1'] if data_pages else []
    if package_modules:
        from build_msx_package_modules import build
        experimental+=['-DPORTABLE_PACKAGE_STREAM=1']
        build(stage/'modules')
        for name in ('GBAPV4.MOD','GBPKFIX.MOD','GBPKLOAD.MOD'):
            shutil.copyfile(stage/'modules'/name,card/'GBENCH'/name)
    else:
        subprocess.run([rasm,str(ROOT/'kernel/msx_gbap4.asm'),'-s','-sq','-o','gbapv4',*experimental],cwd=work,check=True)
        (card/'GBENCH/GBAPV4.MOD').write_bytes((work/'GBAPV4.RAW').read_bytes())
        if data_pages:
            subprocess.run([rasm,str(ROOT/'kernel/msx_data_pages.asm'),'-s','-sq','-o','datapage',*experimental],cwd=work,check=True)
            (card/'GBENCH/GBDPAGE.MOD').write_bytes((work/'GBDPAGE.RAW').read_bytes())
    args=['-DPLATFORM_MSX=1','-DPREEMPTIVE=1','-DPREEMPTIVE_CONTEXT=1','-DTITLEBAR_TILE=1']
    args+=experimental
    if mode==7: args+=['-DMSX_SCREEN7=1']
    subprocess.run([rasm,str(ROOT/'kernel/gbkern.asm'),'-s','-o',f'gbkernm{mode}',*args],cwd=work,check=True)
    if package_modules:
        (card/'GBENCH/GBPKWM.MOD').write_bytes((work/'GBPKWM.RAW').read_bytes())
    subprocess.run([rasm,str(ROOT/'kernel/msx_stub.asm'),*experimental,*(['-DMSX_SCREEN7=1'] if mode==7 else [])],cwd=work,check=True)
    child=(work/'GBMSX.COM').read_bytes()
    if len(child)>0x3F00: raise AssertionError('MSX child exceeds loader window')
    (card/f'GBMSX{mode}.COM').write_bytes(child)
    image=stage/'filesystem.img'
    subprocess.run(['bash','tools/build_msx_img.sh',str(card),str(image)],cwd=ROOT,check=True)
    if chooser:
        from filepick_scenario import stage_image
        stage_image(image,stage/'DOCUI')
    result=stage/'result.txt'
    stem='pageprobe' if data_pages else 'filepickprobe' if chooser else 'scrapprobe' if clipboard else 'fsprobe'
    shutil.copyfile(ROOT/f'build/universal-obj/{stem}/app.noi',stage/'probe.noi')
    state=next(line.split()[2] for line in (ROOT/f'build/universal-obj/{stem}/app.noi').read_text().splitlines()
               if line.startswith(f'DEF _{stem}_state '))
    env={**os.environ,'MSX_UNAPI':'0','MSX_MOUSE':'0','MSX_HEADLESS':'1',
         'MSX_SCRIPT':'debug/portable_clipboard_openmsx.tcl' if clipboard else 'debug/portable_fs_openmsx.tcl',
         'GEOBENCH_FS_OPERATION':'9' if clipboard else '8','GEOBENCH_FS_STATE':state,
         'GEOBENCH_FS_OUTPUT':str(result),'SDL_AUDIODRIVER':'dummy'}
    if chooser:
        env['MSX_SCRIPT']='debug/portable_filepick_openmsx.tcl'
        env['GEOBENCH_FS_DEADLINE']='320' # 13 pointer journeys, not the single-launch FS probe
        linked={v[1]:v[2] for line in (ROOT/f'build/universal-obj/{stem}/app.noi').read_text().splitlines()
                if len(v:=line.split())==3 and v[0]=='DEF'}
        env['GEOBENCH_PICK_OBJECT']=linked['_picker'];env['GEOBENCH_PICK_TEXT']=linked['_text']
    if data_pages:
        env['MSX_SCRIPT']='debug/portable_pages_openmsx.tcl'
        env['GEOBENCH_FS_OPERATION']='10'
    if two_segment:
        env.update(MSX_SCRIPT='debug/portable_launch_openmsx.tcl',
                   GEOBENCH_FS_DEADLINE='300', # three full-bank CRCs plus pointer/Desk journeys
                   GEOBENCH_LAUNCH_CASE=launch_case, GEOBENCH_LAUNCH_PRIMARY=str(stage/'primary.bin'),
                   GEOBENCH_LAUNCH_SECONDARY=str(stage/'secondary.bin'))
        for filename, names in ((work/f'gbkernm{mode}.sym',('MSX_APP_LOAD','MSX_APP_RETURN','MSX_APP_PROGRESS_UPDATED')),
                                (stage/'modules/msx_package.sym',('PKG_SECONDARY_ENTRY',))):
            symbols={n:int(v,16) for n,v in re.findall(r'^(\w+) #([0-9A-Fa-f]+)',filename.read_text(),re.M)}
            for name in names: env['GEOBENCH_LAUNCH_'+name]=str(symbols[name])
    print(f'Portable {service} Screen {mode}; artifacts: {stage}',flush=True)
    subprocess.run(['bash','tools/run_msx.sh',str(image)],cwd=ROOT,env=env,check=True,timeout=180)
    print(result.read_text())
    if 'STATUS=PASS\n' not in result.read_text(): raise AssertionError(f'MSX {service} failed')
    if not clipboard and not chooser and not data_pages:
        data=subprocess.check_output(['mtype','-i',str(image)+'@@16384','::/UFSTEST/RESULT.BIN'])
        if data!=b'DONE': raise AssertionError('independent MSX media readback differs')
    if subprocess.check_output(['mtype','-i',str(image)+'@@16384','::/GBENCH/CLOCK.APP'])!=delivery:
        raise AssertionError('MSX APP is not byte-identical')
    print(f'PASS Screen {mode}: staged APP SHA256 {hashlib.sha256(delivery).hexdigest()}',flush=True)
    return stage


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode',type=int,choices=(6,7),default=7)
    option=parser.add_mutually_exclusive_group()
    option.add_argument('--clipboard',action='store_true')
    option.add_argument('--chooser',action='store_true')
    option.add_argument('--data-pages',action='store_true')
    parser.add_argument('--package-modules',action='store_true',
                        help='private fixed stream composition (requires --data-pages)')
    parser.add_argument('--two-segment',action='store_true',
                        help='package the probe with a full secondary bank (requires --package-modules)')
    parser.add_argument('--launch-case',choices=('good','badcrc','short','extra'),default='good')
    args=parser.parse_args()
    run(args.mode,args.clipboard,args.chooser,args.data_pages,args.package_modules,args.two_segment,args.launch_case)
