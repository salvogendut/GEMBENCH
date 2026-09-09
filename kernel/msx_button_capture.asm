; MSX-only input boundary. Loaded with GBAPV4; the IRQ leaf is copied to fixed
; page 3. No shared WM policy, app ABI, bank allocation or stack limit changes.
; Private port reads preserve PPI C and PSG R15. Like the BIOS IRQ, the leaf
; leaves the PSG register selector changed; address/data pairs must exclude IRQs.
; Capture follows the displayed pointer, not unpolled mouse counter movement.
poll_byte equ #14A2
poll_line equ #14A3

button_init_impl
                ld hl,MSX_BUTTON_LEVEL
                ld de,MSX_BUTTON_LEVEL+1
                ld bc,MSX_BUTTON_QUEUE+20-MSX_BUTTON_LEVEL-1
                ld (hl),0
                ldir
                ld hl,button_irq_template
                ld de,MSX_BUTTON_IRQ
                ld bc,button_irq_end-button_irq_template
                ldir
                ret

; D enters with quit/current held/legacy edge bits. Return D with one FIFO
; edge and the latest sampled held level. IRQ exclusion covers only bounded
; sampling/record copies; preserve the caller's IFF2 on return.
button_filter_impl
                ld a,i
                push af
                di
                call MSX_BUTTON_IRQ
                res 0,d
                res 2,d
                ld a,(MSX_BUTTON_LEVEL)
                or a
                jr z,button_no_hold
                set 2,d
button_no_hold
                ld a,d
                ld (button_flags),a
                ld hl,(poll_byte)
                ld (MSX_BUTTON_VIEW),hl
                ld a,(WM_FOCUS)
                cp WM_MAXWIN
                jr nc,button_invalid
                ld (MSX_BUTTON_VIEW+2),a
                ld hl,MSX_WIN_GEN
                add a,l
                ld l,a
                ld a,(hl)
                ld (MSX_BUTTON_VIEW+3),a
                ld a,(UI_MODAL)
                ld (MSX_BUTTON_VIEW+4),a
                ld a,1
                ld (MSX_BUTTON_VALID),a
button_next
                ld a,(MSX_BUTTON_COUNT)
                or a
                jr z,button_done
                ld hl,MSX_BUTTON_COUNT
                dec (hl)
                ld a,(MSX_BUTTON_HEAD)
                ld e,a
                inc a
                and 3
                ld (MSX_BUTTON_HEAD),a
                ld a,e
                add a,a
                add a,a
                add a,e
                ld e,a
                ld d,0
                ld hl,MSX_BUTTON_QUEUE
                add hl,de
                push hl
                inc hl
                inc hl
                ld de,MSX_BUTTON_VIEW+2
                ld b,3
button_context
                ld a,(de)
                cp (hl)
                jr nz,button_stale
                inc de
                inc hl
                djnz button_context
                pop hl
                ld a,(hl)
                ld (poll_byte),a
                inc hl
                ld a,(hl)
                ld (poll_line),a
                ld hl,button_flags
                set 0,(hl)
                jr button_done
button_stale
                pop hl
                ld hl,MSX_BUTTON_DROPPED
                inc (hl)
                jr nz,button_next
                dec (hl)
                jr button_next
button_invalid
                xor a
                ld (MSX_BUTTON_VALID),a
                ld (MSX_BUTTON_COUNT),a
                ld (MSX_BUTTON_HEAD),a
                ld (MSX_BUTTON_TAIL),a
button_done
                ld a,(button_flags)
                ld d,a
                pop af
                jp po,button_return
                ei
button_return   ret
button_flags    db 0

; Position independent: internal branches are relative; data addresses are
; fixed page 3. Preserve every touched register and never change IFF.
button_irq_template
                push af
                push bc
                push de
                push hl
                in a,(#AA)
                ld b,a
                and #F0
                or 8
                out (#AA),a
                in a,(#A9)                  ; raw matrix row 8, bit 0 = Space
                ld c,a
                ld a,b
                out (#AA),a
                ld a,15
                out (#A0),a
                in a,(#A2)
                ld b,a
                and #BF                     ; port 1, preserve mouse strobes/outputs
                out (#A1),a
                ld a,14
                out (#A0),a
                in a,(#A2)                  ; trigger 1 (joystick or mouse button)
                bit 0,c
                jr nz,button_space_up
                and #EF
button_space_up
                cpl
                and #10                     ; aggregate pressed level: 0 or 16
                ld c,a
                ld a,15
                out (#A0),a
                ld a,b
                out (#A1),a
                ld hl,MSX_BUTTON_LEVEL
                ld a,(hl)
                ld (hl),c
                cpl
                and c                       ; rising edge only
                jr z,button_irq_done
                ld a,(MSX_BUTTON_VALID)
                or a
                jr z,button_irq_done
                ld a,(MSX_BUTTON_COUNT)
                cp 4
                jr nc,button_irq_full
                ld a,(MSX_BUTTON_TAIL)
                ld e,a
                inc a
                and 3
                ld (MSX_BUTTON_TAIL),a
                ld a,e
                add a,a
                add a,a
                add a,e
                ld e,a
                ld d,0
                ld hl,MSX_BUTTON_QUEUE
                add hl,de
                ex de,hl
                ld hl,MSX_BUTTON_VIEW
                ld bc,5
                ldir
                ld hl,MSX_BUTTON_COUNT
                inc (hl)
                jr button_irq_done
button_irq_full
                ld hl,MSX_BUTTON_DROPPED     ; drop newest, never overwrite oldest
                inc (hl)
                jr nz,button_irq_done
                dec (hl)
button_irq_done
                pop hl
                pop de
                pop bc
                pop af
                ret
button_irq_end
                assert MSX_BUTTON_IRQ+button_irq_end-button_irq_template<=MSX_BUTTON_LIMIT,"button capture exceeds private page-3 slot"
