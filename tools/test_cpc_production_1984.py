#!/usr/bin/env python3
"""Run the production-address CPC adapter gate from a private M4 image."""
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

from build_cpc_production import ROOT, VARIANTS, build, symbols
from test_cpc_foundation_1984 import snapshot
from cpc_production_drawing import verify_drawing
from cpc_production_windows import verify_windows
from cpc_production_lifetime import verify_lifetime
from cpc_production_registration import verify_registration
from cpc_production_services import verify_services


def verify(data: bytes, sym: dict[str, int], work: Path) -> dict:
    header, ram = snapshot(data)
    def byte(name): return ram[sym[name]]
    def word(name): return int.from_bytes(ram[sym[name]:sym[name]+2], "little")
    if len(ram) != 512*1024:
        raise AssertionError("requires exact 512-KiB qualification fixture")
    if ram[sym["cpc_result"]:sym["cpc_result"]+6] != b"CPR3D\x01":
        raise AssertionError("production-address core did not boot")
    if (byte("cpc_phase"), byte("cpc_failure")) != (0xA5, 0):
        raise AssertionError(f"phase={byte('cpc_phase'):02X} failure={byte('cpc_failure')}")
    if word("cpc_root_turns") != 64 or word("cpc_io_checks") != 64:
        raise AssertionError("missing root/worker/M4 rounds")
    if byte("cpc_key_observed") & 2:
        raise AssertionError("Right key was not read through the keyboard")
    if word("cpc_irq_count") < 64*6 or byte("sched_fault"):
        raise AssertionError("missing timer preemption or scheduler fault")
    if word("cpc_hw_ticks") != word("cpc_irq_count"):
        raise AssertionError("IRQ/tick accounting mismatch")
    if (word("cpc_hw_seconds"), word("cpc_hw_divider")) != (word("cpc_hw_ticks")//300, 300-word("cpc_hw_ticks")%300):
        raise AssertionError("software time divider mismatch")
    if (byte("wm_nwin"), byte("wm_focus"), byte("sched_current"), byte("sched_runnable"), byte("sched_lock")) != (2, 1, 0, 2, 1):
        raise AssertionError("shared context/fixture window state differs")
    if (byte("cpc_wm_visibility"), ram[sym["cpc_wm_visibility"]+1], ram[sym["cpc_task_visibility"]+1]) != (1, 3, 3):
        raise AssertionError("shared visibility classification differs")
    if any(byte(name) for name in ("io_busy", "io_offline", "io_fd", "io_status", "sched_reserved")):
        raise AssertionError("unfinished M4/IRQ transaction")
    expected_commands = 1+4*((len((work / "CORE.RAW").read_bytes())+127)//128)+64*4
    if word("command_count") != expected_commands:
        raise AssertionError("M4 command count differs")
    if (byte("bank_cur"), header[0x41], header[0x40]) != (0xC0, 0, 0x0D):
        raise AssertionError("bank/ROM/mode not restored")
    if header[0x1B:0x1D] != b"\0\0" or header[0x25] != 1:
        raise AssertionError("final IFF/IM changed")
    top = sym["cpc_main_top"]
    if word("cpc_final_sp") != top or int.from_bytes(header[0x21:0x23], "little") != top:
        raise AssertionError("unbalanced root stack")
    used = {}
    for stem in ("main", "irq", "tmp"):
        start, end = sym[f"cpc_{stem}_stack"], sym[f"cpc_{stem}_top"]
        if ram[start-16:start] != b"\xD7"*16 or ram[end:end+16] != b"\xD7"*16:
            raise AssertionError(f"{stem} stack guard damaged")
        used[stem] = end-start-next((i for i,b in enumerate(ram[start:end]) if b != 0xA6), end-start)
        if not 0 < used[stem] < end-start:
            raise AssertionError(f"{stem} stack measurement invalid")
    for file, base in (("SCHED.RAW", "cpc_sched_base"), ("HARDWARE.RAW", "cpc_hardware_base"),
                       ("CORE.RAW", "cpc_kernel_base"), ("LOADER.RAW", "cpc_loader_base")):
        code = (work / file).read_bytes()
        if ram[sym[base]:sym[base]+len(code)] != code:
            raise AssertionError(f"{file} code changed")
    drawing = "cpc_drawing_begin" in sym
    services = "cpc_services_probe" in sym
    drawing_result = (verify_services(ram, sym, work) if services else
                      verify_registration(ram, sym, work) if "cpc_registration_probe" in sym else
                      verify_lifetime(ram, sym, work) if "cpc_lifetime_probe" in sym else
                      verify_windows(ram, sym, work) if "cpc_window_probe" in sym else
                      verify_drawing(ram, sym, work) if drawing else {})
    pixels = ram[0xC000:0x10000]
    if not drawing and pixels != bytes((a >> 8) ^ (a & 255) for a in range(0xC000, 0x10000)):
        raise AssertionError("non-drawing adapter damaged framebuffer or raster gaps")
    if ram[0x4340:0x4380] != bytes(range(64, 0, -1)):
        raise AssertionError("M4 returned bytes differ")
    # C4 is physical expansion page zero, with its code and saved context.
    worker = (work / "CORE.RAW").read_bytes()[sym["worker_code"]-0x8000:sym["worker_code_end"]-0x8000]
    if ram[0x10000:0x10000+len(worker)] != worker:
        raise AssertionError("mapped worker code differs")
    sizes = (ram[0x7F00], ram[0x13F00])
    if (any(n % 2 or not 24 <= n <= 64 for n in sizes) if services else sizes != (24, 26)):
        raise AssertionError("missing/invalid yield and IRQ snapshots")
    return {**drawing_result, "root_turns": word("cpc_root_turns"), "io_checks": word("cpc_io_checks"),
            "irq_count": word("cpc_irq_count"), "seconds": word("cpc_hw_seconds"),
            "stack_bytes": used, "scheduler_stack_max": byte("sched_stack_max"),
            "worker_counter": word("cpc_worker_counter"), "commands": word("command_count"),
            "framebuffer_sha256": hashlib.sha256(pixels).hexdigest()}


def run(variant="normal", emulator=ROOT.parent / "1984/1984", memory=512) -> Path:
    media = build(variant)
    manifest = json.loads((media / "manifest.json").read_text())
    work = Path(manifest["work"])
    sym = symbols(work / "adapters.sym")
    artifacts = Path(tempfile.mkdtemp(prefix="geobench-cpc-production-"))
    image = artifacts / "ADAPTERS.IMG"
    image.write_bytes(Path(manifest["image"]).read_bytes())
    config = artifacts / "1984.conf"
    config.write_text(f"[machine]\nmodel=6128\nmemory={memory}\n\n[hardware]\nmx4=true\nm4=true\n"
                      f"m4_path=\nm4_image={image}\nalbireo=false\nsymbiface_ide=false\n\n[advanced]\ndebug=true\n")
    pilot = artifacts / "pilot"
    command = [str(emulator), f"--config={config}", "--6128", f"--memory={memory}", "--autostart=BOOT",
               f"--pilot={pilot}", "--pilot-replies-stderr", "--exit-after=12000"]
    process = subprocess.Popen(command, cwd=ROOT, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                               stderr=subprocess.PIPE, text=True, bufsize=1,
                               env={**os.environ, "SDL_VIDEODRIVER": "dummy", "SDL_AUDIODRIVER": "dummy"})
    lines = queue.Queue()
    def pump():
        with (artifacts / "1984.log").open("w") as log:
            for line in process.stderr:
                log.write(line)
                log.flush()
                lines.put(line.rstrip())
        lines.put(None)
    reader = threading.Thread(target=pump, daemon=True)
    reader.start()
    def receive(pattern, timeout=45):
        deadline = time.monotonic()+timeout
        while time.monotonic() < deadline:
            try: line = lines.get(timeout=0.2)
            except queue.Empty: continue
            if line is None: raise RuntimeError(f"1984 exited; see {artifacts}")
            if pattern in line: return line
        raise TimeoutError(f"{pattern}; see {artifacts}")
    def send(cmd):
        fd = os.open(pilot, os.O_WRONLY | os.O_NOCTTY)
        try: os.write(fd, (cmd+"\n").encode())
        finally: os.close(fd)
        reply = receive("1984: pilot reply: ").split("1984: pilot reply: ", 1)[1]
        if not reply.startswith("ok "): raise RuntimeError(f"{cmd}: {reply}")
    print(f"Running production-address adapters ({variant}), M4; artifacts: {artifacts}", flush=True)
    started = time.monotonic()
    try:
        receive("pilot PTY:", 15)
        key_sent = False
        for attempt in range(30):
            send("wait frames 100 200")
            send(f"snapshot-save {artifacts / 'result.sna'}")
            data = (artifacts / "result.sna").read_bytes()
            _, ram = snapshot(data)
            phase = ram[sym["cpc_phase"]]
            if ram[sym["cpc_result"]:sym["cpc_result"]+6] != b"CPR3D\x01":
                if ram[sym["cpc_failure"]] == 0xE1: raise AssertionError("M4 core bootstrap failed")
                continue
            if phase == 2 and not key_sent:
                send("key-down RIGHT")
                key_sent = True
            elif phase in (0xA5, 0xFF): break
        else: raise AssertionError(f"probe did not finish; see {artifacts}")
        if key_sent: send("key-up RIGHT")
        if memory == 128:
            if (ram[sym["cpc_phase"]], ram[sym["cpc_failure"]]) != (0xFF, 8):
                raise AssertionError("undersized memory not rejected by CPC admission")
            result = {"expected_failure": "128-KiB memory rejected"}
        elif variant in ("normal", "full-slot", "drawing", "windows", "lifetime", "registration", "services"):
            result = verify(data, sym, work)
            send("wait frames 150 200")
            send(f"snapshot-save {artifacts / 'stable.sna'}")
            stable = (artifacts / "stable.sna").read_bytes()
            verify(stable, sym, work)
            if snapshot(stable)[1] != ram: raise AssertionError("RAM changed after completion")
        else:
            try:
                if variant=="registration-bad-owner":
                    # Wrong binding can also make later cleanup abort. Inspect
                    # the first actual registration trace, not a generic halt.
                    verify_registration(ram,sym,work,checkpoints=2)
                else:
                    verify(data, sym, work)
            except AssertionError as error:
                expected = {"bad-guard": "main stack guard damaged", "bad-restore": "failure=6",
                            "drawing-bad-clip": "drawing checkpoint clipped-line",
                            "drawing-bad-copy": "drawing checkpoint text-under-pointer",
                            "windows-bad-clip": "window checkpoint initial",
                            "windows-bad-pointer": "window checkpoint initial",
                            "lifetime-bad-purge": "lifetime last-window: message purge",
                            "lifetime-bad-fsctx": "lifetime last-window: FS context",
                            "registration-bad-kind": "registration titleless: furniture/content pixels",
                            "registration-bad-owner": "registration legacy: window owner binding",
                            "services-bad-delivery": "services reply: delivery",
                            "services-bad-visible": "services component-hidden: "}[variant]
                if expected not in str(error): raise
                result = {"expected_failure": str(error)}
            else: raise AssertionError("corrupt adapter unexpectedly passed")
        send(f"crop {artifacts / 'result.ppm'} 0 0 768 576 1")
        result.update(variant=variant, memory_kib=memory, elapsed_host_seconds=round(time.monotonic()-started, 2),
                      emulator_sha256=hashlib.sha256(emulator.read_bytes()).hexdigest(),
                      sections=manifest["sections"], image_sha256=manifest["image_sha256"])
        (artifacts / "result.json").write_text(json.dumps(result, indent=2)+"\n")
        print("PASS "+json.dumps(result, sort_keys=True), flush=True)
        return artifacts
    finally:
        process.terminate()
        try: process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        reader.join(timeout=5)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--variant", choices=VARIANTS, default="normal")
    parser.add_argument("--emulator", type=Path, default=ROOT.parent / "1984/1984")
    parser.add_argument("--memory", type=int, choices=(128, 512), default=512)
    args = parser.parse_args()
    if args.variant != "normal" and args.memory != 512:
        parser.error("test one injected fault at a time")
    run(args.variant, args.emulator.resolve(), args.memory)
