#!/usr/bin/env python3
"""Build the #77 production-address adapter gate, not a CPC distribution."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from build_cpc_foundation import headed
from cpc_production_drawing import DRAWING_VARIANTS, emit_vectors
from cpc_production_windows import WINDOW_VARIANTS, emit_vectors as emit_windows
from cpc_production_lifetime import LIFETIME_VARIANTS, emit_vectors as emit_lifetime
from cpc_production_registration import REGISTRATION_VARIANTS, emit_vectors as emit_registration
from cpc_production_services import SERVICE_VARIANTS, compile_timer
from cpc_production_routing import ROUTING_VARIANTS
from cpc_production_loading import LOADING_VARIANTS, emit_vectors as emit_loading, packages
from cpc_production_fsctx import FSCTX_VARIANTS, compile_module, emit_vectors as emit_fsctx, files as fsctx_files
from cpc_fsdir_protocol import emit_vectors as emit_fsdir, files as fsdir_files
from cpc_fsdir_cases import DIRECTORY_VARIANTS, files as directory_files
from cpc_fswrite_cases import WRITE_VARIANTS, space as write_space
import genfont

ROOT = Path(__file__).resolve().parents[1]
VARIANTS = {"normal": None, "full-slot": "CPC_PAD_KERNEL",
            "bad-guard": "CPC_FAULT_GUARD", "bad-restore": "CPC_FAULT_RESTORE",
            **DRAWING_VARIANTS, **WINDOW_VARIANTS, **LIFETIME_VARIANTS, **REGISTRATION_VARIANTS,
            **SERVICE_VARIANTS, **ROUTING_VARIANTS, **LOADING_VARIANTS, **FSCTX_VARIANTS}


def symbols(path: Path) -> dict[str, int]:
    return {m[1].lower(): int(m[2], 16)
            for m in re.finditer(r"(?m)^(\w+) #([0-9A-Fa-f]+)\b", path.read_text())}


def memory_regions(sym: dict[str, int]) -> list[dict]:
    """Require an explicit owner/reservation for every CPU address, no overlays."""
    result = [{"name": "vectors", "base": 0, "end": 0x100}]
    for name in ("loader", "support", "native_state", "adapter_state", "arch_state", "sched",
                 "sysinfo", "future_state", "draw_staging"):
        result.append(dict(name=name, base=sym[f"cpc_{name}_base"], end=sym[f"cpc_{name}_end"]))
    result.append(dict(name="stacks_and_guards", base=sym["cpc_main_stack"]-16, end=sym["cpc_stacks_end"]))
    for name in ("hardware", "clipboard", "app", "kernel", "screen"):
        result.append(dict(name=name, base=sym[f"cpc_{name}_base"], end=sym[f"cpc_{name}_end"]))
    cursor = 0
    for region in result:
        if not cursor == region["base"] < region["end"] <= 0x10000:
            raise ValueError(f"gap/overlap/invalid production allocation: {region}")
        cursor = region["end"]
    if cursor != 0x10000:
        raise ValueError("incomplete CPU address-space ownership")
    for region in result:
        if region["name"] not in ("app", "screen"):
            if not (region["end"] <= 0x4000 or 0x8000 <= region["base"] < region["end"] <= 0xC000):
                raise ValueError("fixed allocation in app aperture/framebuffer")
    return result


def assemble(work: Path, variant="normal", overrides=()) -> dict[str, int]:
    work.mkdir(parents=True, exist_ok=True)
    routing = variant in ROUTING_VARIANTS
    services = variant in SERVICE_VARIANTS or routing
    fsctx = variant in FSCTX_VARIANTS
    fsdir = variant == "fsctx-protocol"
    writable = variant in WRITE_VARIANTS
    directory = variant in DIRECTORY_VARIANTS or writable
    loading = variant in LOADING_VARIANTS or fsctx
    registration = variant in REGISTRATION_VARIANTS or services or loading
    lifetime = variant in LIFETIME_VARIANTS or registration
    windows = variant in WINDOW_VARIANTS or lifetime
    drawing = variant in DRAWING_VARIANTS or windows
    if drawing:
        emit_vectors(work / "drawing_vectors.inc")
        genfont.main(["genfont", str(work / "DEFAULT.FNT")])
    if windows:
        emit_windows(work / "window_vectors.inc")
    if variant in LIFETIME_VARIANTS:
        emit_lifetime(work / "lifetime_vectors.inc")
    if variant in REGISTRATION_VARIANTS:
        emit_registration(work / "registration_vectors.inc")
    if fsctx:
        emit_fsctx(work / "fsctx_vectors.inc", directory, writable)
        (work / "fsctx_size.inc").write_text("CPC_FS_MODULE_BYTES equ 1\n")
        if fsdir:
            emit_fsdir(work / "fsdir_vectors.inc")
    elif loading:
        emit_loading(work / "loading_vectors.inc")
    if services:
        (work / "TIMER.BIN").write_bytes(bytes(116))  # symbol pass only; never published to media
    cmd = [os.environ.get("RASM", "rasm"), str(ROOT / "kernel/cpc_adapter_image.asm"),
           "-s", "-sq", "-o", "adapters", f"-I{work}", *overrides]
    if drawing:
        cmd += ["-DCPC_DRAWING=1"]
    if windows:
        cmd += ["-DCPC_WM=1"]
    if lifetime:
        cmd += ["-DCPC_LIFETIME=1"]
    if registration:
        cmd += ["-DCPC_REGISTRATION=1"]
    if services:
        cmd += ["-DCPC_SERVICES=1"]
    if routing:
        cmd += ["-DCPC_ROUTING=1"]
    if loading:
        cmd += ["-DCPC_LOADING=1"]
    if fsctx:
        cmd += ["-DCPC_FSCTX=1"]
    if fsdir:
        cmd += ["-DCPC_FSDIR_PROTOCOL=1"]
    if directory:
        cmd += ["-DCPC_FS_DIRECTORY=1"]
    if writable:
        cmd += ["-DCPC_FS_WRITE=1"]
    if VARIANTS[variant]:
        cmd += [f"-D{VARIANTS[variant]}=1"]
    subprocess.run(cmd, cwd=work, check=True)
    sym = symbols(work / "adapters.sym")
    if fsctx:
        compile_module(work,sym,ROOT,directory,variant=="fsctx-directory-bad-meta",writable,variant=="fsctx-write-bad-append")
        subprocess.run(cmd,cwd=work,check=True)
        final=symbols(work / "adapters.sym")
        if {k:v for k,v in final.items() if k!="cpc_fs_module_bytes"}!={k:v for k,v in sym.items() if k!="cpc_fs_module_bytes"}:
            raise AssertionError("FS module compile changed resident addresses")
        sym=final
    elif loading:
        for name,data in packages(sym,ROOT).items():
            (work/name).write_bytes(data)
    if services:
        compile_timer(work,sym,ROOT)
        subprocess.run(cmd,cwd=work,check=True)
        if symbols(work / "adapters.sym")!=sym:
            raise AssertionError("timer payload changed fixed link addresses")
    memory_regions(sym)
    names = ("foundation_bank_set", "storage_gate", "storage_ga_set", "storage_rom_set",
             "storage_command", "storage_send")
    (work / "boot_symbols.inc").write_text("\n".join(f"{name} equ {sym[name]}" for name in names)+"\n")
    core = (work / "CORE.RAW").read_bytes()
    for source, output in (("cpc_m4_loader.asm", "loader"), ("cpc_m4_boot.asm", "boot")):
        subprocess.run([os.environ.get("RASM", "rasm"), str(ROOT / "kernel" / source),
                        "-s", "-sq", "-o", output, f"-I{work}", f"-DCPC_LOAD_BYTES={len(core)}",
                        *(["-DCPC_DRAWING=1"] if drawing else [])],
                       cwd=work, check=True)
    return sym


def build(variant="normal") -> Path:
    required = (os.environ.get("RASM", "rasm"), "sfdisk", "mkfs.fat", "mcopy", "mmd")
    if variant in DIRECTORY_VARIANTS:
        required += ("mattrib",)
    if variant in WRITE_VARIANTS:
        required += ("mtype",)
    for tool in required:
        if not shutil.which(tool):
            raise SystemExit(f"missing {tool}; use distrobox my-distrobox")
    work = ROOT / "build/cpc-production" / variant
    sym = assemble(work, variant)
    media = ROOT / "QA/Diagnostics/CPC-production" / variant
    card = media / "CARD"
    card.mkdir(parents=True, exist_ok=True)
    boot = bytearray(headed((work / "BOOT.RAW").read_bytes(), 0x8000))
    boot[1:12] = b"BOOT    BIN"
    boot[67:69] = sum(boot[:67]).to_bytes(2, "little")
    files = {"BOOT.BIN": boot, "CORE.BIN": (work / "CORE.RAW").read_bytes(),
             "DATA.BIN": bytes(range(64, 0, -1)),
             "BOOT.BAS": (ROOT / "debug/cpc_production/BOOT.BAS").read_text().replace("\n", "\r\n").encode()}
    if variant in LOADING_VARIANTS:
        files.update({"GBENCH/"+name:data for name,data in packages(sym,ROOT).items()})
    if variant in FSCTX_VARIANTS:
        files["FSCTX.BIN"]=(work/"FSCTX.BIN").read_bytes()
        files.update(fsctx_files())
        if variant == "fsctx-protocol":
            files.update(fsdir_files())
            (card / "CATALOG/EIGHTCHR").mkdir(parents=True, exist_ok=True)
        if variant in DIRECTORY_VARIANTS:
            files.update(directory_files())
            (card / "CATALOG/EIGHTCHR").mkdir(parents=True, exist_ok=True)
    for name, data in files.items():
        (card / name).parent.mkdir(parents=True, exist_ok=True)
        (card / name).write_bytes(data)
    image = media / "ADAPTERS.IMG"
    fd, tmp = tempfile.mkstemp(prefix="adapters-", suffix=".img", dir=media)
    try:
        with os.fdopen(fd, "wb") as out:
            out.truncate(32 * 1024 * 1024)
        subprocess.run(["sfdisk", "-q", tmp], input="label: dos\nlabel-id: 0x43504344\nstart=32, type=06\n",
                       text=True, check=True, stdout=subprocess.DEVNULL)
        subprocess.run(["mkfs.fat", "--invariant", "-F16", "--offset", "32", "-n", "CPCADAPT", tmp], check=True)
        subprocess.run(["mcopy", "-i", tmp+"@@16384", *[str(card / name) for name in files if "/" not in name], "::/"],
                       env={**os.environ, "MTOOLS_SKIP_CHECK": "1"}, check=True)
        if variant in LOADING_VARIANTS:
            subprocess.run(["mmd", "-i", tmp+"@@16384", "::/GBENCH"], check=True)
            subprocess.run(["mcopy", "-i", tmp+"@@16384", *[str(card/name) for name in files if "/" in name], "::/GBENCH/"], check=True)
        if variant in FSCTX_VARIANTS:
            for directory in ("DOCS","DOCS/SUB","ALT"):
                subprocess.run(["mmd","-i",tmp+"@@16384","::/"+directory],check=True)
            for name in fsctx_files():
                subprocess.run(["mcopy","-i",tmp+"@@16384",str(card/name),"::/"+name],check=True)
            if variant == "fsctx-protocol" or variant in DIRECTORY_VARIANTS:
                for directory in ("CATALOG", "CATALOG/EIGHTCHR"):
                    subprocess.run(["mmd", "-i", tmp+"@@16384", "::/"+directory], check=True)
                for name in (directory_files() if variant in DIRECTORY_VARIANTS else fsdir_files()):
                    subprocess.run(["mcopy", "-i", tmp+"@@16384", str(card/name), "::/"+name], check=True)
                if variant in DIRECTORY_VARIANTS:
                    subprocess.run(["mattrib", "-i", tmp+"@@16384", "+r", "+h", "+s", "::/CATALOG/BIG.BIN"], check=True)
        Path(tmp).replace(image)
    finally:
        Path(tmp).unlink(missing_ok=True)
    if variant in WRITE_VARIANTS:
        free_kib,cluster_kib=write_space(image)
        (work/'fswrite_geometry.json').write_text(json.dumps(dict(free_kib=free_kib,cluster_kib=cluster_kib))+'\n')
    sections = {name: {"base": sym[base], "used": sym[end]-sym[base], "budget": sym[limit]-sym[base]}
                for name, base, end, limit in (
                    ("scheduler", "cpc_scheduler_begin", "cpc_scheduler_end", "cpc_sched_end"),
                    ("hardware", "cpc_hardware_begin", "cpc_hardware_used_end", "cpc_hardware_end"),
                    ("probe_NOT_complete_kernel", "cpc_kernel_begin", "cpc_kernel_used_end", "cpc_kernel_end"))}
    if "cpc_drawing_begin" in sym:
        sections["support"] = dict(base=sym["cpc_support_base"], used=sym["cpc_support_used_end"]-sym["cpc_support_begin"],
                                   budget=sym["cpc_support_end"]-sym["cpc_support_base"])
        sections["drawing_code"] = dict(base=sym["cpc_drawing_begin"], used=sym["cpc_drawing_end"]-sym["cpc_drawing_begin"])
    if "cpc_window_policy_begin" in sym:
        sections["shared_window_policy"] = dict(base=sym["cpc_window_policy_begin"],
            used=sym["cpc_window_policy_end"]-sym["cpc_window_policy_begin"])
    if "cpc_lifetime_begin" in sym:
        sections["shared_lifetime_cleanup"] = dict(base=sym["cpc_lifetime_begin"],
            used=sym["cpc_lifetime_end"]-sym["cpc_lifetime_begin"])
    if "cpc_registration_begin" in sym:
        sections["shared_registration_chrome"] = dict(base=sym["cpc_registration_begin"],
            used=sym["cpc_registration_end"]-sym["cpc_registration_begin"])
    if "cpc_services_begin" in sym:
        sections["shared_services"] = dict(base=sym["cpc_services_begin"],
            used=sym["cpc_services_end"]-sym["cpc_services_begin"])
        sections["app_linked_timer"] = dict(base=sym["cpc_timer_collect"], used=116)
    if "cpc_routing_begin" in sym:
        sections["shared_input_routing"] = dict(base=sym["cpc_routing_begin"],
            used=sym["cpc_routing_end"]-sym["cpc_routing_begin"])
    if "cpc_loading_begin" in sym:
        sections["shared_launch_admission_and_m4_leaf"] = dict(base=sym["cpc_loading_begin"],
            used=sym["cpc_loading_end"]-sym["cpc_loading_begin"])
    if "cpc_fsctx_begin" in sym:
        sections["fsctx_resident_adapter"] = dict(base=sym["cpc_fsctx_begin"],
            used=sym["cpc_fsctx_end"]-sym["cpc_fsctx_begin"])
        sections["fsctx_data_page_module"] = dict(base=0x4400,used=len((work/"FSCTX.BIN").read_bytes()),budget=0x1C00)
    sources = [ROOT / "kernel/cpc_adapter_image.asm", ROOT / "kernel/cpc_scheduler.asm",
               ROOT / "kernel/cpc_context.inc", ROOT / "kernel/cpc_visibility.inc", ROOT / "kernel/cpc_m4_boot.asm", ROOT / "kernel/cpc_m4_loader.asm",
               *sorted((ROOT / "kernel/core").glob("*.asm")), *sorted((ROOT / "kernel/core").glob("*.inc")),
               *sorted((ROOT / "lib/cpc").glob("*")), *sorted((ROOT / "debug/cpc_production").glob("*")),
               ROOT / "tools/build_cpc_production.py", ROOT / "tools/test_cpc_production_1984.py",
               ROOT / "tools/build_cpc_foundation.py", ROOT / "tools/test_cpc_foundation_1984.py",
               ROOT / "tools/cpc_production_drawing.py", ROOT / "tools/genfont.py",
               ROOT / "kernel/cpc_support.asm", ROOT / "kernel/cpc_parameter_provider.inc",
               ROOT / "kernel/cpc_window_provider.inc", ROOT / "kernel/cpc_window_policy.asm",
               ROOT / "tools/cpc_production_windows.py", ROOT / "tools/cpc_production_lifetime.py",
               ROOT / "kernel/cpc_lifetime.asm", ROOT / "kernel/cpc_lifetime_provider.inc",
               ROOT / "kernel/cpc_registration.asm", ROOT / "kernel/cpc_registration_provider.inc",
               ROOT / "tools/cpc_production_registration.py", ROOT / "tools/cpc_production_services.py",
               ROOT / "kernel/cpc_services.asm", ROOT / "kernel/cpc_services_provider.inc",
               ROOT / "lib/gembench/core/timer_collect.inc", ROOT / "lib/gembench/core/timer_collect_contract.inc",
               ROOT / "tools/cpc_production_routing.py", ROOT / "kernel/cpc_routing.asm",
               ROOT / "kernel/cpc_routing_provider.inc", ROOT / "kernel/cpc_loading.asm",
               ROOT / "tools/cpc_production_loading.py", ROOT / "tools/embed_app_icon.py",
               ROOT / "apps/abiprobe/manifest.json", ROOT / "apps/abiprobe/icon.asm",
               ROOT / "tools/cpc_production_fsctx.py", ROOT / "kernel/cpc_fsctx.asm",
               ROOT / "kernel/kc/cpc_fsctx.h", ROOT / "kernel/kc/gbfsctx_cpc.c",
               ROOT / "kernel/core/fsctx_contract.h", ROOT / "kernel/core/fsctx_layout.h",
               ROOT / "tools/cpc_fsdir_protocol.py", ROOT / "lib/gb/crt0.s",
               ROOT / "tools/cpc_fsdir_cases.py", ROOT / "kernel/kc/cpc_fsdir.inc",
               ROOT / "tools/cpc_fswrite_cases.py", ROOT / "kernel/kc/cpc_fswrite.inc",
               ROOT / "tools/check_app_layout.py"]
    manifest = {"variant": variant, "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                "sections": sections, "memory_regions": memory_regions(sym), "image": str(image), "work": str(work),
                "image_sha256": hashlib.sha256(image.read_bytes()).hexdigest(),
                "files_sha256": {name: hashlib.sha256(data).hexdigest() for name, data in files.items()},
                "sources_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}}
    (media / "manifest.json").write_text(json.dumps(manifest, indent=2)+"\n")
    print(f"Built {image} (M4 adapter gate, no desktop)", flush=True)
    return media


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--variant", choices=VARIANTS, default="normal")
    build(parser.parse_args().variant)
