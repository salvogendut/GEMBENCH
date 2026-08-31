; msx_gbap4.asm - transactional GBAP v4 admission gate for the MSX2 loader.
;
; The ordinary WM launch path has already allocated a pending owner and its
; primary mapper page, mapped that page at #4000, and loaded the complete file.
; This gate runs before the outer JP. It accepts headerless/GBAP v1-v3 binaries
; unchanged, but a file claiming GBAP v4 must be a canonical, primary-only
; GEOBENCH-2 package produced by tools/build_uapp.sh. Any rejection returns NC;
; wmo_fail then restores the old bank and releases the pending owner plus every
; page it owns. Optional external segments remain deliberately unsupported and
; the corresponding package-resources capability is not advertised.

                include "../lib/gbapp.inc"
                include "../lib/msx/glue.inc"

fs_ent_size             equ #14E8

                org   MSX_GBAP4_GATE
                jp    gbap4_validate_loaded
                db    "GBV4",1

GBAP4_HEADER_SIZE       equ 16
GBAP4_MANIFEST_SIZE     equ 64
GBAP4_SEGMENT_SIZE      equ 20
GBAP4_ICON_ENTRY_SIZE   equ 8
GBAP4_ICON_MODE1_SIZE   equ 256
GBAP4_ICON_MODE7_SIZE   equ 512

; gbap4_validate_loaded: CF = admitted, NC = reject.
gbap4_validate_loaded
                ld    hl,(fs_ent_size+2)
                ld    a,h
                or    l
                jp    nz,gb4_reject            ; MSX primary image is 16-bit bounded
                ld    hl,(fs_ent_size)
                ld    (gb4_file_size),hl

                ; Preserve the legacy path unless the complete executable magic
                ; is present. Tiny/headerless applications retain old behaviour.
                ld    de,8
                or    a
                sbc   hl,de
                jp    c,gb4_accept
                ld    a,(APP_BASE+0)
                cp    #C3
                jp    nz,gb4_accept
                ld    a,(APP_BASE+3)
                cp    'G'
                jp    nz,gb4_accept
                ld    a,(APP_BASE+4)
                cp    'B'
                jp    nz,gb4_accept
                ld    a,(APP_BASE+5)
                cp    'A'
                jp    nz,gb4_accept
                ld    a,(APP_BASE+6)
                cp    'P'
                jp    nz,gb4_accept
                ld    a,(APP_BASE+7)
                cp    4
                jr    z,gb4_v4
                cp    1
                jp    c,gb4_reject
                cp    4
                jp    c,gb4_accept              ; GBAP v1-v3 compatibility
                jp    gb4_reject                ; do not execute unknown GBAP versions

gb4_v4
                ld    hl,(gb4_file_size)
                ld    de,364                    ; smallest one-icon v4 preamble
                or    a
                sbc   hl,de
                jp    c,gb4_reject

                ; Canonical outer header and manifest placement.
                ld    a,(APP_BASE+8)
                cp    1
                jr    z,gb4_icon_count_ok
                cp    2
                jp    nz,gb4_reject
