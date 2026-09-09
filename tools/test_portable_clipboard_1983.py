#!/usr/bin/env python3
"""Real Desk input and read-only observations of the portable clipboard APP.

Use the private hard disk produced by test_portable_fs_openmsx.py --clipboard,
with the SAME built-root symbols. No debugger-injected calls or guest writes.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

from test_msx_stability_1983 import Driver, constants


class ClipboardDriver(Driver):
    def exercise(self, args):
        linked = (args.worktree / "build/universal-obj/scrapprobe/app.noi").read_text()
        at = int(re.search(r"^DEF _scrapprobe_state (0x[0-9A-Fa-f]+)", linked, re.M)[1], 16)
        glue = constants(args.worktree / "lib/msx/glue.inc")
        self.wait(lambda: self.read(0xCF00, 2) == [48, 6] and
                  self.value("WM_NWIN") == 1, "desktop boot", 6000)
        state = self.frames(100)
        self.bank = state["p0"]
        self.expect(self.read(0xCF05)[0] == args.mode, "requested screen mode")
        self.expect(state["vdp_regs"][0] & 14 == (10 if args.mode == 7 else 8), "bitmap mode")
        self.expect(self.read(0xCF21)[0] & 1, "typed clipboard capability")
        baseline = self.busy()
        results, identities = [], []
        for cycle in range(3):
            self.click(11, 4)
            self.click(12, 14)
            self.wait(lambda: self.value("WM_NWIN") == 2 and self.value("WM_FOCUS") > 0,
                      "clipboard app opened/focused")
            self.frames(100)
            slot = self.value("WM_FOCUS")
            native = self.entry(slot)[0]
            result = self.call(f"ram {native*0x4000 + at-0x4000} 8")
            self.expect(result[:3] == [85, 49+bool(cycle), int(bool(cycle))],
                        f"clipboard checks cycle {cycle}: {result}")
            owner = (self.read(glue["MSX_WIN_OWNER"]+slot)[0],
                     self.read(glue["MSX_WIN_OWNER_GEN"]+slot)[0])
            self.expect(owner not in identities, "fresh owner generation")
            identities.append(owner); results.append(result)
            self.border(slot)
            self.close(slot, 1)
            self.expect(self.busy() == baseline, "app page reclaimed")
            self.expect(self.read(0x133D)[0] == 1 and
                        self.read(0x3E00, 8) == list(b"\x06\x00SHARED"),
                        "clipboard survived owner teardown")
            self.expect(self.value("SCHED_FAULT") == 0, "scheduler guard")
        return dict(status="PASS", results=results, owners=identities,
                    checks=self.checks, frames=self.frame, final_windows=self.value("WM_NWIN"),
                    busy_pages=self.busy(), stack_max=self.value("SCHED_STACK_MAX"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("bridge", "omega", "sunrise", "image", "worktree", "output"):
        parser.add_argument("--"+name, type=Path, required=True)
    parser.add_argument("--mode", type=int, choices=(6, 7), required=True)
    parser.add_argument("--bios", type=Path)
    parser.add_argument("--subrom", type=Path)
    args = parser.parse_args()
    args.short_desk_stress = False
    if bool(args.bios) != bool(args.subrom): parser.error("supply both BIOS and subROM")
    if args.output.exists(): parser.error("output exists; preserve evidence with a new path")
    app = (args.worktree / "build/universal/SCRAPPRB.APP").read_bytes()
    if subprocess.check_output(["mtype", "-i", str(args.image)+"@@16384", "::/GBENCH/CLOCK.APP"]) != app:
        parser.error("private image does not contain the matching clipboard APP")
    args.output.mkdir(parents=True)
    driver = None
    try:
        with (args.output / "bridge.log").open("w") as log:
            driver = ClipboardDriver(args, log)
            report = driver.exercise(args)
    except Exception as error:
        report = dict(status="FAIL", error=str(error), frame=driver.frame if driver else 0)
    finally:
        if driver:
            try:
                driver.call(f"ppm {args.output.resolve()/'screen.ppm'}")
            except Exception as error:
                report.update(status="FAIL", capture_error=str(error))
            finally:
                driver.process.terminate(); driver.process.wait(timeout=10)
    report.update(mode=args.mode, app_sha256=hashlib.sha256(app).hexdigest(),
                  image_sha256=hashlib.sha256(args.image.read_bytes()).hexdigest(),
                  bridge_sha256=hashlib.sha256(args.bridge.read_bytes()).hexdigest())
    (args.output / "result.json").write_text(json.dumps(report, indent=2)+"\n")
    print(json.dumps(report, indent=2))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
