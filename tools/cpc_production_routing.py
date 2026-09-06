"""Real-keyboard CPC root-loop qualification; no snapshot loading or RAM writes."""
from __future__ import annotations

import hashlib
from cpc_graphics_fixture import CURSOR, address, put_pixel
from cpc_production_registration import chrome
from cpc_production_windows import contains
from test_cpc_foundation_1984 import snapshot

ROUTING_VARIANTS={"routing":None,"routing-bad-bank":"CPC_FAULT_ROUTE_BANK",
                  "routing-bad-click":"CPC_FAULT_ROUTE_CLICK"}


def frame(rects,order,px,py,font,final=False):
    result=bytearray((a>>8)^(a&255) for a in range(0xC000,0x10000))
    surfaces={}
    for slot,rect in rects.items():
        if not slot: continue
        x,y,w,h=rect
        surface=chrome(rect,7 if slot==1 else 31,"Worker" if slot==1 else "Control",font)
        for yy in range(y+15,y+h-1):
            for xx in range(x+1,x+w-1): surface[address(xx*4,yy)]=(0,0xF0,0x0F,0xFF)[slot+1]
        surfaces[slot]=surface
    for y in range(200):
        for x in range(80):
            slot=next(s for s in reversed(order) if contains(rects[s],x,y))
            at=address(x*4,y)
            if final:
                rx,ry,w,h=rects[slot]
                pen=(x^y)&3 if not slot else (3 if x in (rx,rx+w-1) or y in (ry,ry+h-1) else 1)
                result[at]=(0,0xF0,0x0F,0xFF)[pen]
            elif slot: result[at]=surfaces[slot][at]
            else: result[at]=0xF0 if y<8 else 0
    for y,row in enumerate(CURSOR):
        for x,ch in enumerate(row):
            if ch!=".": put_pixel(result,px+x,py+y,int(ch))
    return bytes(result)


def check_state(ram,sym,work,rects,order,focus,name,final=False):
    def fail(detail): raise AssertionError(f"routing {name}: {detail}")
    if ram[sym["wm_focus"]]!=focus: fail("focus")
    if ram[sym["wm_nwin"]]!=len(order) or ram[sym["wm_z"]:sym["wm_z"]+len(order)]!=bytes(order): fail("z-order/count")
    for slot,rect in rects.items():
        at=sym["wm_table"]+25*slot
        if ram[at:at+5]!=bytes((0xC4 if slot==1 else 0xC0,*rect)): fail("geometry/bank")
    if (ram[sym["sched_current"]],ram[sym["sched_lock"]],ram[sym["bank_cur"]])!=(0,1,0xC0): fail("root/lock/bank")
    if ram[sym["core_pointer_paintlock"]] or ram[sym["pointer_visible"]]!=1: fail("pointer ownership")
    if ram[sym["wm_clip_x"]:sym["wm_clip_x"]+4]!=bytes((0,0,80,200)): fail("clip restore")
    px=int.from_bytes(ram[sym["pointer_x"]:sym["pointer_x"]+2],"little")
    py=ram[sym["pointer_y"]]
    if px!=ram[sym["poll_byte"]]*4 or py!=ram[sym["poll_line"]]: fail("physical/public pointer")
    want=frame(rects,order,px,py,(work/"DEFAULT.FNT").read_bytes(),final)
    observed=ram[0xC000:0x10000]
    if observed!=want:
        at=next(i for i,(a,b) in enumerate(zip(observed,want)) if a!=b)
        fail(f"composited pixels at {at:04X}")
    for name in ("cpc_reg_guard","cpc_reg_end","cpc_wm_guard","cpc_wm_end","cpc_draw_state_guard","cpc_draw_state_end"):
        if ram[sym[name]:sym[name]+16]!=b"\xD7"*16: fail("guard "+name)
    if ram[sym["sched_fault"]]: fail("scheduler fault")
    return hashlib.sha256(observed).hexdigest()


def verify_routing(ram,sym,work):
    if ram[sym["rt_done"]]!=1: raise AssertionError("routing did not finish")
    check_state(ram,sym,work,{0:(0,0,80,200),1:(8,20,24,30)},[0,1],1,"cleanup",True)
    if ram[sym["core_page_free"]]!=26: raise AssertionError("routing owner page accounting")
    if ram[0x10202]!=2 or ram[0x10200:0x10202]!=ram[sym["cpc_worker_counter"]:sym["cpc_worker_counter"]+2]:
        raise AssertionError("routing worker drawing/cleanup")
    code=(work/"SUPPORT.RAW").read_bytes()
    actual=bytearray(ram[sym["cpc_support_base"]:sym["cpc_support_base"]+len(code)])
    for name,size in (("up_request",16),("up_text_copy",49)):
        at=sym[name]-sym["cpc_support_base"]
        actual[at:at+size]=code[at:at+size]
    if actual!=code: raise AssertionError("routing low support changed")
    if ram[0x4C00:0x4C74]!=(work/"TIMER.BIN").read_bytes(): raise AssertionError("routing collector changed")
    font=(work/"DEFAULT.FNT").read_bytes()
    if ram[0x7C000:0x80000]!=font+b"\xA9"*(16384-len(font)): raise AssertionError("routing font changed")
    return dict(root_routing_turns=int.from_bytes(ram[sym["rt_turns"]:sym["rt_turns"]+2],"little"))


