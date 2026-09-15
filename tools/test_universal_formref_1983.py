#!/usr/bin/env python3
"""Exercise primary-only universal FormRef on 1983's real MSX core."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

from test_msx_stability_1983 import Driver, constants


def linked_symbols(path: Path) -> dict[str, int]:
    return {name: int(value, 16) for name, value in re.findall(
        r"^DEF (\w+) (0x[0-9A-Fa-f]+)", path.read_text(), re.M)}


def data_symbols(symbols: Path, noi: Path) -> dict[str, int]:
    bases = linked_symbols(noi)
    result: dict[str, int] = {}
    for area, name, value in re.findall(
            r"^\s+([12])\s+(\w+)\s+([0-9A-Fa-f]+)\s+R",
            symbols.read_text(), re.M):
        base = bases["s__DATA" if area == "1" else "s__INITIALIZED"]
        result[name] = base + int(value, 16)
    return result


class FormDriver(Driver):
    def application(self, address: int, size: int = 1) -> list[int]:
        page = self.entry(2)[0]
        return self.call(f"ram {page * 0x4000 + address - 0x4000} {size}")

    def filemgr(self, symbol: str, size: int = 1) -> list[int]:
        page = self.entry(1)[0]
        return self.call(
            f"ram {page * 0x4000 + self.fm_symbols[symbol] - 0x4000} {size}")

    def click(self, x: int, y: int) -> None:
        # A joystick trigger drives the real input path without also enqueuing
        # Space into the form's keyboard stream.
        self.move(x, y)
        self.call("joystick 0 16")
        for _ in range(150):
            self.frames(1)
            if self.value("POLL_FLAGS") & 4:
                break
        else:
            self.call("joystick 0 0")
            raise AssertionError("click was not polled")
        self.call("joystick 0 0")
        self.key()
        self.frames(60)

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
                        "FormRef alias visible in icon view")
            cell = (w - 5) // 3
            self.double_click(x + 4 + cell * (column * 2 + 1) // 2,
                              y + 14 + row * 44 + 12)
            return
        raise AssertionError(f"missing File Manager entry {name!r}")

    def type_keys(self, keys: list[tuple[int, int]]) -> None:
        for row, mask in keys:
            self.key(row, mask)
            self.frames(6)
            self.key(row, 0)
            # Form changes redraw the bounded modal synchronously. Wait until
            # that drawing has consumed the key before presenting the next
            # matrix edge; no host key queue or guest-state patch is used.
            self.frames(100)

    def shift_tab(self) -> None:
        self.call("keys 6 1 7 8")
        self.frames(6)
        self.call("keys 6 0 7 0")
        self.frames(100)

    def exercise(self, args: argparse.Namespace, app: bytes) -> dict:
        symbols = data_symbols(
            args.worktree / "build/universal-obj/uformref/main.sym",
            args.worktree / "build/universal-obj/uformref/app.noi")
        self.fm_symbols = data_symbols(
            args.worktree / "build/msx-obj/filemgr/main.sym",
            args.worktree / "build/msx-obj/filemgr/app.noi")
        glue = constants(args.worktree / "lib/msx/glue.inc")
        focus = symbols["_focus"]
        draft = symbols["_draft_name"]
        states = symbols["_form_states"]
        saved_name = symbols["_saved_name"]
        saved_autosave = symbols["_saved_autosave"]
        saved_layout = symbols["_saved_layout"]

        self.wait(lambda: self.read(0xCF00, 2) == [48, 6] and
                  self.value("WM_NWIN") == 1, "desktop boot", 6000)
        self.bank = self.frames(100)["p0"]
        self.expect(self.read(0xCF05) == [args.mode], "requested Screen mode")
        baseline = self.busy()
        pages = self.read(glue["MSX_PAGE_STATE"], 32)

        self.double_click(5, 44)
        self.wait(lambda: self.value("WM_NWIN") == 2 and
                  self.value("WM_FOCUS") == 1, "File Manager launch")
        self.frames(100)
        self.entry_named(b"A       APP")
        self.wait(lambda: self.value("WM_NWIN") == 3 and
                  self.value("WM_FOCUS") == 2, "universal FormRef launch", 8000)
        self.frames(100)
        window = self.entry(2)
        self.expect(window[1:5] == [20, 42, 42, 70], "portable window geometry")
        loaded = b"".join(bytes(self.call(
            f"ram {window[0] * 0x4000 + offset} {min(4096, len(app) - offset)}"))
            for offset in range(0, len(app), 4096))
        self.expect(loaded == app, "mapped package matches compile-once bytes")
        self.expect(self.application(symbols["_resource_ready"]) == [1],
                    "embedded GBR resource published")

        # Open the modal and edit the bound field through actual matrix keys.
        self.click(30, 103)
        self.wait(lambda: self.application(focus) == [2], "field receives focus")
        self.expect(self.application(states + 4, 12) ==
                    [8, 0, 4, 0, 4, 0, 0, 0, 0, 0, 0, 0],
                    "resource state overlay initialized")
        self.type_keys([(7, 32)] * 8 + [(2, 64), (2, 128), (3, 1)])
        draft_bytes = bytes(self.application(draft, 13))
        self.expect(draft_bytes[:4] == b"abc\0",
                    "field text edited through keyboard: " + repr(draft_bytes))
        self.shift_tab()
        self.expect(self.application(focus) == [7],
                    "Shift-Tab wraps focus in reverse")
        self.type_keys([(7, 8)])
        self.expect(self.application(focus) == [2],
                    "Tab wraps focus forward")
        self.type_keys([(7, 8)])
        self.expect(self.application(focus) == [3], "Tab advances to checkbox")
        self.type_keys([(7, 128)])
        self.expect(self.application(states + 6, 2) == [8, 0],
                    "keyboard toggles checkbox")
        self.type_keys([(7, 8), (7, 8), (7, 128)])
        self.expect(self.application(focus) == [5] and
                    self.application(states + 8, 4) == [0, 0, 12, 0],
                    "keyboard selects exactly one radio")
        self.type_keys([(7, 8), (7, 128)])
        self.wait(lambda: self.application(saved_layout) == [1] and
                  self.application(saved_autosave) == [0], "Save commits form")
        self.expect(bytes(self.application(saved_name, 4)) == b"abc\0",
                    "Save commits caller-owned text")

        # Reopen and use pointer hit testing. Cancel must discard the changed
        # draft state and restore the complete compositor exactly once.
        self.click(30, 103)
        self.wait(lambda: self.application(focus) == [2], "form reopens")
        self.click(30, 90)
        self.expect(self.application(focus) == [3] and
                    self.application(states + 6, 2) == [12, 0],
                    "pointer toggles resource checkbox")
        self.click(36, 123)
        self.frames(100)
        self.expect(self.application(saved_autosave) == [0] and
                    self.application(saved_layout) == [1] and
                    bytes(self.application(saved_name, 4)) == b"abc\0",
                    "Cancel preserves saved values")

        before = self.entry(2)[1:5]
        start_x, start_y = before[0] + 8, before[1] + 4
        self.move(start_x, start_y)
        self.call("joystick 0 16")
        self.frames(6)
        self.move(start_x + 8, start_y + 8)
        self.call("joystick 0 0")
        self.key()
        self.wait(lambda: self.entry(2)[1:3] != before[:2],
                  "managed FormRef window moved")
        self.expect(self.application(saved_layout) == [1] and
                    bytes(self.application(saved_name, 4)) == b"abc\0",
                    "saved form state survives move/repaint")

        self.close(2, 2)
        self.expect(self.busy() == baseline + 1, "FormRef page reclaimed")
        self.close(1, 1)
        self.expect(self.busy() == baseline and
                    self.read(glue["MSX_PAGE_STATE"], 32) == pages,
                    "File Manager and exact page pool reclaimed")
        self.expect(self.value("SCHED_FAULT") == 0, "scheduler guard")
        return {
            "status": "PASS", "mode": args.mode, "checks": self.checks,
            "frames": self.frame, "app_sha256": hashlib.sha256(app).hexdigest(),
            "final_windows": self.value("WM_NWIN"),
            "stack_max": self.value("SCHED_STACK_MAX"),
        }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("bridge", "omega", "sunrise", "image", "worktree", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--mode", type=int, choices=(6, 7), required=True)
    args = parser.parse_args()
    args.bios = args.subrom = None
    args.short_desk_stress = False
    if args.output.exists():
        parser.error("output exists; preserve earlier evidence")
    app = (args.worktree / "build/universal/FORMREF.APP").read_bytes()
    staged = subprocess.check_output([
        "mtype", "-i", str(args.image) + "@@16384", "::/A.APP"])
    if staged != app:
        parser.error("test image and compile-once APP differ")
    source_hash = hashlib.sha256(args.image.read_bytes()).hexdigest()
    args.output.mkdir(parents=True)
    driver = None
    try:
        with (args.output / "bridge.log").open("w") as log:
            driver = FormDriver(args, log)
            report = driver.exercise(args, app)
    except Exception as error:
        report = {"status": "FAIL", "error": str(error),
                  "frame": driver.frame if driver else 0}
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
    report.update(image_sha256=source_hash, source_image_unchanged=unchanged)
    (args.output / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
