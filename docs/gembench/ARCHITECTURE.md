# GEMBENCH architecture

This document describes the intended GEMBENCH boundaries. It is a starting
contract for implementation, not a claim that the target runtime exists yet.

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

The first proof of concept will compare two placements:

1. an app-linked renderer, which is easy to iterate but consumes each app bank;
2. a resident renderer, which saves app space but consumes kernel headroom.

No permanent ABI choice should be made before both variants are measured.

## Resource ownership

`.GBR` is the native, build-time resource format. Version 1 starts with strings
and object trees. Menus, icons, images, shortcuts, and theme metadata will be
added only when their target runtime contracts are ready.

The host compiler owns source validation and emits direct, bounded target data.
The Z80 runtime must not parse JSON, historical GEM `.RSC` files, host pointers,
or unconstrained dynamic structures.

## Runtime invariants

- Keep hot event, object, window, and drawing primitives resident.
- Use fixed-capacity queues and tables with explicit overflow behaviour.
- Merge redundant redraw and pointer events.
- Keep filesystem, firmware, mapper, and painting operations atomic.
- Preserve existing GeoBench entry points while new APIs are introduced.
- Measure resident size, application-bank headroom, stack use, mapper use, VRAM
  use, and repaint latency after every milestone.
- Treat V9938 as the baseline unless an Omega-only V9958 requirement is made
  explicit.

## Integration boundary

The current repository does not contain GeoBench. Before target code is added,
the project needs one documented source relationship: a fork, an imported
history, a subtree, or a pinned sibling dependency. That choice must preserve
the ability to audit upstream changes and reproduce builds.

The initial host compiler and format header are deliberately independent of
that decision.
