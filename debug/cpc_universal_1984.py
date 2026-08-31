#!/usr/bin/env python3
"""Drive the issue-54-A CPC bootstrap through 1984's pilot protocol."""

from __future__ import annotations

import os
from pathlib import Path
import queue
import re
import subprocess
import threading
import time


ROOT = Path(__file__).resolve().parents[1]
EMULATOR = (ROOT / ".." / "1984" / "1984").resolve()
DISK = ROOT / "QA" / "CPC" / "Floppies" / "GEOBENCH.DSK"
PILOT = Path("/tmp/geobench-cpc-1984-pilot")
ARTIFACTS = Path("/tmp/geobench-cpc-1984")


def pump(stream: object, lines: queue.Queue[str]) -> None:
    for line in iter(stream.readline, ""):  # type: ignore[attr-defined]
        lines.put(line.rstrip("\n"))


def main() -> int:
    if not EMULATOR.is_file() or not DISK.is_file():
        raise SystemExit("run make cpc and ensure ../1984/1984 exists")
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    PILOT.unlink(missing_ok=True)
    config = os.environ.get("CPC_1984_CONFIG", "/dev/null")
    command = [
        str(EMULATOR), f"--config={config}", "--6128", "--memory=512",
        f"--disk-a={DISK}", "--autostart=GB", f"--pilot={PILOT}",
        "--pilot-replies-stderr", "--exit-after=5200",
    ]
    process = subprocess.Popen(
        command, cwd=ROOT, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE, text=True, bufsize=1,
        env={**os.environ, "SDL_VIDEODRIVER": "dummy", "SDL_AUDIODRIVER": "dummy"},
    )
    lines: queue.Queue[str] = queue.Queue()
    threading.Thread(target=pump, args=(process.stderr, lines), daemon=True).start()

    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        try:
            line = lines.get(timeout=0.2)
        except queue.Empty:
            continue
        print(line)
        if "pilot PTY:" in line:
            break
    else:
        process.terminate()
        raise SystemExit("1984 did not publish its pilot PTY")

    def send(text: str, timeout: float = 180.0) -> str:
        fd = os.open(PILOT, os.O_WRONLY | os.O_NOCTTY)
        try:
            os.write(fd, (text + "\n").encode())
        finally:
            os.close(fd)
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            try:
                line = lines.get(timeout=0.2)
            except queue.Empty:
                continue
            print(line)
            match = re.search(r"1984: pilot reply: (.*)", line)
            if match:
                return match.group(1)
        raise TimeoutError(text)

    def snapshot_state(name: str) -> tuple[bytes, Path]:
        path = ARTIFACTS / f"{name}.sna"
        send(f"snapshot-save {path}")
        image = path.read_bytes()
        return image[0x100:0x10100], path

    def move_pointer_to(target_x: int, target_y: int) -> None:
        """Steer the digital joystick with snapshot feedback, avoiding timing guesses."""
        for step in range(40):
            ram, _ = snapshot_state(f"steer-{step:02d}")
            x, y = ram[0x1306], ram[0x1307]
            dx, dy = target_x - x, target_y - y
            if abs(dx) <= 1 and abs(dy) <= 1:
                return
            if abs(dx) > 1:
                angle = 0 if dx > 0 else 180
                distance = abs(dx)
            else:
                angle = 270 if dy > 0 else 90
                distance = abs(dy)
            send(f"hold {min(5, max(1, distance // 2))} 1 {angle}")
            send("wait frames 8 40")
        raise RuntimeError(f"could not steer pointer to {target_x},{target_y}")

    try:
        send("target joy")
        send("wait frames 2200 2600")
        send(f"crop {ARTIFACTS / 'desktop.ppm'} 0 0 768 576 1")
        send("hold 45 1 180")
        send("wait frames 50 100")
        send("hold 12 1 90")
        send("wait frames 17 80")
        send(f"crop {ARTIFACTS / 'disk-position.ppm'} 0 0 768 576 1")
        # Keep fire asserted long enough for the cooperative CPC loop to reach
        # its next poll even when a software repaint straddles several frames.
        send("hold-click 12 1")
        # CPC Mode-1 software painting can span several video frames.  Wait
        # for the first-click selection repaint to settle before issuing the
        # second edge, otherwise the emulator can faithfully inject it while
        # the app is still inside its drawing callback.
        send("wait quiet 8 300")
        # Auto-release and the final quiet frame can coincide.  Leave a short
        # neutral interval so k_poll records fire-up before the second press.
        send("wait frames 6 60")
        send(f"crop {ARTIFACTS / 'disk-click1.ppm'} 0 0 768 576 1")
        send("hold-click 12 1")
        send("wait frames 20 100")
        # A real floppy open includes motor spin-up and directory/data reads;
        # a static framebuffer during that interval is not application idle.
        send("wait frames 630 1200")
        send("wait quiet 8 300")
        send(f"crop {ARTIFACTS / 'disk-click2.ppm'} 0 0 768 576 1")
        # The File Manager opens over the Desktop pointer's x=0 position.
        # Allow the asynchronous pilot hold to complete before clicking.
        send("hold 20 1 0")
        send("wait frames 25 80")
        send(f"crop {ARTIFACTS / 'abiprobe-position.ppm'} 0 0 768 576 1")
        # The legacy File Manager enters a synchronous drag discriminator on
        # press. Keep fire down until its slower multi-window loop sees it,
        # then release explicitly so a stationary press becomes a selection.
        send("press 1")
        send("wait frames 60 120")
        send("release 1")
        send("wait frames 20 80")
        send(f"crop {ARTIFACTS / 'abiprobe-selected.ppm'} 0 0 768 576 1")
        send("press 1")
        send("wait frames 60 120")
        send("release 1")
        send("wait frames 420 900")
        send("wait quiet 8 300")
        probe_snapshot = ARTIFACTS / "abiprobe.sna"
        send(f"snapshot-save {probe_snapshot}")
        send(f"crop {ARTIFACTS / 'abiprobe.ppm'} 0 0 768 576 1")
        before = probe_snapshot.read_bytes()[0x100:0x10100]
        probe_slot = before[0x1351]
        probe_entry = 0x1352 + probe_slot * 25
        old_x = before[probe_entry + 1]
        old_y = before[probe_entry + 2]
        move_pointer_to(old_x + 10, old_y + 5)
        send("press 1")
        send("wait frames 12 80")
        # The first CPC drag loads its 209-byte service from the system disk.
        # Keep direction and fire asserted across that real floppy latency.
        send("move 1 0")
        send("wait frames 180 400")
        send("stop")
        send("release 1")
        send("wait frames 180 400")
        send("wait quiet 8 300")
        dragged, dragged_snapshot = snapshot_state("abiprobe-dragged")
        new_x = dragged[probe_entry + 1]
        if new_x <= old_x:
            raise RuntimeError(f"CPC universal drag did not move window: {old_x} -> {new_x}")
        send(f"crop {ARTIFACTS / 'abiprobe-dragged.ppm'} 0 0 768 576 1")
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
    # CPC low RAM is represented directly in the first 64K SNA bank after
    # the 256-byte header. Three live windows prove Desktop + File Manager +
    # the admitted compile-once ABIPROBE application.
    final_ram = dragged_snapshot.read_bytes()[0x100:0x10100]
    nwin = final_ram[0x1350]
    if nwin != 3:
        raise SystemExit(f"CPC ABI smoke failed: expected 3 windows, found {nwin}")
    sysinfo = final_ram[0x3C00:0x3C30]
    if (sysinfo[0], sysinfo[1], sysinfo[4], sysinfo[34], sysinfo[35],
            sysinfo[36], sysinfo[37]) != (48, 6, 2, 80, 200, 4, 4):
        raise SystemExit("CPC ABI smoke failed: invalid sysinfo v6 geometry")
    focus = final_ram[0x1351]
    if final_ram[0x3C9F + focus] == 0:
        raise SystemExit("CPC ABI smoke failed: focused window has no generation")
    print(f"1984 CPC ABI smoke: {nwin} windows; captures: {ARTIFACTS}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
