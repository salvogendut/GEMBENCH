"""Actual native File Manager lifecycle through Desktop input on private M4."""
import json
from pathlib import Path
import subprocess
import zlib

from cpc_filemgr_pixels import listing
from cpc_runtime_desktop import DESKTOP,EDIT,CLOCK
from cpc_runtime_clock import clock_cache_ready, clock_may_remain_parked
from cpc_runtime_configedit import replace_value
from cpc_runtime_pixels import verify_pixels
from cpc_production_lifetime import physical
from cpc_fswrite_cases import space
from test_cpc_foundation_1984 import snapshot


def prepare(case,work,sym,image,artifacts):
    """Change disk fixtures only. No injected guest RAM or patched emulator."""
    raw=(work/'filemgr/FILEMGR.native.bin').read_bytes()
    kernel=bytearray((work/'CORE.RAW').read_bytes())
    payload=raw
    if case=='missing': payload=None
    elif case=='short': payload=raw[:-1]
    elif case=='oversized': payload=raw.ljust(0x3F01,b'\0')
    elif case=='corrupt': payload=raw[:-1]+bytes((raw[-1]^1,))
    elif case=='no-register': payload=b'\xC9'+raw[1:] # trusted test executable returns before registration
    elif case!='unbound': raise ValueError(case)
    at=sym['cpc_filemgr_contract']-0x8000
    if case=='unbound': kernel[at:at+6]=bytes(6)
    elif case=='no-register': kernel[at:at+6]=len(payload).to_bytes(2,'little')+zlib.crc32(payload).to_bytes(4,'little')
    target=['-i',str(image)+'@@16384']
    subprocess.run(['mdel',*target,'::/GBENCH/FILEMGR.BIN'],check=True)
    if payload is not None:
        file=artifacts/'FILEMGR.BIN';file.write_bytes(payload)
        subprocess.run(['mcopy',*target,str(file),'::/GBENCH/FILEMGR.BIN'],check=True)
    if case in ('unbound','no-register'):
        file=artifacts/'CORE.BIN';file.write_bytes(kernel)
        subprocess.run(['mcopy','-o',*target,str(file),'::/CORE.BIN'],check=True)
    return bytes(kernel)


