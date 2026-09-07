"""Configured font/theme tests on private M4 images; never write guest RAM."""
import hashlib
import json
import subprocess

from cpc_production_lifetime import physical
from cpc_runtime_pixels import verify_pixels
from test_cpc_foundation_1984 import snapshot


ASSET_CASES = ('default', 'custom', 'missing', 'empty', 'short', 'trailing',
               'oversized', 'reader-oversized', 'magic', 'width', 'height',
               'coverage', 'version', 'unsafe-name', 'no-default', 'bad-default',
               'default-variant', 'accent-frame', 'same-inks')
# Hardware RGB slots, from the CPC Gate Array palette (also gate_array.c in
# 1984). The assertion below derives canonical firmware G/R/B independently
# rather than copying the kernel's firmware-to-GA translation lookup table.
HW_RGB = (0x808080,0x808080,0x00FF80,0xFFFF80,0x000080,0xFF0080,0x008080,0xFF8080,
          0xFF0080,0xFFFF80,0xFFFF00,0xFFFFFF,0xFF0000,0xFF00FF,0xFF8000,0xFF80FF,
          0x000080,0x00FF80,0x00FF00,0x00FFFF,0x000000,0x0000FF,0x008000,0x0080FF,
          0x800080,0x80FF80,0x80FF00,0x80FFFF,0x800000,0x8000FF,0x808000,0x8080FF)


