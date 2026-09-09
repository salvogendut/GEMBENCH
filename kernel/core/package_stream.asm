; Common bounded two-segment load transaction. DE = live pending owner whose
; primary page is mapped, stream already open at zero. A = internal PKG_*.
; On success PKG_PAGE/ENTRY/SIZE is a private validated result, NOT publication.
; On failure after context acceptance close stream, free secondary, clear result.
; Context/nesting rejection does not take ownership of or touch the stream.
package_load
                push ix
                push iy
                ld a,i
                push af
                di
                ld a,(PKG_LOCK)
                push af
                ld a,1
                ld (PKG_LOCK),a
                call pkg_dispatch
                ld d,a
                di
                pop af
                ld (PKG_LOCK),a
                pop af
                ld a,d
                pop iy
                pop ix
                ret po
                ei
                ret
pkg_dispatch
                ld a,(PKG_BUSY)
                or a
                ld a,PKG_ERR_NESTED
                ret nz
                ld a,(PKG_CURRENT)
                or a
                jp nz,pkg_context
                push de
                call owner_validate
                pop de
                jp nc,pkg_context
                ld hl,(CORE_PENDING_OWNER)
                or a
                sbc hl,de
                jp nz,pkg_context
                ld a,e
                dec a
                ld hl,CORE_APP_FLAGS
                add a,l
                ld l,a
                bit 2,(hl)
                jp nz,pkg_context
                ld a,e
                dec a
                ld hl,CORE_APP_CODE_NATIVE
                add a,l
                ld l,a
                ld a,(PKG_MAPPED)
                cp (hl)
                jp nz,pkg_context
                ld (PKG_BACK),a
                ld (PKG_OWNER),de
                ld a,1
                ld (PKG_BUSY),a
                ld hl,0
                ld (PKG_PAGE),hl
                ld (PKG_ENTRY),hl
                ld (PKG_SECONDARY_SIZE),hl
                ld bc,256
                call pkg_read_exact
                jp nz,pkg_io
                ld hl,PKG_BUFFER
                ld de,APP_BASE
                ld bc,256
                ldir
                ; Bound the untrusted primary before following its manifest.
                ld a,(APP_BASE)
                cp #C3
                jp nz,pkg_format
                ld hl,(APP_BASE+3)
                ld de,#4247
                or a
                sbc hl,de
                jp nz,pkg_format
                ld hl,(APP_BASE+5)
                ld de,#5041
                or a
                sbc hl,de
                jp nz,pkg_format
                ld a,(APP_BASE+7)
                cp 4
                jp nz,pkg_format
                ld a,(APP_BASE+8)
                dec a
                cp 2
                jp nc,pkg_format
                inc a
                add a,a
                add a,a
                add a,a
                add a,16
                ld e,a
                ld d,0
                ld hl,(APP_BASE+14)
                or a
                sbc hl,de
                jp nz,pkg_format
                ld hl,APP_BASE
                add hl,de
                push hl
                pop ix
                ld l,(ix+40)
                ld h,(ix+41)
                ld (PKG_PRIMARY_SIZE),hl
                ld de,256
                or a
                sbc hl,de
                jp c,pkg_format
                ld (PKG_REMAIN),hl
                ld hl,(PKG_PRIMARY_SIZE)
                ld de,#3F00
                or a
                sbc hl,de
                jr c,pkg_primary_bound
                jp nz,pkg_format
pkg_primary_bound
                ld a,(ix+54)
                or (ix+55)
                jp nz,pkg_format
                ld l,(ix+52)
                ld h,(ix+53)
                ld (PKG_TOTAL_SIZE),hl
                ld de,(PKG_PRIMARY_SIZE)
                or a
                sbc hl,de
                jp c,pkg_format
                jp z,pkg_format
                ld hl,(PKG_TOTAL_SIZE)
                ld de,#7E00
                or a
                sbc hl,de
                jr c,pkg_total_bound
                jp nz,pkg_format
pkg_total_bound
                ld hl,APP_BASE+256
                ld (PKG_DEST),hl
                call pkg_primary_stream
                jp nz,pkg_io
                call gbap4_validate_streamed_primary
                jp nc,pkg_format
                call pkg_crc_primary
                ld de,(PKG_OWNER)
                ld b,7                         ; SECONDARY_CODE, existing allocator
                call page_alloc_owned
                jp nc,pkg_nomem
                ld (PKG_PAGE),de
                ld (PKG_NATIVE),a
                call PKG_MAP
                ld hl,APP_BASE
                ld de,APP_BASE+1
                ld bc,#3FFF
                ld (hl),0
                ldir
                ld a,(PKG_BACK)
                call PKG_MAP
                ld hl,(PKG_SECONDARY_SIZE)
                ld (PKG_REMAIN),hl
                ld hl,APP_BASE
                ld (PKG_DEST),hl
                call pkg_secondary_stream
                jp nz,pkg_io
                ; One-byte EOF probe: appended bytes are not another segment.
                ld hl,PKG_BUFFER
                ld bc,1
                call PKG_READ
                or a
                jp nz,pkg_io
                ld a,b
                or c
                jp nz,pkg_format
                call gb4_crc_finish
                ld hl,gb4_crc_value
                ld de,gb4_expected_crc
                ld b,4
