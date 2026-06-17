; ---------------------------------------------------------------------------
; rom/geobench_rom.asm - GEOBENCH.ROM (#152): offloaded low-level drivers in a
; 16K loadable UPPER ROM at #C000.
;
; GEOBENCH selects this ROM (OUT (#DF),n) and pages the upper ROM in (#7F85 -
; upper ROM ON, lower ROM OFF so low-RAM stays visible), then CALLs a fixed slot:
;   #C000  jp fs_read_sector   - read one sector (resident gb_rom_call)
;   #C003  "GBROM",1           - boot-probe signature (gb_rom_probe)
;   #C009  jp gbfat_entry      - FAT write module: save / delete (gb_rom_call_write)
;
; The routines are screen-independent leaf ops over LOW-RAM buffers (< #C000) and the
; IDE ports, so they run unchanged from #C000 while the upper ROM is paged in. The FAT
; write path's WRITABLE scratch can't live in the read-only ROM, so the shared core
; (lib/fs_fat32_core.asm) + the gbfat module relocate their state to fixed low RAM
; (FS_STATE_BASE) via FS_STATE_LOWRAM. See docs/dev/ROM_OFFLOAD_POC.md.
; ---------------------------------------------------------------------------

FS_STATE_LOWRAM equ   1            ; route the core + gbfat scratch state to low RAM
FS_STATE_BASE   equ   #1C00        ; free low-RAM block (#1C00-#21FF; gap above fsam_buf)
GBFAT_AS_INCLUDE equ  1            ; gbfat.asm: no org #6000 / no GBFAT.RAW save here
FAT16_ONLY      equ   0            ; the ROM carries the full FAT16+FAT32 read+write core

                org   #C000
ROM_BASE        equ   #C000

; --- dispatch table + signature (fixed offsets the resident kernel calls) --------
                jp    fs_read_sector            ; #C000 index 0: read one sector
gbrom_sig       db    "GBROM", 1                 ; #C003 magic + version (boot probe)
                jp    gbfat_entry                ; #C009 index 1: FAT write (save/delete)

; --- the offloaded drivers ------------------------------------------------------
; gbfat.asm supplies: GBFAT_*/FS_IDE_*/fs_secbuf equates, the gbfat_entry write
; module (save + delete + fs_write_sector), and `include`s lib/fs_fat32_core.asm
; (mount + read + cluster/dir math, providing fs_read_sector). With FS_STATE_LOWRAM
; set, all writable state is equ'd into the #1C00 block (nothing lands in ROM).
                include "../kernel/modules/gbfat.asm"

; --- pad to a full 16K ROM image ------------------------------------------------
                assert $ <= #10000
                ds    #10000 - $, #FF

                save  "rom/GEOBENCH.ROM", #C000, #4000
