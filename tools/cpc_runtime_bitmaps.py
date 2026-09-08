"""3D-T private M4 asset fixtures, exact-byte and independent pixel checks."""
import hashlib
import json
import subprocess

from cpc_runtime_pixels import verify_pixels
from test_cpc_foundation_1984 import snapshot

BITMAP_CASES = ('default','custom','tall-icon','icon-missing','icon-short','icon-trailing',
                'icon-magic','icon-version','icon-count','icon-offset','icon-width',
                'icon-height','icon-size','icon-oversized','icon-no-default',
                'icon-unsafe','cursor-missing','cursor-short','cursor-trailing',
                'cursor-no-default','cursor-mask','cursor-ink','tile-missing','tile-short','tile-trailing',
                'tile-drive','tile-unsafe')


def fixture(case,work,root):
    normal=(work/'REFINED.IST').read_bytes();fallback=(work/'DEFAULT.IST').read_bytes()
    sprite=(work/'DEFAULT.SPR').read_bytes();tile=(root/'assets/backdrops/waves.BDP').read_bytes()
    selected='ALTICON';candidate=bytearray(normal)
    candidate[100:356]=bytes(b^0xFF for b in candidate[100:356])
    candidate=bytes(candidate);expected=candidate;ist_status=0
    cursor=bytearray(sprite)
    # Add a white dot at bottom-left in each stored phase, preserving the
    # canonical mask/data format and the two-pixel shift relationship.
    for at,mask,ink in ((120,0x88,0x80),(248,0x22,0x20)):
        cursor[at] &= ~mask;cursor[at+1]=(cursor[at+1]&~mask)|ink
    cursor=bytes(cursor);cur_expected=cursor;cur_status=0
    cur_name='ALTCURS';bd_name='WAVES';bd_expected=tile
    if case=='default':
        selected='REFINED';candidate=None;expected=normal
        cur_name='DEFAULT';cursor=None;cur_expected=sprite
        bd_name='SOLID';bd_expected=None
    elif case=='custom': pass
    elif case=='tall-icon':
        # Last catalogue entry is 32x200, partly off-screen at gallery y=32.
        # Canonical contiguous layout stays valid and within the F7 budget.
        candidate=bytearray(candidate)
        start=int.from_bytes(candidate[96:98],'little')
        candidate[99]=200
        candidate[start:]=bytes((i*37)&255 for i in range(8*200))
        candidate=bytes(candidate);expected=candidate
    elif case.startswith('icon-'):
        ist_status=1;expected=fallback
        if case=='icon-missing': candidate=None
        elif case=='icon-short': candidate=candidate[:-1]
        elif case=='icon-trailing': candidate+=b'\0'
        elif case=='icon-oversized': candidate+=bytes(0x3F01-len(candidate))
        elif case=='icon-no-default': candidate=None;fallback=None;expected=None;ist_status=2
        elif case=='icon-unsafe': selected='../BAD';candidate=None
        else:
            offsets={'icon-magic':(0,0),'icon-version':(4,1),'icon-count':(5,20),
                     'icon-offset':(16,0),'icon-width':(18,0),'icon-height':(19,0),
                     'icon-size':(19,200)}
            at,value=offsets[case];candidate=bytearray(candidate);candidate[at]=value;candidate=bytes(candidate)
    elif case.startswith('cursor-'):
        cur_status=1;cur_expected=sprite
        if case=='cursor-missing': cursor=None
        elif case=='cursor-short': cursor=cursor[:-1]
        elif case=='cursor-trailing': cursor+=b'\0'
        elif case=='cursor-no-default': cursor=None;cur_status=2
        elif case=='cursor-mask': cursor=bytes((cursor[0]^1,))+cursor[1:]
        elif case=='cursor-ink': cursor=cursor[:1]+bytes((255,))+cursor[2:]
    elif case.startswith('tile-'):
        bd_expected=None
        if case=='tile-missing': tile=None
        elif case=='tile-short': tile=tile[:-1]
        elif case=='tile-trailing': tile+=b'\0'
        elif case=='tile-drive': bd_name='B:WAVES'
        elif case=='tile-unsafe': bd_name='../BAD'
    else: raise ValueError(case)
    config=f'FONT=DEFAULT\r\nICONS={selected}\r\nCURSOR={cur_name}\r\nBACKDROP={bd_name}\r\nINKS=1,26,0,6,1\r\n'
    return dict(icons=expected,cursor=cur_expected,backdrop=bd_expected,
                status=(ist_status,cur_status,int(bd_expected is None)),
                files={'/GEOBENCH.CFG':config.encode(),'/GBENCH/ALTICON.IST':candidate,
                       '/GBENCH/DEFAULT.IST':fallback,'/GBENCH/ALTCURS.SPR':cursor,
                       '/GBENCH/DEFAULT.SPR':None if case=='cursor-no-default' else sprite,
                       '/GBENCH/WAVES.BDP':tile})


