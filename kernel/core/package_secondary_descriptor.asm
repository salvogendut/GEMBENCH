; Internal streamed profile only, IX = canonical manifest in loaded primary.
; All format policy stays shared. No allocated code becomes callable here.
gb4_validate_stream_capabilities
                ld hl,(PKG_CAPS_LOW)
                ld a,l
                cpl
                and (ix+12)
                jp nz,gb4_helper_bad
                ld a,h
                cpl
                and (ix+13)
                jp nz,gb4_helper_bad
                ld hl,(PKG_CAPS_HIGH)
                ld a,l
                cpl
                and (ix+14)
                jp nz,gb4_helper_bad
                ld a,h
                cpl
                and (ix+15)
                jp nz,gb4_helper_bad
                scf
                ret

gb4_validate_secondary_segment
                push ix
                pop iy
                ld de,GBAP4_MANIFEST_SIZE+GBAP4_SEGMENT_SIZE
                add iy,de
                ld a,(iy+0)
                cp 2
                jp nz,gb4_helper_bad
                ld a,(iy+1)
                or (iy+3)                       ; common, uncompressed
                or (iy+4)
                or (iy+5)                       ; reserved
                or (iy+6)                       ; load address low
                or (iy+10)
                or (iy+11)                      ; offset high word
                or (iy+14)
                or (iy+15)                      ; stored high word
                or (iy+18)
                or (iy+19)                      ; unpacked high word
                jp nz,gb4_helper_bad
                ld a,(iy+2)
                cp 3                            ; required + executable only
                jp nz,gb4_helper_bad
                ld a,(iy+7)
                cp #40
                jp nz,gb4_helper_bad
                ld l,(iy+8)
                ld h,(iy+9)
                ld de,(PKG_PRIMARY_SIZE)
                or a
                sbc hl,de
                jp nz,gb4_helper_bad
                ld l,(iy+12)
                ld h,(iy+13)
                ld (PKG_SECONDARY_SIZE),hl
                ld de,9                         ; header plus at least one opcode
                or a
                sbc hl,de
                jp c,gb4_helper_bad
                ld hl,(PKG_SECONDARY_SIZE)
                ld de,#3F00
                or a
                sbc hl,de
                jp c,gb4_secondary_size_ok
                jp nz,gb4_helper_bad
gb4_secondary_size_ok
                ld hl,(PKG_SECONDARY_SIZE)
                ld e,(iy+16)
                ld d,(iy+17)
                or a
                sbc hl,de
                jp nz,gb4_helper_bad
                ld hl,(PKG_PRIMARY_SIZE)
                add hl,de
                jp c,gb4_helper_bad
                ld de,(PKG_TOTAL_SIZE)
                or a
                sbc hl,de
                jp nz,gb4_helper_bad
                scf
                ret
