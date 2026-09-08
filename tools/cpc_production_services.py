"""CPC deferred/timer composition: fixture inputs, native SDAS link, host checks."""
from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import copy
import struct

from cpc_graphics_fixture import CURSOR, address, put_pixel
from cpc_production_lifetime import NATIVES, physical
from cpc_production_registration import chrome
from cpc_production_windows import contains

SERVICE_VARIANTS={"services":None,"services-bad-delivery":"CPC_FAULT_SERVICE_DELIVERY",
                  "services-bad-visible":"CPC_FAULT_SERVICE_VISIBLE"}


def compile_timer(work, sym, root):
    """Assemble the unmodified MSX app-linked collector, never translate it."""
    sdcc=shutil.which(os.environ.get("SDCC","sdcc"))
    if not sdcc: raise RuntimeError("SDCC required for the shared app-linked timer collector")
    bindir=Path(sdcc).parent
    sdas=os.environ.get("SDAS",str(bindir/"sdasz80"))
    fields={"OWNER":"core_param_timer_owner","RECT":"core_param_timer_rect",
            "GEN":"core_param_timer_gen","DROPPED":"core_param_dropped",
            "DROPPED_GEN":"core_param_dropped_gen","FULLSCREEN":"cpc_fullscreen",
            "WIN_OWNER":"core_win_owner","WIN_GEN":"core_win_gen",
            "VISIBILITY":"cpc_wm_visibility","WINDOW_MAX":"cpc_window_max"}
    lines=[".module cpc_timer_collect",".globl _gb_timer_collect"]
    lines += [f"CORE_TIMER_{k} = {sym[v]}" for k,v in fields.items()]
    lines += [f"{k} = {sym[v]}" for k,v in {
        "TIMER_REPAINT":"wm_repaint_all","TIMER_SET_DAMAGE":"k_wm_damage",
        "TIMER_TEST_VISIBLE":"cpc_timer_visible"}.items()]
    lines += ['.include "core/timer_collect_contract.inc"','.area _DATA','.area _CODE',
              '.include "core/timer_collect.inc"']
    (work/"timer.s").write_text("\n".join(lines)+"\n")
    subprocess.run([sdas,f"-I{root}/lib/gembench","-o","timer.rel","timer.s"],cwd=work,check=True)
    subprocess.run([sdcc,"-mz80","--no-std-crt0","--nostdlib","--code-loc",hex(sym["cpc_timer_collect"]),
                    "--data-loc","0x6000","timer.rel","-o","timer.ihx"],cwd=work,check=True)
    subprocess.run([str(bindir/"makebin"),"-s","65536","-p","timer.ihx","timer.bin"],cwd=work,check=True)
    binary=(work/"timer.bin").read_bytes()[sym["cpc_timer_collect"]:]
    if len(binary)!=116: raise AssertionError("shared collector link is not exactly 116 bytes")
    (work/"TIMER.BIN").write_bytes(binary)


CASES=("initial","queue-full","reply","root-delivery","cancel","remaining-delivery",
       "unregister","activate","visible","partial","component-hidden","window-hidden",
       "stale-timer","fullscreen","invalid-receivers","cleanup")


def message(sender,receiver,kind,*payload):
    return struct.pack("<HH4B",sender,receiver,kind,*payload)


