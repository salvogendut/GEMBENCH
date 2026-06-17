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

## Status (in progress)

- [x] `rom/geobench_rom.asm` + `tools/build_rom.sh` -> 16K `rom/GEOBENCH.ROM` (dispatch
      table + `"GBROM"` signature, verified).
- [x] **`lba_tmp` relocated to a fixed `#1250`** (`lib/fs_fat32_core.asm`, free gap
      `#124A-#12FF`) so the ROM copy reads the same bytes; reclaims 4 resident bytes as
      a bonus (kern_end `#A186` -> `#A182`, slack 2 -> 6). Kernel builds clean.
- [x] **Real `gbrom_fs_read_sector` body in the ROM** (verbatim `fs_read_sector`,
      sharing `FS_IDE_*` / `fs_secbuf #1800` / `lba_tmp #1250`). ROM builds; `jp #C009`
      reaches the body.
- [x] Resident `gb_rom_call` stub (`di` / `OUT (#DF),num` / `OUT (#7F),#85` / `call #C000` / restore / `ei`).
- [x] Boot probe: scan ROM numbers for the `"GBROM"` signature at `#C003`; store the
      number in `gb_rom_num` (`#1254`).
- [x] Route the kernel's `fs_read_sector` through it when present (dispatcher; guarded by
      conditional assembly so the paged `gbfat.asm` copy stays in-RAM).
- [x] Boot the IDE build with `GEOBENCH.ROM` in a free `[board:cyboard]` slot (slot_6);
      desktop + File Manager directory listing load from IDE => **driver ran from ROM. ✅**

ROM-number<->slot mapping confirmed empirically in 1984: `OUT (#DF),6` selects
`[board:cyboard] slot_6`; the probe finds `"GBROM"` and sets `gb_rom_num=6`.

## FAT WRITE offload — DONE ✅ (validated on FAT32)

The FAT *write* path (save/delete) now runs from `GEOBENCH.ROM` too. Validated headless: a ROM
write on a FAT32 volume creates the file with correct content and leaves the filesystem
**fsck-clean** (no cross-links/broken chains; only the cosmetic FSINFO free-count hint is off by
one - a pre-existing gbfat behavior, identical to the paged module). The FAT16 read path still
boots to the desktop. Builds: GBIDE (FAT16) `8543 B`, fits budget.

> NOTE: the gbfat write path is **FAT32-only** (`fs_alloc_cluster`/`fs_fat_set` assume 4-byte
> FAT entries). Writing to a **FAT16** volume corrupts it - this is a pre-existing limitation,
> NOT the offload (the paged module does the same). Test write offloads on a FAT32 image, and
> always `fsck.fat -n` after - a "saved OK" border does not prove FS consistency.

**Architecture (done):**
- ROM is read-only, so the write path's WRITABLE scratch can't live in it. The shared core
  (`fs_fat32_core.asm`) + the gbfat module relocate their state to a fixed low-RAM block via
  `FS_STATE_LOWRAM` / `FS_STATE_BASE = #1C00` (free gap above `fsam_buf #1A00`, below
  `GBFAT_DATA #2200`). Core state = `#1C00+0..+42` (`FS_CORE_STATE_END=+43`); gbfat state =
  `+43..+102`. The `else` branch keeps the original `defs` so the resident read path + paged
  module are byte-identical (verified: GBIDE.BIN unchanged, GBFAT.RAW byte-identical).
- `gbfat.asm` made ROM-includable (guard `org`/`save` with `GBFAT_AS_INCLUDE`, add a
  `gbfat_entry` label). The ROM (`geobench_rom.asm`) now: `#C000` jp fs_read_sector (idx0),
  `#C003` "GBROM" sig, `#C009` jp gbfat_entry (idx1), then `include ../kernel/modules/gbfat.asm`
  (one shared core serves read idx0 + write). Resident `gb_rom_call_write` (calls `#C009`) +
  `gbfat_run` routes to the ROM when present, else the paged fallback.

**Validation (headless):** built with a temporary `-DGBWTEST` harness (save a file right after
`fs_sys_resolve`, then hang; WHITE border = saved). On a **FAT32** image (created with
`mkfs.fat -F32` at partition offset 16384, populated from `QA/CARD`): `gb_rom_num=6`, the file
read back correct, and `fsck.fat -n` on the carved partition was clean (27 files, no structural
errors; only the FSINFO free-count off by one). A first run on **FAT16** `CFCARD.img` *did*
corrupt `GBCFG.BIN` (cross-linked) - that was the FAT32-only-write limitation above, not the
offload; it was repaired with `fsck.fat -w` + re-copying `QA/CARD`. The harness was removed after.

