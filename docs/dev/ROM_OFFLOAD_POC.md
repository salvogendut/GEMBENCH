# GEOBENCH.ROM offload — PoC design & findings (#152)

> Historical proof-of-concept record. Normal CPC distributions now use the
> no-ROM Albireo/M4 kernels, and the default preemptive runtime is deliberately
> ROM-independent. The optional sources remain for recovery and size research;
> use [BUILDING.md](../BUILDING.md) and [ARCHIVED.md](../ARCHIVED.md) for current
> support boundaries.

> **Status: SHIPPED.** The PoC below grew into the full feature on branch
> `152-rom-offload`. The IDE *and* Albireo backends now run from the ROM (FAT
> read/write, AMSDOS floppy read, IDE read, the CH376 backend), the kernel keeps thin
> stubs (`-DGB_ROM_REQ=1`), and the image is also a CPC **background ROM** that boots a
> `GEOBENCH <commit>` banner. Build with `tools/build_rom.sh` (→ `rom/GEOBENCH.ROM` for
> IDE, `rom/GBALB.ROM` for Albireo). See *The GEOBENCH ROM* in `docs/ARCHITECTURE.md`.
> This file is kept as the design record + the gotchas hunted along the way.

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
`mkfs.fat -F32` at partition offset 16384, populated from `QA/CPC/CARD`): `gb_rom_num=6`, the file
read back correct, and `fsck.fat -n` on the carved partition was clean (27 files, no structural
errors; only the FSINFO free-count off by one). A first run on **FAT16** `CFCARD.img` *did*
corrupt `GBCFG.BIN` (cross-linked) - that was the FAT32-only-write limitation above, not the
offload; it was repaired with `fsck.fat -w` + re-copying `QA/CPC/CARD`. The harness was removed after.

**Test recipe for the next offload:** `-DGBWTEST=1` (over budget -> temporarily exempt from the
size assert), boot a **FAT32** `ide_image`, then `dd ... skip=32 count=<part-secs>` + `fsck.fat -n`
the partition. A "saved OK" border does NOT prove FS consistency - always fsck.

## AMSDOS floppy read offload — DONE ✅ (read backend runs from the ROM)

Increments 1 (`2bc9927`, state relocation) + 2 (`c52f23d`, the code move) are committed. The
floppy READ backend (`fsam_dir_first/dir_next/load_file/present` + the uPD765 FDC core) runs
from `GEOBENCH.ROM`; the resident `fs_amsdos.asm` compiles to thin ROM-call stubs that marshal a
`#1270` low-RAM I/O transfer area (`lib/fs_rom_lowram.inc`) <-> the resident `fs_ent_*`/
`fs_req_name`/`fs_load_*`. ROM dispatch slots: `#C00C/#C00F/#C012/#C015`. `fsam_save_file` (the
write stub) stays resident; non-ROM/Albireo builds + the paged `floppysv` are byte-identical.
**Reclaimed ~780 B** (GBIDE 8517 -> 7738). Verified headless: floppy dir read returns the right
first file via the ROM, full desktop boots with Disk A/B. The transfer-area marshalling pattern
proven here is the template for the FS read offload below.

> TODO (rig validation): the floppy LOAD-to-app-page path (the #135 capability the ROM uniquely
> unblocks) uses the same bridge but wasn't headlessly exercised - open Disk A + run an app.

### (history) increment 1 — state relocation

Move the floppy READ backend (`fsam_dir_first/dir_next/load_file/present` + the FDC core in
`fs_amsdos.asm`/`fs_amsdos_core.asm`) into `GEOBENCH.ROM`. The ROM **uniquely** enables this: #135
found "floppy LOAD can't be paged - it writes app pages" (paged modules live in the app bank
`#4000-#7FFF`); the ROM is at `#C000`, independent of that bank, so a ROM floppy-load CAN write
app pages. Floppy is also FLAT (no subdirs) so it sidesteps the IDE read's browse-dir clobber.
Lower-risk than the IDE read (only exercised on Disk A/B, not every boot).

- **Increment 1 — DONE (2bc9927):** relocated the fs_amsdos/core scratch state to fixed low RAM
  (`FS_RDIO_LOWRAM`, `FSAM_STATE_BASE=#1256`); `else` branch byte-identical. Reclaimed 26 B
  (GBIDE 8543->8517). Verified: desktop boots + floppy dir read returns the right first file.

