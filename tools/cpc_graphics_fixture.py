"""Step-3B vectors and independent pixel oracle; not the universal ABI.

Generated assembly is input data only. The Z80 implements address translation,
clipping and pointer composition independently of this pixel-level oracle.
"""
from __future__ import annotations

from pathlib import Path
import struct

GRAPHICS_VARIANTS = {"graphics": None, "graphics-bad-clip": "FAULT_CLIP",
                     "graphics-bad-cursor": "FAULT_CURSOR", "graphics-bad-copy": "FAULT_COPY"}
CURSOR = ("1.......", "13......", "133.....", "1333....",
          "13333...", "133333..", "11133111", "...13...")


def descriptor(op: int, x=0, y=0, w=0, h=0, clip=(0, 0, 80, 200),
               pen=0, buffer=0x4100, capacity=64, px=0) -> bytes:
    return bytes((op, x, y, w, h, *clip, pen)) + struct.pack("<HHH", buffer, capacity, px)


def cases() -> list[dict]:
    result = []
    def add(name, record, status=0, capture=True, pointer=0x4000, length=16):
        result.append(dict(name=name, record=record, status=status, capture=capture,
                           pointer=pointer, length=length, irq=len(result) & 1))
    add("fill", descriptor(1, 5, 10, 20, 12, pen=2))
    add("left-top-clip", descriptor(1, 0, 0, 30, 40, clip=(10, 15, 20, 20), pen=3))
    add("save-clipped", descriptor(2, 72, 193, 14, 16, capacity=56))
    add("overwrite-saved", descriptor(1, 72, 193, 14, 16, pen=3))
    add("restore-clipped", descriptor(3, 72, 193, 14, 16, capacity=56))
    add("overflow-right-bottom", descriptor(1, 70, 190, 250, 250, pen=1))
    add("outside", descriptor(1, 250, 250, 255, 255, pen=3), capture=False)
    add("zero-width", descriptor(1, 0, 0, 0, 255), capture=False)
    add("zero-height", descriptor(1, 0, 0, 255, 0), capture=False)
    add("empty-clip", descriptor(1, 0, 0, 255, 255, clip=(0, 0, 0, 0)))
    add("show-origin", descriptor(4, px=0, y=0))
    add("duplicate-show", descriptor(4, px=0, y=0))
    for px, y in ((41, 37), (82, 49), (123, 73)):
        add(f"phase-{px % 4}", descriptor(5, px=px, y=y))
    add("unrelated-draw", descriptor(1, 1, 170, 8, 8, pen=3))
    add("draw-under-pointer", descriptor(1, 30, 74, 3, 3, pen=1))
    add("hide-updated", descriptor(6))
    add("duplicate-hide", descriptor(6))
    for px, y in ((319, 199), (318, 198), (316, 196), (315, 195)):
        add(f"edge-{px}", descriptor(5, px=px, y=y))
    add("hide-edge", descriptor(6))
    for pointer in (0x0000, 0x3FFF, 0x7EF1, 0xC030, 0xFFFF):
        add(f"bad-pointer-{pointer:04x}", descriptor(1, 1, 1, 1, 1), 1,
            capture=False, pointer=pointer)
    for length in (0, 15, 17, 0xFFFF):
        add(f"bad-length-{length}", descriptor(1, 1, 1, 1, 1), 1,
            capture=False, length=length)
    add("bad-operation", descriptor(255), 2, capture=False)
    add("bad-pen", descriptor(1, 0, 0, 1, 1, pen=4), 3, capture=False)
    add("oversized-transfer", descriptor(2, 0, 0, 80, 200, capacity=65535), 5, capture=False)
    for op in (2, 3):
        add(f"small-buffer-{op}", descriptor(op, 72, 193, 14, 16, capacity=55), 5, capture=False)
        for buffer in (0x3FFF, 0x7EFF, 0xC030, 0xFFF0):
            add(f"bad-buffer-{op}-{buffer:04x}", descriptor(op, 72, 193, 14, 16, buffer=buffer),
                4, capture=False)
    add("bad-pointer-x", descriptor(5, px=320), 4, capture=False)
    add("bad-pointer-y", descriptor(5, px=0, y=200), 4)
    add("last-valid-descriptor", descriptor(1, 79, 199, 255, 255, pen=2), pointer=0x7EF0)
    return result


