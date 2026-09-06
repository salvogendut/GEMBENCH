"""Native registration inputs and independent pixel/state expectations.

No APP loader or event loop is simulated. Frames are constructed per surface
then resolved by brute-force topmost ownership, not the Z80 region iterator.
"""
from __future__ import annotations

import copy
from pathlib import Path
import struct

from cpc_graphics_fixture import CURSOR, address, put_pixel
from cpc_production_lifetime import NATIVES, physical
from cpc_production_windows import contains

REGISTRATION_VARIANTS = {"registration": None,
    "registration-bad-kind": "CPC_FAULT_REG_KIND",
    "registration-bad-owner": "CPC_FAULT_REG_OWNER"}
INPUTS = ((0xC4,0,(10,60,28,45),0,"Legacy"),
          (0xC0,0xB6,(30,85,25,45),0,"Work"),
          (0xC0,0xB6,(48,25,25,45),9,"Title"),
          (0xC0,0xB6,(40,110,32,55),31,"Full"),
          (0xC0,0xB6,(5,130,28,40),3,"Close"),
          (0xC0,0xB6,(65,175,14,24),16,"Grip"),
          (0xC4,0xB6,(50,105,26,45),1,"Reuse"))
CASES = ("initial", "legacy", "titleless", "title-move", "standard", "close-only",
         "resize-only", "full-raw", "full-managed", "focus-legacy", "move", "shrink",
         "close-standard", "reuse-slot", "tiny-title-damage", "cleanup")


def emit_vectors(path: Path):
    rows = ["reg_inputs"]
    for i,(native,selector,*_) in enumerate(INPUTS):
        rows += [f"dw reg_desc_{i}", f"db {native},{selector}"]
    rows += ["reg_titles", "dw "+",".join(f"reg_title_{i}" for i in range(len(INPUTS)))]
    for i,(_,_,rect,kind,title) in enumerate(INPUTS):
        rows += [f"reg_desc_{i}", "db "+",".join(map(str,rect+(10,24))),
                 f"dw #4B00,{0x4A00+i*32},0", f"db {kind}",
                 f'reg_title_{i} db "{title}",0']
    path.write_text("\n".join(rows)+"\n")


