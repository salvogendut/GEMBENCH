; ---------------------------------------------------------------------------
; lib/fs_rom_seam.asm - the resident GEOBENCH.ROM seam shared by every storage
; backend (#152). Included by kernel/gbkern.asm inside `ifdef GB_ROM`, BEFORE the
; storage backend, so both the IDE (fs_ide_fat.asm) and Albireo (fs_albireo.asm)
; builds + the floppy (fs_amsdos.asm) stubs can reach it. The backend-specific
; entry stubs live in their own files; the IDE read-sector / FAT-write helpers
; (gb_rom_call / gb_rom_call_write) stay in fs_ide_fat.asm (IDE only).
; ---------------------------------------------------------------------------

gb_rom_num      equ   #1254        ; 0xFF = ROM not found, else the upper-ROM number

; gb_rom_probe: scan upper ROM numbers 1..15 (skip 0=BASIC, 7=AMSDOS) for the
; "GBROM" signature at #C003. Found -> gb_rom_num = the number; leaves AMSDOS (7)
; selected. Pages in with #7F85 (upper ROM ON + lower ROM OFF so low RAM stays
; visible). Run once at boot.
gb_rom_probe
                di
                ld    a,#FF
                ld    (gb_rom_num),a
                ld    bc,#7F85
                out   (c),c
                ld    d,1                    ; D = candidate ROM number
grp_loop        ld    a,d
                cp    7
                jr    z,grp_next             ; skip AMSDOS
                ld    bc,#DF00
                out   (c),a                  ; select ROM D (value = ROM number)
                ld    hl,#C003
                ld    a,(hl)
                cp    'G'
                jr    nz,grp_next
                inc   hl
                ld    a,(hl)
                cp    'B'
                jr    nz,grp_next
                inc   hl
                ld    a,(hl)
                cp    'R'
                jr    nz,grp_next
                inc   hl
                ld    a,(hl)
                cp    'O'
                jr    nz,grp_next
                inc   hl
                ld    a,(hl)
                cp    'M'
                jr    nz,grp_next
                ld    a,d                     ; full "GBROM" match -> found
                ld    (gb_rom_num),a
                jr    grp_done
grp_next        inc   d
                ld    a,d
                cp    16
                jr    c,grp_loop
grp_done        ld    bc,#DF00               ; restore AMSDOS (7)
                ld    a,7
                out   (c),a
                ei
                ret

; gb_rom_fsam_invoke: HL = ROM dispatch slot. Page GEOBENCH.ROM in (#7F85: upper ROM
; on, lower ROM off so low RAM stays visible), call (HL), restore AMSDOS. CF survives
; the OUT/EI restore. The shared call helper for every backend's read/dir/load stubs.
gb_rom_fsam_invoke
                di
                ld    bc,#DF00
                ld    a,(gb_rom_num)
                out   (c),a
                ld    bc,#7F85
                out   (c),c
                call  grfi_jphl
                ld    bc,#DF00
                ld    a,7
                out   (c),a
                ei
                ret
grfi_jphl       jp    (hl)
