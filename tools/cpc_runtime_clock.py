"""Clock's independent pixel model and M4 runtime integration scenario."""
from cpc_graphics_fixture import put_pixel
import hashlib
import json
from pathlib import Path
from cpc_production_lifetime import physical
from test_cpc_foundation_1984 import snapshot

# Integer design coordinates of the portable watch, independent of APP RAM.
SIN=(0,7,13,20,26,32,38,43,48,52,55,58,61,63,64,64,64,63,61,58,
     55,52,48,43,38,32,26,20,13,7,0,-7,-13,-20,-26,-32,-38,-43,-48,
     -52,-55,-58,-61,-63,-64,-64,-64,-63,-61,-58,-55,-52,-48,-43,-38,-32,-26,-20,-13,-7)
COS=tuple(SIN[(i+15)%60] for i in range(60))


def clock_cache_ready(value, modal=False):
    """A modal may park between completed hand/digit passes. Both are drawable.

    Outside modal polling require the pending digit pass to finish; observers
    still independently require a stable screen and unobstructed draw boundary.
    """
    return bool(value('have_prev') and (modal or (not value('timer_digit_due') and
                (value('ph'),value('pm'))==(value('dh'),value('dm')) and
                (not value('show_sec') or value('ps')==value('ds')))))


def clock_may_remain_parked(rects,order,slot,window_visibility,task_visibility):
    """Conservative independent cover proof, not permission to skip pixels.

    A hidden worker may stop between hand/digit components indefinitely.
    Require one actual foreground rectangle to cover it completely AND both
    scheduler visibility views to agree. Partial/exposed windows still settle.
    """
    if window_visibility or task_visibility or slot not in rects or slot not in order:
        return False
    x,y,w,h=rects[slot]
    for front in order[order.index(slot)+1:]:
        if front not in rects: continue
        fx,fy,fw,fh=rects[front]
        if fx<=x and fy<=y and fx+fw>=x+w and fy+fh>=y+h: return True
    return False