def chrome(rect, kind, title, font):
    """Declarative plain furniture, in logical pixels before Mode-1 packing."""
    x,y,w,h = rect
    pixels = bytearray(320*200)
    def fill(box, pen):
        bx,by,bw,bh = box
        for yy in range(max(y,by,0),min(y+h,by+bh,200)):
            for xx in range(max(x,bx,0)*4,min(x+w,bx+bw,80)*4):
                pixels[yy*320+xx] = pen
    def border(box,pen):
        bx,by,bw,bh = box
        for edge in ((bx,by,bw,1),(bx,by+bh-1,bw,1),(bx,by,1,bh),(bx+bw-1,by,1,bh)):
            fill(edge,pen)
    def text(tx,ty,s,ink,paper):
        fw,fh,first = font[7],font[8],font[5]
        for i,ch in enumerate(s):
            glyph = 16+(ord(ch)-first)*fh
            for gy in range(fh):
                for gx in range(fw):
                    px,py = tx*4+i*fw+gx,ty+gy
                    if 0<=px<320 and 0<=py<200 and contains(rect,px//4,py):
                        pixels[py*320+px] = ink if font[glyph+gy] & (128>>gx) else paper
    if kind & 1:
        fill((x,y,w,14),1)
        for yy in range(y,y+14,2): fill((x,yy,w,1),2)
    border(rect,1)
    if kind & 1:
        if kind & 2: fill((x+1,y+2,2,10),1)
        if kind & 4:
            fill((x+w-4,y+2,3,10),1)
            fill((x+w-3,y+5,1,4),2)
    if kind & 16:
        box = (x+w-2,y+h-6,2,6)
        fill(box,1)
        border(box,2)
    if kind & 1:
        text(x+(4 if kind&2 else 1),y+3,title,1,2)
        if kind & 2: text(x+1,y+3,"X",2,1)
    fill((x+2,y+16,2,3),3)        # fixture content only, not window furniture
    packed = bytearray(16384)
    for yy in range(max(0,y),min(200,y+h)):
        for xx in range(max(0,x)*4,min(80,x+w)*4):
            put_pixel(packed,xx,yy,pixels[yy*320+xx])
    return packed


def expected(font):
    windows = {0:dict(rect=(0,0,80,200),native=0xC0),
               1:dict(rect=(8,20,24,30),native=0xC4)}
    order,focus = [0,1],1
    generations = [1,1,0,0,0,0,0,0]
    frame = bytearray((a>>8) ^ (a&255) for a in range(0xC000,0x10000))
    publication,results = (0,0,0,0),[]
    callbacks = set()
    def repaint(damage):
        surfaces = {s:chrome(v["rect"],v["kind"],v["title"],font)
                    for s,v in windows.items() if s>=2}
        for yy in range(200):
            for xx in range(80):
                if not any(contains(r,xx,yy) for r in damage): continue
                slot = next(s for s in reversed(order) if contains(windows[s]["rect"],xx,yy))
                at = address(xx*4,yy)
                if slot>=2:
                    frame[at] = surfaces[slot][at]
                    callbacks.add(slot)
                else:
                    rx,ry,rw,rh = windows[slot]["rect"]
                    pen = (xx^yy)&3 if not slot else ((3 if focus==slot else 1)
                        if xx in (rx,rx+rw-1) or yy in (ry,ry+rh-1) else 1)
                    frame[at] = (0,0xF0,0x0F,0xFF)[pen]
    def close(slot):
        nonlocal focus
        rx,ry,rw,rh = windows.pop(slot)["rect"]
        order.remove(slot)
        focus = order[-1]
        repaint([(rx,ry,rw+8,rh)])
    for i,name in enumerate(CASES):
        callbacks=set()
        bank=0xC0
        if i==0: repaint([windows[0]["rect"]])
        elif 1<=i<=6 or i==13:
            index = i-1 if i!=13 else 6
            native,selector,rect,kind,title = INPUTS[index]
            slot = next(s for s in range(8) if s not in windows)
            generations[slot] += 1
            windows[slot] = dict(rect=rect,native=native,kind=kind if selector else 7,
                                 flags=19 if selector else 3,index=index,title=title)
            order.append(slot)
            focus=slot
            x,y,w,h=rect
            publication=(x,y,w+8,h)
            repaint([windows[0]["rect"]] if i==2 else [publication])
            bank=native
        elif i==9:
            old=focus
            focus=2
            order.remove(2)
            order.append(2)
            repaint([windows[s]["rect"] for s in (old,focus)])
        elif i==10:
            x,y,w,h=windows[focus]["rect"]
            windows[focus]["rect"]=(18,40,w,h)
            repaint([(min(x,18),min(y,40),max(x,18)+w-min(x,18),max(y,40)+h-min(y,40))])
        elif i==11:
            x,y,w,h=windows[focus]["rect"]
            windows[focus]["rect"]=(x,y,20,30)
            repaint([(x,y,w,h)])
        elif i==12: close(5)
        elif i==14: repaint([(19,43,2,3)])
        elif i==15:
            for slot in range(2,8): close(slot)
        visible=bytearray(frame)
        for yy,row in enumerate(CURSOR):
            for xx,ch in enumerate(row):
                if ch!=".": put_pixel(visible,xx,yy,int(ch))
        results.append(dict(name=name,bank=bank,windows=copy.deepcopy(windows),order=order[:],
                            focus=focus,generations=generations[:],publication=publication,
                            callbacks=callbacks.copy(),frame=bytes(visible)))
    return results


def verify_registration(ram,sym,work,checkpoints=16):
    states=expected((work / "DEFAULT.FNT").read_bytes())
    if ram[sym["reg_trace_tag"]]!=0xC5 or (checkpoints==16 and ram[sym["reg_done"]]!=16):
        raise AssertionError("registration trace/count differs")
    for i,state in enumerate(states[:checkpoints]):
        record=ram[physical(0xC5)+i*1024:physical(0xC5)+(i+1)*1024]
        def fail(detail): raise AssertionError(f"registration {state['name']}: {detail}")
        if list(record[:6])!=[i,0,state["bank"],NATIVES[i+3],len(state["order"]),state["focus"]]:
            fail("status/bank/count/focus")
        if tuple(record[8:12])!=state["publication"]: fail("initial damage publication")
        if record[20:22]!=b"\0\0": fail("pending owner not consumed")
        if record[756:]!=b"\xBD"*(1024-756): fail("state capture tail")
        arch=record[32:544]
        def field(name,n=1): return arch[sym[name]-0x2200:sym[name]-0x2200+n]
        if field("core_win_gen",8)!=bytes(state["generations"]): fail("window generations")
        for suffix in ("", "_gen"):
            want=[0]*8
            for s,w in state["windows"].items():
                want[s]=1 if suffix else (1 if w["native"]==0xC0 else 2)
            if field("core_win_owner"+suffix,8)!=bytes(want): fail("window owner binding")
        counts=[sum(v["native"]==n for v in state["windows"].values()) for n in (0xC0,0xC4)]
        if field("core_app_window_count",8)!=bytes(counts+[0]*6): fail("owner window counts")
        if field("core_app_primary_win",2)!=b"\0\1": fail("primary window changed")
        if field("core_owner_active",8)!=b"\1\1"+b"\0"*6: fail("owner lifetime changed")
        if field("core_page_free")[0]!=24-i: fail("capture page accounting")
        for field_name,values in (("core_page_state",[1]*(i+4)),
            ("core_page_gen",[1]*(i+4)),("core_page_owner",[1,2]+[1]*(i+2)),
            ("core_page_owner_gen",[1]*(i+4)),("core_page_purpose",[1,1]+[6]*(i+2))):
            if field(field_name,32)!=bytes(values+[0]*(32-len(values))): fail(field_name)
        for s in range(8):
            entry=record[544+s*25:544+(s+1)*25]
            if s not in state["windows"]:
                if entry[13]&1: fail("dead slot alive")
                continue
            w=state["windows"][s]
            if entry[:5]!=bytes((w["native"],*w["rect"])): fail("native geometry/mapping")
            if s>=2:
                j=w["index"]
                if entry[5:]!=struct.pack("<HHHHB",0x4800+j*16,0x4B00,0x4B00,0,w["flags"])+b"CHROME  TST":
                    fail("managed descriptor/proc/flags/argument")
                if bool(record[12+s])!=(s in state["callbacks"]): fail("content callback visibility")
        if list(record[744:744+len(state["order"])])!=state["order"]: fail("z-order")
        if record[752:756]!=bytes((0,0,80,200)): fail("repaint clip restore")
        observed=ram[physical(NATIVES[i+3]):physical(NATIVES[i+3])+16384]
        if observed!=state["frame"]:
            at=next(j for j,(a,b) in enumerate(zip(observed,state["frame"])) if a!=b)
            fail(f"furniture/content pixels at {at:04X}")
    if checkpoints!=16:
        return dict(partial_registration_checkpoints=checkpoints)  # fault diagnosis ONLY
    if ram[0xC000:0x10000]!=states[-1]["frame"]: raise AssertionError("registration final framebuffer")
    if ram[sym["reg_long_title"]:sym["reg_long_title"]+25]!=b"01234567890123456789012\0\xD7":
        raise AssertionError("registration bounded native title copy")
    for name in ("cpc_reg_guard","cpc_reg_end","cpc_wm_guard","cpc_wm_end","cpc_draw_state_guard","cpc_draw_state_end"):
        if ram[sym[name]:sym[name]+16]!=b"\xD7"*16: raise AssertionError("registration guard: "+name)
    code=(work / "SUPPORT.RAW").read_bytes()
    observed=bytearray(ram[sym["cpc_support_base"]:sym["cpc_support_base"]+len(code)])
    for name,size in (("up_request",16),("up_text_copy",49)):
        at=sym[name]-sym["cpc_support_base"]
        observed[at:at+size]=code[at:at+size]
    if observed!=code: raise AssertionError("registration low support modified")
    font=(work / "DEFAULT.FNT").read_bytes()
    if ram[0x7C000:0x80000]!=font+b"\xA9"*(16384-len(font)): raise AssertionError("registration font modified")
    if ram[sym["core_pointer_paintlock"]] or ram[sym["pointer_visible"]]!=1:
        raise AssertionError("registration pointer lock/visibility")
    if ram[0x10202]!=2 or ram[0x10200:0x10202]!=ram[sym["cpc_worker_counter"]:sym["cpc_worker_counter"]+2]:
        raise AssertionError("registration worker ran under root lock")
    return dict(registration_checkpoints=len(states),owner_pool_free=ram[sym["core_page_free"]])
