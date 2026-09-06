"""CPC lifecycle fixture inputs and independent state/framebuffer oracle.

The fixture seeds logical FS contexts and queue records. It does not claim
that CPC file-context APIs, deferred delivery or an APP loader are operational.
"""
from __future__ import annotations

import copy
import struct
from pathlib import Path
from cpc_graphics_fixture import CURSOR, address, put_pixel
from cpc_production_windows import contains

LIFETIME_VARIANTS = {"lifetime": None, "lifetime-bad-purge": "CPC_FAULT_LIFE_PURGE",
                     "lifetime-bad-fsctx": "CPC_FAULT_LIFE_FSCTX"}
NATIVES = [0xC0]+[g+s for g in range(0xC4,0xFC,8) for s in range(4)]
NATIVES = NATIVES[:28]  # F7 belongs to font/data, never the owner pool
CASES = ("root-protection", "foreign-window", "bad-generation", "close-sibling",
         "last-window", "dead-window", "reuse", "stale-reused-window", "close-reused",
         "windowless-publish", "windowless-quit", "second-pair", "explicit-quit",
         "stale-owner", "root-still-protected", "unsupported-drag")


def cleanup_seed(generation):
    owner, other = 3 | generation << 8, 3 | (generation+1) << 8
    endpoints = [(owner,0x101),(0x101,owner),(other,0x101),(0x101,other),
                 (0x102,0x101),(owner,owner),(0x101,0x102),(owner,0x102)]
    queue = [struct.pack("<HH4B",s,r,32+i,40+i,50+i,60+i) for i,(s,r) in enumerate(endpoints)]
    contexts = bytearray()
    for i, who in enumerate((owner,owner,other,0x102)):
        record = bytearray((i*37+j)&255 for j in range(144))
        record[:4] = struct.pack("<BBH",1,20+i,who)
        contexts += record
    return queue, contexts


def emit_vectors(path: Path):
    queue, contexts = cleanup_seed(1)
    rows = ["life_queue_seed", "db "+",".join(map(str,b"".join(queue))), "life_fs_seed"]
    rows += ["db "+",".join(map(str,contexts[i:i+32])) for i in range(0,576,32)]
    path.write_text("\n".join(rows)+"\n")


def physical(native):
    if native == 0xC0: return 0x4000
    if native not in NATIVES[1:]: raise AssertionError("invalid lifetime page tag")
    return 0x10000+(((native & 0x38)>>3)*4+(native&3))*16384


