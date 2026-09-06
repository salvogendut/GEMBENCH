"""Production-address drawing vectors and independent pixel/checker oracle."""
from __future__ import annotations

import struct
from pathlib import Path
from cpc_graphics_fixture import CURSOR, address, put_pixel, cases as primitive_cases
from genfont import G

DRAWING_VARIANTS = {"drawing": None, "drawing-bad-clip": "CPC_FAULT_DRAW_CLIP",
                    "drawing-bad-copy": "CPC_FAULT_DRAW_COPY"}


def line(x0, y0, x1, y1, pen=3):
    return struct.pack("<BBHHHHB", 1, 1, x0, y0, x1, y1, pen).ljust(16, b"\0")


def text_record(x, y, pen=1, paper=0, count=8, pointer=0x4500):
    return struct.pack("<BBBBBBHB", 2, 1, x, y, pen, paper, pointer, count).ljust(16, b"\0")


def timer(op, handle=0x0101, rect=(4, 5, 6, 7)):
    return struct.pack("<BBH4B", op, 1, handle, *rect).ljust(16, b"\0")


def cases():
    result = []
    def add(name, record, *, kind=1, clip=(0, 0, 80, 200), status=0, boolean=0,
            pointer=0x4400, length=16, context=0, text=b"", capture=False):
        result.append(dict(name=name, record=record, kind=kind, clip=clip, status=status,
                           boolean=boolean, pointer=pointer, length=length, context=context,
                           text=text.ljust(48, b"\0"), capture=capture, iff=len(result)&1))
    selected = {"fill", "left-top-clip", "save-clipped", "overwrite-saved", "restore-clipped",
                "overflow-right-bottom", "show-origin", "duplicate-show", "phase-1", "phase-2", "phase-3",
                "unrelated-draw", "draw-under-pointer", "hide-updated", "edge-319", "hide-edge"}
    for case in primitive_cases():
        if case["name"] in selected:
            add(case["name"], case["record"], kind=0,
                capture=case["name"] not in {"duplicate-show", "unrelated-draw", "overflow-right-bottom"})
    # All octants + horizontal, vertical and a single point; aggregate capture.
    for i, (x, y) in enumerate(((140, 83), (124, 110), (77, 115), (52, 89),
                                 (55, 64), (87, 37), (121, 40), (150, 65))):
        add(f"line-octant-{i}", line(100, 75, x, y, i%4), capture=i==7)
    add("horizontal", line(0, 199, 319, 199, 1))
    add("vertical", line(319, 199, 319, 0, 2))
    add("point", line(0, 0, 0, 0, 3), capture=True)
    add("clipped-line", line(2, 12, 300, 193), clip=(13, 22, 30, 40), capture=True)
    add("empty-clip-line", line(0, 0, 319, 199), clip=(0, 0, 0, 0), capture=True)
    # Pointer at sub-byte phase 1, text crosses its saved background.
    from cpc_graphics_fixture import descriptor
    add("text-pointer-show", descriptor(5, px=41, y=37), kind=0)
    add("text-under-pointer", text_record(10, 37, count=8), text=b"GEOBENCH", capture=True)
    add("text-pointer-hide", descriptor(6), kind=0, capture=True)
    add("partial-glyph-clip", text_record(8, 55, 3, 2, 12), text=b"ABCDEFGHIJKL",
        clip=(10, 58, 7, 3), capture=True)
    add("bottom-right-text", text_record(79, 198, 2, 1, 8), text=b"EDGE1234", capture=True)
    add("long-text", text_record(50, 90, count=48), text=b"0123456789ABCDEF"*3, capture=True)
    add("font-range", text_record(2, 140, count=5), text=bytes((1, 31, 65, 132, 255)), capture=True)
    add("text-nul", text_record(2, 152, count=5), text=b"A\0XYZ", capture=True)
    add("text-zero", text_record(0, 0, count=0, pointer=0xFFFF))
    add("bad-text-span", text_record(0, 0, count=2, pointer=0x7EFF), status=1)
    add("bad-text-count", text_record(0, 0, count=49), status=1)
    add("bad-line-x", line(0, 0, 320, 1), status=1)
    add("bad-line-y", line(0, 0, 1, 200), status=1)
    add("bad-pen", line(0, 0, 1, 1, 4), status=1)
    add("last-descriptor", line(310, 100, 318, 105), pointer=0x7EF0)
    add("bad-descriptor", line(0, 0, 1, 1), pointer=0x7EF1, status=1)
    add("bad-length", line(0, 0, 1, 1), length=15, status=1)
    add("bad-version", bytes((1, 2))+line(0, 0, 1, 1)[2:], status=6)
    add("worker-cannot-draw", line(0, 0, 319, 199), context=1, status=2, capture=True)
    add("wrong-primary", line(0, 0, 319, 199), context=2, status=2)
    add("stale-owner", line(0, 0, 319, 199), context=3, status=2)
    add("timer-publish", timer(3), boolean=1)
    add("timer-busy", timer(3), status=5)
    add("timer-any", timer(6), boolean=1)
    add("timer-wrong-owner", timer(4, 0x0102), status=4)
    add("timer-stale", timer(4, 0x0201), status=3)
    add("timer-cancel", timer(7))
    add("timer-empty", timer(6))
    add("final", line(12, 175, 72, 188), capture=True)
    assert len(result) <= 64
    assert sum(c["capture"] for c in result) <= 26
    return result


