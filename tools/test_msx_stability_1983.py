#!/usr/bin/env python3
"""Real-key Desk/Clock/Calculator lifecycle on 1983's unmodified core.

The read-only bridge is built separately; this does not emulate GEOBENCH policy
in the host or write guest RAM. Results are bounded runtime evidence, not a
claim of full release stability or of testing the SDL front end.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import select
import subprocess


def constants(path: Path) -> dict[str, int]:
    return {name: int(value[1:], 16) if value.startswith("#") else int(value)
            for name, value in re.findall(
                r"^(\w+)\s+equ\s+(#[0-9A-Fa-f]+|\d+)(?=\s|$)",
                path.read_text(), re.M)}


class Driver:
    def __init__(self, args, log):
        symbols = (args.worktree/"build/universal-obj/uclock/main.sym").read_text()
        linked = (args.worktree/"build/universal-obj/uclock/app.noi").read_text()
        offset = int(re.search(r"^\s+1\s+_show_sec\s+([0-9A-Fa-f]+)", symbols, re.M)[1], 16)
        base = int(re.search(r"^DEF s__DATA (0x[0-9A-Fa-f]+)", linked, re.M)[1], 16)
        self.seconds_address = base + offset
        command = [str(args.bridge), str(args.omega), str(args.sunrise), str(args.image)]
        if args.bios:
            command += [str(args.bios), str(args.subrom)]
        self.process = subprocess.Popen(command,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log,
            text=True, bufsize=1)
        self.layout = constants(args.worktree / "kernel/lowram.inc")
        self.bank = None
        self.frame = 0
        self.checks = 0
        self.metrics = []
        self.short_desk_stress = args.short_desk_stress
        try:
            if self.response() != {"ready": True}:
                raise RuntimeError("bridge initialization")
        except Exception:
            self.process.terminate()
            self.process.wait(timeout=10)
            raise

    def response(self):
        if not select.select([self.process.stdout], [], [], 60)[0]:
            raise TimeoutError("1983 bridge did not reply within 60 seconds")
        line = self.process.stdout.readline()
        if not line:
            raise RuntimeError(f"1983 bridge exited: {self.process.poll()}")
        data = json.loads(line)
        if isinstance(data, dict) and "error" in data:
            raise RuntimeError(data["error"])
        return data

    def call(self, command):
        self.process.stdin.write(command + "\n")
        self.process.stdin.flush()
        return self.response()

    def frames(self, count):
        state = self.call(f"frames {count}")
        self.frame = state["frame"]
        return state

    def read(self, address, count=1):
        # Once boot establishes the fixed low-RAM mapper segment, inspect that
        # physical segment even while a BIOS call temporarily maps ROM over it.
        if self.bank is not None and address < 0x4000:
            return self.call(f"ram {self.bank * 0x4000 + address} {count}")
        return self.call(f"read {address} {count}")

    def value(self, name):
        return self.read(self.layout[name])[0]

    def expect(self, condition, description):
        if not condition:
            raise AssertionError(f"frame {self.frame}: {description}")
        self.checks += 1

    def wait(self, condition, description, limit=2000):
        end = self.frame + limit
        while self.frame < end:
            if condition():
                self.expect(True, description)
                return
            self.frames(5)
        raise AssertionError(f"frame {self.frame}: timeout {description}")

    def key(self, row=8, mask=0):
        self.call(f"key {row} {mask}")

    def move(self, x, y, held=0):
        end = self.frame + 6000
        while self.frame < end:
            px, py = self.read(self.layout["POLL_MX"], 2)
            if abs(px-x) <= 1 and abs(py-y) <= 3:
                self.key(8, held)
                self.frames(8)
                return
            mask = 128 if px < x-1 else 16 if px > x+1 else 64 if py < y-3 else 32
            self.key(8, held | mask)
            self.frames(1)
        raise AssertionError(f"pointer timeout: {px},{py} -> {x},{y}")

    def click(self, x, y):
        self.move(x, y)
        self.key(8, 1)
        self.frames(4 if self.short_desk_stress else 6)
        self.key()
        self.frames(60)

    def focus_desktop(self):
        self.click(115, 195)
        self.wait(lambda: self.value("WM_FOCUS") == 0, "desktop focus")

    def accessory(self, row, count):
        self.focus_desktop()
        self.click(11, 4)
        self.click(12, 14 + row*10)
        self.wait(lambda: self.value("WM_NWIN") == count and self.value("WM_FOCUS") > 0,
                  "Desk accessory launch/activation")
        self.frames(100)
        slot = self.value("WM_FOCUS")
        entry = self.entry(slot)
        self.expect((entry[13] & 0xE0) == 0xA0 and entry[24] == row+1,
                    "accessory identity and registration")
        self.border(slot)
        return slot

    def entry(self, slot):
        return self.read(self.layout["WM_TABLE"] + slot*self.layout["WM_ESZ"], 25)

    def border(self, slot):
        _, x, y, w, h, *_ = self.entry(slot)
        mode = self.read(0xCF05)[0]
        for px, py in [(x,y+20), (x+w-1,y+20), (x+5,y+h-1)]:
            # 1983 stores the physical even/odd VRAM banks separately in
            # Screen 7; openMSX's debug VRAM view is linearly interleaved.
            addresses = [py*128+px, 65536+py*128+px] if mode == 7 else [py*128+px]
            expected = 0x22 if mode == 7 else 0xAA
            for address in addresses:
                actual = self.call(f"vram {address} 1")
                self.expect(actual == [expected],
                            f"window chrome at {px},{py}, VRAM {address}: {actual} != {[expected]}")

    def busy(self):
        return sum(bool(x) for x in self.read(self.layout["APP_BUSY"], 8))

    def close(self, slot, count):
        entry = self.entry(slot)
        self.click(entry[1]+2, entry[2]+4)
        self.wait(lambda: self.value("WM_NWIN") == count, "window close")
        self.frames(50)

    def cadence(self, label):
        self.move(15, 195)
        start = previous = self.frame
        changes, gaps = 0, []
        last = self.value("POLL_MX")
        self.key(8, 128)
        for _ in range(150):
            self.frames(1)
            now = self.value("POLL_MX")
            if now != last:
                changes += 1
                gaps.append(self.frame-previous)
                previous, last = self.frame, now
            if now >= 110:
                break
        self.key()
        self.expect(changes > 0, "pointer advances under load")
        self.metrics.append(dict(scenario=label, frames=self.frame-start,
                                 changes=changes, max_gap_frames=max(gaps), end_x=last))

    def run(self, mode):
        self.wait(lambda: self.read(0xCF00, 6)[:2] == [48, 6] and
                  self.value("WM_NWIN") == 1, "desktop boot", 6000)
        state = self.frames(100)
        self.bank = state["p0"]
        self.expect(self.read(0xCF05)[0] == mode, "requested Screen mode")
        self.expect((state["vdp_regs"][0] & 14) == (10 if mode == 7 else 8),
                    f"VDP entered requested bitmap mode, R0={state['vdp_regs'][0]}")
        baseline_busy = self.busy()
        self.cadence("desktop-idle")
        for cycle in range(3):
            clock = self.accessory(0, 2)
            self.key(5, 1)
            self.frames(20)
            self.key()
            self.frames(100)
            self.expect(self.call(f"ram {self.entry(clock)[0]*0x4000 + self.seconds_address-0x4000} 1") == [1],
                        "Clock seconds acknowledged the real S key")
            self.cadence(f"clock-seconds-{cycle}")
            calc = self.accessory(1, 3)
            self.expect(self.accessory(0, 3) == clock, "Clock reused, not duplicated")
            self.close(clock, 2)
            self.expect(self.busy() == baseline_busy+1, "Clock page reclaimed")
            self.close(calc, 1)
            self.expect(self.busy() == baseline_busy, "accessory pages reclaimed")
            self.expect(self.value("SCHED_FAULT") == 0, "scheduler stack guards")
        if self.short_desk_stress:
            clock = self.accessory(0, 2)
            self.key(5, 1)
            self.frames(20)
            self.key()
            self.frames(100)
            self.expect(self.call(f"ram {self.entry(clock)[0]*0x4000 + self.seconds_address-0x4000} 1") == [1],
                        "Clock seconds enabled for short-click stress")
            self.focus_desktop()
            for cycle in range(50):
                self.click(11, 4)  # four PAL frames: 80 ms, including during repaint
                self.wait(lambda: self.value("UI_MODAL") == 1,
                          f"Desk short click {cycle+1}", 200)
                # Native GBUI C binding: UI_NAME=0x1708, UI_TEXT=0x1718.
                self.expect(self.read(0x1718, 5) == list(b"Clock"), "actual Desk menu")
                self.key(7, 4)
                self.frames(4)
                self.key()
                self.wait(lambda: self.value("UI_MODAL") == 0, "Desk cancelled", 200)
                self.frames(7)
            self.click(self.entry(clock)[1]+8, self.entry(clock)[2]+4)
            self.close(clock, 1)
            self.expect(self.busy() == baseline_busy, "stress Clock page reclaimed")
            self.expect(self.value("SCHED_FAULT") == 0, "stress scheduler guards")
        return dict(status="PASS", frames=self.frame, checks=self.checks,
                    short_desk_cycles=50 if self.short_desk_stress else 0,
                    pointer_metrics=self.metrics, final_windows=self.value("WM_NWIN"),
                    stack_max=self.value("SCHED_STACK_MAX"), busy_pages=self.busy())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("bridge", "omega", "sunrise", "image", "worktree", "output"):
        parser.add_argument("--"+name, type=Path, required=True)
    parser.add_argument("--mode", type=int, choices=(6,7), required=True)
    parser.add_argument("--bios", type=Path)
    parser.add_argument("--subrom", type=Path)
    parser.add_argument("--short-desk-stress", action="store_true",
                        help="use 80-ms clicks and add 50 Desk cycles while Clock repaints")
    args = parser.parse_args()
    if bool(args.bios) != bool(args.subrom):
        parser.error("--bios and --subrom must be supplied together")
    if args.output.exists():
        parser.error("output already exists; choose a new directory to preserve evidence")
    args.output.mkdir(parents=True)
    driver = None
    report = {}
    try:
        with (args.output/"bridge.log").open("w") as log:
            driver = Driver(args, log)
            report = driver.run(args.mode)
    except Exception as error:
        report = dict(status="FAIL", error=str(error), frames=driver.frame if driver else 0)
    finally:
        if driver:
            try:
                report["last_state"] = driver.frames(0)
                report["window_table"] = driver.read(driver.layout["WM_TABLE"], 25*8)
                report["pointer_metrics"] = driver.metrics
                driver.call(f"ppm {args.output.resolve()/'screen.ppm'}")
            except Exception as error:
                report["capture_error"] = str(error)
                report["status"] = "FAIL"
            finally:
                driver.process.terminate()
                driver.process.wait(timeout=10)
        report.update(mode=args.mode, firmware="philips" if args.bios else "omega-rainbios",
                      image_sha256=hashlib.sha256(args.image.read_bytes()).hexdigest())
        (args.output/"result.json").write_text(json.dumps(report, indent=2)+"\n")
    print(json.dumps(report, indent=2))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
