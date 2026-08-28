#!/usr/bin/env python3
import argparse
import os
import queue
import re
import select
import subprocess
import sys
import threading
import time


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
EMU = os.path.abspath(os.path.join(ROOT, "..", "1984", "1984"))
DSK = os.path.join(ROOT, "QA", "CPC", "Floppies", "GEOBENCH.DSK")
PILOT_LINK = "/tmp/geobench-settings-pilot"


def read_lines(stream, outq):
    for line in iter(stream.readline, ""):
        outq.put(line.rstrip("\n"))


class OCRFrames:
    def __init__(self, fd):
        self.fd = fd
        self.buf = bytearray()
        self.latest = ""

    def poll(self, timeout):
        r, _, _ = select.select([self.fd], [], [], timeout)
        if not r:
            return None
        chunk = os.read(self.fd, 4096)
        if not chunk:
            return None
        self.buf.extend(chunk)
        frame = None
        while True:
            start = self.buf.find(b"\f")
            if start < 0:
                break
            nxt = self.buf.find(b"\f", start + 1)
            if nxt < 0:
                if start > 0:
                    del self.buf[:start]
                break
            raw = bytes(self.buf[start + 1:nxt])
            del self.buf[:nxt]
            lines = raw.replace(b"\r", b"").decode("latin1", "replace").split("\n")
            frame = "\n".join(line.rstrip() for line in lines if line is not None)
            self.latest = frame
        return frame

    def wait_for(self, needles, timeout):
        if isinstance(needles, str):
            needles = [needles]
        deadline = time.time() + timeout
        while time.time() < deadline:
            self.poll(0.2)
            if self.latest and all(n in self.latest for n in needles):
                return self.latest
        raise TimeoutError(f"timed out waiting for OCR text: {needles}")


class Pilot:
    def __init__(self, path, outq):
        self.path = path
        self.outq = outq

    def _read_reply(self, timeout):
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                line = self.outq.get(timeout=0.2)
            except queue.Empty:
                continue
            print(line)
            m = re.search(r"1984: pilot reply: (.*)", line)
            if m:
                return m.group(1)
        raise TimeoutError("timed out waiting for pilot reply")

    def command(self, text, expect=("ok", "state", "err"), timeout=3.0):
        fd = os.open(self.path, os.O_WRONLY | os.O_NOCTTY)
        try:
            os.write(fd, (text + "\n").encode("utf-8"))
        finally:
            os.close(fd)
        while True:
            line = self._read_reply(timeout)
            if line.startswith(expect):
                return line


def launch(args):
    cmd = [
        EMU,
        "--config=/dev/null",
        "--6128",
        "--memory=512",
        f"--disk-a={DSK}",
        "--autostart=GB",
        f"--pilot={PILOT_LINK}",
        "--pilot-replies-stderr",
        "--kbd-pty",
        "--ocr-monitor",
    ]
    if args.gif_out:
        cmd.append(f"--gif-out={args.gif_out}")
    if args.screenshot_at:
        cmd.append(f"--screenshot-at={args.screenshot_at}")
    if args.exit_after:
        cmd.append(f"--exit-after={args.exit_after}")
    proc = subprocess.Popen(
        cmd,
        cwd=os.path.join(ROOT, "..", "1984"),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
        env={
            **os.environ,
            "SDL_VIDEODRIVER": "dummy",
            "SDL_AUDIODRIVER": "dummy",
        },
    )
    q = queue.Queue()
    t = threading.Thread(target=read_lines, args=(proc.stderr, q), daemon=True)
    t.start()

    kbd_path = None
    pilot_path = None
    deadline = time.time() + 10
    while time.time() < deadline:
        try:
            line = q.get(timeout=0.2)
        except queue.Empty:
            continue
        print(line)
        m = re.search(r"1984: kbd PTY: (\S+)", line)
        if m:
            kbd_path = m.group(1)
        m = re.search(r"1984: pilot PTY: (\S+)", line)
        if m:
            pilot_path = m.group(1)
        if pilot_path and kbd_path:
            break
    if not kbd_path:
        raise RuntimeError("kbd PTY path was not announced")
    if not pilot_path:
        raise RuntimeError("pilot PTY path was not announced")
    return proc, Pilot(PILOT_LINK, q), OCRFrames(os.open(kbd_path, os.O_RDONLY | os.O_NONBLOCK))


def macro_open_settings(pilot, frames):
    print(pilot.command("target joy"))
    print(pilot.command("hold 70 1 135"))
    time.sleep(1.5)
    print(pilot.command("hold 12 1 0"))
    time.sleep(0.4)
    print(pilot.command("hold-click 4 1"))
    try:
        frames.wait_for(["System"], 1.5)
    except TimeoutError:
        pass
    print(pilot.command("hold 14 1 270"))
    time.sleep(0.5)
    print(pilot.command("hold-click 4 1"))


def repl(pilot, frames):
    print("Interactive mode. Prefix ':frame' to dump OCR, ':wait TEXT' to wait for OCR text.")
    for line in sys.stdin:
        line = line.rstrip("\n")
        if not line:
            continue
        if line == ":frame":
            frames.poll(0.1)
            print(frames.latest)
            continue
        if line.startswith(":wait "):
            text = line[6:]
            print(frames.wait_for(text, 5))
            continue
        print(pilot.command(line))


def main():
    ap = argparse.ArgumentParser(description="Launch GEOBENCH under 1984 with pilot+OCR helpers.")
    ap.add_argument("--gif-out")
    ap.add_argument("--screenshot-at")
    ap.add_argument("--exit-after", type=int, default=5000)
    ap.add_argument("--macro", choices=["none", "open-settings"], default="none")
    ap.add_argument("--interactive", action="store_true")
    args = ap.parse_args()

    proc, pilot, frames = launch(args)
    try:
        try:
            frame = frames.wait_for(["Disk A", "Clock"], 15)
        except TimeoutError:
            print("=== OCR timeout; latest frame ===")
            print(frames.latest)
            raise
        print("=== Desktop OCR ===")
        print(frame)
        print(pilot.command("state"))
        if args.macro == "open-settings":
            macro_open_settings(pilot, frames)
            time.sleep(1.0)
            frames.poll(0.5)
            print("=== Post-macro OCR ===")
            print(frames.latest)
        if args.interactive:
            repl(pilot, frames)
    finally:
        try:
            proc.wait(timeout=1)
        except subprocess.TimeoutExpired:
            proc.terminate()
            proc.wait(timeout=3)


if __name__ == "__main__":
    main()
