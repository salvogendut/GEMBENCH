"""Settings' shared text editor plus CPC persistence/reload, on private M4 only."""
import hashlib
import json
import re
import subprocess

from cpc_runtime_pixels import DEFAULT_THEME, verify_pixels
from cpc_runtime_clock import clock_cache_ready
from cpc_production_lifetime import physical
from test_cpc_foundation_1984 import snapshot

EDIT_CASES=('normal','exact','append','duplicate','unterminated','missing','empty',
            'oversized','long-value','unterminated-append','no-space',
            'module-missing','module-short','module-oversized')


def replace_value(raw,value):
    match=re.search(rb'(?:\A|(?<=[\r\n]))TITLEBAR=([^\r\n]*)',raw)
    if match: return raw[:match.start(1)]+value+raw[match.end(1):]
    return raw+b'TITLEBAR='+value+b'\r\n'


def prepare(case,media,work,image,artifacts):
    raw=(media/'CARD/GEOBENCH.CFG').read_bytes();payload=raw;name='/GEOBENCH.CFG'
    if case in ('normal','reboot'): return
    if case=='exact': payload=raw+b'#'*(512-len(raw))
    elif case=='append': payload=b''.join(line for line in raw.splitlines(keepends=True) if not line.startswith(b'TITLEBAR='))
    elif case=='duplicate': payload=raw+b'TITLEBAR=SOLID\r\n'
    elif case=='unterminated': payload=b'ICONS=REFINED\r\nTITLEBAR=ORIGINAL'
    elif case=='missing': payload=None
    elif case=='empty': payload=b''
    elif case=='oversized': payload=raw+b'#'*(513-len(raw))
    elif case=='long-value': payload=b'TITLEBAR='+b'X'*300+b'\r\n'
    elif case=='unterminated-append': payload=b'ICONS=REFINED'
    elif case=='no-space': payload=b'ICONS=REFINED\r\n';payload+=b'#'*(510-len(payload))+b'\r\n'
    elif case.startswith('module-'):
        name='/GBENCH/GBEDIT.MOD';module=(work/'GBEDIT.MOD').read_bytes()
        payload=None if case=='module-missing' else module[:-1] if case=='module-short' else module+b'\0'
    else: raise ValueError(case)
    target=['-i',str(image)+'@@16384'];subprocess.run(['mdel',*target,'::'+name],check=True)
    if payload is not None:
        path=artifacts/'edit-fixture.bin';path.write_bytes(payload)
        subprocess.run(['mcopy',*target,str(path),'::'+name],check=True)