def emit_vectors(path: Path):
    rows = ["cpc_drawing_cases"]
    for c in cases():
        record = c["record"] + bytes((*c["clip"], c["kind"], c["status"], c["boolean"]))
        record += struct.pack("<HHBB", c["pointer"], c["length"], c["iff"], c["context"])
        record += c["text"]+bytes((c["capture"],))
        assert len(record) == 78
        rows += ["; "+c["name"], "db "+",".join(str(x) for x in record)]
    rows += [f"CPC_DRAW_CASES equ {len(cases())}", "CPC_DRAW_CASE_SIZE equ 78", "cursor_phases"]
    # Four phases of the already-proved pointer, byte-for-byte same encoding.
    for phase in range(4):
        data = []
        for row in CURSOR:
            pixels = "."*phase+row+"."*(4-phase)
            for col in range(3):
                mask, ink = 255, 0
                for sub, ch in enumerate(pixels[col*4:col*4+4]):
                    if ch != ".":
                        mask &= ~(0x88 >> sub)
                        pen = int(ch)
                        ink |= ((pen&1) << (7-sub)) | ((pen>>1) << (3-sub))
                data += [mask, ink]
        rows += ["db "+",".join(str(x) for x in data)]
    path.write_text("\n".join(rows)+"\n")


def expected_frames():
    frame = bytearray((a>>8) ^ (a&255) for a in range(0xC000, 0x10000))
    frames, saved, pointer = [], b"", None
    for c in cases():
        d, clip = c["record"], c["clip"]
        def visible(x, y):
            return (0 <= x < 320 and 0 <= y < 200 and
                    clip[0]*4 <= x < (clip[0]+clip[2])*4 and clip[1] <= y < clip[1]+clip[3])
        def plot(x, y, pen):
            if visible(x, y): put_pixel(frame, x, y, pen)
        if c["status"] == 0:
            if c["kind"] == 0:
                op, x, y, w, h, cx, cy, cw, ch, pen = d[:10]
                left, top = max(x, cx), max(y, cy)
                right, bottom = min(x+w, cx+cw, 80), min(y+h, cy+ch, 200)
                if op == 2:
                    saved = bytes(frame[address(px*4, py)] for py in range(top, bottom) for px in range(left, right))
                elif op in (1, 3):
                    offset = 0
                    for py in range(top, bottom):
                        for px in range(left, right):
                            if op == 1:
                                for sub in range(4): put_pixel(frame, px*4+sub, py, pen)
                            else:
                                frame[address(px*4, py)] = saved[offset]
                                offset += 1
                elif op == 6: pointer = None
                elif op == 5 or (op == 4 and pointer is None):
                    pointer = (int.from_bytes(d[14:16], "little"), y)
            elif d[0] == 1:
                x, y, endx, endy = struct.unpack_from("<4H", d, 2)
                dx, dy = abs(endx-x), abs(endy-y)
                sx, sy = (1 if x < endx else -1), (1 if y < endy else -1)
                err = dx-dy
                while True:
                    plot(x, y, d[10])
                    if (x, y) == (endx, endy): break
                    e2 = 2*err
                    if e2 >= -dy: err -= dy; x += sx
                    if e2 <= dx: err += dx; y += sy
            elif d[0] == 2:
                for i, code in enumerate(c["text"][:d[8]]):
                    if not code: break
                    art = G.get(chr(code), []) if 32 <= code <= 131 else []
                    for y in range(8):
                        for x in range(6):
                            ink = y < len(art) and x < 5 and art[y][x] == "#"
                            plot(d[2]*4+i*6+x, d[3]+y, d[4] if ink else d[5])
        visible_frame = bytearray(frame)
        if pointer is not None:
            for y, row in enumerate(CURSOR):
                for x, ch in enumerate(row):
                    px, py = pointer[0]+x, pointer[1]+y
                    if ch != "." and px < 320 and py < 200:
                        put_pixel(visible_frame, px, py, int(ch))
        if c["capture"]: frames.append((c["name"], bytes(visible_frame)))
    return frames, saved


