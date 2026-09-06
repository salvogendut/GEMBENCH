"""Shared CPC window-policy fixture inputs and independent per-byte oracle.

Not production window policy: the oracle uses brute-force pixel ownership,
not the Z80 rectangle-band iterator. Native test callbacks are instrumented.
"""
from __future__ import annotations

import struct
from pathlib import Path
from cpc_graphics_fixture import CURSOR, address, put_pixel

WINDOW_VARIANTS = {"windows": None, "windows-bad-clip": "CPC_FAULT_WM_CLIP",
                   "windows-bad-pointer": "CPC_FAULT_WM_POINTER"}
RECTS = ((0, 0, 80, 200), (8, 20, 24, 30), (20, 35, 30, 60),
         (55, 15, 20, 35), (24, 42, 8, 12))
NATIVES = (0xC0, 0xC4, 0xC0, 0xC0, 0xC0)


def cases():
    # op: full, click, move, size, explicit damage, top-only, withdrawal.
    return [("initial", (0, 0, 0, 0, 0)),
            ("same-focus", (1, 60, 20, 0, 0)),
            ("sibling-focus", (1, 21, 36, 0, 0)),
            ("cross-page-focus", (1, 9, 21, 0, 0)),
            ("desktop-focus", (1, 1, 1, 0, 0)),
            ("return-sibling", (1, 40, 60, 0, 0)),
            ("move-expose", (2, 38, 80, 0, 0)),
            ("shrink", (3, 18, 30, 0, 0)),
            ("exposed-focus", (1, 25, 52, 0, 0)),
            ("tiny-damage", (4, 70, 170, 5, 4)),
            ("top-only", (5, 0, 0, 0, 0)),
            ("no-hit", (1, 90, 210, 0, 0)),
            ("withdraw-fixture", (6, 0, 0, 0, 0)),
            ("move-screen-edge", (2, 70, 180, 0, 0)),
            ("shrink-screen-edge", (3, 8, 16, 0, 0)),
            ("empty-damage", (4, 0, 0, 0, 0))]


def emit_vectors(path: Path):
    rows = ["cpc_fixture_records"]
    for slot, rect in enumerate(RECTS):
        rows += ["db " + ",".join(map(str, (NATIVES[slot], *rect))),
                 "dw 0,cpc_fixture_paint," + str(0x4500+slot*16) + "," + str(0 if not slot else 0x4600+slot*16),
                 f"db {9 if not slot else 3 if slot in (1, 3) else 1}", "ds 11,0"]
    rows += ["cpc_window_vectors"]
    for name, event in cases():
        rows += [f"; {name}", "db " + ",".join(map(str, event))]
    rows += [f"CPC_WINDOW_EVENTS equ {len(cases())}",
             "assert CPC_WINDOW_EVENTS*32<=CPC_WM_TRACE_END-CPC_WM_TRACE,\"WM trace overflow\""]
    path.write_text("\n".join(rows)+"\n")


def contains(rect, x, y):
    rx, ry, w, h = rect
    return rx <= x < rx+w and ry <= y < ry+h


def expected_frames():
    rects = list(RECTS)
    order, focus = [0, 1, 4, 2, 3], 3
    frame = bytearray((a >> 8) ^ (a & 255) for a in range(0xC000, 0x10000))
    result, passes = [], 0
    for name, (op, a, b, c, d) in cases():
        flags, damage, top_only, paint = 1, [], False, True
        if op == 0:
            damage = [RECTS[0]]
        elif op == 1:
            target = next((s for s in reversed(order) if contains(rects[s], a, b)), None)
            paint = target is not None and target != focus
            if paint:
                flags = int(NATIVES[focus] != NATIVES[target])
                damage = [rects[s] for s in (target, focus) if s]
                focus = target
                if target:
                    order.remove(target)
                    order.append(target)
        elif op in (2, 3):
            x, y, w, h = rects[focus]
            if op == 2:
                damage = [(min(x,a), min(y,b), max(x,a)+w-min(x,a), max(y,b)+h-min(y,b))]
                rects[focus] = (a,b,w,h)
            else:
                damage = [(x,y,max(w,a),max(h,b))]
                rects[focus] = (x,y,a,b)
        elif op == 4:
            damage = [(a,b,c,d)]
        elif op == 5:
            x,y,w,h = rects[focus]
            damage, top_only = [(x,y,w+8,h)], True
        elif op == 6:
            x,y,w,h = rects[4]
            damage = [(x,y,w+8,h)]
            order.remove(4)
            focus = order[-1]
        counts = [0]*5
        if paint:
            passes += 1
            for y in range(200):
                for x in range(80):
                    if not any(contains(r,x,y) for r in damage):
                        continue
                    slot = next(s for s in reversed(order) if contains(rects[s],x,y))
                    if top_only and slot != order[-1]:
                        continue
                    counts[slot] += 1
                    rx,ry,w,h = rects[slot]
                    if not slot:
                        pen = (x ^ y) & 3
                    elif x in (rx,rx+w-1) or y in (ry,ry+h-1):
                        pen = 3 if slot == focus else 1
                    else:
                        pen = slot & 3
                    frame[address(x*4,y)] = (0,0xF0,0x0F,0xFF)[pen]
        visible = bytearray(frame)
        for y,row in enumerate(CURSOR):
            for x,ch in enumerate(row):
                if ch != ".": put_pixel(visible,105+x,47+y,int(ch))
        result.append(dict(name=name, frame=bytes(visible), writes=counts, focus=focus,
                           flags=flags, order=order[:], saves=passes+1, restores=passes))
    return result


