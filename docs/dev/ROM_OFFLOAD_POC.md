# GEOBENCH.ROM offload — PoC design & findings (#152)

Goal of the PoC (from #152): run `fs_read_sector` + the FAT16 read path from a 16K
loadable **upper ROM** (`#C000`), prove the IDE desktop boots with the driver living
in ROM, and reclaim resident `#8000` space.

## Key finding: the ROM-paging seam already exists in-tree

`lib/screen.asm` `save_block` already pages the upper ROM in/out to read screen RAM:

```
ld bc,#7F89 / out (c),c   ; upper ROM OFF (mode 1) - #C000 reads = screen RAM
...
ld bc,#7F81 / out (c),c   ; upper ROM ON  (mode 1) - #C000 reads = the selected ROM
```

So GEOBENCH normally runs with the **upper ROM ON** (`#7F81`); reads of `#C000` come
from whatever upper ROM is selected, writes always reach screen RAM. `save_block`
flips it OFF only to read the framebuffer. **The video controller fetches the screen
from RAM independently of the CPU ROM mapping**, so paging the ROM never flickers.

What #152 adds on top:
- **Select the GEOBENCH ROM number** with `OUT (#DF), n` so that, while the upper ROM
  is ON, `#C000` decodes to `GEOBENCH.ROM` rather than UniDOS/whatever.
- Put the offloaded routines behind a **known entry table at `#C000`** and `call` them
  directly (no RSX / firmware ROM-init fragility).

## Why `fs_read_sector` is the ideal first candidate

`lib/fs_fat32_core.asm:fs_read_sector` is a pure leaf op:
- I/O only on the IDE ports `FS_IDE_*` = `#FD08..#FD0F`.
- Reads `lba_tmp`, writes `fs_secbuf` — **both in low RAM (< #C000)**, unaffected by the
  upper-ROM mapping.
- Never touches `#C000`.

So the *same code*, placed in the ROM and called with the ROM paged in, works
unchanged: it reads/writes low RAM and bangs the IDE ports while executing from `#C000`.

## The call seam (resident stub, ~30-50 B)

```
gb_rom_call:            ; e.g. HL = ROM entry offset, or a fixed dispatch index
        di
        ld   bc,#DF00 | GB_ROM_NUM   ; select GEOBENCH.ROM
        out  (c),c
        ld   bc,#7F81               ; upper ROM ON (already the normal state)
        out  (c),c
        call <rom entry>            ; e.g. ROM #C000 + index*3 (a jp table)
        ld   bc,#DF00 | PREV_ROM    ; restore the previously selected ROM number
        out  (c),c                  ; (so save_block's OFF/ON still behaves)
        ei
        ret
```
Open question: whether we must restore `PREV_ROM` or can leave GEOBENCH.ROM selected
permanently (save_block pages the ROM *off* to read the screen, so the selected number
is irrelevant to it). Simplest: select GEOBENCH.ROM once at boot if present, never
restore. Verify nothing else depends on a specific upper ROM staying selected.

## ROM image layout (`rom/geobench_rom.asm`, 16K @ #C000)

```
#C000: jp gbrom_fs_read_sector   ; index 0  - the dispatch table (known entry points)
#C003: jp gbrom_<next>           ; index 1
...
       db "GBROM",1              ; signature for the boot probe (at a fixed offset)
       ; --- routines ---
gbrom_fs_read_sector: ... (copy of fs_read_sector)
       ; FS_IDE_* equ, fs_secbuf / lba_tmp addresses are SHARED with the kernel
       ; (fixed low-RAM addresses) - factor into a shared .inc both sides include.
```

## Boot probe

At boot: page the upper ROM through each slot number, check the `"GBROM"` signature at
the fixed offset. Found -> set a `gb_rom_present` flag + remember the number; route the
FS calls through `gb_rom_call`. Not found -> fall back to the in-RAM `fs_read_sector`
(stock build unchanged).

## PoC milestone (testable)

1. `rom/geobench_rom.asm` + `tools/build_rom.sh` -> `GEOBENCH.ROM` (16K, padded).
2. Shared `lib/fs_shared.inc`: `FS_IDE_*`, `fs_secbuf`, `lba_tmp` addresses (kernel + ROM).
3. Resident `gb_rom_call` stub + `gb_rom_present` probe.
4. Route the kernel's `fs_read_sector` call sites through the stub when present.
5. Drop `GEOBENCH.ROM` into a free `[expansion_roms]` slot in the 1984 config
   (slot_6 is free) and boot the IDE build. **Desktop loads + directory lists from
   IDE => the leaf driver ran from ROM => approach proven.**

## Risks / unknowns

- Exact `OUT (#DF)` ROM-number <-> 1984 expansion-slot mapping (test empirically).
- Whether to restore the previously-selected ROM (see seam note above).
- `di` window length: `fs_read_sector` already runs bounded waits; keep the ROM paged
  in only for the duration of one leaf call.
- Real-HW: M4 / X-MEM / SymbiFACE loadable-ROM slot numbering may differ from 1984.

## Then (beyond PoC)

Move the rest of the FS subsystem (FAT16/32 read+write, FDC floppy, Albireo CH376),
fonts, cursor/hand sprites into the ROM; replace the GBFAT/FLOPPYSV/GBUI *module loads*
with instant ROM calls. Reclaimed resident space unblocks #156 (window maximize gadget)
and future resident chrome.
