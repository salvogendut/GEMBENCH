# lib/

System libraries shared by the kernel (and, via `gb/`, the C apps). The `.asm`
files are assembled into the kernel; they abstract the CPC's hardware so higher
layers never poke video, storage or input registers directly.

## Kernel libraries (Z80 asm)

| File | Role |
|------|------|
| `gbapp.inc` | The **app ABI**: jump-table addresses, the banked memory model, app load address. Included by the kernel and mirrored by `libgb`. |
| `firmware.inc` | AMSDOS/firmware vector equates used by the kernel. |
| `screen.asm` | Mode 1 drawing: address math, filled rectangles, blits, save/restore. Hides the 320×200 pixel/byte layout. |
| `text.asm` | The 6×8 (sub-byte) proportional text renderer. |
| `font.asm` | Loads a `.FNT` font set into the data bank. |
| `input.asm` | Keyboard/joystick polling -> pointer direction + fire/quit. |
| `cursor.asm` | Software pointer sprite: draw, erase, move with save-under. |
| `cursor_arrow.asm`, `cursor_hand.asm` | Pointer bitmaps. |
| `fs.asm` | Storage dispatcher — picks a backend at boot. |
| `fs_amsdos.asm` | AMSDOS directory + file load over the floppy. |
| `fs_ide_fat.asm` | FAT16 over SYMBiFACE/Cyboard IDE. |
| `bank.asm` | Expansion-RAM paging (the `#4000–#7FFF` window). |
| `config.asm` | `GEOBENCH.CFG` (key=value) parser. |
| `icon_*.asm` | Icon bitmaps, packed into the `.IST` icon set at build time. |

## libgb (`gb/`)

The shared **C bindings** every GEOBENCH app links against:

| File | Role |
|------|------|
| `gb/gb.h` | C prototypes for the kernel API. |
| `gb/gblib.s` | Asm trampolines mapping SDCC's calling convention onto the jump table. |
| `gb/crt0.s` | C startup for a banked app (entry at `#4000`, initializer copy). |

## Design constraints

- **Speed first.** These run on a ~4 MHz Z80; inner loops are hand-tuned asm.
- **One way in.** Each library exposes clear entry points; the kernel and apps
  call the same code rather than duplicating it.
- Mode 1 (320×200, 4 colours) is the assumed surface; pixel-layout assumptions
  stay isolated in `screen.asm`.
