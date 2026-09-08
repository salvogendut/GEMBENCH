"""Link shared config/dialog/picker code against checked native CPC allocations."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

from check_app_layout import LOADED_AREAS, read_areas
from gblib_subset import generate


def provider(work, sym):
    out = []
    def byte(name, address): out.append(f'#define {name} (*(volatile unsigned char *){address})')
    def word(name, address): out.append(f'#define {name} (*(unsigned int *){address})')
    def ptr(name, address, kind='char'): out.append(f'#define {name} (({kind} *){address})')
    cfg = sym['cpc_cfg_output']; ui = sym['cpc_ui_request']
    ptr('KCFG_TEXT', sym['cpc_cfg_text'], 'const char')
    word('KCFG_LEN', cfg)
    out += [f'#define CHROME_CFG_LEN {cfg}',
            f'#define CHROME_CFG_TEXT {sym["cpc_cfg_text"]}']
    ptr('CPC_TITLE_NAME', sym['cpc_title_name'])
    ptr('CPC_GADGET_NAME', sym['cpc_gadget_name'])
    for name, offset in (('KCFG_ICONNAME',2),('KCFG_FONTNAME',13),('KCFG_MEMSTR',26),
                         ('KCFG_CURSORNAME',33),('KCFG_BDPNAME',49)):
        ptr(name, cfg+offset)
    word('KCFG_MEMKB', cfg+24)
    ptr('KCFG_INKS', cfg+44, 'unsigned char')
    for name, offset in (('KCFG_BDDRIVE',60),('KCFG_BD_SOLID',61),('KCFG_FRAMEPEN',62)):
        # Config results are staged, then applied by the visual-asset provider.
        out.append(f'#define {name} (*(unsigned char *){cfg+offset})')
    ptr('FS_REQ_NAME', sym['fs_req_name'])
    for name, offset in (('UI_OP',0),('UI_COL',1),('UI_LINE',2),('UI_N',3),('UI_RES',4),('UI_MODAL',5)):
        byte(name, ui+offset)
    byte('FILEMGR_WINDOW_COUNT', sym['wm_nwin'])
    byte('FILEMGR_FOCUS', sym['wm_focus'])
    byte('FILEMGR_FREE_PAGES', sym['core_page_free'])
    out.append(f'#define FILEMGR_WINDOW_LIMIT {sym["cpc_window_max"]}')
    ptr('DESKTOP_MENU', sym['menu_def'], 'volatile unsigned char')
    ptr('DESKTOP_FULLSCREEN', 0x130A, 'volatile unsigned char')
    out.append(f'#define DESKTOP_KERNEL_BYTES {sym["cpc_kernel_used_end"]-sym["cpc_kernel_begin"]}u')
    out.append(f'#define DESKTOP_FILEMGR_READY {int(sym.get("cpc_filemgr_profile")==1)}')
    out.append(f'#define DESKTOP_SETTINGS_READY {int(sym.get("cpc_settings_profile")==1)}')
    ptr('UI_NAME', ui+8)
    ptr('UI_TEXT', sym['cpc_ui_text'])
    ptr('GB_UI_TEXT_END', sym['cpc_ui_request_end'], 'const char')
    word('UI_WIDTH', ui+8); word('UI_HEIGHT', ui+10)
    byte('GB_UI_STATUS', sym['cpc_ui_status'])
    ptr('CPC_PICK_PATH', sym['cpc_pick_path'])
    word('CPC_PICK_OWNER', sym['cpc_pick_owner'])
    word('CPC_UI_OWNER', sym['cpc_ui_owner'])
    byte('CPC_PICK_STATUS', sym['cpc_pick_status'])
    word('CPC_PICK_PROBE_BYTES', sym['cpc_pick_probe_bytes'])
    ptr('CPC_PICK_PROBE_DATA', sym['cpc_pick_probe_data'])
    out.append(f'#define CPC_EDIT_OP {sym["cpc_edit_op"]}')
    for name in ('STATUS','CHANGED','ERROR'):
        byte('CPC_EDIT_'+name,sym['cpc_edit_'+name.lower()])
    out += [f'#define GB_UI_SAVEUNDER {sym["cpc_ui_under"]}',
            f'#define GB_POPUP_BUFFER {sym["cpc_ui_popup"]}',
            f'#define GB_POPUP_CAPACITY {sym["cpc_ui_popup_end"]-sym["cpc_ui_popup"]}']
    path = work/'cpc_native.h'
    path.write_text('\n'.join(out)+'\n')
    return path


def compile_native(work, sym, root):
    sdcc = shutil.which(os.environ.get('SDCC','sdcc'))
    if not sdcc: raise RuntimeError('SDCC required for native modules')
    bindir = Path(sdcc).parent
    sdas = os.environ.get('SDAS',str(bindir/'sdasz80'))
    header = provider(work, sym)
    fsheader=work/'cpc_fs_client.h'
    fsheader.write_text(
        f'#define GB_FSCTX_REQUEST_ADDRESS {sym["cpc_fs_request"]}\n'
        f'#define GB_FSCTX_TRANSFER_ADDRESS {sym["cpc_fs_xfer"]}\n'
        '#define GB_FSCTX_REQUEST ((volatile unsigned char *)GB_FSCTX_REQUEST_ADDRESS)\n'
        '#define GB_FSCTX_TRANSFER ((volatile unsigned char *)GB_FSCTX_TRANSFER_ADDRESS)\n'
        '#define GB_FSCTX_WORD_AT(offset) (*(volatile unsigned int *)(GB_FSCTX_REQUEST_ADDRESS+(offset)))\n')
    (work/'native_fs.s').write_text('.module native_fs\n.globl _gb_fsctx_call\n'
                                   f'_gb_fsctx_call = {sym["cpc_native_fs_call"]}\n'
                                   '.globl _cpc_config_update\n'
                                   f'_cpc_config_update = {sym["cpc_config_update"]}\n')
    (work/'cpc_picker.h').write_text('extern unsigned char cpc_picker_error(void);\n'
                                   '#define GB_PICK_STATUS cpc_picker_error\n')
    (work/'ui_lib.s').write_text(generate(root/'lib/gb/gblib.s',[root/'kernel/kc/cpc_ui.symbols'],
                                       interrupt_safe=sym.get('cpc_settings_profile')==1))
    for source, target in ((root/'lib/gb/crt0.s','native_crt.rel'),(work/'ui_lib.s','ui_lib.rel'),
                           (work/'native_fs.s','native_fs.rel')):
        subprocess.run([sdas,'-o',target,str(source)],cwd=work,check=True)
    shared = ['-mz80','--opt-code-size','--fomit-frame-pointer','-I',str(root/'lib/gb'),
              '-I',str(root/'include/gembench')]
    fsdefs=[f'-DGB_FSCTX_PLATFORM_HEADER="{fsheader}"']
    cfgdefs = [f'-DGB_CONFIG_PROVIDER="{header}"','-DGB_CONFIG_CHROME']
    version=(root/'VERSION').read_text().strip()
    commit=os.environ.get('GIT_COMMIT') or subprocess.check_output(
        ['git','rev-parse','--short=12','HEAD'],cwd=root,text=True).strip()
    if not re.fullmatch(r'[A-Za-z0-9._+-]{1,12}',version) or not re.fullmatch(r'[A-Za-z0-9._+-]{1,13}',commit):
        raise ValueError('invalid native module build identity')
    (work/'native_identity.json').write_text(json.dumps(dict(version=version,git=commit))+'\n')
    uidefs = [f'-DGB_UI_PROVIDER="{header}"','-DGBUI_BASIC_ONLY',
              f'-DGB_VERSION="{version}"',f'-DGB_GIT="{commit}"']
    if sym.get('cpc_settings_profile')==1:
        uidefs.append('-DGB_UI_POPUP_MAX=17')  # 16 backdrop stems plus SOLID
    for source, target, defs in (
        ('kernel/kc/kcfg_mod.c','native_cfg.rel',cfgdefs),
        ('kernel/kc/kcfg.c','native_parser.rel',
         ['-DGB_CFG_ASSET_EXTENSIONS'] if sym.get('cpc_settings_profile')==1 else []),
        ('kernel/kc/gbui_mod.c','native_ui.rel',uidefs),
        ('kernel/kc/cpc_picker_mod.c','native_picker.rel',[*fsdefs,f'-DGB_UI_PROVIDER="{header}"']),
        ('kernel/kc/cpc_config_edit.c','native_edit.rel',[*fsdefs,f'-DGB_UI_PROVIDER="{header}"']),
        ('lib/gb/gbpick.c','native_picklib.rel',[f'-DGB_PICK_PROVIDER="{work/"cpc_picker.h"}"']),
        ('lib/gembench/gbfsctx.c','native_fs_client.rel',fsdefs),
        ('lib/gb/gbdlg.c','native_popup.rel',
         [f'-DGB_POPUP_BUFFER={sym["cpc_ui_popup"]}',
          f'-DGB_POPUP_CAPACITY={sym["cpc_ui_popup_end"]-sym["cpc_ui_popup"]}']),
        ('lib/gb/gbprompt.c','native_prompt.rel',[])):
        subprocess.run([sdcc,*shared,*defs,'-c',str(root/source),'-o',target],cwd=work,check=True)
    layout = {}
    for name, objects in (('GBCFG', ['native_cfg.rel','native_parser.rel']),
                           ('GBUI', ['native_ui.rel','native_popup.rel','native_prompt.rel','ui_lib.rel']),
                           ('GBPICK', ['native_picker.rel','native_picklib.rel','native_popup.rel',
                                       'native_fs_client.rel','native_fs.rel','ui_lib.rel']),
                           ('GBEDIT', ['native_edit.rel','native_fs_client.rel','native_fs.rel'])):
        base,end=sym['cpc_module_base'],sym['cpc_module_code_end']
        data,limit=sym['cpc_module_data'],sym['cpc_module_data_end']
        subprocess.run([sdcc,'-mz80','--no-std-crt0','--code-loc',hex(base),'--data-loc',hex(data),
                        'native_crt.rel',*objects,'-o',name+'.ihx'],cwd=work,check=True)
        areas=read_areas(work/(name+'.map'))
        for area,(at,size) in areas.items():
            lo,hi=(base,end) if area in LOADED_AREAS else (data,limit)
            if size and not lo<=at<at+size<=hi:
                raise AssertionError(f'{name} {area} outside owned allocation: {at:X}+{size}')
        subprocess.run([str(bindir/'makebin'),'-s','65536','-p',name+'.ihx',name+'.bin'],cwd=work,check=True)
        raw=(work/(name+'.bin')).read_bytes()[base:]
        if not 1<=len(raw)<=end-base: raise AssertionError(name+' module code overflow')
        (work/(name+'.MOD')).write_bytes(raw.ljust(end-base,b'\0'))
        layout[name]=dict(base=base,used=len(raw),budget=end-base,data_base=data,
                         data_used=sum(size for area,(_,size) in areas.items() if area not in LOADED_AREAS),
                         data_budget=limit-data)
    (work/'native_layout.json').write_text(json.dumps(layout,indent=2)+'\n')
    return layout