def expected():
    pages = [dict(gen=0,owner=0,purpose=0) for _ in NATIVES]
    def alloc(owner,purpose):
        i = next(i for i,p in enumerate(pages) if not p["owner"])
        pages[i].update(gen=pages[i]["gen"]+1,owner=owner,purpose=purpose)
        return i
    alloc(0x101,1)
    alloc(0x102,1)
    trace_tags = [NATIVES[alloc(0x101,6)] for _ in range(2)]
    rects = [(0,0,80,200),(8,20,24,30),None,None]
    order,focus,run = [0,1],1,2
    win_gen = [1,1,0,0,0,0,0,0]
    app_gen,app_owner,primary,app_pages,app_windows,app_worker = 0,0,0,[],[],255
    queue,contexts,flags,service,accessory,endpoint = [],bytearray(576),0,0,0,0
    frame = bytearray((a>>8) ^ (a&255) for a in range(0xC000,0x10000))
    saves,restores = 0,0

    def repaint(damage):
        nonlocal saves,restores
        restores += bool(saves)
        saves += 1
        for y in range(200):
            for x in range(80):
                if not contains(damage,x,y): continue
                slot = next(s for s in reversed(order) if contains(rects[s],x,y))
                rx,ry,w,h = rects[slot]
                pen = ((x^y)&3 if not slot else (3 if slot==focus else 1)
                       if x in (rx,rx+w-1) or y in (ry,ry+h-1) else slot&3)
                frame[address(x*4,y)] = (0,0xF0,0x0F,0xFF)[pen]

    def new_app(count):
        nonlocal app_gen,app_owner,primary,app_pages,app_windows,app_worker,focus,run
        nonlocal queue,contexts,flags,service,accessory,endpoint
        app_gen += 1
        app_owner = app_gen*256+3
        app_pages = [alloc(app_owner,p) for p in (1,2,7)]
        primary = NATIVES[app_pages[0]]
        app_windows = list(range(2,2+count))
        for slot in app_windows:
            win_gen[slot] += 1
            rects[slot] = (20 if slot==2 else 45,60,20,35)
            order.append(slot)
        app_worker = 2 if count else 255
        run += bool(count)
        if count: focus = order[-1]
        flags = 1 if count else 0
        queue,contexts = cleanup_seed(app_gen)
        service,accessory,endpoint = 0x44,0x55,0x4090
        repaint(rects[0])

    def release():
        nonlocal queue,flags,service,accessory,endpoint,app_worker
        queue = [r for r in queue if app_owner not in struct.unpack_from("<HH",r)]
        for i in range(4):
            if struct.unpack_from("<H",contexts,i*144+2)[0] == app_owner:
                contexts[i*144] = 0
        for p in pages:
            if p["owner"] == app_owner: p.update(owner=0,purpose=0)
        flags,service,accessory,endpoint,app_worker = 0,0,0,0,255

    def close(slot):
        nonlocal focus,run,app_worker
        x,y,w,h = rects[slot]
        order.remove(slot)
        app_windows.remove(slot)
        if app_worker==slot:
            run -= 1
            app_worker = 255
        focus = order[-1]
        if not app_windows: release()
        repaint((x,y,w+8,h))

    result = []
    for case,name in enumerate(CASES):
        status,bank = 0,0xC0
        if case == 0: new_app(2); status=5
        elif case == 1: status=3
        elif case == 2: status,bank=2,primary
        elif case == 3: bank=primary; close(2)
        elif case == 4: bank=primary; close(3)
        elif case == 5: status=2
        elif case == 6: new_app(1)
        elif case == 7: status,bank=2,primary
        elif case == 8: bank=primary; close(2)
        elif case == 9: new_app(0); flags=9; bank=primary
        elif case == 10: bank=primary; release()
        elif case == 11: new_app(2)
        elif case == 12: bank=primary; close(2); close(3)
        elif case == 13: status=2
        elif case == 14: status=5
        elif case == 15: status=1
        frame_tag = NATIVES[alloc(0x101,6)]
        visible = bytearray(frame)
        for y,row in enumerate(CURSOR):
            for x,ch in enumerate(row):
                if ch != ".": put_pixel(visible,x,y,int(ch))
        result.append(dict(name=name,status=status,bank=bank,focus=focus,order=order[:],run=run,
            primary=primary,owner=app_owner,app_gen=app_gen,pages=copy.deepcopy(pages),app_pages=app_pages[:],
            windows=app_windows[:],win_gen=win_gen[:],worker=app_worker,flags=flags,service=service,
            accessory=accessory,endpoint=endpoint,queue=b"".join(queue),contexts=bytes(contexts),
            frame=bytes(visible),frame_tag=frame_tag,saves=saves,restores=restores))
    return trace_tags,result