def prepare(case,work,root,image,artifacts):
    data=fixture(case,work,root);target=['-i',str(image)+'@@16384']
    for name,payload in data['files'].items():
        # Removing a not-yet-created optional candidate is not an error.
        if name not in ('/GBENCH/ALTICON.IST','/GBENCH/ALTCURS.SPR'):
            subprocess.run(['mdel',*target,'::'+name],check=True)
        if payload is not None:
            path=artifacts/name.rsplit('/',1)[-1];path.write_bytes(payload)
            subprocess.run(['mcopy',*target,str(path),'::'+name],check=True)
    return data


def run_bitmaps(media,manifest,work,sym,artifacts,image,emulator,
                send,wait,read,key,move,case,fixture):
    from test_cpc_runtime_1984 import integrity
    rects={1:(11,66,58,68)};order=[0,1];accents={1:0}
    menu=b'\0';titles={};calculators={};popup=None;gallery=False
    checks=[];stacks={'main':0,'irq':0,'tmp':0};original=image.read_bytes()
    def word(r,name): return int.from_bytes(r[sym[name]:sym[name]+2],'little')
    def observe(name,modal=False):
        previous=None
        for _ in range(150):
            data=read(name);_,r=snapshot(data)
            if r[sym['pointer_visible']] and not r[sym['io_busy']] and not r[sym['core_pointer_paintlock']]:
                signature=bytes(r[0xC000:0x10000]);turn=word(r,'cpc_runtime_turns')
                if previous and signature==previous[0] and (modal or turn!=previous[1]): break
                previous=signature,turn
            wait(3)
        else: raise AssertionError(name+': incomplete drawing')
        r,used=integrity(data,sym,work,cursor=fixture['cursor'])
        for k,n in used.items(): stacks[k]=max(stacks[k],n)
        statuses=tuple(r[sym[k]] for k in ('cpc_icon_status','cpc_cursor_status','cpc_backdrop_status'))
        if statuses!=fixture['status']: raise AssertionError((name,'asset status',statuses,fixture['status']))
        icon=fixture['icons'];n=0 if icon is None else len(icon)
        if word(r,'cpc_icon_bytes')!=n or r[sym['cpc_icon_count']]!=(0 if icon is None else icon[5]):
            raise AssertionError(name+': icon admission/count')
        at=0x7C000+sym['data_icons']-0x4000
        if n and r[at:at+n]!=icon: raise AssertionError(name+': icon publication bytes')
        if fixture['backdrop'] is not None and r[sym['cpc_bd_tile']:sym['cpc_bd_tile']+64]!=fixture['backdrop']:
            raise AssertionError(name+': backdrop publication')
        verify_pixels(r,sym,work,rects,order,accents,menu,titles,popup,calculators,
                      cursor=fixture['cursor'],backdrop=fixture['backdrop'],icons=icon if gallery else None)
        if r[sym['wm_nwin']]!=len(order) or r[sym['wm_z']:sym['wm_z']+len(order)]!=bytes(order):
            raise AssertionError(name+': owner/z-order')
        checks.append(name);send(f'crop {artifacts/(name+".ppm")} 0 0 768 576 1')
        print(f'{name}: status={statuses} stack={stacks}',flush=True)
        return r
    observe('bitmap-boot')
    move(76,185);key('SPACE');menu=bytes((1,10))+b'Desk\0\0\0\0'
    key('A');gallery=True;observe('bitmap-gallery')
    # Deliberately overlap the pointer with icon and tile pixels before reload.
    move(4,40);r=observe('bitmap-pointer-on-icon')
    before=word(r,'cpc_runtime_draw_calls');calls=word(r,'cpc_visual_calls')
    key('R');r=observe('bitmap-same-reload')
    if word(r,'cpc_visual_calls')!=calls+1 or r[sym['cpc_visual_dirty']]:
        raise AssertionError('same assets dirtied desktop / reload did not run')
    if word(r,'cpc_runtime_draw_calls')!=before: raise AssertionError('unchanged assets repainted')
    for phase in range(1,5):
        key('V');r=observe('bitmap-pointer-phase-'+str(phase%4))
        if r[sym['pointer_x']]%4!=phase%4: raise AssertionError('pointer phase key missed')
    # All corrupt/fallback cases exercise a real loaded directory and the
    # renderer, not merely status flags. Rich lifecycle on default and custom.
    if case in ('default','custom'):
        key('F7');rects[2]=(24,24,31,144);order.append(2);titles[2]='Calculator';calculators[2]='0'
        menu=bytes((1,10))+b'Edit\0\0\0\0';observe('bitmap-calculator-over-icons')
        key('7');key('2');calculators[2]='72';observe('bitmap-calculator-72')
        move(76,185);key('SPACE');menu=bytes((1,10))+b'Desk\0\0\0\0'
        key('R');observe('bitmap-live-reload')
        send('key-down U');wait(30);send('key-up U');wait(30)
        popup=dict(x=23,y=84,hot=-1,labels=('Continue','Cancel'));observe('bitmap-popup',True)
        key('ESCAPE');popup=None;observe('bitmap-popup-restored')
        key('F7');menu=bytes((1,10))+b'Edit\0\0\0\0';observe('bitmap-activate')
        key('ESCAPE');del rects[2];order=[0,1];del titles[2];del calculators[2]
        menu=b'\0';observe('bitmap-close-exposes-tile')
        move(25,70);_,r=snapshot(read());grab=(r[sym['poll_byte']],r[sym['poll_line']])
        send('key-down SPACE');wait(10);move(31,78)
        _,r=snapshot(read());drop=(r[sym['poll_byte']],r[sym['poll_line']])
        send('key-up SPACE');wait(60)
        rects[1]=(max(0,min(22,11+drop[0]-grab[0])),max(8,min(132,66+drop[1]-grab[1])),58,68)
        observe('bitmap-drag-exposure')
        # Right/bottom clipped pointer, then restore the saved edge pixels.
        move(79,199);key('SPACE');menu=bytes((1,10))+b'Desk\0\0\0\0'
        observe('bitmap-pointer-edge')
        for phase in range(1,5):
            key('V');observe('bitmap-pointer-edge-phase-'+str(phase%4))
        move(75,180);observe('bitmap-pointer-edge-restored')
        key('F4');r=observe('bitmap-filesystem')
        if r[sym['cpc_runtime_fs_status']]: raise AssertionError('icon bank damaged filesystem')
    if image.read_bytes()!=original: raise AssertionError('asset test wrote mounted media')
    report=dict(case=case,checkpoints=checks,stack=stacks,sections=manifest['sections'],
                emulator_sha256=hashlib.sha256(emulator.read_bytes()).hexdigest())
    (artifacts/'result.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS CPC bitmap assets '+json.dumps(report),flush=True)
    return artifacts
