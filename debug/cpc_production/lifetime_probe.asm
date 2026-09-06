; Private owner/window publication and seeded queue/FS records. These are NOT
; a second lifetime policy, filesystem operations, or an application loader.
CPC_LIFE_GUARD equ #3290
life_trace_tags equ #32A0
life_case equ #32A2
life_status equ #32A3
life_bank equ #32A4
life_frame_native equ #32A5
life_owner equ #32A6
life_primary equ #32A8
life_page_handle equ #32A9
life_window_handle equ #32AB
life_trace_dest equ #32AD
life_mode equ #32AF
life_slot equ #32B0
life_done equ #32B1
life_header equ #32D0
CPC_LIFE_END equ #32F0
                assert CPC_WM_END+16<=CPC_LIFE_GUARD,"lifetime/WM state overlap"
                assert life_header+32<=CPC_LIFE_END,"lifetime header overflow"
                assert CPC_LIFE_END+16<=CPC_FUTURE_STATE_END,"lifetime state overflow"

cpc_lifetime_probe
                di
                ld hl,CPC_WM_GUARD
                call life_guard
                ld hl,CPC_WM_END
                call life_guard
                ld hl,CPC_LIFE_GUARD
                call life_guard
                ld hl,CPC_LIFE_END
                call life_guard
                ld hl,#2840                ; future launch/service reservation
                ld de,#2841
                ld bc,#BF
                ld (hl),#AC
                ldir
                ld hl,cpc_fixture_records
                ld de,WM_TABLE
                ld bc,50
                ldir
                ld hl,WM_TABLE+WM_ESZ+WM_FR_FLAGS
                set 3,(hl)                 ; original worker still owns its runnable slot
                call app_mark_root_current
                ; Two root-owned pages hold sixteen 2048-byte state records.
                call life_trace_alloc
                ld (life_trace_tags),a
                call life_trace_alloc
                ld (life_trace_tags+1),a
life_loop
                ld a,#C0
                call foundation_bank_set
                ld a,(life_case)
                add a,a
                ld e,a
                ld d,0
                ld hl,life_actions
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ex de,hl
                call cpc_window_call
                ld (life_status),a
                di
                ld a,(BANK_CUR)
                ld (life_bank),a
                call life_capture
                ld hl,life_case
                inc (hl)
                ld a,(hl)
                cp 16
                jr nz,life_loop
                ld (life_done),a
                ld a,#C0
                call foundation_bank_set
                ld a,1
                ld (WM_FOCUS),a
                call clip_set_full
                call sched_compositor_prepare
                ret
life_guard
                ld b,16
life_guard_loop
                ld (hl),#D7
                inc hl
                djnz life_guard_loop
                ret
life_trace_alloc
                ld de,(draw_root_owner)
                ld b,6
                call page_alloc_owned
                jp nc,life_alloc_fail
                push af
                call foundation_bank_set
                ld hl,#4000
                ld de,#4001
                ld bc,#3FFF
                ld (hl),#BD
                ldir
                ld a,#C0
                call foundation_bank_set
                pop af
                ret
life_alloc_fail
                ld a,40
                jp cpc_probe_fail

life_actions
                dw life_initial,life_foreign,life_bad_generation,life_close_first
                dw life_close_last,life_dead_window,life_reuse,life_old_window
                dw life_close_reused,life_windowless,life_quit,life_second_pair
                dw life_quit,life_stale_owner,life_root_quit,life_drag_unsupported
life_initial
                ld a,2
                call life_new_app
life_root_quit
                ld a,#C0
                call foundation_bank_set
                ld a,2
                jp k_app
life_foreign
                ld hl,(life_window_handle)
                ld a,4
                jp k_app
life_bad_generation
                call life_map_app
                ld hl,(life_window_handle)
                inc h
                ld a,4
                jp k_app
life_close_first
                call life_map_app
                ld hl,(life_window_handle)
                ld a,4
                jp k_app
life_close_last
                call life_map_app
                ld a,3
                call window_handle_slot
                ex de,hl
                ld a,4
                jp k_app
life_dead_window
                ld hl,(life_window_handle)
                ld a,4
                jp k_app
life_reuse
                ld a,1
                call life_new_app
                xor a
                ret
life_old_window
                call life_map_app
                ld hl,#0103
                ld a,4
                jp k_app
life_close_reused
                jp life_close_first
life_windowless
                xor a
                call life_new_app
                call life_map_app
                ld a,1
                jp k_app
life_quit
                call life_map_app
                ld a,2
                jp k_app
life_second_pair
                ld a,2
                call life_new_app
                xor a
                ret
life_stale_owner
                ld de,#0103
                jp owner_release
life_drag_unsupported
                xor a
                ld (WM_FOCUS),a
                ld a,8
                call k_app
                push af
                ld a,1
                ld (WM_FOCUS),a
                pop af
                ret
life_map_app
                ld a,(life_primary)
                jp foundation_bank_set

