#!/usr/bin/env python3
"""Link shared Settings to real CPC services; optionally build its private M4 profile.

This is the first #79 gate: complete code/data/helper layout and explicit native
bindings. A successful link is not M4 runtime qualification or APP admission.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

from build_cpc_runtime import ROOT, assemble
from check_app_layout import LOADED_AREAS, read_areas
from gblib_subset import generate

FILESYSTEM = {'gb_drives','gb_get_drive','gb_set_drive','gb_back','gb_dir1','gb_dirn',
              'gb_entname','gb_isdir','gb_chdir','gb_set_name','gb_fs_load'}
MAIN_CALLS = FILESYSTEM | {
    'settings_begin','settings_end','settings_io_reset','settings_io_failed','settings_commit',
    'settings_storage_claim','gb_app_quit','gb_backdrop','gb_curhide','gb_curshow',
    'gb_fill','gb_frame','gb_getkey','gb_mx','gb_my','gb_repaint_top',
    'gb_select','gb_select_hit','gb_textbw','gb_popup','gb_alert','gb_wm_close',
    'gb_wm_h','gb_wm_w','gb_wm_x','gb_wm_y','gb_wm_managed_kind',
    '_divuchar','_mulint','_divuint','_moduchar'}


def requirements(obj):
    refs=set(re.findall(r'^S (_\w+) Ref[0-9A-Fa-f]+$',obj,re.M))
    unknown=refs-{'_'+name for name in MAIN_CALLS}
    if unknown: raise ValueError('unreviewed native Settings dependency: '+str(sorted(unknown)))
    if not {'_settings_commit','_settings_begin','_gb_wm_managed_kind'} <= refs:
        raise ValueError('wrong Settings source/provider profile')
    return refs


def compile_settings(work,runtime,sym,root=ROOT):
    work=Path(work).resolve();runtime=Path(runtime).resolve()
    work.mkdir(parents=True,exist_ok=True)
    for name,address in (('gb_msg',0x1302),('poll_mx',0x1306),('poll_my',0x1307),
                         ('poll_flags',0x1308),('mw_rect',0x1448),('cpc_app_limit',0x7F00)):
        if sym.get(name)!=address: raise ValueError('native Settings layout changed: '+name)
    if sym['cpc_ui_request_end']-sym['cpc_ui_text'] < 16*11+6:
        raise ValueError('Settings picker labels exceed native UI capacity')
    sdcc=shutil.which(os.environ.get('SDCC','sdcc'))
    if not sdcc: raise RuntimeError('SDCC required for native Settings link')
    bindir=Path(sdcc).parent;sdas=os.environ.get('SDAS',str(bindir/'sdasz80'))
    (work/'gblib.s').write_text(generate(root/'lib/gb/gblib.s',
                                      [root/'apps/settings/platform/cpc.symbols'],interrupt_safe=True))
    (work/'sys.symbols').write_text('gb_app_quit\n')
    (work/'sys.s').write_text(generate(root/'lib/gb/gbsys.s',[work/'sys.symbols']))
    for source,target in ((root/'lib/gb/crt0.s','crt.rel'),(work/'gblib.s','gblib.rel'),
                          (work/'sys.s','sys.rel'),(root/'lib/gb/gbwindow_kind.s','kind.rel'),
                          (root/'lib/gb/gbrepaint.s','repaint.rel'),
                          (runtime/'native_fs.s','native_fs.rel')):
        subprocess.run([sdas,'-o',target,str(source)],cwd=work,check=True)
    common=['-mz80','--std-c99','--opt-code-size','--fomit-frame-pointer',
            '--max-allocs-per-node','100000','-DGB_PREEMPTIVE','-DGB_CPC_RESTART',
            '-DGB_NATIVE_WINDOW_KIND',
            '-I',str(root/'lib/gb'),'-I',str(root/'include/gembench'),
            f'-DGB_SETTINGS_BINDINGS="{runtime/"cpc_native.h"}"',
            f'-DGB_FSCTX_PLATFORM_HEADER="{runtime/"cpc_fs_client.h"}"']
    for source,target,defs in (
        ('apps/settings/main.c','main.rel',
         [f'-DGB_SETTINGS_PROVIDER="{root/"apps/settings/platform/cpc.h"}"']),
        ('kernel/kc/cpc_settings.c','provider.rel',[]),
        ('lib/gb/gbselect.c','selector.rel',[]),
        ('lib/gembench/gbfsctx.c','fs.rel',[]),
        ('lib/gb/gbui_stub.c','ui.rel',[f'-DGB_UI_PROVIDER="{runtime/"cpc_native.h"}"'])):
        subprocess.run([sdcc,*common,*defs,'-c',str(root/source),'-o',target],cwd=work,check=True)
    refs=requirements((work/'main.rel').read_text())
    provided=set(re.findall(r'^S (_\w+) Def[0-9A-Fa-f]+$',(work/'provider.rel').read_text(),re.M))
    if not {'_'+name for name in FILESYSTEM} <= provided:
        raise ValueError('native filesystem calls are not supplied by the owned Settings facade')
    base,data,limit=0x4000,0x7800,sym['cpc_app_limit']
    objects=['crt.rel','main.rel','provider.rel','selector.rel','fs.rel','ui.rel',
             'gblib.rel','sys.rel','kind.rel','repaint.rel','native_fs.rel']
    subprocess.run([sdcc,'-mz80','--no-std-crt0','--code-loc',hex(base),'--data-loc',hex(data),
                    *objects,'-o','settings.ihx'],cwd=work,check=True)
    areas=read_areas(work/'settings.map')
    for name,(at,size) in areas.items():
        lo,hi=(base,data) if name in LOADED_AREAS else (data,limit)
        if size and not lo<=at<at+size<=hi:
            raise ValueError(f'Settings {name} outside owned allocation: {at:X}+{size}')
    subprocess.run([str(bindir/'makebin'),'-s','65536','-p','settings.ihx','settings.bin'],cwd=work,check=True)
    raw=(work/'settings.bin').read_bytes()[base:]
    if not 0<len(raw)<=data-base: raise ValueError('Settings code image exceeds checked budget')
    (work/'SETTINGS.native.bin').write_bytes(raw)
    report=dict(status='linked only; launch/admission and M4 qualification remain disabled',
                staged=False,runtime_qualified=False,source='apps/settings/main.c',
                profile='native CPC appearance-only',geometry=[320,200],
                settings=['FONT','ICONS','CURSOR','TITLEBAR','GADGETS','BACKDROP'],
                deferred=['palette','wallpaper','savers','reset defaults','System menu launch'],
                code_bytes=len(raw),code_budget=data-base,code_sha256=hashlib.sha256(raw).hexdigest(),
                data_base=data,data_bytes=sum(size for name,(_,size) in areas.items() if name not in LOADED_AREAS),
                data_budget=limit-data,snapshot_base=limit,areas=areas,
                main_requirements=sorted(refs),owned_filesystem_calls=sorted(FILESYSTEM),
                icon_header_read_bytes=16,picker_max_labels=17,picker_max_text_bytes=16*11+6,
                runtime_kernel_sha256=hashlib.sha256((runtime/'CORE.RAW').read_bytes()).hexdigest())
    (work/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    return report


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'build/cpc-settings-link')
    parser.add_argument('--integration-image',action='store_true')
    args=parser.parse_args()
    if args.integration_image:
        from build_cpc_runtime import build
        build(settings=True)
        return
    work=args.output.resolve();runtime=work/'runtime'
    sym=assemble(runtime)
    print(json.dumps(compile_settings(work,runtime,sym),indent=2))


if __name__=='__main__': main()
