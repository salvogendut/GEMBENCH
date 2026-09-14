; CPC leaf for the same opt-in text-window contract as msx_text_input.asm.
; Call after a fresh matrix scan. Ctrl restores keyboard-pointer navigation.
; Inspect only live explicit-kind managed descriptors, preserving bank/IFF and
; all caller registers other than AF. Never consult an unmapped app pointer.
cpc_text_mode
                ld a,(CPC_KEYS+2)
                bit 7,a
                jr nz,cpc_text_focus
                xor a
                ret
cpc_text_focus
                push bc
                push de
                push hl
                ld a,i
                push af
                di
                ld a,(WM_FOCUS)
                cp CPC_WINDOW_MAX
                jr nc,cpc_text_inactive
                call sched_wm_entry
                push hl
                ld de,WM_FR_FLAGS
                add hl,de
                ld a,(hl)
                and #13
                cp #13
                pop hl
                jr nz,cpc_text_inactive
                ld a,(BANK_CUR)
                push af
                ld a,(hl)
                call foundation_bank_set
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
                call foundation_bank_set
                ld a,e
                jr cpc_text_return
cpc_text_inactive
                xor a
cpc_text_return
                ld e,a
                pop af
                jp po,cpc_text_di
                ei
cpc_text_di
                ld a,e
                or a
                jr z,cpc_text_zero
                ld a,1
cpc_text_zero
                pop hl
                pop de
                pop bc
                ret

; Mask just pointer keys in this poll sample. GETKEY performs its own fresh
; scan before translation, so arrows/Space are still delivered to the editor.
; Joystick row 9 is untouched; native/default windows keep their old routing.
cpc_text_pointer
                call cpc_text_mode
                or a
                ret z
                ld hl,CPC_KEYS
                ld a,(hl)
                or 7                       ; up/right/down
                ld (hl),a
                inc hl
                set 0,(hl)                 ; left
                ld hl,CPC_KEYS+5
                set 7,(hl)                 ; Space must not click while typing
                ret
