#!/usr/bin/env python3
"""Collect reproducible GEMBENCH MSX2 baseline measurements.

The static half reads build/distribution artifacts.  The optional runtime half
parses 1983's ``--dump-state`` and page-3 diagnostic dump output. Keeping
the parser here makes the saved JSON useful to CI and future size comparisons,
instead of leaving the baseline as prose copied from a terminal session.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
from typing import Any


APP_BANK_START = 0x4000
APP_LOAD_LIMIT = 0x7F00
APP_LOAD_CAPACITY = APP_LOAD_LIMIT - APP_BANK_START
MAPPER_SEGMENT_BYTES = 16 * 1024
TARGET_MAPPER_KIB = 512
TARGET_MAPPER_SEGMENTS = TARGET_MAPPER_KIB * 1024 // MAPPER_SEGMENT_BYTES
TARGET_VRAM_BYTES = 128 * 1024
SCREEN7_FRAMEBUFFER_BYTES = 512 * 212 // 2
SCREEN7_POINTER_PATTERN_BYTES = 64
SCREEN7_POINTER_COLOUR_BYTES = 32
SCREEN7_POINTER_ATTRIBUTE_BYTES = 9
SCREEN7_POINTER_RESOURCE_BYTES = (
    SCREEN7_POINTER_PATTERN_BYTES
    + SCREEN7_POINTER_COLOUR_BYTES
    + SCREEN7_POINTER_ATTRIBUTE_BYTES
)

GLUE_DUMP_START = 0xC018
GLUE_DUMP_LENGTH = 0xC04C - GLUE_DUMP_START
MSX_TPASEG = 0xC018
MSX_TOTSEG = 0xC019
MSX_FREESEG = 0xC01A
MSX_PAGE_DATA = 0xC020
BASELINE_PHASE = 0xC02A
BASELINE_STACK_MAX = 0xC02B
BASELINE_STACK_FAULT = 0xC02C
BASELINE_COOKIE = 0xC02D
BASELINE_FULL_START = 0xC040
BASELINE_FULL_END = 0xC043
BASELINE_DAMAGE_START = 0xC046
BASELINE_DAMAGE_END = 0xC049
BASELINE_COOKIE_VALUE = 0xB7
BASELINE_TIMER_HZ = 16_384
BASELINE_DAMAGE_RECT = {"x": 32, "y": 48, "width": 40, "height": 80}
WM_MAXWIN = 8

RAM_LINE_RE = re.compile(r"^([0-9A-Fa-f]{4}):((?: [0-9A-Fa-f]{2})+)$")


class BaselineError(ValueError):
    """Raised when baseline inputs are missing or malformed."""


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(128 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def relative_name(root: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return path.as_posix()


def artifact(root: Path, path: Path, kind: str) -> dict[str, Any]:
    return {
        "kind": kind,
        "path": relative_name(root, path),
        "bytes": path.stat().st_size,
        "sha256": sha256(path),
    }


def read_msx_mode(config_path: Path) -> int:
    for raw_line in config_path.read_text(encoding="ascii").splitlines():
        key, separator, value = raw_line.partition("=")
        if separator and key.strip().upper() == "MSXMODE":
            try:
                return int(value.strip(), 10)
            except ValueError as exc:
                raise BaselineError(f"invalid MSXMODE in {config_path}") from exc
    raise BaselineError(f"MSXMODE is missing from {config_path}")


def collect_static(root: Path) -> dict[str, Any]:
    card = root / "QA" / "MSX" / "CARD"
    app_dir = card / "GBENCH"
    config_path = card / "GEOBENCH.CFG"
    if not app_dir.is_dir():
        raise BaselineError(f"missing staged application directory: {app_dir}")
    if not config_path.is_file():
        raise BaselineError(f"missing staged configuration: {config_path}")

    apps: list[dict[str, Any]] = []
    for path in sorted(app_dir.glob("*.APP")):
        size = path.stat().st_size
        apps.append(
            {
                "name": path.stem,
                "path": relative_name(root, path),
                "bytes": size,
                "load_headroom_bytes": APP_LOAD_CAPACITY - size,
                "sha256": sha256(path),
            }
        )
    if not apps:
        raise BaselineError(f"no staged applications found in {app_dir}")

    artifact_specs = (
        (root / "build" / "msx" / "GBKERN6.RAW", "screen-6-kernel"),
        (root / "build" / "msx" / "GBKERN7.RAW", "screen-7-kernel"),
        (root / "build" / "msx" / "GBSCHED.RAW", "scheduler"),
        (card / "GBMSX6.COM", "screen-6-loader-and-kernel"),
        (card / "GBMSX7.COM", "screen-7-loader-and-kernel"),
        (root / "build" / "examples" / "hello-dialog.gbr", "example-gbr"),
    )
    artifacts = [artifact(root, path, kind) for path, kind in artifact_specs if path.is_file()]

    return {
        "target": {
            "machine": "Omega MSX2",
            "cpu_hz_approx": 3_579_545,
            "mapper_kib": TARGET_MAPPER_KIB,
            "mapper_segments": TARGET_MAPPER_SEGMENTS,
            "vram_bytes": TARGET_VRAM_BYTES,
            "screen_mode": read_msx_mode(config_path),
        },
        "app_bank": {
            "start": APP_BANK_START,
            "load_limit": APP_LOAD_LIMIT,
            "load_capacity_bytes": APP_LOAD_CAPACITY,
        },
        "vram_model": {
            "screen7_framebuffer_bytes": SCREEN7_FRAMEBUFFER_BYTES,
            "persistent_pointer_resource_bytes": SCREEN7_POINTER_RESOURCE_BYTES,
            "persistent_save_under_bytes": 0,
            "persistent_resource_cache_bytes": 0,
            "notes": (
                "The MSX2 pointer uses V9938 sprites, so it has no VRAM save-under. "
                "Fonts, icons, and backdrop sources remain in RAM and are rendered into "
                "the framebuffer rather than retained as a separate VRAM cache."
            ),
        },
        "artifacts": artifacts,
        "applications": apps,
    }


def parse_memory_dump(text: str) -> dict[int, int]:
    memory: dict[int, int] = {}
    for raw_line in text.splitlines():
        match = RAM_LINE_RE.match(raw_line.strip())
        if not match:
            continue
        address = int(match.group(1), 16)
        for offset, value in enumerate(match.group(2).split()):
            memory[address + offset] = int(value, 16)
    return memory


def parse_state(text: str) -> dict[str, Any]:
    state_line = next(
        (line.strip() for line in text.splitlines() if line.startswith("state frame=")),
        None,
    )
    if state_line is None:
        raise BaselineError("1983 log has no --dump-state line")
    fields: dict[str, str] = {}
    for token in state_line.removeprefix("state ").split():
        key, separator, value = token.partition("=")
        if separator:
            fields[key] = value
    required = {
        "frame",
        "pc",
        "sp",
        "mapper",
        "cycles",
        "instructions",
        "vram_nonzero",
        "vdp_r0",
        "vdp_r1",
    }
    missing = sorted(required - fields.keys())
    if missing:
        raise BaselineError(f"1983 state line is missing: {', '.join(missing)}")
    try:
        mapper = [int(value, 16) for value in fields["mapper"].split(",")]
        if len(mapper) != 4:
            raise ValueError
        return {
            "frame": int(fields["frame"], 10),
            "pc": int(fields["pc"], 16),
            "sp": int(fields["sp"], 16),
            "primary_slot": int(fields.get("slot", "0"), 16),
            "secondary_slot": int(fields.get("subslot", "0"), 16),
            "mapper_registers": mapper,
            "cycles": int(fields["cycles"], 10),
            "instructions": int(fields["instructions"], 10),
            "vram_nonzero_bytes": int(fields["vram_nonzero"], 10),
            "vdp_r0": int(fields["vdp_r0"], 16),
            "vdp_r1": int(fields["vdp_r1"], 16),
        }
    except ValueError as exc:
        raise BaselineError("1983 state line contains an invalid number") from exc


def byte_at(memory: dict[int, int], address: int) -> int | None:
    return memory.get(address)


def bcd_byte(value: int | None) -> int | None:
    if value is None or value & 0x0F > 9 or value >> 4 > 9:
        return None
    return (value >> 4) * 10 + (value & 0x0F)


def rtc_seconds_at(memory: dict[int, int], address: int) -> int | None:
    second = bcd_byte(byte_at(memory, address))
    minute = bcd_byte(byte_at(memory, address + 1))
    hour = bcd_byte(byte_at(memory, address + 2))
    if second is None or minute is None or hour is None:
        return None
    if second >= 60 or minute >= 60 or hour >= 24:
        return None
    return hour * 3600 + minute * 60 + second


def rtc_elapsed_ticks(start: int | None, end: int | None) -> int | None:
    if start is None or end is None:
        return None
    return (end - start) % (24 * 60 * 60)


def collect_runtime(log_path: Path, require_probes: bool = False) -> dict[str, Any]:
    text = log_path.read_text(encoding="utf-8", errors="replace")
    runtime = parse_state(text)
    memory = parse_memory_dump(text)
    total_segments = byte_at(memory, MSX_TOTSEG)
    free_segments_at_entry = byte_at(memory, MSX_FREESEG)
    if free_segments_at_entry is None:
        app_pages = None
    else:
        # One segment is allocated for PAGE_DATA before the pool is built. The
        # pool then reuses the TPA segment and allocates at most seven more.
        app_pages = 1 + min(WM_MAXWIN - 1, max(0, free_segments_at_entry - 1))
    probes: dict[str, Any] | None = None
    if byte_at(memory, BASELINE_COOKIE) == BASELINE_COOKIE_VALUE:
        full_ticks = rtc_elapsed_ticks(
            rtc_seconds_at(memory, BASELINE_FULL_START),
            rtc_seconds_at(memory, BASELINE_FULL_END),
        )
        damage_ticks = rtc_elapsed_ticks(
            rtc_seconds_at(memory, BASELINE_DAMAGE_START),
            rtc_seconds_at(memory, BASELINE_DAMAGE_END),
        )
        probes = {
            "phase": byte_at(memory, BASELINE_PHASE),
            "scheduler_stack_high_water_bytes": byte_at(memory, BASELINE_STACK_MAX),
            "scheduler_stack_fault": byte_at(memory, BASELINE_STACK_FAULT),
            "full_repaint_ticks": full_ticks,
            "damage_repaint_ticks": damage_ticks,
            "full_repaint_microseconds": (
                round(full_ticks * 1_000_000 / BASELINE_TIMER_HZ, 2)
                if full_ticks is not None
                else None
            ),
            "damage_repaint_microseconds": (
                round(damage_ticks * 1_000_000 / BASELINE_TIMER_HZ, 2)
                if damage_ticks is not None
                else None
            ),
        }
    runtime.update(
        {
            "mapper_total_segments": total_segments,
            "mapper_free_segments_at_entry": free_segments_at_entry,
            "tpa_segment": byte_at(memory, MSX_TPASEG),
            "page_data_segment": byte_at(memory, MSX_PAGE_DATA),
            "app_pool_pages": app_pages,
            "idle_busy_app_pages": 1 if app_pages else None,
            # PAGE_DATA consumes one ALL_SEG allocation.  The app pool contains
            # the existing TPA segment plus APP_NPAGES-1 ALL_SEG allocations,
            # hence the number held from DOS is exactly APP_NPAGES.
            "mapper_segments_held_by_gembench": app_pages,
            "screen7_register_baseline": (
                runtime["vdp_r0"] == 0x0A and runtime["vdp_r1"] == 0x62
            ),
            "diagnostic_probes": probes,
            "log": log_path.as_posix(),
        }
    )
    errors: list[str] = []
    if not runtime["screen7_register_baseline"]:
        errors.append(
            f"VDP registers are R0=0x{runtime['vdp_r0']:02X}, "
            f"R1=0x{runtime['vdp_r1']:02X}, not the Screen 7 desktop baseline"
        )
    if total_segments != TARGET_MAPPER_SEGMENTS:
        errors.append(
            f"mapper segment count is {total_segments}, expected {TARGET_MAPPER_SEGMENTS}"
        )
    if (
        free_segments_at_entry is None
        or total_segments is None
        or not 1 <= free_segments_at_entry <= total_segments
    ):
        errors.append(f"implausible or missing free mapper segment count: {free_segments_at_entry}")
    if runtime["page_data_segment"] is None:
        errors.append("PAGE_DATA segment was not captured")
    if app_pages is None or not 1 <= app_pages <= WM_MAXWIN:
        errors.append(f"implausible or missing app-pool size: {app_pages}")
    if require_probes:
        if probes is None:
            errors.append("diagnostic probe cookie was not captured")
        else:
            if probes["phase"] != 4:
                errors.append(f"diagnostic probe phase is {probes['phase']}, expected 4")
            if not probes["scheduler_stack_high_water_bytes"]:
                errors.append("scheduler stack high-water is zero or missing")
            if probes["scheduler_stack_fault"] != 0:
                errors.append(
                    f"scheduler stack fault is {probes['scheduler_stack_fault']}, expected 0"
                )
            if not probes["full_repaint_ticks"]:
                errors.append("full repaint timing is zero or missing")
            if not probes["damage_repaint_ticks"]:
                errors.append("damage repaint timing is zero or missing")
    if errors:
        raise BaselineError("guest did not reach a healthy GEMBENCH desktop: " + "; ".join(errors))
    return runtime


def collect_report(
    root: Path,
    emulator_log: Path | None = None,
    *,
    static: dict[str, Any] | None = None,
    require_probes: bool = False,
) -> dict[str, Any]:
    report: dict[str, Any] = {
        "schema_version": 1,
        "static": collect_static(root) if static is None else static,
        "runtime": None,
        "repaint_timing": {
            "status": "not-instrumented",
            "notes": (
                "1983 currently exposes final machine counters, not cycle markers around "
                "individual repaint calls. A dedicated diagnostic probe is required for "
                "full and damage-limited repaint latency."
            ),
        },
    }
    if emulator_log is not None:
        runtime = collect_runtime(emulator_log, require_probes=require_probes)
        runtime["log"] = relative_name(root, emulator_log)
        report["runtime"] = runtime
        probes = runtime["diagnostic_probes"]
        if probes is not None:
            report["repaint_timing"] = {
                "status": "captured",
                "timer_hz": BASELINE_TIMER_HZ,
                "timer": "RP-5C01 seconds-test clock",
                "full_ticks": probes["full_repaint_ticks"],
                "full_microseconds": probes["full_repaint_microseconds"],
                "damage_ticks": probes["damage_repaint_ticks"],
                "damage_microseconds": probes["damage_repaint_microseconds"],
                "damage_rect": BASELINE_DAMAGE_RECT,
                "notes": (
                    "Each result is one diagnostic-build sample from the 16,384 Hz "
                    "RTC seconds-test clock. Packed 24-hour start/end values give an "
                    "unambiguous 5.27-second window. Release builds do not link or run "
                    "this probe. The openMSX reference comparison is recorded in "
                    "docs/gembench/OPENMSX-VALIDATION.md."
                ),
            }
    return report


def format_hex(value: int | None, width: int = 4) -> str:
    return "not captured" if value is None else f"`0x{value:0{width}X}`"


def render_markdown(report: dict[str, Any]) -> str:
    static = report["static"]
    target = static["target"]
    runtime = report["runtime"]
    lines = [
        "# GEMBENCH MSX2 baseline",
        "",
        "This report is generated by `tools/gembench_baseline.py`. It records the",
        "pre-GBR-runtime baseline used to evaluate later resident and app-linked changes.",
        "",
        "## Target",
        "",
        f"- Machine: {target['machine']} at approximately {target['cpu_hz_approx']:,} Hz",
        f"- Mapper RAM: {target['mapper_kib']} KiB ({target['mapper_segments']} x 16 KiB segments)",
        f"- VRAM: {target['vram_bytes'] // 1024} KiB",
        f"- Staged video mode: Screen {target['screen_mode']}",
        "",
        "## Build artifacts",
        "",
        "| Artifact | Bytes | SHA-256 |",
        "| --- | ---: | --- |",
    ]
    for item in static["artifacts"]:
        lines.append(
            f"| `{item['path']}` ({item['kind']}) | {item['bytes']:,} | `{item['sha256']}` |"
        )
    app_bank = static["app_bank"]
    lines.extend(
        [
            "",
            "## Application-bank headroom",
            "",
            f"The loader range is {format_hex(app_bank['start'])} through "
            f"{format_hex(app_bank['load_limit'])}, giving {app_bank['load_capacity_bytes']:,} "
            "bytes before the loader guard.",
            "",
            "| Application | Bytes | Load headroom |",
            "| --- | ---: | ---: |",
        ]
    )
    for app in sorted(static["applications"], key=lambda item: item["load_headroom_bytes"]):
        lines.append(
            f"| {app['name']} | {app['bytes']:,} | {app['load_headroom_bytes']:,} |"
        )

    vram = static["vram_model"]
    lines.extend(
        [
            "",
            "## Mapper and VRAM",
            "",
            f"- Screen 7 framebuffer: {vram['screen7_framebuffer_bytes']:,} bytes.",
            f"- Persistent pointer resource: {vram['persistent_pointer_resource_bytes']} bytes "
            "(64 pattern + 32 colour + 9 attribute bytes).",
            f"- Persistent VRAM save-under: {vram['persistent_save_under_bytes']} bytes.",
            f"- Persistent resource cache outside the framebuffer: "
            f"{vram['persistent_resource_cache_bytes']} bytes.",
        ]
    )
    if runtime:
        lines.extend(
            [
                f"- Mapper segments held from DOS at idle: "
                f"{runtime['mapper_segments_held_by_gembench'] if runtime['mapper_segments_held_by_gembench'] is not None else 'not captured'}.",
                f"- Mapper segments total / free at GEMBENCH entry: "
                f"{runtime['mapper_total_segments']} / {runtime['mapper_free_segments_at_entry']}.",
                f"- Derived app-pool pages / idle busy pages: "
                f"{runtime['app_pool_pages'] if runtime['app_pool_pages'] is not None else 'not captured'} / "
                f"{runtime['idle_busy_app_pages'] if runtime['idle_busy_app_pages'] is not None else 'not captured'}.",
                f"- Non-zero VRAM bytes in the captured desktop frame: {runtime['vram_nonzero_bytes']:,} "
                "(an occupancy signal, not an allocation limit).",
            ]
        )
    lines.extend(["", vram["notes"]])

    lines.extend(["", "## Runtime telemetry", ""])
    if runtime is None:
        lines.append(
            "No emulator log was supplied. Run `make gembench-baseline-1983` to capture it."
        )
    else:
        probes = runtime["diagnostic_probes"]
        lines.extend(
            [
                f"- Capture frame: {runtime['frame']:,}",
                f"- PC / SP: {format_hex(runtime['pc'])} / {format_hex(runtime['sp'])}",
                f"- VDP R0 / R1: {format_hex(runtime['vdp_r0'], 2)} / {format_hex(runtime['vdp_r1'], 2)}",
                f"- Screen 7 register baseline matched: {'yes' if runtime['screen7_register_baseline'] else 'no'}",
                f"- Page-1 TPA / PAGE_DATA segments: {runtime['tpa_segment']} / {runtime['page_data_segment']}",
            ]
        )
        if probes is None:
            lines.append(
                "- Scheduler stack high-water: not captured; run the diagnostic probe target."
            )
        else:
            lines.extend(
                [
                    f"- Scheduler stack high-water: {probes['scheduler_stack_high_water_bytes']} bytes.",
                    f"- Scheduler stack fault: {probes['scheduler_stack_fault']}.",
                    f"- Diagnostic probe phase: {probes['phase']} (4 means complete).",
                ]
            )

    repaint = report["repaint_timing"]
    lines.extend(["", "## Repaint timing", "", f"Status: **{repaint['status']}**.", ""])
    if repaint["status"] == "captured":
        rect = repaint["damage_rect"]
        lines.extend(
            [
                f"- Full desktop: {repaint['full_ticks']:,} ticks "
                f"({repaint['full_microseconds']:,.2f} us).",
                f"- Damage rectangle ({rect['x']}, {rect['y']}, {rect['width']}, "
                f"{rect['height']}): {repaint['damage_ticks']:,} ticks "
                f"({repaint['damage_microseconds']:,.2f} us).",
                f"- Timer: {repaint['timer']} at {repaint['timer_hz']:,} Hz.",
                "",
            ]
        )
    lines.extend(
        [
            repaint["notes"],
            "",
            "## Reproduce",
            "",
            "```sh",
            "make gembench-baseline-1983",
            "make gembench-baseline-probes-1983",
            "```",
            "",
        ]
    )
    return "\n".join(lines)


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--emulator-log", type=Path)
    parser.add_argument("--markdown", type=Path)
    parser.add_argument("--json", dest="json_path", type=Path)
    parser.add_argument("--require-runtime", action="store_true")
    parser.add_argument("--require-probes", action="store_true")
    parser.add_argument("--static-json", type=Path)
    args = parser.parse_args(argv)
    if args.markdown is None and args.json_path is None:
        parser.error("at least one of --markdown or --json is required")
    if args.require_runtime and args.emulator_log is None:
        parser.error("--require-runtime requires --emulator-log")
    if args.require_probes and args.emulator_log is None:
        parser.error("--require-probes requires --emulator-log")
    try:
        static = None
        if args.static_json is not None:
            source_report = json.loads(args.static_json.read_text(encoding="utf-8"))
            static = source_report.get("static")
            if not isinstance(static, dict):
                raise BaselineError(f"static section is missing from {args.static_json}")
        report = collect_report(
            args.root,
            args.emulator_log,
            static=static,
            require_probes=args.require_probes,
        )
    except (BaselineError, OSError, json.JSONDecodeError) as exc:
        print(f"baseline error: {exc}", file=sys.stderr)
        return 1
    if args.markdown is not None:
        write_text(args.markdown, render_markdown(report))
    if args.json_path is not None:
        write_text(args.json_path, json.dumps(report, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
