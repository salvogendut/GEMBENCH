; Optional GB_PARAMS 9. Typed clipboard policy shared by both receivers.
; Serialized mapped root only. Reuse text scratch; no extra transfer buffer.
up_clipboard
                ld a,(CORE_PARAM_CURRENT)
                or a
                jp nz,up_context
                ld hl,(up_request+4)
                ld de,8
                or a
                sbc hl,de
                jp nz,up_bad
                ld hl,(up_request+2)
                ld bc,8
                call up_span
                jp nc,up_bad
                ld a,(hl)
                cp 4
                jp nc,up_bad
                ld de,up_text_copy
                ldir
                ld ix,up_text_copy
                ld (ix+1),0
                ld a,(ix+0)
                cp 1
                jr z,up_scrap_set
                cp 3
                jr z,up_scrap_clear
                ld bc,(PARAM_SCRAP_LENGTH)
                ld hl,510
                or a
                sbc hl,bc
                ld a,5                      ; corrupt stored length
                jp c,up_scrap_error
                ld a,(PARAM_SCRAP_TYPE)
                cp 5
                jr c,up_scrap_type
                xor a
up_scrap_type
                ld (ix+10),a                ; normalized stored type
                ld a,b
                or c
                jr nz,up_scrap_nonempty
                ld (ix+10),0
up_scrap_nonempty
                ld a,(ix+0)
                or a
                jp nz,up_scrap_get
                ld a,(ix+10)
                jp up_scrap_result

up_scrap_clear
                xor a
                ld (PARAM_SCRAP_TYPE),a
                ld bc,0
                ld (PARAM_SCRAP_LENGTH),bc
                jp up_scrap_result
up_scrap_set
                ld a,(ix+2)
                dec a
                cp 4
                ld a,3
                jp nc,up_scrap_error
                ld c,(ix+6)
                ld b,(ix+7)
                ld a,b
                or c
                jr z,up_scrap_clear
                ld hl,510
                or a
                sbc hl,bc
                jr nc,up_scrap_set_span
                ld bc,510
                ld (ix+1),1                 ; explicit truncation
up_scrap_set_span
                call up_scrap_span
                ld a,2
                jp nc,up_scrap_error
                push bc
                ld de,PARAM_SCRAP_DATA
                ldir
                pop bc
                ld (PARAM_SCRAP_LENGTH),bc   ; publish metadata after copy
                ld a,(ix+2)
                ld (PARAM_SCRAP_TYPE),a
                jp up_scrap_result

up_scrap_get
                ld a,(ix+2)
                cp 255
                jr z,up_scrap_get_size
                cp 5
                ld a,3
                jr nc,up_scrap_error
                ld a,(ix+10)
                cp (ix+2)
                ld a,4
                jr nz,up_scrap_error
up_scrap_get_size
                ld l,(ix+6)
                ld h,(ix+7)
                or a
                sbc hl,bc                   ; capacity - length
                jr nc,up_scrap_get_span
                ld c,(ix+6)
                ld b,(ix+7)
                ld (ix+1),1
up_scrap_get_span
                call up_scrap_span
                ld a,2
                jr nc,up_scrap_error
                ld a,b
                or c
                jr z,up_scrap_get_done
                push bc
                ex de,hl
                ld hl,PARAM_SCRAP_DATA
                ldir
                pop bc
up_scrap_get_done
                ld a,(ix+10)
                jr up_scrap_result
up_scrap_error
                ld (ix+1),a
                xor a
                ld bc,0
up_scrap_result
                ld (ix+2),a
                ld (ix+6),c
                ld (ix+7),b
                ld hl,up_text_copy
                ld de,(up_request+2)
                ld bc,8
                ldir
                jp up_ok

; Effective payload length BC; return HL=buffer, CF=valid. Empty spans ignore
; the pointer. Reject overlap with the eight-byte result header in either order.
up_scrap_span
                ld l,(ix+4)
                ld h,(ix+5)
                ld a,b
                or c
                scf
                ret z
                call up_span
                ret nc
                push hl
                ld de,(up_request+2)
                or a
                sbc hl,de
                jr c,up_scrap_buffer_first
                ld de,8
                or a
                sbc hl,de
                pop hl
                ccf
                ret
up_scrap_buffer_first
                add hl,de
                add hl,bc
                or a
                sbc hl,de
                pop hl
                ret c
                ld a,h                      ; equality uses subtraction flags
                scf
                ret z
                or a
                ret

                assert PARAM_SCRAP_DATA==PARAM_SCRAP_LENGTH+2,"clipboard payload must follow length"
                assert ((PARAM_SCRAP_LENGTH>=0)&(PARAM_SCRAP_DATA+510<=#4000))|((PARAM_SCRAP_LENGTH>=#8000)&(PARAM_SCRAP_DATA+510<=#10000)),"clipboard must remain fixed"
                assert ((PARAM_SCRAP_TYPE>=0)&(PARAM_SCRAP_TYPE<#4000))|((PARAM_SCRAP_TYPE>=#8000)&(PARAM_SCRAP_TYPE<#10000)),"clipboard type must remain fixed"
                assert (PARAM_SCRAP_TYPE<PARAM_SCRAP_LENGTH)|(PARAM_SCRAP_TYPE>=PARAM_SCRAP_DATA+510),"clipboard tag must not consume payload"
