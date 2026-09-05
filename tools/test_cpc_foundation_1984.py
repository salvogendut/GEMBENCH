#!/usr/bin/env python3
"""Execute isolated CPC step-3A/3B probes through 1984's M4 and pilot paths."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import queue
import re
import subprocess
import tempfile
import threading
import time

from build_cpc_foundation import ROOT, VARIANTS, build
from cpc_graphics_fixture import GRAPHICS_VARIANTS, verify_graphics


def symbols(path: Path) -> dict[str, int]:
    return {match[1].lower(): int(match[2], 16)
            for match in re.finditer(r"(?m)^(\w+) #([0-9A-Fa-f]+)\b", path.read_text())}


def snapshot(data: bytes) -> tuple[bytes, bytes]:
    if len(data) < 256 or data[:8] != b"MV - SNA" or data[0x10] != 3:
        raise AssertionError("expected a 1984 v3 SNA")
    length = int.from_bytes(data[0x6B:0x6D], "little") * 1024
    if length == 0 or len(data) < 256 + length:
        raise AssertionError("expected complete flat physical RAM in snapshot")
    return data[:256], data[256:256 + length]


def verify(data: bytes, sym: dict[str, int], raw: bytes) -> dict[str, object]:
    header, ram = snapshot(data)
    def byte(name: str) -> int:
        return ram[sym[name]]
    def word(name: str) -> int:
        return int.from_bytes(ram[sym[name]:sym[name] + 2], "little")
    if ram[sym["magic"]:sym["magic"] + 6] != b"CPF3A\x01":
        raise AssertionError("probe did not boot / wrong result version")
    if byte("phase") != 0xA5 or byte("failure"):
        raise AssertionError(f"probe phase={byte('phase'):02X} failure={byte('failure')}")
    if len(ram) != 512 * 1024:
        raise AssertionError("positive fixture must be exactly 512 KiB")
    if byte("rounds_done") != 50 or word("page_checks") != 50 * 29:
        raise AssertionError("incomplete bank stress workload")
    if word("irq_count") != 50 * 29:
        raise AssertionError("expected one real IM1 interrupt per page visit")
    if ram[sym["irq_per_page"]:sym["irq_per_page"] + 29] != bytes([50]) * 29:
        raise AssertionError("interrupt coverage differs across mapped pages")
    if (byte("bank_shadow"), header[0x41], header[0x40]) != (0xC0, 0, 0x0D):
        raise AssertionError("bank or Mode-1/ROM mapping not restored")
    if header[0x1B:0x1D] != b"\0\0" or header[0x25] != 1:
        raise AssertionError("unexpected final IFF/interrupt mode")
    if word("final_sp") != sym["main_stack_top"]:
        raise AssertionError("unbalanced foreground stack")
    if int.from_bytes(header[0x21:0x23], "little") != sym["main_stack_top"]:
        raise AssertionError("snapshot stack does not match fixed resident stack")
    for stem in ("main", "irq"):
        for side in ("low", "high"):
            start = sym[f"{stem}_guard_{side}"]
            if ram[start:start + 16] != b"\xD7" * 16:
                raise AssertionError(f"{stem} {side} guard damaged")
        stack = ram[sym[f"{stem}_stack"]:sym[f"{stem}_stack_top"]]
        used = len(stack) - next((i for i, b in enumerate(stack) if b != 0xA6), len(stack))
        if used != word(f"{stem}_stack_used") or not 0 < used < len(stack):
            raise AssertionError(f"invalid {stem} stack measurement")
    expected_regs = raw[sym["expected_registers"] - 0x8000:
                        sym["expected_registers"] - 0x8000 + 20]
    if ram[sym["observed"]:sym["observed"] + 20] != expected_regs:
        raise AssertionError("IRQ register/flag context changed")
    if ram[0x8000:sym["code_end"]] != raw[:sym["code_end"] - 0x8000]:
        raise AssertionError("resident probe code changed")
    tags = [0xC0] + [0xC4 + group * 8 + block for group in range(7) for block in range(4)]
    for index, tag in enumerate(tags):
        base = 0x4000 if index == 0 else 0x10000 + (index - 1) * 0x4000
        expected = bytes(tag ^ (address >> 8) ^ (address & 255)
                         for address in range(0x4000, 0x8000))
        if ram[base:base + 0x4000] != expected:
            raise AssertionError(f"physical page {index} (tag {tag:02X}) corrupted or aliased")
    pixels = ram[0xC000:0x10000]
    if pixels != bytes((address >> 8) ^ (address & 255) for address in range(0xC000, 0x10000)):
        raise AssertionError("framebuffer modified by non-drawing operations")
    return {"rounds": byte("rounds_done"), "page_checks": word("page_checks"),
            "interrupts": word("irq_count"), "main_stack_bytes": word("main_stack_used"),
            "irq_stack_bytes": word("irq_stack_used"),
            "resident_code_bytes": sym["code_end"] - sym["probe_start"],
            "framebuffer_sha256": hashlib.sha256(pixels).hexdigest()}


def run(variant: str, memory: int, emulator: Path) -> None:
    media = build(variant)
    manifest = json.loads((media / "manifest.json").read_text())
    sym = symbols(Path(manifest["symbols"]))
    raw = (ROOT / "build/cpc-foundation" / variant / "FOUND.RAW").read_bytes()
    graphics = variant in GRAPHICS_VARIANTS
    signature = b"CPF3B\x01" if graphics else b"CPF3A\x01"
    def check(data):
        return verify_graphics(*snapshot(data), sym, raw) if graphics else verify(data, sym, raw)
    # Every launch uses a private PTY, log, snapshots and image copy. Never run
    # the emulator against someone's mounted release or parked CPC card.
    artifacts = Path(tempfile.mkdtemp(prefix="geobench-cpc-foundation-"))
    image = artifacts / "FOUNDATION.IMG"
    image.write_bytes(Path(manifest["image"]).read_bytes())
    config = artifacts / "1984.conf"
    config.write_text(Path(manifest["config"]).read_text().replace(manifest["image"], str(image)))
    pilot = artifacts / "pilot"
    command = [str(emulator), f"--config={config}", "--6128", f"--memory={memory}",
               "--autostart=BOOT", f"--pilot={pilot}", "--pilot-replies-stderr",
               "--exit-after=12000"]
    process = subprocess.Popen(command, cwd=ROOT, stdin=subprocess.DEVNULL,
                               stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                               text=True, bufsize=1, env={**os.environ,
                               "SDL_VIDEODRIVER": "dummy", "SDL_AUDIODRIVER": "dummy"})
    lines: queue.Queue[str | None] = queue.Queue()
    def pump() -> None:
        with (artifacts / "1984.log").open("w") as log:
            for line in process.stderr:
                log.write(line)
                log.flush()
                lines.put(line.rstrip())
        lines.put(None)
    reader = threading.Thread(target=pump, daemon=True)
    reader.start()
    def receive(pattern: str, timeout: float = 45) -> str:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                line = lines.get(timeout=min(0.2, max(0.01, deadline - time.monotonic())))
            except queue.Empty:
                continue
            if line is None:
                raise RuntimeError(f"1984 exited; see {artifacts / '1984.log'}")
            if pattern in line:
                return line
        raise TimeoutError(f"{pattern}; see {artifacts / '1984.log'}")
    def send(command: str) -> str:
        fd = os.open(pilot, os.O_WRONLY | os.O_NOCTTY)
        try:
            os.write(fd, (command + "\n").encode())
        finally:
            os.close(fd)
        reply = receive("1984: pilot reply: ").split("1984: pilot reply: ", 1)[1]
        if not reply.startswith("ok "):
            raise RuntimeError(f"pilot {command}: {reply}")
        return reply
    started = time.monotonic()
    print(f"Running {variant}, {memory} KiB; artifacts: {artifacts}", flush=True)
    try:
        receive("pilot PTY:", 15)
        for attempt in range(30):
            send("wait frames 150 200")
            path = artifacts / "result.sna"
            send(f"snapshot-save {path}")
            data = path.read_bytes()
            _, ram = snapshot(data)
            if ram[sym["magic"]:sym["magic"] + 6] != signature:
                continue
            if ram[sym["phase"]] in (0xA5, 0xFF):
                break
        else:
            raise AssertionError("probe did not finish within 4500 frames")
        if variant in ("normal", "graphics") and memory == 512:
            result = check(data)
            # Stable endpoint: no transient PASS before a reboot or later write.
            send("wait frames 150 200")
            send(f"snapshot-save {artifacts / 'stable.sna'}")
            stable = (artifacts / "stable.sna").read_bytes()
            check(stable)
            if snapshot(stable)[1] != ram:
                raise AssertionError("RAM changed after completion")
        elif graphics:
            expected = {"graphics-bad-clip": "framebuffer checkpoint left-top-clip",
                        "graphics-bad-cursor": "framebuffer checkpoint phase-1",
                        "graphics-bad-copy": "failure=8"}[variant]
            try:
                check(data)
            except AssertionError as error:
                if expected not in str(error):
                    raise
                result = {"expected_failure": str(error)}
            else:
                raise AssertionError("graphics corruption fixture passed unexpectedly")
        else:
            expected = {"bad-bank": 2, "bad-register": 3, "bad-stack": 7}.get(variant, 1)
            if (ram[sym["phase"]], ram[sym["failure"]]) != (0xFF, expected):
                raise AssertionError(f"negative fixture did not report failure {expected}")
            result = {"expected_failure": expected}
        send(f"crop {artifacts / 'result.ppm'} 0 0 768 576 1")
        result.update({"variant": variant, "memory_kib": memory,
                       "elapsed_host_seconds": round(time.monotonic() - started, 2),
                       "image_sha256": manifest["image_sha256"],
                       "raw_sha256": manifest["raw_sha256"],
                       "emulator_sha256": hashlib.sha256(emulator.read_bytes()).hexdigest()})
        (artifacts / "result.json").write_text(json.dumps(result, indent=2) + "\n")
        print("PASS " + json.dumps(result, sort_keys=True), flush=True)
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        reader.join(timeout=5)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--variant", choices=VARIANTS, default="normal")
    parser.add_argument("--memory", type=int, choices=(128, 512), default=512)
    parser.add_argument("--emulator", type=Path, default=ROOT.parent / "1984/1984")
    args = parser.parse_args()
    if args.variant != "normal" and args.memory != 512:
        parser.error("use one injected fault at a time")
    run(args.variant, args.memory, args.emulator.resolve())
