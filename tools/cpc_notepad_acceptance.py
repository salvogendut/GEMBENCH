"""Actual unchanged Notepad acceptance through CPC/M4 keyboard and menus.

Only read-only snapshots observe editor/ownership state. Faults are staged in
disposable media before boot; no debugger writes or replacement APP code.
"""
from cpc_graphics_fixture import address


def exercise_case(case,nested,expected,path,expected_files,d):
    def menu(row,edit=False):
        d.pointer(19 if edit else 11,3);d.click();d.wait(20)
        d.pointer(20 if edit else 12,14+row*10);d.click()
    def app(r,name,size):
        at=d.base(r,d.slot)+d.ns[name]-0x4000
        return r[at:at+size]
    def ready(r):return d.mode(r)==1 and app(r,'_scratch',9)[8]==5
    def type_name(name):
        for i,ch in enumerate(name):
            d.text_key('.' if ch=='.' else ch.upper(),
                       lambda r,i=i:app(r,'_scratch',89)[76+i]!=0)
        d.text_key('RETURN',lambda r:d.mode(r)!=1)
    def save_as(name,result=0):
        menu(3);d.until('Save As chooser',ready);d.wait(50)
        type_name(name)
        d.until('explicit overwrite guard',lambda r:d.mode(r)==9)
        d.checked('save-as-confirmation');d.wait(60)
        d.text_key('S',lambda r:d.mode(r)==result and (result or not d.view(r)[13]))
    def load(name,result):
        menu(1)
        for _ in range(32):
            r=d.until('Load chooser',ready);p=app(r,'_scratch',161)
            for row in range(p[10]):
                if p[89+12*row:100+12*row]==name:
                    d.pointer(10,48+row*10);d.click()
                    d.until('load outcome',lambda r:d.mode(r)==result);d.wait(100)
                    return
            if not p[11]:raise AssertionError('file missing from chooser')
            d.pointer(22,112);d.click()
        raise AssertionError('chooser page bound exceeded')
    def retained(label,payload,dirty):
        r=d.checked(label)
        if (d.view(r)[:2]!=len(payload).to_bytes(2,'little') or
            bool(d.view(r)[13])!=dirty or d.leaf(r,len(payload))!=payload):
            raise AssertionError(label+': document content/dirty state differs')
        return r
    def settle():
        at=d.sym['cpc_runtime_turns'];r=d.ram();before=int.from_bytes(r[at:at+2],'little')
        d.until('editor click debounce',lambda r:
                ((int.from_bytes(r[at:at+2],'little')-before)&65535)>=12)
    d.wait(80)
    if case=='blank':
        d.text_key('Z',lambda r:d.view(r)[0]==1)
        save_as('UNOTE.TXT');retained('direct-app-launch-edit-save',b'z',False)
        expected_files['/UNOTE.TXT']=b'z'
    elif case=='boundary' and not nested:
        d.key('X');retained('4096-capacity-edit-rejected',expected,False)
        save_as('FRESH.TXT');retained('4096-save-as',expected,False)
        expected_files['/ADOC/FRESH.TXT']=expected
        load(b'TOOLARGETXT',7);retained('4097-rejected-old-document-retained',expected,False)
        d.text_key('RETURN',lambda r:d.mode(r)==0)
        # Reopen what the guest actually wrote, then independently mtype it at
        # teardown. Neither the original file nor an in-memory round trip suffices.
        load(b'FRESH   TXT',0);retained('4096-reopened',expected,False)
        menu(1);d.until('chooser cancellation',ready)
        d.held_escape('chooser-escape-held',lambda r:d.mode(r)==0)
        retained('chooser-cancel-keeps-document',expected,False)
    elif case=='clipboard':
        menu(0,True);d.checked('select-all')
        if not nested:
            menu(1,True)
            r=d.checked('clipboard-copy')
            at=d.sym['cpc_clipboard_base']
            if r[at:at+2+len(expected)]!=len(expected).to_bytes(2,'little')+expected:
                raise AssertionError('clipboard bytes differ')
        else:
            # The producer owner has already closed: paste into a new owner
            # and replace its selection, then save through the real M4 service.
            payload=expected_files['/ADOC/EXACT.TXT']
            menu(2,True);retained('paste-after-producer-close',payload,True)
            menu(2);d.until('pasted document saved',lambda r:d.mode(r)==0 and not d.view(r)[13])
            expected_files[path]=payload;retained('clipboard-save',payload,False)
    elif case in ('write-denied','disk-full') and not nested:
        d.text_key('Z',lambda r:d.view(r)[0]==len(expected)+1)
        dirty=b'z'+expected
        if case=='disk-full':save_as('NOSPACE.TXT',7)
        else:
            menu(2);d.until('read-only save rejected',lambda r:d.mode(r)==7)
        retained(case+'-retains-dirty-text',dirty,True)
        settle()
        d.text_key('RETURN',lambda r:d.mode(r)==0)
        if case=='disk-full':
            menu(0);d.until('dirty New confirmation',lambda r:d.mode(r)==2)
            d.held_escape('failed-save-dirty-cancel',lambda r:d.mode(r)==0)
            retained('failed-save-cancel-preserves-edit',dirty,True)
            menu(0);d.until('explicit discard',lambda r:d.mode(r)==2)
            d.pointer(16,58);d.click()
            d.until('new blank after discard',lambda r:d.mode(r)==0 and not any(d.view(r)[:2]))
        else:
            # Retry to a writable new name, leaving the protected original intact.
            save_as('RECOVER.TXT');retained('write-denied-recovered-save-as',dirty,False)
            expected_files['/ADOC/RECOVER.TXT']=dirty
    elif case=='stress':
        # Caret repaint must not scribble over the File Manager in front.
        # Click its exposed bottom strip; park outside both windows.
        r=d.ram();x,y,w,h=r[d.sym['wm_table']+26:d.sym['wm_table']+30]
        d.pointer(x+w//2,y+h-4);d.click()
        d.until('covering File Manager focus',lambda r:r[d.sym['wm_focus']]==1)
        d.pointer(76,190);d.wait(80);before=d.ram()
        x,y,w,h=before[d.sym['wm_table']+26:d.sym['wm_table']+30]
        def pixels(r):
            return bytes(r[0xC000+address(col*4,line)]
                         for line in range(y,y+h) for col in range(x,x+w))
        d.wait(180);after=d.ram()
        if pixels(before)!=pixels(after):raise AssertionError('covered editor damaged foreground window')
        d.checked('occluded-caret-stable')
        d.pointer(30,20);d.click()
        d.until('editor refocused',lambda r:r[d.sym['wm_focus']]==d.slot)
        retained('refocus-document',expected,False)
