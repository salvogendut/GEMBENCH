#!/usr/bin/env python3
"""Real Desk input and read-only observations of the portable data-page APP.

Use an isolated image from test_portable_fs_openmsx.py --data-pages and its
matching worktree. Does not inject guest calls or write guest RAM.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

from test_msx_stability_1983 import Driver, constants
from embed_app_icon import parse_manifest


class PageDriver(Driver):
    def exercise(self, args):
        linked = args.symbols.read_text()
        stem = 'computeprobe' if args.compute else 'pageprobe'
        at = int(re.search(rf"^DEF _{stem}_state (0x[0-9A-Fa-f]+)", linked, re.M)[1], 16)
        glue = constants(args.worktree / "lib/msx/glue.inc")
        self.wait(lambda: self.read(0xCF00, 2) == [48, 6] and
                  self.value("WM_NWIN") == 1, "desktop boot", 6000)
        state = self.frames(100)
        self.bank = state["p0"]
        self.expect(self.read(0xCF05)[0] == args.mode, "requested screen mode")
        self.expect(state["vdp_regs"][0] & 14 == (10 if args.mode == 7 else 8), "bitmap mode")
        self.expect(self.read(0xCF21)[0] & 2, "portable data-page capability")
        if args.compute:
            self.expect(self.read(0xCF21)[0] & 4, "sealed computation capability")
        baseline = self.busy()
        pages = self.read(glue["MSX_PAGE_STATE"], 32)
        free = self.read(glue["MSX_PAGE_FREE"])[0]
        results, identities = [], []
        app = args.app.read_bytes()
        manifest = parse_manifest(app)
        primary = app[:manifest['primary_image_size']]
        secondary = next((app[s['offset']:s['offset']+s['stored_length']]
                          for s in manifest['segments'] if s['type'] == 2), None)
        progress = []
        for cycle in range(3):
            self.cycle = cycle
            self.click(11, 4)
            if secondary is not None:
                package = constants(args.worktree/'kernel/msx_package_layout.inc')
                self.move(12, 14)
                self.key(8, 1)
                self.frames(6)
                self.key()
                self.wait(lambda: self.read(package['MSX_PACKAGE_STATE'])[0] == 1,
                          'stream started through Desk', 100)
                self.expect(self.read(package['MSX_PACKAGE_STATE'])[0] == 1,
                            'observed in-flight stream, not a completed launch')
                previous = self.frame
                last = self.value('POLL_MX')
                gaps = []
                self.key(8, 128)
                for _ in range(100):
                    self.frames(1)
                    self.expect(self.value('SCHED_LOCK') and not self.value('SCHED_CURRENT'),
                                'root serialized during pointer-only loading progress')
                    now = self.value('POLL_MX')
                    if now != last:
                        gaps.append(self.frame-previous)
                        previous, last = self.frame, now
                self.key()
                self.expect(len(gaps) > 20 and max(gaps) <= 6,
                            f'pointer progress during stream: {gaps}')
                progress.append(dict(changes=len(gaps), max_gap_frames=max(gaps)))
            else:
                self.click(12, 14)
            self.wait(lambda: self.value("WM_NWIN") == 2 and self.value("WM_FOCUS") > 0,
                      "data-page app opened/focused")
            self.frames(100)
            slot = self.value("WM_FOCUS")
            native = self.entry(slot)[0]
            result = self.call(f"ram {native*0x4000 + at-0x4000} 8")
            count = result[1]+256*result[2]
            self.expect(result[0] == 85 and (count == 54 if args.compute else count >= 130) and
                        result[4] == (0 if args.compute else bool(cycle)),
                        f"{stem} checks cycle {cycle}: {result}")
            code = b"".join(bytes(self.call(f"ram {native*0x4000+i} {min(4096,len(primary)-i)}"))
                            for i in range(0, len(primary), 4096))
            self.expect(code == primary, "primary application code unchanged")
            owner = (self.read(glue["MSX_WIN_OWNER"]+slot)[0],
                     self.read(glue["MSX_WIN_OWNER_GEN"]+slot)[0])
            if secondary is not None:
                candidates = [i for i in range(self.read(glue['MSX_PAGE_TOTAL'])[0])
                              if self.read(glue['MSX_PAGE_STATE']+i)[0] and
                              self.read(glue['MSX_PAGE_PURPOSE']+i)[0] == 7 and
                              self.read(glue['MSX_PAGE_OWNER']+i)[0] == owner[0] and
                              self.read(glue['MSX_PAGE_OWNER_GEN']+i)[0] == owner[1]]
                self.expect(len(candidates) == 1, 'one secondary belonging to this owner generation')
                bank = self.read(glue['MSX_PAGE_NATIVE']+candidates[0])[0]
                stored = b''.join(bytes(self.call(f'ram {bank*0x4000+i} 4096'))
                                  for i in range(0, 0x4000, 4096))
                if args.compute:
                    self.expect(stored[:len(secondary)] == secondary,
                                'secondary executable bytes unchanged after real calls')
                    # The C probe checks initialization, persistent 4-KiB state,
                    # and reset for each fresh owner. Its data tail is mutable.
                    seal = self.read(0x2180+8*(owner[0]-1), 3)
                    expected = [owner[1], candidates[0]+1,
                                self.read(glue['MSX_PAGE_GEN']+candidates[0])[0]]
                    self.expect(seal == expected,
                                f'seal matches live owner/page: actual={seal} expected={expected}')
                else:
                    self.expect(stored == secondary+bytes(0x4000-len(secondary)),
                                'complete secondary bytes and zeroed allocation tail')
            self.expect(owner not in identities, "fresh owner generation")
            identities.append(owner); results.append(result)
            self.border(slot)
            self.close(slot, 1)
            self.expect(self.busy() == baseline, "all owned pages reclaimed")
            self.expect(self.read(glue["MSX_PAGE_STATE"], 32) == pages and
                        self.read(glue["MSX_PAGE_FREE"])[0] == free,
                        "exact full-pool baseline restored")
            self.expect(self.value("SCHED_FAULT") == 0, "scheduler guard")
            if args.compute:
                self.expect(self.read(0x2180, 64) == [0]*64 and self.read(0x21C0) == [0],
                            'all seals reclaimed and call gate idle')
        return dict(status="PASS", results=results, owners=identities,
                    stream_progress=progress,
                    checks=self.checks, frames=self.frame, final_windows=self.value("WM_NWIN"),
                    busy_pages=self.busy(), stack_max=self.value("SCHED_STACK_MAX"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("bridge", "omega", "sunrise", "image", "worktree", "output"):
        parser.add_argument("--"+name, type=Path, required=True)
    parser.add_argument("--mode", type=int, choices=(6, 7), required=True)
    parser.add_argument("--bios", type=Path)
    parser.add_argument("--subrom", type=Path)
    parser.add_argument('--app', type=Path, help='matching staged APP, including a two-segment package')
    parser.add_argument('--symbols', type=Path, help='matching link symbols (defaults to staged probe.noi)')
    parser.add_argument('--compute', action='store_true', help='execute the compiled computation probe')
    args = parser.parse_args()
    stem = 'computeprobe' if args.compute else 'pageprobe'
    args.app = args.app or args.worktree/('build/universal/COMPUTE.APP' if args.compute else 'build/universal/PAGEPRB.APP')
    args.symbols = args.symbols or (args.app.with_suffix('.noi') if args.app.with_suffix('.noi').exists()
                                  else args.worktree/f'build/universal-obj/{stem}/app.noi')
    args.short_desk_stress = False
    if bool(args.bios) != bool(args.subrom): parser.error("supply both BIOS and subROM")
    if args.output.exists(): parser.error("output exists; preserve evidence with a new path")
    app = args.app.read_bytes()
    if subprocess.check_output(["mtype", "-i", str(args.image)+"@@16384", "::/GBENCH/CLOCK.APP"]) != app:
        parser.error("private image does not contain the matching data-page APP")
    original = hashlib.sha256(args.image.read_bytes()).hexdigest()
    args.output.mkdir(parents=True)
    driver = None
    try:
        with (args.output / "bridge.log").open("w") as log:
            driver = PageDriver(args, log)
            report = driver.exercise(args)
    except Exception as error:
        report = dict(status="FAIL", error=str(error), frame=driver.frame if driver else 0)
        if driver:
            try:
                report.update(cycle=getattr(driver, 'cycle', None), machine=driver.frames(0),
                              package=driver.read(0xD0E3, 29), windows=driver.value('WM_NWIN'),
                              lock=driver.value('SCHED_LOCK'))
            except Exception as observation_error:
                report['observation_error'] = str(observation_error)
    finally:
        if driver:
            try:
                driver.call(f"ppm {args.output.resolve()/'screen.ppm'}")
            except Exception as error:
                report.update(status="FAIL", capture_error=str(error))
            finally:
                driver.process.terminate(); driver.process.wait(timeout=10)
    unchanged = hashlib.sha256(args.image.read_bytes()).hexdigest() == original
    report.update(mode=args.mode, app_sha256=hashlib.sha256(app).hexdigest(),
                  image_sha256=original, image_unchanged=unchanged,
                  bridge_sha256=hashlib.sha256(args.bridge.read_bytes()).hexdigest())
    if not unchanged: report.update(status="FAIL", error="diagnostic changed disk image")
    (args.output / "result.json").write_text(json.dumps(report, indent=2)+"\n")
    print(json.dumps(report, indent=2))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
