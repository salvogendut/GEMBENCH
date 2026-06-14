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

; --- addresses shared with the kernel (match lib/fs_ide_fat.asm + the fixed low-RAM
;     equs; lba_tmp was relocated to #1250 in fs_fat32_core.asm so this copy reads
;     the same bytes) ---------------------------------------------------------------
FS_IDE_SCNT     equ   #FD0A
FS_IDE_LBAL     equ   #FD0B
FS_IDE_LBAM     equ   #FD0C
FS_IDE_LBAH     equ   #FD0D
FS_IDE_DEV      equ   #FD0E
FS_IDE_CMD      equ   #FD0F
FS_IDE_STAT     equ   #FD0F
FS_IDE_DATA     equ   #FD08
fs_secbuf       equ   #1800        ; 512B sector buffer (low RAM)
lba_tmp         equ   #1250        ; 24-bit LBA staged by the kernel (low RAM)

; --- dispatch table: known entry points; the kernel CALLs ROM_BASE + index*3 ----
gbrom_table
                jp    gbrom_fs_read_sector       ; index 0

; --- signature for the boot probe (fixed offset, right after the table) ---------
gbrom_sig       db    "GBROM", 1                 ; magic + version

; --- routines -------------------------------------------------------------------
; gbrom_fs_read_sector: read one 512B sector at lba_tmp -> fs_secbuf via the IDE
; ports. Verbatim copy of lib/fs_fat32_core.asm:fs_read_sector - pure low-RAM +
; port I/O, never touches #C000, so it runs unchanged from the paged-in ROM. The
; kernel stages lba_tmp (#1250) and reads fs_secbuf (#1800) before/after the call.
gbrom_fs_read_sector
                ld    de,0                     ; wait BSY=0 before commanding
grs_bsy         ld    bc,FS_IDE_STAT
                in    a,(c)
                bit   7,a
                jr    z,grs_bsyok
                dec   de
                ld    a,d
                or    e
                jr    nz,grs_bsy
                ret                             ; timeout: buffer untouched
grs_bsyok       ld    a,(lba_tmp+3)            ; LBA 27-24 in the device register
                and   #0F
                or    #E0                       ; LBA mode, master
                ld    bc,FS_IDE_DEV
                out   (c),a
                ld    a,1
                ld    bc,FS_IDE_SCNT
                out   (c),a
                ld    a,(lba_tmp)
                ld    bc,FS_IDE_LBAL
                out   (c),a
                ld    a,(lba_tmp+1)
                ld    bc,FS_IDE_LBAM
                out   (c),a
                ld    a,(lba_tmp+2)
                ld    bc,FS_IDE_LBAH
                out   (c),a
                ld    a,#20                     ; READ SECTORS
                ld    bc,FS_IDE_CMD
                out   (c),a
                ld    de,0                       ; wait DRQ, bail on ERR/timeout
grs_poll        ld    bc,FS_IDE_STAT
                in    a,(c)
                bit   0,a
                jr    nz,grs_fail
                bit   3,a
                jr    nz,grs_drq
                dec   de
                ld    a,d
                or    e
                jr    nz,grs_poll
grs_fail        ret                             ; error/timeout: buffer untouched
grs_drq         ld    hl,fs_secbuf
                ld    de,512
                ld    bc,FS_IDE_DATA
grs_read        in    a,(c)
                ld    (hl),a
                inc   hl
                dec   de
                ld    a,d
                or    e
                jr    nz,grs_read
                ret

; --- pad to a full 16K ROM image ------------------------------------------------
                assert $ <= #10000
                ds    #10000 - $, #FF

                save  "rom/GEOBENCH.ROM", #C000, #4000
