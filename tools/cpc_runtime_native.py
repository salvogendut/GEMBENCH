"""Real shared native UI/config execution; all observations are read-only."""
import json
from cpc_production_lifetime import physical
from cpc_runtime_pixels import verify_pixels
from test_cpc_foundation_1984 import snapshot


CONFIG_CASES = {
    'missing': None,
    'empty': b'',
    'exact': b'ICONS=CLASSIC\r\n'+b'#'*(512-15),
    'oversized': b'ICONS=CLASSIC\r\n'+b'#'*(513-15),
    'custom': b'# FONT=WRONG\r\nICONS=ABCDEFGH9\r\nFONT=SMALL\r\nCURSOR=ARROW\r\n'
              b'BACKDROP=C:TILE.BDP\r\nINKS=1,26,1,6,99\r\nDEBUG=TRUE\r\nUNKNOWN=X\r\n',
}


def run_native(root,media,manifest,work,sym,artifacts,image,emulator,send,wait,read,key,move,
               native_fault=None, config_case=None):
    from test_cpc_runtime_1984 import integrity
    rects={1:(11,66,58,68)};order=[0,1];accents={1:0}
    menu=b'\0';titles={};calculators={};clocks={};slot=None;popup=None;dialog=None
    checks=[];stacks={'main':0,'irq':0,'tmp':0}
    noi={v[1]:int(v[2],16) for line in (root/'build/universal-obj/uclock/app.noi').read_text().splitlines()
         if len(v:=line.split())==3 and v[0]=='DEF'}
    offsets={v[1]:int(v[2],16) for line in (root/'build/universal-obj/uclock/main.sym').read_text().splitlines()
             if len(v:=line.split())==4 and v[0]=='1' and v[3]=='R'}
    def word(r,name): return int.from_bytes(r[sym[name]:sym[name]+2],'little')
    def value(r,name):
        at=physical(r[sym['wm_table']+25*slot])+noi['s__DATA']-0x4000+offsets['_'+name]
        return r[at]
    def observe(name,modal=False):
        previous=None
        for _ in range(180):
            data=read(name);_,r=snapshot(data)
            if r[sym['pointer_visible']] and not r[sym['core_pointer_paintlock']] and not r[sym['io_busy']]:
                if slot is None or (value(r,'have_prev') and (modal or (not value(r,'timer_digit_due') and
                    (value(r,'ph'),value(r,'pm'))==(value(r,'dh'),value(r,'dm')) and
                    (not value(r,'show_sec') or value(r,'ps')==value(r,'ds'))))):
                    signature=bytes(r[0xC000:0x10000])+bytes(r[0x1240:0x1242])
                    turn=word(r,'cpc_runtime_turns')
                    if previous and signature==previous[0] and (modal or turn!=previous[1]): break
                    previous=signature,turn
            wait(3)
        else: raise AssertionError(name+': draw not complete')
        r,used=integrity(data,sym,work)
        for k,n in used.items(): stacks[k]=max(stacks[k],n)
        if bool(r[sym['ui_modal']])!=modal: raise AssertionError(name+': modal gate leaked')
        if slot is not None: clocks[slot]=tuple(value(r,k) for k in ('ph','pm','ps','show_sec','dh','dm','ds'))
        verify_pixels(r,sym,work,rects,order,accents,menu,titles,popup,calculators,clocks,dialog)
        if r[sym['wm_nwin']]!=len(order) or r[sym['wm_z']:sym['wm_z']+len(order)]!=bytes(order):
            raise AssertionError(name+': window lifecycle changed during modal')
        if sym['cpc_system_page'] in r[sym['core_page_native']:sym['core_page_native']+sym['cpc_pool_pages']]:
            raise AssertionError('module bank admitted to application allocator')
        checks.append(name);print(f'{name}: stack={stacks}',flush=True)
        send(f'crop {artifacts/(name+".ppm")} 0 0 768 576 1')
        return r
    def pulse(name):
        # Hold actual input until sampled; a short pulse can fall wholly inside
        # a Clock software draw. This acknowledges input, never injects RAM.
        field='in_quit' if name=='ESCAPE' else 'poll_lastfire' if name=='SPACE' else 'cpc_key_previous'
        target=4 if name=='ESCAPE' else 32 if name=='SPACE' else \
               {'BACKSPACE':8,'RETURN':13,'TAB':9}.get(name,ord(name.lower()) if len(name)==1 else 0)
        matrix={'U':(5,2),'P':(3,3),'I':(4,3),'N':(5,6),'A':(8,5),'B':(6,6),'C':(7,6),
                'BACKSPACE':(9,7),'RETURN':(2,2),'TAB':(8,4),'6':(6,0),'4':(7,0),'3':(7,1),'2':(8,1)}
        for command,wanted in (('key-down '+name,target),('key-up '+name,0)):
            send(command)
            for _ in range(180):
                wait(3);_,r=snapshot(read())
                if not wanted and name in matrix:
                    row,bit=matrix[name]
                    if r[sym['cpc_keys']+row] & (1<<bit): break
                elif r[sym[field]]==wanted: break
            else: raise AssertionError('input not acknowledged: '+command)
        wait(15)
    def root_focus():
        nonlocal menu
        move(76,185);key('SPACE');menu=bytes((1,10))+b'Desk\0\0\0\0'
    def module(r,name):
        raw=(work/(name+'.MOD')).read_bytes();at=physical(sym['cpc_system_page'])
        if r[at:at+len(raw)]!=raw: raise AssertionError(name+' module code corrupted')
    def cfg(r):
        at=sym['cpc_cfg_output'];length=word(r,'cpc_cfg_output')
        expected=CONFIG_CASES[config_case] if config_case else (media/'CARD/GEOBENCH.CFG').read_bytes()
        valid=expected is not None and len(expected)<=512
        if length!=(len(expected) if valid else 0): raise AssertionError('config length/fallback')
        if valid and r[sym['cpc_cfg_text']:sym['cpc_cfg_text']+length]!=expected:
            raise AssertionError('config bytes changed')
        stem=b'ABCDEFGH' if config_case=='custom' else b'CLASSIC ' if config_case=='exact' else \
             b'DEFAULT ' if config_case else b'REFINED '
        font=b'SMALL   ' if config_case=='custom' else b'DEFAULT '
        if r[at+2:at+13]!=stem+b'IST' or r[at+13:at+24]!=font+b'FNT':
            raise AssertionError('shared config parser/defaults differ')
        if r[at+26:at+31]!=b'512K\0': raise AssertionError('RAM output')
        if config_case=='custom':
            if r[at+33:at+44]!=b'ARROW   SPR' or r[at+49:at+60]!=b'TILE    BDP' or \
               r[at+44:at+49]!=bytes((1,26,1,6,26)) or r[at+60:at+63]!=bytes((0,0,1)):
                raise AssertionError('shared config normalization differs')
        status=r[sym['cpc_cfg_status']]
        if status!=(19 if config_case=='missing' else 2 if config_case=='oversized' else 0):
            raise AssertionError('configuration status differs: '+str(status))
        module(r,'GBCFG')
    r=observe('native-config-boot');cfg(r)
    root_focus();r=observe('native-root-focus')
    if config_case:
        key('R');r=observe('native-config-reload');cfg(r)
        if word(r,'cpc_cfg_calls')!=1: raise AssertionError('reload was not executed')
    elif native_fault:
        before=word(r,'cpc_ui_calls');key('U');r=observe('native-module-rejected')
        if r[sym['cpc_ui_status']]!=1 or r[sym['cpc_ui_request']+4]!=255 or \
           word(r,'cpc_ui_calls')!=before+1: raise AssertionError('failed module did not cancel')
        key('F2');rects[2]=(26,20,28,122);order.append(2);titles[2]='Clock';slot=2
        menu=bytes((2,10))+b'View\0\0\0\0'+bytes((17,))+b'Options\0'
        observe('native-module-failure-clock-recovery')
    else:
        key('F7');rects[2]=(24,24,31,144);order.append(2);titles[2]='Calculator';calculators[2]='0'
        menu=bytes((1,10))+b'Edit\0\0\0\0';observe('native-calculator')
        key('7');key('2');calculators[2]='72';observe('native-calculator-value')
        key('F2');rects[3]=(26,20,28,122);order.append(3);titles[3]='Clock';slot=3
        menu=bytes((2,10))+b'View\0\0\0\0'+bytes((17,))+b'Options\0'
        observe('native-clock');key('S');root_focus();r=observe('native-live-background')
        workers=word(r,'cpc_runtime_worker_calls')
        pulse('U');popup=dict(x=23,y=84,hot=-1,labels=('Continue','Cancel'))
        r=observe('native-popup',True);module(r,'GBUI')
        frozen=word(r,'cpc_runtime_worker_calls');wait(150);r=observe('native-modal-worker-park',True)
        if word(r,'cpc_runtime_worker_calls')!=frozen: raise AssertionError('worker ran in module bank')
        move(25,97);popup['hot']=1;observe('native-popup-hover',True)
        pulse('SPACE');popup=None;r=observe('native-popup-selected')
        if r[sym['cpc_ui_request']+4]!=1: raise AssertionError('popup result')
        pulse('P');dialog=dict(kind='prompt');observe('native-prompt',True)
        pulse('A');pulse('B');pulse('BACKSPACE');pulse('C');dialog['value']='AC'
        observe('native-prompt-edit',True)
        pulse('RETURN');dialog=None;r=observe('native-prompt-accepted')
        if r[sym['cpc_ui_request']+4]!=1 or r[sym['cpc_ui_request']+8:sym['cpc_ui_request']+24]!=b'AC\0'+bytes(13):
            raise AssertionError('prompt result did not cross bank boundary')
        pulse('P');dialog=dict(kind='prompt');observe('native-prompt-again',True)
        pulse('ESCAPE');dialog=None;r=observe('native-prompt-cancel')
        if r[sym['cpc_ui_request']+4]: raise AssertionError('cancel accepted prompt')
        pulse('N');dialog=dict(kind='size');observe('native-size',True)
        pulse('6');pulse('4');pulse('TAB');pulse('3');pulse('2')
        dialog.update(values=('64','32'),active=1);observe('native-size-edit',True)
        pulse('RETURN');dialog=None;r=observe('native-size-accepted')
        at=sym['cpc_ui_request']
        if r[at+4]!=1 or r[at+8:at+12]!=bytes((64,0,32,0)): raise AssertionError('size result')
        identity=manifest['native_identity']
        pulse('I');dialog=dict(kind='about',build=f'Version : {identity["version"]} Git: {identity["git"]}')
        popup=dict(x=33,y=111,hot=-1,labels=('  OK  ',));observe('native-about',True)
        pulse('ESCAPE');popup=None;dialog=None;r=observe('native-about-restored')
        if word(r,'cpc_runtime_worker_calls')==workers: raise AssertionError('worker did not resume')
        key('R');r=observe('native-config-reload-live');cfg(r)
        key('F4');r=observe('native-M4-after-dialogs')
        if r[sym['cpc_runtime_fs_status']]: raise AssertionError('M4 service failed after modal')
        key('F7');order.remove(2);order.append(2);menu=bytes((1,10))+b'Edit\0\0\0\0'
        observe('native-calculator-preserved')
    report=dict(checkpoints=checks,stack=stacks,sections=manifest['sections'],
                native_fault=native_fault,config_case=config_case)
    (artifacts/'result.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS native config/UI '+json.dumps(report),flush=True)
    return artifacts
