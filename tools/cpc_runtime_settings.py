"""Real shared Settings through Desktop input on disposable M4 media only."""
import hashlib
import json
import re
import subprocess

from cpc_runtime_assets import variant
from cpc_runtime_bitmaps import fixture as bitmap_fixture
from cpc_runtime_configedit import replace_value
from cpc_runtime_desktop import DESKTOP, CLOCK, EDIT
from cpc_runtime_clock import clock_cache_ready, clock_may_remain_parked
from cpc_runtime_filemgr import popup_ready
from cpc_filemgr_pixels import listing
from cpc_fswrite_cases import space
from cpc_runtime_pixels import DEFAULT_THEME, verify_pixels
from cpc_production_lifetime import physical
from test_cpc_foundation_1984 import snapshot

KEYS=('FONT','ICONS','CURSOR','TITLEBAR','GADGETS','BACKDROP')
CHOICES=('ALTERN.FNT','DEFAULT.IST','ALTCURS.SPR','WEAVE.TBR','IMPROVED.GDT','WAVES.BDP')
DELIVERY_CHOICES=('DEFAULT.FNT','DEFAULT.IST','DEFAULT.SPR','WEAVE.TBR','IMPROVED.GDT','WAVES.BDP')


def prepare(case,root,media,work,sym,image,artifacts):
    if image.is_symlink() or image.resolve()!=(artifacts/'RUNTIME.IMG').resolve():
        raise ValueError('Settings tests require a disposable artifact image')
    target=['-i',str(image)+'@@16384']
    manifest=json.loads((media/'manifest.json').read_text())
    delivery=manifest.get('profile')=='cpc-desktop-m4-v3'
    choices=DELIVERY_CHOICES if delivery else CHOICES
    extras={} if delivery else {'GBENCH/ALTERN.FNT':variant((work/'DEFAULT.FNT').read_bytes()),
            'GBENCH/ALTCURS.SPR':bitmap_fixture('custom',work,root)['cursor']}
    if case!='reboot':
        for name,raw in extras.items():
            path=artifacts/name.split('/')[-1];path.write_bytes(raw)
            subprocess.run(['mcopy',*target,str(path),'::/'+name],check=True)
    else:
        # Only an unchanged private image plus the six expected saved values
        # may seed cold restart; do not accept arbitrary replacement binaries.
        expected=(media/'CARD/GEOBENCH.CFG').read_bytes()
        for key,value in zip(KEYS,choices):expected=replace_value(expected,value.encode(),(key+'=').encode())
        files={**json.loads((media/'manifest.json').read_text())['files'],
               **{k:hashlib.sha256(v).hexdigest() for k,v in extras.items()},
               'GEOBENCH.CFG':hashlib.sha256(expected).hexdigest()}
        for name,digest in files.items():
            raw=subprocess.check_output(['mtype',*target,'::/'+name])
            if hashlib.sha256(raw).hexdigest()!=digest:raise AssertionError('invalid Settings reboot seed: '+name)
    kernel=(work/'CORE.RAW').read_bytes()
    if case in ('missing','short','corrupt','unbound'):
        raw=(work/'settings/SETTINGS.native.bin').read_bytes()
        if case!='unbound':
            subprocess.run(['mdel',*target,'::/GBENCH/SETTINGS.BIN'],check=True)
            if case!='missing':
                raw=raw[:-1] if case=='short' else raw[:-1]+bytes((raw[-1]^1,))
                path=artifacts/'SETTINGS.BIN';path.write_bytes(raw)
                subprocess.run(['mcopy',*target,str(path),'::/GBENCH/SETTINGS.BIN'],check=True)
        else:
            at=sym['cpc_settings_contract']-0x8000
            kernel=kernel[:at]+bytes(6)+kernel[at+6:]
            path=artifacts/'CORE.BIN';path.write_bytes(kernel)
            subprocess.run(['mcopy','-o',*target,str(path),'::/CORE.BIN'],check=True)
    if case=='edit-missing':subprocess.run(['mdel',*target,'::/GBENCH/GBEDIT.MOD'],check=True)
    from cpc_settings_faults import prepare as faults
    details=faults(case,root,work,image,artifacts,extras)
    names=(set(json.loads((media/'manifest.json').read_text())['files'])|set(extras))-details['removed']
    if case=='missing':names.remove('GBENCH/SETTINGS.BIN')
    if case=='edit-missing':names.remove('GBENCH/GBEDIT.MOD')
    payloads={name:hashlib.sha256(subprocess.check_output(['mtype',*target,'::/'+name])).hexdigest()
              for name in sorted(names)}
    (artifacts/'payloads-before.json').write_text(json.dumps(payloads,indent=2)+'\n')
    details['payloads']=payloads
    return dict(extras=extras,choices=choices,delivery=delivery,**{'kernel':kernel,**details})


