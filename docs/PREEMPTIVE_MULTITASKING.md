# Preemptive Multitasking

Issue [#477](https://github.com/salvogendut/geobench/issues/477) tracks the
incremental conversion from the callback-driven cooperative window manager to
preemptively scheduled application workers. This remains an opt-in development
build. Normal release builds retain the existing cooperative behavior and pay
no resident-kernel cost.

## Non-ROM Architecture

Preemption does not use `GEOBENCH.ROM`, the M4 ROM, or a ROM-backed CPC kernel.
`tools/build_scheduler.sh` assembles a target-specific scheduler payload of at
most 512 bytes. The preemptive build embeds that payload in `DESKTOP.APP`; the
desktop copies it to fixed RAM and initializes it before entering the window
manager:

- CPC and PCW: `#3C00-#3DFF`;
- MSX2: page-3 RAM at `#C900-#CAFF`.

The same CPC binary model therefore works with floppy, Albireo, and M4 storage.
`PREEMPTIVE=1` is deliberately rejected when `GB_ROM_REQ=1` so a development
build cannot accidentally acquire a GEOBENCH-ROM dependency.

The CPC timer adapter does use the computer's standard firmware interrupt
handler, as the cooperative system already does for input and timing. That is a
machine service, not scheduler storage: all GEOBENCH scheduler code remains in
RAM and arrived from disk with `DESKTOP.APP`.

## Execution Model

The desktop is the root task. It continues to own the compositor, input,
firmware calls, storage, paged modules, and window-manager policy. Once per WM
cycle it yields only when at least one worker is runnable.

An application becomes a worker explicitly by calling `gb_task_enable()` after
registering its window. Its legacy `on_frame` callback then performs background
computation, while `on_repaint` remains compositor-owned. Existing applications
are not opted in and continue to run cooperatively without source changes.

The CPC timer can interrupt a worker that never yields. It cannot preempt the
resident kernel, a paged module, firmware, storage code, or the compositor.
Blocking I/O therefore still blocks the system at this stage.

## Context And Stack

The Z80 has no protected mode or hardware task context. Every active task uses
the platform's existing fixed stack. At a switch, the scheduler saves all main
and alternate registers and copies only the live `BOOT_SP-SP` bytes into the
owning application bank at `#7F00-#7FFF`. Restoring a task copies those bytes
back before restoring its registers.

This design consumes 256 bytes in each participating application bank instead
of allocating eight fixed-RAM stacks. `tools/build_capp.sh` requires
`TASK_STACK_RESERVE=256` for task builds and rejects any linked image whose
code, data, or BSS reaches the reserved range.

Eight scheduler-state bytes reuse the retired `REPAINT_HDLR` block at
`#1340-#1347`. The scheduler's emergency stack overlays `#1450-#1480` only while
application execution is interruptible; that scratch is not live then.

## CPC Interrupt Path

The CPC adapter installs a three-byte jump in writable IM-1 vector RAM at
`#0038` only after a worker becomes runnable. A six-tick quantum at the CPC's
300 Hz interrupt rate gives a nominal 50 Hz scheduling slice.

On a worker interrupt, the adapter switches only when all of these checks pass:

- execution is in the mapped application page (`#4000-#7FFF`);
- the mapped bank still belongs to the current WM slot;
- scheduler/kernel work is not locked.

Fast paths tail-call the normal CPC firmware interrupt handler immediately. If
a switch is due, the scheduler first restores the selected task's registers and
stack, then tail-calls that same handler. Firmware therefore receives its exact
native interrupt stack contract on every tick; keyboard, pointer, clock, sound,
and firmware events continue at their normal rate. The scheduler also preserves
the alternate Z80 register set used internally by the CPC firmware. Exit to
BASIC/DOS restores the standard `JP #B941` IM-1 vector.

## Build And Diagnostic

Use `make cpc-preemptive` for the RAM-resident CPC development distribution.
The scheduler is embedded automatically in `DESKTOP.APP`; no scheduler file or
ROM is required on the target media.

`TASKDEMO.APP` is the deterministic test worker. Its compute callback never
yields, so a responsive desktop while it runs proves timer preemption rather
than cooperative progress. Build it with `make taskdemo`; it is not staged in
normal distributions. Defining `GB_PREEMPTIVE_DIAGNOSTIC` for the desktop
auto-opens it for emulator tests.

## Budget

- Normal `PREEMPTIVE=0` resident-kernel cost: **0 bytes**.
- Scheduler image: **at most 512 bytes**, carried by the desktop and installed
  in fixed RAM.
- Scheduler state: **0 new low-RAM bytes**, reusing eight retired bytes.
- Participating application reserve: **256 bytes per app bank**.
- CPC preemptive transfer buffer: **6.5 KiB** (`#2200-#3BFF`) instead of the
  cooperative build's 7 KiB; arbitrary-size copy remains chunked.

Every preemptive payload records the largest copied fixed-stack context in
`SCHED_STACK_MAX` and latches `SCHED_FAULT` if a context exceeds 255 bytes. This
telemetry lives inside the already reserved scheduler state and does not add
resident-kernel bytes.

## Platform Status

- **CPC:** RAM-resident context engine and firmware-compatible timer adapter
  are implemented. Two simultaneous non-yielding workers have run for an
  extended emulator stress test with exact 300 Hz firmware-time progression,
  a 32-byte maximum observed context, and no stack fault.
- **MSX2:** fixed-RAM payload location and shared context format are defined;
  H.TIMI/mapper-safe timer glue still needs implementation and stress testing.
- **PCW:** fixed-RAM payload location and shared context format are defined;
  a platform timer source still needs implementation and stress testing.

MSX2 and PCW must remain cooperative until their timer adapters pass the same
non-yielding-worker, input, repaint, storage, close, and exit tests as CPC.
