; ---------------------------------------------------------------------------
; rom/geobench_rom.asm - GEOBENCH.ROM (#152): offloaded low-level drivers in a
; 16K loadable UPPER ROM at #C000.
;
; GEOBENCH selects this ROM (OUT (#DF),n) and pages the upper ROM in (#7F81 - the
; same gate-array seam lib/screen.asm:save_block already uses), then CALLs a slot
; in the dispatch table below. The routines are screen-independent leaf ops: they
; touch only the I/O ports and LOW-RAM buffers (< #C000), so they run unchanged
; from #C000 while the upper ROM is paged in. See docs/dev/ROM_OFFLOAD_POC.md.
;
; PoC scope: gbrom_fs_read_sector (the IDE 512B sector read). The real body and the
; shared FS_IDE_* / fs_secbuf / lba_tmp addresses (a lib/fs_shared.inc, included by
; both the kernel and this ROM) land in the next step; this skeleton validates the
; build pipeline and the dispatch/signature layout.
; ---------------------------------------------------------------------------

                org   #C000
ROM_BASE        equ   #C000

; --- dispatch table: known entry points; the kernel CALLs ROM_BASE + index*3 ----
gbrom_table
                jp    gbrom_fs_read_sector       ; index 0

; --- signature for the boot probe (fixed offset, right after the table) ---------
gbrom_sig       db    "GBROM", 1                 ; magic + version

; --- routines -------------------------------------------------------------------
; gbrom_fs_read_sector: read one 512B sector at lba_tmp -> fs_secbuf via the IDE
; ports (#FD08..#FD0F). Pure low-RAM + port I/O. PLACEHOLDER: the real body (a copy
; of lib/fs_fat32_core.asm:fs_read_sector, sharing addresses via fs_shared.inc)
; lands here next.
gbrom_fs_read_sector
                ret

; --- pad to a full 16K ROM image ------------------------------------------------
                assert $ <= #10000
                ds    #10000 - $, #FF

                save  "rom/GEOBENCH.ROM", #C000, #4000
