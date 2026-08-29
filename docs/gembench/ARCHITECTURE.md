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