def firmware_rgb(ink):
    levels=(0,128,255)
    return levels[(ink//3)%3]<<16 | levels[ink//9]<<8 | levels[ink%3]


def variant(font):
    result=bytearray(font)
    # Distinct artwork, unchanged 6x8 geometry/ASCII+UI glyph coverage.
    for char in range(33,127): result[16+(char-32)*8+3] ^= 0x10
    return bytes(result)


def asset_fixture(case, default):
    selected='ALTERN';candidate=variant(default);fallback=default
    inks=(1,26,0,6,1);frame_pen=2;status=1;expected=default
    if case=='default': selected='DEFAULT';candidate=None;status=0
    elif case=='custom': inks=(0,26,0,6,18);frame_pen=1;status=0;expected=candidate
    elif case=='accent-frame': inks=(0,0,0,6,2);frame_pen=3;status=0;expected=candidate
    elif case=='same-inks': inks=(4,4,4,4,4);status=0;expected=candidate
    elif case=='missing': candidate=None
    elif case=='empty': candidate=b''
    elif case=='short': candidate=candidate[:-1]
    elif case=='trailing': candidate+=b'\0'
    elif case=='oversized': candidate+=bytes(1025-len(candidate))
    elif case=='reader-oversized': candidate+=bytes(0x3F01-len(candidate))
    elif case in ('magic','width','height','coverage','version'):
        candidate=bytearray(candidate)
        offset,value={'magic':(0,0),'width':(7,8),'height':(8,0),
                      'coverage':(6,255),'version':(4,2)}[case]
        candidate[offset]=value;candidate=bytes(candidate)
    elif case=='unsafe-name': selected='../OTHER';candidate=None
    elif case=='no-default': selected='DEFAULT';candidate=None;fallback=None;status=2
    elif case=='bad-default': selected='DEFAULT';candidate=None;fallback=default[:-1];status=2
    elif case=='default-variant': candidate=None;fallback=variant(default);expected=fallback
    else: raise ValueError(case)
    return dict(font=expected,inks=inks,frame_pen=frame_pen,status=status,
                files={'/GEOBENCH.CFG':('FONT='+selected+'\r\nINKS='+','.join(map(str,inks))+'\r\n').encode(),
                       '/GBENCH/DEFAULT.FNT':fallback,'/GBENCH/ALTERN.FNT':candidate})


def prepare(case,work,image,artifacts):
    fixture=asset_fixture(case,(work/'DEFAULT.FNT').read_bytes())
    target=['-i',str(image)+'@@16384']
    for name,data in fixture['files'].items():
        if name!='/GBENCH/ALTERN.FNT': subprocess.run(['mdel',*target,'::'+name],check=True)
        if data is not None:
            path=artifacts/name.rsplit('/',1)[-1];path.write_bytes(data)
            subprocess.run(['mcopy',*target,str(path),'::'+name],check=True)
    return fixture


def run_assets(media,manifest,work,sym,artifacts,image,emulator,send,wait,read,key,move,case,fixture):
    from test_cpc_runtime_1984 import integrity
    rects={1:(11,66,58,68)};order=[0,1];accents={1:0};menu=b'\0';titles={};calculators={};popup=None
    checks=[];stacks={'main':0,'irq':0,'tmp':0}
    original=image.read_bytes()
    def word(r,name): return int.from_bytes(r[sym[name]:sym[name]+2],'little')
    def observe(name,modal=False):
        previous=None
        for _ in range(120):
            data=read(name);_,r=snapshot(data)
            if r[sym['pointer_visible']] and not r[sym['io_busy']] and not r[sym['core_pointer_paintlock']]:
                signature=bytes(r[0xC000:0x10000]);turn=word(r,'cpc_runtime_turns')
                if previous and signature==previous[0] and (modal or turn!=previous[1]): break
                previous=signature,turn
            wait(3)
        else: raise AssertionError(name+': incomplete draw')
        r,used=integrity(data,sym,work,font=fixture['font']);header,_=snapshot(data)
        for k,n in used.items(): stacks[k]=max(stacks[k],n)
        if r[sym['cpc_font_status']]!=fixture['status']: raise AssertionError(name+': font fallback status')
        if word(r,'cpc_font_bytes')!=816 or r[sym['font_first']:sym['font_covmask']+1]!=bytes((32,131,6,8,252)):
            raise AssertionError(name+': font geometry/size')
        if r[sym['kcfg_framepen']]!=fixture['frame_pen']: raise AssertionError(name+': frame contrast')
        for pen,ink in zip((0,1,2,3,16),fixture['inks']):
            if HW_RGB[header[0x2F+pen]&31]!=firmware_rgb(ink): raise AssertionError(name+': hardware ink '+str(pen))
        if bool(r[sym['ui_modal']])!=modal: raise AssertionError(name+': modal leaked')
        verify_pixels(r,sym,work,rects,order,accents,menu,titles,popup,calculators,
                      font=fixture['font'],frame_pen=fixture['frame_pen'])
        if r[sym['wm_nwin']]!=len(order) or r[sym['wm_z']:sym['wm_z']+len(order)]!=bytes(order):
            raise AssertionError(name+': window ownership changed')
        checks.append(name);send(f'crop {artifacts/(name+".ppm")} 0 0 768 576 1')
        print(f'{name}: font={fixture["status"]} stack={stacks}',flush=True)
        return r
    r=observe('assets-boot')
    app=(media/'CARD/GBENCH/ABIPROBE.APP').read_bytes();at=physical(r[sym['wm_table']+25])
    if r[at:at+len(app)]!=app: raise AssertionError('font load changed universal app')
    move(76,185);key('SPACE');menu=bytes((1,10))+b'Desk\0\0\0\0';r=observe('assets-root-focus')
    before=word(r,'cpc_runtime_draw_calls');count=word(r,'cpc_visual_calls')
    key('R');r=observe('assets-same-config-reload')
    if word(r,'cpc_visual_calls')!=count+1 or r[sym['cpc_visual_dirty']]:
        raise AssertionError('unchanged reload did not run / dirtied font')
    if word(r,'cpc_runtime_draw_calls')!=before: raise AssertionError('unchanged reload repainted')
    # Every malformed/default case verifies the read limit, fallback, palette,
    # code integrity and no-op reload. Rich interactions only need both artwork
    # variants, not nineteen repeats of the same application test.
    if case in ('default','custom'):
        key('F7');rects[2]=(24,24,31,144);order.append(2);titles[2]='Calculator';calculators[2]='0'
        menu=bytes((1,10))+b'Edit\0\0\0\0';observe('assets-calculator')
        key('7');key('2');calculators[2]='72';observe('assets-calculator-72')
        move(76,185);key('SPACE');menu=bytes((1,10))+b'Desk\0\0\0\0';observe('assets-live-root')
        key('R');observe('assets-live-reload-preserves-72')
        send('key-down U');wait(30);send('key-up U');wait(30)
        popup=dict(x=23,y=84,hot=-1,labels=('Continue','Cancel'));observe('assets-native-popup',True)
        key('ESCAPE');popup=None;observe('assets-native-popup-restored')
        key('F4');r=observe('assets-storage-after-reload')
        if r[sym['cpc_runtime_fs_status']] or not r[sym['cpc_runtime_fs_calls']]:
            raise AssertionError('asset publication damaged filesystem module')
    if image.read_bytes()!=original: raise AssertionError('asset reads changed mounted media')
    report=dict(case=case,checkpoints=checks,stack_high_water=stacks,sections=manifest['sections'],
                font_sha256=hashlib.sha256(fixture['font']).hexdigest(),
                emulator_sha256=hashlib.sha256(emulator.read_bytes()).hexdigest())
    (artifacts/'result.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS configured CPC font/palette '+json.dumps(report),flush=True)
    return artifacts
