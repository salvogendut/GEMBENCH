"""Existing portable computation APP through the private CPC receiver, M4 only."""
import hashlib
import json
import os
import re
import subprocess
from embed_app_icon import parse_manifest, refresh_v4_crc
from cpc_production_lifetime import physical

CASES=('normal','crc','short','extra','no-register',
       'module-missing','module-short','module-extra','module-corrupt')

def prepare(root,work,image,artifacts,case):
    volume=str(image)+'@@16384'
    if case.startswith('module-'):
        name='::/GBENCH/GBPKLOAD.MOD'
        if case=='module-missing':
            subprocess.run(['mdel','-i',volume,name],check=True)
        else:
            data=bytearray((work/'GBPKLOAD.MOD').read_bytes())
            if case=='module-short':data=data[:-1]
            if case=='module-extra':data+=b'!'
            if case=='module-corrupt':data[42]^=1
            file=artifacts/'bad-module.bin';file.write_bytes(data)
            subprocess.run(['mcopy','-o','-i',volume,str(file),name],check=True)
        return
    secondary=artifacts/'secondary.bin'
    subprocess.run(['bash','tools/build_usecondary.sh','apps/computeprobe/leaf',str(secondary)],cwd=root,check=True)
    secondary.write_bytes(secondary.read_bytes().ljust(0x1F00,b'\0'))
    subprocess.run(['python3','tools/check_secondary_app.py','--source','apps/computeprobe/leaf',
                    '--asm','build/universal-secondary/leaf/main.asm',
                    '--map','build/universal-secondary/leaf/secondary.map','--binary',str(secondary)],cwd=root,check=True)
    app=artifacts/'COMPUTE.APP'
    subprocess.run(['bash','tools/build_uapp.sh','apps/computeprobe',str(app)],cwd=root,check=True,
        env={**os.environ,'UNIVERSAL_COMPUTE':'1','APP_ICON':'apps/abiprobe/icon.asm','APP_SECONDARY':str(secondary)})
    (artifacts/'probe.noi').write_bytes((root/'build/universal-obj/computeprobe/app.noi').read_bytes())
    data=bytearray(app.read_bytes())
    if case=='crc':data[-1]^=1
    if case=='short':data=data[:-1]
    if case=='extra':data+=b'!'
    if case=='no-register':
        at=int.from_bytes(data[1:3],'little')-0x4000
        data[at]=0xC9                       # valid main returning without a window
        refresh_v4_crc(data)
    staged=artifacts/'staged.APP';staged.write_bytes(data)
    # The real Desktop has no diagnostic F5 shortcut. Use its existing Desk
    # Calculator launch on this disposable image only.
    subprocess.run(['mcopy','-o','-i',volume,str(staged),'::/GBENCH/CALC.APP'],check=True)

