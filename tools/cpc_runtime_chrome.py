"""3D-U M4-only chrome admission and real-window rendering regressions."""
import hashlib
import json
import subprocess

from cpc_runtime_pixels import DEFAULT_THEME, verify_pixels
from test_cpc_foundation_1984 import snapshot

CHROME_CASES=('default','custom','legacy','legacy-no-gadgets','title-missing',
              'title-short','title-trailing','legacy-short','legacy-trailing',
              'title-oversized','gadget-missing','gadget-short','gadget-trailing',
              'module-missing','module-short','module-trailing','unsafe-name',
              'unterminated','full-config','duplicate-key','empty-value')


def fixture(case, root, module):
    title=(root/'assets/titlebars/WEAVE.TBR').read_bytes()
    gadgets=(root/'assets/gadgets/IMPROVED.GDT').read_bytes()
    name='ALTTITLE';gname='ALTGAD';expected=title+gadgets;status=[0,0,0]
    if case=='default':
        name=gname='ORIGINAL';title=gadgets=None;expected=DEFAULT_THEME
    elif case=='custom': pass
    elif case.startswith('legacy'):
        # Distinct embedded gadget pair: only an explicit GDT may replace it.
        title+=bytes(b^0xFF for b in DEFAULT_THEME[56:])
        if case=='legacy-no-gadgets': gadgets=None;expected=title;status[2]=1
        elif case=='legacy-short': title=title[:-1];expected=DEFAULT_THEME[:56]+gadgets;status[1]=1
        elif case=='legacy-trailing': title+=b'\0';expected=DEFAULT_THEME[:56]+gadgets;status[1]=1
    elif case.startswith('title-'):
        expected=DEFAULT_THEME[:56]+gadgets;status[1]=1
        if case=='title-missing': title=None
        elif case=='title-short': title=title[:-1]
        elif case=='title-trailing': title+=b'\0'
        elif case=='title-oversized': title+=bytes(0x3F01-len(title))
    elif case.startswith('gadget-'):
        expected=title+DEFAULT_THEME[56:];status[2]=1
        if case=='gadget-missing': gadgets=None
        elif case=='gadget-short': gadgets=gadgets[:-1]
        elif case=='gadget-trailing': gadgets+=b'\0'
    elif case.startswith('module-'):
        expected=DEFAULT_THEME;status=[1,1,1]
        if case=='module-missing': module=None
        elif case=='module-short': module=module[:-1]
        elif case=='module-trailing': module+=b'\0'
    elif case in ('unsafe-name','empty-value'):
        name='../BAD' if case=='unsafe-name' else ''
        expected=DEFAULT_THEME[:56]+gadgets;status[1]=1
    elif case not in ('unterminated','full-config','duplicate-key'): raise ValueError(case)
    config=f'ICONS=REFINED\r\nFONT=DEFAULT\r\nCURSOR=DEFAULT\r\nBACKDROP=SOLID\r\nGADGETS={gname}.GDT\r\nTITLEBAR={name}.TBR\r\n'
    if case=='unterminated': config=config.rsplit('TITLEBAR=',1)[0]+'TITLEBAR=ALTTITLE'
    elif case=='duplicate-key': config+='TITLEBAR=ORIGINAL\r\nGADGETS=ORIGINAL\r\n'
    if case=='full-config':
        # Fill exactly 512 bytes and end within a short (<8-char) value.
        config='GADGETS=ALTGAD\r\n'+'#'+'x'*(512-len('GADGETS=ALTGAD\r\n')-len('\r\nTITLEBAR=LAST')-1)+'\r\nTITLEBAR=LAST'
        assert len(config)==512
        name='LAST'
    return dict(theme=expected,ready=not status[0],status=tuple(status),
                names=((name.split('.',1)[0][:8].ljust(8)+'TBR').encode(),(gname[:8].ljust(8)+'GDT').encode()),
                files={'/GEOBENCH.CFG':config.encode(),'/GBENCH/ALTTITLE.TBR':title,
                       '/GBENCH/LAST.TBR':title if case=='full-config' else None,
                       '/GBENCH/ALTGAD.GDT':gadgets,'/GBENCH/GBTITLE.MOD':module})


def prepare(case,work,root,image,artifacts):
    data=fixture(case,root,(work/'GBTITLE.MOD').read_bytes())
    target=['-i',str(image)+'@@16384']
    for name,payload in data['files'].items():
        if name in ('/GEOBENCH.CFG','/GBENCH/GBTITLE.MOD'):
            subprocess.run(['mdel',*target,'::'+name],check=True)
        if payload is not None:
            path=artifacts/name.rsplit('/',1)[-1];path.write_bytes(payload)
            subprocess.run(['mcopy',*target,str(path),'::'+name],check=True)
    return data


