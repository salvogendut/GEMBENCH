; Portable data-page policy, shared by receivers. HL=primary header, BC=16.
; Provider wrapper serializes entry, retains IX/IFF/lock, and supplies mapping.
; No app pointer is retained; all state survives switching #4000..#7FFF.
; Private scratch aliases the serialized FS request and transfer reservations.
data_page_dispatch
                ld a,b
                or a
                jp nz,dp_bad_outer
                ld a,c
                cp 16
                jp nz,dp_bad_outer
                call dp_span
                jp nc,dp_bad_outer
                ld (DATA_REQUEST+16),hl
                ld de,DATA_REQUEST
                ldir
                ld ix,DATA_REQUEST
                ld (ix+1),0
                ld a,(DATA_CURRENT)
                or a
                jp nz,dp_context
                call DATA_OWNER_CURRENT
                ld a,e
                or a
                jp z,dp_context
                ld (DATA_REQUEST+18),de
                dec a
                ld hl,CORE_APP_CODE_NATIVE
                add a,l
                ld l,a
                ld a,(DATA_MAPPED)
                cp (hl)
                jp nz,dp_context
                ld a,e
                dec a
                ld hl,CORE_APP_FLAGS
                add a,l
                ld l,a
                bit 2,(hl)
                jp nz,dp_context
                ld hl,DATA_REQUEST+10
                ld b,6
dp_reserved     ld a,(hl)
                or a
                jp nz,dp_bad
                inc hl
                djnz dp_reserved
                ld a,(ix+0)
                cp 4
                jp nc,dp_bad
                cp 2
                jr nc,dp_handle
                ld hl,DATA_REQUEST+4
                ld b,6
dp_zero_fields  ld a,(hl)
                or a
                jp nz,dp_bad
                inc hl
                djnz dp_zero_fields
                ld a,(ix+0)
                or a
                jr nz,dp_handle
                ld a,(ix+2)
                or (ix+3)
                jp nz,dp_bad
                ld de,(DATA_REQUEST+18)
                ld b,3                       ; DOCUMENT, never executable
                call page_alloc_owned
                ld (DATA_REQUEST+2),de
                jp c,dp_ok
                ld a,5                       ; no memory
                jp dp_result
dp_handle
                ld hl,(DATA_REQUEST+2)
                ld de,(DATA_REQUEST+18)
                call page_check_owned
                or a
                jp nz,dp_result
                ld a,(ix+2)
                dec a
                ld c,a
                ; Derive the validated pool index, not an undocumented return
                ; register of the legacy GB_PAGE adapter. Reject code purposes
                ; even if the application owns that page through another API.
                ld hl,CORE_PAGE_PURPOSE
                ld a,c
                add a,l
                ld l,a
                ld a,(hl)
                cp 3
                jp nz,dp_bad
                ld a,(ix+0)
                cp 1
                jr nz,dp_transfer
                ld hl,(DATA_REQUEST+2)
                ld de,(DATA_REQUEST+18)
                call page_free_owned
                jp dp_result
dp_transfer
                ld hl,CORE_PAGE_NATIVE
                ld a,c
                add a,l
                ld l,a
                ld a,(hl)
                ld (DATA_REQUEST+20),a
                ld bc,(DATA_REQUEST+8)
                ld hl,512
                or a
                sbc hl,bc
                jp c,dp_bad
                ld hl,(DATA_REQUEST+4)
                add hl,bc
                jp c,dp_bad
                ld de,#4000
                or a
                sbc hl,de
                jr c,dp_offset_ok
                jp nz,dp_bad
dp_offset_ok
                ld a,b
                or c
                jp z,dp_ok                   ; zero length never maps or copies
                ld hl,(DATA_REQUEST+6)
                call dp_span
                jp nc,dp_bad
                ; Buffer/header disjoint; compare half-open intervals.
                ld de,(DATA_REQUEST+16)
                or a
                sbc hl,de
                jr c,dp_buffer_first
                ld de,16
                or a
                sbc hl,de
                jp c,dp_bad
                jr dp_stage
dp_buffer_first
                add hl,de
                add hl,bc
                or a
                sbc hl,de
                jr c,dp_stage
                jp nz,dp_bad
dp_stage
                ld a,(ix+0)
                cp 3
                jr nz,dp_map
                ld hl,(DATA_REQUEST+6)
                ld de,DATA_TRANSFER
                ldir                          ; capture write bytes BEFORE mapping
dp_map
                ld a,(DATA_MAPPED)
                ld (DATA_REQUEST+21),a
                ld a,(DATA_REQUEST+20)
                call DATA_MAP
                ld hl,(DATA_REQUEST+4)
                ld de,#4000
                add hl,de
                ld de,DATA_TRANSFER
                ld bc,(DATA_REQUEST+8)
                ld a,(ix+0)
                cp 2
                jr z,dp_copy
                ex de,hl
dp_copy         ldir
                ld a,(DATA_REQUEST+21)
                call DATA_MAP
                ld a,(ix+0)
                cp 2
                jr nz,dp_ok
                ld hl,DATA_TRANSFER
                ld de,(DATA_REQUEST+6)
                ld bc,(DATA_REQUEST+8)
                ldir                          ; publish read bytes AFTER restoring
dp_ok           xor a
                jr dp_result
dp_context      ld a,7
                jr dp_result
dp_bad          ld a,6
dp_result       ld (DATA_REQUEST+1),a
                push af
                ld hl,DATA_REQUEST
                ld de,(DATA_REQUEST+16)
                ld bc,16
                ldir
                pop af
                ret
dp_bad_outer    ld a,6
                ret

; Same primary span convention as GB_PARAMS; preserve HL/BC, CF=valid.
dp_span
                ld a,h
                cp #40
                jr c,dp_span_bad_start
                push hl
                add hl,bc
                jr c,dp_span_bad
                ld a,h
                cp #7F
                jr c,dp_span_good
                jr nz,dp_span_bad
                ld a,l
                or a
                jr nz,dp_span_bad
dp_span_good    pop hl
                scf
                ret
dp_span_bad     pop hl
dp_span_bad_start
                or a
                ret

                assert DATA_REQUEST+22<=DATA_TRANSFER | DATA_TRANSFER+512<=DATA_REQUEST,"page header/transfer overlap"
                assert ((DATA_REQUEST>=0)&(DATA_REQUEST+22<=#4000))|((DATA_REQUEST>=#8000)&(DATA_REQUEST+22<=#10000)),"page request must remain fixed"
                assert ((DATA_TRANSFER>=0)&(DATA_TRANSFER+512<=#4000))|((DATA_TRANSFER>=#8000)&(DATA_TRANSFER+512<=#10000)),"page transfer must remain fixed"
