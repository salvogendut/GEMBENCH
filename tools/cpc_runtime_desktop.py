"""Observe the actual Desktop boot/bind/menu path on a private M4 image."""
import json
from pathlib import Path

from cpc_production_lifetime import physical
from cpc_runtime_clock import clock_cache_ready
from cpc_runtime_pixels import verify_pixels
from cpc_filemgr_pixels import listing
from cpc_fswrite_cases import space
from test_cpc_foundation_1984 import snapshot

DESKTOP=bytes((2,10))+b'Desk\0\0\0\0'+bytes((17,))+b'System\0\0'
EDIT=bytes((1,10))+b'Edit\0\0\0\0'
CLOCK=bytes((2,10))+b'View\0\0\0\0'+bytes((17,))+b'Options\0'


def system_items(manifest):
    return ('Ram Usage','Tidy Icons')+(('Settings',) if 'settings' in manifest['sections'] else ())+('About GEOBENCH',)


def run_desktop(root,manifest,work,sym,artifacts,send,wait,read,key,move):
    from test_cpc_runtime_1984 import integrity
    noi={v[1]:int(v[2],16) for line in (root/'build/universal-obj/uclock/app.noi').read_text().splitlines()
         if len(v:=line.split())==3 and v[0]=='DEF'}
    offsets={v[1]:int(v[2],16) for line in (root/'build/universal-obj/uclock/main.sym').read_text().splitlines()
             if len(v:=line.split())==4 and v[0]=='1' and v[3]=='R'}
    rects={};order=[0];accents={};titles={};calculators={};clocks={};filemanagers={}
    focus=0;menu=DESKTOP;clock_slot=None;popup=None;dialog=None;checks=[];stack=dict(main=0,irq=0,tmp=0)
    desktop=dict(icons=(work/'REFINED.IST').read_bytes())
    def word(r,name): return int.from_bytes(r[sym[name]:sym[name]+2],'little')
    def clock_value(r,name):
        at=physical(r[sym['wm_table']+25*clock_slot])+noi['s__DATA']-0x4000+offsets['_'+name]
        return r[at]
    def checked(name):
        previous=None
        modal=popup is not None or dialog is not None
        for _ in range(200):
            data=read(name);_,r=snapshot(data)
            if r[sym['pointer_visible']] and not any(r[sym[k]] for k in ('io_busy','core_pointer_paintlock')) and (modal or not r[sym['core_param_timer_owner']]):
                if clock_slot is None or clock_cache_ready(lambda k:clock_value(r,k),modal):
                    signature=bytes(r[0xC000:0x10000])+bytes(r[sym['menu_def']:sym['menu_def']+37])
                    turns=word(r,'cpc_runtime_turns')
                    if previous and signature==previous[0] and (modal or (turns-previous[1])&65535>=2): break
                    if previous is None or signature!=previous[0]: previous=signature,turns
            wait(3)
        else: raise AssertionError(name+': drawing/root loop did not settle')
        r,used=integrity(data,sym,work)
        for k,n in used.items(): stack[k]=max(stack[k],n)
        if r[sym['cpc_desktop_status']]!=1: raise AssertionError('native root binding failed')
        if clock_slot is not None:
            clocks[clock_slot]=tuple(clock_value(r,k) for k in ('ph','pm','ps','show_sec','dh','dm','ds'))
        painted_popup=popup if dialog is None else dict(x=33,y=111,hot=-1,labels=('  OK  ',))
        verify_pixels(r,sym,work,rects,order,accents,menu,titles,popup=painted_popup,calculators=calculators,clocks=clocks,dialog=dialog,desktop=desktop,filemanagers=filemanagers)
        if r[sym['wm_nwin']]!=len(order) or r[sym['wm_focus']]!=focus or r[sym['wm_z']:sym['wm_z']+len(order)]!=bytes(order):
            raise AssertionError(name+': owner/window lifecycle mismatch')
        if r[sym['wm_table']:sym['wm_table']+5]!=bytes((0xC0,0,0,80,200)):
            raise AssertionError('root page or geometry changed')
        if r[sym['core_page_free']]!=27-len(order) or word(r,'core_pending_owner') or any(r[sym['launch_arg']:sym['launch_arg']+11]):
            raise AssertionError('Desktop owner/page/launch state leaked')
        if bool(r[sym['ui_modal']])!=modal or sum(bool(r[sym['core_fsctx_table']+i*144]) for i in range(4))!=len(filemanagers):
            raise AssertionError('Desktop modal/context leak')
        if popup is not None:
            labels=b''.join(s.encode()+b'\0' for s in popup['labels'])
            if r[sym['cpc_ui_request']+3]!=len(popup['labels']) or r[sym['cpc_ui_text']:sym['cpc_ui_text']+len(labels)]!=labels:
                raise AssertionError('actual menu request lost item count/labels')
        checks.append(name);send(f'crop {artifacts/(name+".ppm")} 0 0 768 576 1')
        print(f'{name}: windows={len(order)} stack={stack}',flush=True)
        return r
    def click():
        for command,held in (('key-down SPACE',True),('key-up SPACE',False)):
            send(command)
            for _ in range(150):
                wait(3);_,r=snapshot(read())
                if bool(r[sym['poll_lastfire']])==held: break
            else: raise AssertionError('click not sampled')
    def root_focus():
        nonlocal focus,menu
        move(76,185);click();focus=0;menu=DESKTOP
    def choose(col,index):
        nonlocal popup
        move(col+1,3);click();wait(12)
        popup=dict(x=col,y=8,hot=-1,labels=('Clock','Calculator') if col==10 else system_items(manifest))
        checked(f'desktop-popup-{len(checks)}')
        move(col+2,13+index*10);click();wait(12);popup=None
    def drag(slot,x,y):
        ox,oy,w,h=rects[slot]
        move(ox+10,oy+5);_,r=snapshot(read());grab=(r[sym['poll_byte']],r[sym['poll_line']])
        send('key-down SPACE');wait(10);move(grab[0]+x-ox,grab[1]+y-oy)
        _,r=snapshot(read());drop=(r[sym['poll_byte']],r[sym['poll_line']])
        send('key-up SPACE');wait(60)
        rects[slot]=(max(0,min(80-w,ox+drop[0]-grab[0])),max(8,min(200-h,oy+drop[1]-grab[1])),w,h)
        _,r=snapshot(read());at=sym['wm_table']+25*slot+1
        if r[at:at+4]!=bytes(rects[slot]) or rects[slot]==(ox,oy,w,h):
            raise AssertionError('title drag differs from pointer displacement')
    r=checked('desktop-boot')
    owner=bytes((r[sym['core_win_owner']],r[sym['core_win_owner_gen']]))
    choose(17,0);desktop['footprint']=f"{(manifest['sections']['kernel']['used']+512)//1024}K used"
    checked('desktop-footprint')
    choose(10,1);rects[1]=(24,24,31,144);order.append(1);focus=1;menu=EDIT
    titles[1]='Calculator';calculators[1]='0';checked('desktop-calculator')
    key('7');key('2');calculators[1]='72';checked('desktop-calculator-input')
    drag(1,8,34);checked('desktop-calculator-drag')
    root_focus();checked('desktop-return-root')
    choose(10,0);rects[2]=(26,20,28,122);order.append(2);focus=2;menu=CLOCK
    titles[2]='Clock';clock_slot=2;checked('desktop-clock')
    key('S');checked('desktop-clock-seconds')
    drag(2,35,28);checked('desktop-clock-drag')
    root_focus();r=checked('desktop-background-clock');before=word(r,'cpc_runtime_worker_calls')
    wait(150);r=checked('desktop-background-progress')
    if word(r,'cpc_runtime_worker_calls')==before: raise AssertionError('background worker stopped')
    choose(17,1);checked('desktop-system-tidy')
    # A title click opens the actual System menu. Cancel without a forced paint.
    move(18,3);click();wait(12);key('ESCAPE');checked('desktop-system-cancel')
    choose(10,1);order.remove(1);order.append(1);focus=1;menu=EDIT
    checked('desktop-reactivate-calculator')
    key('ESCAPE');order.remove(1);del rects[1];del calculators[1];del titles[1]
    focus=2;menu=CLOCK;checked('desktop-calculator-close')
    root_focus()
    choose(10,0);order.remove(2);order.append(2);focus=2;menu=CLOCK;checked('desktop-reactivate-clock')
    key('ESCAPE');order.remove(2);del rects[2];del titles[2];clocks.clear();clock_slot=None
    focus=0;menu=DESKTOP;r=checked('desktop-clock-close')
    if owner!=bytes((r[sym['core_win_owner']],r[sym['core_win_owner_gen']])):
        raise AssertionError('Desktop owner was replaced')
    if r[sym['core_page_free']]!=26: raise AssertionError('application page leak')
    choose(17,0);desktop.pop('footprint');checked('desktop-footprint-off')
    choose(17,len(system_items(manifest))-1)
    identity=manifest['native_identity']
    dialog=dict(kind='about',build=f"Version : {identity['version']} Git: {identity['git']}")
    checked('desktop-about');key('ESCAPE');dialog=None;checked('desktop-about-restores')
    # Public Desktop gestures, not the old diagnostic F-key launcher.
    move(3,26);click();click()
    if 'filemgr' in manifest['sections']:
        rects[1]=(4,26,56,158);order.append(1);focus=1;menu=bytes((1,10))+b'View\0\0\0\0'
        filemanagers[1]=dict(items=listing(manifest['files']))
        titles[1]=f"Disk C {space(Path(manifest['image']))[0]//1024}MiB free"
        checked('desktop-disk-opens-filemgr');key('ESCAPE')
        del filemanagers[1];del rects[1];del titles[1];order.remove(1);focus=0;menu=DESKTOP
        checked('desktop-filemgr-close-restores')
    else:
        popup=dict(x=23,y=84,hot=-1,labels=('Disk browsing unavailable','File Manager integration pending'))
        checked('desktop-disk-unavailable');key('ESCAPE');popup=None
        checked('desktop-disk-error-restores')
    move(69,45);click();click()
    rects[1]=(26,20,28,122);order.append(1);focus=1;menu=CLOCK
    titles[1]='Clock';clock_slot=1;checked('desktop-clock-icon-launch')
    root_focus();move(69,45);click();click();focus=1;menu=CLOCK
    checked('desktop-clock-icon-reactivates')
    # Use the actual title close gadget this time, not Escape.
    move(rects[1][0]+1,rects[1][1]+5);click()
    order.remove(1);del rects[1];del titles[1];clocks.clear();clock_slot=None
    focus=0;menu=DESKTOP;checked('desktop-title-close-returns')
    if (artifacts/'RUNTIME.IMG').read_bytes()!=Path(manifest['image']).read_bytes():
        raise AssertionError('read-only Desktop lifecycle changed its M4 copy')
    report=dict(checkpoints=checks,stack=stack,sections=manifest['sections'],
                status='actual Desktop with build-matched File Manager' if 'filemgr' in manifest['sections'] else
                       'actual Desktop boot contract; native File Manager admission still closed')
    (artifacts/'result.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS actual Desktop contract '+json.dumps(report),flush=True)
    return artifacts
