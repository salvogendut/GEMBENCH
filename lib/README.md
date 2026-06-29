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
| `fs_albireo.asm` | CH376/Albireo backend (the chip does FAT in firmware) — the shipped card backend. |
| `fs_ide_fat.asm` | _Archived_ — FAT16/FAT32 over SYMBiFACE/Cyboard IDE (mount + write + seam). See `docs/ARCHIVED.md`. |
| `fs_ide_read.asm` | _Archived_ — the IDE FAT read backend (dir + load), shared by the ROM. |
| `fs_m4.asm` | File-level FAT over the M4 board (#174/#259): directory, load, and save/create for the shared card image; delete remains pending. |
| `fs_rom_seam.asm`, `fs_*_lowram.inc` | #152 ROM offload: the seam that pages `GEOBENCH.ROM` in + the fixed low-RAM addresses the resident stubs and the ROM share. |
| `bank.asm` | Expansion-RAM paging (the `#4000–#7FFF` window). |
| `config.asm` | _Orphaned_ — the old resident `GEOBENCH.CFG` (key=value) parser. Superseded by the paged `GBCFG.MOD` (`kernel/kc/kcfg.c`); kept in-tree only until nothing references it. |
| `icon_*.asm` | Icon bitmaps, packed into the `.IST` icon set at build time. |

## libgb (`gb/`)

The shared **C bindings** every GEOBENCH app links against:

| File | Role |
|------|------|
| `gb/gb.h` | C prototypes for the kernel API. |
| `gb/gblib.s` | Asm trampolines mapping SDCC's calling convention onto the jump table. |
| `gb/crt0.s` | C startup for a banked app (entry at `#4000`, initializer copy). |
| `gb/gbdoc.c` | The `gb_doc` document framework: registers an app's buffer + new/open/save hooks and drives the shared File/Edit/View menus. |
| `gb/gbwin.c` | Window chrome helpers an app links in (drag/resize against the kernel WM). |
| `gb/gbdlg.c`, `gb/gbpick.c`, `gb/gbprompt.c` | Dialog/menu/file-picker/prompt renderers — compiled into the paged `GBUI.MOD`, not into every app bank. |
| `gb/gbui_stub.c`, `gb/gbnet_stub.c` | Thin app-side stubs that call the paged `GBUI.MOD` / active network module (`GBNET.MOD` or `GBNETM4.MOD`) through the kernel. |

## Design constraints

- **Speed first.** These run on a ~4 MHz Z80; inner loops are hand-tuned asm.
- **One way in.** Each library exposes clear entry points; the kernel and apps
  call the same code rather than duplicating it.
- Mode 1 (320×200, 4 colours) is the assumed surface; pixel-layout assumptions
  stay isolated in `screen.asm`.