gb4_icon_count_ok
                ld    (gb4_icon_count),a
                ld    a,(APP_BASE+9)
                cp    GBAP4_ICON_ENTRY_SIZE
                jp    nz,gb4_reject
                ld    hl,(APP_BASE+12)
                ld    de,GBAP4_HEADER_SIZE
                or    a
                sbc   hl,de
                jp    nz,gb4_reject
                ld    a,(gb4_icon_count)
                add   a,a
                add   a,a
                add   a,a
                add   a,GBAP4_HEADER_SIZE
                ld    l,a
                ld    h,0
                ld    (gb4_manifest_offset),hl
                ld    de,(APP_BASE+14)
                or    a
                sbc   hl,de
                jp    nz,gb4_reject
                ld    hl,(gb4_manifest_offset)
                ld    de,APP_BASE
                add   hl,de
                push  hl
                pop   ix

                ; GBM4 v1, universal-z80, all three platform bits.
                ld    a,(ix+0)
                cp    'G'
                jp    nz,gb4_reject
                ld    a,(ix+1)
                cp    'B'
                jp    nz,gb4_reject
                ld    a,(ix+2)
                cp    'M'
                jp    nz,gb4_reject
                ld    a,(ix+3)
                cp    '4'
                jp    nz,gb4_reject
                ld    a,(ix+4)
                cp    GBAP4_MANIFEST_SIZE
                jp    nz,gb4_reject
                ld    a,(ix+5)
                cp    1
                jp    nz,gb4_reject
                ld    a,(ix+6)
                cp    3
                jp    nz,gb4_reject
                ld    a,(ix+7)
                cp    7
                jp    nz,gb4_reject
                ld    a,(ix+8)
                cp    2
                jp    nz,gb4_reject
                ld    a,(ix+9)
                or    a
                jp    nz,gb4_reject
                ld    a,(ix+10)
                cp    6
                jp    nz,gb4_reject
                ld    a,(ix+11)
                cp    MSX_SYSINFO_SIZE
                jp    nz,gb4_reject

                ; Required masks must be live. Optional masks may name only
                ; currently assigned capabilities and may not overlap required.
                ld    a,(ix+13)                ; low capability bit 15 is unknown
                and   #80
                jp    nz,gb4_reject
                ld    a,(ix+14)
                ld    b,a
                and   #80                      ; high-capability bits 0..6 assigned
                jp    nz,gb4_reject
                ld    a,b
                and   #03                      ; universal-loader + runtime-geometry
                cp    #03
                jp    nz,gb4_reject
                ld    a,(ix+15)
                or    a
                jp    nz,gb4_reject
                ld    a,(ix+17)
                and   #80
                jp    nz,gb4_reject
                ld    a,(ix+18)
                and   #80                      ; seven assigned high capabilities
                jp    nz,gb4_reject
                ld    a,(ix+19)
                or    a
                jp    nz,gb4_reject
                ld    a,(ix+12)
                and   (ix+16)
                jp    nz,gb4_reject
                ld    a,(ix+13)
                and   (ix+17)
                jp    nz,gb4_reject
                ld    a,(ix+14)
                and   (ix+18)
                jp    nz,gb4_reject
                ld    a,(ix+15)
                and   (ix+19)
                jp    nz,gb4_reject

                call  gb4_validate_identity
                jp    nc,gb4_reject
                ld    a,(ix+30)                ; lifecycle: nonzero, assigned bits only
                or    a
                jp    z,gb4_reject
                and   #F0
                jp    nz,gb4_reject
                ld    a,(ix+31)
                or    a
                jp    nz,gb4_reject

                ; The already allocated primary counts toward minimum_pages.
                ld    a,(ix+32)
                or    a
                jp    z,gb4_reject
                ld    b,a
                ld    a,(ix+33)
                cp    b
                jp    c,gb4_reject
                ld    a,(MSX_PAGE_FREE)
                inc   a
                cp    b
                jp    c,gb4_reject
                ld    a,(ix+34)
                cp    1                        ; Gate 2: primary-only transaction
                jp    nz,gb4_reject
                ld    a,(ix+35)
                cp    GBAP4_SEGMENT_SIZE
                jp    nz,gb4_reject

                ; Segment directory follows the manifest; icons follow its one
                ; primary descriptor. All offsets are checked before use.
                ld    hl,(gb4_manifest_offset)
                ld    de,GBAP4_MANIFEST_SIZE
                add   hl,de
                ld    e,(ix+36)
                ld    d,(ix+37)
                or    a
                sbc   hl,de
                jp    nz,gb4_reject
                ld    hl,(gb4_manifest_offset)
                ld    de,GBAP4_MANIFEST_SIZE+GBAP4_SEGMENT_SIZE
                add   hl,de
                ld    (gb4_resource_offset),hl

                ld    hl,(APP_BASE+10)         ; outer preamble == primary entry
                ld    e,(ix+38)
                ld    d,(ix+39)
                or    a
                sbc   hl,de
                jp    nz,gb4_reject
                ld    hl,(APP_BASE+10)
                ld    de,(gb4_file_size)
                or    a
                sbc   hl,de
                jp    nc,gb4_reject            ; entry must land inside primary image
                ld    l,(ix+38)
                ld    h,(ix+39)
                ld    de,APP_BASE
                add   hl,de
                ld    de,(APP_BASE+1)
                or    a
                sbc   hl,de
                jp    nz,gb4_reject

                ld    l,(ix+40)                ; primary length == loaded file
                ld    h,(ix+41)
                ld    de,(gb4_file_size)
                or    a
                sbc   hl,de
                jp    nz,gb4_reject
                ld    a,(ix+42)
                or    (ix+43)
                jp    nz,gb4_reject
                call  gb4_validate_abi_id
                jp    nc,gb4_reject
                ld    l,(ix+52)                ; package size is a 32-bit field
                ld    h,(ix+53)
                ld    de,(gb4_file_size)
                or    a
                sbc   hl,de
                jp    nz,gb4_reject
                ld    a,(ix+54)
                or    (ix+55)
                jp    nz,gb4_reject
                ld    a,(ix+60)
                or    (ix+61)
                or    (ix+62)
                or    (ix+63)
                jp    nz,gb4_reject

                call  gb4_validate_primary_segment
                jp    nc,gb4_reject
                call  gb4_validate_icons
                jp    nc,gb4_reject
                call  gb4_validate_crc
                jp    nc,gb4_reject
gb4_accept
                scf
                ret
gb4_reject
                or    a                         ; clear carry for wmo_fail rollback
                ret

