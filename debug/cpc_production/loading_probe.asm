; Real M4 inputs and transaction captures, no RAM-loaded applications.
lp_case equ #3300
lp_executed equ #3301
lp_trace equ #3302
lp_request equ #3304
lp_owner equ #3306
lp_saved_page equ #3308
lp_done equ #3309
lp_last_page equ #330A
lp_iff equ #330B
lp_snapshot equ #3310              ; 32-byte fixed capture before data-page map
lp_pressure_count equ #3330
lp_pressure equ #3332              ; up to 26 native pages or six owner handles
CPC_LOADING_TRACE equ #6200        ; reserved data-page test telemetry
cpc_loading_probe
                di
                ld a,1
                ld (SCHED_LOCK),a
                ld (KCFG_FRAMEPEN),a
                ld a,9                       ; original worker has no paint proc
                ld (WM_TABLE+WM_ESZ+WM_FR_FLAGS),a
                ld a,#C5                     ; first free page's context fence
                call foundation_bank_set
                ld hl,CPC_APP_LIMIT
                ld de,CPC_APP_LIMIT+1
                ld bc,255
                ld (hl),#D7
                ldir
                ld a,#C0
                call foundation_bank_set
                ld hl,CPC_LOADING_TRACE
                ld (lp_trace),hl
                ld hl,lp_inputs
                ld (lp_request),hl
                ld a,#50
                ld (CPC_PHASE),a
lp_next
                ; All app names originate in the caller's page, as on MSX.
                ld hl,(lp_request)
                ld de,#4700
                call copy11
                ld (lp_request),hl
                call lp_allocate_pressure
                ld a,(lp_case)
                cp LP_LAUNCH_AS
                jr nz,lp_open
                ld hl,lp_argument
                ld de,fs_ent_name
                call copy11
                ld a,1
                ld (WM_OPEN_STRICT),a
                ld hl,#4700
                call k_wm_launch_as
                jr lp_capture
lp_open
                ld hl,#4700
                call k_wm_open
lp_capture
                ld a,i
                ld a,0
                jp po,lp_iff_saved
                inc a
lp_iff_saved
                ld (lp_iff),a
                di
                ld hl,lp_snapshot
                ld a,(CORE_PAGE_FREE)
                ld (hl),a
                inc hl
                ld a,(WM_NWIN)
                ld (hl),a
                inc hl
                ld a,(WM_FOCUS)
                ld (hl),a
                inc hl
                ld a,(BANK_CUR)
                ld (hl),a
                inc hl
                ld de,(CORE_PENDING_OWNER)
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                ld a,(lp_executed)
                ld (hl),a
                inc hl
                ld a,(lp_case)
                ld (hl),a
                inc hl
                ex de,hl
                ld hl,CORE_OWNER_ACTIVE
                ld bc,8
                ldir
                ld a,(WM_TABLE+2*WM_ESZ)
                ld (de),a
                inc de
                ld hl,CORE_WIN_OWNER+2
                ldi
                ld hl,CORE_WIN_OWNER_GEN+2
                ldi
                ld a,(WM_TABLE+2*WM_ESZ+WM_FR_FLAGS)
                ld (de),a
                inc de
                ld hl,fs_ent_size
                ld bc,2
                ldir
                ld a,(lp_iff)
                ld (de),a
                inc de
                ld a,(SCHED_LOCK)
                ld (de),a
                inc de
                ld a,(SCHED_CURRENT)
                ld (de),a
                inc de
                ld a,(io_status)
                ld (de),a
                inc de
                ld a,(io_offline)
                ld (de),a
                inc de
                ld a,(io_fd)
                ld (de),a
                inc de
                ld a,(CORE_APP_CODE_NATIVE+2)
                ld (de),a
                inc de
                ld a,(CORE_APP_CODE_PAGE+2)
                ld (de),a
                inc de
                ld a,(WM_OPEN_STRICT)
                ld (de),a
                inc de
                ld a,(WM_TABLE+2*WM_ESZ+14)
                ld (de),a
                ld a,CPC_DATA_PAGE
                call foundation_bank_set
                ld hl,lp_snapshot
                ld de,(lp_trace)
                ld bc,32
                ldir
                ld (lp_trace),de
                ld a,#C0
                call foundation_bank_set
                ld a,(WM_NWIN)
                cp 3
                jr nz,lp_closed
                ; Real successful registration and real last-window cleanup.
                ld c,2
                call app_window_close_slot
                di
lp_closed
                call lp_release_pressure
                ld hl,lp_case
                inc (hl)
                ld a,(hl)
                cp LP_CASES
                jp nz,lp_next
                ld (lp_done),a
                ld a,3
                ld (WM_TABLE+WM_ESZ+WM_FR_FLAGS),a
                call clip_set_full
                call sched_compositor_prepare
                ret
; Exhaustion is reached using the real allocator, not forged counters/tables.
lp_allocate_pressure
                ld a,(lp_case)
                cp LP_NOOWNER
                jr z,lp_owner_more
                cp LP_NOPAGE
                ret nz
lp_page_more
                ld de,(draw_root_owner)
                ld b,GB_PAGE_RESOURCE
                call page_alloc_owned
                ret nc
                ld e,a
                ld d,0
                call lp_save_allocation
                jr lp_page_more
lp_owner_more
                call owner_alloc
                ret nc
                call lp_save_allocation
                jr lp_owner_more
lp_save_allocation
                ld a,(lp_pressure_count)
                add a,a
                ld l,a
                ld h,0
                ld bc,lp_pressure
                add hl,bc
                ld (hl),e
                inc hl
                ld (hl),d
                ld hl,lp_pressure_count
                inc (hl)
                ret
lp_release_pressure
                ld a,(lp_pressure_count)
                or a
                ret z
                dec a
                ld (lp_pressure_count),a
                add a,a
                ld l,a
                ld h,0
                ld bc,lp_pressure
                add hl,bc
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld a,(lp_case)
                cp LP_NOOWNER
                jr nz,lp_release_page
                call owner_release
                jr lp_release_pressure
lp_release_page
                ld a,e
                call wm_free_page
                jr lp_release_pressure
                assert lp_pressure+52<CPC_REG_END,"loading pressure telemetry overflow"
lp_argument db "DRAW    PIC"
                include "loading_vectors.inc"