def draw_clock(surface,rect,time,fill,text):
    x,y,w,h=rect;hour,minute,second,seconds=time[:4]
    top=y+14;digital=y+h-16;avail=digital-2-top
    radius=min(w*2-6,avail//2-2);cx=x*4+w*2;cy=top+avail//2
    def scale(n): return (1 if n>=0 else -1)*(abs(n)//64)
    def endpoint(pos,rad):
        return cx+scale(SIN[pos]*rad),cy-scale(COS[pos]*rad)
    def line(start,end,pen):
        ax,ay=start;bx,by=end;dx=abs(bx-ax);dy=abs(by-ay)
        sx=1 if ax<bx else -1;sy=1 if ay<by else -1;error=dx-dy
        while True:
            if x*4<=ax<(x+w)*4 and y<=ay<y+h: put_pixel(surface,ax,ay,pen)
            if (ax,ay)==(bx,by): break
            twice=error*2
            if twice>=-dy: error-=dy;ax+=sx
            if twice<=dx: error+=dx;ay+=sy
    for k in range(0,60,2): line(endpoint(k,radius),endpoint((k+2)%60,radius),1)
    for k in range(0,60,5): line(endpoint(k,radius),endpoint(k,radius*37//44),1)
    line((cx,cy),endpoint(((hour%12)*5+minute//12)%60,radius*20//44),1)
    line((cx,cy),endpoint(minute,radius*30//44),1)
    if seconds: line((cx,cy),endpoint(second,radius*36//44),3)
    width=12 if seconds else 8
    # A native modal may begin between the independent hand and digit damage
    # passes. Model both completed caches; never copy guest pixels as expected.
    dh,dm,ds=time[4:7] if len(time)>4 else (hour,minute,second)
    value=f'{dh:02}:{dm:02}'+(f':{ds:02}' if seconds else '')
    fill(surface,x+(w-width)//2,digital,width,8,0)
    text(surface,x+(w-width)//2,digital,value,1,0)


def run_clock(root,media,manifest,work,sym,artifacts,image,emulator,send,wait,read,key,move):
    from cpc_runtime_pixels import verify_pixels
    from test_cpc_runtime_1984 import integrity
    noi={v[1]:int(v[2],16) for line in (root/'build/universal-obj/uclock/app.noi').read_text().splitlines()
         if len(v:=line.split())==3 and v[0]=='DEF'}
    offsets={v[1]:int(v[2],16) for line in (root/'build/universal-obj/uclock/main.sym').read_text().splitlines()
             if len(v:=line.split())==4 and v[0]=='1' and v[3]=='R'}
    def word(r,name): return int.from_bytes(r[sym[name]:sym[name]+2],'little')
    def value(r,name):
        base=physical(r[sym['wm_table']+50])
        return r[base+noi['s__DATA']-0x4000+offsets['_'+name]]
    rects={1:(11,66,58,68),2:(26,20,28,122)};order=[0,1,2];accents={1:0}
    titles={2:'Clock'};calculators={};clocks={}
    definition=bytes((2,10))+b'View\0\0\0\0'+bytes((17,))+b'Options\0'
    menu=definition;checks=[];max_stack={'main':0,'irq':0,'tmp':0}
    def stable(name):
        previous=None
        for _ in range(150):
            data=read(name);_,r=snapshot(data)
            if r[sym['sched_fault']]: raise AssertionError('Clock caused scheduler fault')
            # Require identical completed pixels across a root-loop boundary.
            # A single unlocked sample can catch the minute-bar refresh halfway
            # through; requiring the PC to be in POLL instead aliases with the
            # frame-boundary snapshot. Sampling a compute-only worker is safe:
            # flat RAM is observed without bank injection, and the changed root
            # turn counter still proves that the root completed another pass.
            if r[sym['pointer_visible']] and not (
                    r[sym['core_pointer_paintlock']] or r[sym['core_param_timer_owner']] or
                    r[sym['io_busy']]):
                if (2 not in rects or
                    clock_may_remain_parked(rects,order,2,r[sym['cpc_wm_visibility']+2],
                                           r[sym['cpc_task_visibility']+2]) or
                    clock_cache_ready(lambda k:value(r,k))):
                    signature=(bytes(r[0xC000:0x10000]),bytes(r[0x1240:0x1242]),
                               tuple(value(r,k) for k in ('ph','pm','ps','show_sec')) if 2 in rects else ())
                    turn=word(r,'cpc_runtime_turns')
                    if previous is not None and signature==previous[0] and turn!=previous[1]:
                        r,used=integrity(data,sym,work)
                        for k,n in used.items(): max_stack[k]=max(max_stack[k],n)
                        return r
                    previous=(signature,turn)
            wait(3)
        raise AssertionError(name+': Clock did not reach a completed update')
    def checked(name):
        r=stable(name)
        if 2 in rects:
            clocks[2]=tuple(value(r,k) for k in ('ph','pm','ps','show_sec'))
        verify_pixels(r,sym,work,rects,order,accents,menu,titles,None,calculators,clocks)
        if r[sym['wm_z']:sym['wm_z']+len(order)]!=bytes(order) or r[sym['wm_nwin']]!=len(order):
            raise AssertionError(name+': window count/order')
        if r[sym['wm_focus']]!=order[-1]: raise AssertionError(name+': focus')
        for slot,rect in rects.items():
            at=sym['wm_table']+25*slot+1
            if r[at:at+4]!=bytes(rect): raise AssertionError(name+': geometry')
        send(f'crop {artifacts/(name+".ppm")} 0 0 768 576 1')
        checks.append(name)
        print(f'{name}: time={clocks.get(2)} worker={word(r,"cpc_runtime_worker_calls")} '
              f'visibility={list(r[sym["cpc_wm_visibility"]:sym["cpc_wm_visibility"]+4])} stack={max_stack}',flush=True)
        return r
    def elapsed(r,seconds=3):
        start=word(r,'cpc_hw_seconds')
        for _ in range(120):
            wait(20);_,after=snapshot(read())
            if (word(after,'cpc_hw_seconds')-start)&65535>=seconds: return
        raise AssertionError('software time did not advance')
    def owner(r): return bytes((r[sym['core_win_owner']+2],r[sym['core_win_owner_gen']+2]))
    key('F2');r=checked('clock-open')
    app=(media/'CARD/GBENCH/CLOCK.APP').read_bytes()
    if (app != (root/'build/universal/CLOCK.APP').read_bytes() or
            hashlib.sha256(app).hexdigest() != manifest['files']['GBENCH/CLOCK.APP']):
        raise AssertionError('Clock differs from the canonical compile-once build')
    initial_owner=owner(r);idx=initial_owner[0]-1;base=physical(r[sym['wm_table']+50])
    if r[base:base+len(app)]!=app: raise AssertionError('loaded Clock bytes differ')
    if r[sym['core_app_accessory']+idx]!=1 or r[sym['core_app_service']+idx]!=0xA0:
        raise AssertionError('Clock accessory identity')
    if r[sym['sched_runnable']]!=2 or not word(r,'cpc_runtime_worker_calls'):
        raise AssertionError('Clock worker was not enabled/scheduled')
    key('S');r=checked('clock-seconds')
    if not value(r,'show_sec'): raise AssertionError('seconds input was not delivered')
    elapsed(r);r=checked('clock-focused-tick')
    # The exposed left side of ABI Probe focuses it without touching Clock.
    move(22,70);key('SPACE');order=[0,2,1];menu=b'\0'
    r=checked('clock-background-partial')
    elapsed(r);r=checked('clock-background-tick')
    key('F2');order=[0,1,2];menu=definition;r=checked('clock-reactivate')
    if owner(r)!=initial_owner or not value(r,'show_sec'): raise AssertionError('activation lost Clock identity/state')

    def quiet_start(name):
        r=stable(name)
        # Exclude the unrelated once-per-minute top-bar refresh from counters.
        if word(r,'cpc_hw_seconds')%60>52:
            elapsed(r,60-word(r,'cpc_hw_seconds')%60);r=stable(name)
        return r
    def unchanged_counters(before,after,names):
        for name in names:
            if word(before,name)!=word(after,name): raise AssertionError('unnecessary work: '+name)
    def drag(slot,x,y):
        ox,oy,w,h=rects[slot]
        move(ox+10,oy+5);_,r=snapshot(read())
        grab=(r[sym['poll_byte']],r[sym['poll_line']])
        send('key-down SPACE');wait(10);move(grab[0]+x-ox,grab[1]+y-oy)
        _,r=snapshot(read());drop=(r[sym['poll_byte']],r[sym['poll_line']])
        send('key-up SPACE');wait(60)
        expected=(max(0,min(80-w,ox+drop[0]-grab[0])),max(8,min(200-h,oy+drop[1]-grab[1])),w,h)
        _,r=snapshot(read());at=sym['wm_table']+slot*25+1
        if r[at:at+4]!=bytes(expected): raise AssertionError('drag differs from pointer displacement')
        rects[slot]=expected

    # Calculator covers every changing component, but not Clock's title.
    key('F7');rects[3]=(24,24,31,144);order.append(3);calculators[3]='0';titles[3]='Calculator'
    menu=bytes((1,10))+b'Edit\0\0\0\0';r=checked('clock-components-covered')
    before=quiet_start('components-before');elapsed(before);r=checked('clock-components-park-paint')
    if r[sym['cpc_wm_visibility']+2]!=1: raise AssertionError('title-only Clock should remain partial')
    if word(r,'cpc_runtime_worker_calls')==word(before,'cpc_runtime_worker_calls'):
        raise AssertionError('partially visible worker was incorrectly stopped')
    unchanged_counters(before,r,('cpc_runtime_draw_calls','pointer_saves','pointer_restores'))

    drag(3,39,24);r=checked('clock-partial-exposure')
    # Pointer on the covering window, inside the old bounding damage, must
    # remain untouched; only Clock's exact uncovered fragments are painted.
    move(42,75);before=quiet_start('partial-before')
    # Require a genuinely exposed moving hand. During seconds 0..30 the hand
    # and seconds digits can both be entirely behind Calculator. Clipped line
    # rejection now correctly does zero raster work in that interval.
    second=word(before,'cpc_hw_seconds')%60
    if not 35<=second<=44:
        elapsed(before,(35-second)%60);before=quiet_start('partial-before')
    elapsed(before);r=checked('clock-partial-tick')
    if word(r,'cpc_runtime_draw_calls')==word(before,'cpc_runtime_draw_calls'):
        raise AssertionError('partially visible Clock did not paint')
    unchanged_counters(before,r,('pointer_saves','pointer_restores'))

    move(36,60);before=quiet_start('under-pointer-before');elapsed(before)
    checked('clock-update-under-pointer')
    move(5,180);checked('clock-pointer-save-under-restored')

    # A taller foreground window now covers the complete Clock, including title.
    drag(3,24,8);r=checked('clock-fully-covered')
    if r[sym['cpc_wm_visibility']+2] or r[sym['cpc_task_visibility']+2]:
        raise AssertionError('fully covered Clock was not parked')
    before=quiet_start('hidden-before');elapsed(before);r=checked('clock-hidden-no-work')
    unchanged_counters(before,r,('cpc_runtime_worker_calls','cpc_runtime_draw_calls','pointer_saves','pointer_restores'))
    if r[base+0x3F00:base+0x4000]!=before[base+0x3F00:base+0x4000]:
        raise AssertionError('parked worker snapshot changed')
    if r[sym['core_param_timer_owner']]: raise AssertionError('hidden timer was not drained')

    key('F2');order=[0,1,3,2];menu=definition;r=checked('clock-hidden-reactivation')
    if owner(r)!=initial_owner or not value(r,'show_sec'): raise AssertionError('hidden activation lost identity/state')
    key('F2');r=checked('clock-repeat-activation')
    if owner(r)!=initial_owner: raise AssertionError('duplicate Clock owner')
    key('ESCAPE');del rects[2];del clocks[2];order.remove(2);menu=bytes((1,10))+b'Edit\0\0\0\0'
    r=checked('clock-close-cleanup')
    for name in ('core_app_service','core_app_accessory',
                 'core_defer_handler_lo','core_defer_handler_hi'):
        if r[sym[name]+idx]: raise AssertionError('Clock cleanup leaked '+name)
    if r[sym['core_app_worker_win']+idx]!=255:
        raise AssertionError('Clock cleanup retained a worker slot')
    if r[sym['sched_runnable']]!=1 or r[sym['core_param_timer_owner']]:
        raise AssertionError('Clock cleanup left runnable/timer state')
    before=quiet_start('closed-before');elapsed(before);r=checked('clock-closed-no-work')
    unchanged_counters(before,r,('cpc_runtime_worker_calls','cpc_runtime_draw_calls','pointer_saves','pointer_restores'))
    key('F2');rects[2]=(26,20,28,122);order.append(2);menu=definition;r=checked('clock-relaunch')
    if owner(r)==initial_owner or value(r,'show_sec'): raise AssertionError('Clock did not relaunch with fresh state')
    fresh=owner(r)
    for slot in range(4,8):
        key('F3');rects[slot]=(11,66,58,68);order.append(slot);accents[slot]=0
    menu=b'\0';checked('clock-full-window-table')
    key('F2');order.remove(2);order.append(2);menu=definition;r=checked('clock-activate-while-full')
    if owner(r)!=fresh: raise AssertionError('full-table activation created a duplicate')
    key('F4');r=checked('clock-live-with-M4-service')
    if r[sym['cpc_runtime_fs_status']] or r[sym['cpc_runtime_fs_calls']]!=1:
        raise AssertionError('M4 service failed while Clock worker was live')
    if image.read_bytes()!=Path(manifest['image']).read_bytes():
        raise AssertionError('Clock run changed read-only M4 files')
    report=dict(checkpoints=checks,sections=manifest['sections'],stack=max_stack,
                app_sha256=hashlib.sha256(app).hexdigest(),
                emulator_sha256=hashlib.sha256(emulator.read_bytes()).hexdigest())
    (artifacts/'result.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS universal Clock/shared worker '+json.dumps(report),flush=True)
    return artifacts
