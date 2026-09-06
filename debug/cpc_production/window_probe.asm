; Instrumented native records/callbacks, not production chrome or menus.
; Shared core alone mutates live z-order/focus/damage and enumerates clips.
CPC_WINDOW_MENU_CLEAR equ cpc_fixture_menu_clear
CPC_WINDOW_MENU_INSTALL equ cpc_fixture_menu_install
                ifdef CPC_REGISTRATION
CPC_WINDOW_CHROME_DRAW equ wm_chrome_draw
                else
CPC_WINDOW_CHROME_DRAW equ cpc_fixture_paint
                endif
CPC_WM_GUARD equ #3200
CPC_WM_END equ #3280
wm_fixture_event equ #3220
wm_fixture_index equ #3222
wm_fixture_menu equ #3223
wm_fixture_slot equ #3225
wm_fixture_x equ #3226
wm_fixture_y equ #3227
wm_fixture_row equ #3228
wm_fixture_column equ #3229
wm_fixture_right equ #322A
wm_fixture_bottom equ #322B
wm_fixture_width equ #322D
wm_fixture_count equ #3230          ; 5 word write counts + 5 callback counts
wm_fixture_done equ #323F
CPC_WM_TRACE equ #1E00              ; 16 x 32-byte checkpoint state
CPC_WM_TRACE_END equ #2000
                assert CPC_LOAD_COUNT+2<=CPC_WM_TRACE,"WM trace/loader overlap"
                assert CPC_WM_TRACE_END<=CPC_ADAPTER_STATE_END,"WM trace overflow"
                assert CPC_DRAW_TRACE_END<=CPC_WM_GUARD,"WM/drawing state overlap"
                assert CPC_WM_END+16<=CPC_FUTURE_STATE_END,"WM state overflow"

cpc_window_probe
                di
                ld hl,CPC_WM_GUARD
                ld b,16
cpc_wm_guard_low
                ld (hl),#D7
                inc hl
                djnz cpc_wm_guard_low
                ld hl,CPC_WM_END
                ld b,16
cpc_wm_guard_high
                ld (hl),#D7
                inc hl
                djnz cpc_wm_guard_high
                ld hl,cpc_fixture_records
                ld de,WM_TABLE
                ld bc,5*WM_ESZ
                ldir
                xor a
                ld (WM_NWIN),a
                call wm_z_append
                ld a,1
                call wm_z_append
                ld a,4
                call wm_z_append
                ld a,2
                call wm_z_append
                ld a,3
                call wm_z_append
                call wm_focus_top
                ld a,#FF
                ld (CORE_PREVIOUS_FOCUS),a
                ld hl,105
                ld (pointer_x),hl
                ld a,47
                ld (pointer_y),a
                call pointer_show
                ld hl,cpc_window_vectors
                ld (wm_fixture_event),hl
cpc_wm_event_loop
                di
                ld hl,wm_fixture_count
                ld de,wm_fixture_count+1
                ld bc,14
                ld (hl),0
                ldir
                ld a,1
                ld (CORE_INPUT_FLAGS),a
                ld ix,(wm_fixture_event)
                ld a,(ix+0)
                or a
                jr z,cpc_wm_full
                dec a
                jr z,cpc_wm_click
                dec a
                jr z,cpc_wm_move
                dec a
                jr z,cpc_wm_size
                dec a
                jr z,cpc_wm_damage
                dec a
                jr z,cpc_wm_top
                ; Fixture withdrawal tests z-remove, NOT application close.
                ld a,4
                call wm_set_clip
                ld c,4
                call wm_z_remove
                ld a,4
                call sched_wm_entry
                ld de,WM_FR_FLAGS
                add hl,de
                ld (hl),0
                call wm_focus_top
                jr cpc_wm_paint
cpc_wm_full
                call clip_set_full
                jr cpc_wm_paint
cpc_wm_click
                ld a,(ix+1)
                ld (CORE_POINTER_X),a
                ld a,(ix+2)
                ld (CORE_POINTER_Y),a
                call wm_focus_click
                jr cpc_wm_completed
cpc_wm_move
                ld a,(ix+1)
                ld l,(ix+2)
                call k_wm_setpos
                jr cpc_wm_paint
cpc_wm_size
                ld a,(ix+1)
                ld l,(ix+2)
                call k_wm_setsize
                jr cpc_wm_paint
cpc_wm_damage
                ld c,(ix+1)
                ld b,(ix+2)
                ld e,(ix+3)
                ld d,(ix+4)
                call k_wm_damage
                jr cpc_wm_paint
cpc_wm_top
                ld a,(WM_FOCUS)
                call wm_set_clip
                call wm_repaint_top
                jr cpc_wm_completed
cpc_wm_paint
                call wm_repaint_all
cpc_wm_completed
                di
                ld a,(BANK_CUR)
                cp #C0
                ld a,30
                jp nz,cpc_probe_fail
                call wm_map_focus
                call cpc_wm_capture
                ld a,#C0
                call foundation_bank_set
                ld hl,(wm_fixture_event)
                ld de,5
                add hl,de
                ld (wm_fixture_event),hl
                ld hl,wm_fixture_index
                inc (hl)
                ld a,(hl)
                cp CPC_WINDOW_EVENTS
                jp nz,cpc_wm_event_loop
                ld (wm_fixture_done),a
                ; Return to original context fixture for the common checks.
                ld hl,root_record
                ld de,WM_TABLE
                ld bc,50
                ldir
                xor a
                ld (WM_NWIN),a
                call wm_z_append
                ld a,1
                call wm_z_append
                call wm_focus_top
                call clip_set_full
                call sched_compositor_prepare
                ret