def verify_windows(ram: bytes, sym: dict, work: Path):
    def byte(name): return ram[sym[name]]
    frames = expected_frames()
    if byte("wm_fixture_done") != len(frames) or byte("draw_capture_count") != len(frames):
        raise AssertionError("window checkpoint count differs")
    for i, expected in enumerate(frames):
        frame = ram[0x14000+i*16384:0x14000+(i+1)*16384]
        if frame != expected["frame"]:
            at = next(j for j,(a,b) in enumerate(zip(frame,expected["frame"])) if a != b)
            raise AssertionError(f"window checkpoint {expected['name']} pixels differ at {at:04X}")
        trace = ram[sym["cpc_wm_trace"]+i*32:sym["cpc_wm_trace"]+(i+1)*32]
        if list(struct.unpack_from("<5H",trace)) != expected["writes"]:
            raise AssertionError(f"window checkpoint {expected['name']} damage writes differ")
        # Fully hidden/disjoint windows must not receive even a no-op callback.
        if [bool(v) for v in trace[10:15]] != [bool(v) for v in expected["writes"]]:
            raise AssertionError(f"window checkpoint {expected['name']} callback visibility differs")
        focus, order = expected["focus"], expected["order"]
        if (trace[15], trace[16], list(trace[17:17+len(order)]), trace[27]) != (focus, expected["flags"], order, len(order)):
            raise AssertionError(f"window checkpoint {expected['name']} focus/z-order differs")
        if (trace[22], *struct.unpack_from("<HH",trace,23)) != (NATIVES[focus], 0x4500+focus*16, 0 if not focus else 0x4600+focus*16):
            raise AssertionError(f"window checkpoint {expected['name']} focus mapping/menu handoff differs")
        if struct.unpack_from("<HH",trace,28) != (expected["saves"],expected["restores"]):
            raise AssertionError(f"window checkpoint {expected['name']} pointer pass lock differs")
    if ram[0xC000:0x10000] != frames[-1]["frame"]:
        raise AssertionError("window final framebuffer differs")
    for name in ("cpc_wm_guard", "cpc_wm_end", "cpc_draw_state_guard", "cpc_draw_state_end"):
        at = sym[name]
        if ram[at:at+16] != b"\xD7"*16: raise AssertionError("window/drawing state guard damaged")
    if byte("core_pointer_paintlock") or byte("core_pointer_suppressed") or byte("pointer_visible") != 1:
        raise AssertionError("window pointer state differs")
    if ram[sym["core_clip_x"]:sym["core_clip_x"]+4] != bytes(RECTS[0]):
        raise AssertionError("window full clip not restored")
    code = (work / "SUPPORT.RAW").read_bytes()
    observed = bytearray(ram[sym["cpc_support_base"]:sym["cpc_support_base"]+len(code)])
    for name, size in (("up_request",16),("up_text_copy",49)):
        at = sym[name]-sym["cpc_support_base"]
        observed[at:at+size] = code[at:at+size]
    if observed != code: raise AssertionError("window SUPPORT.RAW changed")
    font = (work / "DEFAULT.FNT").read_bytes()
    if ram[0x7C000:0x80000] != font+b"\xA9"*(16384-len(font)):
        raise AssertionError("window font/service page changed")
    if byte("core_page_total") != 28 or byte("core_page_free") != 26-len(frames):
        raise AssertionError("window page accounting differs")
    for name, values in (("core_page_state", [1]*(2+len(frames))),
                         ("core_page_gen", [1]*(2+len(frames))),
                         ("core_page_owner", [1,2]+[1]*len(frames)),
                         ("core_page_owner_gen", [1]*(2+len(frames))),
                         ("core_page_purpose", [1,1]+[6]*len(frames))):
        if ram[sym[name]:sym[name]+32] != bytes(values+[0]*(32-len(values))):
            raise AssertionError("window page metadata differs: "+name)
    if ram[0x10202] != 2: raise AssertionError("window actual worker drawing not rejected")
    at = sym["cpc_worker_counter"]
    if ram[0x10200:0x10202] != ram[at:at+2]:
        raise AssertionError("worker ran during locked window repaint")
    drawing_irqs = int.from_bytes(ram[sym["draw_irq_total"]:sym["draw_irq_total"]+2], "little")
    if not drawing_irqs: raise AssertionError("window drawing IRQ coverage missing")
    return dict(window_checkpoints=len(frames), owner_pool_free=byte("core_page_free"),
                window_bytes_written=sum(sum(f["writes"]) for f in frames), drawing_irqs=drawing_irqs)