def verify_drawing(ram: bytes, sym: dict, work: Path) -> dict:
    def byte(name): return ram[sym[name]]
    def word(name): return int.from_bytes(ram[sym[name]:sym[name]+2], "little")
    frames, saved = expected_frames()
    if byte("draw_case_count_done") != len(cases()) or byte("draw_capture_count") != len(frames):
        raise AssertionError("drawing case/capture count differs")
    for index, (name, frame) in enumerate(frames):
        base = 0x14000+index*0x4000  # allocated capture pages C5.., C4 remains worker
        if ram[base:base+16384] != frame:
            differing = next(i for i, (a,b) in enumerate(zip(ram[base:base+16384], frame)) if a != b)
            raise AssertionError(f"drawing checkpoint {name} differs at {differing:04X}")
    if ram[0xC000:0x10000] != frames[-1][1]:
        raise AssertionError("drawing final framebuffer differs")
    if ram[0x4100:0x4100+len(saved)] != saved:
        raise AssertionError("canonical block roundtrip differs")
    code = (work / "SUPPORT.RAW").read_bytes()
    base = sym["cpc_support_base"]
    observed = bytearray(ram[base:base+len(code)])
    # The shared receiver owns exactly these mutable inline request/text bytes.
    for name, size in (("up_request",16), ("up_text_copy",49)):
        at = sym[name]-base
        observed[at:at+size] = code[at:at+size]
    if observed != code:
        raise AssertionError("SUPPORT.RAW code changed")
    for at in (sym["cpc_draw_state_guard"], sym["cpc_draw_state_end"]):
        if ram[at:at+16] != b"\xD7"*16:
            raise AssertionError("drawing state guard damaged")
    font = (work / "DEFAULT.FNT").read_bytes()
    if ram[0x7C000:0x80000] != font+b"\xA9"*(16384-len(font)):
        raise AssertionError("font/service page changed")
    if byte("core_page_total") != 28 or byte("core_page_free") != 26-len(frames):
        raise AssertionError("shared page pool accounting differs")
    for name, values in (("core_page_state", [1]*28),
                         ("core_page_gen", [1]*28),
                         ("core_page_owner", [1,2]+[1]*26),
                         ("core_page_owner_gen", [1]*28),
                         ("core_page_purpose", [1,1]+[6]*26)):
        if ram[sym[name]:sym[name]+32] != bytes(values+[0]*4):
            raise AssertionError("shared page metadata differs: "+name)
    if (word("draw_root_owner"), word("draw_worker_owner")) != (0x0101, 0x0102):
        raise AssertionError("shared owner allocation differs")
    if ram[sym["core_win_gen"]:sym["core_win_gen"]+2] != b"\1\1":
        raise AssertionError("shared window generations differ")
    if ram[sym["core_app_code_native"]:sym["core_app_code_native"]+2] != b"\xC0\xC4":
        raise AssertionError("primary code binding differs")
    if byte("core_param_timer_owner") or byte("core_param_dropped"):
        raise AssertionError("timer publication not cleaned up")
    if ram[0x10202] != 2:  # C4 counter neighbor records the actual worker call
        raise AssertionError("actual worker drawing was not rejected")
    if not word("draw_irq_total"):
        raise AssertionError("no interrupts serviced inside drawing loops")
    # Unrelated native draw must not hide/show an already-visible pointer.
    traces = [tuple(struct.unpack_from("<HH", ram, sym["cpc_draw_trace"]+i*4)) for i in range(len(frames))]
    names = [name for name, _ in frames]
    shown = traces[names.index("phase-3")]
    changed = traces[names.index("draw-under-pointer")]
    if changed != (shown[0]+1, shown[1]+1):
        raise AssertionError("pointer rectangle exclusion/restore count differs")
    # Text under the pointer must exclude once and restore against updated bytes.
    before = traces[names.index("empty-clip-line")]
    after = traces[names.index("text-under-pointer")]
    if after != (before[0]+2, before[1]+1):
        raise AssertionError("pointer text exclusion/restore count differs")
    return dict(drawing_cases=len(cases()), pixel_checkpoints=len(frames),
                drawing_irqs=word("draw_irq_total"),
                owner_pool_free=byte("core_page_free"), pointer_saves=word("pointer_saves"),
                pointer_restores=word("pointer_restores"))