; Application identity is one or more [A-Z0-9_] bytes followed only by spaces.
gb4_validate_identity
                push  ix
                pop   hl
                ld    de,20
                add   hl,de
                ld    b,8
                ld    c,0                       ; bit 0: character, bit 1: padding
gb4_id_loop
                ld    a,(hl)
                inc   hl
                cp    ' '
                jr    z,gb4_id_space
                bit   1,c
                jr    nz,gb4_id_bad
                cp    '_'
                jr    z,gb4_id_char
                cp    '0'
                jr    c,gb4_id_letter
                cp    '9'+1
                jr    c,gb4_id_char
gb4_id_letter
                cp    'A'
                jr    c,gb4_id_bad
                cp    'Z'+1
                jr    nc,gb4_id_bad
gb4_id_char
                set   0,c
                jr    gb4_id_next
gb4_id_space
                bit   0,c                       ; leading/empty identity is invalid
                jr    z,gb4_id_bad
                set   1,c
gb4_id_next
                djnz  gb4_id_loop
                scf
                ret
gb4_id_bad
                or    a
                ret

gb4_validate_abi_id
                ld    a,(ix+44)
                cp    'G'
                jp    nz,gb4_helper_bad
                ld    a,(ix+45)
                cp    'E'
                jp    nz,gb4_helper_bad
                ld    a,(ix+46)
                cp    'O'
                jp    nz,gb4_helper_bad
                ld    a,(ix+47)
                cp    'B'
                jp    nz,gb4_helper_bad
                ld    a,(ix+48)
                cp    'N'
                jp    nz,gb4_helper_bad
                ld    a,(ix+49)
                cp    'C'
                jp    nz,gb4_helper_bad
                ld    a,(ix+50)
                cp    'H'
                jp    nz,gb4_helper_bad
                ld    a,(ix+51)
                cp    '2'
                jp    nz,gb4_helper_bad
                scf
                ret

; The Gate-2 MSX loader admits exactly the mandatory common primary segment.
gb4_validate_primary_segment
                push  ix
                pop   iy
                ld    de,GBAP4_MANIFEST_SIZE
                add   iy,de
                ld    a,(iy+0)
                cp    1
                jp    nz,gb4_helper_bad
                ld    a,(iy+1)
                or    a
                jp    nz,gb4_helper_bad
                ld    a,(iy+2)
                cp    3
                jp    nz,gb4_helper_bad
                ld    a,(iy+3)
                or    a
                jp    nz,gb4_helper_bad
                ld    a,(iy+4)
                or    (iy+5)
                jp    nz,gb4_helper_bad
                ld    a,(iy+6)
                or    a
                jp    nz,gb4_helper_bad
                ld    a,(iy+7)
                cp    #40
                jp    nz,gb4_helper_bad
                ld    a,(iy+8)                 ; file offset dword == zero
                or    (iy+9)
                or    (iy+10)
                or    (iy+11)
                jp    nz,gb4_helper_bad
                ld    l,(iy+12)
                ld    h,(iy+13)
                ld    de,(gb4_file_size)
                or    a
                sbc   hl,de
                jp    nz,gb4_helper_bad
                ld    a,(iy+14)
                or    (iy+15)
                jp    nz,gb4_helper_bad
                ld    l,(iy+16)
                ld    h,(iy+17)
                ld    de,(gb4_file_size)
                or    a
                sbc   hl,de
                jp    nz,gb4_helper_bad
                ld    a,(iy+18)
                or    (iy+19)
                jp    nz,gb4_helper_bad
                scf
                ret

; Canonical SDK icon directory: required Mode-1 resource first, optional native
; Screen-7 resource second, both contiguous after the segment directory.
gb4_validate_icons
                ld    iy,APP_BASE+GBAP4_HEADER_SIZE
                ld    a,(iy+0)
                cp    1
                jp    nz,gb4_helper_bad
                ld    a,(iy+1)
                cp    8
                jp    nz,gb4_helper_bad
                ld    a,(iy+2)
                cp    32
                jp    nz,gb4_helper_bad
                ld    a,(iy+3)
                or    a
                jp    nz,gb4_helper_bad
                ld    a,(iy+4)
                or    a
                jp    nz,gb4_helper_bad
                ld    a,(iy+5)
                cp    1
                jp    nz,gb4_helper_bad
                ld    l,(iy+6)
                ld    h,(iy+7)
                ld    de,(gb4_resource_offset)
                or    a
                sbc   hl,de
                jp    nz,gb4_helper_bad
                ld    hl,(gb4_resource_offset)
                ld    de,GBAP4_ICON_MODE1_SIZE
                add   hl,de
                ld    a,(gb4_icon_count)
                cp    1
                jr    z,gb4_icons_total
                ld    a,(iy+8)
                cp    7
                jp    nz,gb4_helper_bad
                ld    a,(iy+9)
                cp    16
                jp    nz,gb4_helper_bad
                ld    a,(iy+10)
                cp    32
                jp    nz,gb4_helper_bad
                ld    a,(iy+11)
                or    a
                jp    nz,gb4_helper_bad
                ld    a,(iy+12)
                or    a
                jp    nz,gb4_helper_bad
                ld    a,(iy+13)
                cp    2
                jp    nz,gb4_helper_bad
                ld    e,(iy+14)
                ld    d,(iy+15)
                or    a
                sbc   hl,de
                jp    nz,gb4_helper_bad
                ex    de,hl                     ; DE = second resource offset
                ld    hl,GBAP4_ICON_MODE7_SIZE
                add   hl,de
