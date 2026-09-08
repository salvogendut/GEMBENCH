; Private input/checkpoint orchestration, not a second WM or parameter policy.
cpc_drawing_init
                ld hl,CPC_DRAW_STATE_GUARD
                ld b,16
cpc_draw_guard_low
                ld (hl),#D7
                inc hl
                djnz cpc_draw_guard_low
                ld hl,CPC_DRAW_STATE_END
                ld b,16
cpc_draw_guard_high
                ld (hl),#D7
                inc hl
                djnz cpc_draw_guard_high
                ld hl,cpc_memory_pages
                ld de,CORE_PAGE_NATIVE
                ld bc,CPC_POOL_PAGES
                ldir
                ld a,CPC_POOL_PAGES
                ld (CORE_PAGE_TOTAL),a
                call owner_alloc
                ld (draw_root_owner),de
                ld (CORE_PENDING_OWNER),de
                ld b,1
                call page_alloc_owned
                call app_bind_code_page
                xor a
                call window_generation_next
                ld de,(draw_root_owner)
                xor a
                call app_window_attach
                call owner_alloc
                ld (draw_worker_owner),de
                ld (CORE_PENDING_OWNER),de
                ld b,1
                call page_alloc_owned
                call app_bind_code_page
                ld a,1
                call window_generation_next
                ld de,(draw_worker_owner)
                ld a,1
                call app_window_attach
                ld hl,0
                ld (CORE_PENDING_OWNER),hl
                ld a,1
                ld (CORE_APP_WORKER_WIN+1),a
                call sched_compositor_prepare
                ld a,CPC_DATA_PAGE
                call foundation_bank_set
                ld hl,#4000
                ld de,#4001
                ld bc,#3FFF
                ld (hl),#A9
                ldir
                ld hl,cpc_font_payload
                ld de,#4000
                ld bc,cpc_font_end-cpc_font_payload
                ldir
                ld hl,#4000
                call font_apply_header
                ifdef CPC_FAULT_DRAW_COPY
                ld hl,#4500
                ld (hl),'X'
                inc hl
                ld (hl),0
                endif
                ld a,#C0
                call foundation_bank_set
                ld hl,cpc_drawing_cases
                ld (draw_case_ptr),hl
                ret

cpc_drawing_case
                ld a,(draw_case_index)
                cp CPC_DRAW_CASES
                ret nc
                ld hl,(draw_case_ptr)
                ld de,#4400
                ld bc,16
                ldir
                ld hl,#4400
                ld de,#7EF0
                ld bc,16
                ldir
                ld hl,(draw_case_ptr)
                ld de,29
                add hl,de
                ld de,#4500
                ld bc,48
                ldir
                ld hl,(draw_case_ptr)
                ld de,16
                add hl,de
                ld de,WM_CLIP_X
                ld bc,4
                ldir
                ld ix,(draw_case_ptr)
                ld a,(ix+28)
                cp 1
                jr nz,cpc_draw_not_worker
                ld (SCHED_CURRENT),a
cpc_draw_not_worker
                cp 2
                jr nz,cpc_draw_not_primary
                ld a,#C5
                ld (CORE_APP_CODE_NATIVE),a
cpc_draw_not_primary
                ld a,(ix+28)
                cp 3
                jr nz,cpc_draw_context_ready
                ld a,2
                ld (CORE_PAGE_OWNER_GEN),a
cpc_draw_context_ready
                ld l,(ix+23)
                ld h,(ix+24)
                ld c,(ix+25)
                ld b,(ix+26)
                ld a,(ix+27)
                or a
                jr z,cpc_draw_di
                ei
cpc_draw_di
                ld a,(ix+20)
                or a
                jr nz,cpc_draw_params
                call graphics_gate
                jr cpc_draw_returned
cpc_draw_params
                call universal_parameters
cpc_draw_returned
                ld (draw_status),a
                ld a,e
                ld (draw_boolean),a
                ld a,i
                ld a,0
                jp po,cpc_draw_iff
                inc a
cpc_draw_iff
                ld (draw_iff),a
                di
                ld a,(BANK_CUR)
                cp #C0
                ld a,20
                jp nz,cpc_probe_fail
                ld a,(SCHED_LOCK)
                cp 1
                ld a,21
                jp nz,cpc_probe_fail
                ; IX must have survived the public receiver and native mapping.
                push ix
                pop hl
                ld de,(draw_case_ptr)
                or a
                sbc hl,de
                ld a,22
                jp nz,cpc_probe_fail
                ld a,(draw_status)
                cp (ix+21)
                ld a,23
                jp nz,cpc_probe_fail
                ld a,(draw_iff)
                cp (ix+27)
                ld a,24
                jp nz,cpc_probe_fail
                ld a,(ix+20)
                or a
                jr z,cpc_draw_boolean_ok
                ld a,(draw_boolean)
                cp (ix+22)
                ld a,25
                jp nz,cpc_probe_fail
cpc_draw_boolean_ok
                xor a
                ld (SCHED_CURRENT),a
                ld a,#C0
                ld (CORE_APP_CODE_NATIVE),a
                ld a,1
                ld (CORE_PAGE_OWNER_GEN),a
                ld a,(ix+77)
                or a
                call nz,cpc_draw_capture
                ld hl,(draw_case_ptr)
                ld de,CPC_DRAW_CASE_SIZE
                add hl,de
                ld (draw_case_ptr),hl
                ld hl,draw_case_index
                inc (hl)
                ld hl,draw_case_count_done
                inc (hl)
                xor a
                ld (WM_CLIP_X),a
                ld (WM_CLIP_Y),a
                ld a,CPC_COLUMNS
                ld (WM_CLIP_W),a
                ld a,CPC_LINES
                ld (WM_CLIP_H),a
                ret

cpc_draw_capture
                ld de,(draw_root_owner)
                ld b,6                        ; shared allocator: owned temporary page
                call page_alloc_owned
                ld b,a
                ld a,26
                jp nc,cpc_probe_fail
                ld a,b
                call foundation_bank_set
                ld hl,#C000
                ld de,#4000
                ld bc,#4000
                ldir
                ld a,#C0
                call foundation_bank_set
                ld a,(draw_capture_count)
                add a,a
                add a,a
                ld e,a
                ld d,0
                ld hl,CPC_DRAW_TRACE
                add hl,de
                ex de,hl
                ld hl,pointer_saves
                ld bc,4
                ldir
                ld hl,draw_capture_count
                inc (hl)
                ret