def expected(font):
    """Independent per-pixel ownership and FIFO model, not the Z80 iterator."""
    rects={0:(0,0,80,200),1:(8,20,24,30),2:(20,25,20,35)}
    order,focus,color=[0,1,2],2,3
    frame=bytearray((a>>8)^(a&255) for a in range(0xC000,0x10000))
    queue,log,states=[],[],[]
    current=bytes(8)
    turns=publishes=recursions=passes=0
    timer_rect=(0,0,0,0)
    api=bytearray(32)
    api[:13]=bytes((5,5,6,5,5,5,6,5,8,0,0,0,1))
    api[24:30]=bytes((5,)*6) # main-stack overrun/guards, IRQ/temp, wrap rejected
    callbacks=set()
    def repaint(box,top=False,timer=False,legacy=False):
        nonlocal passes,recursions
        passes+=1
        surfaces={}
        for slot in (1,2):
            if slot not in rects: continue
            x,y,w,h=rects[slot]
            surface=chrome(rects[slot],7 if slot==1 else 0,"Timer" if slot==1 else "Cover",font)
            for yy in range(y+15,y+h-1):
                for xx in range(x+1,x+w-1):
                    surface[address(xx*4,yy)]=(0,0xF0,0x0F,0xFF)[color if slot==1 else 3]
            surfaces[slot]=surface
        painted=set()
        for y in range(200):
            for x in range(80):
                if not contains(box,x,y): continue
                slot=next(s for s in reversed(order) if contains(rects[s],x,y))
                if top and slot!=focus: continue
                at=address(x*4,y)
                if slot and not legacy:
                    frame[at]=surfaces[slot][at]
                    callbacks.add(slot)
                    painted.add(slot)
                else:
                    rx,ry,w,h=rects[slot]
                    pen=(x^y)&3 if not slot else (3 if x in (rx,rx+w-1) or y in (ry,ry+h-1) else 1)
                    frame[at]=(0,0xF0,0x0F,0xFF)[pen]
        # This tiny partial component intersects one rectangular cover fragment.
        if timer and 2 in painted: recursions+=1
    def dispatch(valid=True,activate=True):
        nonlocal current,turns,focus
        turns+=1
        if not queue: return
        current=queue.pop(0)
        if not valid: return
        receiver=int.from_bytes(current[2:4],"little")
        log.append(current+bytes((0xC4 if receiver==0x102 else 0xC0,focus,0,1)))
        if current[4]==1:
            queue.append(message(receiver,0x101,2,0xEE,0xDD,0xCC))
        if current[4]==2 and activate:
            focus=1
            order.remove(1)
            order.append(1)
            repaint((8,20,32,30),top=True)
    def move(x,y):
        ox,oy,w,h=rects[2]
        rects[2]=(x,y,w,h)
        repaint((min(x,ox),min(y,oy),max(x,ox)+w-min(x,ox),max(y,oy)+h-min(y,oy)))
    def resize(w,h):
        x,y,ow,oh=rects[2]
        rects[2]=(x,y,w,h)
        repaint((x,y,max(w,ow),max(h,oh)))
    for i,name in enumerate(CASES):
        callbacks=set()
        if i==0: repaint(rects[0])
        elif i==1:
            queue=[message(0x102 if n&1 else 0x101,0x101 if n&1 else 0x102,
                           3 if n else 1,n,0xA0+n,0xB0+n) for n in range(8)]
            api[16:21]=bytes((4,2,3,2,5))
        elif i in (2,3,5): dispatch()
        elif i==4:
            old=len(queue)
            queue=[m for m in queue if m[:2]!=b"\1\1"]
            api[21]=old-len(queue)
        elif i==6: queue=[]
        elif i==7:
            queue.append(message(0x101,0x102,2,7,8,9))
            dispatch()
        elif 8<=i<=13:
            publishes+=1
            timer_rect=(18,36,6,3) if i==9 else (22,36,3,3) if i==10 else (10,36,2,3)
            if i==8:
                focus=2
                order.remove(2)
                order.append(2)
                repaint(rects[0])
                color=2
            elif i==9: color=1
            elif i==10: color=0
            elif i==11:
                move(8,20)
                resize(24,30)
            elif i==12:
                move(20,25)
                resize(20,35)
            dispatch()
            if i in (8,9): repaint(timer_rect,timer=True)
        elif i==14:
            for valid in (False,False,False,False,True):
                queue.append(message(0x101,0x102,2,7,8,9))
                dispatch(valid=valid,activate=False)
        else:
            order.remove(2)
            focus=1
            rects.pop(2)
            repaint((20,25,28,35))
            repaint(rects[0],legacy=True)
        visible=bytearray(frame)
        for y,row in enumerate(CURSOR):
            for x,ch in enumerate(row):
                if ch!=".": put_pixel(visible,x,y,int(ch))
        states.append(dict(name=name,frame=bytes(visible),queue=queue[:],current=current,log=b"".join(log),
            turns=turns,publishes=publishes,recursions=recursions,passes=passes,api=bytes(api),
            timer_rect=timer_rect,rects=copy.deepcopy(rects),order=order[:],focus=focus,
            color=color,callbacks=callbacks.copy()))
    return states