def run_settings(root,manifest,work,sym,artifacts,send,wait,read,key,move,case,fixture):
    from test_cpc_runtime_1984 import integrity
    image=artifacts/'RUNTIME.IMG';target=['-i',str(image)+'@@16384']
    def disk():return subprocess.check_output(['mtype',*target,'::/GEOBENCH.CFG'])
    expected=disk();initial=image.read_bytes();files={**manifest['files'],**fixture['extras']}
    choices=fixture['choices']
    for name in fixture['removed']:files.pop(name,None)
    published=expected[:512]
    app=work/'settings';raw=fixture.get('settings_raw',(app/'SETTINGS.native.bin').read_bytes())
    def symbols(path):
        return {v[1]:int(v[2],16) for line in path.read_text().splitlines()
                if len(v:=line.split())==3 and v[0]=='DEF'}
    def fields(path):
        return {v[1]:int(v[2],16) for line in path.read_text().splitlines()
                if len(v:=line.split())==4 and v[0]=='1' and v[3]=='R'}
    noi=symbols(fixture.get('settings_noi',app/'settings.noi'));off=fields(app/'main.sym')
    cnoi=symbols(root/'build/universal-obj/uclock/app.noi');coff=fields(root/'build/universal-obj/uclock/main.sym')
    fnoi=symbols(work/'filemgr/filemgr.noi');foff=fields(work/'filemgr/main.sym')
    rects={};order=[0];titles={};settings={};filemanagers={};clocks={};calculators={}
    focus=0;menu=DESKTOP;popup=None;clock_slot=None;setting_slot=None
    font=(work/'DEFAULT.FNT').read_bytes();cursor=(work/'DEFAULT.SPR').read_bytes()
    icons=(work/'REFINED.IST').read_bytes();theme=DEFAULT_THEME;backdrop=None
    checks=[];stack=dict(main=0,irq=0,tmp=0)
    unpublished=set()
    if case=='config-oversized':
        published=b'';icons=(work/'DEFAULT.IST').read_bytes()
    if case=='empty-icons':
        # Both icon files are absent, so Desktop keeps its labels but has no
        # icon artwork. Preserve oracle geometry and blank only the bitmaps.
        at=int.from_bytes(icons[16:18],'little');icons=icons[:at]+bytes(len(icons)-at)
    def word(r,name):return int.from_bytes(r[sym[name]:sym[name]+2],'little')
    def field(r,slot,name,n=1,layout=None):
        ni,of=layout or (noi,off)
        address=ni.get('_'+name,ni['s__DATA']+of.get('_'+name,0))
        if '_'+name not in ni and '_'+name not in of:raise AssertionError('unknown app field '+name)
        at=physical(r[sym['wm_table']+25*slot])+address-0x4000
        return r[at:at+n]
    def cv(r,name):return field(r,clock_slot,name,layout=(cnoi,coff))[0]
    def values():
        return [re.search(rb'(?:\A|(?<=[\r\n]))'+k.encode()+rb'=([^\r\n]*)',published)[1].decode() for k in KEYS]
    def apply_expected(row):
        nonlocal font,cursor,icons,theme,backdrop
        if row==0:font=(work/'DEFAULT.FNT').read_bytes() if fixture['delivery'] else fixture['extras']['GBENCH/ALTERN.FNT']
        elif row==1:icons=(work/'DEFAULT.IST').read_bytes()
        elif row==2:cursor=(work/'DEFAULT.SPR').read_bytes() if fixture['delivery'] else fixture['extras']['GBENCH/ALTCURS.SPR']
        elif row==3:theme=(root/'assets/titlebars/WEAVE.TBR').read_bytes()+theme[56:]
        elif row==4:theme=theme[:56]+(root/'assets/gadgets/IMPROVED.GDT').read_bytes()
        else:backdrop=(root/'assets/backdrops/waves.BDP').read_bytes()
    if case=='reboot':
        for row in range(6):apply_expected(row)
    def checked(name):
        previous=None
        for _ in range(350):
            data=read(name);_,r=snapshot(data)
            ready=r[sym['wm_nwin']]==len(order) and bool(r[sym['ui_modal']])==(popup is not None)
            if popup is not None:ready=ready and popup_ready(r,sym,popup)
            if setting_slot is not None:ready=ready and field(r,setting_slot,'picker_state')==b'\0'
            for slot in filemanagers:ready=ready and field(r,slot,'list_state',layout=(fnoi,foff))==b'\0'
            if clock_slot is not None:
                ready=ready and (clock_may_remain_parked(rects,order,clock_slot,r[sym['cpc_wm_visibility']+clock_slot],r[sym['cpc_task_visibility']+clock_slot]) or
                                 clock_cache_ready(lambda k:cv(r,k),popup is not None))
            if ready and r[sym['pointer_visible']] and not any(r[sym[k]] for k in ('io_busy','core_pointer_paintlock','core_param_timer_owner')):
                sig=bytes(r[0xC000:0x10000])+bytes(r[sym['menu_def']:sym['menu_def']+37])
                if clock_slot is not None:sig+=bytes(cv(r,k) for k in ('ph','pm','ps','show_sec','dh','dm','ds'))
                turn=word(r,'cpc_runtime_turns')
                if previous and sig==previous[0] and (popup is not None or (turn-previous[1])&65535>=2):break
                if previous is None or sig!=previous[0]:previous=sig,turn
            wait(5)
        else:raise AssertionError(name+': Settings/root did not settle')
        r,used=integrity(data,sym,work,font=font,cursor=cursor,theme=theme,kernel=fixture['kernel'])
        for k,n in used.items():stack[k]=max(stack[k],n)
        if r[sym['wm_focus']]!=focus or r[sym['wm_z']:sym['wm_z']+len(order)]!=bytes(order):raise AssertionError(name+': focus/stack')
        for slot,rect in rects.items():
            if r[sym['wm_table']+25*slot+1:sym['wm_table']+25*slot+5]!=bytes(rect):raise AssertionError(name+': geometry')
        if r[sym['core_page_free']]!=27-len(order) or word(r,'core_pending_owner'):raise AssertionError(name+': page/owner leak')
        live=[r[sym['core_fsctx_table']+i*144:sym['core_fsctx_table']+(i+1)*144] for i in range(4)]
        live=[c for c in live if c[0]]
        if len(live)!=len(filemanagers)+len(settings):raise AssertionError(name+': context leak')
        for slot in (*filemanagers,*settings):
            owner=bytes((r[sym['core_win_owner']+slot],r[sym['core_win_owner_gen']+slot]))
            if sum(c[2:4]==owner for c in live)!=1:raise AssertionError('context owner differs')
        for slot in filemanagers:
            if field(r,slot,'fm_path',40,layout=(fnoi,foff)).split(b'\0',1)[0]:raise AssertionError('Settings moved File Manager browse path')
        for slot in settings:
            at=physical(r[sym['wm_table']+25*slot])
            if r[at:at+len(raw)]!=raw:raise AssertionError('Settings code changed')
            n=int.from_bytes(field(r,slot,'cfglen',2),'little')
            if field(r,slot,'cfgbuf',n)!=settings[slot].get('config',published):raise AssertionError('Settings config copy differs')
            if field(r,slot,'settings_storage_claim')!=b'\0':raise AssertionError('Settings storage claim leaked')
        n=word(r,'cpc_cfg_output')
        if r[sym['cpc_cfg_text']:sym['cpc_cfg_text']+n]!=published:raise AssertionError('unverified live config publication')
        if clock_slot is not None:clocks[clock_slot]=tuple(cv(r,k) for k in ('ph','pm','ps','show_sec','dh','dm','ds'))
        if popup is not None:
            px,py=r[sym['poll_byte']],r[sym['poll_line']];w=max(len(s)*6//4+4 for s in popup['labels'])
            hot=(py-popup['y']-2)//10
            popup['hot']=hot if popup['x']<=px<popup['x']+w and 0<=hot<min(10,len(popup['labels'])) else -1
        send(f'crop {artifacts/(name+".ppm")} 0 0 768 576 1')
        verify_pixels(r,sym,work,rects,[s for s in order if s not in unpublished],{},menu,titles,popup=popup,calculators=calculators,clocks=clocks,
                      font=font,cursor=cursor,theme=theme,backdrop=backdrop,desktop=icons,filemanagers=filemanagers,settings=settings)
        if disk()!=expected:raise AssertionError('unexpected persisted config')
        checks.append(name);print(f'{name}: windows={len(order)} contexts={len(live)} stack={stack}',flush=True)
        return r
    def click():
        for cmd,held in (('key-down SPACE',True),('key-up SPACE',False)):
            send(cmd)
            for _ in range(180):
                wait(3);_,r=snapshot(read())
                if bool(r[sym['poll_lastfire']])==held:break
            else:raise AssertionError('click not sampled')
    def root_focus():
        nonlocal focus,menu
        move(77,190);click();focus=0;menu=DESKTOP
    def choose_menu(col,index):
        nonlocal popup
        move(col+1,3);click()
        popup=dict(x=col,y=8,hot=-1,labels=('Clock','Calculator') if col==10 else ('Ram Usage','Tidy Icons','Settings','About GEOBENCH'))
        checked('settings-menu-'+str(len(checks)))
        move(col+2,13+10*index);click();popup=None
    def open_settings(slot):
        nonlocal setting_slot,focus,menu
        root_focus();choose_menu(17,2)
        setting_slot=slot;rects[slot]=(18,32,58,112);order.append(slot);focus=slot;menu=b'\0'
        titles[slot]='Settings';settings[slot]=dict(values=values(),config=published)
    def close_settings():
        nonlocal setting_slot,focus,menu
        key('ESCAPE');slot=setting_slot;setting_slot=None
        order.remove(slot);del rects[slot];del titles[slot];del settings[slot]
        focus=order[-1];menu=DESKTOP if not focus else b'\0' if focus in settings else CLOCK if focus==clock_slot else EDIT
    def drag(slot,x,y):
        nonlocal focus,menu
        ox,oy,w,h=rects[slot]
        move(ox+10,oy+5);_,r=snapshot(read());grab=(r[sym['poll_byte']],r[sym['poll_line']])
        send('key-down SPACE');wait(10);move(grab[0]+x-ox,grab[1]+y-oy)
        _,r=snapshot(read());drop=(r[sym['poll_byte']],r[sym['poll_line']])
        send('key-up SPACE');wait(60)
        rects[slot]=(max(0,min(80-w,ox+drop[0]-grab[0])),max(8,min(200-h,oy+drop[1]-grab[1])),w,h)
        if rects[slot]==(ox,oy,w,h):raise AssertionError('drag did not move')
        order.remove(slot);order.append(slot);focus=slot;menu=b'\0' if slot in settings else CLOCK if slot==clock_slot else EDIT
    def choose_row(row,choice=None,error=None,save_error=None,scroll=False):
        nonlocal popup,expected,published
        x,y,_,_=rects[setting_slot];move(x+20,y+18+row*12);click()
        for _ in range(350):
            _,r=snapshot(read('picker-wait'))
            if r[sym['ui_modal']] and r[sym['cpc_ui_status']]==0 and r[sym['cpc_ui_request']]==1:break
            wait(5)
        else:raise AssertionError('asset picker did not open')
        n=r[sym['cpc_ui_request']+3];labels=r[sym['cpc_ui_text']:sym['cpc_ui_request_end']].split(b'\0')[:n]
        labels=[s.decode() for s in labels]
        settings[setting_slot]['reading']=row
        if error:
            popup=dict(x=23,y=84,hot=-1,labels=error)
            checked('settings-picker-error-'+str(len(checks)))
            key('ESCAPE');popup=None;settings[setting_slot].pop('reading',None)
            return
        ext=('FNT','IST','SPR','TBR','GDT','BDP')[row]
        valid={k.split('/')[-1].rsplit('.',1)[0] for k in files if k.startswith('GBENCH/') and k.endswith('.'+ext)}
        if row==5:valid={'C:'+k for k in valid}|{'SOLID'}
        if case=='malformed-icons' and row==1:valid-={'SHORT','BADMAGIC','BADCOUNT'}
        if (len(labels)!=min(len(valid),17 if row==5 else 16) or len(set(labels))!=len(labels) or
            not set(labels)<=valid):raise AssertionError('unexpected asset enumeration: '+str(labels))
        popup=dict(x=x+16,y=max(8,min(y+18+row*12,198-(min(n,10)*10+4))),hot=-1,labels=labels)
        checked('settings-picker-'+KEYS[row]+'-'+str(len(checks)))
        if scroll:
            if n!=17 or sum(len(s)+1 for s in labels)>182:raise AssertionError('maximal list not exercised')
            move(popup['x']+2,popup['y']+103);wait(120);popup['top']=n-10
            checked('settings-picker-scrolled-bottom')
            move(popup['x']+2,popup['y']-1);wait(120);popup['top']=0
            checked('settings-picker-scrolled-top')
        if choice is None:key('ESCAPE')
        else:
            label=('C:' if row==5 and choice!='SOLID' else '')+choice.split('.')[0]
            move(popup['x']+2,popup['y']+6+10*labels.index(label));click()
            if case=='edit-missing':save_error=1
            if save_error is None:
                expected=replace_value(expected,choice.encode(),(KEYS[row]+'=').encode());published=expected
                if choice!='SOLID':apply_expected(row)
            else:
                if case=='readback-error':expected=replace_value(expected,choice.encode(),(KEYS[row]+'=').encode())
                popup=dict(x=23,y=84,hot=-1,labels=('Could not apply setting','Check storage and retry.'))
                # The failed commit reports before the content is repainted.
                r=checked('settings-write-rejected-'+str(len(checks)))
                if r[sym['cpc_edit_status']]!=save_error or r[sym['cpc_edit_changed']]:raise AssertionError('wrong save rejection stage')
                key('ESCAPE')
        popup=None;settings[setting_slot]=dict(values=values(),config=published)
    checked('settings-boot')
    if case=='mixed':
        move(3,26);click();click()
        rects[1]=(4,26,56,158);order.append(1);focus=1;menu=bytes((1,10))+b'View\0\0\0\0'
        filemanagers[1]=dict(items=listing(files))
        titles[1]=f'Disk C {space(image)[0]//1024}MiB free';checked('settings-filemgr-open')
        root_focus();choose_menu(10,0)
        clock_slot=2;rects[2]=(26,20,28,122);titles[2]='Clock';order.append(2);focus=2;menu=CLOCK
        checked('settings-clock-open');key('S');checked('settings-clock-seconds')
        root_focus();choose_menu(10,1)
        rects[3]=(24,24,31,144);titles[3]='Calculator';calculators[3]='0';order.append(3);focus=3;menu=EDIT
        checked('settings-calculator-open');key('7');key('2');calculators[3]='72';checked('settings-calculator-input')
    if case in ('missing','short','corrupt','unbound'):
        choose_menu(17,2);popup=dict(x=23,y=84,hot=-1,labels=('Application not opened','Missing, invalid or no RAM'))
        checked('settings-rejected-'+case);key('ESCAPE');popup=None;checked('settings-rejection-recovered')
    elif case in ('config-nul','config-oversized'):
        choose_menu(17,2);order.append(1);unpublished.add(1);focus=1
        popup=dict(x=23,y=84,hot=-1,labels=('Settings unavailable','Check config and storage.'))
        checked('settings-invalid-config-rejected')
        # The current Desktop also reports a launch failure when initialization
        # quits back to the same focus. Acknowledge both real dialogs; waiting
        # for root turns between nested launch/error dialogs would deadlock
        # the test, not the machine.
        send('key-down ESCAPE');wait(12);send('key-up ESCAPE')
        order.remove(1);unpublished.clear();focus=0
        popup=dict(x=23,y=84,hot=-1,labels=('Application not opened','Missing, invalid or no RAM'))
        checked('settings-invalid-config-launch-report')
        key('ESCAPE');popup=None
        checked('settings-invalid-config-recovered')
    elif case=='contexts':
        for slot in range(1,5):
            open_settings(slot);checked('settings-context-open-'+str(slot))
        choose_row(0,choices[0],save_error=7);checked('settings-context-save-recovered')
        root_focus();choose_menu(17,2);order.append(5);unpublished.add(5);focus=5
        popup=dict(x=23,y=84,hot=-1,labels=('Settings unavailable','Check config and storage.'))
        checked('settings-context-launch-rejected')
        key('ESCAPE');popup=None;order.remove(5);unpublished.clear();focus=4;menu=b'\0'
        checked('settings-context-launch-recovered')
        close_settings();checked('settings-context-returned')
        setting_slot=3
        choose_row(0,choices[0]);checked('settings-context-save-retry')
        # Earlier instances keep their own config snapshots, as on MSX.
        for slot in (3,2,1):
            setting_slot=slot;close_settings();checked('settings-context-close-'+str(slot))
        open_settings(1);checked('settings-context-reopen');close_settings();checked('settings-context-clean')
    else:
        slot=4 if case=='mixed' else 1
        open_settings(slot);checked('settings-open')
        if case not in ('directory-error','read-error'):
            choose_row(0);checked('settings-cancel-preserved')
        if case in ('normal','mixed'):
            for row,choice in enumerate(choices):
                choose_row(row,choice);checked('settings-saved-'+KEYS[row])
        elif case=='edit-missing':
            choose_row(0,choices[0]);checked('settings-write-recovery')
        elif case in ('config-full','write-denied','readback-error'):
            stage={'config-full':4,'write-denied':5,'readback-error':6}[case]
            choose_row(0,choices[0],save_error=stage);checked('settings-failed-save-recovery')
            choose_row(2);checked('settings-picker-after-failed-save')
        elif case=='empty-icons':
            for _ in range(2):
                choose_row(1,error=('No files found','in /GBENCH.'));checked('settings-empty-recovery-'+str(len(checks)))
        elif case=='malformed-icons':
            choose_row(1);checked('settings-malformed-headers-filtered')
        elif case=='long-backdrops':
            choose_row(5,scroll=True);checked('settings-long-list-cancel')
            choose_row(5,'SOLID',scroll=True);checked('settings-long-list-selection')
        elif case in ('directory-error','read-error'):
            for _ in range(2):
                choose_row(1,error=('Cannot read assets','Storage operation failed.'))
                checked('settings-io-error-recovery-'+str(len(checks)))
            if case=='read-error':choose_row(0);checked('settings-readable-row-after-error')
        elif case=='stress':
            for cycle in range(8):
                for row in range(6):choose_row(row)
                close_settings();checked('settings-stress-close-'+str(cycle))
                open_settings(slot);checked('settings-stress-open-'+str(cycle))
        if case=='mixed':
            for x,y in ((0,65),(22,10),(8,75)):
                drag(slot,x,y);checked(f'settings-drag-{x}-{y}')
            root_focus();checked('settings-desktop-focus')
            x,y,_,_=rects[slot];move(x+12,y+5);click();focus=slot;menu=b'\0';checked('settings-refocus')
        close_settings();checked('settings-close')
        open_settings(slot);checked('settings-reopen');close_settings();checked('settings-reclose')
        if case=='mixed':
            key('ESCAPE');order.remove(3);del rects[3];del titles[3];calculators.clear();focus=2;menu=CLOCK
            checked('settings-calculator-recovered')
            key('ESCAPE');order.remove(2);del rects[2];del titles[2];clocks.clear();clock_slot=None;focus=1;menu=bytes((1,10))+b'View\0\0\0\0'
            checked('settings-clock-recovered')
            key('ESCAPE');order.remove(1);del rects[1];del titles[1];filemanagers.clear();focus=0;menu=DESKTOP
            checked('settings-clean-desktop')
    if case not in ('normal','mixed','contexts','readback-error') and image.read_bytes()!=initial:raise AssertionError('read-only Settings scenario changed disk')
    for name,digest in fixture['payloads'].items():
        if name=='GEOBENCH.CFG':digest=hashlib.sha256(expected).hexdigest()
        if hashlib.sha256(subprocess.check_output(['mtype',*target,'::/'+name])).hexdigest()!=digest:
            raise AssertionError('unrelated Settings disk payload changed: '+name)
    report=dict(case=case,checkpoints=checks,stack=stack,config_sha256=hashlib.sha256(expected).hexdigest(),
                published_sha256=hashlib.sha256(published).hexdigest(),
                verified_payloads=len(fixture['payloads']),
                fault_injection='test-only GBEDIT readback client' if case=='readback-error' else
                                'test-only Settings client: enumerated asset disappears before M4 open' if case=='read-error' else 'disk fixture only',
                native_settings=manifest['sections']['settings'],delivery=fixture['delivery'])
    (artifacts/'result.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS '+('delivered' if fixture['delivery'] else 'private')+' Settings '+json.dumps(report),flush=True)
    return artifacts