def run_filemgr(root,manifest,work,sym,artifacts,send,wait,read,key,move,case=None,kernel=None,scenario=None):
    from test_cpc_runtime_1984 import integrity
    app=work/'filemgr'
    noi={v[1]:int(v[2],16) for line in (app/'filemgr.noi').read_text().splitlines()
         if len(v:=line.split())==3 and v[0]=='DEF'}
    offsets={v[1]:int(v[2],16)+(noi['s__INITIALIZED']-noi['s__DATA'] if v[0]=='2' else 0)
             for line in (app/'main.sym').read_text().splitlines()
             if len(v:=line.split())==4 and v[0] in ('1','2') and v[3]=='R'}
    icons=(work/'REFINED.IST').read_bytes();raw=(app/'FILEMGR.native.bin').read_bytes()
    items=listing(manifest['files']);rects={};order=[0];fms={};titles={};accents={}
    focus=0;menu=DESKTOP;popup=None;calculators={};clocks={};clock_slot=None
    checks=[];stack=dict(main=0,irq=0,tmp=0);unpublished=set()
    clock_noi={v[1]:int(v[2],16) for line in (root/'build/universal-obj/uclock/app.noi').read_text().splitlines()
               if len(v:=line.split())==3 and v[0]=='DEF'}
    clock_offsets={v[1]:int(v[2],16) for line in (root/'build/universal-obj/uclock/main.sym').read_text().splitlines()
                   if len(v:=line.split())==4 and v[0]=='1' and v[3]=='R'}
    free=space(Path(manifest['image']))[0]
    def title(path=''):
        suffix=f' {free//1024}MiB free'
        return ('Disk C'+path)[:23-len(suffix)]+suffix
    def word(r,name): return int.from_bytes(r[sym[name]:sym[name]+2],'little')
    def field(r,slot,name,n=1):
        base=physical(r[sym['wm_table']+25*slot])+noi['s__DATA']-0x4000
        return r[base+offsets['_'+name]:base+offsets['_'+name]+n]
    def clock_value(r,name):
        base=physical(r[sym['wm_table']+25*clock_slot])+clock_noi['s__DATA']-0x4000
        return r[base+clock_offsets['_'+name]]
    def checked(name):
        previous=None
        for _ in range(350):
            data=read(name);_,r=snapshot(data)
            ready=all(field(r,s,'list_state')==b'\0' for s in fms)
            if popup is not None:
                labels=b''.join(label.encode()+b'\0' for label in popup['labels'])
                ready=ready and r[sym['cpc_ui_request']+3]==len(popup['labels']) and \
                    r[sym['cpc_ui_text']:sym['cpc_ui_text']+len(labels)]==labels
            if clock_slot is not None:
                ready=ready and not r[sym['core_param_timer_owner']] and (
                    clock_may_remain_parked(rects,order,clock_slot,r[sym['cpc_wm_visibility']+clock_slot],r[sym['cpc_task_visibility']+clock_slot]) or
                    clock_cache_ready(lambda k:clock_value(r,k),popup is not None))
            if ready and r[sym['pointer_visible']] and not any(r[sym[k]] for k in ('io_busy','core_pointer_paintlock')) and bool(r[sym['ui_modal']])==(popup is not None):
                sig=bytes(r[0xC000:0x10000])+bytes(r[sym['menu_def']:sym['menu_def']+37])
                turn=word(r,'cpc_runtime_turns')
                if previous and sig==previous[0] and (popup is not None or (turn-previous[1])&65535>=2): break
                if previous is None or sig!=previous[0]: previous=sig,turn
            wait(5)
        else: raise AssertionError(name+': File Manager/root did not settle')
        r,used=integrity(data,sym,work,kernel=kernel)
        for k,n in used.items(): stack[k]=max(stack[k],n)
        if r[sym['wm_nwin']]!=len(order) or r[sym['wm_focus']]!=focus or r[sym['wm_z']:sym['wm_z']+len(order)]!=bytes(order):
            raise AssertionError(name+': window ownership/order')
        if word(r,'core_pending_owner') or any(r[sym['launch_arg']:sym['launch_arg']+11]):
            raise AssertionError('pending launch identity/argument leaked')
        if r[sym['core_page_free']]!=27-len(order): raise AssertionError('application page leak')
        contexts=[r[sym['core_fsctx_table']+i*144:sym['core_fsctx_table']+(i+1)*144] for i in range(4)]
        live=[c for c in contexts if c[0]]
        if len(live)!=len(fms): raise AssertionError('filesystem context leak')
        for slot in fms:
            path=fms[slot].get('path','');expected=listing(manifest['files'],path)
            base=physical(r[sym['wm_table']+25*slot])
            if r[base:base+len(raw)]!=raw: raise AssertionError('native File Manager code changed')
            owner=bytes((r[sym['core_win_owner']+slot],r[sym['core_win_owner_gen']+slot]))
            if sum(c[2:4]==owner for c in live)!=1: raise AssertionError('context not owned by its window')
            if field(r,slot,'total')[0]!=len(expected) or field(r,slot,'fm_path',40).split(b'\0',1)[0].decode()!=path: raise AssertionError('listing/path')
            names=field(r,slot,'names',11*len(expected));indices=field(r,slot,'order',len(expected))
            got=[]
            for i in indices:
                n=names[i*11:i*11+11];got.append(n[:8].decode().rstrip()+('.'+n[8:].decode().rstrip() if n[8:]!=b'   ' else ''))
            if got!=[n for n,_ in expected]: raise AssertionError('directory contents/order: '+repr(got))
            if field(r,slot,'title_buf',24).split(b'\0',1)[0].decode()!=title(path): raise AssertionError('title/free space')
            # A failed View save shows its modal over the old pixels before
            # fm_set_view returns and redraws the newly selected session view.
            if popup is None and (field(r,slot,'top')!=bytes((fms[slot].get('top',0),)) or field(r,slot,'view')!=bytes((fms[slot].get('view',1),))):
                raise AssertionError('File Manager view/scroll state differs')
        if clock_slot is not None:
            clocks[clock_slot]=tuple(clock_value(r,k) for k in ('ph','pm','ps','show_sec','dh','dm','ds'))
        painted_order=[slot for slot in order if slot not in unpublished]
        verify_pixels(r,sym,work,rects,painted_order,accents,menu,titles,popup=popup,desktop=icons,filemanagers=fms,calculators=calculators,clocks=clocks)
        checks.append(name);send(f'crop {artifacts/(name+".ppm")} 0 0 768 576 1')
        print(f'{name}: windows={len(order)} contexts={len(live)} stack={stack}',flush=True)
        return r
    def click():
        for command,held in (('key-down SPACE',True),('key-up SPACE',False)):
            send(command)
            for _ in range(180):
                wait(3);_,r=snapshot(read())
                if bool(r[sym['poll_lastfire']])==held: break
            else: raise AssertionError('click not sampled')
    def disk_click():
        move(76,190);click();wait(10)
        move(3,26);click();click()
    def open_disk(slot):
        nonlocal focus,menu
        disk_click()
        rects[slot]=(4,26,56,158);order.append(slot);focus=slot
        fms[slot]=dict(items=items);titles[slot]=title()
        menu=bytes((1,10))+b'View\0\0\0\0'
    def close_fm(slot):
        nonlocal focus,menu
        key('ESCAPE');order.remove(slot);del fms[slot];del rects[slot];del titles[slot]
        focus=order[-1];menu=bytes((1,10))+b'View\0\0\0\0' if focus else DESKTOP
    def open_item(slot,name):
        """Use the listing oracle, not diagnostic-image-specific icon positions."""
        fm=fms[slot];index=[n for n,_ in fm['items']].index(name)
        x,y,w,h=rects[slot];top=fm.get('top',0)
        if fm.get('view',1):
            row,col=divmod(index,3);cx=x+4+col*((w-5)//3)+6;cy=y+20+(row-top)*44
        else:
            row=index;cx=x+12;cy=y+20+(row-top)*18
        if not y+14<=cy<y+h-1: raise AssertionError('item is not visible: '+name)
        move(cx,cy);click();click()
    def finish():
        report=dict(scenario=scenario or case or 'lifecycle',checkpoints=checks,stack=stack,sections=manifest['sections'])
        (artifacts/'result.json').write_text(json.dumps(report,indent=2)+'\n')
        print('PASS native File Manager '+json.dumps(report),flush=True)
        return artifacts
    def choose_desk(index):
        move(76,190);click();wait(10)
        move(11,3);click();wait(12);move(12,13+index*10);click()
    def drag(slot,x,y):
        ox,oy,w,h=rects[slot]
        move(ox+10,oy+5);_,r=snapshot(read());grab=(r[sym['poll_byte']],r[sym['poll_line']])
        send('key-down SPACE');wait(10);move(grab[0]+x-ox,grab[1]+y-oy)
        _,r=snapshot(read());drop=(r[sym['poll_byte']],r[sym['poll_line']])
        send('key-up SPACE');wait(60)
        rects[slot]=(max(0,min(80-w,ox+drop[0]-grab[0])),max(8,min(200-h,oy+drop[1]-grab[1])),w,h)
        _,r=snapshot(read());at=sym['wm_table']+25*slot+1
        if r[at:at+4]!=bytes(rects[slot]): raise AssertionError('drag differs from pointer displacement')
    checked('filemgr-root')
    if scenario=='reboot':
        before=(artifacts/'RUNTIME.IMG').read_bytes()
        open_disk(1);fms[1]['view']=0;checked('reboot-persisted-list')
        open_item(1,'GBENCH')
        fms[1]=dict(items=[('..',14)]+listing(manifest['files'],'/GBENCH'),path='/GBENCH',view=0)
        titles[1]=title('/GBENCH');checked('reboot-list-directory')
        open_item(1,'..');fms[1]=dict(items=items,view=0);titles[1]=title()
        checked('reboot-list-parent')
        close_fm(1);checked('reboot-list-close')
        if (artifacts/'RUNTIME.IMG').read_bytes()!=before: raise AssertionError('reboot read-only browsing wrote disk')
        return finish()
    if scenario=='workflow':
        view_menu=bytes((1,10))+b'View\0\0\0\0'
        def directory(slot,path):
            fms[slot]=dict(items=([('..',14)] if path else [])+listing(manifest['files'],path),path=path)
            titles[slot]=title(path)
        open_disk(1);checked('workflow-disk')
        open_item(1,'GBENCH');directory(1,'/GBENCH');checked('workflow-directory')
        open_item(1,'CALC.APP')
        rects[2]=(24,24,31,144);order.append(2);focus=2;menu=EDIT
        titles[2]='Calculator';calculators[2]='0';checked('workflow-calculator')
        key('7');key('2');calculators[2]='72';checked('workflow-calculator-input')
        key('ESCAPE');order.remove(2);del rects[2];del titles[2];calculators.clear();focus=1;menu=view_menu
        checked('workflow-calculator-return')
        # Exercise the actual generated resource menu, including checked labels.
        move(11,3);click();wait(12)
        popup=dict(x=10,y=8,hot=-1,labels=('[ ] Fullscreen','(x) Icons','( ) List'))
        checked('workflow-view-menu');key('ESCAPE');popup=None;checked('workflow-view-cancel')
        move(11,3);click();wait(12);move(12,33);click();fms[1]['view']=0
        checked('workflow-list-menu')
        move(6,166);click();fms[1]['top']=7;checked('workflow-list-page-down')
        move(6,42);click();fms[1]['top']=6;checked('workflow-list-arrow-up')
        move(6,176);click();fms[1]['top']=7;checked('workflow-list-arrow-down')
        key('I');fms[1]['view']=1;fms[1]['top']=0;checked('workflow-icons-shortcut')
        key('F');rects[1]=(0,8,80,192);checked('workflow-fullscreen')
        key('F');rects[1]=(4,26,56,158);checked('workflow-fullscreen-restores')
        open_item(1,'..');directory(1,'');checked('workflow-parent')
        open_item(1,'GEOBENCH.CFG')
        popup=dict(x=23,y=84,hot=-1,labels=('Not available yet','Unsupported file or location'))
        checked('workflow-unsupported-file');key('ESCAPE');popup=None;checked('workflow-error-restores')
        open_item(1,'GBENCH');directory(1,'/GBENCH');checked('workflow-directory-again')
        open_item(1,'CLOCK.APP');clock_slot=2;rects[2]=(26,20,28,122);order.append(2);focus=2;menu=CLOCK;titles[2]='Clock'
        checked('workflow-clock');key('S');checked('workflow-clock-seconds')
        drag(2,52,20);checked('workflow-clock-moved')
        move(14,31);click();order.remove(1);order.append(1);focus=1;menu=view_menu
        checked('workflow-refocus-directory')
        drag(1,0,38);checked('workflow-directory-moved')
        open_disk(3);checked('workflow-independent-root')
        close_fm(3);checked('workflow-independent-close')
        close_fm(1);focus=2;menu=CLOCK;checked('workflow-directory-close')
        key('ESCAPE');order.remove(2);del rects[2];del titles[2];clocks.clear();clock_slot=None;focus=0;menu=DESKTOP
        checked('workflow-clean-desktop')
        return finish()
    if scenario=='contexts':
        for slot in range(1,5):
            open_disk(slot);checked(f'contexts-open-{slot}')
        # Saving View needs a temporary context in addition to all four live
        # directory contexts. It must fail visibly without stealing one or
        # changing disk/live config; the session view may still change.
        image=artifacts/'RUNTIME.IMG';before=image.read_bytes()
        send('key-down L');wait(12);send('key-up L')
        popup=dict(x=23,y=84,hot=-1,labels=('View not saved','Configuration error'))
        r=checked('contexts-config-save-rejected')
        if field(r,4,'view')!=b'\0': raise AssertionError('failed View save lost the new session preference')
        if r[sym['cpc_edit_status']]!=7 or not r[sym['cpc_edit_error']] or image.read_bytes()!=before:
            raise AssertionError('full-context edit did not reject without writing')
        key('ESCAPE');popup=None;fms[4]['view']=0;checked('contexts-session-view-only')
        # Registration occurs before opening the required directory context.
        # While its error dialog is active, the fifth window is owned but has
        # not published any pixels or menu; only the four earlier listings exist.
        disk_click();order.append(5);unpublished.add(5);focus=5;menu=DESKTOP
        popup=dict(x=23,y=84,hot=-1,labels=('File Manager unavailable','No filesystem context'))
        checked('contexts-full-initialization-error')
        key('ESCAPE');popup=None;order.remove(5);unpublished.clear();focus=4;menu=bytes((1,10))+b'View\0\0\0\0'
        checked('contexts-failed-app-released')
        close_fm(4);checked('contexts-capacity-returned')
        open_disk(4);checked('contexts-reopen-after-exhaustion')
        for slot in range(4,0,-1):
            close_fm(slot);checked(f'contexts-close-{slot}')
        return finish()
    if scenario=='services':
        image=artifacts/'RUNTIME.IMG';target=['-i',str(image)+'@@16384']
        def disk(): return subprocess.check_output(['mtype',*target,'::/GEOBENCH.CFG'])
        expected=disk()
        def accepted(r):
            if r[sym['cpc_edit_status']] or r[sym['cpc_edit_error']] or r[sym['cpc_ui_request']+4]!=1:
                raise AssertionError('actual File Manager config call failed')
            owner=r[sym['core_win_owner']+2] | r[sym['core_win_owner_gen']+2]<<8
            if word(r,'cpc_ui_owner')!=owner: raise AssertionError('config module lost File Manager caller identity')
            n=word(r,'cpc_cfg_output')
            if disk()!=expected or r[sym['cpc_cfg_text']:sym['cpc_cfg_text']+n]!=expected:
                raise AssertionError('saved/live configuration differs')
        choose_desk(0);clock_slot=1;rects[1]=(26,20,28,122);order.append(1);focus=1;menu=CLOCK;titles[1]='Clock'
        checked('services-clock');key('S');checked('services-clock-seconds')
        drag(1,52,20);checked('services-clock-moved')
        open_disk(2);r=checked('services-filemgr');workers=word(r,'cpc_runtime_worker_calls')
        expected=replace_value(expected,b'LIST',b'VIEW=');key('L');fms[2]['view']=0
        r=checked('services-list');accepted(r)
        saved=image.read_bytes();calls=word(r,'cpc_edit_calls')
        key('L');r=checked('services-list-noop')
        if image.read_bytes()!=saved or word(r,'cpc_edit_calls')!=calls:
            raise AssertionError('unchanged view invoked persistence or wrote disk')
        expected=replace_value(expected,b'DEFAULT',b'VIEW=');key('I');fms[2]['view']=1
        r=checked('services-icons');accepted(r)
        move(14,46);click();click()
        fms[2]=dict(items=[('..',14)]+listing(manifest['files'],'/GBENCH'),path='/GBENCH');titles[2]=title('/GBENCH')
        checked('services-directory')
        expected=replace_value(expected,b'LIST',b'VIEW=');key('L');fms[2]['view']=0
        r=checked('services-directory-list');accepted(r)
        if word(r,'cpc_runtime_worker_calls')==workers: raise AssertionError('Clock worker did not progress across native service calls')
        close_fm(2);focus=1;menu=CLOCK;checked('services-filemgr-close')
        open_disk(2);fms[2]['view']=0;checked('services-reopen-persisted-view')
        close_fm(2);focus=1;menu=CLOCK;checked('services-context-returned')
        key('ESCAPE');order.remove(1);del rects[1];del titles[1];clocks.clear();clock_slot=None;focus=0;menu=DESKTOP
        checked('services-clock-close')
        return finish()
    if scenario=='windows':
        for slot in range(1,5):
            open_disk(slot);checked(f'windows-filemgr-{slot}')
        move(14,46);click();click()
        fms[4]=dict(items=[('..',14)]+listing(manifest['files'],'/GBENCH'),path='/GBENCH');titles[4]=title('/GBENCH')
        checked('windows-directory')
        for slot in (5,6,7):
            if focus!=4:
                move(14,31);click();order.remove(4);order.append(4);focus=4;menu=bytes((1,10))+b'View\0\0\0\0'
                checked(f'windows-focus-parent-{slot}')
            move(30,46);click();click()
            rects[slot]=(11,66,58,68);accents[slot]=0;order.append(slot);focus=slot;menu=b'\0'
            checked(f'windows-probe-{slot}')
        move(14,31);click();order.remove(4);order.append(4);focus=4;menu=bytes((1,10))+b'View\0\0\0\0'
        checked('windows-full')
        move(30,46);click();click()
        popup=dict(x=23,y=84,hot=-1,labels=('Application not opened','Missing, invalid or no RAM'))
        checked('windows-capacity-rejected');key('ESCAPE');popup=None;checked('windows-capacity-restores')
        close_fm(4);focus=7;menu=b'\0';checked('windows-capacity-returned')
        open_disk(4);checked('windows-reopen-after-full')
        close_fm(4);focus=7;menu=b'\0';checked('windows-close-reopened')
        for slot in (7,6,5):
            key('ESCAPE');order.remove(slot);del rects[slot];del accents[slot];focus=order[-1]
            menu=b'\0' if focus>=5 else bytes((1,10))+b'View\0\0\0\0'
            checked(f'windows-close-probe-{slot}')
        for slot in (3,2,1):
            close_fm(slot);checked(f'windows-close-filemgr-{slot}')
        return finish()
    if scenario: raise ValueError('unimplemented File Manager scenario: '+scenario)
    if case:
        disk_click();popup=dict(x=23,y=84,hot=-1,labels=('Application not opened','Missing, invalid or no RAM'))
        checked('filemgr-rejected-'+case)
        key('ESCAPE');popup=None;checked('filemgr-failure-restores')
        # A failed native transaction must not prevent a later portable launch.
        move(11,3);click();wait(12);move(12,23);click()
        rects[1]=(24,24,31,144);order.append(1);focus=1;menu=EDIT
        titles[1]='Calculator';calculators[1]='0';checked('filemgr-failure-next-launch')
        key('ESCAPE');order.remove(1);del rects[1];del titles[1];calculators.clear()
        focus=0;menu=DESKTOP;checked('filemgr-failure-next-close')
        report=dict(case=case,checkpoints=checks,stack=stack)
        (artifacts/'result.json').write_text(json.dumps(report,indent=2)+'\n')
        print('PASS native File Manager rejection '+json.dumps(report),flush=True)
        return artifacts
    previous=None
    for iteration in range(3):
        open_disk(1);r=checked(f'filemgr-open-{iteration}')
        owner=bytes((r[sym['core_win_owner']+1],r[sym['core_win_owner_gen']+1]))
        if owner==previous: raise AssertionError('stale owner generation reused')
        previous=owner
        key('ESCAPE');order.remove(1);del fms[1];del rects[1];del titles[1];focus=0;menu=DESKTOP
        checked(f'filemgr-close-{iteration}')
    open_disk(1);checked('filemgr-first')
    # The first owner browses /GBENCH; the second must still open at root.
    move(14,46);click();click()
    fms[1]=dict(items=[('..',14)]+listing(manifest['files'],'/GBENCH'),path='/GBENCH')
    titles[1]=title('/GBENCH');checked('filemgr-system-directory')
    open_disk(2);checked('filemgr-second')
    for slot in (2,1):
        key('ESCAPE');order.remove(slot);del fms[slot];del rects[slot];del titles[slot]
        focus=order[-1];menu=bytes((1,10))+b'View\0\0\0\0' if focus else DESKTOP
        checked(f'filemgr-close-pair-{slot}')
        if slot==2:
            # Launch the unchanged portable Calculator from the first owner's
            # /GBENCH listing, then return to that same native directory state.
            open_item(1,'CALC.APP')
            rects[2]=(24,24,31,144);order.append(2);focus=2;menu=EDIT
            titles[2]='Calculator';calculators[2]='0';checked('filemgr-launch-calculator')
            key('7');key('2');calculators[2]='72';checked('filemgr-calculator-input')
            key('ESCAPE');order.remove(2);del rects[2];del titles[2];calculators.clear()
            focus=1;menu=bytes((1,10))+b'View\0\0\0\0'
            checked('filemgr-child-returns')
    report=dict(checkpoints=checks,stack=stack,sections=manifest['sections'])
    (artifacts/'result.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS native File Manager '+json.dumps(report),flush=True)
    return artifacts
