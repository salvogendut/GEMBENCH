; Private inputs/root-turn driver and observations. Policy is shared, including
; real worker GB_PARAMS publication and the app-linked SDAS timer collector.
svc_case equ #3360
svc_request equ #3361
svc_worker_status equ #3362
svc_publishes equ #3363
svc_deliveries equ #3364
svc_turns equ #3365
svc_dispatch_bank equ #3366
svc_trace_tag equ #3367
svc_frame_tag equ #3368
svc_index equ #3369
svc_busy_status equ #336A
svc_done equ #336B
svc_paints equ #3370
svc_recursions equ #3373
svc_color equ #3374
svc_vector equ #3375
svc_copy equ #3378
svc_header equ #3380
svc_hidden_before equ #33A0
svc_hidden_ok equ #33A2
svc_trace_dest equ #33A3
svc_cycles equ #33A5
svc_api equ #1E00
svc_lookup equ #1E40
svc_log equ #1E80
                assert svc_log+8*12<=CPC_ADAPTER_STATE_END,"service delivery log overflow"
                assert svc_cycles+1<=CPC_REG_END,"service fixture overflow"

cpc_services_probe
                di
                ld hl,CPC_WM_GUARD
                call svc_guard
                ld hl,CPC_WM_END
                call svc_guard
                ld hl,CPC_REG_GUARD
                call svc_guard
                ld hl,CPC_REG_END
                call svc_guard
                call app_mark_root_current
                ld hl,cpc_fixture_records
                ld de,WM_TABLE
                ld bc,25
                ldir
                ld a,1
                ld (KCFG_FRAMEPEN),a
                ld a,3
                ld (svc_color),a
                ld a,#C4
                call foundation_bank_set
                ld hl,svc_worker_desc
                ld de,#4100
                ld bc,12
                ldir
                ld hl,svc_title
                ld de,#4A00
                call gtd_copy
                call svc_callbacks
                call svc_register_endpoint
                ld a,#C0
                call foundation_bank_set
                call svc_callbacks
                call svc_register_endpoint
                ld hl,cpc_timer_payload
                ld de,CPC_TIMER_COLLECT
                ld bc,116
                ldir
                ld hl,svc_cover_desc
                ld de,#4800
                ld bc,13
                ldir
                ld hl,svc_cover_title
                ld de,#4A00
                call gtd_copy
                ld hl,#4800
                ld a,GB_WK_ABI_V1
                call k_wm_managed
                ld a,#40
                ld (CORE_APP_SERVICE),a
                ld a,#A0
                ld (CORE_APP_SERVICE+1),a
                ld a,7
                ld (CORE_APP_ACCESSORY+1),a
                call svc_admission
                call svc_register_endpoint
                call svc_lookup_test
                call svc_alloc
                ld (svc_trace_tag),a
                call foundation_bank_set
                ld hl,#4000
                ld de,#4001
                ld bc,#3FFF
                ld (hl),#BD
                ldir
svc_loop
                ld a,#C0
                call foundation_bank_set
                xor a
                ld (svc_paints),a
                ld (svc_paints+1),a
                ld (svc_paints+2),a
                ld a,(svc_case)
                add a,a
                ld e,a
                ld d,0
                ld hl,svc_actions
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ex de,hl
                call md_call
                di
                call svc_capture
                ld hl,svc_case
                inc (hl)
                ld a,(hl)
                cp 16
                jr nz,svc_loop
                ld (svc_done),a
                call clip_set_full
                call sched_compositor_prepare
                ret
svc_guard
                ld b,16
svc_guard_loop  ld (hl),#D7
                inc hl
                djnz svc_guard_loop
                ret
