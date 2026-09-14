"""Portable chooser on the existing M4 test launcher, not a second kernel."""
import hashlib
import os
import subprocess
from cpc_production_lifetime import physical
from test_cpc_foundation_1984 import snapshot
from filepick_scenario import FEATURES, fixture, stage_image, status_pixels, exercise as scenario
from cpc_graphics_fixture import address


def prepare(root,image,artifacts):
    app=root/'build/universal/PICKPRB.APP'
    subprocess.run(['bash','tools/build_uapp.sh','apps/filepickprobe',str(app)],cwd=root,
                   env={**os.environ,**FEATURES},check=True)
    fixture(artifacts/'DOCUI')
    subprocess.run(['mcopy','-o','-i',str(image)+'@@16384',str(app),
                    '::/GBENCH/FSPROBE.APP'],check=True)
    stage_image(image,artifacts/'DOCUI')


def exercise(root,work,sym,artifacts,image,send,wait,read,key,move):
    from test_cpc_runtime_1984 import integrity
    app=(root/'build/universal/PICKPRB.APP').read_bytes()
    if subprocess.check_output(['mtype','-i',str(image)+'@@16384','::/GBENCH/FSPROBE.APP'])!=app:
        raise AssertionError('chooser APP alias differs')
    original_hash=hashlib.sha256(image.read_bytes()).hexdigest()
    linked={v[1]:int(v[2],16) for line in (root/'build/universal-obj/filepickprobe/app.noi').read_text().splitlines()
            if len(v:=line.split())==3 and v[0]=='DEF'}
    stacks={'main':0,'irq':0,'tmp':0}
    font=(work/'DEFAULT.FNT').read_bytes()
    def observe(name,fields):
        for _ in range(200):
            wait(5);data=read(name);_,ram=snapshot(data)
            base=physical(ram[sym['wm_table']+50])-0x4000
            values=ram[base+linked['_filepickprobe_state']:base+linked['_filepickprobe_state']+12]
            if all(values[k]==v for k,v in fields.items()) and not any(
                    ram[sym[f]] for f in ('io_busy','core_pointer_paintlock')):
                def pixel(x,y):
                    byte=ram[0xC000+address(x,y)];shift=x%4
                    return ((byte>>(7-shift))&1)|(((byte>>(3-shift))&1)<<1)
                if status_pixels(values,font,pixel): break
        else: raise AssertionError(f'{name}: state {list(values)}, wanted {fields}')
        ram,used=integrity(data,sym,work)
        for k,v in used.items(): stacks[k]=max(stacks[k],v)
        if values[11]!=85: raise AssertionError('4096-byte document guard')
        if ram[base+0x4000:base+0x4000+len(app)]!=app: raise AssertionError('chooser code changed')
        if ram[sym['wm_nwin']]!=3 or ram[sym['wm_focus']]!=2: raise AssertionError('chooser focus/lifecycle')
        contexts=sum(bool(ram[sym['core_fsctx_table']+144*i]) for i in range(4))
        if contexts!=(0 if values[0]==8 else 1): raise AssertionError('chooser context leak/count')
        at=base+linked['_picker'];n=values[8]+256*values[9]
        send(f'crop {artifacts/(name+".ppm")} 0 0 768 576 1')
        print(f'{name}: state={list(values)} stack={stacks}',flush=True)
        return dict(path=bytes(ram[at+17:at+65]).split(b'\0',1)[0].decode(),
                    name=bytes(ram[at+65:at+76]),
                    data=bytes(ram[base+linked['_text']+1:base+linked['_text']+1+n]))
    def click(x,y): move(x,y);key('SPACE')
    key('F5')
    checks=scenario(click,observe)
    click(6,24);wait(50)
    ram,used=integrity(read('chooser-closed'),sym,work)
    if ram[sym['wm_nwin']]!=2 or any(ram[sym['core_fsctx_table']+144*i] for i in range(4)):
        raise AssertionError('chooser close leaked a window/context')
    if hashlib.sha256(image.read_bytes()).hexdigest()!=original_hash:
        raise AssertionError('read-only chooser diagnostic changed media')
    return dict(status='PASS',checkpoints=checks,stack=stacks,
                app_sha256=hashlib.sha256(app).hexdigest(),image_unchanged=True)
