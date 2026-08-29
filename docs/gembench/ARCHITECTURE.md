# GEMBENCH architecture

This document describes the implemented GEMBENCH boundaries and the constraints
for extending them.

## Layers

```text
GEMBENCH desktop, accessories, and applications
------------------------------------------------
Objects | Resources | Forms | Menus | Events | Shell
------------------------------------------------
GeoBench libgb and stable kernel jump table
------------------------------------------------
GeoBench mapper, VDP, input, and filesystem backends
------------------------------------------------
MSX-DOS2 / Nextor on Omega MSX2 hardware
```

Applications should use the public GEMBENCH and GeoBench contracts. They must
not depend on private kernel labels or access video, mapper, input, or storage
hardware directly.

## Memory model

The design retains GeoBench's 16 KiB page-1 application window at
`0x4000-0x7fff` and its resident kernel at `0x8000` and above. Code running
while page 1 is switched must live outside the switched range, including its
stack and return path.

An application can own one code segment and optional resource or data segments.
Resource references are little-endian offsets or small indices; they are never
live pointers into a mapper segment. The renderer may temporarily map a resource
segment, consume the selected record or payload, restore the application code
segment, and then return.

The first proof of concept compared two placements:

1. an app-linked renderer, which is easy to iterate but consumes each app bank;
2. a resident renderer, which saves app space but consumes kernel headroom.

Milestone 7 measured both variants. The resident candidate does not fit the
current kernel window, while mapper-backing the 306-byte FormRef resource loses
almost all application headroom to strict external validation. Small GBR v1
resources therefore remain embedded and rendered app-side. Milestone 8 froze
that placement-independent resource format and replaced the prototype
window-tail probe with an explicit registration contract. The bounded MSX2
mapper transport remains opt-in for future large-resource experiments; see
[M7-BANKING-DECISION.md](M7-BANKING-DECISION.md) and [ABI-V1.md](ABI-V1.md).

## Resource ownership

`.GBR` is the native, build-time resource format. Version 1 starts with strings
and object trees. Menus, icons, images, shortcuts, and theme metadata will be
added only when their target runtime contracts are ready.

The host compiler owns source validation and emits direct, bounded target data.
The Z80 runtime must not parse JSON, historical GEM `.RSC` files, host pointers,
or unconstrained dynamic structures.

## Runtime invariants

- Keep existing hot input, window, and drawing primitives resident; measure new
  policy layers before assigning them resident space.
- Use fixed-capacity queues and tables with explicit overflow behaviour.
- Merge redundant redraw and pointer events.
- Keep filesystem, firmware, mapper, and painting operations atomic.
- Preserve existing GeoBench entry points while new APIs are introduced.
- Measure resident size, application-bank headroom, stack use, mapper use, VRAM
  use, and repaint latency after every milestone.
- Treat V9938 as the baseline unless an Omega-only V9958 requirement is made
  explicit.

## Event delivery

Milestone 11 retains the existing window procedure as the scheduling and
delivery boundary. An MSX2 application may link `gbevent` and feed each
`gb_msg_t` callback to `gb_event_collect()`. A six-byte caller-owned
subscription selects keyboard, pointer, timer, and window classes; a nine-byte
caller-owned record can report several classes from the same callback.

There is no hidden queue, allocator, resident state, new jump-table slot, or
low-RAM cell. A frame callback samples the published pointer position once,
drains at most one key, and produces at most one timer expiry. Only the latest
pointer position survives between callbacks, so redundant movement is
naturally coalesced and event storage cannot grow. `GB_MSG_FRAME` is a sampling
pulse rather than a window event; other subscribed messages retain their
existing type and three-byte payload. Legacy applications continue to consume
the original callback directly.

## Visible-region repainting

Milestone 12 leaves the kernel's bottom-up compositor and single damage clip
unchanged. The MSX2 Desktop alone links `gbregion` and, at the start of its
existing repaint callback, intersects that damage with its own window and
subtracts opaque windows above it. It redraws once per resulting clip; every
other application still receives exactly one callback per compositor pass.

The caller owns two four-rectangle arrays plus the original damage rectangle
and four control bytes, for a fixed 40-byte state. No allocation, resident
state, public low-RAM cell, or jump-table slot is added. Subtraction emits top,
bottom, left, and right pieces in a stable order. More than four pieces, an
invalid window table, an unknown application page, or duplicate windows in one
page selects one iteration with the original damage clip. Exhaustion and
explicit early exit restore that clip before the compositor continues.