gb4_icons_total
                ld    de,(APP_BASE+10)
                or    a
                sbc   hl,de
                jp    nz,gb4_helper_bad
                scf
                ret

gb4_helper_bad
                or    a
                ret

; CRC-32/ISO-HDLC over the complete loaded package. The four stored CRC bytes
; are temporarily zeroed, then restored before the result is compared.
gb4_validate_crc
                push  ix
                pop   hl
                ld    de,56
                add   hl,de
                ld    de,gb4_expected_crc
                ld    bc,4
                ldir
                push  ix
                pop   hl
                ld    de,56
                add   hl,de
                xor   a
                ld    b,4
gb4_crc_zero
                ld    (hl),a
                inc   hl
                djnz  gb4_crc_zero
                call  gb4_crc32_loaded

                ld    hl,gb4_expected_crc
                push  ix
                pop   de
                ex    de,hl
                ld    bc,56
                add   hl,bc                     ; HL = manifest CRC destination
                ex    de,hl                     ; DE = destination, HL = expected source
                ld    bc,4
                ldir

                ld    hl,gb4_crc_value
                ld    de,gb4_expected_crc
                ld    b,4
gb4_crc_compare
                ld    a,(de)
                cp    (hl)
                jp    nz,gb4_helper_bad
                inc   de
                inc   hl
                djnz  gb4_crc_compare
                scf
                ret

gb4_crc32_loaded
                ld    hl,gb4_crc_value
                ld    (hl),#FF
                ld    de,gb4_crc_value+1
                ld    bc,3
                ldir
                ld    hl,APP_BASE
                ld    bc,(gb4_file_size)
gb4_crc_byte
                ld    a,b
                or    c
                jr    z,gb4_crc_finish
                ld    a,(hl)
                inc   hl
                push  hl
                push  bc
                ld    hl,gb4_crc_value
                xor   (hl)
                ld    (hl),a
                ld    b,8
gb4_crc_bit
                bit   0,(hl)
                jr    z,gb4_crc_no_poly
                call  gb4_crc_shift
                ld    a,(gb4_crc_value+0)
                xor   #20
                ld    (gb4_crc_value+0),a
                ld    a,(gb4_crc_value+1)
                xor   #83
                ld    (gb4_crc_value+1),a
                ld    a,(gb4_crc_value+2)
                xor   #B8
                ld    (gb4_crc_value+2),a
                ld    a,(gb4_crc_value+3)
                xor   #ED
                ld    (gb4_crc_value+3),a
                jr    gb4_crc_next_bit
gb4_crc_no_poly
                call  gb4_crc_shift
gb4_crc_next_bit
                ld    hl,gb4_crc_value
                djnz  gb4_crc_bit
                pop   bc
                pop   hl
                dec   bc
                jr    gb4_crc_byte
gb4_crc_finish
                ld    hl,gb4_crc_value
                ld    b,4
gb4_crc_complement
                ld    a,(hl)
                cpl
                ld    (hl),a
                inc   hl
                djnz  gb4_crc_complement
                ret

; Logical right shift of the little-endian 32-bit CRC cell. Returns HL at byte 0.
gb4_crc_shift
                ld    hl,gb4_crc_value+3
                srl   (hl)
                dec   hl
                rr    (hl)
                dec   hl
                rr    (hl)
                dec   hl
                rr    (hl)
                ret

gb4_file_size       dw 0
gb4_manifest_offset dw 0
gb4_resource_offset dw 0
gb4_icon_count      db 0
gb4_expected_crc    ds 4,0
gb4_crc_value       ds 4,0
gb4_gate_end

                assert gb4_gate_end<=MSX_GBAP4_GATE_LIMIT,"GBAPV4.MOD exceeds fixed gate area"
                assert gb4_gate_end-MSX_GBAP4_GATE==MSX_GBAP4_GATE_SIZE,"update fixed GBAPV4.MOD size"
                save  "GBAPV4.RAW",MSX_GBAP4_GATE,gb4_gate_end-MSX_GBAP4_GATE
