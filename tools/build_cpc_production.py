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
import genfont

ROOT = Path(__file__).resolve().parents[1]
VARIANTS = {"normal": None, "full-slot": "CPC_PAD_KERNEL",
            "bad-guard": "CPC_FAULT_GUARD", "bad-restore": "CPC_FAULT_RESTORE",
            **DRAWING_VARIANTS, **WINDOW_VARIANTS, **LIFETIME_VARIANTS, **REGISTRATION_VARIANTS,
            **SERVICE_VARIANTS}


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
    services = variant in SERVICE_VARIANTS
    registration = variant in REGISTRATION_VARIANTS or services
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
    if VARIANTS[variant]:
        cmd += [f"-D{VARIANTS[variant]}=1"]
    subprocess.run(cmd, cwd=work, check=True)
    sym = symbols(work / "adapters.sym")
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
    for tool in (os.environ.get("RASM", "rasm"), "sfdisk", "mkfs.fat", "mcopy"):
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
    for name, data in files.items():
        (card / name).write_bytes(data)
    image = media / "ADAPTERS.IMG"
    fd, tmp = tempfile.mkstemp(prefix="adapters-", suffix=".img", dir=media)
    try:
        with os.fdopen(fd, "wb") as out:
            out.truncate(32 * 1024 * 1024)
        subprocess.run(["sfdisk", "-q", tmp], input="label: dos\nlabel-id: 0x43504344\nstart=32, type=06\n",
                       text=True, check=True, stdout=subprocess.DEVNULL)
        subprocess.run(["mkfs.fat", "--invariant", "-F16", "--offset", "32", "-n", "CPCADAPT", tmp], check=True)
        subprocess.run(["mcopy", "-i", tmp+"@@16384", *[str(card / name) for name in files], "::/"],
                       env={**os.environ, "MTOOLS_SKIP_CHECK": "1"}, check=True)
        Path(tmp).replace(image)
    finally:
        Path(tmp).unlink(missing_ok=True)
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
               ROOT / "lib/gembench/core/timer_collect.inc", ROOT / "lib/gembench/core/timer_collect_contract.inc"]
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
