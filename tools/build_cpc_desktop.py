#!/usr/bin/env python3
"""Link the actual Desktop against the boot-only native CPC root contract.

Default output is a private linked BIN/report, not an admitted native APP.
The optional integration image remains separate from the normal launcher.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

from build_cpc_runtime import ROOT, assemble, build
from check_app_layout import read_areas, LOADED_AREAS
from gblib_subset import generate


def compile_desktop(work, runtime, sym, root=ROOT):
    work=Path(work).resolve();runtime=Path(runtime).resolve();work.mkdir(parents=True,exist_ok=True)
    if sym.get('cpc_desktop_profile')!=1:
        raise AssertionError('Desktop requires the private native boot profile')
    for name,at in (('gb_msg',0x1302),('poll_mx',0x1306),('poll_my',0x1307),
                    ('poll_flags',0x1308),('wm_table',0x1352),('mw_rect',0x1448)):
        if sym.get(name)!=at: raise AssertionError('native SDK binding changed: '+name)
    sdcc=shutil.which(os.environ.get('SDCC','sdcc'))
    if not sdcc: raise RuntimeError('SDCC required')
    bindir=Path(sdcc).parent;sdas=os.environ.get('SDAS',str(bindir/'sdasz80'))
    (work/'desktop_lib.s').write_text(generate(root/'lib/gb/gblib.s',
        [root/'apps/desktop/platform/cpc.symbols'],
        interrupt_safe=sym.get('cpc_settings_profile')==1))
    (work/'desktop_boot.s').write_text('.module desktop_boot\n'+''.join(
        f'.globl _desktop_{name}\n_desktop_{name} = {sym["cpc_desktop_"+name]}\n'
        for name in ('start','collect')))
    for source,target in ((root/'lib/gb/crt0.s','desktop_crt.rel'),
                          (work/'desktop_lib.s','desktop_lib.rel'),
                          (work/'desktop_boot.s','desktop_boot.rel'),
                          (root/'lib/gembench/gbdefer.s','desktop_defer.rel')):
        subprocess.run([sdas,'-o',target,str(source)],cwd=work,check=True)
    common=['-mz80','--std-c99','--opt-code-size','--fomit-frame-pointer',
            '-DGB_PREEMPTIVE','-DGB_CPC_RESTART',
            '-I',str(root/'lib/gb'),'-I',str(root/'include/gembench'),
            f'-DGB_DESKTOP_BINDINGS="{runtime/"cpc_native.h"}"']
    # Keep helper flags identical to the already-qualified native modules.
    # Raising gbdoc's allocation-search limit to 5000 miscompiled g_nitems[i]
    # with the project compiler; the real M4 popup checks cover that boundary.
    for source,target,defs in (
        ('apps/desktop/main.c','desktop_main.rel',
         ['--max-allocs-per-node','5000',f'-DGB_DESKTOP_PROVIDER="{root/"apps/desktop/platform/cpc.h"}"']),
        ('kernel/kc/cpc_desktop.c','desktop_provider.rel',[]),
        ('lib/gb/gbdoc.c','desktop_doc.rel',['-DGBDOC_MENU_ONLY']),
        ('lib/gb/gbui_stub.c','desktop_ui.rel',[f'-DGB_UI_PROVIDER="{runtime/"cpc_native.h"}"'])):
        subprocess.run([sdcc,*common,*defs,'-c',str(root/source),'-o',target],cwd=work,check=True)
    base,end=sym['cpc_bar_payload'],sym['cpc_bar_end']
    data,limit=sym['cpc_bar_data'],sym['cpc_bar_data_end']
    objects=['desktop_crt','desktop_main','desktop_provider','desktop_doc','desktop_ui',
             'desktop_lib','desktop_boot','desktop_defer']
    subprocess.run([sdcc,'-mz80','--no-std-crt0','--code-loc',hex(base),'--data-loc',hex(data),
                    *(name+'.rel' for name in objects),'-o','desktop.ihx'],cwd=work,check=True)
    areas=read_areas(work/'desktop.map')
    for area,(at,size) in areas.items():
        lo,hi=(base,end) if area in LOADED_AREAS else (data,limit)
        if size and not lo<=at<at+size<=hi:
            raise AssertionError(f'Desktop {area} outside owned allocation: {at:X}+{size}')
    refs=set(re.findall(r'^S (_\w+) Ref[0-9A-Fa-f]+$',(work/'desktop_main.rel').read_text(),re.M))
    forbidden={'_gb_task_root_init','_gb_fs_load','_gb_drives','_gb_get_drive','_gb_set_drive',
               '_gb_copy_begin','_gb_copy_end','_gb_file_delete','_gb_pic_open','_gb_pic_blit',
               '_gb_wm_full','_gb_wm_run','_gb_on_bar','_gb_exit','_gb_titlebar_init',
               '_gb_gadgets_install','_gb_set_name','_gb_dir1','_gb_dirn','_gb_chdir'}
    if refs & forbidden: raise AssertionError('legacy native dependencies: '+str(sorted(refs&forbidden)))
    if any(name.startswith('_gb_msx') for name in refs): raise AssertionError('MSX hardware in CPC root')
    subprocess.run([str(bindir/'makebin'),'-s','65536','-p','desktop.ihx','desktop.bin'],cwd=work,check=True)
    raw=(work/'desktop.bin').read_bytes()[base:]
    if not 0<len(raw)<=end-base: raise AssertionError('Desktop code overflow')
    (work/'DESKTOP.native.bin').write_bytes(raw.ljust(end-base,b'\0'))
    report=dict(status='private boot-only Desktop profile; not a native APP or desktop distribution',
                staged=False,source='apps/desktop/main.c',geometry=[320,200],
                base=base,used=len(raw),budget=end-base,data_base=data,
                data_used=sum(n for k,(_,n) in areas.items() if k not in LOADED_AREAS),
                data_budget=limit-data,snapshot_base=sym['cpc_app_limit'],areas=areas,
                main_requirements=sorted(refs),system_items=['Ram Usage','Tidy Icons']+
                    (['Settings'] if sym.get('cpc_settings_profile')==1 else [])+['About GEOBENCH'],
                deferred=([] if sym.get('cpc_filemgr_profile')==1 else ['native File Manager admission'])+
                         ([] if sym.get('cpc_settings_profile')==1 else ['Settings'])+
                         ['savers','wallpaper/PIC paging',
                          'trash/delete','media refresh/hotplug','firmware exit'])
    (work/'desktop_layout.json').write_text(json.dumps(report,indent=2)+'\n')
    return report


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'build/cpc-desktop-link')
    parser.add_argument('--integration-image',action='store_true')
    args=parser.parse_args()
    if args.integration_image:
        build(desktop=True)
        return
    runtime=args.output.resolve()/'runtime'
    sym=assemble(runtime,('-DCPC_NATIVE_DESKTOP=1',))
    print(json.dumps(compile_desktop(args.output,runtime,sym),indent=2))


if __name__=='__main__': main()
