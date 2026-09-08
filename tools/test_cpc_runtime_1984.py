#!/usr/bin/env python3
"""Boot the unchanged universal APP on M4; observe, never inject, guest RAM."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import queue
import subprocess
import tempfile
import threading
import time

from build_cpc_runtime import ROOT, build, symbols
from test_cpc_foundation_1984 import snapshot
from cpc_production_lifetime import physical
from cpc_runtime_pixels import verify_pixels, cursor_phases, DEFAULT_THEME
from cpc_fswrite_cases import space


def integrity(data, sym, work, font=None, cursor=None, theme=DEFAULT_THEME, title_ready=True, kernel=None):
    header, ram = snapshot(data)
    if len(ram) != 512*1024: raise AssertionError("512 KiB required")
    if ram[sym['cpc_runtime_status']] != 1: raise AssertionError("runtime failed to boot")
    if ram[sym['sched_fault']]: raise AssertionError("scheduler fault")
    for name in ('io_busy','io_offline','io_fd','core_pointer_paintlock'):
        if ram[sym[name]]: raise AssertionError(f"unfinished transaction: {name}")
    used = {}
    for stem in ('main','irq','tmp'):
        lo, hi = sym[f'cpc_{stem}_stack'], sym[f'cpc_{stem}_top']
        if ram[lo-16:lo] != b'\xD7'*16 or ram[hi:hi+16] != b'\xD7'*16:
            raise AssertionError(f'{stem} stack guard')
        used[stem] = hi-lo-next((i for i,b in enumerate(ram[lo:hi]) if b!=0xA6),hi-lo)
        if used[stem] >= hi-lo: raise AssertionError(f'{stem} stack exhausted')
    for name,base in (('CORE.RAW',0x8000),('SCHED.RAW',0x2900),('HARDWARE.RAW',0x3800),
                      ('ROOTBAR.BIN',0x4000),
                      ('SUPPORT.RAW',0x400),('FSCTX.BIN',0x7C400),('DEFAULT.FNT',0x7C000)):
        expected = font if name=='DEFAULT.FNT' and font is not None else (work/name).read_bytes()
        if name=='CORE.RAW' and kernel is not None: expected=kernel
        actual = bytearray(ram[base:base+len(expected)])
        if name == 'SUPPORT.RAW':
            for field,n in (('up_request',16),('up_text_copy',49)):
                off=sym[field]-base
                actual[off:off+n]=expected[off:off+n]
        if name == 'CORE.RAW':
            off=sym['cursor_phases']-base
            phases=cursor_phases((work/'DEFAULT.SPR').read_bytes() if cursor is None else cursor)
            if actual[off:off+512]!=phases: raise AssertionError('cursor phase publication changed')
            actual[off:off+512]=expected[off:off+512]
        if actual != expected: raise AssertionError(f'{name} code/data changed')
    if header[0x25] != 1 or header[0x40] != 0x0D: raise AssertionError('IM/ROM/mode')
    if bool(ram[sym['title_ready']])!=title_ready: raise AssertionError('title renderer readiness')
    at=0x7C000+sym['data_title']-0x4000  # excluded F7 is not an app/owner page
    if ram[at:at+106]!=theme: raise AssertionError('title/gadget publication changed')
    if title_ready and ram[at+106:at+sym['cpc_title_module_size']]!=(work/'GBTITLE.MOD').read_bytes()[106:]:
        raise AssertionError('title renderer code changed')
    if ram[0x1448:0x144C] != ram[sym['mw_rect']:sym['mw_rect']+4]:
        raise AssertionError('public managed geometry differs')
    return ram, used


def run(emulator=ROOT.parent/'1984/1984', skip_build=False, filesystem=False, menus=False, accessories=False, clock=False, desk=False, root_fault=None, native=False, native_fault=None, config_case=None, asset_case=None, latency=False, bitmap_case=None, chrome_case=None, picker=False, picker_fault=None, config_edit=None, seed_image=None, desktop=False, filemgr=False, filemgr_case=None, filemgr_scenario=None, desktop_delivery=False):
    filemgr=filemgr or filemgr_case is not None or filemgr_scenario is not None
    desktop=desktop or desktop_delivery
    if desktop_delivery:
        if (seed_image and filemgr_scenario != 'reboot') or filemgr_scenario == 'windows':
            raise ValueError('Desktop delivery test must use its own image without diagnostic applications')
        if filemgr_scenario == 'reboot' and not seed_image:
            raise ValueError('File Manager reboot check requires the saved View test image')
        from cpc_desktop_media import validate
        media=ROOT/'QA/CPC-Desktop' if skip_build else build(desktop=True,filemgr=True,delivery=True)
        manifest=validate(media,pristine=True)
        if filemgr and manifest['profile'] != 'cpc-desktop-m4-v2':
            raise ValueError('File Manager acceptance requires the Sprint 3 delivery profile')
        # Check the real FAT contents, not just the host staging directory.
        for name,expected in manifest['files'].items():
            payload=subprocess.check_output(['mtype','-i',manifest['image']+'@@16384','::/'+name])
            if hashlib.sha256(payload).hexdigest()!=expected:
                raise AssertionError('delivered M4 file differs: '+name)
        if seed_image:
            # Cold-boot only a payload-identical services-test copy with the
            # expected saved View. Never mutate the source or silently accept
            # replacement native/universal binaries through this test path.
            from cpc_runtime_configedit import replace_value
            for name,expected in manifest['files'].items():
                if name == 'GEOBENCH.CFG':
                    expected=hashlib.sha256(replace_value((media/'CARD'/name).read_bytes(),b'LIST',b'VIEW=')).hexdigest()
                payload=subprocess.check_output(['mtype','-i',str(seed_image)+'@@16384','::/'+name])
                if hashlib.sha256(payload).hexdigest()!=expected:
                    raise AssertionError('File Manager reboot seed differs: '+name)
    else:
        variant='filemgr-contract' if filemgr else 'desktop-contract' if desktop else 'runtime'
        media = ROOT/('QA/Diagnostics/CPC-'+variant) if skip_build else build(desktop=desktop,filemgr=filemgr)
        manifest=json.loads((media/'manifest.json').read_text())
    work=Path(manifest['work']);sym=symbols(work/'runtime.sym')
    artifacts=Path(tempfile.mkdtemp(prefix='geobench-cpc-runtime-'))
    image=artifacts/'RUNTIME.IMG';image.write_bytes(Path(seed_image or manifest['image']).read_bytes())
    filemgr_kernel=None
    if filemgr_case:
        from cpc_runtime_filemgr import prepare
        filemgr_kernel=prepare(filemgr_case,work,sym,image,artifacts)
    if config_edit:
        from cpc_runtime_configedit import prepare
        prepare(config_edit,media,work,image,artifacts)
    if asset_case:
        from cpc_runtime_assets import prepare
        asset_fixture=prepare(asset_case,work,image,artifacts)
    if bitmap_case:
        from cpc_runtime_bitmaps import prepare
        bitmap_fixture=prepare(bitmap_case,work,ROOT,image,artifacts)
    if chrome_case:
        from cpc_runtime_chrome import prepare
        chrome_fixture=prepare(chrome_case,work,ROOT,image,artifacts)
    if native_fault or config_case or picker_fault:
        target=['-i',str(image)+'@@16384']
        if native_fault or picker_fault:
            module='GBPICK.MOD' if picker_fault else 'GBUI.MOD'
            fault=picker_fault or native_fault
            name='::/GBENCH/'+module
            raw=(work/module).read_bytes()
            payload=None if fault=='missing' else raw[:-1] if fault=='short' else raw+b'\0'
        else:
            from cpc_runtime_native import CONFIG_CASES
            name='::/GEOBENCH.CFG';payload=CONFIG_CASES[config_case]
        subprocess.run(['mdel',*target,name],check=True)
        if payload is not None:
            fixture=artifacts/'native-fixture.bin';fixture.write_bytes(payload)
            subprocess.run(['mcopy',*target,str(fixture),name],check=True)
    if root_fault:
        # Corrupt ONLY the private M4 image, never mounted/user/release media.
        target=['-i',str(image)+'@@16384']
        parser_fault=root_fault.startswith('cfg-')
        fault=root_fault[4:] if parser_fault else root_fault
        name='::/GBENCH/GBCFG.MOD' if parser_fault else '::/GBENCH/ROOTUI.BIN'
        subprocess.run(['mdel',*target,name],check=True)
        if fault!='missing':
            module=(work/('GBCFG.MOD' if parser_fault else 'ROOTBAR.BIN')).read_bytes()
            invalid=artifacts/'invalid-root.bin'
            invalid.write_bytes(module[:-1] if fault=='short' else module+b'\0')
            subprocess.run(['mcopy',*target,str(invalid),name],check=True)
    config=artifacts/'1984.conf'
    config.write_text(f'[machine]\nmodel=6128\nmemory=512\n[hardware]\nmx4=true\nm4=true\n'
                      f'm4_path=\nm4_image={image}\nalbireo=false\nsymbiface_ide=false\n[advanced]\ndebug=true\n')
    pilot=artifacts/'pilot'
    process=subprocess.Popen([str(emulator),f'--config={config}','--6128','--memory=512',
                              '--autostart=BOOT',f'--pilot={pilot}','--pilot-replies-stderr','--exit-after=30000'],
                             cwd=ROOT,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,
                             text=True,bufsize=1,env={**os.environ,'SDL_VIDEODRIVER':'dummy','SDL_AUDIODRIVER':'dummy'})
    lines=queue.Queue()
    def pump():
        with (artifacts/'1984.log').open('w') as log:
            for line in process.stderr: log.write(line);log.flush();lines.put(line.rstrip())
        lines.put(None)
    reader=threading.Thread(target=pump,daemon=True);reader.start()
    def receive(pattern,timeout=45):
        deadline=time.monotonic()+timeout
        while time.monotonic()<deadline:
            try: line=lines.get(timeout=.2)
            except queue.Empty: continue
            if line is None: raise RuntimeError(f'1984 exited; {artifacts}')
            if pattern in line: return line
        raise TimeoutError(f'{pattern}; {artifacts}')
    def send(command):
        fd=os.open(pilot,os.O_WRONLY|os.O_NOCTTY)
        try: os.write(fd,(command+'\n').encode())
        finally: os.close(fd)
        reply=receive('1984: pilot reply: ').split('1984: pilot reply: ',1)[1]
        if not reply.startswith('ok '): raise RuntimeError(reply)
        return reply
    def wait(n=30): return send(f'wait frames {n} 300')
    def read(name='steering'):
        path=artifacts/(name+'.sna');send(f'snapshot-save {path}')
        return path.read_bytes()
    def key(name,frames=12):
        send('key-down '+name);wait(frames);send('key-up '+name)
        _,r=snapshot(read())
        at=sym['cpc_runtime_turns'];before=int.from_bytes(r[at:at+2],'little')
        for _ in range(120):
            wait(20);_,r=snapshot(read())
            if (int.from_bytes(r[at:at+2],'little')-before)&65535 >= 5: break
        else: raise AssertionError('root loop failed to resume after '+name)
    def state(name):
        data=read(name);r,used=integrity(data,sym,work)
        send(f'crop {artifacts/(name+".ppm")} 0 0 768 576 1')
        print(f'{name}: windows={r[sym["wm_nwin"]]} focus={r[sym["wm_focus"]]} stack={used}',flush=True)
        return r
    def move(x,y):
        for axis,target,negative,positive in (('poll_byte',x,'LEFT','RIGHT'),('poll_line',y,'UP','DOWN')):
            for _ in range(70):
                _,r=snapshot(read());delta=target-r[sym[axis]]
                if abs(delta)<=1: break
                direction=positive if delta>0 else negative
                send('key-down '+direction);wait(min(15,max(1,abs(delta)-1)))
                send('key-up '+direction);wait(8)
            else: raise AssertionError('pointer steering timeout')
    rects={1:(11,66,58,68)};order=[0,1];accents={1:0}
    menu=b'\0';titles={};popup=None;calculators={}
    checks=[]
    def checked(name):
        r=state(name)
        verify_pixels(r,sym,work,rects,order,accents,menu,titles,popup,calculators,
                      frame_pen=1 if config_case=='custom' else 2)
        if r[sym['wm_nwin']]!=len(order) or r[sym['wm_z']:sym['wm_z']+len(order)]!=bytes(order):
            raise AssertionError(name+': z-order/count')
        for slot,rect in rects.items():
            at=sym['wm_table']+25*slot+1
            if r[at:at+4]!=bytes(rect): raise AssertionError(name+': window geometry')
        checks.append(name)
        return r
    print(f'Unified CPC runtime, M4; artifacts: {artifacts}',flush=True)
    try:
        receive('pilot PTY:',15)
        for _ in range(30):
            wait(100);data=read('boot');_,ram=snapshot(data)
            if ram[sym['cpc_runtime_status']] == 1:
                if root_fault: raise AssertionError('invalid root module executed')
                break
            if ram[sym['cpc_runtime_status']] == 255:
                if not root_fault: raise AssertionError('runtime boot failure')
                if ram[sym['cpc_runtime_launches']] or ram[sym['sched_fault']]:
                    raise AssertionError('invalid root module crossed boot boundary')
                if root_fault.startswith('cfg-') and ram[sym['cpc_cfg_status']]!=3:
                    raise AssertionError('parser executable failure was not reported')
                for name,base in (('CORE.RAW',0x8000),('SCHED.RAW',0x2900),('HARDWARE.RAW',0x3800)):
                    expected=(work/name).read_bytes()
                    actual=bytearray(ram[base:base+len(expected)])
                    if name=='CORE.RAW' and not parser_fault:
                        off=sym['cursor_phases']-base
                        if actual[off:off+512]!=cursor_phases((work/'DEFAULT.SPR').read_bytes()):
                            raise AssertionError('failed root load damaged initialized cursor')
                        actual[off:off+512]=expected[off:off+512]
                    if actual!=expected: raise AssertionError('boot failure damaged '+name)
                for stem in ('main','irq','tmp'):
                    lo,hi=sym[f'cpc_{stem}_stack'],sym[f'cpc_{stem}_top']
                    if ram[lo-16:lo]!=b'\xD7'*16 or ram[hi:hi+16]!=b'\xD7'*16:
                        raise AssertionError('boot failure stack guard')
                before=bytes(ram);wait(100);_,after=snapshot(read('rejected'))
                if bytes(after)!=before: raise AssertionError('failed boot resumed execution')
                report=dict(expected_failure=root_fault,sections=manifest['sections'])
                (artifacts/'result.json').write_text(json.dumps(report,indent=2)+'\n')
                print('PASS root module rejection '+json.dumps(report),flush=True)
                return artifacts
        else: raise AssertionError('runtime boot timeout')
        wait(50)
        if filemgr:
            from cpc_runtime_filemgr import run_filemgr
            return run_filemgr(ROOT,manifest,work,sym,artifacts,send,wait,read,key,move,filemgr_case,filemgr_kernel,filemgr_scenario)
        if desktop:
            from cpc_runtime_desktop import run_desktop
            return run_desktop(ROOT,manifest,work,sym,artifacts,send,wait,read,key,move)
        if config_edit:
            from cpc_runtime_configedit import run_edit
            return run_edit(ROOT,media,manifest,work,sym,artifacts,image,emulator,send,wait,read,key,move,config_edit)
        if chrome_case:
            from cpc_runtime_chrome import run_chrome
            return run_chrome(media,manifest,work,sym,artifacts,image,emulator,
                              send,wait,read,key,move,chrome_case,chrome_fixture)
        if bitmap_case:
            from cpc_runtime_bitmaps import run_bitmaps
            return run_bitmaps(media,manifest,work,sym,artifacts,image,emulator,
                               send,wait,read,key,move,bitmap_case,bitmap_fixture)
        if asset_case:
            from cpc_runtime_assets import run_assets
            return run_assets(media,manifest,work,sym,artifacts,image,emulator,
                              send,wait,read,key,move,asset_case,asset_fixture)
        ram=checked('opened')
        if ram[sym['wm_nwin']]!=2 or ram[sym['wm_focus']]!=1: raise AssertionError('APP failed to open/focus')
        entry=sym['wm_table']+25
        if ram[entry+1:entry+5]!=bytes((11,66,58,68)): raise AssertionError('wrong universal geometry')
        app=(media/'CARD/GBENCH/ABIPROBE.APP').read_bytes();base=physical(ram[entry])
        if ram[base:base+len(app)]!=app: raise AssertionError('loaded APP differs')
        if native or native_fault or config_case:
            from cpc_runtime_native import run_native
            return run_native(ROOT,media,manifest,work,sym,artifacts,image,emulator,
                              send,wait,read,key,move,native_fault,config_case)
        if picker or picker_fault:
            from cpc_runtime_picker import run_picker
            return run_picker(ROOT,manifest,work,sym,artifacts,send,wait,read,key,move,picker_fault)
        if desk:
            from cpc_runtime_desk import run_desk
            return run_desk(ROOT,media,manifest,work,sym,artifacts,image,emulator,
                            send,wait,read,key,move)
        if latency:
            from cpc_runtime_latency import run_latency
            return run_latency(ROOT,media,manifest,work,sym,artifacts,image,emulator,
                               send,wait,read,key,move)
        if clock:
            from cpc_runtime_clock import run_clock
            return run_clock(ROOT,media,manifest,work,sym,artifacts,image,emulator,
                             send,wait,read,key,move)
        if accessories:
            key('F7');rects[2]=(24,24,31,144);order=[0,1,2];calculators[2]='0';titles[2]='Calculator'
            definition=bytes((1,10))+b'Edit\0\0\0\0';menu=definition
            ram=checked('calculator-open')
            calc=(media/'CARD/GBENCH/CALC.APP').read_bytes()
            if hashlib.sha256(calc).hexdigest()!='5e1989d171052d751386b355b1204382c88bba69f4edc632ea65fafb8b7da8f5':
                raise AssertionError('Calculator differs from established MSX build')
            def owner(r,slot):
                return bytes((r[sym['core_win_owner']+slot],r[sym['core_win_owner_gen']+slot]))
            initial_owner=owner(ram,2)
            owner_index=initial_owner[0]-1
            entry=sym['wm_table']+50;base=physical(ram[entry])
            if ram[base:base+len(calc)]!=calc: raise AssertionError('loaded Calculator bytes differ')
            if ram[sym['core_app_service']+owner_index]!=0xA0 or ram[sym['core_app_accessory']+owner_index]!=2:
                raise AssertionError('Calculator did not register its exact accessory identity')
            if not ram[sym['core_defer_handler_hi']+owner_index]: raise AssertionError('missing deferred handler')
            move(28,93);key('SPACE');calculators[2]='7';checked('calculator-button-seven')
            key('2');calculators[2]='72';checked('calculator-keyboard-two')
            move(49,133);key('SPACE');checked('calculator-plus')
            key('3');calculators[2]='3';checked('calculator-keyboard-three')
            move(49,153);key('SPACE');calculators[2]='75';checked('calculator-sum')
            key('F7');ram=checked('calculator-repeat-activation')
            if owner(ram,2)!=initial_owner: raise AssertionError('repeat created a duplicate owner')
            move(16,105);key('SPACE');order=[0,2,1];menu=b'\0';accents[1]=1
            checked('calculator-focus-away')
            key('F7');order=[0,1,2];menu=definition;ram=checked('calculator-exact-activation')
            current=sym['core_defer_current']
            if ram[current:current+8]!=bytes((1,1))+initial_owner+bytes((1,2,0,0)):
                raise AssertionError('wrong deferred sender/receiver/payload')
            at=sym['core_defer_send']+4;pointer=int.from_bytes(ram[at:at+2],'little')
            if not sym['cpc_main_stack']<=pointer<=sym['cpc_main_top']-6:
                raise AssertionError('shared Desktop did not send from a bounded C stack local')
            if ram[sym['core_defer_count']] or ram[sym['core_defer_busy']]:
                raise AssertionError('activation did not drain the serialized FIFO')
            move(12,3);send('key-down SPACE');wait(15);send('key-up SPACE');wait(20)
            popup=(10,-1,('Clear',));checked('calculator-edit-popup')
            key('ESCAPE');popup=None;checked('calculator-edit-cancel')
            move(12,3);send('key-down SPACE');wait(15);send('key-up SPACE');wait(20)
            move(13,13);key('SPACE');popup=None;calculators[2]='0';checked('calculator-edit-clear')
            move(35,29)
            _,r=snapshot(read());grab=(r[sym['poll_byte']],r[sym['poll_line']])
            send('key-down SPACE');wait(10);move(42,39)
            _,r=snapshot(read());drop=(r[sym['poll_byte']],r[sym['poll_line']])
            send('key-up SPACE');wait(60)
            _,r=snapshot(read());moved=tuple(r[entry+1:entry+5])
            expected=(max(0,min(49,24+drop[0]-grab[0])),max(8,min(56,24+drop[1]-grab[1])),31,144)
            if moved!=expected or moved==rects[2]: raise AssertionError('Calculator title drag differs')
            rects[2]=moved;checked('calculator-title-drag')
            key('4');calculators[2]='4';checked('calculator-input-after-drag')
            # The exact live endpoint must be activated BEFORE checking capacity.
            for slot in range(3,8):
                key('F3');rects[slot]=(11,66,58,68);order.append(slot);accents[slot]=0;menu=b'\0'
            ram=checked('accessory-window-slots-full')
            key('F7');order.remove(2);order.append(2);menu=definition
            ram=checked('accessory-activate-while-full')
            if owner(ram,2)!=initial_owner or ram[sym['wm_nwin']]!=8:
                raise AssertionError('full-window activation allocated another instance')
            key('ESCAPE');del rects[2];del calculators[2];order.remove(2);menu=b'\0'
            ram=checked('accessory-close-cleanup')
            for field in ('core_app_service','core_app_accessory','core_defer_handler_lo','core_defer_handler_hi'):
                if ram[sym[field]+owner_index]: raise AssertionError('accessory identity/handler survived teardown')
            key('F7');rects[2]=(24,24,31,144);order.append(2);calculators[2]='0';menu=definition
            ram=checked('accessory-relaunch-fresh-owner')
            if owner(ram,2)==initial_owner: raise AssertionError('relaunch reused stale generation')
            if ram[sym['core_defer_count']] or ram[sym['shell_busy']]: raise AssertionError('unfinished service work')
            if image.read_bytes()!=Path(manifest['image']).read_bytes(): raise AssertionError('accessory run changed M4 media')
            result=dict(checkpoints=checks,sections=manifest['sections'],
                        app_sha256=hashlib.sha256(calc).hexdigest(),
                        emulator_sha256=hashlib.sha256(emulator.read_bytes()).hexdigest())
            (artifacts/'result.json').write_text(json.dumps(result,indent=2)+'\n')
            print('PASS unchanged Calculator/shared accessory policy '+json.dumps(result),flush=True)
            return artifacts
        if filesystem:
            key('F5')
            ram=state('portable-filesystem')
            entry=sym['wm_table']+50
            if ram[sym['wm_nwin']]!=3 or ram[sym['wm_focus']]!=2:
                raise AssertionError('FSPROBE did not open/focus')
            at=next(int(line.split()[2],16) for line in
                    (ROOT/'build/universal-obj/fsprobe/app.noi').read_text().splitlines()
                    if line.startswith('DEF _fsprobe_state '))
            appbase=physical(ram[entry]);result=ram[appbase+at-0x4000:appbase+at-0x4000+8]
            if result[0]!=85: raise AssertionError(f'FSPROBE failed: {list(result)}')
            if any(ram[sym['core_fsctx_table']+144*i] for i in range(4)):
                raise AssertionError('FSPROBE leaked contexts')
            data=subprocess.check_output(['mtype','-i',str(image)+'@@16384','::/UFSTEST/RESULT.BIN'])
            if data!=b'DONE': raise AssertionError('portable write media readback differs')
            # Closing the diagnostic must expose precisely the unchanged ABI
            # Probe/background, including pixels overlaid during filesystem I/O.
            key('ESCAPE');checked('filesystem-close-exposure')
            report=dict(checks=result[1],sections=manifest['sections'],
                        app_sha256=manifest['files']['GBENCH/FSPROBE.APP'],
                        emulator_sha256=hashlib.sha256(emulator.read_bytes()).hexdigest())
            (artifacts/'result.json').write_text(json.dumps(report,indent=2)+'\n')
            print('PASS portable filesystem '+json.dumps(report),flush=True)
            return artifacts
        if menus:
            key('F6');rects[2]=(17,90,58,68);order=[0,1,2];accents[2]=0;titles[2]='Menu ABI'
            definition=bytes((2,10))+b'Probe\0\0\0'+bytes((26,))+b'Tools\0\0\0'
            menu=definition;ram=checked('menu-open')
            entry=sym['wm_table']+50;base=physical(ram[entry])
            menuapp=(media/'CARD/GBENCH/MENUPRBE.APP').read_bytes()
            if ram[base:base+len(menuapp)]!=menuapp: raise AssertionError('menu APP bytes differ')
            at=next(int(line.split()[2],16) for line in
                    (ROOT/'build/universal-obj/menuprobe/app.noi').read_text().splitlines()
                    if line.startswith('DEF _menuprobe_state '))
            state_at=base+at-0x4000
            # Real top-bar click -> current owner's event -> existing portable
            # popup. Its polling loop intentionally suspends the root bar.
            move(12,3);send('key-down SPACE');wait(15);send('key-up SPACE');wait(20)
            popup=(10,-1);ram=checked('popup-open')
            if ram[state_at:state_at+3]!=bytes((1,0,1)):
                raise AssertionError('menu event was not delivered to focused APP')
            move(13,13);wait(15);popup=(10,0);checked('popup-hover')
            key('SPACE');popup=None;accents[2]=1;ram=checked('popup-selected')
            if ram[state_at:state_at+3]!=bytes((1,1,0)):
                raise AssertionError('popup action not selected')
            # Focus the exposed old APP: menu disappears, then returns intact
            # when its owning window is raised again, without moving either.
            move(25,70);key('SPACE');menu=b'\0';order=[0,2,1];ram=checked('menu-focus-away')
            if ram[sym['wm_focus']]!=1: raise AssertionError('focus-away')
            move(73,110);key('SPACE');menu=definition;order=[0,1,2];accents[2]=0
            ram=checked('menu-focus-return')
            if ram[sym['wm_focus']]!=2: raise AssertionError('focus-return')
            # Second title, Escape cancel: leave all save-under pixels intact.
            move(28,3);send('key-down SPACE');wait(15);send('key-up SPACE');wait(20)
            popup=(26,-1);checked('second-popup')
            key('ESCAPE');popup=None;ram=checked('popup-cancelled')
            if ram[state_at:state_at+3]!=bytes((2,1,0)):
                raise AssertionError('cancel changed action count')
            key('ESCAPE');del rects[2];order=[0,1];menu=b'\0';checked('menu-close-exposure')
            if image.read_bytes()!=Path(manifest['image']).read_bytes():
                raise AssertionError('menu test changed M4 files')
            report=dict(checkpoints=checks,sections=manifest['sections'],
                        app_sha256=hashlib.sha256(menuapp).hexdigest(),
                        emulator_sha256=hashlib.sha256(emulator.read_bytes()).hexdigest())
            (artifacts/'result.json').write_text(json.dumps(report,indent=2)+'\n')
            print('PASS shared Desktop bar/menus '+json.dumps(report),flush=True)
            return artifacts
        move(30,100);key('SPACE');accents[1]=1;ram=checked('content-damage')
        move(25,70)
        _,r=snapshot(read());grab=(r[sym['poll_byte']],r[sym['poll_line']])
        send('key-down SPACE');wait(10)
        move(31,78)
        _,r=snapshot(read());drop=(r[sym['poll_byte']],r[sym['poll_line']])
        send('key-up SPACE');wait(60)
        _,r=snapshot(read());rect=tuple(r[entry+1:entry+5])
        expected=(max(0,min(22,11+drop[0]-grab[0])),max(8,min(132,66+drop[1]-grab[1])),58,68)
        if rect!=expected or rect==rects[1]: raise AssertionError('title drag geometry differs')
        rects[1]=rect;ram=checked('moved')
        key('F4');ram=checked('storage-while-windowed')
        if ram[sym['cpc_runtime_fs_calls']]!=1 or ram[sym['cpc_runtime_fs_status']]:
            raise AssertionError('private M4 filesystem service failed')
        at=sym['cpc_runtime_free']
        if int.from_bytes(ram[at:at+2],'little')!=space(image)[0]: raise AssertionError('M4 free-space differs')
        if any(ram[sym['core_fsctx_table']+144*i] for i in range(4)): raise AssertionError('FS context leaked')
        key('F3');rects[2]=(11,66,58,68);order=[0,1,2];accents[2]=0
        ram=checked('overlap-open')
        # The moved first window extends to the right of the second window.
        move(rects[1][0]+56,rects[1][1]+30);key('SPACE')
        accents[1]=0;order=[0,2,1];ram=checked('focus-exposes-first')
        if ram[sym['wm_focus']]!=1: raise AssertionError('exposed window did not gain focus')
        key('ESCAPE');del rects[1];order=[0,2];ram=checked('close-exposes-second')
        key('ESCAPE');rects={};order=[0];menu=bytes((1,10))+b'Desk\0\0\0\0';ram=checked('closed')
        if ram[sym['wm_nwin']]!=1 or ram[sym['core_page_free']]!=sym['cpc_pool_pages']-1: raise AssertionError('close/reclaim')
        # A now toggles the asset gallery; use an unbound key for translation.
        key('B');ram=checked('ascii-key')
        if ram[sym['cpc_runtime_key']]!=ord('b'): raise AssertionError('ASCII input differs')
        key('S');ram=checked('canonical-save-line-restore')
        if ram[sym['cpc_runtime_surface_calls']]!=1 or ram[sym['cpc_runtime_surface_status']]:
            raise AssertionError('save/line/restore service failed')
        if ram[0x6100:0x6120]!=bytes(32): raise AssertionError('canonical saved bytes differ')
        key('F3');rects={1:(11,66,58,68)};order=[0,1];accents={1:0};menu=b'\0';ram=checked('reopened')
        if ram[sym['wm_nwin']]!=2 or ram[sym['core_page_free']]!=sym['cpc_pool_pages']-2: raise AssertionError('reopen/reuse')
        if image.read_bytes()!=Path(manifest['image']).read_bytes(): raise AssertionError('read-only run changed media')
        result=dict(checkpoints=checks,sections=manifest['sections'],app_sha256=hashlib.sha256(app).hexdigest(),
                    emulator_sha256=hashlib.sha256(emulator.read_bytes()).hexdigest())
        (artifacts/'result.json').write_text(json.dumps(result,indent=2)+'\n')
        print('PASS '+json.dumps(result),flush=True)
        return artifacts
    finally:
        process.terminate()
        try: process.wait(timeout=5)
        except subprocess.TimeoutExpired: process.kill();process.wait()
        reader.join(timeout=5)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--emulator',type=Path,default=ROOT.parent/'1984/1984')
    parser.add_argument('--skip-build',action='store_true')
    mode=parser.add_mutually_exclusive_group()
    mode.add_argument('--filesystem',action='store_true')
    mode.add_argument('--menus',action='store_true')
    mode.add_argument('--accessories',action='store_true')
    mode.add_argument('--clock',action='store_true')
    mode.add_argument('--latency',action='store_true')
    mode.add_argument('--desk',action='store_true')
    mode.add_argument('--desktop',action='store_true',help='private actual Desktop boot contract, not File Manager admission')
    parser.add_argument('--desktop-delivery',action='store_true',help='use the regular M4 Desktop image on a disposable copy, optionally with a File Manager scenario')
    mode.add_argument('--filemgr',action='store_true',help='private build-matched native File Manager lifecycle')
    mode.add_argument('--filemgr-case',choices=('missing','short','oversized','corrupt','unbound','no-register'))
    mode.add_argument('--filemgr-scenario',choices=('contexts','services','windows','workflow','stacking','cadence','minute-cadence'))
    mode.add_argument('--root-fault',choices=('missing','short','oversized','cfg-missing','cfg-short','cfg-oversized'))
    mode.add_argument('--native',action='store_true')
    mode.add_argument('--native-fault',choices=('missing','short','oversized'))
    mode.add_argument('--picker',action='store_true')
    mode.add_argument('--picker-fault',choices=('missing','short','oversized'))
    from cpc_runtime_configedit import EDIT_CASES
    mode.add_argument('--config-edit',choices=EDIT_CASES)
    mode.add_argument('--config-case',choices=('missing','empty','exact','oversized','custom'))
    from cpc_runtime_assets import ASSET_CASES
    mode.add_argument('--asset-case',choices=ASSET_CASES)
    from cpc_runtime_bitmaps import BITMAP_CASES
    mode.add_argument('--bitmap-case',choices=BITMAP_CASES)
    from cpc_runtime_chrome import CHROME_CASES
    mode.add_argument('--chrome-case',choices=CHROME_CASES)
    args=parser.parse_args();args.emulator=args.emulator.resolve()
    artifacts=run(**vars(args))
    if args.desktop_delivery and args.filemgr_scenario=='services':
        run(args.emulator,skip_build=True,desktop_delivery=True,filemgr_scenario='reboot',
            seed_image=artifacts/'RUNTIME.IMG')