def verify_services(ram,sym,work):
    states=expected((work/"DEFAULT.FNT").read_bytes())
    if ram[sym["svc_trace_tag"]]!=0xC5 or ram[sym["svc_done"]]!=16:
        raise AssertionError("services trace/count differs")
    for i,state in enumerate(states):
        record=ram[physical(0xC5)+i*1024:physical(0xC5)+(i+1)*1024]
        def fail(detail): raise AssertionError(f"services {state['name']}: {detail}")
        if record[4]!=len(state["log"])//12 or record[631:727]!=state["log"].ljust(96,b"\0"):
            fail("delivery record/bank/root context")
        if record[0]!=i or record[1] or record[7:9]!=bytes((0xC5,NATIVES[i+3])):
            fail("checkpoint identity/request/banks")
        if record[2]!=0 or record[3]!=state["publishes"] or record[10]!=(5 if i>=8 else 0):
            fail("actual worker publication/busy status")
        if record[5]!=state["turns"] or record[6]!=(0 if i<2 else 0xC4 if i==7 else 0xC0):
            fail("bounded root turns/focus mapping")
        if tuple(record[12:16])!=(len(state["order"]),state["focus"],2 if i>=10 else 0,1 if i>=10 else 0):
            fail("focus/count/occluded acknowledgement")
        if record[19]!=state["recursions"] or record[20]!=state["color"] or record[26]!=int(i>=11):
            fail("collector recursion/hidden worker")
        if [bool(v) for v in record[16:19]]!=[s in state["callbacks"] for s in range(3)]:
            fail("callback visibility")
        # The pointer starts hidden and is first shown after the initial pass.
        if struct.unpack_from("<HH",record,22)!=(state["passes"],state["passes"]-1):
            fail("pointer repaint passes")
        if record[727:759]!=state["api"]: fail("API admission/cancel status")
        if record[759:769]!=struct.pack("<5H",0x102,0x102,0,0,0x101): fail("owner service lookup")
        if record[769:]!=b"\xBD"*255: fail("capture tail")
        arch=record[32:544]
        def field(name,n=1):
            at=sym[name]-0x2200
            return arch[at:at+n]
        if field("core_defer_count")[0]!=len(state["queue"]): fail("one-message FIFO count")
        if field("core_defer_queue",len(state["queue"])*8)!=b"".join(state["queue"]): fail("FIFO/reply/purge order")
        if field("core_defer_current",8)!=state["current"] or field("core_defer_busy")!=b"\0":
            fail("stable current record/busy restoration")
        for name,v in (("core_defer_handler_lo",0x20),("core_defer_handler_hi",0x4B)):
            if field(name,8)!=bytes(([v,v] if i<15 else [0,0])+[0]*6): fail("endpoint registration")
        for name,want in (("core_app_code_native",[0xC0,0xC4]+[0]*6),
            ("core_owner_active",[1,1]+[0]*6),("core_owner_gen",[1,1]+[0]*6),
            ("core_app_window_count",[2 if i<15 else 1,1]+[0]*6),
            ("core_app_service",[0x40,0xA0]+[0]*6),("core_app_accessory",[0,7]+[0]*6),
            ("core_win_owner",[1,2,1 if i<15 else 0]+[0]*5),
            ("core_win_owner_gen",[1,1,1 if i<15 else 0]+[0]*5),
            ("core_win_gen",[1,2 if i==12 else 1,1]+[0]*5)):
            if field(name,8)!=bytes(want): fail(name)
        if field("core_param_timer_owner")!=b"\0": fail("timer mailbox not consumed")
        if field("core_param_timer_rect",4)!=bytes(state["timer_rect"]): fail("busy publish changed immutable damage")
        if field("core_param_timer_gen")[0]!=int(i>=8): fail("timer generation")
        if field("core_page_free")[0]!=24-i: fail("capture page accounting")
        for name,values in (("core_page_state",[1]*(i+4)),("core_page_gen",[1]*(i+4)),
            ("core_page_owner",[1,2]+[1]*(i+2)),("core_page_owner_gen",[1]*(i+4)),
            ("core_page_purpose",[1,1]+[6]*(i+2))):
            if field(name,32)!=bytes(values+[0]*(32-len(values))): fail(name)
        for slot,rect in state["rects"].items():
            entry=record[544+slot*25:544+(slot+1)*25]
            if entry[:5]!=bytes((0xC4 if slot==1 else 0xC0,*rect)): fail("native geometry/mapping")
            if slot==2 and (entry[5:7]!=b"\0\x48" or entry[13]!=19): fail("managed cover binding")
        if record[619:619+len(state["order"])]!=bytes(state["order"]): fail("z-order")
        # An invisible component returns after its region test, without a paint
        # pass (which normally resets clip). The next shared root phase resets
        # it. Preserve and expose this existing MSX contract, not a CPC fixup.
        clip=state["timer_rect"] if i==10 else (0,0,80,200)
        if record[627:631]!=bytes(clip): fail("root/collector clip state")
        at=physical(NATIVES[i+3])
        observed=ram[at:at+16384]
        if observed!=state["frame"]:
            delta=next(j for j,(a,b) in enumerate(zip(observed,state["frame"])) if a!=b)
            fail(f"effective damage pixels at {delta:04X}")
    if ram[0xC000:0x10000]!=states[-1]["frame"]: raise AssertionError("services final framebuffer")
    for name in ("cpc_reg_guard","cpc_reg_end","cpc_wm_guard","cpc_wm_end","cpc_draw_state_guard","cpc_draw_state_end"):
        if ram[sym[name]:sym[name]+16]!=b"\xD7"*16: raise AssertionError("services guard: "+name)
    code=(work/"SUPPORT.RAW").read_bytes()
    observed=bytearray(ram[sym["cpc_support_base"]:sym["cpc_support_base"]+len(code)])
    for name,size in (("up_request",16),("up_text_copy",49)):
        at=sym[name]-sym["cpc_support_base"]
        observed[at:at+size]=code[at:at+size]
    if observed!=code: raise AssertionError("services low support modified")
    timer=(work/"TIMER.BIN").read_bytes()
    if ram[0x4C00:0x4C00+116]!=timer: raise AssertionError("services app-linked collector modified")
    font=(work/"DEFAULT.FNT").read_bytes()
    if ram[0x7C000:0x80000]!=font+b"\xA9"*(16384-len(font)): raise AssertionError("services font modified")
    if ram[sym["core_pointer_paintlock"]] or ram[sym["pointer_visible"]]!=1:
        raise AssertionError("services pointer lock/visibility")
    if ram[0x10202]!=2 or ram[0x10200:0x10202]!=ram[sym["cpc_worker_counter"]:sym["cpc_worker_counter"]+2]:
        raise AssertionError("services worker drawing/locked cleanup")
    return dict(service_checkpoints=16,deferred_deliveries=len(states[-1]["log"])//12,
                root_service_turns=states[-1]["turns"],worker_publications=states[-1]["publishes"],
                owner_pool_free=ram[sym["core_page_free"]])
