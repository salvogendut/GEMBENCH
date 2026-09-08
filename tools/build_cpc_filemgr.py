#!/usr/bin/env python3
"""Link the actual File Manager against checked native CPC runtime bindings.

Default output is a private link artifact/report, not an admitted/staged APP.
--integration-image binds it to a separate build-matched qualification kernel.
The normal runtime's universal-only admission stays closed to native binaries.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import zlib

from build_cpc_runtime import ROOT, assemble
from check_app_layout import LOADED_AREAS, read_areas
from gblib_subset import generate


def compile_filemgr(work, runtime, sym, root=ROOT):
    work=Path(work).resolve();runtime=Path(runtime).resolve()
    work.mkdir(parents=True, exist_ok=True)
    sdcc=shutil.which(os.environ.get('SDCC','sdcc'))
    if not sdcc: raise RuntimeError('SDCC required for the native File Manager link')
    bindir=Path(sdcc).parent;sdas=os.environ.get('SDAS',str(bindir/'sdasz80'))
    # These retained native SDK cells are also consumed by the shared kernel.
    # Other native services/storage are selected explicitly, not old CPC stubs.
    for name,at in (('gb_msg',0x1302),('poll_mx',0x1306),('poll_my',0x1307),
                    ('poll_flags',0x1308),('mw_rect',0x1448)):
        if sym.get(name)!=at: raise AssertionError('native SDK binding changed: '+name)
    (work/'gblib.s').write_text(generate(root/'lib/gb/gblib.s',
                                       [root/'apps/filemgr/platform/cpc.symbols']))
    (work/'sys.symbols').write_text('gb_app_quit\n')
    (work/'sys.s').write_text(generate(root/'lib/gb/gbsys.s',[work/'sys.symbols']))
    for source,target in ((root/'lib/gb/crt0.s','crt.rel'),(work/'gblib.s','gblib.rel'),
                          (work/'sys.s','sys.rel'),(root/'lib/gb/gbwindow_kind.s','kind.rel'),
                          (root/'lib/gb/gbrepaint.s','repaint.rel'),
                          (runtime/'native_fs.s','native_fs.rel')):
        subprocess.run([sdas,'-o',target,str(source)],cwd=work,check=True)
    common=['-mz80','--std-c99','--opt-code-size','--fomit-frame-pointer',
            '--max-allocs-per-node','5000','-DGB_PREEMPTIVE','-DGB_CPC_RESTART',
            '-DGB_NATIVE_WINDOW_KIND','-I',str(root/'lib/gb'),
            '-I',str(root/'include/gembench'),
            f'-DGB_FSCTX_PLATFORM_HEADER="{runtime/"cpc_fs_client.h"}"',
            f'-DGB_FILEMGR_BINDINGS="{runtime/"cpc_native.h"}"']
    for source,target,defs in (
        ('apps/filemgr/main.c','main.rel',
         [f'-DGB_FILEMGR_PROVIDER="{root/"apps/filemgr/platform/cpc.h"}"']),
        ('kernel/kc/cpc_filemgr.c','provider.rel',[]),
        ('lib/gembench/gbr_menu.c','menu.rel',[]),
        ('lib/gembench/gbfsctx.c','fs.rel',[]),
        ('lib/gb/gbscroll.c','scroll.rel',[]),
        ('lib/gb/gbui_stub.c','ui.rel',
         ['-DGBR_MENU_RUNTIME',f'-DGB_UI_PROVIDER="{runtime/"cpc_native.h"}"'])):
        subprocess.run([sdcc,*common,*defs,'-c',str(root/source),'-o',target],cwd=work,check=True)
    objects=['crt.rel','main.rel','provider.rel','menu.rel','fs.rel','scroll.rel','ui.rel',
             'gblib.rel','sys.rel','kind.rel','repaint.rel','native_fs.rel']
    base=0x4000;data=0x7800;limit=sym['cpc_app_limit']
    subprocess.run([sdcc,'-mz80','--no-std-crt0','--code-loc',hex(base),'--data-loc',hex(data),
                    *objects,'-o','filemgr.ihx'],cwd=work,check=True)
    areas=read_areas(work/'filemgr.map')
    for name,(at,size) in areas.items():
        lo,hi=(base,data) if name in LOADED_AREAS else (data,limit)
        if size and not lo<=at<at+size<=hi:
            raise AssertionError(f'File Manager {name} outside owned allocation: {at:X}+{size}')
    # No legacy filesystem, module probing, copy buffer, software dragging,
    # msx-only hardware or monolithic window manager may sneak back into main.
    refs=set(re.findall(r'^S (_\w+) Ref[0-9A-Fa-f]+$',(work/'main.rel').read_text(),re.M))
    forbidden={'_gb_dir1','_gb_dirn','_gb_back','_gb_chdir','_gb_entname','_gb_isdir',
               '_gb_fs_load','_gb_fs_save','_gb_copy_begin','_gb_copy_end','_gb_drag_start',
               '_gb_drag_window','_gb_drag_resize','_gb_get_drive','_gb_set_drive',
               '_gb_set_name','_gb_wm_full','_gb_doc','_gb_pic_edit'}
    if refs & forbidden: raise AssertionError('legacy native dependencies: '+str(sorted(refs & forbidden)))
    if any(name.startswith('_gb_msx') for name in refs): raise AssertionError('MSX hardware in CPC app')
    subprocess.run([str(bindir/'makebin'),'-s','65536','-p','filemgr.ihx','filemgr.bin'],cwd=work,check=True)
    raw=(work/'filemgr.bin').read_bytes()[base:]
    if not 0<len(raw)<=data-base: raise AssertionError('native File Manager image overflow')
    (work/'FILEMGR.native.bin').write_bytes(raw)
    report=dict(status='linked only; native APP admission and runtime qualification still required',
                staged=False,source='apps/filemgr/main.c',geometry=[320,200],
                code_bytes=len(raw),code_sha256=hashlib.sha256(raw).hexdigest(),code_budget=data-base,data_base=data,
                data_bytes=sum(size for name,(_,size) in areas.items() if name not in LOADED_AREAS),
                data_budget=limit-data,snapshot_base=limit,areas=areas,main_requirements=sorted(refs),
                deferred=['copy/delete/drag-drop','embedded APP icon probing',
                          'data-file associations','apps outside qualified /GBENCH profile'])
    (work/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    return report


def bind_runtime(runtime, app, sym):
    """Bind one checked native system image, without changing code addresses.

    This private receiver is build-specific, not a portable package or a
    security sandbox. The ordinary runtime has no contract to patch.
    """
    runtime=Path(runtime);app=Path(app)
    if sym.get('cpc_filemgr_profile')!=1:
        raise AssertionError('native File Manager requires its private runtime profile')
    raw=(app/'FILEMGR.native.bin').read_bytes()
    report=json.loads((app/'report.json').read_text())
    if not 0<len(raw)<=0x3800 or len(raw)!=report['code_bytes'] or \
            hashlib.sha256(raw).hexdigest()!=report['code_sha256']:
        raise AssertionError('native File Manager differs from checked link')
    contract=len(raw).to_bytes(2,'little')+zlib.crc32(raw).to_bytes(4,'little')
    kernel=bytearray((runtime/'CORE.RAW').read_bytes())
    off=sym['cpc_filemgr_contract']-sym['cpc_kernel_begin']
    if not 0<=off<=len(kernel)-6 or kernel[off:off+6] not in (bytes(6),contract):
        raise AssertionError('invalid native contract patch site')
    kernel[off:off+6]=contract
    (runtime/'CORE.RAW').write_bytes(kernel)
    report.update(status='private build-matched native File Manager; runtime qualification required',
                  private_integration=True,
                  contract=contract.hex(),runtime_contract=sym['cpc_filemgr_contract'])
    (runtime/'filemgr_layout.json').write_text(json.dumps(report,indent=2)+'\n')
    return report


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'build/cpc-filemgr')
    parser.add_argument('--integration-image',action='store_true')
    args=parser.parse_args()
    if args.integration_image:
        from build_cpc_runtime import build
        build(filemgr=True)
        return
    args.output=args.output.resolve()
    runtime=args.output/'runtime'
    sym=assemble(runtime)
    print(json.dumps(compile_filemgr(args.output,runtime,sym),indent=2))


if __name__=='__main__': main()
