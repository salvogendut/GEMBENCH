"""Unchanged Notepad, real CPC Desktop document launches, disposable M4 only."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
from cpc_production_lifetime import physical
from test_cpc_foundation_1984 import snapshot

APP_SHA='fae9ad2f6da69b906af13836f7230095d2ca8421211a8f80a79e310813f933b7'
QUIT_APP_SHA=APP_SHA
DOCUMENTS={'/ADOC/EXACT.TXT':b'abc\nxyz\n','/ADOC/SUB/EXACT.TXT':b'Nested document.\n'}
BASIC_PATH='/ADOC/DIR.EXT/ROUND.BAS'
BASIC_DISK=b'10 PRINT "ONE"\r\n20 END\r\n'
BASIC_SEED='/ADOC/DIR.EXT/SEED.TXT'

def documents(case):
    result=dict(DOCUMENTS)
    if case=='config':
        result['/ADOC/GEOBENCH.CFG']=b'FONT=DEFAULT\nVIEW=ICONS\n'
    if case=='basic':
        result[BASIC_PATH]=BASIC_DISK
        result[BASIC_SEED]=b'Open BASIC through Notepad.\n'
    if case=='boundary':
        result['/ADOC/EXACT.TXT']=(b'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ\n'*111)[:4096]
        result['/ADOC/TOOLARGE.TXT']=result['/ADOC/EXACT.TXT']+b'!'
    return result

def prepare(manifest,app,image,artifacts,case):
    delivery=manifest['profile'] in ('cpc-desktop-m4-v4','cpc-desktop-m4-v5')
    if not delivery and manifest['profile']!='cpc-notepad-handoff-private-v1':
        raise ValueError('Notepad requires the explicit API-v3/text-input receiver')
    app=Path(app);data=app.read_bytes()
    digest=hashlib.sha256(data).hexdigest()
    if digest not in (APP_SHA,QUIT_APP_SHA):raise ValueError('not a pinned universal Notepad APP')
    if case=='quit' and digest!=QUIT_APP_SHA:raise ValueError('Quit test requires the menu-update APP')
    (artifacts/'NOTEPAD.APP').write_bytes(data)
    (artifacts/'probe.noi').write_bytes(app.with_suffix('.noi').read_bytes())
    target=['-i',str(image)+'@@16384']
    if delivery and subprocess.check_output(['mtype',*target,'::/GBENCH/NOTEPAD.APP'])!=data:
        raise ValueError('delivered Notepad differs from the accepted APP')
    for name in ('::/ADOC','::/ADOC/SUB'):subprocess.run(['mmd',*target,name],check=True)
    if case=='basic':subprocess.run(['mmd',*target,'::/ADOC/DIR.EXT'],check=True)
    for index,(path,payload) in enumerate(documents(case).items()):
        file=artifacts/f'document-{index}.txt';file.write_bytes(payload)
        subprocess.run(['mcopy',*target,str(file),'::'+path],check=True)
    if case=='write-denied':
        subprocess.run(['mattrib',*target,'+r','::/ADOC/EXACT.TXT'],check=True)
    # A separate pristine alias proves a failed document launch does not leave
    # pending identity for the next blank launch. No source/manual image edits.
    if case=='bad-app':
        subprocess.run(['mcopy','-o',*target,str(artifacts/'NOTEPAD.APP'),'::/GBENCH/CALC.APP'],check=True)
    if case=='bad-app':
        bad=bytearray(data);bad[-1]^=1;(artifacts/'bad.APP').write_bytes(bad)
    if not delivery or case=='bad-app':
        subprocess.run(['mcopy','-o',*target,str(artifacts/('bad.APP' if case=='bad-app' else 'NOTEPAD.APP')),
                        '::/GBENCH/NOTEPAD.APP'],check=True)
    if case=='disk-full':
        from cpc_fswrite_cases import space
        free,_=space(image)
        filler=artifacts/'filler.bin'
        with filler.open('wb') as f:f.truncate(free*1024)
        subprocess.run(['mcopy',*target,str(filler),'::/FILLER.BIN'],check=True)
        if space(image)[0]:raise AssertionError('disk-full fixture still has free clusters')

def exercise(manifest,work,sym,image,artifacts,case,send,wait,read,key,move):
    from test_cpc_runtime_1984 import integrity
    from embed_app_icon import parse_manifest
    def symbols(path):return {k:int(v,16) for k,v in re.findall(r'^DEF (\w+) (0x[0-9A-Fa-f]+)',path.read_text(),re.M)}
    app=(artifacts/'NOTEPAD.APP').read_bytes();primary=parse_manifest(app)['segments'][0]['stored_length']
    ns=symbols(artifacts/'probe.noi');fs=symbols(work/'filemgr/filemgr.noi')
    offsets={k:int(v,16)+(fs['s__INITIALIZED']-fs['s__DATA'] if area=='2' else 0)
             for area,k,v in re.findall(r'^\s+([12])\s+(\w+)\s+([0-9A-Fa-f]+)\s+R',
               (work/'filemgr/main.sym').read_text(),re.M)}
    checks=[];slot=2
    def ram():return snapshot(read())[1]
    def until(label,predicate):
        for _ in range(400):
            wait(5);r=ram()
            if predicate(r):return r
        raise AssertionError(label+' did not complete')
    def checked(label):
        wait(30)
        # Mode publication precedes painting. Observe an idle drawing boundary
        # rather than rejecting a snapshot taken inside a legitimate repaint.
        for _ in range(400):
            data=read(label)
            if not snapshot(data)[1][sym['core_pointer_paintlock']]:break
            wait(5)
        else:raise AssertionError(label+': repaint did not finish')
        r,stack=integrity(data,sym,work)
        if r[0x2F1F]!=3 or r[sym['cpc_fs_pending']]:raise AssertionError('API/stranded handoff')
        checks.append(dict(name=label,stack=stack))
        send(f'crop {artifacts/(label+".ppm")} 0 0 768 576 1')
        print('notepad: '+label,flush=True)
        return r
    def base(r,s):return physical(r[sym['wm_table']+25*s])
    def view(r):return r[base(r,slot)+ns['_editor']-0x4000:base(r,slot)+ns['_editor']-0x4000+19]
    def mode(r):return r[base(r,slot)+ns['_mode']-0x4000]
    def field(r,n,size=1):
        at=base(r,1)+fs['s__DATA']-0x4000+offsets['_'+n];return r[at:at+size]
    def pointer(x,y):
        send('key-down Left_Ctrl')
        try:move(x,y)
        finally:send('key-up Left_Ctrl')
    def click():
        send('key-down Left_Ctrl')
        try:
            for action,held in (('key-down SPACE',True),('key-up SPACE',False)):
                send(action);until('pointer click',lambda r:bool(r[sym['poll_lastfire']])==held)
        finally:send('key-up Left_Ctrl')
    def focus_filemgr():
        r=ram();x,y,w,h=r[sym['wm_table']+26:sym['wm_table']+30]
        pointer(x+w-2,y+h-2);click()
        return until('File Manager refocus for reuse',lambda state:state[sym['wm_focus']]==1)
    def named(name,attempts=0):
        if attempts>=40:raise AssertionError('File Manager scroll bound exceeded')
        r=until('directory',lambda r:field(r,'list_state')==b'\0')
        names=field(r,'names',1144);order=field(r,'order',field(r,'total')[0])
        for index,entry in enumerate(order):
            if names[entry*11:entry*11+11]==name:
                index+=bool(field(r,'fm_path')[0]);row,col=divmod(index,3)
                x,y,w,h=r[sym['wm_table']+26:sym['wm_table']+30]
                cy=y+20+(row-field(r,'top')[0])*44
                if cy>=y+h-1:
                    pointer(x+2,y+h-5);click();wait(15);return named(name,attempts+1)
                if field(r,'view')!=b'\1' or not y+14<=cy<y+h-1:raise AssertionError('entry not visible')
                pointer(x+4+col*((w-5)//3)+6,cy);click();click();return
        raise AssertionError('missing entry '+repr(name))
    def text_key(name,predicate):
        send('key-down '+name)
        try:until('key '+name,predicate)
        finally:send('key-up '+name)
        wait(25)
    def held_escape(label,predicate):
        send('key-down ESCAPE')
        try:
            until(label,predicate);wait(150)
            r=checked(label)
            if not predicate(r):raise AssertionError(label+': held Escape reached another consumer')
        finally:send('key-up ESCAPE')
        wait(25)
        return r
    def leaf(r,n):
        owner=r[sym['core_win_owner']+slot]
        seal=r[sym['sec_table']+(owner-1)*8:sym['sec_table']+owner*8]
        if not seal[0] or not seal[1]:raise AssertionError('missing secondary seal')
        page=r[sym['core_page_native']+seal[1]-1]
        # Frozen accepted model layout: DATA=5E00, CRT prefix one byte.
        start=physical(page)+0x1E01;return r[start:start+n]
    before=checked('boot');pages=before[sym['core_page_state']:sym['core_page_state']+32]
    pointer(76,190);click();pointer(3,26);click();click()
    until('File Manager',lambda r:r[sym['wm_nwin']]==2)
    folder=b'/GBENCH\0' if case=='blank' else b'/ADOC\0'
    named(b'GBENCH     ' if case=='blank' else b'ADOC       ')
    until('document folder',lambda r:field(r,'fm_path',len(folder))==folder)
    expected_files=documents(case)
    if case=='basic':
        named(b'DIR     EXT')
        until('dotted document folder',lambda r:field(r,'fm_path',14)==b'/ADOC/DIR.EXT\0')
    for cycle,nested in enumerate((False,)*12 if case=='stress' else
                                  (False,) if case in ('blank','config','basic') else (False,True)):
        path=BASIC_SEED if case=='basic' else \
             '/ADOC/GEOBENCH.CFG' if case=='config' else \
             '/ADOC/SUB/EXACT.TXT' if nested else '/ADOC/EXACT.TXT'
        expected=b'' if case=='blank' else expected_files[path]
        if case=='basic':expected=expected.replace(b'\r',b'')
        if nested:
            named(b'SUB        ');until('SUB',lambda r:field(r,'fm_path',10)==b'/ADOC/SUB\0')
        named(b'NOTEPAD APP' if case=='blank' else
              b'SEED    TXT' if case=='basic' else
              b'GEOBENCHCFG' if case=='config' else b'EXACT   TXT')
        if case=='bad-app':
            wait(150);wait(150);r=checked('rejected-document')
            if r[sym['wm_nwin']]!=2:raise AssertionError('bad APP was published')
            # Dismiss the real File Manager failure alert before closing it.
            key('ESCAPE');break
        if case=='reuse-dirty' and nested:
            until('dirty reuse confirmation',lambda r:r[sym['wm_nwin']]==3 and
                  r[sym['wm_focus']]==slot and mode(r)==2)
            checked('dirty-reuse-confirmation')
            key('ESCAPE');r=until('dirty reuse cancelled',lambda r:mode(r)==0)
            root=expected_files['/ADOC/EXACT.TXT']
            if view(r)[:2]!=(len(root)+1).to_bytes(2,'little') or not view(r)[13]:
                raise AssertionError('reuse Cancel lost the dirty root document')
            focus_filemgr();named(b'EXACT   TXT')
            until('dirty reuse confirmation retry',lambda r:r[sym['wm_focus']]==slot and mode(r)==2)
            pointer(16,58);click() # Discard
        until('Notepad focus',lambda r:r[sym['wm_nwin']]==3 and r[sym['wm_focus']]==slot)
        until('document load',lambda r:mode(r)==0 and
              view(r)[:2]==len(expected).to_bytes(2,'little') and not view(r)[13])
        r=checked(('nested-document' if nested else 'root-document')+f'-{cycle}')
        if case in ('reuse','reuse-dirty') and cycle and r[sym['wm_nwin']]!=3:
            raise AssertionError('live document open allocated another window')
        if view(r)[:2]!=len(expected).to_bytes(2,'little') or view(r)[13] or leaf(r,len(expected))!=expected:
            raise AssertionError('wrong document identity/content')
        if r[base(r,slot):base(r,slot)+primary]!=app[:primary]:raise AssertionError('primary APP changed')
        if case=='config':
            wait(80)
            text_key('Z',lambda state:view(state)[0:2]==(len(expected)+1).to_bytes(2,'little'))
            changed=b'z'+expected
            pointer(11,3);click();wait(20);pointer(12,34);click()
            r=until('configuration save',lambda state:mode(state)==0 and not view(state)[13])
            if int.from_bytes(r[sym['cpc_cfg_length']:sym['cpc_cfg_length']+2],'little')!=len(changed):
                raise AssertionError('resident configuration length was not published')
            if r[sym['cpc_cfg_text']:sym['cpc_cfg_text']+len(changed)]!=changed:
                raise AssertionError('resident configuration bytes differ from saved document')
            expected_files[path]=changed;checked('configuration-published')
        if case=='basic' and not cycle:
            def app_state(state,name,size):
                at=base(state,slot)+ns[name]-0x4000
                return state[at:at+size]
            def picker_ready(state):return mode(state)==1 and app_state(state,'_scratch',9)[8]==5
            def load_basic():
                pointer(11,3);click();wait(20);pointer(12,24);click()
                for _ in range(32):
                    state=until('BASIC chooser',picker_ready);picker=app_state(state,'_scratch',161)
                    for row in range(picker[10]):
                        if picker[89+12*row:100+12*row]==b'ROUND   BAS':
                            pointer(10,48+row*10);click();return
                    if not picker[11]:raise AssertionError('BASIC missing from chooser')
                    pointer(22,112);click()
                raise AssertionError('BASIC chooser page bound exceeded')
            normalized=BASIC_DISK.replace(b'\r',b'')
            load_basic()
            r=until('BASIC normalized load',lambda state:mode(state)==0 and
                    view(state)[:2]==len(normalized).to_bytes(2,'little') and not view(state)[13])
            if leaf(r,len(normalized))!=normalized:raise AssertionError('BASIC CRLF was not normalized')
            checked('basic-crlf-loaded');wait(80)
            text_key('Z',lambda state:view(state)[0:2]==(len(normalized)+1).to_bytes(2,'little'))
            changed=b'z'+normalized
            if leaf(ram(),len(changed))!=changed:raise AssertionError('BASIC edit differs')
            pointer(11,3);click();wait(20);pointer(12,34);click()
            r=until('BASIC save',lambda state:mode(state)==0 and not view(state)[13])
            if view(r)[:2]!=len(changed).to_bytes(2,'little') or leaf(r,len(changed))!=changed:
                raise AssertionError('BASIC save changed the normalized editor text')
            expected_files[BASIC_PATH]=changed.replace(b'\n',b'\r\n')
            checked('basic-crlf-saved')
            load_basic()
            r=until('BASIC exact reopen',lambda state:mode(state)==0 and
                    view(state)[:2]==len(changed).to_bytes(2,'little') and not view(state)[13])
            if leaf(r,len(changed))!=changed:raise AssertionError('BASIC reopen differs')
            checked('basic-crlf-reopened')
        if case in ('blank','boundary','clipboard','write-denied','disk-full','stress'):
            from types import SimpleNamespace
            from cpc_notepad_acceptance import exercise_case
            exercise_case(case,nested,expected,path,expected_files,SimpleNamespace(
                ram=ram,until=until,checked=checked,view=view,mode=mode,leaf=leaf,
                base=base,slot=slot,ns=ns,sym=sym,wait=wait,key=key,send=send,
                pointer=pointer,click=click,text_key=text_key,held_escape=held_escape))
        if not nested and case=='handoff':
            wait(80);old_pointer=r[sym['poll_byte']:sym['poll_byte']+2]
            for k,c in (('RIGHT',1),('DOWN',5),('LEFT',4),('UP',0),('RIGHT',1)):
                text_key(k,lambda r,c=c:view(r)[2:4]==c.to_bytes(2,'little'))
            text_key('Z',lambda r:view(r)[0]==9)
            text_key('SPACE',lambda r:view(r)[0]==10)
            text_key('BACKSPACE',lambda r:view(r)[0]==9)
            r=checked('arrow-space-edit')
            expected=b'azbc\nxyz\n'
            if leaf(r,len(expected))!=expected or not view(r)[13]:raise AssertionError('wrong edited text')
            if r[sym['poll_byte']:sym['poll_byte']+2]!=old_pointer:raise AssertionError('text moved pointer')
            old_view=view(r)
            pointer(76,190);click();until('desktop focus',lambda r:r[sym['wm_focus']]==0)
            r=ram();px=r[sym['poll_byte']]
            key('RIGHT');r=checked('background-pointer')
            if r[sym['poll_byte']]<=px or view(r)!=old_view:raise AssertionError('background text consumed pointer input')
            pointer(30,20);click();until('editor focus',lambda r:r[sym['wm_focus']]==slot)
            checked('focus-return')
            pointer(11,3);click();wait(20);pointer(12,34);click()
            until('save',lambda r:mode(r)==0 and not view(r)[13]);checked('save-in-place')
            expected_files[path]=expected
        if case in ('reuse','reuse-dirty') and not nested:
            if case=='reuse-dirty':
                wait(80) # match the launch-click drain before text input
                text_key('Z',lambda state:view(state)[0:2]==(len(expected)+1).to_bytes(2,'little'))
                r=checked('dirty-reuse-source')
            # Raise File Manager through its exposed lower frame, then launch a
            # second exact-path document. The registered editor must be reused.
            focus_filemgr()
            checked('reuse-source-refocused')
            continue
        if case in ('quit','escape'):
            def quit_menu(label):
                pointer(11,3);click();wait(20);checked(label)
                pointer(12,54);click()
            if nested:
                wait(80) # match the initial editor's launch-click drain/paint settle
                text_key('Z',lambda r:view(r)[0]==len(expected)+1)
                if case=='escape':
                    held_escape('escape-dirty-close',lambda r:mode(r)==2)
                    r=held_escape('escape-cancel-held',lambda r:mode(r)==0)
                else:
                    quit_menu('dirty-quit-menu')
                    until('dirty Quit confirmation',lambda r:mode(r)==2)
                    checked('quit-confirmation');pointer(28,58);click()
                    r=until('Quit cancelled',lambda r:mode(r)==0)
                if not view(r)[13] or view(r)[0]!=len(expected)+1:
                    raise AssertionError('Quit Cancel lost dirty document')
                checked('quit-cancelled');quit_menu('discard-quit-menu')
                until('discard confirmation',lambda r:mode(r)==2);pointer(16,58);click()
            elif case=='escape':held_escape('escape-clean-close-held',lambda r:r[sym['wm_nwin']]==2)
            else:quit_menu('clean-quit-menu')
        else:key('ESCAPE')
        until('editor close',lambda r:r[sym['wm_nwin']]==2)
        r=checked(('closed-nested' if nested else 'closed-root')+f'-{cycle}')
        if any(r[sym['sec_table']:sym['sec_table']+64]):raise AssertionError('per-cycle secondary seal leak')
    key('ESCAPE');until('File Manager close',lambda r:r[sym['wm_nwin']]==1)
    if case=='bad-app':
        slot=1;pointer(11,3);click();wait(15);pointer(12,23);click()
        until('blank Notepad',lambda r:r[sym['wm_nwin']]==2)
        r=checked('blank-after-rejection')
        if mode(r) or view(r)[:2]!=b'\0\0':raise AssertionError('stale document inherited')
        key('ESCAPE');until('blank close',lambda r:r[sym['wm_nwin']]==1)
    r=checked('clean-desktop')
    if r[sym['core_page_state']:sym['core_page_state']+32]!=pages or any(r[sym['sec_table']:sym['sec_table']+64]):
        raise AssertionError('page/seal leak')
    if any(r[sym['core_fsctx_table']+144*i] for i in range(4)):raise AssertionError('context leak')
    for path,expected in expected_files.items():
        if subprocess.check_output(['mtype','-i',str(image)+'@@16384','::'+path])!=expected:
            raise AssertionError('independent saved-file readback differs: '+path)
    send(f'crop {artifacts/"result.ppm"} 0 0 768 576 1')
    report=dict(status='PASS',case=case,checks=checks,app_sha256=hashlib.sha256(app).hexdigest(),sections=manifest['sections'])
    (artifacts/'result.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS CPC Notepad '+case,flush=True)
    return artifacts
