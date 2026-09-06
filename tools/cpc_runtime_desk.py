"""Actual Desktop/gb_doc/gb_popup integration on M4, without guest RAM writes."""
import hashlib
import json
from pathlib import Path
from cpc_production_lifetime import physical
from cpc_runtime_pixels import verify_pixels
from test_cpc_foundation_1984 import snapshot

DESK=bytes((1,10))+b'Desk\0\0\0\0'
EDIT=bytes((1,10))+b'Edit\0\0\0\0'
CLOCK=bytes((2,10))+b'View\0\0\0\0'+bytes((17,))+b'Options\0'
LABELS=('Clock','Calculator')


def run_desk(root,media,manifest,work,sym,artifacts,image,emulator,send,wait,read,key,move):
    from test_cpc_runtime_1984 import integrity
    noi={v[1]:int(v[2],16) for line in (root/'build/universal-obj/uclock/app.noi').read_text().splitlines()
         if len(v:=line.split())==3 and v[0]=='DEF'}
    offsets={v[1]:int(v[2],16) for line in (root/'build/universal-obj/uclock/main.sym').read_text().splitlines()
             if len(v:=line.split())==4 and v[0]=='1' and v[3]=='R'}
    rects={1:(11,66,58,68)};order=[0,1];accents={1:0};focus=1
    titles={};calculators={};clocks={};clock_slot=None;menu=b'\0';popup=None
    checks=[];stack={'main':0,'irq':0,'tmp':0}
    def word(r,name): return int.from_bytes(r[sym[name]:sym[name]+2],'little')
    def value(r,name):
        base=physical(r[sym['wm_table']+25*clock_slot])
        return r[base+noi['s__DATA']-0x4000+offsets['_'+name]]
    def checked(name):
        previous=None
        for _ in range(150):
            data=read(name);_,r=snapshot(data)
            if r[sym['sched_fault']]: raise AssertionError('scheduler fault')
            if r[sym['pointer_visible']] and not any(r[sym[n]] for n in
                    ('core_pointer_paintlock','core_param_timer_owner','io_busy')):
                if clock_slot is None or (value(r,'have_prev') and not value(r,'timer_digit_due') and
                    (value(r,'ph'),value(r,'pm'))==(value(r,'dh'),value(r,'dm')) and
                    (not value(r,'show_sec') or value(r,'ps')==value(r,'ds'))):
                    signature=bytes(r[0xC000:0x10000])+bytes(r[0x1240:0x1242])
                    # Modal polling intentionally does not re-enter the root
                    # loop/worker dispatcher; otherwise require root progress.
                    turn=word(r,'cpc_runtime_turns')
                    if previous and signature==previous[0] and (popup is not None or turn!=previous[1]):
                        r,used=integrity(data,sym,work)
                        for k,n in used.items(): stack[k]=max(stack[k],n)
                        break
                    previous=(signature,turn)
            wait(3)
        else: raise AssertionError(name+': incomplete drawing')
        if clock_slot is not None:
            clocks[clock_slot]=tuple(value(r,k) for k in ('ph','pm','ps','show_sec'))
        verify_pixels(r,sym,work,rects,order,accents,menu,titles,popup,calculators,clocks)
        if r[sym['wm_focus']]!=focus or r[sym['wm_nwin']]!=len(order):
            raise AssertionError(name+': focus/window count')
        if r[sym['wm_z']:sym['wm_z']+len(order)]!=bytes(order): raise AssertionError(name+': z order')
        for slot,rect in rects.items():
            at=sym['wm_table']+25*slot+1
            if r[at:at+4]!=bytes(rect): raise AssertionError(name+': geometry')
        send(f'crop {artifacts/(name+".ppm")} 0 0 768 576 1')
        checks.append(name)
        print(f'{name}: focus={focus} windows={len(order)} stack={stack}',flush=True)
        return r
    def owner(r,slot):
        return bytes((r[sym['core_win_owner']+slot],r[sym['core_win_owner_gen']+slot]))
    def click(root_turns=True):
        # Real held input, released after the actual CPC poll observes it.
        # Fixed short pulses can fall entirely inside Clock's software draw.
        for command,held in (('key-down SPACE',True),('key-up SPACE',False)):
            send(command)
            for _ in range(150):
                wait(3);_,r=snapshot(read())
                if bool(r[sym['poll_lastfire']])==held: break
            else: raise AssertionError('CPC did not sample '+command)
        if root_turns:
            before=word(r,'cpc_runtime_turns')
            for _ in range(150):
                wait(3);_,r=snapshot(read())
                if (word(r,'cpc_runtime_turns')-before)&65535>=5: break
            else: raise AssertionError('root did not resume after click')
    def root_focus():
        nonlocal focus,menu
        move(76,185);click();focus=0;menu=DESK
    def open_menu():
        nonlocal popup
        move(12,3);click(False)
        popup=dict(x=10,y=8,hot=-1,labels=LABELS)
    def select(index):
        nonlocal popup
        move(13,13+10*index);click();popup=None
    def focused(slot,definition):
        nonlocal focus,menu
        order.remove(slot);order.append(slot);focus=slot;menu=definition

    root_focus();checked('desk-root-focus')
    open_menu();checked('desk-popup')
    move(13,23);popup['hot']=1;checked('desk-calculator-hover')
    key('ESCAPE');popup=None;checked('desk-cancel-restores')
    open_menu();select(1)
    rects[2]=(24,24,31,144);order.append(2);focus=2;menu=EDIT
    titles[2]='Calculator';calculators[2]='0';r=checked('desk-launch-calculator')
    calc_owner=owner(r,2)
    key('7');key('2');calculators[2]='72';checked('desk-calculator-input')
    root_focus();open_menu();select(0)
    rects[3]=(26,20,28,122);order.append(3);focus=3;menu=CLOCK
    titles[3]='Clock';clock_slot=3;r=checked('desk-launch-clock')
    clock_owner=owner(r,3)
    key('S');r=checked('desk-clock-seconds')
    if not value(r,'show_sec'): raise AssertionError('seconds key did not reach Clock')
    root_focus();r=checked('desk-clock-background')
    before=word(r,'cpc_runtime_worker_calls');wait(150);r=checked('desk-background-tick')
    if word(r,'cpc_runtime_worker_calls')==before: raise AssertionError('background Clock did not run')
    open_menu();r=checked('desk-popup-over-live-clock')
    before=word(r,'cpc_runtime_worker_calls');wait(150);r=checked('desk-modal-save-under-stable')
    if word(r,'cpc_runtime_worker_calls')!=before: raise AssertionError('worker changed modal save-under')
    # Title re-click follows gb_doc_event -> gb_popup_close, not a second menu.
    move(12,3);click();popup=None;checked('desk-title-reclick-cancels')
    open_menu();move(73,175);click();popup=None;checked('desk-click-away-cancels')
    open_menu();select(0);focused(3,CLOCK);r=checked('desk-reactivate-clock')
    if owner(r,3)!=clock_owner or not value(r,'show_sec'): raise AssertionError('Clock identity/state changed')
    root_focus();open_menu();select(1);focused(2,EDIT);r=checked('desk-reactivate-calculator')
    if owner(r,2)!=calc_owner: raise AssertionError('Calculator identity changed')
    # Closing and relaunching must clear registration and advance generation.
    key('ESCAPE');del rects[2];del calculators[2];order.remove(2);focus=3;menu=CLOCK
    r=checked('desk-calculator-close')
    idx=calc_owner[0]-1
    if r[sym['core_app_accessory']+idx] or r[sym['core_app_service']+idx]:
        raise AssertionError('closed Calculator service leaked')
    root_focus();open_menu();select(1)
    rects[2]=(24,24,31,144);order.append(2);focus=2;menu=EDIT;calculators[2]='0'
    r=checked('desk-calculator-fresh-owner')
    if owner(r,2)==calc_owner: raise AssertionError('stale owner generation reused')
    for slot in range(4,8):
        key('F3');rects[slot]=(11,66,58,68);order.append(slot);accents[slot]=0
    focus=7;menu=b'\0';checked('desk-full-window-table')
    root_focus();open_menu();select(0);focused(3,CLOCK);r=checked('desk-activate-clock-while-full')
    if owner(r,3)!=clock_owner or not value(r,'show_sec'): raise AssertionError('full-table activation failed')
    root_focus();open_menu();select(1);focused(2,EDIT);checked('desk-activate-calculator-while-full')
    # Remove Clock, consume its slot with another ordinary APP, then prove the
    # real full-capacity alert unwinds without duplicate owners or stale menus.
    root_focus();open_menu();select(0);focused(3,CLOCK)
    key('ESCAPE');del rects[3];del clocks[3];del titles[3];order.remove(3);clock_slot=None
    focus=2;menu=EDIT;checked('desk-clock-close')
    key('F3');rects[3]=(11,66,58,68);order.append(3);accents[3]=0;focus=3;menu=b'\0'
    root_focus();open_menu();move(13,13);click(False)
    popup=dict(x=23,y=84,hot=-1,labels=('Sorry, not enough RAM','to run more apps.'))
    checked('desk-full-capacity-alert')
    key('ESCAPE');popup=None;checked('desk-capacity-alert-dismissed')
    root_focus();open_menu();select(1);focused(2,EDIT);checked('desk-activation-after-alert')
    key('F4');r=checked('desk-M4-service')
    if r[sym['cpc_runtime_fs_status']] or r[sym['cpc_runtime_fs_calls']]!=1:
        raise AssertionError('M4 service failed')
    if image.read_bytes()!=Path(manifest['image']).read_bytes(): raise AssertionError('read-only M4 run changed files')
    report=dict(checkpoints=checks,stack=stack,sections=manifest['sections'],
                root_sha256=hashlib.sha256((work/'ROOTBAR.BIN').read_bytes()).hexdigest(),
                emulator_sha256=hashlib.sha256(emulator.read_bytes()).hexdigest())
    (artifacts/'result.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS shared Desktop Desk menu '+json.dumps(report),flush=True)
    return artifacts
