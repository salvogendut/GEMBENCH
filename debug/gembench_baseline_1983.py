#!/usr/bin/env python3
"""Boot GEMBENCH in 1983 and generate the baseline reports."""

from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_EMULATOR = ROOT.parent / "1983" / "1983"
DEFAULT_MODELS = ROOT.parent / "1983" / "1983-models.conf"
DEFAULT_SUNRISE_ROM = ROOT.parent / "1983" / "ROMS" / "Nextor-2.1.1.SunriseIDE.ROM"
DEFAULT_IDE_IMAGE = ROOT / "QA" / "MSX" / "GBMSX.IMG"
PASTE_INITIAL_DELAY_FRAMES = 3


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--emulator", type=Path, default=DEFAULT_EMULATOR)
    parser.add_argument("--models", type=Path, default=DEFAULT_MODELS)
    parser.add_argument("--model", default="omega-msx2")
    parser.add_argument("--sunrise-rom", type=Path, default=DEFAULT_SUNRISE_ROM)
    parser.add_argument("--ide-image", type=Path, default=DEFAULT_IDE_IMAGE)
    parser.add_argument("--output-dir", type=Path, default=ROOT / "build" / "baseline")
    parser.add_argument("--frames", type=int, default=6000)
    parser.add_argument("--runtime-probes", action="store_true")
    parser.add_argument("--input-response", action="store_true")
    parser.add_argument("--keyboard-paste-at", type=int, default=2000)
    parser.add_argument("--static-json", type=Path)
    args = parser.parse_args(argv)

    if not args.emulator.is_file():
        parser.error(f"emulator not found: {args.emulator}")
    if not args.models.is_file():
        parser.error(f"machine catalogue not found: {args.models}")
    if not args.sunrise_rom.is_file():
        parser.error(f"Sunrise Nextor ROM not found: {args.sunrise_rom}")
    if not args.ide_image.is_file():
        parser.error(f"system IDE image not found: {args.ide_image}")
    if args.frames <= 0:
        parser.error("--frames must be positive")
    if args.input_response and not args.runtime_probes:
        parser.error("--input-response requires --runtime-probes")
    if args.keyboard_paste_at < 0:
        parser.error("--keyboard-paste-at must be non-negative")
    if args.input_response and args.frames <= args.keyboard_paste_at + 10:
        parser.error("--frames must leave time for the injected keyboard response")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    log_path = args.output_dir / "1983.log"
    screenshot_path = args.output_dir / "desktop.ppm"
    markdown_path = args.output_dir / "gembench-baseline.md"
    json_path = args.output_dir / "gembench-baseline.json"
    for generated_path in (log_path, screenshot_path, markdown_path, json_path):
        generated_path.unlink(missing_ok=True)
    command = [
        str(args.emulator),
        "--config",
        "/dev/null",
        "--models",
        str(args.models),
        "--model",
        args.model,
        "--headless",
        "--unthrottled",
        "--memory",
        "512",
        "--sunrise-rom",
        str(args.sunrise_rom),
        "--ide",
        str(args.ide_image),
        "--ide-mode",
        "read-only",
        "--exit-after",
        str(args.frames),
        "--screenshot",
        str(screenshot_path),
        "--dump-state",
        "--dump-ram",
        "0xC000:96",
    ]
    if args.input_response:
        command.extend(
            ["--paste-text", "b", "--paste-at", str(args.keyboard_paste_at)]
        )
    completed = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=False)
    log = completed.stdout + completed.stderr
    log_path.write_text(log, encoding="utf-8")
    if "state frame=" not in log:
        print(log, file=sys.stderr, end="")
        print(f"baseline error: 1983 exited {completed.returncode} without telemetry", file=sys.stderr)
        return 1
    if not screenshot_path.is_file():
        print("baseline error: 1983 did not create the desktop screenshot", file=sys.stderr)
        return 1

    report_command = [
        sys.executable,
        str(ROOT / "tools" / "gembench_baseline.py"),
        "--root",
        str(ROOT),
        "--emulator-log",
        str(log_path),
        "--require-runtime",
        "--markdown",
        str(markdown_path),
        "--json",
        str(json_path),
    ]
    if args.runtime_probes:
        report_command.append("--require-probes")
    if args.input_response:
        report_command.extend(
            [
                "--require-input-keyboard",
                "--keyboard-injection-frame",
                str(args.keyboard_paste_at + PASTE_INITIAL_DELAY_FRAMES),
            ]
        )
    if args.static_json is not None:
        report_command.extend(["--static-json", str(args.static_json)])
    report = subprocess.run(report_command, cwd=ROOT, check=False)
    if report.returncode:
        return report.returncode

    print(f"1983 log: {log_path.relative_to(ROOT)}")
    print(f"screenshot: {screenshot_path.relative_to(ROOT)}")
    print(f"Markdown report: {markdown_path.relative_to(ROOT)}")
    print(f"JSON report: {json_path.relative_to(ROOT)}")
    if completed.returncode:
        print(
            f"note: 1983 exited {completed.returncode} after writing telemetry; "
            "host configuration/RTC persistence errors do not invalidate the guest capture",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
