"""Shared native chooser on a private M4 image; real input, read-only observations."""
import json
from cpc_production_lifetime import physical
from cpc_runtime_pixels import verify_pixels
from cpc_runtime_clock import clock_cache_ready
from test_cpc_foundation_1984 import snapshot


def run_picker(root,manifest,work,sym,artifacts,send,wait,read,key,move,fault=None):
    from test_cpc_runtime_1984 import integrity
    rects={1:(11,66,58,68)};order=[0,1];accents={1:0}
    menu=b'\0';titles={};clocks={};slot=None;popup=None
    checks=[];stacks={'main':0,'irq':0,'tmp':0}
    noi={v[1]:int(v[2],16) for line in (root/'build/universal-obj/uclock/app.noi').read_text().splitlines()
         if len(v:=line.split())==3 and v[0]=='DEF'}
    offsets={v[1]:int(v[2],16) for line in (root/'build/universal-obj/uclock/main.sym').read_text().splitlines()
             if len(v:=line.split())==4 and v[0]=='1' and v[3]=='R'}
    def word(r,name): return int.from_bytes(r[sym[name]:sym[name]+2],'little')
    def value(r,name):
        at=physical(r[sym['wm_table']+25*slot])+noi['s__DATA']-0x4000+offsets['_'+name]
        return r[at]
    def observe(name):
        modal=popup is not None;previous=None
        for _ in range(180):
            data=read(name);_,r=snapshot(data)
            if r[sym['pointer_visible']] and not r[sym['core_pointer_paintlock']] and not r[sym['io_busy']]:
                if slot is None or clock_cache_ready(lambda k:value(r,k),modal):
                    signature=bytes(r[0xC000:0x10000])+bytes(r[0x1240:0x1242])
                    turn=word(r,'cpc_runtime_turns')
                    if previous and signature==previous[0] and (modal or turn!=previous[1]): break
                    previous=signature,turn
            wait(3)
        else: raise AssertionError(name+': draw not complete')
        r,used=integrity(data,sym,work)
        for k,n in used.items(): stacks[k]=max(stacks[k],n)
        if bool(r[sym['ui_modal']])!=modal: raise AssertionError(name+': modal gate')
        if slot is not None: clocks[slot]=tuple(value(r,k) for k in ('ph','pm','ps','show_sec','dh','dm','ds'))
        verify_pixels(r,sym,work,rects,order,accents,menu,titles,popup,clocks=clocks)
        if r[sym['wm_nwin']]!=len(order) or r[sym['wm_z']:sym['wm_z']+len(order)]!=bytes(order):
            raise AssertionError(name+': modal changed window lifecycle')
        active=[sym['core_fsctx_table']+144*i for i in range(4) if r[sym['core_fsctx_table']+144*i]]
        if len(active)!=int(modal): raise AssertionError(name+': context leak/count '+str(active))
        if modal:
            owner=word(r,'cpc_ui_owner')
            root_owner=r[sym['core_win_owner']] | r[sym['core_win_owner_gen']]<<8
            if not owner or owner!=root_owner or \
               int.from_bytes(r[active[0]+2:active[0]+4],'little')!=owner:
                raise AssertionError(name+': context does not belong to original caller')
            raw=(work/'GBPICK.MOD').read_bytes();at=physical(sym['cpc_system_page'])
            if r[at:at+len(raw)]!=raw: raise AssertionError('picker code corrupted')
        checks.append(name);print(f'{name}: stack={stacks}',flush=True)
        send(f'crop {artifacts/(name+".ppm")} 0 0 768 576 1')
        return r
    def pulse(name):
        field='in_quit' if name=='ESCAPE' else 'poll_lastfire' if name=='SPACE' else 'cpc_key_previous'
        target=4 if name=='ESCAPE' else 32 if name=='SPACE' else ord(name.lower())
        for command,wanted in (('key-down '+name,target),('key-up '+name,0)):
            send(command)
            for _ in range(180):
                wait(3);_,r=snapshot(read())
                if not wanted and name in ('O','D'):
                    row,bit=(4,2) if name=='O' else (7,5)
                    if r[sym['cpc_keys']+row] & (1<<bit): break
                elif r[sym[field]]==wanted: break
            else: raise AssertionError('input not acknowledged: '+command)
        wait(15)
    def show(labels):
        nonlocal popup
        popup=dict(x=10,y=8,hot=-1,labels=labels)
    def choose(row,labels=None):
        nonlocal popup
        move(12,12+row*10);pulse('SPACE')
        if labels is None: popup=None
        else:
            show(labels)
            # New popup polls the current pointer before observation.
            popup['hot']=row if row<len(labels) else -1
        wait(15)
    def selected(r,path,name=None):
        at=sym['cpc_pick_path']
        if bytes(r[at:at+48]).split(b'\0',1)[0]!=path.encode(): raise AssertionError('selected path')
        if r[sym['cpc_ui_request']+4]!=1 or r[sym['cpc_pick_status']]: raise AssertionError('selection status')
        if word(r,'cpc_pick_owner')!=word(r,'cpc_ui_owner'): raise AssertionError('path owner')
        if name is not None:
            at=sym['cpc_ui_request']+8
            if r[at:at+11]!=name: raise AssertionError('selected raw 8.3 name')

    observe('picker-boot')
    move(76,185);key('SPACE');menu=bytes((1,10))+b'Desk\0\0\0\0'
    initial=observe('picker-root-focus');initial_workers=word(initial,'cpc_runtime_worker_calls')
    if fault:
        before=word(snapshot(read())[1],'cpc_ui_calls')
        key('O');r=observe('picker-module-rejected')
        if r[sym['cpc_ui_status']]!=1 or r[sym['cpc_ui_request']+4]!=0 or \
           word(r,'cpc_ui_calls')!=before+1 or word(r,'cpc_pick_probe_bytes'):
            raise AssertionError('invalid picker module did not cancel')
        key('F2');rects[2]=(26,20,28,122);order.append(2);titles[2]='Clock';slot=2
        menu=bytes((2,10))+b'View\0\0\0\0'+bytes((17,))+b'Options\0'
        observe('picker-module-failure-clock-recovery')
    else:
        top=('..','GBENCH/','UFSTEST/','PICKTEST/')
        folder=('..','INNER/','EMPTY/','NOTES.TXT')
        pulse('O');show(top);r=observe('picker-root')
        frozen=word(r,'cpc_runtime_worker_calls');wait(100);r=observe('picker-worker-parked')
        if word(r,'cpc_runtime_worker_calls')!=frozen: raise AssertionError('worker ran in picker bank')
        choose(3,folder);observe('picker-filtered-folder')
        choose(2,('..',));observe('picker-empty-folder')
        choose(0,folder);observe('picker-parent')
        choose(1,('..','HELLO.TXT'));observe('picker-nested-folder')
        choose(1);r=observe('picker-open-readback')
        selected(r,'/PICKTEST/INNER',b'HELLO   TXT')
        expected=b'Picked from M4!\n';at=sym['cpc_pick_probe_data']
        if word(r,'cpc_pick_probe_bytes')!=len(expected) or r[at:at+len(expected)]!=expected:
            raise AssertionError('selected file could not be read after modal return')
        move(76,185);pulse('D');show(('..','[Save here]','HELLO.TXT'))
        observe('picker-destination-starts-at-last-path')
        choose(2,('..','[Save here]','HELLO.TXT'));observe('picker-destination-ignores-file')
        choose(0,('..','[Save here]','INNER/','EMPTY/','NOTES.TXT'));observe('picker-destination-parent')
        choose(3,('..','[Save here]'));observe('picker-empty-destination')
        choose(1);r=observe('picker-destination-selected');selected(r,'/PICKTEST/EMPTY')
        move(76,185);pulse('O');show(top);observe('picker-open-resets-root')
        pulse('ESCAPE');popup=None;r=observe('picker-cancel-restored')
        if r[sym['cpc_ui_request']+4] or word(r,'cpc_pick_probe_bytes'): raise AssertionError('cancel accepted')
        key('F2');rects[2]=(26,20,28,122);order.append(2);titles[2]='Clock';slot=2
        menu=bytes((2,10))+b'View\0\0\0\0'+bytes((17,))+b'Options\0'
        observe('picker-clock');key('S')
        move(76,185);key('SPACE');menu=bytes((1,10))+b'Desk\0\0\0\0'
        observe('picker-background-clock')
        for i in range(5):
            pulse('O');show(top);r=observe(f'picker-repeat-{i}')
            workers=word(r,'cpc_runtime_worker_calls');hands=clocks[slot];wait(100)
            r=observe(f'picker-clock-parked-{i}')
            if word(r,'cpc_runtime_worker_calls')!=workers or clocks[slot]!=hands:
                raise AssertionError('background work ran during picker')
            pulse('ESCAPE');popup=None;observe(f'picker-repeat-restored-{i}')
    key('F4');r=observe('picker-M4-after-dialogs')
    if r[sym['cpc_runtime_fs_status']]: raise AssertionError('filesystem did not recover')
    if word(r,'cpc_runtime_worker_calls')==initial_workers: raise AssertionError('worker failed to resume')
    report=dict(checkpoints=checks,stack=stacks,sections=manifest['sections'],picker_fault=fault)
    (artifacts/'result.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS native picker '+json.dumps(report),flush=True)
    return artifacts