cpc_wm_capture
                ; Record focus mapping before the allocator maps a capture page.
                ld a,(wm_fixture_index)
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,CPC_WM_TRACE
                add hl,de
                ex de,hl
                ld hl,wm_fixture_count
                ld bc,15
                ldir
                ld a,(WM_FOCUS)
                ld (de),a
                inc de
                ld a,(CORE_INPUT_FLAGS)
                ld (de),a
                inc de
                ld hl,WM_Z
                ld bc,5
                ldir
                ld a,(BANK_CUR)
                ld (de),a
                inc de
                ld hl,CORE_FOCUS_HANDLER
                ld bc,2
                ldir
                ld hl,wm_fixture_menu
                ld bc,2
                ldir
                ld a,(WM_NWIN)
                ld (de),a
                inc de
                ld hl,pointer_saves
                ld bc,4
                ldir
                jp cpc_draw_capture

; Deterministic clipped furniture/content stand-in. Count every byte/callback.
; Nested hide/show requests must be inhibited by the shared paint-pass lock.
cpc_fixture_paint
                ld a,(CORE_REGION_SLOT)
                ld (wm_fixture_slot),a
                ld e,a
                ld d,0
                ld hl,wm_fixture_count+10
                add hl,de
                inc (hl)
                call cpc_window_pointer_hide
                call cpc_window_pointer_show
                ld a,(wm_fixture_slot)
                call sched_wm_entry
                ld a,(BANK_CUR)
                cp (hl)
                ld a,31
                jp nz,cpc_probe_fail
                inc hl
                ld a,(hl)
                ld (wm_fixture_x),a
                inc hl
                ld a,(hl)
                ld (wm_fixture_y),a
                inc hl
                ld a,(wm_fixture_x)
                add a,(hl)
                dec a
                ld (wm_fixture_right),a
                inc hl
                ld a,(wm_fixture_y)
                add a,(hl)
                dec a
                ld (wm_fixture_bottom),a
                call cpc_window_clip
                ret nc
                ifdef CPC_FAULT_WM_CLIP
                ; Deliberate one-byte overdraw, still within physical RAM.
                ld a,(rect_x)
                ld hl,rect_w
                add a,(hl)
                cp CPC_COLUMNS
                jr nc,cpc_fixture_fault_done
                inc (hl)
cpc_fixture_fault_done
                endif
                ld a,(rect_y)
                ld (wm_fixture_row),a
                ld a,(rect_h)
                ld (draw_rows),a
                call cpc_draw_sample_begin
                ei                           ; IRQs may run; SCHED_LOCK prevents reentry
cpc_fixture_row
                ld a,(rect_x)
                ld (wm_fixture_column),a
                ld d,a
                ld a,(wm_fixture_row)
                ld e,a
                call scr_addr
                ld a,(rect_w)
                ld (wm_fixture_width),a
cpc_fixture_byte
                push hl
                ld a,(wm_fixture_slot)
                or a
                jr z,cpc_fixture_root_pen
                ld c,a
                ld a,(wm_fixture_column)
                ld hl,wm_fixture_x
                cp (hl)
                jr z,cpc_fixture_border
                ld hl,wm_fixture_right
                cp (hl)
                jr z,cpc_fixture_border
                ld a,(wm_fixture_row)
                ld hl,wm_fixture_y
                cp (hl)
                jr z,cpc_fixture_border
                ld hl,wm_fixture_bottom
                cp (hl)
                jr z,cpc_fixture_border
                ld a,c
                jr cpc_fixture_pen_ready
cpc_fixture_border
                ld a,(WM_FOCUS)
                cp c
                ld a,1
                jr nz,cpc_fixture_pen_ready
                ld a,3
                jr cpc_fixture_pen_ready
cpc_fixture_root_pen
                ld a,(wm_fixture_row)
                ld c,a
                ld a,(wm_fixture_column)
                xor c
cpc_fixture_pen_ready
                and 3
                ld e,a
                ld d,0
                ld hl,solid_pens
                add hl,de
                ld a,(hl)
                pop hl
                ld (hl),a
                inc hl
                push hl
                ld a,(wm_fixture_slot)
                add a,a
                ld e,a
                ld d,0
                ld hl,wm_fixture_count
                add hl,de
                inc (hl)
                jr nz,cpc_fixture_counted
                inc hl
                inc (hl)
cpc_fixture_counted
                pop hl
                ld a,(wm_fixture_column)
                inc a
                ld (wm_fixture_column),a
                ld a,(wm_fixture_width)
                dec a
                ld (wm_fixture_width),a
                jr nz,cpc_fixture_byte
                ld a,(wm_fixture_row)
                inc a
                ld (wm_fixture_row),a
                ld a,(draw_rows)
                dec a
                ld (draw_rows),a
                jp nz,cpc_fixture_row
                di
                jp cpc_draw_sample_end
cpc_fixture_menu_clear
                ld hl,0
cpc_fixture_menu_install
                ld (wm_fixture_menu),hl
                ret
                include "window_vectors.inc"
