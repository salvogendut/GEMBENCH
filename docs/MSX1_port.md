# MSX1 port investigation

Status: design memory only. No MSX1 implementation exists yet.

## Feasibility

The current MSX2 binaries cannot run on an MSX1. They require the V9938,
MSX-DOS 2/Nextor mapper services, and one of these 512x212 bitmap modes:

- Screen 6: 2 bits per pixel, approximately 27 KB of VRAM.
- Screen 7: 4 bits per pixel, approximately 54 KB of VRAM.

A TMS9918 MSX1 with 16 KB of VRAM cannot provide either mode or the V9938
command engine. An MSX1 port is nevertheless feasible as a separate 256x192
Screen 2 target.

## Recommended target

The practical initial hardware profile is:

- MSX1 with a TMS9918-compatible VDP and 16 KB VRAM.
- At least a 256 KB memory mapper; 512 KB is recommended.
- Nextor or another environment exposing the mapper and the file services used
  by GEOBENCH.

A stock 64 KB MSX1 is not an initial target. GEOBENCH assigns separate 16 KB
mapper segments to kernel data and applications. Supporting a machine without
a mapper would require a reduced, probably single-application memory model and
substantial loader changes.

## Video model

The new backend would use TMS9918 Screen 2 at 256x192. Screen 2 can consume most
of the 16 KB VRAM with a name table, pattern table, colour table, and sprite
data, but it is not a conventional packed-pixel framebuffer. Each eight-pixel
row of a pattern is restricted to one foreground and one background colour.

Consequences:

- Add `PLATFORM_MSX1` for the kernel and `GB_MSX1` for applications.
- Use a 256x192 application geometry, approximately 64 GEOBENCH byte columns.
- Implement software text, fill, frame, line, blit, save and restore operations
  over Screen 2 pattern and colour tables.
- Add an MSX1 sprite-pointer implementation.
- Reduce canonical four-colour assets at runtime to the two colours available
  in each Screen 2 pattern row.
- Do not support Screen 7 pictures, sixteen-colour application icons, or extra
  VRAM pages.

The backend must be compiled as a separate target so it adds no resident bytes
to the CPC, PCW, or MSX2 kernels.

## Application impact

Most shared applications already use `GB_COLS`, `GB_LINES`, and `GB_XPIX`, but
the much narrower display still requires a layout audit. Fullscreen and wide
applications such as Browser, Telnet, Paint, Settings, and Mahjong need compact
MSX1 layouts. Desktop, File Manager, Notepad, Clock, and Calculator are the best
initial application set.

Portable `.PIC`, `.IST`, `.SPR`, `.TBR`, and `.GDT` artifacts should remain
canonical. Any MSX1 colour or pattern conversion belongs in the MSX1 runtime
backend rather than in distribution-building scripts.

## Proposed milestones

1. Build a `PLATFORM_MSX1` kernel that enters Screen 2, clears the display,
   renders the shared font, and restores the original mode on exit.
2. Implement pointer input and the core drawing/window primitives.
3. Boot Desktop and run File Manager using Nextor-backed storage and mapper
   allocation.
4. Audit and adapt the small core applications for 256x192.
5. Add canonical asset conversion, Viewer support, and restricted-colour
   pictures.
6. Evaluate Browser, Telnet, sound, and screensavers after the desktop is
   stable.
7. Consider a separate stock-64KB profile only after measuring the completed
   mapper-based build.

## Main risks

- Screen 2 colour restrictions may make the current four-pen UI difficult to
  reproduce clearly without carefully selected colour pairs.
- Software rendering will be slower than the V9938 command-based backends.
- Some application layouts assume the current 512-pixel MSX2 width despite
  using shared geometry constants.
- DOS and mapper availability vary considerably between expanded MSX1 systems.

The first decision point is a small Screen 2 prototype: shared font, one themed
window, pointer sprite, and repaint/save-under timing on real or accurately
emulated MSX1 hardware.
