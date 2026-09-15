#!/usr/bin/env python3
"""Exercise the compile-once GBR resource receiver on 1983's real MSX core."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

from test_msx_stability_1983 import Driver, constants


def linked_symbols(noi: Path) -> dict[str, int]:
    return {name: int(value, 16) for name, value in re.findall(
        r"^DEF (\w+) (0x[0-9A-Fa-f]+)", noi.read_text(), re.M)}


def data_symbols(symbols: Path, noi: Path) -> dict[str, int]:
    bases = linked_symbols(noi)
    result: dict[str, int] = {}
    for area, name, value in re.findall(
            r"^\s+([12])\s+(\w+)\s+([0-9A-Fa-f]+)\s+R",
            symbols.read_text(), re.M):
        base = bases["s__DATA" if area == "1" else "s__INITIALIZED"]
        result[name] = base + int(value, 16)
    return result


class ResourceDriver(Driver):
    def application(self, address: int, size: int = 1) -> list[int]:
        page = self.entry(2)[0]
        return self.call(f"ram {page * 0x4000 + address - 0x4000} {size}")

    def filemgr(self, symbol: str, size: int = 1) -> list[int]:
        page = self.entry(1)[0]
        return self.call(
            f"ram {page * 0x4000 + self.fm_symbols[symbol] - 0x4000} {size}")

    def double_click(self, x: int, y: int) -> None:
        self.move(x, y)
        for pause in (1, 60):
            self.wait(lambda: not self.value("POLL_FLAGS") & 4,
                      "button release before next press", 150)
            self.call("joystick 0 16")
            for _ in range(150):
                self.frames(1)
                if self.value("POLL_FLAGS") & 4:
                    break
            else:
                raise AssertionError("double click was not polled")
            self.call("joystick 0 0")
            self.frames(pause)

    def entry_named(self, name: bytes) -> None:
        self.wait(lambda: self.filemgr("_list_state") == [0],
                  "File Manager listing complete")
        total = self.filemgr("_total")[0]
        names = self.filemgr("_names", 64 * 11)
        order = self.filemgr("_order", 64)
        for index, raw in enumerate(order[:total]):
            if bytes(names[raw * 11:raw * 11 + 11]) != name:
                continue
            row, column = divmod(index, 3)
            _, x, y, w, h, *_ = self.entry(1)
            self.expect(0 <= row < (h - 16) // 44,
                        "resource entry visible in icon view")
            cell = (w - 5) // 3
            self.double_click(x + 4 + cell * (column * 2 + 1) // 2,
                              y + 14 + row * 44 + 12)
            return
        listed = [bytes(names[raw * 11:raw * 11 + 11]) for raw in order[:total]]
        raise AssertionError(
            f"missing File Manager entry {name!r}: total={total}, "
            f"listed={listed!r}, windows={self.value('WM_NWIN')}, "
            f"focus={self.value('WM_FOCUS')}, page={self.entry(1)[0]}")

    def exercise(self, args: argparse.Namespace, app: bytes) -> dict:
        universal = data_symbols(
            args.worktree / "build/universal-obj/ugbrdemo/main.sym",
            args.worktree / "build/universal-obj/ugbrdemo/app.noi")
        self.fm_symbols = data_symbols(
            args.worktree / "build/msx-obj/filemgr/main.sym",
            args.worktree / "build/msx-obj/filemgr/app.noi")
        glue = constants(args.worktree / "lib/msx/glue.inc")
        ready = universal["_ready"]
        states = universal["_object_states"]

        self.wait(lambda: self.read(0xCF00, 2) == [48, 6] and
                  self.value("WM_NWIN") == 1, "desktop boot", 6000)
        self.bank = self.frames(100)["p0"]
        self.expect(self.read(0xCF05) == [args.mode], "requested Screen mode")
        baseline = self.busy()

        self.double_click(5, 44)
        self.wait(lambda: self.value("WM_NWIN") == 2 and
                  self.value("WM_FOCUS") == 1, "File Manager launch")
        self.frames(100)
        self.entry_named(b"HELLO   GBR")
        self.wait(lambda: self.value("WM_NWIN") == 3 and
                  self.value("WM_FOCUS") == 2,
                  "universal GBRDEMO launch and focus", 8000)
        self.frames(100)

        expected_ready = int(args.case == "good")
        self.expect(self.application(ready) == [expected_ready],
                    "canonical resource accepted or malformed resource inert")
        initial_state = [8, 0] if expected_ready else [0, 0]
        self.expect(self.application(states + 4, 2) == initial_state,
                    "button begins outlined and unselected, or remains inert")
        loaded = b"".join(bytes(self.call(
            f"ram {self.entry(2)[0] * 0x4000 + i} {min(4096, len(app) - i)}"))
            for i in range(0, len(app), 4096))
        self.expect(loaded == app, "loaded application matches compile-once bytes")
        self.expect(self.read(glue["MSX_FSCTX_PENDING"]) == [0] and
                    self.read(0x1485, 11) == [0] * 11,
                    "launch record and scratch consumed")
        self.expect(sum(bool(self.read(glue["MSX_FSCTX_TABLE"] + 144 * i)[0])
                        for i in range(4)) == 1,
                    "receiver closed its adopted context")

        self.click(64, 124)
        wanted_state = [10, 0] if expected_ready else [0, 0]
        self.wait(lambda: self.application(states + 4, 2) == wanted_state,
                  "resource button state or malformed-resource inertness")

        before = self.entry(2)[1:5]
        start_x, start_y = before[0] + 8, before[1] + 4
        self.move(start_x, start_y)
        self.key(8, 1)
        self.frames(6)
        self.move(start_x + 10, start_y + 8, 1)
        self.key()
        self.wait(lambda: self.entry(2)[1:3] != before[:2],
                  "managed resource window moved")
        self.expect(self.application(ready) == [expected_ready] and
                    self.application(states + 4, 2) == wanted_state,
                    "resource state survives move and overlap repaint")

        self.close(2, 2)
        self.expect(self.busy() == baseline + 1,
                    "resource application page reclaimed")
        self.close(1, 1)
        self.expect(self.busy() == baseline and
                    not any(self.read(glue["MSX_FSCTX_TABLE"] + 144 * i)[0]
                            for i in range(4)),
                    "File Manager page and contexts reclaimed")
        self.expect(not self.value("SCHED_FAULT"), "scheduler guard")
        return dict(status="PASS", case=args.case, mode=args.mode,
                    checks=self.checks, frames=self.frame)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("bridge", "omega", "sunrise", "image", "worktree", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--mode", type=int, choices=(6, 7), required=True)
    parser.add_argument("--case", choices=("good", "checksum", "truncated", "oversized"),
                        required=True)
    args = parser.parse_args()
    args.bios = args.subrom = None
    args.short_desk_stress = False
    if args.output.exists():
        parser.error("output exists; preserve earlier evidence")
    app = (args.worktree / "build/universal/GBRDEMO.APP").read_bytes()
    if subprocess.check_output([
            "mtype", "-i", str(args.image) + "@@16384", "::/GBENCH/GBRDEMO.APP"
            ]) != app:
        parser.error("test image and compile-once APP differ")
    source_hash = hashlib.sha256(args.image.read_bytes()).hexdigest()
    args.output.mkdir(parents=True)
    driver = None
    try:
        with (args.output / "bridge.log").open("w") as log:
            driver = ResourceDriver(args, log)
            report = driver.exercise(args, app)
    except Exception as error:
        report = dict(status="FAIL", error=str(error),
                      frame=driver.frame if driver else 0)
    finally:
        if driver:
            try:
                driver.call(f"ppm {args.output.resolve() / 'screen.ppm'}")
            except Exception as error:
                report.update(status="FAIL", capture_error=str(error))
            finally:
                driver.process.terminate()
                driver.process.wait(timeout=10)
    unchanged = hashlib.sha256(args.image.read_bytes()).hexdigest() == source_hash
    if not unchanged:
        report.update(status="FAIL", media_changed=True)
    report.update(image_sha256=source_hash, source_image_unchanged=unchanged,
                  app_sha256=hashlib.sha256(app).hexdigest(),
                  bridge_sha256=hashlib.sha256(args.bridge.read_bytes()).hexdigest())
    (args.output / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
