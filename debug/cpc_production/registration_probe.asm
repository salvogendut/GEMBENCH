; Inputs/captures only. Actual registration, kind selection, furniture,
; z-order, focus/damage and close are the production shared code.
reg_clip equ #3300
reg_calls equ #3308                 ; eight callback counters per checkpoint
reg_case equ #3310
reg_status equ #3311
reg_bank equ #3312
reg_trace_tag equ #3313
reg_frame_tag equ #3314
reg_add_index equ #3315
reg_selector equ #3316
reg_destination equ #3317
reg_trace_dest equ #3319
reg_done equ #331B
reg_close_slot equ #331C
reg_header equ #3320
reg_long_title equ #3340           ; 24-byte destination plus checked trailing guard
                assert reg_header+32<=CPC_REG_END,"registration telemetry overflow"

cpc_registration_probe
                di
                ld hl,CPC_WM_GUARD
                call reg_guard
                ld hl,CPC_WM_END
                call reg_guard
                ld hl,CPC_REG_GUARD
                call reg_guard
                ld hl,CPC_REG_END
                call reg_guard
                ld hl,cpc_fixture_records
                ld de,WM_TABLE
                ld bc,50
                ldir
                ld a,9                       ; original worker, legacy paint callback
                ld (WM_TABLE+WM_ESZ+WM_FR_FLAGS),a
                call app_mark_root_current
                ld a,1
                ld (KCFG_FRAMEPEN),a
                ld hl,reg_arg
                ld de,launch_arg
                call copy11
                ld a,#D7
                ld (reg_long_title+24),a
                ld hl,reg_long_input
                ld de,reg_long_title
                call kw_copy_title
                call reg_alloc
                ld (reg_trace_tag),a
                call foundation_bank_set
                ld hl,#4000
                ld de,#4001
                ld bc,#3FFF
                ld (hl),#BD
                ldir
reg_loop
                ld a,#C0
                call foundation_bank_set
                xor a
                ld hl,reg_calls
                ld b,8
reg_clear_calls ld (hl),a
                inc hl
                djnz reg_clear_calls
                ld a,(reg_case)
                add a,a
                ld e,a
                ld d,0
                ld hl,reg_actions
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ex de,hl
                call md_call
                di
                ld (reg_status),a
                ld a,(BANK_CUR)
                ld (reg_bank),a
                call reg_capture
                ld hl,reg_case
                inc (hl)
                ld a,(hl)
                cp 16
                jr nz,reg_loop
                ld (reg_done),a
                call clip_set_full
                call sched_compositor_prepare
                ret
reg_guard
                ld b,16
reg_guard_loop  ld (hl),#D7
                inc hl
                djnz reg_guard_loop
                ret
reg_alloc
                ld de,(draw_root_owner)
                ld b,6
                call page_alloc_owned
                ret c
                ld a,45
                jp cpc_probe_fail

reg_actions
                dw reg_initial,reg_add_next,reg_add_next,reg_add_next
                dw reg_add_next,reg_add_next,reg_add_next,reg_full_raw
                dw reg_full_managed,reg_focus,reg_move,reg_size
                dw reg_close_five,reg_reuse,reg_tiny,reg_cleanup
reg_initial
                call clip_set_full
                call wm_repaint_all
                xor a
                ret
reg_add_next
                ld a,(reg_case)
                dec a
                jr reg_add
reg_reuse
                ld a,6