- **Test harness (rebuild as needed):** `-DGBFTEST=1` after `fs_sys_resolve` -> `xor a;
  ld (fsam_unit),a; call fsam_dir_first; border WHITE if CF else RED; hang`. Config:
  `gbide_flp.conf` = gbide.conf + `drive_a=<repo>/QA/CPC/Floppies/GEOBENCH.DSK`. Read `fs_ent_name` from the
  SNA (symbol `FS_ENT_NAME`, e.g. #9793) - should be `GBKERN  BIN`. (Build is over budget ->
  temporarily exempt from the size assert.)

- **Increment 2 — TODO (the code move + transfer-area bridge):**
  1. **Split `fs_amsdos.asm`:** the read path (dir/load/present + core) goes to the ROM, but
     `fsam_save_file` (the WRITE stub, lines ~355-410) loads the paged `floppysv` module and has
     resident deps (`fs_load_sys`, bank) - it must STAY resident. Guard `fsam_save_file` with
     `ifndef FS_RDIO_LOWRAM` (excluded from the ROM include) and keep a resident copy, OR extract
     it to its own file. Confirm whether `fsam_save_file` needs the FDC core (if not, the resident
     keeps only the stub).
  2. **I/O scratch (transfer area)** at `#1270+` (after the fsam state): the ROM build defines
     `fs_ent_name`(11)/`fs_ent_attr`(1)/`fs_ent_size`(4) [outputs] + `fs_req_name`(11)/
     `fs_load_dst`(2)/`fs_load_max`(2) [inputs] as equs there (fs_amsdos references exactly these
     - verified, NOT fs_ent_clus). The resident keeps its own `fs_ent_*` (fs.asm defs, untouched).
  3. **ROM dispatch:** add idx2 `jp fsam_dir_first`, idx3 `jp fsam_dir_next`, idx4
     `jp fsam_load_file`, idx5 `jp fsam_present` (after `#C009`). Include the read half of
     fs_amsdos in the ROM.
  4. **Resident stubs** `gb_rom_fsam_*` (mirror `gb_rom_call`, page in with `#7F85`): before a
     LOAD, copy resident `fs_req_name`/`fs_load_dst`/`fs_load_max` -> scratch (+ set the app bank);
     call the ROM dispatch; after dir/load, copy scratch `fs_ent_*` -> resident `fs_ent_*`; return
     the ROM's CF (survives the `out`/`ei` restore). `fsam_unit` is already shared at `#1256`.
  5. **Rewire `fs.asm:fs_set_drive`** floppy branch: point `fs_p_first/next/load` at the stubs.
  6. **Drop the read half of fs_amsdos from the resident** (the reclaim).
  - **Test:** GBFTEST floppy dir read (-> GBKERN BIN via the ROM); a floppy file LOAD into an app
    page (the #135 capability - verify the ldir lands in the banked page); full boot; FM open
    Disk A. The write path (`floppysv`) must still save to a floppy.

## FS READ mount/dir offload — DONE ✅ (the IDE read backend runs from the ROM)

The big ~1KB reclaim for #156 is done + committed. The IDE FAT read backend
(`fside_dir_first/dir_next/load_file` + `flf_cmpname`, extracted to `lib/fs_ide_read.asm`)
runs from `GEOBENCH.ROM`; the GB_ROM resident build compiles thin ROM-call stubs that marshal
the `#1270` transfer area (+ `FSAM_IO_CLUS`) and share the FAT core state at `#1C00`. Dispatch
slots `#C018/#C01B/#C01E`. The resident `fs_fat32_core` include is dropped (a tiny `copy4` +
`flf_cmpname` kept for `fs_sys_resolve`). **GBIDE FAT16 7691 → 6817 B** (~874 B); non-ROM,
Albireo, paged modules unchanged. Verified on FAT16 + FAT32 (desktop boot exercises
`fs_sys_resolve` + the app load through the stubs) + real hardware, and a save-then-relist on
FAT32 (ROM read + ROM write together) is fsck-clean.

> BUG FOUND + FIXED during B2: B1 had put `fat_eoc` (a `defb`) in a `.inc` included BEFORE
> `org #C000`, so it landed outside the ROM image and the ROM read garbage for the FAT
> end-of-chain marker — latent (reads don't use it) until a SAVE wrote a corrupt FAT entry
> (`fat_set_val = 0xED7F8901` instead of `0x0FFFFFFF`). Fix (`5761063`): include the `.inc`
> AFTER `org`. Pinpointed via an SNA dump of `#1C00` right after a save. LESSON: any `defb`
> shared with the ROM must be placed after the ROM's `org`, or it falls outside the image.

### (superseded) original design

The ~1KB resident win for #156. Foundation committed:
- **Inc A (efbbc13):** resident GB_ROM build shares the FAT core state with the ROM at #1C00
  (FS_STATE_LOWRAM). Safe because gbfat_save restores fs_dir_clus to the browse dir. Validated:
  desktop boots + a save-then-relist test (-DGBSRTEST, FAT32) finds the saved file, fsck-clean.
- **Inc B1 (df911d8):** FAT core-state equs extracted to lib/fs_fat_lowram.inc (shared by the
  resident + ROM), so the resident keeps the state addresses after the read code leaves. Pure
  refactor, boots.

**Inc B2 (TODO) - the code move (the ~1KB reclaim). Follow the floppy template exactly:**
1. **Split fs_ide_fat.asm.** Extract the read backend (fside_dir_first/dir_next/load_file +
   flf_cmpname, lines ~54-244) into a new lib/fs_ide_read.asm. fs_ide_fat.asm keeps fs_sys_resolve,
   fs_sysdir_enter/leave, the write stubs (gbfat_run/fside_save/delete) and the seam
   (gb_rom_probe/gb_rom_call/_write) - all resident.
2. **Conditionals in fs_ide_fat.asm** (mirror fs_amsdos):
   - core include (line 47): `if (not GB_ROM_STUBS) and (not IN_GBROM)` - only the non-ROM
     resident includes fs_fat32_core here (the ROM already has it via gbfat; the GB_ROM resident
     uses stubs).
   - read: `ifndef GB_ROM_STUBS` -> `include "fs_ide_read.asm"`; `else` -> the stubs
     (gb_rom_fside_dir_first @ROM idx6, dir_next @idx7, load_file @idx8; reuse gb_rom_fsam_invoke
     + a fside_ent_out copy helper).
3. **ROM (geobench_rom.asm):** add dispatch jp fside_dir_first (#C018), jp fside_dir_next (#C01B),
   jp fside_load_file (#C01E); `include "../lib/fs_ide_read.asm"` AFTER gbfat (which provides the
   core); add the IDE I/O aliases - reuse FSAM_IO_NAME/ATTR/SIZE/REQ/DST/MAX and add FSAM_IO_CLUS
   (IDE entries carry a start cluster; floppy didn't). Alias fs_ent_clus = FSAM_IO_CLUS.
4. **State split** (the intricate part): fs_mounted + flf_clus/flf_sic/flf_secs are ROM-only ->
   put them in fs_fat_lowram.inc at FS_STATE_BASE+104.. (after the gbfat write state +43..102;
   NOTE this region overlaps fsam_buf #1A00-#21FF but IDE-read and floppy-read are never
   concurrent, like the existing #1C00 overlap). fs_dir_sp/fs_dir_stack/fs_sys_clus/fs_dir_save
   stay resident (used by k_chdir/k_back + fs_sys_resolve). fs_ent_clus -> resident defs, the
   stub copies it out of FSAM_IO_CLUS (alongside fs_ent_name/attr/size out of FSAM_IO_NAME..).
5. **Drop the resident fs_fat32_core include** (the reclaim) once nothing resident calls it
   (fside_* are stubs; gbfat_run/save go to the ROM; nav uses only the #1C00 state addresses).
6. **Test (all via the normal boot - no harness):** desktop boots (fs_sys_resolve finds /GEOBENCH
   via the dir stubs, DESKTOP.APP loads via the load stub into its bank page - the ldir lands in
   the MMR bank #4000-#7FFF, untouched by #7F85), FM lists C/GEOBENCH, chdir into /GEOBENCH + back,
   save a file then re-list (browse dir survives). FAT16 (CFCARD) AND FAT32.

## FS READ mount/dir offload — original design (#152, #156)

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
  `ide_image=~/Downloads/CFCARD.img` (FAT16, `QA/CPC/CARD` layout at partition offset 16384).
- Sync a fresh build: `mcopy -i ~/Downloads/CFCARD.img@@16384 -o QA/CPC/CARD/GBIDE.BIN ::/`.
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
the real rig boots normally). The IDE test image MUST be the `QA/CPC/CARD` layout
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
