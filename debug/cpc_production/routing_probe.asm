; Actual shared WM loop, native fixture surfaces and external keyboard input.
; F2 pauses ONLY at the loop boundary for read-only observations. F1 finishes
; through balanced returns and shared sibling close. No snapshot/RAM injection.
rt_ready equ #1E00
rt_done equ #1E01
rt_turns equ #1E02
rt_bars equ #1E04
rt_legacy equ #1E06
rt_menu_flags equ #1E08
rt_bar_bank equ #1E09
rt_last_kind equ #1E0A
rt_last_slot equ #1E0B
rt_last_params equ #1E0C
rt_call_slot equ #1E0F
rt_events equ #1E40              ; three banks of 16 message counters (bytes)
rt_before equ #1E80             ; worker count at start of actual loop
                assert rt_before+2<=CPC_ADAPTER_STATE_END,"routing fixture state overflow"
cpc_routing_probe
                di
                ld a,1
                ld (SCHED_LOCK),a
                ld hl,CPC_WM_GUARD
                call rt_guard
                ld hl,CPC_WM_END
                call rt_guard
                ld hl,CPC_REG_GUARD
                call rt_guard
                ld hl,CPC_REG_END
                call rt_guard
                call app_mark_root_current
                ld hl,rt_root_desc
                ld de,WM_TABLE
                ld bc,25
                ldir
                ld a,1
                ld (KCFG_FRAMEPEN),a
                ld a,#C4
                call foundation_bank_set
                ld hl,(#4200)
                ld (rt_before),hl
                call rt_callbacks
                ld hl,rt_worker_desc
                ld de,#4100
                ld bc,12
                ldir
                ld hl,rt_worker_title
                ld de,#4A00
                call gtd_copy
                ld hl,#4B20
                ld (WM_TABLE+25+9),hl
                xor a
                call k_defer
                ld a,#C0
                call foundation_bank_set
                call rt_callbacks
                ld hl,cpc_timer_payload
                ld de,CPC_TIMER_COLLECT
                ld bc,116
                ldir
                ld hl,rt_cover_desc
                ld de,#4800
                ld bc,13
                ldir
                ld hl,rt_cover_title
                ld de,#4A00
                call gtd_copy
                ld hl,#4800
                ld a,GB_WK_ABI_V1
                call k_wm_managed
                ld hl,#4B60
                ld (BAR_HANDLER),hl
                ld a,2
                ld (poll_byte),a
                ld hl,8
                ld (pointer_x),hl
                ld a,180
                ld (poll_line),a
                ld (pointer_y),a
                ld a,#FF
                ld (CORE_PREVIOUS_FOCUS),a
                call clip_set_full
                call wm_repaint_all
                ld a,#40
                ld (CPC_PHASE),a
                jp wm_loop
rt_guard
                ld b,16
rt_guard_next   ld (hl),#D7
                inc hl
                djnz rt_guard_next
                ret
rt_callbacks
                ld a,#C3
                ld (#4B00),a
                ld (#4B20),a
                ld (#4B40),a
                ld (#4B60),a
                ld hl,rt_proc
                ld (#4B01),hl
                ld (#4B21),hl
                ld hl,rt_root_frame
                ld (#4B41),hl
                ld hl,rt_bar
                ld (#4B61),hl
                ret
rt_root_desc
                db #C0,0,0,80,200
                dw #4B40,rt_background,#4B20,0
                db 9
                ds 11,0
rt_worker_desc  db 8,20,24,30,10,24
                dw #4B00,#4A00,#4000
rt_cover_desc   db 40,60,24,40,10,24
                dw #4B00,#4A00,0
                db 31
rt_worker_title db "Worker",0
rt_cover_title  db "Control",0
rt_root_frame
                call rt_check_root
                ld hl,rt_legacy
                inc (hl)
                ret
rt_bar
                ld a,(BANK_CUR)
                ld (rt_bar_bank),a
                cp #C0
                ld a,61
                jp nz,cpc_probe_fail
                call rt_check_root
                call CPC_TIMER_COLLECT
                ld hl,(rt_bars)
                inc hl
                ld (rt_bars),hl
                ret
rt_check_root
                ld a,(SCHED_CURRENT)
                or a
                ld a,62
                jp nz,cpc_probe_fail
                ld a,(SCHED_LOCK)
                cp 1
                ld a,63
                jp nz,cpc_probe_fail
                ret
rt_proc
                call rt_check_root
                ld a,(GB_MSG)
                cp GB_MSG_DRAW
                jp z,rt_content
                ld e,a
                cp 12                       ; deferred delivery need not target focus
                ld a,(WM_FOCUS)
                jr nz,rt_proc_slot
                ld a,(CORE_DEFER_CURRENT+2)
                dec a
                ld hl,CORE_APP_PRIMARY_WIN
                add a,l
                ld l,a
                ld a,(hl)
rt_proc_slot
                ld (rt_call_slot),a
                push de
                call wm_entry
                ld a,(BANK_CUR)
                cp (hl)
                ld a,64
                jp nz,cpc_probe_fail
                pop de
                ld a,(rt_call_slot)
                add a,a
                add a,a
                add a,a
                add a,a
                add a,e
                ld l,a
                ld h,0
                ld de,rt_events
                add hl,de
                inc (hl)
                ld a,(GB_MSG)
                cp GB_MSG_FRAME
                ret z
                ld (rt_last_kind),a
                ld a,(rt_call_slot)
                ld (rt_last_slot),a
                ld hl,GB_MSG+1
                ld de,rt_last_params
                ld bc,3
                ldir
                ld a,(GB_MSG)
                cp GB_MSG_MENU
                ret nz
                ; Real menu callback queues a message to its own owner. The
                ; same root turn dispatches it after poll/focus, without nesting.
                call owner_current
                ld (#4600),de
                ld a,3
                ld (#4602),a
                ld a,42
                ld (#4603),a
                ld (#4604),a
                ld (#4605),a
                ld hl,#4600
                ld a,1
                jp k_defer
rt_content
                ld a,(CORE_REGION_SLOT)
                inc a
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
rt_background
                xor a
                ld (fb_val),a
                ld bc,0
                ld de,#50C8
                call fill_xywh
                ld a,KWB_LIGHT
                ld (fb_val),a
                ld bc,0
                ld de,#5008
                jp fill_xywh
cpc_route_repeat
                di
                ld hl,(rt_turns)
                inc hl
                ld (rt_turns),hl
                ld a,(CPC_KEYS+1)
                bit 5,a                     ; F1: balanced diagnostic finish
                jp z,rt_finish
                bit 6,a                     ; F2: observable root-loop boundary
                jp nz,wm_loop
                ld a,1
                ld (rt_ready),a
rt_pause
                ei
                halt
                call cpc_input_scan
                ld a,(CPC_KEYS+1)
                bit 6,a
                jr z,rt_pause
                xor a
                ld (rt_ready),a
                jp wm_loop
rt_finish
                ld a,2
                call window_handle_slot
                ex de,hl
                ld a,4
                call k_app
                ld a,#C4
                call foundation_bank_set
                ld hl,(#4200)
                ld (CPC_WORKER_COUNTER),hl
                ld hl,0
                xor a
                call k_defer
                ld a,#C0
                call foundation_bank_set
                ld hl,cpc_fixture_records
                ld de,WM_TABLE
                ld bc,50
                ldir
                ld a,9
                ld (WM_TABLE+25+13),a
                call clip_set_full
                call wm_repaint_all
                ld a,1
                ld (rt_done),a
                di
                ret
                ifdef CPC_FAULT_ROUTE_CLICK
cpc_route_bad_menu
                call menu_dispatch
                ld a,(in_fire)
                or a
                ret z
                ld a,(poll_line)
                cp 8
                ret nc
                set 0,d                      ; fault: menu click leaks into focus routing
                ret
                endif
