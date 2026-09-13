; Opt-in text windows. Read the appended kind bit only for live explicit-kind
; managed windows. WM upper flag bits remain shell classes. Restore mapping and
; IFF, including during loader progress while another application bank is mapped.
msx_text_mode
                push bc
                push de
                push hl
                ld a,i
                push af
                di
                ; Ctrl temporarily restores keyboard-pointer operation, so a
                ; keyboard-only user can leave the editor (Ctrl+arrows/Space).
                in a,(#AA)
                ld b,a
                and #F0
                or 6
                out (#AA),a
                in a,(#A9)
                ld c,a
                ld a,b
                out (#AA),a
                bit 1,c
                jr z,text_not_active
                ld a,(WM_FOCUS)
                cp WM_MAXWIN
                jr nc,text_not_active
                call wm_entry
                push hl
                ld de,WM_FR_FLAGS
                add hl,de
                ld a,(hl)
                and #13
                cp #13
                pop hl
                jr nz,text_not_active
                ld a,(BANK_CUR)
                push af
                ld a,(hl)
                call bank_set
                ld de,WM_FR_FRAME
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ex de,hl
                ld de,12
                add hl,de
                ld a,(hl)
                and #20
                ld e,a
                pop af
                call bank_set
                ld a,e
                jr text_return
text_not_active xor a
text_return     ld e,a
                pop af
                jp po,text_di
                ei
text_di         ld a,e
                or a
                jr z,text_zero
                ld a,1
text_zero       pop hl
                pop de
                pop bc
                ret

msx_text_getkey
                ld ix,CHSNS
                call msx_bios
                jr z,text_no_key
                ld ix,CHGET
                call msx_bios
                cp 28
                ret c
                cp 32
                ret nc
                push af
                call msx_text_mode
                or a
                jr z,text_drop_key
                pop af
                ret
text_drop_key   pop af
text_no_key     xor a
                ret
