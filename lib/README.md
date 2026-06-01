# lib/

Reusable system libraries shared by the kernel, the desktop shell, and
applications. These abstract the CPC's hardware so higher layers never poke
video or input registers directly.

## Planned libraries

| Library | Role |
|---------|------|
| **graphics** | Low-level drawing on the CPC video hardware: clear, plot, lines, rectangles, blitting bitmaps, clipping. Hides the Mode 1 pixel/byte layout. |
| **window** | Window primitives: regions, clipping rectangles, redraw, z-order. Built on top of graphics. |
| **input** | Mouse and keyboard polling, a software pointer sprite, and event delivery (clicks, drags, keypresses). |
| **font** | Proportional bitmap fonts and text rendering (GEOS-inspired). |
| **gadget** *(later)* | Reusable UI controls: buttons, scrollbars, list views. |

## Design constraints

- **Speed first.** These run on a ~4 MHz Z80; inner loops are hand-tuned asm.
- **No hidden state coupling.** Libraries expose clear entry points so apps and
  the desktop call the same code.
- Mode 1 (320×200, 4 colours) is the assumed default surface; keep the pixel
  layout assumptions isolated in the graphics library so other modes are
  possible later.

## Status

Not started. The graphics library is the foundation everything else needs first.