def verify_lifetime(ram,sym,work):
    tags,states = expected()
    if list(ram[sym["life_trace_tags"]:sym["life_trace_tags"]+2]) != tags or ram[sym["life_done"]]!=16:
        raise AssertionError("lifetime trace/count differs")
    for i,state in enumerate(states):
        base = physical(tags[i//8])+(i%8)*2048
        record = ram[base:base+2048]
        def fail(detail): raise AssertionError(f"lifetime {state['name']}: {detail}")
        if list(record[:10]) != [i,state["status"],state["bank"],state["focus"],len(state["order"]),
                               state["run"],state["frame_tag"],state["primary"],3,state["app_gen"]]:
            fail("status/bank/focus/runnable/identity")
        if struct.unpack_from("<HH",record,12) != (state["saves"],state["restores"]): fail("pointer locking")
        arch = record[32:544]
        def field(name,size=1):
            at=sym[name]-0x2200
            return arch[at:at+size]
        if field("core_page_native",32) != bytes(NATIVES+[0]*4): fail("page native table")
        for name, values in (("core_page_state",[int(bool(p["owner"])) for p in state["pages"]]),
                             ("core_page_gen",[p["gen"] for p in state["pages"]]),
                             ("core_page_owner",[p["owner"]&255 for p in state["pages"]]),
                             ("core_page_owner_gen",[p["owner"]>>8 for p in state["pages"]]),
                             ("core_page_purpose",[p["purpose"] for p in state["pages"]])):
            if field(name,32) != bytes(values+[0]*4): fail("page reclamation: "+name)
        active = bool(state["flags"])
        # A not-yet-published windowless app does not escape into a checkpoint.
        if field("core_owner_active",8) != bytes((1,1,int(active),0,0,0,0,0)): fail("owner liveness")
        if field("core_owner_gen",8) != bytes((1,1,state["app_gen"],0,0,0,0,0)): fail("owner generation")
        if field("core_win_gen",8) != bytes(state["win_gen"]): fail("window generation")
        links = [1,2]+[3 if s in state["windows"] else 0 for s in range(2,8)]
        gens = [1,1]+[state["app_gen"] if s in state["windows"] else 0 for s in range(2,8)]
        if field("core_win_owner",8)!=bytes(links) or field("core_win_owner_gen",8)!=bytes(gens): fail("window ownership")
        if field("core_app_window_count",8)!=bytes((1,1,len(state["windows"]),0,0,0,0,0)): fail("sibling count")
        for name, value in (("core_app_flags",state["flags"]),("core_app_service",state["service"]),
                            ("core_app_accessory",state["accessory"]),("core_app_worker_win",state["worker"]),
                            ("core_app_primary_win",state["windows"][0] if state["windows"] else 255),
                            ("core_defer_handler_lo",state["endpoint"]&255),("core_defer_handler_hi",state["endpoint"]>>8)):
            if field(name,3)[2]!=value: fail("application reset: "+name)
        for name,value in (("core_app_code_native",state["primary"] if active else 0),
                           ("core_app_code_page",state["app_pages"][0]+1 if active else 0),
                           ("core_app_code_gen",state["pages"][state["app_pages"][0]]["gen"] if active else 0)):
            if field(name,3)[2]!=value: fail("code page lifecycle: "+name)
        if field("core_pending_owner",2)!=b"\0\0": fail("pending owner leaked")
        if field("core_page_free")[0]!=sum(not p["owner"] for p in state["pages"]): fail("free-page count")
        if field("core_defer_count")[0]!=len(state["queue"])//8 or field("core_defer_queue",len(state["queue"]))!=state["queue"]:
            fail("message purge/FIFO/generation")
        if record[544:1120]!=state["contexts"]: fail("FS context cleanup/generation/tail")
        native = record[1120:1320]
        for slot in state["order"]:
            flags = 9 if slot==0 else 11 if slot==1 or slot==state["worker"] else 3
            if native[slot*25+13]!=flags: fail("native runnable/alive flags")
        for slot in (2,3):
            if slot not in state["windows"] and native[slot*25+13]: fail("closed native flags survived")
        if list(record[1320:1320+len(state["order"])])!=state["order"]: fail("z-order")
        if record[1328:1332]!=bytes((0,0,80,200)): fail("restored clip")
        if record[1332:]!=b"\xBD"*(2048-1332): fail("trace tail overwritten")
        at=physical(state["frame_tag"])
        if ram[at:at+16384]!=state["frame"]: fail("framebuffer damage/exposure")
    if ram[0xC000:0x10000]!=states[-1]["frame"]: raise AssertionError("lifetime final framebuffer")
    # Trace is an observation, not authority to conceal later table mutations.
    final_base=physical(tags[1])+7*2048
    final=ram[final_base:final_base+2048]
    for start,end,offset in ((0x2200,0x2400,32),(0x2600,0x2840,544)):
        if ram[start:end]!=final[offset:offset+end-start]: raise AssertionError("lifetime final tables changed")
    if ram[0x2840:0x2900]!=b"\xAC"*192: raise AssertionError("lifetime launch/service reservation changed")
    for name in ("cpc_wm_guard","cpc_wm_end","cpc_life_guard","cpc_life_end","cpc_draw_state_guard","cpc_draw_state_end"):
        if ram[sym[name]:sym[name]+16]!=b"\xD7"*16: raise AssertionError("lifetime state guard")
    if ram[sym["core_pointer_paintlock"]] or ram[sym["pointer_visible"]]!=1: raise AssertionError("lifetime pointer state")
    raw=(work/"SUPPORT.RAW").read_bytes()
    observed=bytearray(ram[sym["cpc_support_base"]:sym["cpc_support_base"]+len(raw)])
    for name,size in (("up_request",16),("up_text_copy",49)):
        at=sym[name]-sym["cpc_support_base"]
        observed[at:at+size]=raw[at:at+size]
    if observed!=raw: raise AssertionError("lifetime SUPPORT.RAW code changed")
    font=(work/"DEFAULT.FNT").read_bytes()
    if ram[0x7C000:0x80000]!=font+b"\xA9"*(16384-len(font)): raise AssertionError("lifetime font page")
    if ram[0x10202]!=2 or ram[0x10200:0x10202]!=ram[sym["cpc_worker_counter"]:sym["cpc_worker_counter"]+2]:
        raise AssertionError("lifetime worker rejection/lock")
    return dict(lifetime_checkpoints=16,owner_generations=4,
                owner_pool_free=ram[sym["core_page_free"]])
