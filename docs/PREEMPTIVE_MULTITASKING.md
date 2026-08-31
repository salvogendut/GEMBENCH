# Preemptive application workers on MSX2

GEMBENCH release builds use an app-carried, fixed-RAM scheduler for opted-in
pure application workers. The desktop root task remains responsible for the
kernel, filesystem, window manager, compositor, input, and paged modules.

This is not arbitrary kernel preemption. Shared machine services stay atomic;
only code built with the task profile may run in a worker context.

## Build profiles

```sh
make msx                       # release default: preemptive workers enabled
make msx-preemptive            # compatibility alias
make msx-cooperative           # scheduler-free regression image
make msx-preemptive-diagnostic # stages the TASKDEMO stress worker
```

`tools/build_scheduler.sh` accepts only the `msx` target and enforces the 1,536
byte fixed-RAM payload limit.

## Timer and context path

The MSX2 adapter hooks H.TIMI and uses the VDP frame cadence. Context switches
save the complete Z80 register state and bounded task stack, retain the caller's
mapper segment, and restore the correct page before returning. Page-3 glue stays
visible while BIOS ROM mappings are active.

Scheduler locks prevent switching while the root task owns a non-reentrant
kernel operation. Applications cannot opt arbitrary UI or filesystem code into
a worker; worker code must communicate through bounded owner-safe mailboxes.

## Visibility priority

Application owners aggregate the visibility of all their windows. Runnable
visual workers are ordered:

1. focused application;
2. fully visible applications;
3. partially visible applications;
4. background/nonvisual work.

A fully covered visual worker is parked. When z-order or geometry changes, the
compositor refreshes visibility state before scheduling and emits exact exposed
damage for affected surfaces.

Clock demonstrates the production timer path: its worker publishes a bounded
damage rectangle and the desktop validates the owner/window generation before
painting. XAOS demonstrates pure fixed-point computation in a worker. TASKDEMO
is diagnostic-only and intentionally never yields.

## Validation

```sh
make gembench-m8-timer-openmsx
tools/test_visible_regions_openmsx.sh
```

The first test proves background Clock progress and occlusion safety. The second
exercises fully covered, partially visible, focus, and multi-window Paint
workflows through the global compositor and scheduler.