def run_edit(root,media,manifest,work,sym,artifacts,image,emulator,send,wait,read,key,move,case):
    from test_cpc_runtime_1984 import integrity,run
    rects={1:(11,66,58,68)};order=[0,1];accents={1:0}
    menu=b'\0';titles={};calculators={};clocks={};clock_slot=None
    checks=[];stacks=dict(main=0,irq=0,tmp=0)
    noi={v[1]:int(v[2],16) for line in (root/'build/universal-obj/uclock/app.noi').read_text().splitlines()
         if len(v:=line.split())==3 and v[0]=='DEF'}
    offsets={v[1]:int(v[2],16) for line in (root/'build/universal-obj/uclock/main.sym').read_text().splitlines()
             if len(v:=line.split())==4 and v[0]=='1' and v[3]=='R'}
    theme=DEFAULT_THEME
    weave=(root/'assets/titlebars/WEAVE.TBR').read_bytes()+DEFAULT_THEME[56:]
    if case=='reboot': theme=weave
    target=['-i',str(image)+'@@16384']
    def disk():
        result=subprocess.run(['mtype',*target,'::/GEOBENCH.CFG'],capture_output=True)
        if result.returncode:
            if case=='missing': return None
            raise AssertionError('cannot read private config: '+result.stderr.decode())
        return result.stdout
    expected=disk();initial=image.read_bytes()
    def word(r,name): return int.from_bytes(r[sym[name]:sym[name]+2],'little')
    def clock_value(r,name):
        at=physical(r[sym['wm_table']+25*clock_slot])+noi['s__DATA']-0x4000+offsets['_'+name]
        return r[at]
    def observe(name):
        previous=None
        for _ in range(180):
            data=read(name);_,r=snapshot(data)
            if r[sym['pointer_visible']] and not r[sym['io_busy']] and not r[sym['core_pointer_paintlock']]:
                if clock_slot is None or clock_cache_ready(lambda k:clock_value(r,k)):
                    signature=bytes(r[0xC000:0x10000]);turn=word(r,'cpc_runtime_turns')
                    if previous and signature==previous[0] and turn!=previous[1]: break
                    previous=signature,turn
            wait(3)
        else: raise AssertionError(name+': draw did not complete')
        r,used=integrity(data,sym,work,theme=theme)
        for k,n in used.items(): stacks[k]=max(stacks[k],n)
        if clock_slot is not None:
            clocks[clock_slot]=tuple(clock_value(r,k) for k in ('ph','pm','ps','show_sec','dh','dm','ds'))
        verify_pixels(r,sym,work,rects,order,accents,menu,titles,calculators=calculators,clocks=clocks,theme=theme)
        if r[sym['wm_nwin']]!=len(order) or r[sym['wm_z']:sym['wm_z']+len(order)]!=bytes(order):
            raise AssertionError('configuration edit changed window lifecycle')
        if r[sym['ui_modal']] or any(r[sym['core_fsctx_table']+i*144] for i in range(4)):
            raise AssertionError('configuration context/modal leak')
        if word(r,'cpc_edit_calls'):
            owner=r[sym['core_win_owner']] | r[sym['core_win_owner_gen']]<<8
            if word(r,'cpc_ui_owner')!=owner: raise AssertionError('edit lost original caller identity')
        if disk()!=expected: raise AssertionError('configuration bytes differ from expected edit')
        checks.append(name);send(f'crop {artifacts/(name+".ppm")} 0 0 768 576 1')
        print(f'{name}: stack={stacks}',flush=True)
        return r
    def accepted(r,changed):
        if r[sym['cpc_edit_status']] or r[sym['cpc_ui_request']+4]!=1 or \
           r[sym['cpc_edit_changed']]!=changed or r[sym['cpc_edit_error']]:
            raise AssertionError('config persistence/reload did not succeed: '+
                                 str(tuple(r[sym[k]] for k in ('cpc_edit_status','cpc_edit_changed','cpc_edit_error'))))
        n=word(r,'cpc_cfg_output')
        if n!=len(expected) or r[sym['cpc_cfg_text']:sym['cpc_cfg_text']+n]!=expected:
            raise AssertionError('live configuration was not published after verification')
    observe('config-edit-boot')
    move(76,185);key('SPACE');menu=bytes((1,10))+b'Desk\0\0\0\0'
    r=observe('config-edit-root')
    failure=1 if case.startswith('module-') else 3 if case in ('missing','empty','oversized') else \
            4 if case in ('long-value','unterminated-append','no-space') else 0
    reboot_artifacts=None
    if failure:
        live=r[sym['cpc_cfg_text']:sym['cpc_cfg_text']+word(r,'cpc_cfg_output')]
        key('W');r=observe('config-edit-rejected')
        if r[sym['cpc_edit_status']]!=failure or r[sym['cpc_ui_request']+4] or r[sym['cpc_edit_changed']]:
            raise AssertionError('wrong edit rejection '+str(r[sym['cpc_edit_status']]))
        if image.read_bytes()!=initial: raise AssertionError('rejected edit wrote the image')
        if live!=r[sym['cpc_cfg_text']:sym['cpc_cfg_text']+word(r,'cpc_cfg_output')]:
            raise AssertionError('rejected edit published configuration')
    elif case=='reboot':
        if b'TITLEBAR=WEAVE' not in expected: raise AssertionError('saved config lost across reboot')
        key('W');r=observe('config-edit-reboot-noop');accepted(r,0)
        if image.read_bytes()!=initial: raise AssertionError('reboot/no-op rewrote disk')
    else:
        expected=replace_value(expected,b'WEAVE');key('W');theme=weave
        r=observe('config-edit-saved-weave');accepted(r,1)
        saved=image.read_bytes();draws=word(r,'cpc_runtime_draw_calls');calls=word(r,'cpc_visual_calls')
        key('W');r=observe('config-edit-noop');accepted(r,0)
        if image.read_bytes()!=saved or word(r,'cpc_visual_calls')!=calls+1 or \
           r[sym['cpc_visual_dirty']] or word(r,'cpc_runtime_draw_calls')!=draws:
            raise AssertionError('no-op caused write/repaint or skipped reload')
        expected=replace_value(expected,b'ORIGINAL');key('E');theme=DEFAULT_THEME
        r=observe('config-edit-restored-original');accepted(r,1)
    key('F7');rects[2]=(24,24,31,144);order.append(2);titles[2]='Calculator';calculators[2]='0'
    menu=bytes((1,10))+b'Edit\0\0\0\0';observe('config-edit-calculator')
    key('7');key('2');calculators[2]='72';observe('config-edit-calculator-value')
    move(76,185);key('SPACE');menu=bytes((1,10))+b'Desk\0\0\0\0'
    if case=='normal':
        expected=replace_value(expected,b'WEAVE');key('W');theme=weave
        r=observe('config-edit-live-application');accepted(r,1)
        key('F2');rects[3]=(26,20,28,122);order.append(3);titles[3]='Clock';clock_slot=3
        menu=bytes((2,10))+b'View\0\0\0\0'+bytes((17,))+b'Options\0'
        observe('config-edit-clock');key('S')
        move(76,185);key('SPACE');menu=bytes((1,10))+b'Desk\0\0\0\0'
        r=observe('config-edit-background-clock');workers=word(r,'cpc_runtime_worker_calls')
        expected=replace_value(expected,b'ORIGINAL');key('E');theme=DEFAULT_THEME
        r=observe('config-edit-with-live-worker');accepted(r,1)
        expected=replace_value(expected,b'WEAVE');key('W');theme=weave
        r=observe('config-edit-worker-resumed');accepted(r,1)
        if word(r,'cpc_runtime_worker_calls')==workers: raise AssertionError('worker failed to resume after editing')
        # Start a second clean emulator from a COPY of the successfully saved
        # private image. Never mutate the first emulator's mounted filesystem.
        reboot_artifacts=run(emulator=emulator,skip_build=True,config_edit='reboot',seed_image=image)
    key('F4');r=observe('config-edit-filesystem-recovery')
    if r[sym['cpc_runtime_fs_status']]: raise AssertionError('filesystem did not recover')
    report=dict(case=case,checkpoints=checks,stack=stacks,sections=manifest['sections'],
                config_sha256=hashlib.sha256(expected or b'').hexdigest(),
                reboot_artifacts=str(reboot_artifacts) if reboot_artifacts else None)
    (artifacts/'result.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS Settings configuration persistence '+json.dumps(report),flush=True)
    return artifacts