def boot_rejected(case,data,artifacts,sym,wait,read):
    from test_cpc_foundation_1984 import snapshot
    ram=snapshot(data)[1]
    if ram[sym['cpc_package_ready']] or ram[sym['wm_nwin']] or ram[sym['core_owner_active']]:
        raise AssertionError('bad module reached capability/app publication')
    if any(ram[sym[n]] for n in ('io_busy','io_fd','io_offline','cs_owned')):
        raise AssertionError('bad boot module leaked transport state')
    for stem in ('main','irq','tmp'):
        lo,hi=sym[f'cpc_{stem}_stack'],sym[f'cpc_{stem}_top']
        if ram[lo-16:lo]!=b'\xD7'*16 or ram[hi:hi+16]!=b'\xD7'*16:
            raise AssertionError('boot failure stack guard')
    wait(60)
    if snapshot(read('boot-rejected-stable'))[1]!=ram:
        raise AssertionError('rejected boot resumed execution')
    result=dict(status='PASS',case=case,boot_failed_closed=True)
    (artifacts/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    print('PASS '+json.dumps(result),flush=True)
    return artifacts

def exercise(root,manifest,work,sym,image,artifacts,case,send,wait,read,key,move):
    from test_cpc_runtime_1984 import integrity
    from test_cpc_foundation_1984 import snapshot
    original=hashlib.sha256(image.read_bytes()).hexdigest()
    checks=[]
    def state(name):
        wait(20)
        ram,stack=integrity(read(name),sym,work)
        for n in ('pkg_busy','sec_busy','cs_owned','cpc_package_prefix'):
            if ram[sym[n]]:raise AssertionError('unfinished '+n)
        if ram[sym['cpc_package_ready']]!=1:
            raise AssertionError('unqualified module')
        if ram[0x100:0x400]!=(work/'GBPKLOAD.MOD').read_bytes():
            raise AssertionError('fixed loader module changed')
        if int.from_bytes(ram[0x2F20:0x2F22],'little')!=0x05DF:
            raise AssertionError('secondary capability missing/wrong')
        checks.append(dict(name=name,stack_bytes=stack));return ram
    base=state('secondary-baseline')
    pages=base[sym['core_page_state']:sym['core_page_state']+32]
    owners=base[sym['core_owner_active']:sym['core_owner_active']+8]
    identities=[]
    app=(artifacts/'COMPUTE.APP').read_bytes()
    primary=parse_manifest(app)['segments'][0]['stored_length']
    at=int(re.search(r'^DEF _computeprobe_state (0x[0-9A-Fa-f]+)',
                    (artifacts/'probe.noi').read_text(),re.M)[1],16)
    def click():
        for command,held in (('key-down SPACE',True),('key-up SPACE',False)):
            send(command)
            for _ in range(200):
                wait(3);r=snapshot(read())[1]
                if bool(r[sym['poll_lastfire']])==held:break
            else:raise AssertionError('click was not sampled')
    last_generation=base[sym['core_owner_gen']+1]
    for cycle in range(3):
        move(76,190);click();wait(10)
        move(11,3);click();wait(12);move(12,23);click()
        r=state('secondary-launch-'+str(cycle))
        generation=r[sym['core_owner_gen']+1]
        if generation==last_generation:raise AssertionError('launch was not attempted')
        last_generation=generation
        if case=='normal':
            slot=r[sym['wm_focus']]
            if r[sym['wm_nwin']]!=2 or slot!=1:
                raise AssertionError('computation APP did not register/focus')
            p=physical(r[sym['wm_table']+25])-0x4000
            if r[p+at]!=85 or r[p+at+1]!=54:
                raise AssertionError('copied calls failed: '+str(list(r[p+at:p+at+8])))
            if r[p+0x4000:p+0x4000+primary]!=app[:primary]:
                raise AssertionError('primary code changed')
            owner=r[sym['core_win_owner']+slot];generation=r[sym['core_win_owner_gen']+slot]
            identity=(owner,generation)
            if identity in identities:raise AssertionError('owner generation reused')
            identities.append(identity)
            seal=r[sym['sec_table']+8*(owner-1):sym['sec_table']+8*owner]
            if seal[0]!=generation or not seal[1]:raise AssertionError('missing owner seal')
            index=seal[1]-1
            if r[sym['core_page_purpose']+index]!=7:raise AssertionError('wrong secondary purpose')
            secondary=app[primary:]
            start=physical(r[sym['core_page_native']+index])
            if r[start:start+len(secondary)]!=secondary:raise AssertionError('secondary code changed')
            key('ESCAPE');r=state('secondary-close-'+str(cycle))
        if r[sym['wm_nwin']]!=1 or r[sym['wm_focus']]!=0:
            raise AssertionError('failed/closed APP left a window')
        if r[sym['core_page_state']:sym['core_page_state']+32]!=pages or r[sym['core_owner_active']:sym['core_owner_active']+8]!=owners:
            raise AssertionError('owner/page leak')
        if any(r[sym['sec_table']:sym['sec_table']+64]):raise AssertionError('stale executable seal')
    send(f'crop {artifacts/"result.ppm"} 0 0 768 576 1')
    if hashlib.sha256(image.read_bytes()).hexdigest()!=original:
        raise AssertionError('computation qualification wrote to disk')
    report=dict(status='PASS',case=case,checks=checks,owners=identities,
                app_sha256=hashlib.sha256(app).hexdigest(),sections=manifest['sections'])
    (artifacts/'result.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS secondary receiver '+json.dumps(dict(case=case,checkpoints=len(checks),owners=identities)),flush=True)
    return artifacts
