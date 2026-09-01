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
M4_CARD = ROOT / "QA" / "CPC" / "CARD"
M4_IMAGE = ROOT / "QA" / "CPC" / "GEOBENCH.IMG"
M4_CONFIG = ROOT / "debug" / "cpc_m4_1984.conf"
APP_TARGETS = {
    # Inside GBENCH the M4 directory view prepends the synthetic ".." cell.
    # The applications are sorted after it by type and 8.3 name.
    "ABIPROBE": (37, 51),
    "CALC": (52, 51),
    "CLOCK": (22, 95),
}
APP_KINDS = {
    "ABIPROBE": 0x07,  # legacy CPC chrome
    "CALC": 0x80 | 0x01 | 0x02 | 0x08,
    "CLOCK": 0x80 | 0x1F,
}


def pump(stream: object, lines: queue.Queue[str]) -> None:
    for line in iter(stream.readline, ""):  # type: ignore[attr-defined]
        lines.put(line.rstrip("\n"))


def main() -> int:
    if (not EMULATOR.is_file() or not (M4_CARD / "GB.BAS").is_file()
            or not M4_IMAGE.is_file()):
        raise SystemExit("run make cpc and ensure ../1984/1984 exists")
    app = os.environ.get("CPC_SMOKE_APP", "ABIPROBE").upper()
    if app not in APP_TARGETS:
        raise SystemExit(
            "CPC_SMOKE_APP must be one of " + ", ".join(APP_TARGETS)
        )
    route = os.environ.get("CPC_SMOKE_ROUTE", "FILEMGR").upper()
    if route not in ("FILEMGR", "DESK"):
        raise SystemExit("CPC_SMOKE_ROUTE must be FILEMGR or DESK")
    if route == "DESK" and app not in ("CLOCK", "CALC"):
        raise SystemExit("the Desk route supports CLOCK or CALC")
    suffix = f"{route.lower()}-{app.lower()}"
    artifacts = Path(f"/tmp/geobench-cpc-1984-{suffix}")
    artifacts.mkdir(parents=True, exist_ok=True)
    pilot = Path(f"/tmp/geobench-cpc-1984-{suffix}-pilot")
    pilot.unlink(missing_ok=True)
    config = os.environ.get("CPC_1984_CONFIG", str(M4_CONFIG))
    command = [
        str(EMULATOR), f"--config={config}", "--6128", "--memory=512",
        "--autostart=GB", f"--pilot={pilot}",
        "--pilot-replies-stderr", "--exit-after=12000",
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
        fd = os.open(pilot, os.O_WRONLY | os.O_NOCTTY)
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
        path = artifacts / f"{name}.sna"
        send(f"snapshot-save {path}")
        image = path.read_bytes()
        return image[0x100:0x10100], path

    def move_pointer_to(target_x: int, target_y: int) -> None:
        """Steer the digital joystick with snapshot feedback, avoiding timing guesses."""
        # A direct Desk reactivation deliberately crosses almost the complete
        # desktop after focusing an exposed corner.  Keep enough feedback
        # iterations for both axes on CPC's accelerated keyboard joystick.
        for step in range(160):
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
        send(f"crop {artifacts / 'desktop.ppm'} 0 0 768 576 1")
        if route == "DESK":
            def desk_activate() -> bytes:
                # Document-less Desktop places Desk at column 10. The popup
                # starts at line 8 with ten-pixel rows: Clock is row zero and
                # Calculator row one.
                move_pointer_to(12, 4)
                # Keep the edge asserted explicitly.  CPC software painting
                # can outlive 1984's short hold-click pulse, particularly on
                # the first top-bar repaint after boot.
                send("press 1")
                send("wait frames 60 120")
                send("release 1")
                send("wait frames 40 120")
                send(f"crop {artifacts / 'desk-menu.ppm'} 0 0 768 576 1")
                move_pointer_to(12, 14 if app == "CLOCK" else 24)
                send("press 1")
                send("wait frames 60 120")
                send("release 1")
                send("wait frames 500 900")
                send("wait quiet 8 300")
                state, _ = snapshot_state(f"desk-{app.lower()}")
                return state

            first = desk_activate()
            if first[0x1350] != 2:
                raise RuntimeError(
                    f"Desk {app} launch expected two windows, found {first[0x1350]}"
                )
            first_focus = first[0x1351]
            if first[0x3EB8 + first_focus] != APP_KINDS[app]:
                raise RuntimeError(f"Desk {app} launch published the wrong window kind")
            if first[0x1347]:
                raise RuntimeError("CPC scheduler faulted during Desk launch")
            # Focus an uncovered Desktop point, then select the same accessory
            # again. Exact endpoint activation must raise the existing window,
            # never allocate a duplicate application page/window.
            move_pointer_to(70, 100)
            send("hold-click 12 1")
            send("wait frames 80 180")
            second = desk_activate()
            if second[0x1350] != 2:
                raise RuntimeError(
                    f"Desk {app} activation duplicated the app: {second[0x1350]} windows"
                )
            if second[0x1351] != first_focus:
                raise RuntimeError(f"Desk {app} did not restore focus to its live endpoint")
            if second[0x1347]:
                raise RuntimeError("CPC scheduler faulted during exact Desk activation")
            send(f"crop {artifacts / f'desk-{app.lower()}-reactivated.ppm'} 0 0 768 576 1")
            print(
                f"1984 CPC Desk smoke: {app}, exact activation, 2 windows; "
                f"captures: {artifacts}"
            )
            return 0
        send("hold 45 1 180")
        send("wait frames 50 100")
        send("hold 12 1 90")
        send("wait frames 17 80")
        send(f"crop {artifacts / 'disk-position.ppm'} 0 0 768 576 1")
        # Keep fire asserted long enough for a software repaint to straddle
        # several CPC frames without losing the input edge.
        send("hold-click 12 1")
        # CPC Mode-1 software painting can span several video frames.  Wait
        # for the first-click selection repaint to settle before issuing the
        # second edge, otherwise the emulator can faithfully inject it while
        # the app is still inside its drawing callback.
        send("wait quiet 8 300")
        # Auto-release and the final quiet frame can coincide.  Leave a short
        # neutral interval so k_poll records fire-up before the second press.
        send("wait frames 6 60")
        send(f"crop {artifacts / 'disk-click1.ppm'} 0 0 768 576 1")
        send("hold-click 12 1")
        send("wait frames 20 100")
        # The M4 FAT-card backend has no floppy motor or seek latency.
        send("wait frames 120 300")
        send("wait quiet 8 300")
        send(f"crop {artifacts / 'disk-click2.ppm'} 0 0 768 576 1")
        # The M4 card root contains launchers and the shared GBENCH system
        # directory. Enter that directory before selecting an application;
        # unlike the compact floppy image, applications do not live at root.
        move_pointer_to(22, 51)
        send("wait frames 25 80")
        send("press 1")
        send("wait frames 60 120")
        send("release 1")
        send("wait frames 20 80")
        send("press 1")
        send("wait frames 60 120")
        send("release 1")
        send("wait frames 120 300")
        send("wait quiet 8 300")
        send(f"crop {artifacts / 'gbench-directory.ppm'} 0 0 768 576 1")
        # Select the requested first-row package using low-RAM pointer
        # feedback, rather than relying on host/emulator timing.
        target_x, target_y = APP_TARGETS[app]
        move_pointer_to(target_x, target_y)
        send("wait frames 25 80")
        send(f"crop {artifacts / f'{app.lower()}-position.ppm'} 0 0 768 576 1")
        # The legacy File Manager enters a synchronous drag discriminator on
        # press. Keep fire down until its slower multi-window loop sees it,
        # then release explicitly so a stationary press becomes a selection.
        send("press 1")
        send("wait frames 60 120")
        send("release 1")
        send("wait frames 20 80")
        send(f"crop {artifacts / f'{app.lower()}-selected.ppm'} 0 0 768 576 1")
        send("press 1")
        send("wait frames 60 120")
        send("release 1")
        # Leave enough frame time for the package and first title renderer to
        # settle without relying on framebuffer quiet during module loading.
        send("wait frames 420 900")
        send("wait quiet 8 300")
        probe_snapshot = artifacts / f"{app.lower()}.sna"
        send(f"snapshot-save {probe_snapshot}")
        send(f"crop {artifacts / f'{app.lower()}.ppm'} 0 0 768 576 1")
        before = probe_snapshot.read_bytes()[0x100:0x10100]
        probe_slot = before[0x1351]
        probe_entry = 0x1352 + probe_slot * 25
        actual_kind = before[0x3EB8 + probe_slot]
        if actual_kind != APP_KINDS[app]:
            raise RuntimeError(
                f"CPC {app} window kind is 0x{actual_kind:02X}, "
                f"expected 0x{APP_KINDS[app]:02X}"
            )
        old_x = before[probe_entry + 1]
        old_y = before[probe_entry + 2]
        if app == "CLOCK":
            if before[0x1344] < 2:
                raise RuntimeError("CPC Clock did not join the shared scheduler")
            if before[0x1347]:
                raise RuntimeError("CPC scheduler reported a stack fault after Clock launch")
            # Show seconds, then focus the exposed left edge of File Manager.
            # The Clock must continue changing while it is no longer focused.
            send("key-tap S 4")
            send("wait frames 40 100")
            move_pointer_to(10, 50)
            send("hold-click 12 1")
            send("wait frames 40 120")
            bg_before, _ = snapshot_state("clock-background-before")
            if bg_before[0x1351] == probe_slot:
                raise RuntimeError("CPC Clock background test did not move focus")
            send("wait frames 900 1200")
            bg_after, bg_after_snapshot = snapshot_state("clock-background-after")
            if bg_before[0xC000:0x10000] == bg_after[0xC000:0x10000]:
                raise RuntimeError("CPC Clock framebuffer stopped while unfocused")
            if bg_after[0x1344] < 2 or bg_after[0x1347]:
                raise RuntimeError("CPC shared scheduler became unhealthy during the background run")
            send(f"crop {artifacts / 'clock-background.ppm'} 0 0 768 576 1")
            dragged, dragged_snapshot = bg_after, bg_after_snapshot
        else:
            move_pointer_to(old_x + 10, old_y + 5)
            send("press 1")
            send("wait frames 12 80")
            # The first CPC drag loads its service from the M4 card. Keep the
            # direction asserted until the service has entered its move loop.
            send("move 1 0")
            send("wait frames 60 160")
            send("stop")
            send("release 1")
            send("wait frames 60 160")
            send("wait quiet 8 300")
            dragged, dragged_snapshot = snapshot_state(f"{app.lower()}-dragged")
            new_x = dragged[probe_entry + 1]
            if new_x <= old_x:
                raise RuntimeError(
                    f"CPC universal {app} drag did not move window: {old_x} -> {new_x}"
                )
            send(f"crop {artifacts / f'{app.lower()}-dragged.ppm'} 0 0 768 576 1")
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
    # CPC low RAM is represented directly in the first 64K SNA bank after
    # the 256-byte header. Three live windows prove Desktop + File Manager +
    # the admitted compile-once application.
    final_ram = dragged_snapshot.read_bytes()[0x100:0x10100]
    nwin = final_ram[0x1350]
    if nwin != 3:
        raise SystemExit(f"CPC ABI smoke failed: expected 3 windows, found {nwin}")
    sysinfo = final_ram[0x3E00:0x3E30]
    if (sysinfo[0], sysinfo[1], sysinfo[4], sysinfo[34], sysinfo[35],
            sysinfo[36], sysinfo[37]) != (48, 6, 2, 80, 200, 4, 4):
        raise SystemExit("CPC ABI smoke failed: invalid sysinfo v6 geometry")
    focus = final_ram[0x1351]
    if final_ram[0x3E9F + focus] == 0:
        raise SystemExit("CPC ABI smoke failed: focused window has no generation")
    print(f"1984 CPC ABI smoke: {app}, {nwin} windows; captures: {artifacts}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
