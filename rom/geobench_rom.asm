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

; #152: this ROM is built per storage card (mirrors the per-card kernel). -DSTORAGE_ALBIREO=1
; builds the Albireo (CH376) variant -> rom/GBALB.ROM; the default builds the IDE variant
; -> rom/GEOBENCH.ROM. The floppy (fs_amsdos) read backend is common to both.
                ifndef STORAGE_ALBIREO
STORAGE_ALBIREO equ   0
                endif

FS_RDIO_LOWRAM  equ   1            ; floppy read backend (fs_amsdos): scratch -> fixed low RAM
IN_GBROM        equ   1            ; build the READ half of fs_amsdos here (no resident write stub)
                include "../lib/fs_rom_lowram.inc"   ; fsam state + I/O transfer area addresses
fsam_buf        equ   #1A00        ; floppy whole-directory buffer (2KB; resident agrees)
; the backends write/read the entry + load fields via the I/O transfer area
fs_ent_name     equ   FSAM_IO_NAME
fs_ent_attr     equ   FSAM_IO_ATTR
fs_ent_size     equ   FSAM_IO_SIZE
fs_req_name     equ   FSAM_IO_REQ
fs_load_dst     equ   FSAM_IO_DST
fs_load_max     equ   FSAM_IO_MAX

                if STORAGE_ALBIREO
FS_ALB_LOWRAM   equ   1            ; CH376 path state + save args -> fixed low RAM (#1293)
                include "../lib/fs_alb_lowram.inc"   ; alb_path + fsalb_mounted + ALB_IO_SRC/SLEN
fs_save_src     equ   ALB_IO_SRC   ; save streams from the caller's app page (mapped under #7F85)
fs_save_len     equ   ALB_IO_SLEN
                else
fs_ent_clus     equ   FSAM_IO_CLUS        ; IDE entries carry a start cluster (floppy didn't)
FS_STATE_LOWRAM equ   1            ; route the FAT core + gbfat scratch state to low RAM
FS_STATE_BASE   equ   #1C00        ; free low-RAM block (#1C00-#21FF; gap above fsam_buf)
; NOTE: fs_fat_lowram.inc is included AFTER `org #C000` below - it defines fat_eoc as a
; `defb`, which must land INSIDE the ROM image (before org it lands at address 0 and the
; ROM reads garbage for the FAT end-of-chain marker -> corrupt FAT entries on a save, #152).
GBFAT_AS_INCLUDE equ  1            ; gbfat.asm: no org #6000 / no GBFAT.RAW save here
FAT16_ONLY      equ   0            ; the ROM carries the full FAT16+FAT32 read+write core
                endif

                org   #C000
ROM_BASE        equ   #C000

; --- dispatch table + signature (fixed offsets the resident kernel calls) --------
                if STORAGE_ALBIREO
                jp    rom_inert                 ; #C000 index 0: (IDE read - unused on Albireo)
gbrom_sig       db    "GBROM", 1                 ; #C003 magic + version (boot probe)
                jp    rom_inert                 ; #C009 index 1: (FAT write - unused on Albireo)
                jp    fsam_dir_first             ; #C00C index 2: floppy dir first
                jp    fsam_dir_next              ; #C00F index 3: floppy dir next
                jp    fsam_load_file             ; #C012 index 4: floppy file load
                jp    fsam_present               ; #C015 index 5: floppy presence probe
                jp    fsalb_dir_first            ; #C018 index 6: Albireo dir first
                jp    fsalb_dir_next             ; #C01B index 7: Albireo dir next
                jp    fsalb_load_file            ; #C01E index 8: Albireo file load
                jp    fsalb_save_file            ; #C021 index 9: Albireo save
                jp    fsalb_delete_file          ; #C024 index 10: Albireo delete
rom_inert       ret                              ; #C027 inert target for the unused IDE slots
                else
                jp    fs_read_sector            ; #C000 index 0: read one sector
gbrom_sig       db    "GBROM", 1                 ; #C003 magic + version (boot probe)
                jp    gbfat_entry                ; #C009 index 1: FAT write (save/delete)
                jp    fsam_dir_first             ; #C00C index 2: floppy dir first
                jp    fsam_dir_next              ; #C00F index 3: floppy dir next
                jp    fsam_load_file             ; #C012 index 4: floppy file load
                jp    fsam_present               ; #C015 index 5: floppy presence probe
                jp    fside_dir_first            ; #C018 index 6: IDE dir first
                jp    fside_dir_next             ; #C01B index 7: IDE dir next
                jp    fside_load_file            ; #C01E index 8: IDE file load
                include "../lib/fs_fat_lowram.inc"  ; FAT core state addrs + fat_eoc (in-ROM, #152)
                endif

; --- the offloaded drivers ------------------------------------------------------
; fs_amsdos.asm (with IN_GBROM) supplies the floppy READ backend + the uPD765 FDC core
; (common to both cards). The Albireo build adds fs_albireo.asm (the CH376 I/O backend);
; the IDE build adds gbfat.asm (the gbfat_entry write module + lib/fs_fat32_core.asm,
; providing fs_read_sector) and fs_ide_read.asm. All writable state is equ'd into low RAM.
                include "../lib/fs_amsdos.asm"
                if STORAGE_ALBIREO
                include "../lib/fs_albireo.asm"    ; CH376 read/write/dir backend (uses #1293 state)
                else
                include "../kernel/modules/gbfat.asm"
                include "../lib/fs_ide_read.asm"   ; IDE read backend (uses gbfat's fs_fat32_core)
                endif

; --- pad to a full 16K ROM image ------------------------------------------------
                assert $ <= #10000
                ds    #10000 - $, #FF

                if STORAGE_ALBIREO
                save  "rom/GBALB.ROM", #C000, #4000
                else
                save  "rom/GEOBENCH.ROM", #C000, #4000
                endif
