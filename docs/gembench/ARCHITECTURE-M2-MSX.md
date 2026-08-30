# Architecture Milestone 2: MSX2 applications and windows

Status: **implemented on the MSX2 target in issue
[#32](https://github.com/salvogendut/GEMBENCH/issues/32)**.

Milestone 2 completes the first useful slice of improvement 3 from the
SymbOS-inspired architecture review. The generation-tagged owner introduced by
Milestone 1 is now a real application record, windows point to that application
instead of defining its lifetime, and one mapped code page may own several
independently managed windows. CPC and PCW retain the inherited one-window
lifecycle and do not advertise these capabilities yet.

## Application and window records

The resident MSX2 implementation has two independent fixed-capacity tables:

- eight application records, identified by the existing opaque `gb_owner_t`;
- eight frozen compositor records, each with a parallel application link and a
  nonzero reuse generation.

An application record owns its primary code mapper segment/page handle, live
window count, primary window, lifecycle flags, shell service/accessory identity,
and optional worker window. The existing 25-byte compositor record does not
move or grow. Its private parallel owner bytes from Milestone 1 now link it to
the application, and a new parallel generation byte creates an opaque
`gb_window_t` whose low byte is slot plus one and high byte is the generation.

The loader allocates the application before loading its primary page. The first
window consumes the pending application identity; later windows find the same
application from the mapped code page. A failed or non-registering load still
releases its pending application and primary page.

## Lifecycle rules

Closing a window now performs these steps on MSX2:

1. mark only that compositor record dead and remove it from z-order;
2. detach its application link and invalidate its window handle;
3. update the application's window count, primary window, and worker link;
4. keep the application/code page alive while another owned window remains;
5. release the application and all owned mapper pages only after its last
   window closes.

`gb_app_quit()` marks the application terminating, closes every owned window,
and releases an already-windowless application. It rejects the Desktop root.
Legacy one-window applications retain their previous observable behavior: their
only close is also their application teardown.

Only one optional scheduled worker window is recorded per application in this
milestone. The 503-byte fixed scheduler remains unchanged and continues to
snapshot work by window slot; application ownership is authoritative for close
cleanup. Message queues, priorities, multiple workers, process hierarchies, and
cross-application window operations remain later work.

## Public API

The append-only MSX jump table adds `GB_APP` at `0x80CC`. Applications opt into
its small bindings with `SYS=1`:

```c
unsigned char gb_app_publish(void);
unsigned char gb_app_quit(void);
gb_window_t gb_window_current(void);
unsigned char gb_window_close(gb_window_t window);
unsigned char gb_window_check(gb_window_t window);
unsigned char gb_window_slots_free(void);
unsigned char gb_app_window_count(void);
unsigned char gb_window_drag(void);
```

Window close/check reject stale generations and handles belonging to another
application. `gb_app_publish()` makes an explicitly windowless application
independent of the loader's pending state. `gb_window_drag()` validates the
focused window and reuses the resident managed-window outline engine; Paint
therefore does not carry a second copy of that engine in its code page.

The status values are `GB_APP_OK`, `GB_APP_ERR_STALE`,
`GB_APP_ERR_OWNER`, `GB_APP_ERR_FULL`, `GB_APP_ERR_ROOT`, and
`GB_APP_ERR_BADARG`. Window handles are short-lived runtime capabilities, not
persistent IDs and not compositor slots.

## Capability record v2

`GB_SYSINFO` retains its complete 20-byte v1 prefix and now returns a 24-byte v2
record. The appended bytes are:

| Offset | Bytes | v2 field |
| ---: | ---: | --- |
| 20 | 1 | maximum application records (`8`) |
| 21 | 1 | application-record implementation version (`1`) |
| 22 | 1 | maximum windows owned by one application (`8`) |
| 23 | 1 | reserved, zero |

The record advertises `GB_CAP_APPLICATIONS` (`0x0200`) and
`GB_CAP_MULTI_WINDOW` (`0x0400`). Consumers must inspect `size`, `version`, and
capability bits rather than assume these fields exist on another target.

## Shell services and workers

Shell service class and exact Desk accessory ID now belong to the application
record. The old window flag/argument values remain compatibility mirrors, while
find/send resolve the target through its application. A multi-window service is
therefore discoverable through its topmost owned window without duplicating
registration state in every pane.

If a managed descriptor supplies a worker callback, the application records the
first such window. Closing that window clears the worker link and scheduler
runnable count while sibling windows keep the application alive.

## In-tree Paint migration

The MSX2 Paint source under `apps/paint/` is the representative multi-window
application:

- Toolchest is the durable primary window;
- Preview appears for an open picture and may close without quitting Paint;
- Canvas appears after selecting an area and may close independently;
- all three records share one application owner and one code mapper page;
- document close releases Preview, Canvas, and the borrowed document page while
  Toolchest survives; and
- Quit uses application teardown and reclaims every remaining window/page.

Paint's former invisible full-screen workspace, manual pane z-order, and
private drag engine are absent from the MSX build. The resulting `PAINT.APP` is
15,710 bytes, 43 bytes smaller than the imported one-window baseline.

The initialization order also preserves an incoming `.PIC` name before loading
`PAINT.IST`; this fixes launch-document recognition that the lifecycle test
exposed.

## Resident storage and limits

The Milestone-2 private tables occupy fixed page-3 RAM at `0xC308-0xC35D`:
application code-page metadata, counts, primary/worker slots, flags,
service/accessory values, eight window generations, and lifecycle scratch.
Together with Milestone 1, the private architecture area spans
`0xC200-0xC35D`, below the fixed glue ceiling at `0xC900`.

The release preemptive kernels build to 13,498 bytes (Screen 6) and 15,076 bytes
(Screen 7). The scheduler remains exactly 503/512 bytes. The compositor and
application tables are both bounded to eight, while the mapper pool remains an
independent runtime quantity (25 pages on the reference 512 KiB configuration).

## Validation

```sh
make gembench-msx
make gembench-m2-openmsx
make gembench-m2-paint-openmsx
MSX_HEADLESS=1 tools/test_shell_service_openmsx.sh
MSX_HEADLESS=1 tools/test_desk_accessories_openmsx.sh
```

The API diagnostic creates a second window, verifies the shared owner/count and
free-slot values, closes it by opaque handle, proves the old handle stale, then
closes/reopens the application and observes both owner and window generation
advance.

The existing shell-service and Desk-accessory probes guard the compatibility
mirrors while the authoritative class and exact accessory identity live in the
application record.

The Paint run opens a real 176x176 `.PIC`, observes Toolchest and Preview under
one owner/code page, opens Canvas as the third owned window, and drags all three
panes before continuing to interact with them. It closes Canvas alone, closes
the document while Toolchest survives, and finally quits. It finishes at two
baseline windows/owners and restores all mapper pages used by Paint.

## Target boundary

Only `PLATFORM_MSX` exports `GB_APP`, sysinfo v2, and the application tables.
The public source types remain target-neutral for a later CPC/PCW backend, but
those targets must not advertise `GB_CAP_APPLICATIONS` or
`GB_CAP_MULTI_WINDOW` until their own lifecycle, memory-bank, graphics, and
emulator tests implement the same contract.