svc_callbacks
                ld a,#C3
                ld (#4B00),a
                ld (#4B20),a
                ld hl,svc_content
                ld (#4B01),hl
                ld hl,svc_handler
                ld (#4B21),hl
                ret
svc_register_endpoint
                ld hl,#4B20
                xor a
                jp k_defer
svc_alloc
                ld de,(draw_root_owner)
                ld b,6
                call page_alloc_owned
                ret c
                ld a,50
                jp cpc_probe_fail

svc_admission
                ld hl,svc_api_vectors
                ld (svc_vector),hl
                xor a
                ld (svc_index),a
svc_api_loop
                ld ix,(svc_vector)
                ld a,(ix+3)
                ld (SCHED_CURRENT),a
                ld l,(ix+1)
                ld h,(ix+2)
                ld a,(ix+0)
                call k_defer
                ld c,a
                ld a,(svc_index)
                ld e,a
                ld d,0
                ld hl,svc_api
                add hl,de
                ld (hl),c
                ld hl,(svc_vector)
                ld de,4
                add hl,de
                ld (svc_vector),hl
                ld hl,svc_index
                inc (hl)
                ld a,(hl)
                cp 11
                jr c,svc_api_loop
                xor a
                ld (SCHED_CURRENT),a
                ld hl,svc_edge_message
                ld de,#7EFA
                ld bc,6
                ldir
                ld hl,#7EFA
                ld a,1
                call k_defer
                ld (svc_api+11),a
                ld a,6
                call k_defer
                ld (svc_api+12),a
                ret
svc_lookup_test
                ld b,#A0
                ld a,4
                call k_defer
                ld (svc_lookup),de
                ld c,7
                ld a,5
                call k_defer
                ld (svc_lookup+2),de
                ld c,8
                ld a,5
                call k_defer
                ld (svc_lookup+4),de
                ld b,0
                ld a,4
                call k_defer
                ld (svc_lookup+6),de
                ld b,#40
                ld a,4
                call k_defer
                ld (svc_lookup+8),de
                ret
svc_actions
                dw svc_initial,svc_fill_queue,svc_turn,svc_turn
                dw svc_cancel,svc_turn,svc_unregister,svc_activate
                dw svc_visible,svc_partial,svc_component_hidden,svc_window_hidden
                dw svc_stale_timer,svc_fullscreen,svc_drop_receivers,svc_cleanup
svc_initial
                call clip_set_full
                jp wm_repaint_all
svc_fill_queue
                xor a
                ld (svc_index),a
svc_enqueue_loop
                ld a,(svc_index)
                and 1
                ld a,#C0
                ld de,#0102
                jr z,svc_enqueue_bank
                ld a,#C4
                dec e
svc_enqueue_bank
                push de
                call foundation_bank_set
                pop de
                ld (#4600),de
                ld a,(svc_index)
                ld (#4603),a
                add a,#A0
                ld (#4604),a
                add a,#10
                ld (#4605),a
                ld a,(svc_index)
                or a
                ld a,3
                jr nz,svc_enqueue_type
                ld a,1
svc_enqueue_type
                ld (#4602),a
                ld hl,#4600
                ld a,1
                call k_defer
                or a
                ld a,51
                jp nz,cpc_probe_fail
                ld hl,svc_index
                inc (hl)
                ld a,(hl)
                cp 8
                jr c,svc_enqueue_loop
                ld a,#C0
                call foundation_bank_set
                ld hl,#4600
                ld a,1
                call k_defer
                ld (svc_api+16),a          ; valid full
                ld a,2
                ld (#4601),a
                ld hl,#4600
                ld a,1
                call k_defer
                ld (svc_api+17),a          ; stale precedes full
                ld a,1
                ld (#4601),a
                xor a
                ld (CORE_DEFER_HANDLER_LO+1),a
                ld (CORE_DEFER_HANDLER_HI+1),a
                ld hl,#4600
                ld a,1
                call k_defer
                ld (svc_api+18),a          ; no endpoint precedes full
                ld a,#20
                ld (CORE_DEFER_HANDLER_LO+1),a
                ld a,#4B
                ld (CORE_DEFER_HANDLER_HI+1),a
                ld hl,CORE_APP_FLAGS+1
                set 2,(hl)
                ld hl,#4600
                ld a,1
                call k_defer
                ld (svc_api+19),a
                ld hl,CORE_APP_FLAGS+1
                res 2,(hl)
                xor a
                ld (#4602),a
                ld hl,#4600
                ld a,1
                call k_defer
                ld (svc_api+20),a
                ret
svc_turn
                call cpc_root_dispatch_phase  ; same bounded phase as the MSX WM loop
                ld a,(BANK_CUR)
                ld (svc_dispatch_bank),a
                ld a,#C0                    ; Desktop's app-linked bar/collector phase
                call foundation_bank_set
                call CPC_TIMER_COLLECT
                di
                ld hl,svc_turns
                inc (hl)
                ret
svc_cancel
                ld a,6
                call k_defer
                ld (svc_api+21),a
                ret
svc_unregister
                ld a,#C4
                call foundation_bank_set
                ld hl,0
                xor a
                call k_defer
                ld (svc_api+22),a
                call svc_register_endpoint
                ld a,#C0
                jp foundation_bank_set
svc_activate
                call svc_send_activation
                jp svc_turn
svc_send_activation
                ld hl,svc_activation
                ld de,#4600
                ld bc,6
                ldir
                ld hl,#4600
                ld a,1
                jp k_defer

; The real IRQ-preempted worker consumes requests, never a forged CURRENT field.
cpc_service_worker_hook
                ld a,(svc_request)
                or a
                ret z
                ld hl,#4600
                ld bc,16
                call universal_parameters
                ld (svc_worker_status),a
                ld hl,#4604
                inc (hl)                    ; busy publish must not overwrite the first rectangle
                ld hl,#4600
                ld bc,16
                call universal_parameters
                ld (svc_busy_status),a
                ld hl,svc_publishes
                inc (hl)
                xor a
                ld (svc_request),a
                ret
svc_yield
                xor a
                ld (SCHED_LOCK),a
                call sched_yield
                di
                ld a,1
                ld (SCHED_LOCK),a
                ret
svc_submit
                push hl                     ; fixed four-byte component rectangle
                ld a,#C4
                call foundation_bank_set
                ld hl,svc_timer_request
                ld de,#4600
                ld bc,16
                ldir
                pop hl
                ld de,#4604
                ld bc,4
                ldir
                ld a,#C0
                call foundation_bank_set
                ld a,1
                ld (svc_request),a
                ld a,20
                ld (svc_cycles),a
svc_wait_worker
                call svc_yield
                ld a,(svc_request)
                or a
                ret z
                ld hl,svc_cycles
                dec (hl)
                jr nz,svc_wait_worker
                ld a,52
                jp cpc_probe_fail
svc_visible
                ld a,2
                call wm_raise
                call clip_set_full
                call wm_repaint_all
                ld a,2
                ld (svc_color),a
                ld hl,svc_rect_visible
                call svc_submit
                jp svc_turn
svc_partial
                ld a,1
                ld (svc_color),a
                ld hl,svc_rect_partial
                call svc_submit
                jp svc_turn
svc_component_hidden
                xor a
                ld (svc_color),a
                ld hl,svc_rect_hidden
                call svc_submit
                jp svc_turn
svc_window_hidden
                ld hl,svc_rect_visible
                call svc_submit
                ld a,8
                ld l,20
                call k_wm_setpos
                call wm_repaint_all
                ld a,24
                ld l,30
                call k_wm_setsize
                call wm_repaint_all
                ; A completely hidden worker must not consume another request.
                ld a,1
                ld (svc_request),a
                ld a,#C4
                call foundation_bank_set
                ld hl,(#4200)
                ld (svc_hidden_before),hl
                ld a,#C0
                call foundation_bank_set
                call svc_yield
                call svc_yield
                call svc_yield
                call svc_yield
                ld a,#C4
                call foundation_bank_set
                ld hl,(#4200)
                ld de,(svc_hidden_before)
                or a
                sbc hl,de
                ld a,53
                jp nz,cpc_probe_fail
                ld a,(svc_request)
                ld (svc_hidden_ok),a
                xor a
                ld (svc_request),a
                ld a,#C0
                call foundation_bank_set
                jp svc_turn
svc_stale_timer
                ld a,20
                ld l,25
                call k_wm_setpos
                call wm_repaint_all
                ld a,20
                ld l,35
                call k_wm_setsize
                call wm_repaint_all
                ld hl,svc_rect_visible
                call svc_submit
                ld hl,CORE_WIN_GEN+1         ; invalidate after publication, not a fake publisher
                inc (hl)
                jp svc_turn
svc_fullscreen
                ld a,1
                ld (CORE_WIN_GEN+1),a
                ld hl,svc_rect_visible
                call svc_submit
                ld a,1
                ld (CPC_FULLSCREEN),a
                call svc_turn
                xor a
                ld (CPC_FULLSCREEN),a
                ret
svc_drop_receivers
                call svc_send_activation
                ld hl,CORE_OWNER_GEN+1
                inc (hl)
                call svc_turn               ; receiver generation changed since send
                ld hl,CORE_OWNER_GEN+1
                dec (hl)
                call svc_send_activation
                ld hl,CORE_APP_FLAGS+1
                set 2,(hl)
                call svc_turn
                ld hl,CORE_APP_FLAGS+1
                res 2,(hl)
                call svc_send_activation
                xor a
                ld (CORE_DEFER_HANDLER_LO+1),a
                ld (CORE_DEFER_HANDLER_HI+1),a
                call svc_turn
                ld a,#C4
                call foundation_bank_set
                call svc_register_endpoint
                ld a,#C0
                call foundation_bank_set
                call svc_send_activation
                xor a
                ld (CORE_APP_CODE_NATIVE+1),a
                call svc_turn
                ld a,#C4
                ld (CORE_APP_CODE_NATIVE+1),a
                call svc_send_activation
                ld a,#FF
                ld (CORE_APP_PRIMARY_WIN+1),a
                call svc_turn               ; windowless endpoint: deliver but do not activate
                ld a,1
                ld (CORE_APP_PRIMARY_WIN+1),a
                ret
svc_cleanup
                ld hl,0
                xor a
                call k_defer
                ld a,#C4
                call foundation_bank_set
                ld hl,0
                xor a
                call k_defer
                ld hl,(#4200)
                ld (CPC_WORKER_COUNTER),hl
                ld a,#C0
                call foundation_bank_set
                ld a,2
                call window_handle_slot
                ex de,hl
                ld a,4
                call k_app
                ld hl,cpc_fixture_records+25
                ld de,WM_TABLE+25
                ld bc,25
                ldir
                ld a,9
                ld (WM_TABLE+25+WM_FR_FLAGS),a
                call clip_set_full
                jp wm_repaint_all

svc_handler
                ld a,(svc_deliveries)
                cp 8
                ld a,54
                jp nc,cpc_probe_fail
                ld a,2
                call k_defer
                ld hl,CORE_DEFER_CURRENT
                or a
                sbc hl,de
                ld a,55
                jp nz,cpc_probe_fail
                ld hl,CORE_DEFER_CURRENT
                ld de,svc_copy
                ld bc,8
                ldir
                ld a,(svc_deliveries)
                add a,a
                ld e,a
                add a,a
                add a,e
                add a,a                    ; delivery index * 12
                ld e,a
                ld d,0
                ld hl,svc_log
                add hl,de
                ex de,hl
                ld hl,CORE_DEFER_CURRENT
                ld bc,8
                ldir
                ld a,(BANK_CUR)
                ld (de),a
                inc de
                ld a,(WM_FOCUS)
                ld (de),a
                inc de
                ld a,(SCHED_CURRENT)
                ld (de),a
                inc de
                ld a,(SCHED_LOCK)
                ld (de),a
                ld hl,svc_deliveries
                inc (hl)
                ld a,(CORE_DEFER_CURRENT+4)
                cp 1
                jr nz,svc_no_reply
                ld hl,(CORE_DEFER_CURRENT)
                ld (#4680),hl
                ld hl,svc_reply+2
                ld de,#4682
                ld bc,4
                ldir
                ld hl,#4680
                ld a,1
                call k_defer
                or a
                ld a,56
                jp nz,cpc_probe_fail
svc_no_reply
                call defer_dispatch_one    ; busy suppresses nesting, including the new reply
                ld hl,CORE_DEFER_CURRENT
                ld de,svc_copy
                ld b,8
svc_current_check
                ld a,(de)
                cp (hl)
                ld a,57
                jp nz,cpc_probe_fail
                inc hl
                inc de
                djnz svc_current_check
                ld a,(CORE_DEFER_CURRENT+4)
                cp 2
                ret nz
                ld a,1
                ld (CORE_MESSAGE+3),a
                ret

svc_content
                ld a,(GB_MSG)
                cp GB_MSG_DRAW
                ld a,58
                jp nz,cpc_probe_fail
                ld a,(CORE_REGION_SLOT)
                ld e,a
                ld d,0
                ld hl,svc_paints
                add hl,de
                inc (hl)
                ld a,(BANK_CUR)
                cp #C0
                jr nz,svc_content_fill
                ld a,(CORE_PARAM_TIMER_OWNER)
                bit 7,a
                jr z,svc_content_fill
                call CPC_TIMER_COLLECT      ; active marker rejects recursive root collection
                ld hl,svc_recursions
                inc (hl)
svc_content_fill
                ld a,(CORE_REGION_SLOT)
                cp 1
                ld a,3
                jr nz,svc_content_pen
                ld a,(svc_color)
svc_content_pen
                call pen_to_byte
                ld (fb_val),a
                ld a,(MW_RECT)
                inc a
                ld b,a
                ld a,(MW_RECT+1)
                add a,15
                ld c,a
                ld a,(MW_RECT+2)
                sub 2
                ld d,a
                ld a,(MW_RECT+3)
                sub 16
                ld e,a
                jp fill_xywh

svc_capture
                call svc_alloc
                ld (svc_frame_tag),a
                call foundation_bank_set
                ld hl,#C000
                ld de,#4000
                ld bc,#4000
                ldir
                ld a,(svc_trace_tag)
                call foundation_bank_set
                ld a,(svc_case)
                add a,a
                add a,a
                add a,#40
                ld d,a
                ld e,0
                ld (svc_trace_dest),de
                ld hl,svc_case
                ld de,svc_header
                ld bc,12
                ldir
                ld a,(WM_NWIN)
                ld (svc_header+12),a
                ld a,(WM_FOCUS)
                ld (svc_header+13),a
                ld a,(CORE_PARAM_DROPPED)
                ld (svc_header+14),a
                ld a,(CORE_PARAM_DROPPED_GEN)
                ld (svc_header+15),a
                ld hl,svc_paints
                ld de,svc_header+16
                ld bc,5
                ldir
                ld hl,(pointer_saves)
                ld (svc_header+22),hl
                ld hl,(pointer_restores)
                ld (svc_header+24),hl
                ld a,(svc_hidden_ok)
                ld (svc_header+26),a
                ld hl,svc_header
                ld de,(svc_trace_dest)
                ld bc,32
                ldir
                ld hl,#2200
                ld bc,512
                ldir
                ld hl,WM_TABLE
                ld bc,75
                ldir
                ld hl,WM_Z
                ld bc,8
                ldir
                ld hl,WM_CLIP_X
                ld bc,4
                ldir
                ld hl,svc_log
                ld bc,96
                ldir
                ld hl,svc_api
                ld bc,32
                ldir
                ld hl,svc_lookup
                ld bc,10
                ldir
                ld a,#C0
                jp foundation_bank_set
svc_worker_desc db 8,20,24,30,10,24
                dw #4B00,#4A00,#4000
svc_cover_desc db 20,25,20,35,10,24
                dw #4B00,#4A00,0
                db 0
svc_title db "Timer",0
svc_cover_title db "Cover",0
svc_edge_message dw #0102
                db 3,9,10,11
svc_activation dw #0102
                db 2,7,8,9
svc_reply dw #0101
                db 2,#EE,#DD,#CC
svc_timer_request db 3,1
                dw #0102
                ds 12,0
svc_rect_visible db 10,36,2,3
svc_rect_partial db 18,36,6,3
svc_rect_hidden db 22,36,3,3
svc_api_vectors
                db 0
                dw #3FFF
                db 0,0
                dw #7F00
                db 0,0
                dw #4B20
                db 1,1
                dw #3FFF
                db 0,1
                dw #7EFB
                db 0,1
                dw #8000
                db 0,1
                dw #4600
                db 1,7
                dw 0
                db 0,3
                dw 0
                db 0,2
                dw 0
                db 0,0
                dw #7EFF
                db 0
