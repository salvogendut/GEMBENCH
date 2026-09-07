#!/usr/bin/env python3
"""Compose the shared CPC core and universal launcher on a private M4 card."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

from build_cpc_foundation import headed
from build_cpc_production import ROOT, memory_regions, symbols
from cpc_production_fsctx import compile_module
from cpc_runtime_bar import compile_bar
from cpc_native_modules import compile_native
from cpc_production_services import compile_timer
import genfont
import packicons

ICON_SOURCES = ('floppy','clock','trash','geobench','basic','binary','picture',
                'text','folder','app','font','desktop','filemanager','sd','up',
                'screensaver','cf','ide','fractal','settings','calculator')


def bitmap_assets(work):
    packicons.main(['packicons',str(work/'DEFAULT.IST'),
                    *(str(ROOT/f'lib/icon_{name}.asm') for name in ICON_SOURCES)])
    subprocess.run(['python3',str(ROOT/'tools/png2spr.py'),str(ROOT/'assets/pointer.png'),
                    str(work/'DEFAULT.SPR'),'cursor','12x16'],check=True)
    (work/'REFINED.IST').write_bytes((ROOT/'assets/iconsets/REFINED.IST').read_bytes())
    for folder,extension,size in (('titlebars','TBR',56),('gadgets','GDT',50)):
        raw=(ROOT/f'assets/{folder}/ORIGINAL.{extension}').read_bytes()
        if len(raw)!=size: raise AssertionError('invalid embedded '+extension)
        (work/f'ORIGINAL.{extension}').write_bytes(raw)


def title_module(work, sym):
    names=('data_title','cpc_title_module_size','cpc_title_off','rect_x','rect_y','rect_w','rect_h',
           'fb_x','fb_y','draw_rows','draw_y','scr_addr')
    (work/'title_symbols.inc').write_text('\n'.join(f'{k} equ {sym[k]}' for k in names)+'\n')
    subprocess.run([os.environ.get('RASM','rasm'),str(ROOT/'kernel/cpc_title_module.asm'),
                    '-s','-sq','-o','title',f'-I{work}'],cwd=work,check=True)
    return symbols(work/'title.sym')['cpc_title_module_used_end']-sym['data_title']


def assemble(work: Path, overrides=()):
    work.mkdir(parents=True, exist_ok=True)
    genfont.main(["genfont", str(work / "DEFAULT.FNT")])
    bitmap_assets(work)
    (work / "fsctx_size.inc").write_text("CPC_FS_MODULE_BYTES equ 1\n")
    (work / "TIMER.BIN").write_bytes(bytes(116))
    command = [os.environ.get("RASM", "rasm"), str(ROOT / "kernel/cpc_runtime.asm"),
               "-s", "-sq", "-o", "runtime", f"-I{work}", *overrides]
    subprocess.run(command, cwd=work, check=True)
    initial = symbols(work / "runtime.sym")
    title_module(work,initial)
    compile_module(work, initial, ROOT, directory=True, writable=True)
    compile_timer(work, initial, ROOT)
    compile_native(work, initial, ROOT)
    bar = compile_bar(work, initial, ROOT)
    (work / "bar_layout.json").write_text(json.dumps(bar, indent=2) + "\n")
    subprocess.run(command, cwd=work, check=True)
    sym = symbols(work / "runtime.sym")
    def resident(s): return {k: v for k, v in s.items() if k != "cpc_fs_module_bytes"}
    if resident(sym) != resident(initial):
        raise AssertionError("FS/bar modules changed runtime addresses")
    memory_regions(sym)
    (work / "boot_symbols.inc").write_text("\n".join(
        f"{name} equ {sym[name]}" for name in
        ("foundation_bank_set", "storage_gate", "storage_ga_set", "storage_rom_set",
         "storage_command", "storage_send")) + "\n")
    for source, output in (("cpc_m4_loader.asm", "loader"), ("cpc_m4_boot.asm", "boot")):
        subprocess.run([os.environ.get("RASM", "rasm"), str(ROOT / "kernel" / source),
                        "-s", "-sq", "-o", output, f"-I{work}", "-DCPC_DRAWING=1",
                        f"-DCPC_LOAD_BYTES={(work / 'CORE.RAW').stat().st_size}"],
                       cwd=work, check=True)
    return sym


def build():
    work = ROOT / "build/cpc-runtime"
    sym = assemble(work)
    app = ROOT / "build/universal/ABIPROBE.APP"
    subprocess.run(["bash", "tools/build_uapp.sh", "apps/abiprobe", str(app)], cwd=ROOT, check=True)
    fsapp = ROOT / "build/universal/FSPROBE.APP"
    subprocess.run(["bash", "tools/build_uapp.sh", "apps/fsprobe", str(fsapp)],
                   env={**os.environ, "UNIVERSAL_FS": "1"}, cwd=ROOT, check=True)
    menuapp = ROOT / "build/universal/MENUPRBE.APP"
    subprocess.run(["bash", "tools/build_uapp.sh", "apps/menuprobe", str(menuapp)],
                   env={**os.environ, "UNIVERSAL_MENU": "1", "APP_ICON": "apps/abiprobe/icon.asm"},
                   cwd=ROOT, check=True)
    calculator = ROOT / "build/universal/CALC.APP"
    subprocess.run(["bash", "tools/build_uapp.sh", "apps/ucalculator", str(calculator)],
                   env={**os.environ, "UNIVERSAL_WINDOW_KIND": "1", "UNIVERSAL_ACCESSORY": "1",
                        "UNIVERSAL_MENU": "1", "DATA_LOC": "0x7600"}, cwd=ROOT, check=True)
    clock = ROOT / "build/universal/CLOCK.APP"
    subprocess.run(["bash", "tools/build_uapp.sh", "apps/uclock", str(clock)],
                   env={**os.environ, "UNIVERSAL_TASK": "1", "UNIVERSAL_WINDOW_KIND": "1",
                        "UNIVERSAL_ACCESSORY": "1", "UNIVERSAL_MENU": "1", "DATA_LOC": "0x7300"},
                   cwd=ROOT, check=True)
    media = ROOT / "QA/Diagnostics/CPC-runtime"
    card = media / "CARD"
    card.mkdir(parents=True, exist_ok=True)
    boot = bytearray(headed((work / "BOOT.RAW").read_bytes(), 0x8000))
    boot[1:12] = b"BOOT    BIN"
    boot[67:69] = sum(boot[:67]).to_bytes(2, "little")
    files = {"BOOT.BIN": bytes(boot), "CORE.BIN": (work / "CORE.RAW").read_bytes(),
             "BOOT.BAS": b'10 MEMORY &7FFF\r\n20 LOAD"BOOT.BIN",&8000\r\n30 CALL &8000\r\n',
             "FSCTX.BIN": (work / "FSCTX.BIN").read_bytes(),
             "GBENCH/ROOTUI.BIN": (work / "ROOTBAR.BIN").read_bytes(),
             "GBENCH/GBCFG.MOD": (work / "GBCFG.MOD").read_bytes(),
             "GBENCH/GBUI.MOD": (work / "GBUI.MOD").read_bytes(),
             "GBENCH/GBPICK.MOD": (work / "GBPICK.MOD").read_bytes(),
             "GBENCH/DEFAULT.FNT": (work / "DEFAULT.FNT").read_bytes(),
             "GBENCH/DEFAULT.IST": (work / "DEFAULT.IST").read_bytes(),
             "GBENCH/REFINED.IST": (work / "REFINED.IST").read_bytes(),
             "GBENCH/DEFAULT.SPR": (work / "DEFAULT.SPR").read_bytes(),
             "GBENCH/GBTITLE.MOD": (work / "GBTITLE.MOD").read_bytes(),
             "GEOBENCH.CFG": b'ICONS=REFINED\r\nFONT=DEFAULT\r\nCURSOR=DEFAULT\r\nBACKDROP=SOLID\r\nTITLEBAR=ORIGINAL\r\nGADGETS=ORIGINAL\r\nINKS=1,26,0,6,1\r\n',
             "GBENCH/ABIPROBE.APP": app.read_bytes(),
             "GBENCH/FSPROBE.APP": fsapp.read_bytes(),
             "GBENCH/MENUPRBE.APP": menuapp.read_bytes(),
             "GBENCH/CALC.APP": calculator.read_bytes(),
             "GBENCH/CLOCK.APP": clock.read_bytes(),
             "UFSTEST/SOURCE.BIN": bytes((i*13+7)&255 for i in range(1025)),
             "UFSTEST/SUB/SMALL.TXT": b"OK!",
             "PICKTEST/NOTES.TXT": b"Picker notes\r\n",
             "PICKTEST/IGNORE.BIN": b"not a text file",
             "PICKTEST/INNER/HELLO.TXT": b"Picked from M4!\n"}
    for tile in (ROOT/'assets/backdrops').glob('*.BDP'):
        files['GBENCH/'+tile.name.upper()] = tile.read_bytes()
    for folder,ext in (('titlebars','TBR'),('gadgets','GDT')):
        for path in (ROOT/'assets'/folder).glob('*.'+ext):
            raw=path.read_bytes()
            if len(raw) not in ((56,106) if ext=='TBR' else (50,)):
                raise AssertionError('invalid chrome asset '+str(path))
            files['GBENCH/'+path.name.upper()]=raw
    directories=("GBENCH", "UFSTEST", "UFSTEST/SUB", "PICKTEST", "PICKTEST/INNER", "PICKTEST/EMPTY")
    for name in directories:
        (card/name).mkdir(parents=True,exist_ok=True)
    for name, payload in files.items():
        path = card / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)
    image = media / "RUNTIME.IMG"
    fd, temporary = tempfile.mkstemp(prefix="runtime-", suffix=".img", dir=media)
    try:
        with os.fdopen(fd, "wb") as out: out.truncate(32 * 1024 * 1024)
        subprocess.run(["sfdisk", "-q", temporary],
                       input="label: dos\nlabel-id: 0x4350434c\nstart=32, type=06\n",
                       text=True, check=True, stdout=subprocess.DEVNULL)
        subprocess.run(["mkfs.fat", "--invariant", "-F16", "--offset", "32",
                        "-n", "CPCRUNTIME", temporary], check=True)
        volume = temporary + "@@16384"
        subprocess.run(["mmd", "-i", volume, *["::/"+name for name in directories]], check=True)
        for name in files:
            subprocess.run(["mcopy", "-i", volume, str(card / name), "::/" + name], check=True)
        Path(temporary).replace(image)
    finally:
        Path(temporary).unlink(missing_ok=True)
    sections = {}
    for name, begin, end, limit in (
        ("kernel", "cpc_kernel_begin", "cpc_kernel_used_end", "cpc_kernel_end"),
        ("support", "cpc_support_begin", "cpc_support_used_end", "cpc_support_end"),
        ("hardware", "cpc_hardware_begin", "cpc_hardware_used_end", "cpc_hardware_end"),
        ("scheduler", "cpc_scheduler_begin", "cpc_scheduler_end", "cpc_sched_end")):
        sections[name] = dict(base=sym[begin], used=sym[end]-sym[begin], budget=sym[limit]-sym[begin])
    sections["fsctx"] = dict(base=0x4400, used=len(files["FSCTX.BIN"]), budget=sym['cpc_fs_module_limit']-0x4400)
    sections['title'] = dict(base=sym['data_title'],page=sym['cpc_data_page'],
                            used=symbols(work/'title.sym')['cpc_title_module_used_end']-sym['data_title'],
                            loaded=sym['cpc_title_module_size'],budget=sym['cpc_title_limit']-sym['data_title'])
    sections["icons"] = dict(base=sym['data_icons'],used=len(files['GBENCH/REFINED.IST']),
                            budget=sym['cpc_icon_limit']-sym['data_icons'],page=sym['cpc_data_page'])
    sections["cursor"] = dict(base=sym['cursor_phases'],used=512,budget=512,
                             save_under=sym['pointer_background'],save_under_bytes=64)
    sections["bar"] = json.loads((work / "bar_layout.json").read_text())
    sections.update(json.loads((work / "native_layout.json").read_text()))
    manifest = dict(work=str(work), image=str(image), regions=memory_regions(sym), sections=sections,
                    native_identity=json.loads((work/'native_identity.json').read_text()),
                    files={name: hashlib.sha256(data).hexdigest() for name, data in files.items()},
                    status="experimental universal launcher; not Desktop/distribution")
    (media / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    # Explicit private config: manual testing never edits the user's normal
    # machine setup or mounts their existing M4/Albireo card.
    (media / "1984.conf").write_text(
        '[machine]\nmodel=6128\nmemory=512\n[hardware]\nmx4=true\nm4=true\n'
        f'm4_path=\nm4_image={image}\nalbireo=false\nsymbiface_ide=false\n')
    print(f"Built {image}: {json.dumps(sections)}", flush=True)
    return media


if __name__ == "__main__": build()