**Test recipe for the next offload:** `-DGBWTEST=1` (over budget -> temporarily exempt from the
size assert), boot a **FAT32** `ide_image`, then `dd ... skip=32 count=<part-secs>` + `fsck.fat -n`
the partition. A "saved OK" border does NOT prove FS consistency - always fsck.

## FS READ mount/dir offload — DESIGNED, not yet implemented (the ~1KB resident win for #156)

Goal: move the resident FAT *read* backend (`fside_dir_first/dir_next/load_file` in
`fs_ide_fat.asm` + the `fs_fat32_core` mount/dir/cluster code) into `GEOBENCH.ROM`, so the
resident kernel calls ROM entries and drops its own copy - the ~1KB resident reclaim that
unblocks the #156 maximize gadget. The ROM already carries `fs_fat32_core` (for the write), so
the code largely exists there; this wires the resident READ ops to it.

**Why it's higher-risk than the write offload:** the read path is load-bearing (every boot,
every FM listing, every app load). A bug = unbootable. Plan each step + regression-test on BOTH
FAT16 (CFCARD.img) and FAT32 (the mkfs.fat image) before the next.

**State to relocate to fixed low RAM (so the ROM can read/write it), ~72 B:**
- `fs.asm`: `fs_ent_name`(11) `fs_ent_attr`(1) `fs_ent_size`(4) `fs_req_name`(11)
  `fs_load_dst`(2) `fs_load_max`(2) `fs_cur_drive`(1). (`fs_p_*` dispatch ptrs stay resident.)
- `fs_ide_fat.asm`: `fs_mounted`(1) `fs_dir_sp`(1) `fs_dir_stack`(16) `flf_clus`(4)
  `fs_ent_clus`(4) `fs_sys_clus`(4) `fs_dir_save`(4) `flf_sic`(1) `flf_secs`(2).
  Use the same `FS_STATE_LOWRAM`/`else`-is-byte-identical pattern as `fs_fat32_core` (verify the
  resident GBIDE.BIN is unchanged by the relocation alone). Pick a free block (e.g. `#1C70+`,
  above the write state at `#1C00..#1C66`, still below `GBFAT_DATA #2200`).

**THE design risk - the browse directory.** `fs_dir_clus` (core state) is the FM's current
folder AND what the read walks. The WRITE path's `fs_mount` resets `fs_dir_clus` to root, so if
read and write share one core-state block a save would silently snap the FM back to root. The
write offload sidestepped this by keeping its `#1C00` state separate from the resident read
state. Keep them separate: the READ path gets its own dir/nav context (its own `fs_dir_clus` +
`fs_dir_stack`); the write keeps `#1C00`. They may share the static MOUNT GEOMETRY (`fs_part_lba`
/`fs_fat_lba`/`fs_data_lba`/`fs_spc`/...) since that's volume-constant, but NOT the browse dir.

**ROM dispatch (extend the table):** restructure the head into a clean jp-table -
`#C000` jp fs_read_sector (idx0), `#C003` "GBROM",1, `#C009` jp gbfat_entry (idx1, write),
then idx2 `rom_dir_first`, idx3 `rom_dir_next`, idx4 `rom_load_file` (and maybe idx5
`fs_sys_resolve`). Resident `gb_rom_call_dirfirst/_dirnext/_loadfile` (mirror `gb_rom_call`).
`load_file` writes `fs_load_dst` which may point into a banked app page at `#4000-#7FFF` - that
window is the MMR bank, untouched by the `#7F85` upper-ROM paging, so the resident sets the bank
before the ROM call and the ROM's `ldir` lands correctly (verify with an app load).

**Then drop the resident `fs_fat32_core` include from `fs_ide_fat.asm`** (and the resident
`fside_*` read code) once nothing resident calls them - that's where the bytes come back.

**Test matrix:** boot; FM directory listing; chdir into a subdir + back; open an app (load);
**save a file, then confirm the FM browse dir survived** (the clobber test); on FAT16 AND FAT32.

## Read-sector offload — RESOLVED ✅ (the reboot was a gate-array RMR bug)

The GB_ROM FAT16 build now boots to the desktop and lists the IDE directory with the
read driver executing from `GEOBENCH.ROM`. Verified headless in 1984 (`gb_rom_num=6`,
FM shows `C/GEOBENCH`) and on real hardware.

