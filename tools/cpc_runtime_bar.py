"""Link the shared Desktop menu/bar component in the bounded native root page."""
import os
from pathlib import Path
import shutil
import subprocess

from check_app_layout import LOADED_AREAS, read_areas
from gblib_subset import generate


def compile_bar(work, sym, root):
    sdcc = shutil.which(os.environ.get('SDCC', 'sdcc'))
    if not sdcc:
        raise RuntimeError('SDCC required for shared Desktop bar')
    bindir = Path(sdcc).parent
    sdas = os.environ.get('SDAS', str(bindir / 'sdasz80'))
    (work / 'bar_lib.s').write_text(generate(root / 'lib/gb/gblib.s',
                                            [root / 'kernel/kc/cpc_root_bar.symbols']))
    for source, output in ((root / 'kernel/kc/cpc_root_bar.s', 'bar_entry.rel'),
                           (work / 'bar_lib.s', 'bar_lib.rel'),
                           (root / 'lib/gembench/gbdefer.s', 'bar_defer.rel')):
        subprocess.run([sdas, '-o', output, str(source)], cwd=work, check=True)
    subprocess.run([sdcc, '-mz80', '--std-c99', '--opt-code-size', '--fomit-frame-pointer',
                    f'-DGB_UI_PROVIDER="{work / "cpc_native.h"}"',
                    f'-DGB_FSCTX_PLATFORM_HEADER="{work / "cpc_fs_client.h"}"',
                    '-I', str(root / 'lib/gb'), '-c', str(root / 'kernel/kc/cpc_root_bar.c'),
                    '-I', str(root / 'include/gembench'),
                    '-o', 'bar.rel'], cwd=work, check=True)
    for source, output, defs in (
            ('gbdoc.c', 'doc.rel', ['-DGBDOC_MENU_ONLY']),
            ('gbdlg.c', 'popup.rel', [f'-DGB_POPUP_BUFFER={sym["cpc_root_popup"]}',
                                     f'-DGB_POPUP_CAPACITY={sym["cpc_root_popup_end"]-sym["cpc_root_popup"]}'])):
        subprocess.run([sdcc, '-mz80', '--std-c99', '--opt-code-size', '--fomit-frame-pointer',
                        *defs, '-I', str(root/'lib/gb'), '-c', str(root/'lib/gb'/source),
                        '-o', output], cwd=work, check=True)
    base, end = sym['cpc_bar_payload'], sym['cpc_bar_end']
    data, limit = sym['cpc_bar_data'], sym['cpc_bar_data_end']
    subprocess.run([sdcc, '-mz80', '--no-std-crt0', '--code-loc', hex(base),
                    '--data-loc', hex(data), 'bar_entry.rel', 'bar.rel', 'bar_lib.rel', 'bar_defer.rel',
                    'doc.rel', 'popup.rel', 'native_fs_client.rel', 'native_fs.rel',
                    '-o', 'bar.ihx'], cwd=work, check=True)
    areas = read_areas(work / 'bar.map')
    for name, (address, size) in areas.items():
        lo, hi = (base, end) if name in LOADED_AREAS else (data, limit)
        if size and not lo <= address < address + size <= hi:
            raise AssertionError(f'Desktop bar allocation overflow: {name} {address:X}+{size}')
        if size and name in ('_INITIALIZED', '_INITIALIZER', '_GSINIT', '_GSFINAL'):
            raise AssertionError('Desktop bar must not require CRT initialization')
    subprocess.run([str(bindir / 'makebin'), '-s', '65536', '-p', 'bar.ihx', 'bar.bin'], cwd=work, check=True)
    raw = (work / 'bar.bin').read_bytes()[base:]
    if not 36 <= len(raw) <= end-base:
        raise AssertionError('Desktop bar binary exceeds resident slot')
    (work / 'ROOTBAR.BIN').write_bytes(raw.ljust(end-base, b'\0'))
    return dict(base=base, used=len(raw), budget=end-base,
                data_base=data, data_used=sum(n for k, (_, n) in areas.items() if k not in LOADED_AREAS),
                data_budget=limit-data, popup_base=sym['cpc_root_popup'],
                popup_budget=sym['cpc_root_popup_end']-sym['cpc_root_popup'])