; Publish zero, one or two owned native records through the real identity and
; z-order helpers. No application binary or public registration ABI is used.
life_new_app
                ld (life_mode),a
                call owner_alloc
                jp nc,life_alloc_fail
                ld (life_owner),de
                ld (CORE_PENDING_OWNER),de
                ld b,1
                call page_alloc_owned
                jp nc,life_alloc_fail
                ld (life_page_handle),de
                call app_bind_code_page
                ld (life_primary),a
                call foundation_bank_set
                ld hl,#4000
                ld de,#4001
                ld bc,#3FFF
                ld (hl),#A9
                ldir
                ld hl,#FE18                ; private pure-compute JR self
                ld (#4000),hl
                ld hl,#4000
                ld (#410A),hl
                ld de,(life_owner)
                ld b,2
                call page_alloc_owned
                jp nc,life_alloc_fail
                ld de,(life_owner)
                ld b,7
                call page_alloc_owned
                jp nc,life_alloc_fail
                call life_seed_cleanup
                ld a,2
                ld (life_slot),a
                ld a,(life_mode)
                or a
                jr z,life_new_ready
life_attach
                ld a,(life_slot)
                call window_generation_next
                ld a,(life_slot)
                cp 2
                jr nz,life_other_handle
                ld (life_window_handle),de
life_other_handle
                ld a,(life_slot)
                call sched_wm_entry
                ex de,hl
                ld hl,life_record
                ld bc,25
                ldir
                ld a,(life_slot)
                call sched_wm_entry
                ld a,(life_primary)
                ld (hl),a
                inc hl
                ld a,(life_slot)
                cp 2
                jr z,life_geometry_ready
                ld (hl),45
life_geometry_ready
                ld de,(life_owner)
                ld a,(life_slot)
                call app_window_attach
                jp nc,life_alloc_fail
                ld a,(life_slot)
                call wm_z_append
                ld hl,life_slot
                inc (hl)
                ld a,(life_mode)
                add a,2
                cp (hl)
                jr nz,life_attach
                ld a,2
                ld (WM_FOCUS),a
                call k_task_enable          ; actual shared initial worker snapshot
                di
                call app_mark_worker_current
                call wm_focus_top
life_new_ready
                ld hl,0
                ld (CORE_PENDING_OWNER),hl
                call clip_set_full
                call wm_repaint_all
                di
                ld a,#C0
                call foundation_bank_set
                ret
life_record
                db 0,20,60,20,35
                dw #4100,cpc_fixture_paint,#4500,#4600
                db 3
                ds 11,0

life_seed_cleanup
                ld hl,life_queue_seed
                ld de,CORE_DEFER_QUEUE
                ld bc,64
                ldir
                ld a,8
                ld (CORE_DEFER_COUNT),a
                ld hl,life_fs_seed
                ld de,CORE_FSCTX_TABLE
                ld bc,576
                ldir
                ld a,(life_owner+1)
                ld (CORE_DEFER_QUEUE+1),a
                ld (CORE_DEFER_QUEUE+11),a
                ld (CORE_DEFER_QUEUE+41),a
                ld (CORE_DEFER_QUEUE+43),a
                ld (CORE_DEFER_QUEUE+57),a
                ld (CORE_FSCTX_TABLE+3),a
                ld (CORE_FSCTX_TABLE+147),a
                inc a
                ld (CORE_DEFER_QUEUE+17),a
                ld (CORE_DEFER_QUEUE+27),a
                ld (CORE_FSCTX_TABLE+291),a
                ld a,#90
                ld (CORE_DEFER_HANDLER_LO+2),a
                ld a,#40
                ld (CORE_DEFER_HANDLER_HI+2),a
                ld a,#44
                ld (CORE_APP_SERVICE+2),a
                ld a,#55
                ld (CORE_APP_ACCESSORY+2),a
                ret

life_capture
                ; Every frame is a real root-owned temporary allocation. Its
                ; tag is recorded, so captures need not occupy contiguous pages.
                ld de,(draw_root_owner)
                ld b,6
                call page_alloc_owned
                jp nc,life_alloc_fail
                ld (life_frame_native),a
                call foundation_bank_set
                ld hl,#C000
                ld de,#4000
                ld bc,#4000
                ldir
                ld a,(life_case)
                and 7
                add a,a
                add a,a
                add a,a
                add a,#40
                ld h,a
                ld l,0
                ld (life_trace_dest),hl
                ld a,(life_case)
                cp 8
                ld a,(life_trace_tags)
                jr c,life_trace_first
                ld a,(life_trace_tags+1)
life_trace_first
                call foundation_bank_set
                ld a,(life_case)
                ld (life_header),a
                ld a,(life_status)
                ld (life_header+1),a
                ld a,(life_bank)
                ld (life_header+2),a
                ld a,(WM_FOCUS)
                ld (life_header+3),a
                ld a,(WM_NWIN)
                ld (life_header+4),a
                ld a,(SCHED_RUNNABLE)
                ld (life_header+5),a
                ld a,(life_frame_native)
                ld (life_header+6),a
                ld a,(life_primary)
                ld (life_header+7),a
                ld hl,(life_owner)
                ld (life_header+8),hl
                ld hl,(life_window_handle)
                ld (life_header+10),hl
                ld hl,(pointer_saves)
                ld (life_header+12),hl
                ld hl,(pointer_restores)
                ld (life_header+14),hl
                ld hl,life_header
                ld de,(life_trace_dest)
                ld bc,32
                ldir
                ld hl,#2200
                ld bc,#200
                ldir
                ld hl,CORE_FSCTX_TABLE
                ld bc,576
                ldir
                ld hl,WM_TABLE
                ld bc,200
                ldir
                ld hl,WM_Z
                ld bc,8
                ldir
                ld hl,WM_CLIP_X
                ld bc,4
                ldir
                ld a,#C0
                jp foundation_bank_set
                include "lifetime_vectors.inc"
