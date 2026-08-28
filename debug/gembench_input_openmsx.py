#!/usr/bin/env python3
"""Repeat and validate GEMBENCH's input-response probe under openMSX."""

from __future__ import annotations

import json
import os
from pathlib import Path
import statistics
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "debug" / "gembench_input_openmsx.tcl"
OUTPUT_DIR = ROOT / "build" / "baseline"
RUN_COUNT = 2
INTEGER_FIELDS = {
    "POINTER_BEFORE_X",
    "POINTER_BEFORE_Y",
    "POINTER_AFTER_X",
    "POINTER_AFTER_Y",
    "INPUT_FLAGS",
    "INPUT_KEY",
    "RUNNABLE_TASKS",
    "STACK_MAX",
    "STACK_FAULT",
    "PROBE_PHASE",
    "POINTER_ARM_TICK",
    "POINTER_ACK_TICK",
    "KEYBOARD_ARM_TICK",
    "KEYBOARD_ACK_TICK",
}
FLOAT_FIELDS = {"POINTER_RESPONSE_MS", "KEYBOARD_RESPONSE_MS"}


class InputProbeError(RuntimeError):
    """Raised when an openMSX input run is missing or unhealthy."""


def parse_result(path: Path) -> dict[str, object]:
    values: dict[str, object] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        key, separator, value = line.partition("=")
        if not separator:
            continue
        if key in INTEGER_FIELDS:
            values[key.lower()] = int(value, 10)
        elif key in FLOAT_FIELDS:
            values[key.lower()] = float(value)
        else:
            values[key.lower()] = value
    required = {field.lower() for field in INTEGER_FIELDS | FLOAT_FIELDS | {"STATUS"}}
    missing = sorted(required - values.keys())
    if missing:
        raise InputProbeError(f"{path}: missing fields: {', '.join(missing)}")
    if values["status"] != "PASS":
        raise InputProbeError(f"{path}: {values['status']}")
    if values["input_flags"] != 7:
        raise InputProbeError(f"{path}: input flags are {values['input_flags']}, expected 7")
    if values["input_key"] != ord("b"):
        raise InputProbeError(f"{path}: key value is {values['input_key']}, expected 98")
    if values["runnable_tasks"] != 3:
        raise InputProbeError(
            f"{path}: runnable task count is {values['runnable_tasks']}, expected 3"
        )
    if values["stack_max"] <= 0 or values["stack_fault"] != 0:
        raise InputProbeError(f"{path}: unhealthy scheduler stack telemetry")
    if values["probe_phase"] != 4:
        raise InputProbeError(f"{path}: repaint probe phase is not complete")
    if (
        values["pointer_before_x"] == values["pointer_after_x"]
        and values["pointer_before_y"] == values["pointer_after_y"]
    ):
        raise InputProbeError(f"{path}: pointer sprite did not visibly move")
    for field in ("pointer_response_ms", "keyboard_response_ms"):
        response = values[field]
        if not isinstance(response, float) or not 0 < response <= 250:
            raise InputProbeError(f"{path}: implausible {field}: {response}")
    return values


def main() -> int:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    runs: list[dict[str, object]] = []
    for run_number in range(1, RUN_COUNT + 1):
        result_path = OUTPUT_DIR / f"openmsx-input-{run_number}.log"
        result_path.unlink(missing_ok=True)
        environment = os.environ.copy()
        environment.update(
            {
                "MSX_UNAPI": "0",
                "MSX_HEADLESS": "1",
                "MSX_SCRIPT": str(SCRIPT.relative_to(ROOT)),
                "GEMBENCH_INPUT_OUTPUT": str(result_path),
            }
        )
        completed = subprocess.run(
            [str(ROOT / "tools" / "run_msx.sh")],
            cwd=ROOT,
            env=environment,
            text=True,
            capture_output=True,
            check=False,
            timeout=180,
        )
        if completed.returncode:
            raise InputProbeError(
                f"openMSX run {run_number} exited {completed.returncode}: "
                f"{completed.stdout}{completed.stderr}"
            )
        if not result_path.is_file():
            raise InputProbeError(f"openMSX run {run_number} produced no result log")
        run = parse_result(result_path)
        run["run"] = run_number
        runs.append(run)

    pointer_values = [float(run["pointer_response_ms"]) for run in runs]
    keyboard_values = [float(run["keyboard_response_ms"]) for run in runs]
    report = {
        "schema_version": 1,
        "emulator": "openMSX 21.0",
        "machine": "Philips NMS 8250, PAL, V9938",
        "runs": runs,
        "pointer_response_ms_mean": round(statistics.mean(pointer_values), 3),
        "keyboard_response_ms_mean": round(statistics.mean(keyboard_values), 3),
    }
    json_path = OUTPUT_DIR / "openmsx-input.json"
    json_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"openMSX input report: {json_path.relative_to(ROOT)}")
    for run in runs:
        print(
            f"run {run['run']}: pointer {run['pointer_response_ms']:.3f} ms, "
            f"keyboard {run['keyboard_response_ms']:.3f} ms"
        )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (InputProbeError, OSError, subprocess.SubprocessError, ValueError) as exc:
        print(f"input probe error: {exc}", file=sys.stderr)
        raise SystemExit(1)
