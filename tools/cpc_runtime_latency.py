"""M4 cursor cadence regression: ordinary keys, read-only IRQ/position samples.

Use actual video-frame replies AND guest IRQ ticks, never host command duration
or requested frames. Snapshots themselves advance emulation. Video timing also
catches long DI sections that lose IRQ ticks and hide stalls from that counter.
The movement-gap counter covers input gaps that fall between snapshots.
This qualifies the Clock workload, not arbitrary blocking I/O or real hardware.
"""
import hashlib
import json
import re

from cpc_production_lifetime import physical
from cpc_runtime_clock import clock_cache_ready
from cpc_runtime_pixels import verify_pixels
from test_cpc_foundation_1984 import snapshot


def check_latency(rows):
    baseline = rows[0]['steps_per_second']
    for row in rows:
        if row['max_gap_ticks'] > 12:
            raise AssertionError(f"{row['case']}: input gap exceeded 12 IRQ ticks: {row}")
        if row['still_frames'] > 2:
            raise AssertionError(f"{row['case']}: video timing exposes a cursor stall: {row}")
        if row['steps_per_second'] < max(40, baseline * .9):
            raise AssertionError(f"{row['case']}: cursor throughput regressed: {row}")
        if row['seconds'] and not row['draws']:
            raise AssertionError(f"{row['case']}: seconds were not actually drawn")


def run_latency(root, media, manifest, work, sym, artifacts, image, emulator,
                send, wait, read, key, move):
    from test_cpc_runtime_1984 import integrity
    noi = {v[1]: int(v[2], 16) for line in
           (root/'build/universal-obj/uclock/app.noi').read_text().splitlines()
           if len(v := line.split()) == 3 and v[0] == 'DEF'}
    offsets = {v[1]: int(v[2], 16) for line in
               (root/'build/universal-obj/uclock/main.sym').read_text().splitlines()
               if len(v := line.split()) == 4 and v[0] == '1' and v[3] == 'R'}
    def word(r, name): return int.from_bytes(r[sym[name]:sym[name]+2], 'little')
    def value(r, name):
        base = physical(r[sym['wm_table']+50])
        return r[base+noi['s__DATA']-0x4000+offsets['_'+name]]
    rows = []
    stacks = {'main': 0, 'irq': 0, 'tmp': 0}
    has_clock = False
    focus = 1
    seconds = False
    clock_menu = bytes((2, 10))+b'View\0\0\0\0'+bytes((17,))+b'Options\0'
    def checked(name):
        previous = None
        for _ in range(150):
            data = read(name); _, r = snapshot(data)
            if r[sym['sched_fault']]: raise AssertionError('scheduler fault')
            if (r[sym['pointer_visible']] and not r[sym['core_pointer_paintlock']]
                    and not r[sym['core_param_timer_owner']] and not r[sym['io_busy']]
                    and (not has_clock or clock_cache_ready(lambda n: value(r, n)))):
                signature = (bytes(r[0xC000:0x10000]), bytes(r[0x1240:0x1242]))
                turn = word(r, 'cpc_runtime_turns')
                if previous and previous[0] == signature and previous[1] != turn:
                    r, used = integrity(data, sym, work)
                    for k, n in used.items(): stacks[k] = max(stacks[k], n)
                    rects = {1: (11, 66, 58, 68)}
                    if has_clock: rects[2] = (26, 20, 28, 122)
                    order = [0, 1, 2] if has_clock else [0, 1]
                    menu = clock_menu if focus == 2 else bytes((1, 10))+b'Desk\0\0\0\0' if focus == 0 else b'\0'
                    clocks = {2: tuple(value(r, n) for n in ('ph', 'pm', 'ps', 'show_sec'))} if has_clock else {}
                    verify_pixels(r, sym, work, rects, order, {1: 0}, menu,
                                  {2: 'Clock'} if has_clock else {}, clocks=clocks)
                    if r[sym['wm_focus']] != focus: raise AssertionError('unexpected focus')
                    if has_clock and bool(value(r, 'show_sec')) != seconds:
                        raise AssertionError('seconds toggle was not delivered')
                    return r
                previous = signature, turn
            wait(2)
        raise AssertionError(name+': did not reach a complete, stable frame')

    def measure(name):
        # Stay clear of the screen edge for the entire held-key measurement.
        move(75, 8); wait(30)
        start = checked(name+'-before')
        samples = []
        send('key-down DOWN')
        try:
            for _ in range(45):
                reply = wait(2)
                video_frame = int(re.search(r'\bframe=(\d+)', reply)[1])
                h, r = snapshot(read(name+'-moving'))
                y = r[sym['pointer_y']]
                if not 0 < y < 195: raise AssertionError('latency measurement hit screen edge')
                samples.append(dict(y=y, frame=video_frame, irq=word(r, 'cpc_irq_count'),
                    gap=word(r, 'cpc_pointer_max_gap'),
                    pc=int.from_bytes(h[0x23:0x25], 'little'),
                    timer=r[sym['core_param_timer_owner']]))
        finally:
            send('key-up DOWN')
        ticks = (samples[-1]['irq']-samples[0]['irq']) & 65535
        frames = samples[-1]['frame']-samples[0]['frame']
        steps = samples[-1]['y']-samples[0]['y']
        same = samples[0]; still = 0
        for sample in samples[1:]:
            if sample['y'] != same['y']: same = sample
            else: still = max(still, sample['frame']-same['frame'])
        row = dict(case=name, seconds=seconds, irq_ticks=ticks, video_frames=frames, steps=steps,
                   # Video time determines responsiveness. IRQ loss is reported
                   # separately: software-clock accuracy is not a cursor SLA.
                   steps_per_second=50*steps/frames, irq_frame_ratio=ticks/(frames*6),
                   still_frames=still,
                   max_gap_ticks=max(s['gap'] for s in samples),
                   draws=(word(r, 'cpc_runtime_draw_calls')-word(start, 'cpc_runtime_draw_calls')) & 65535)
        rows.append(row)
        (artifacts/(name+'-samples.json')).write_text(json.dumps(samples, indent=2)+'\n')
        print(json.dumps(row), flush=True)
        checked(name+'-after')

    measure('no-clock')
    key('F2'); has_clock = True; focus = 2
    measure('clock-seconds-off')
    key('S'); seconds = True
    measure('clock-focused-seconds')
    move(75, 20); key('SPACE'); focus = 0
    measure('clock-background-seconds')
    check_latency(rows)

    # Move into, through and out of timer damage while it is active. Validate
    # the entire composed surface before any focus change/full repaint can
    # erase a cursor trail. Never click, freeze time, or inject guest RAM.
    for y in (45, 75, 120):
        for x in (40, 20, 75):
            move(x, y)
            checked(f'pointer-crossing-{x}-{y}')
    key('F2'); focus = 2
    key('S'); seconds = False
    measure('clock-seconds-off-again')
    check_latency(rows)
    if image.read_bytes() != (media/'RUNTIME.IMG').read_bytes():
        raise AssertionError('read-only latency scenario changed M4 media')
    report = dict(cases=rows, stack=stacks, files=manifest['files'],
                  emulator_sha256=hashlib.sha256(emulator.read_bytes()).hexdigest())
    (artifacts/'result.json').write_text(json.dumps(report, indent=2)+'\n')
    print('PASS cursor cadence and moving save-under '+json.dumps(report), flush=True)
    return artifacts