This is deliberately an app-linked source contract rather than a new frozen
binary ABI. It suits an inexpensive opaque backdrop; streaming image renderers
and applications with costly setup keep the legacy single callback. CPC and PCW
also keep that path. The representative MSX2 move skips 71.8% of the damaged
Desktop area while the resident Screen 6/7 kernels remain unchanged.

## Typed scrap

Milestone 13 layers typed scrap over the resident raw clipboard instead of
replacing it. `CLIP_LEN` remains at `0x3E00`, all 510 bytes from `0x3E02` through
`0x3FFF` remain payload, and the existing `gb_clip_set()`, `gb_clip_get()`, and
`gb_clip_len()` calls retain their meanings. MSX2 owns one private metadata byte,
`SCRAP_TYPE` at `0x133D`, outside that payload.

The ordering rule is the synchronization contract. A raw write clears the type
before publishing its new length and data. A typed write also clears the old
type first and writes the new type only after the complete bounded payload is
visible. Readers normalize an empty clipboard or an unknown/stale tag to
`GB_SCRAP_UNTYPED`. Text, bitmap, icon, and file-list are the supported typed
identities; mismatch returns without copying or changing the destination.
Oversized typed input is explicitly truncated to 510 bytes and reports that
result rather than silently wrapping.

`gbscrap` is an MSX2 app-linked source API; it adds no jump-table slot, resource
record, managed-window field, or persistent process. Code-constrained text
clients may link the set/type-only adapter and continue using the resident raw
length/get calls after accepting text or legacy untyped data. Notepad is the
first migration and deliberately accepts raw text from older applications.

A mapper-backed scrap page is not yet justified. The existing segment allocator
is coupled to live application windows, and the shell service does not retain
payloads or own mapper pages. Holding a segment today would reduce the number of
concurrent windows for capacity that common text transfers do not need.
Persistent disk scrap and desk-accessory routing remain separate future work.

## Shell services

Milestone 14 adds a bounded MSX2-only coordination layer over the existing live
window table. It is deliberately not a process manager. A window may advertise
one of seven coarse service classes in private flag bits 5-7 after completing
normal WM registration. Discovery scans the fixed eight-slot z-order from top
to bottom and returns an opaque slot-plus-one handle. Handles are short-lived
and callers should normally use `gb_shell_request()`, which discovers and sends
within one callback turn.

Delivery is synchronous, queue-free, and non-reentrant. The kernel validates the
handle, request, live flag, service registration, and callback before changing
focus. An open request first copies its required fixed 11-byte 8.3 argument into
the existing synchronous drag-name scratch. The kernel then sets one private
low-RAM guard byte, raises and maps the target, sends `GB_MSG_SHELL` through its
ordinary window procedure, restores the caller's mapper bank, clears the guard,
and repaints. The target writes an explicit result in `gb_msg.p1`; nested sends
return busy without mutating focus or arguments. No resident queue, allocator,
payload buffer, mapper segment, or polling loop is introduced.

The standard requests are open, activate, close, and quit. Notepad registers the
text-editor class. It accepts a replacement document only when bounded storage
I/O is idle and the current document is clean; busy or dirty state rejects the
request before changing the name or contents. Accepted open starts the same
512-byte-per-frame loader used at startup. Close and quit reuse the existing
save-confirmation path. File Manager treats provider absence as the legacy
launch path and treats a live provider's busy/rejected response as an atomic
activation rather than creating a duplicate editor.

The implementation appends `GB_MSG_SHELL` after the frozen window messages and
adds the MSX-only `GB_SHELL` jump at `0x80C0`. It does not alter GBR1 bytes, the
legacy 12-byte window descriptor, the explicit 13-byte kind descriptor, or any
existing jump address. CPC and PCW neither export nor link the service and retain
their existing launch behavior.

## Integration boundary

The repository contains GeoBench's complete history and runtime foundation. The
initial import is pinned to upstream commit `6309ff3`; see `UPSTREAM.md` for the
remote and reproduction procedure. Future GeoBench updates are explicit merges
from that upstream rather than copied source snapshots.

GEMBENCH-specific documents live under `docs/gembench/`, format declarations
under `include/gembench/`, and host resource tools alongside the inherited
GeoBench tools. Runtime extensions should remain visibly separated until their
ABI and placement have passed the proof-of-concept measurement gate. The GBR1
and MSX2 managed-window contracts have passed that gate and are frozen as
GEMBENCH-1; future incompatible work must use an explicit version boundary.