reg_add
                ld (reg_add_index),a
                add a,a
                add a,a
                ld e,a
                ld d,0
                ld hl,reg_inputs
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ld a,(hl)
                inc hl
                push af
                ld a,(hl)
                ld (reg_selector),a
                pop af
                push de
                call foundation_bank_set
                ld a,(reg_add_index)
                add a,a
                add a,a
                add a,a
                add a,a
                ld e,a
                ld d,#48
                ld (reg_destination),de
                pop hl
                ld bc,13
                ldir
                ld a,(reg_add_index)
                add a,a
                ld e,a
                ld d,0
                ld hl,reg_titles
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ex de,hl
                ld a,(reg_add_index)
                add a,a
                add a,a
                add a,a
                add a,a
                add a,a
                ld e,a
                ld d,#4A
                call gtd_copy
                ld a,#C3                     ; real callback trampoline in caller page
                ld (#4B00),a
                ld hl,reg_content
                ld (#4B01),hl
                ld a,(reg_selector)
                ld hl,(reg_destination)
                call k_wm_managed
                ; Record initial publication clip before first repaint resets it.
                ld hl,WM_CLIP_X
                ld de,reg_clip
                ld bc,4
                ldir
                call wm_map_focus
                ld a,(reg_case)
                cp 2                         ; explicitly exercise background legacy chrome
                call z,clip_set_full
                call wm_repaint_all
                xor a
                ret
reg_full_raw
                ld hl,#4800
                call wm_register
                ld a,0
                adc a,0                     ; raw registration promises NC when full
                ret
reg_full_managed
                ld a,GB_WK_ABI_V1
                ld hl,#4800
                call k_wm_managed             ; void native API: test no mutation, not flags
                xor a
                ret
reg_focus
                ld a,11
                ld (CORE_POINTER_X),a
                ld a,61
                ld (CORE_POINTER_Y),a
                ld a,1
                ld (CORE_INPUT_FLAGS),a
                call wm_focus_click
                xor a
                ret
reg_move
                ld a,18
                ld l,40
                call k_wm_setpos
                call wm_repaint_all
                xor a
                ret
reg_size
                ld a,20
                ld l,30
                call k_wm_setsize
                call wm_repaint_all
                xor a
                ret
reg_close_five
                ld a,5
                call window_handle_slot
                ex de,hl
                ld a,4
                jp k_app
reg_tiny
                ld c,19
                ld b,43
                ld e,2
                ld d,3
                call k_wm_damage
                call wm_repaint_all
                xor a
                ret
reg_cleanup
                ld a,2
                ld (reg_close_slot),a
reg_close_loop
                ld a,(reg_close_slot)
                call wm_entry
                ld a,(hl)
                call foundation_bank_set
                ld a,(reg_close_slot)
                call window_handle_slot
                ex de,hl
                ld a,4
                call k_app
                or a
                jp nz,cpc_probe_fail
                ld hl,reg_close_slot
                inc (hl)
                ld a,(hl)
                cp 8
                jr c,reg_close_loop
                ld a,#C0
                call foundation_bank_set
                xor a
                ret

; Bounded synthetic CONTENT only, never a synthetic window frame. Validate
; the message, published rect and mapped caller before drawing a small mark.
reg_content
                ld a,(GB_MSG)
                cp GB_MSG_DRAW
                ld a,46
                jp nz,cpc_probe_fail
                ld a,(CORE_REGION_SLOT)
                call wm_entry
                ld a,(BANK_CUR)
                cp (hl)
                ld a,47
                jp nz,cpc_probe_fail
                inc hl
                ld de,MW_RECT
                ld b,4
reg_rect_check  ld a,(de)
                cp (hl)
                ld a,48
                jp nz,cpc_probe_fail
                inc hl
                inc de
                djnz reg_rect_check
                ld a,(CORE_REGION_SLOT)
                ld e,a
                ld d,0
                ld hl,reg_calls
                add hl,de
                inc (hl)
                ld a,(MW_RECT)
                add a,2
                ld b,a
                ld a,(MW_RECT+1)
                add a,16
                ld c,a
                ld d,2
                ld e,3
                ld a,#FF
                ld (fb_val),a
                jp fill_xywh

reg_capture
                call reg_alloc
                ld (reg_frame_tag),a
                call foundation_bank_set
                ld hl,#C000
                ld de,#4000
                ld bc,#4000
                ldir
                ld a,(reg_trace_tag)
                call foundation_bank_set
                ld a,(reg_case)
                add a,a
                add a,a
                add a,#40
                ld d,a
                ld e,0
                ld (reg_trace_dest),de
                ld hl,reg_header
                ld a,(reg_case)
                ld (hl),a
                inc hl
                ld a,(reg_status)
                ld (hl),a
                inc hl
                ld a,(reg_bank)
                ld (hl),a
                inc hl
                ld a,(reg_frame_tag)
                ld (hl),a
                inc hl
                ld a,(WM_NWIN)
                ld (hl),a
                inc hl
                ld a,(WM_FOCUS)
                ld (hl),a
                ld hl,reg_clip
                ld de,reg_header+8
                ld bc,4
                ldir
                ld hl,reg_calls
                ld de,reg_header+12
                ld bc,8
                ldir
                ld hl,(CORE_PENDING_OWNER)
                ld (reg_header+20),hl
                ld hl,reg_header
                ld de,(reg_trace_dest)
                ld bc,32
                ldir
                ld hl,#2200
                ld bc,512
                ldir
                ld hl,WM_TABLE
                ld bc,WM_ESZ*8
                ldir
                ld hl,WM_Z
                ld bc,8
                ldir
                ld hl,WM_CLIP_X
                ld bc,4
                ldir
                ld a,#C0
                jp foundation_bank_set
reg_arg db "CHROME  TST"
reg_long_input db "01234567890123456789012345678901234567890123456789",0
                include "registration_vectors.inc"