def drive_routing(send,sym,work,artifacts):
    """Steer actual CPC keys; F2 observes a safe boundary, F1 requests cleanup."""
    rects={0:(0,0,80,200),1:(8,20,24,30),2:(40,60,24,40)}
    order,focus=[0,1,2],2
    captures=[]
    def read(name="steering"):
        p=artifacts/(name+".sna")
        send(f"snapshot-save {p}")
        _,ram=snapshot(p.read_bytes())
        if ram[sym["cpc_phase"]]==0xFF:
            raise AssertionError(f"routing runtime failure={ram[sym['cpc_failure']]}")
        return ram
    def wait(n): send(f"wait frames {n} 200")
    def event(r,slot,kind): return r[sym["rt_events"]+slot*16+kind]
    def difference(a,b,slot,kind): return (event(b,slot,kind)-event(a,slot,kind))&255
    def observe(name):
        send("key-down F2")
        for _ in range(100):
            wait(5)
            r=read()
            if r[sym["rt_ready"]]: break
        else: raise AssertionError("routing boundary timeout")
        r=read(name)
        digest=check_state(r,sym,work,rects,order,focus,name)
        if r[sym["rt_bars"]:sym["rt_bars"]+2]!=r[sym["rt_turns"]:sym["rt_turns"]+2]:
            raise AssertionError(f"routing {name}: bar/turn accounting")
        captures.append(dict(name=name,sha256=digest,focus=focus,rects={**rects}))
        print(f"routing checkpoint {name}: PASS",flush=True)
        return r
    def resume():
        send("key-up F2")
        wait(5)
    def move(x,y):
        for axis,target,neg,pos in (("poll_byte",x,"LEFT","RIGHT"),("poll_line",y,"UP","DOWN")):
            for _ in range(90):
                r=read()
                delta=target-r[sym[axis]]
                if abs(delta)<=1: break
                key=pos if delta>0 else neg
                send("key-down "+key)
                wait(min(20,max(1,abs(delta)-1)))
                send("key-up "+key)
                wait(8)
            else: raise AssertionError("routing pointer steering timeout")
        return read()
    def click():
        send("key-down SPACE")
        wait(20)                  # long hold proves one edge, not one click per frame
        send("key-up SPACE")
        wait(15)
    def require(ok,detail):
        if not ok: raise AssertionError("routing "+detail)
    r=observe("initial")
    resume()
    move(12,45)
    click()
    focus=1
    order=[0,2,1]
    s=observe("cross-owner")
    require(difference(r,s,1,4)==1,"cross-owner click delivery")
    resume()
    move(10,3)
    click()
    r=observe("menu")
    require(difference(s,r,1,1)==1 and difference(s,r,1,12)==1,"menu/deferred delivery")
    require(r[sym["core_defer_count"]]==0 and r[sym["core_defer_busy"]]==0,"menu queue state")
    resume()
    move(50,90)
    click()
    focus=2
    order=[0,1,2]
    s=observe("return-cover")
    require(difference(r,s,2,4)==1,"return-cover click")
    resume()
    move(2,180)
    click()
    focus=0
    r=observe("desktop-focus")
    resume()
    move(50,90)
    click()
    focus=2
    s=observe("sibling-focus")
    require(difference(r,s,2,4)==0,"same-owner activation click was not consumed")
    resume()
    click()
    r=observe("content-edge")
    require(difference(s,r,2,4)==1,"content click edge")
    resume()
    before=move(48,63)
    grab=(before[sym["poll_byte"]],before[sym["poll_line"]])
    send("key-down SPACE")
    wait(12)
    after=move(grab[0]+7,grab[1]+10)
    send("key-up SPACE")
    wait(20)
    dx,dy=after[sym["poll_byte"]]-grab[0],after[sym["poll_line"]]-grab[1]
    rects[2]=(40+dx,60+dy,24,40)
    s=observe("move")
    require(difference(r,s,2,8)==1,"move notification")
    require(tuple(s[sym["rt_last_params"]:sym["rt_last_params"]+2])==rects[2][:2],"move payload")
    resume()
    x,y,w,h=rects[2]
    move(x+w-1,y+h-1)
    send("key-down SPACE")
    wait(12)
    after=move(min(78,x+w+5),min(198,y+h+8))
    send("key-up SPACE")
    wait(20)
    rects[2]=(x,y,after[sym["poll_byte"]]-x+1,after[sym["poll_line"]]-y+1)
    r=observe("resize")
    require(difference(s,r,2,9)==1,"resize notification")
    require(tuple(r[sym["rt_last_params"]:sym["rt_last_params"]+2])==rects[2][2:],"resize payload")
    restore=rects[2]
    resume()
    x,y,w,h=restore
    move(x+w-3,y+6)
    click()
    rects[2]=(0,8,80,192)
    s=observe("maximise")
    require(difference(r,s,2,10)==1,"maximise notification")
    worker=s[0x10200:0x10202]
    resume()
    wait(80)
    r=observe("hidden-worker")
    require(r[0x10200:0x10202]==worker and r[sym["cpc_task_visibility"]+1]==0,"covered worker received CPU")
    resume()
    move(77,14)
    click()
    rects[2]=restore
    s=observe("restore")
    require(difference(r,s,2,10)==1,"restore notification")
    resume()
    send("key-down ESCAPE")
    wait(20)
    send("key-up ESCAPE")
    wait(12)
    r=observe("close-request")
    require(difference(s,r,2,6)>0,"quit close notification")
    resume()
    move(18,23)
    click()
    focus=1
    order=[0,2,1]
    s=observe("legacy-title")
    require(difference(r,s,1,7)==1,"legacy title drag notification")
    resume()
    send("key-down F1")
    for _ in range(100):
        wait(5)
        r=read()
        if r[sym["cpc_phase"]]==0xA5: break
    else: raise AssertionError("routing cleanup timeout")
    send("key-up F1")
    import json
    (artifacts/"routing-checkpoints.json").write_text(json.dumps(captures,indent=2)+"\n")
    return dict(routing_checkpoints=len(captures),input_transport="CPC keyboard matrix")