def run_chrome(media,manifest,work,sym,artifacts,image,emulator,send,wait,read,key,move,case,fixture):
    from test_cpc_runtime_1984 import integrity
    rects={1:(11,66,58,68)};order=[0,1];accents={1:0}
    menu=b'\0';titles={};calculators={};checks=[];stacks=dict(main=0,irq=0,tmp=0)
    original=image.read_bytes()
    def word(r,name): return int.from_bytes(r[sym[name]:sym[name]+2],'little')
    def observe(name):
        previous=None
        for _ in range(120):
            data=read(name);_,r=snapshot(data)
            if r[sym['pointer_visible']] and not r[sym['io_busy']] and not r[sym['core_pointer_paintlock']]:
                signature=bytes(r[0xC000:0x10000]);turn=word(r,'cpc_runtime_turns')
                if previous and signature==previous[0] and turn!=previous[1]: break
                previous=signature,turn
            wait(3)
        else: raise AssertionError(name+': incomplete drawing')
        r,used=integrity(data,sym,work,theme=fixture['theme'],title_ready=fixture['ready'])
        for k,n in used.items(): stacks[k]=max(stacks[k],n)
        status=tuple(r[sym[k]] for k in ('cpc_title_module_status','cpc_title_status','cpc_gadget_status'))
        if status!=fixture['status']: raise AssertionError((name,'fallback status',status,fixture['status']))
        for field,value in zip(('cpc_title_name','cpc_gadget_name'),fixture['names']):
            if r[sym[field]:sym[field]+11]!=value: raise AssertionError((name,field,r[sym[field]:sym[field]+11],value))
        verify_pixels(r,sym,work,rects,order,accents,menu,titles,None,calculators,
                      theme=fixture['theme'],title_ready=fixture['ready'])
        if r[sym['wm_nwin']]!=len(order) or r[sym['wm_z']:sym['wm_z']+len(order)]!=bytes(order):
            raise AssertionError(name+': ownership/z-order changed')
        for slot,rect in rects.items():
            at=sym['wm_table']+25*slot+1
            if r[at:at+4]!=bytes(rect): raise AssertionError(name+': window geometry')
        checks.append(name);send(f'crop {artifacts/(name+".ppm")} 0 0 768 576 1')
        print(f'{name}: chrome={status} stack={stacks}',flush=True)
        return r
    observe('chrome-boot')
    move(76,185);key('SPACE');menu=bytes((1,10))+b'Desk\0\0\0\0'
    r=observe('chrome-root-focus');before=word(r,'cpc_runtime_draw_calls');calls=word(r,'cpc_visual_calls')
    key('R');r=observe('chrome-unchanged-reload')
    if word(r,'cpc_visual_calls')!=calls+1 or r[sym['cpc_visual_dirty']] or word(r,'cpc_runtime_draw_calls')!=before:
        raise AssertionError('unchanged theme caused repaint / did not reload')
    if case in ('default','custom','legacy-no-gadgets','module-missing'):
        key('F7');rects[2]=(24,24,31,144);order.append(2);titles[2]='Calculator';calculators[2]='0'
        menu=bytes((1,10))+b'Edit\0\0\0\0';observe('chrome-calculator')
        key('7');key('2');calculators[2]='72';observe('chrome-calculator-72')
        # Focus the exposed Probe title. Its raise repairs a partly occluded
        # title/gadget without drawing into the foreground's retained pixels.
        move(19,70);key('SPACE');order=[0,2,1];menu=b'\0';observe('chrome-focus-probe')
        key('F7');order=[0,1,2];menu=bytes((1,10))+b'Edit\0\0\0\0'
        observe('chrome-focus-calculator')
        move(35,29);_,r=snapshot(read());grab=(r[sym['poll_byte']],r[sym['poll_line']])
        send('key-down SPACE');wait(10);move(41,43)
        _,r=snapshot(read());drop=(r[sym['poll_byte']],r[sym['poll_line']])
        send('key-up SPACE');wait(60)
        rects[2]=(max(0,min(49,24+drop[0]-grab[0])),max(8,min(56,24+drop[1]-grab[1])),31,144)
        observe('chrome-drag-exposure')
        # The loaded close artwork retains the shared close hit-test.
        x,y,w,h=rects[2];move(x+2,y+5);key('SPACE')
        del rects[2];del titles[2];del calculators[2];order=[0,1];menu=b'\0'
        observe('chrome-close-gadget')
        # Same maximize/restore policy with configured right-hand gadget.
        move(65,71);key('SPACE');rects[1]=(0,8,80,192);observe('chrome-maximize')
        move(76,13);key('SPACE');rects[1]=(11,66,58,68);observe('chrome-restore')
        move(76,185);key('SPACE');menu=bytes((1,10))+b'Desk\0\0\0\0'
        key('F4');r=observe('chrome-filesystem-after-drawing')
        if r[sym['cpc_runtime_fs_status']]: raise AssertionError('title module damaged filesystem')
    if image.read_bytes()!=original: raise AssertionError('chrome test wrote mounted media')
    report=dict(case=case,checkpoints=checks,stack=stacks,sections=manifest['sections'],
                emulator_sha256=hashlib.sha256(emulator.read_bytes()).hexdigest())
    (artifacts/'result.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS CPC title/gadget assets '+json.dumps(report),flush=True)
    return artifacts
