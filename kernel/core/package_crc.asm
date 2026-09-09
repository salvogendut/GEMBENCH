; Streamed CRC-32/ISO-HDLC update. Keep the accumulator in DE:HL while
; processing the chunk, rather than loading/shifting fixed memory per bit.
; Input HL=bytes, BC=count; raw accumulator in gb4_crc_value. Preserve IX/IY.
; Seed and final complement remain shared with primary-only admission.
gb4_crc_byte
                push ix
                push iy
                push hl
                pop ix
                push bc
                pop iy
                ld hl,(gb4_crc_value)
                ld de,(gb4_crc_value+2)
pkg_crc_bytes
                ld a,iyh
                or iyl
                jr z,pkg_crc_done
                ld a,(ix+0)
                xor l
                ld l,a
                inc ix
                ld b,8
pkg_crc_bits
                srl d
                rr e
                rr h
                rr l
                jr nc,pkg_crc_no_xor
                ld a,l
                xor #20
                ld l,a
                ld a,h
                xor #83
                ld h,a
                ld a,e
                xor #B8
                ld e,a
                ld a,d
                xor #ED
                ld d,a
pkg_crc_no_xor
                djnz pkg_crc_bits
                dec iy
                jr pkg_crc_bytes
pkg_crc_done
                ld (gb4_crc_value),hl
                ld (gb4_crc_value+2),de
                pop iy
                pop ix
                ret
