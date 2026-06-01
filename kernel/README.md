# kernel/

The resident GEOBENCH OS kernel — the code that stays in memory the whole time
the desktop is running.

## Responsibilities

- **Boot / init** — set up the memory map, video mode, and interrupt handling,
  then hand control to the desktop shell.
- **Memory management** — track free RAM and the banked 128K memory map; hand
  out and reclaim blocks for applications and system buffers.
- **Application loading** — load app binaries from disk on demand and transfer
  control to them (GEOS-style: small resident kernel, apps come and go).
- **System services / API dispatch** — the call gate applications use to reach
  kernel and library routines (graphics, windowing, input, files).
- **Interrupt / timing** — vblank-driven housekeeping (cursor blink, pointer,
  timers).

## Design constraints

- Keep it **small**. Every byte resident is a byte applications can't use.
- Cooperative, single-foreground-app model to start — no preemptive scheduler.
- All hardware addresses and firmware vectors live behind named constants so the
  CPC-vs-CPC+ and 64K-vs-128K differences stay contained.

## Status

Not started. First milestone: boot, set video mode, clear to a desktop, return.