pkg_crc_check
                ld a,(de)
                cp (hl)
                jp nz,pkg_format
                inc hl
                inc de
                djnz pkg_crc_check
                ld a,(PKG_NATIVE)
                call PKG_MAP
                call pkg_secondary_entry
                push af
                ld a,(PKG_BACK)
                call PKG_MAP
                pop af
                jp nc,pkg_format
                call PKG_CLOSE
                or a
                jr z,pkg_success
                ld a,PKG_ERR_IO
                jr pkg_abort_closed
pkg_success     xor a
                ld (PKG_BUSY),a
                ld (PKG_STATUS),a
                ret
pkg_format      ld a,PKG_ERR_FORMAT
                jr pkg_abort
pkg_io          ld a,PKG_ERR_IO
                jr pkg_abort
pkg_nomem       ld a,PKG_ERR_NOMEM
pkg_abort
                ld (PKG_STATUS),a
                call PKG_CLOSE                 ; release stream even on failure
                ld a,(PKG_STATUS)
pkg_abort_closed
                ld (PKG_STATUS),a
                ld a,(PKG_BACK)
                call PKG_MAP
                ld hl,(PKG_PAGE)
                ld a,h
                or l
                jr z,pkg_clear_result
                ld de,(PKG_OWNER)
                call page_free_owned
pkg_clear_result
                ld hl,0
                ld (PKG_PAGE),hl
                ld (PKG_ENTRY),hl
                ld (PKG_SECONDARY_SIZE),hl
                xor a
                ld (PKG_BUSY),a
                ld a,(PKG_STATUS)
                ret
pkg_context     ld a,PKG_ERR_CONTEXT
                ret

pkg_chunk
                ld bc,(PKG_REMAIN)
                ld hl,512
                or a
                sbc hl,bc
                ret nc
                ld bc,512
                ret
pkg_read_exact
                ld (PKG_COUNT),bc
                ld hl,PKG_BUFFER
                call PKG_READ
                or a
                ret nz
                ld hl,(PKG_COUNT)
                or a
                sbc hl,bc
                ret
pkg_primary_stream
                ld hl,(PKG_REMAIN)
                ld a,h
                or l
                ret z
                call pkg_chunk
                call pkg_read_exact
                ret nz
                call pkg_copy
                jr pkg_primary_stream
pkg_secondary_stream
                ld hl,(PKG_REMAIN)
                ld a,h
                or l
                ret z
                call pkg_chunk
                call pkg_read_exact
                ret nz
                ld hl,PKG_BUFFER
                ld bc,(PKG_COUNT)
                call gb4_crc_byte               ; same CRC update as primary
                ld a,(PKG_NATIVE)
                call PKG_MAP
                call pkg_copy
                ld a,(PKG_BACK)
                call PKG_MAP
                jr pkg_secondary_stream
pkg_copy
                ld hl,(PKG_REMAIN)
                ld bc,(PKG_COUNT)
                or a
                sbc hl,bc
                ld (PKG_REMAIN),hl
                ld hl,PKG_BUFFER
                ld de,(PKG_DEST)
                ldir
                ld (PKG_DEST),de
                ret
pkg_crc_primary
                push ix
                pop hl
                ld de,56
                add hl,de
                push hl
                ld de,gb4_expected_crc
                ld bc,4
                ldir
                pop hl
                push hl
                xor a
                ld b,4
pkg_zero_crc    ld (hl),a
                inc hl
                djnz pkg_zero_crc
                call gb4_crc32_loaded
                pop de
                ld hl,gb4_expected_crc
                ld bc,4
                ldir
                ret
pkg_secondary_entry
                ld a,(APP_BASE)
                cp #C3
                jr nz,pkg_entry_bad
                ld hl,(APP_BASE+3)
                ld de,#4247
                or a
                sbc hl,de
                jr nz,pkg_entry_bad
                ld hl,(APP_BASE+5)
                ld de,#3453
                or a
                sbc hl,de
                jr nz,pkg_entry_bad
                ld a,(APP_BASE+7)
                dec a
                jr nz,pkg_entry_bad
                ld hl,(APP_BASE+1)
                ld de,APP_BASE+8
                or a
                sbc hl,de
                jr c,pkg_entry_bad
                ld hl,(APP_BASE+1)
                ld de,APP_BASE
                or a
                sbc hl,de
                ld de,(PKG_SECONDARY_SIZE)
                or a
                sbc hl,de
                jr nc,pkg_entry_bad
                ld hl,(APP_BASE+1)
                ld (PKG_ENTRY),hl
                scf
                ret
pkg_entry_bad   or a
                ret
package_load_end
                assert ((package_load>=0)&(package_load_end<=#4000))|((package_load>=#8000)&(package_load_end<=#10000)),"package transaction must execute in fixed memory"