def emit_vectors(path: Path) -> None:
    rows = ["graphics_cases"]
    for case in cases():
        packet = case["record"] + bytes((case["status"], case["capture"]))
        packet += struct.pack("<HHB", case["pointer"], case["length"], case["irq"])
        rows += [f"; {case['name']}", "db " + ",".join(f"#{b:02X}" for b in packet)]
    rows += [f"graphics_case_count equ {len(cases())}", "graphics_case_size equ 23",
             f"graphics_capture_count equ {1 + sum(c['capture'] for c in cases())}",
             "cursor_phases"]
    # Four pre-shifted phases of an 8x8 fixture pointer, three CPC bytes/row.
    for phase in range(4):
        data = []
        for line in CURSOR:
            pixels = "." * phase + line + "." * (4 - phase)
            for col in range(3):
                mask, ink = 255, 0
                for sub, char in enumerate(pixels[col * 4:col * 4 + 4]):
                    if char != ".":
                        mask &= ~(0x88 >> sub)
                        pen = int(char)
                        ink |= ((pen & 1) << (7 - sub)) | ((pen >> 1) << (3 - sub))
                data += [mask, ink]
        rows.append("db " + ",".join(f"#{b:02X}" for b in data))
    path.write_text("\n".join(rows) + "\n")


def address(x: int, y: int) -> int:
    return (y % 8) * 2048 + (y // 8) * 80 + x // 4


def put_pixel(frame: bytearray, x: int, y: int, pen: int) -> None:
    offset, sub = address(x, y), x % 4
    mask = 0x88 >> sub
    frame[offset] = (frame[offset] & ~mask) | ((pen & 1) << (7 - sub)) | ((pen >> 1) << (3 - sub))


def expected_frames() -> tuple[list[tuple[str, bytes]], bytes]:
    frame = bytearray((a >> 8) ^ (a & 255) for a in range(0xC000, 0x10000))
    frames = [("initial", bytes(frame))]
    saved = b""
    pointer = None
    for case in cases():
        d = case["record"]
        op, x, y, w, h, cx, cy, cw, ch, pen = d[:10]
        if not case["status"]:
            left, top = max(x, cx), max(y, cy)
            right, bottom = min(x + w, cx + cw, 80), min(y + h, cy + ch, 200)
            if op in (1, 2, 3) and right > left and bottom > top:
                if op == 2:
                    saved = bytes(frame[address(px * 4, py)]
                                  for py in range(top, bottom) for px in range(left, right))
                else:
                    offset = 0
                    for py in range(top, bottom):
                        for px in range(left, right):
                            if op == 1:
                                for sub in range(4):
                                    put_pixel(frame, px * 4 + sub, py, pen)
                            else:
                                frame[address(px * 4, py)] = saved[offset]
                                offset += 1
            elif op == 6:
                pointer = None
            elif op == 5 or (op == 4 and pointer is None):
                pointer = (int.from_bytes(d[14:16], "little"), y)
        visible = bytearray(frame)
        if pointer is not None:
            for dy, line in enumerate(CURSOR):
                for dx, char in enumerate(line):
                    px, py = pointer[0] + dx, pointer[1] + dy
                    if char != "." and px < 320 and py < 200:
                        put_pixel(visible, px, py, int(char))
        if case["capture"]:
            frames.append((case["name"], bytes(visible)))
    return frames, saved


def verify_graphics(header: bytes, ram: bytes, sym: dict[str, int], raw: bytes) -> dict:
    def word(name):
        return int.from_bytes(ram[sym[name]:sym[name] + 2], "little")
    if ram[sym["magic"]:sym["magic"] + 6] != b"CPF3B\x01":
        raise AssertionError("wrong graphics probe signature")
    if (ram[sym["phase"]], ram[sym["failure"]]) != (0xA5, 0):
        raise AssertionError(f"graphics phase={ram[sym['phase']]:02X} failure={ram[sym['failure']]}")
    if len(ram) != 512 * 1024 or ram[sym["rounds_done"]] != 50:
        raise AssertionError("incomplete graphics workload")
    if word("request_count") != len(cases()) * 50:
        raise AssertionError("incomplete graphics request count")
    if word("irq_count") < sum(c["irq"] for c in cases()) * 50:
        raise AssertionError("missing interrupt-enabled request coverage")
    if (ram[sym["bank_shadow"]], header[0x41], header[0x40]) != (0xC0, 0, 0x0D):
        raise AssertionError("graphics bank/ROM/mode state not restored")
    if header[0x1B:0x1D] != b"\0\0" or header[0x25] != 1:
        raise AssertionError("graphics final interrupt state changed")
    if word("final_sp") != sym["main_stack_top"] or int.from_bytes(header[0x21:0x23], "little") != sym["main_stack_top"]:
        raise AssertionError("graphics foreground stack unbalanced")
    for stem in ("main", "irq", "request", "pointer", "transfer"):
        for side in ("low", "high"):
            start = sym[f"{stem}_guard_{side}"]
            if ram[start:start + 16] != b"\xD7" * 16:
                raise AssertionError(f"{stem} {side} guard damaged")
    for stem in ("main", "irq"):
        stack = ram[sym[f"{stem}_stack"]:sym[f"{stem}_stack_top"]]
        used = len(stack) - next((i for i, b in enumerate(stack) if b != 0xA6), len(stack))
        if used != word(f"{stem}_stack_used") or not 0 < used < len(stack):
            raise AssertionError(f"invalid graphics {stem} stack measurement")
    if ram[0x8000:sym["code_end"]] != raw[:sym["code_end"] - 0x8000]:
        raise AssertionError("graphics resident code changed")
    frames, saved = expected_frames()
    if ram[sym["capture_count"]] != len(frames):
        raise AssertionError("missing graphics checkpoints")
    for index, (name, expected) in enumerate(frames):
        actual = ram[0x10000 + index * 0x4000:0x10000 + (index + 1) * 0x4000]
        if actual != expected:
            offset = next(i for i, (a, e) in enumerate(zip(actual, expected)) if a != e)
            raise AssertionError(f"framebuffer checkpoint {name}: {0xC000 + offset:04X} "
                                 f"got {actual[offset]:02X}, expected {expected[offset]:02X}")
    if ram[0xC000:0x10000] != frames[-1][1]:
        raise AssertionError("final framebuffer differs from last checkpoint")
    if ram[0x7C000:0x80000] != b"\xA9" * 0x4000:
        raise AssertionError("service page unexpectedly modified")
    # Producer writes only two descriptor locations and the actual save span.
    expected_caller = bytearray(b"\x5A" * 0x4000)
    expected_caller[:16] = cases()[-1]["record"]
    expected_caller[0x3EF0:0x3F00] = cases()[-1]["record"]
    expected_caller[0x100:0x100 + len(saved)] = saved
    if ram[0x4000:0x8000] != expected_caller:
        raise AssertionError("caller page/canonical save buffer changed outside permitted spans")
    traces = {}
    for index, (name, _) in enumerate(frames):
        start = sym["trace_records"] + index * 4
        traces[name] = struct.unpack_from("<HH", ram, start)
    for current, previous in (("duplicate-show", "show-origin"),
                              ("unrelated-draw", "phase-3"),
                              ("duplicate-hide", "hide-updated")):
        if traces[current] != traces[previous]:
            raise AssertionError(f"unnecessary pointer save/restore at {current}")
    if traces["draw-under-pointer"] != tuple(n + 1 for n in traces["unrelated-draw"]):
        raise AssertionError("background update did not bracket pointer once")
    return dict(rounds=50, requests=word("request_count"), interrupts=word("irq_count"),
                checkpoints=len(frames), main_stack_bytes=word("main_stack_used"),
                irq_stack_bytes=word("irq_stack_used"), resident_code_bytes=sym["code_end"] - 0x8000,
                canonical_save_bytes=len(saved), pointer_saves=word("pointer_saves"),
                pointer_restores=word("pointer_restores"))