**Root cause — the upper-ROM page-in value also paged the LOWER ROM.** `gb_rom_call`
(and `gb_rom_probe`) used `#7F81` to enable the upper ROM. From 1984 `src/gate_array.c`:
`lower_rom = !(val & 0x04)`, `upper_rom = !(val & 0x08)`. `#81` has bit2 **clear**, so it
enables the **lower** ROM too - the firmware ROM is paged in over `#0000-#3FFF`, exactly
where `lba_tmp` (`#1250`) and `fs_secbuf` (`#1800`) live. The ROM read then fetched its
LBA from firmware bytes (garbage), read a wrong sector, corrupted the mount, and reset.

**Fix:** page in with **`#7F85`** (`%10000101`: bit2 **set** -> lower ROM OFF / low RAM
visible; bit3 clear -> upper ROM ON; mode 1) in both the probe and the call. Two
constants in `lib/fs_ide_fat.asm`. (`save_block` gets away with `#7F81` because it only
ever touches screen RAM at `#C000` under the paging, never low RAM.)

**How it was pinned down (bisection, all headless in 1984):**
1. NORMAL build (no GB_ROM, but with the `lba_tmp`->`#1250` move) boots clean => the
   relocation is innocent.
2. Probe-only (`-DGB_PROBE_ONLY`: probe at boot, reads stay in-RAM) boots, `gb_rom_num=6`
   => the probe is innocent.
3. The in-RAM read wrapped in the SAME paging dance (`-DGB_DANCE`, no `#C000` execution,
   valid sectors) ALSO reboots => it is NOT executing-from-ROM and NOT the ROM body.
4. `di`-only wrapper (`-DGB_DITEST`: `di`/`ei` around the in-RAM read, no ROM paging)
   BOOTS => `di`/`ei` is harmless; the ROM-select/`#7F81` paging is the killer.
5. 1984 `gate_array.c` bit semantics => `#7F81` enables the lower ROM => `#7F85` fix.

(Earlier wrong turns, kept for the record: an interrupt-state `ld a,i`/`ret po` preserve
and an enable-then-select order swap both still rebooted - because the real fault was the
lower-ROM bit, not interrupts or order.)

### Test harness (reuse for the rest of the offload)
- Config: `/tmp/gbide.conf` - `[board:cyboard]` with HDCPM(1) + GEOBENCH.ROM(6) +
  UNIDOS(7) + UNITOOLS(8) + FATFS-P1/P2(9/10); `symbiface_ide=true`,
  `ide_image=~/Downloads/CFCARD.img` (FAT16, `QA/CARD` layout at partition offset 16384).
- Sync a fresh build: `mcopy -i ~/Downloads/CFCARD.img@@16384 -o QA/CARD/GBIDE.BIN ::/`.
- Boot: `1984 --config=/tmp/gbide.conf --paste='|drive,"A","IDE:"\nrun"gb\n'
  --save-sna-at=5400:x.sna --screenshot-at=5450:x.ppm`. Read `gb_rom_num` at SNA
  offset `256+0x1254`; `0x6` + a desktop screenshot = booted, `0x0` + UniDOS banner = reboot.

## Earlier investigation notes (superseded by the fix above)
1. **Isolate lba_tmp-relocation vs the seam:** build NORMAL (no `GB_ROM_REQ`, so
   in-RAM driver but WITH the `lba_tmp`→#1250 move + dispatcher restructure) and boot
   it. Boots clean => the seam is the culprit; reboots => the relocation is (recheck
   `#1250` truly free, or a `defs`-block shift broke a hardcoded offset).
2. **Probe vs call:** force `gb_rom_num=#FF` (skip the scan) so `fs_read_sector` just
   `ret z`s — if it still reboots, it's `gb_rom_probe` itself (gate-array `#7F81` /
   `OUT #DF` scan / restore-to-7 disrupting UniDOS at #C000); if not, it's
   `gb_rom_call` / the ROM body.
3. **Restore target:** the probe/call restore upper ROM to **7** (UniDOS). If the
   firmware's live ROM at hand-over wasn't 7, restoring to 7 breaks it. Try preserving
   the IFF and/or not changing the selection persistently. (Can't read the current
   upper-ROM select — write-only — so track it, or leave GEOBENCH selected and verify
   nothing else reads #C000-on between save_block windows.)
4. Capture a `--save-sna-at` at an early boot frame and read `gb_rom_num` (#1254) +
   the PC to see whether the probe ran and where it died.

Tooling notes: headless 1984 with this FatFS/IDE config runs <8 fps (slow to iterate;
the real rig boots normally). The IDE test image MUST be the `QA/CARD` layout
(`GB.BAS` + `GBIDE.BIN` + `/GEOBENCH`, booted `RUN"GB`) — NOT `tools/build_ide_img.sh`
(old flat `GBKERN.BIN` + `.BIN` apps, `RUN"GBKERN`).

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
