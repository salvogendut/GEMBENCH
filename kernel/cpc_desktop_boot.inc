; Private boot-only binding of the actual Desktop to the already-owned root.
; HL = native gb_win_t, DE = bar callback (SDCC call-1). No second registration,
; owner allocation, scheduler install, public ABI or normal APP admission.
CPC_DESKTOP_STATUS equ #1D76
CPC_DESKTOP_PROFILE equ 1
                assert CPC_DESKTOP_STATUS+1<CPC_PICK_PATH,"Desktop boot status overlap"
cpc_desktop_start
                push ix
                push hl
                pop ix
                ld a,(CPC_DESKTOP_STATUS)
                or a
                jp nz,cpc_desktop_bind_reject
                ld a,(BANK_CUR)
                cp #C0
                jp nz,cpc_desktop_bind_reject
                ld a,(SCHED_CURRENT)
                or a
                jp nz,cpc_desktop_bind_reject
                ld a,(WM_NWIN)
                cp 1
                jp nz,cpc_desktop_bind_reject
                ld a,(WM_FOCUS)
                or a
                jp nz,cpc_desktop_bind_reject
                ld a,(WM_TABLE)
                cp #C0
                jp nz,cpc_desktop_bind_reject
                ld a,(WM_TABLE+WM_FR_FLAGS)
                cp 1
                jp nz,cpc_desktop_bind_reject
                ld a,(CORE_WIN_OWNER)
                or a
                jp z,cpc_desktop_bind_reject
                ld a,(CORE_WIN_OWNER_GEN)
                or a
                jp z,cpc_desktop_bind_reject
                ld a,d                     ; bar callback in the loaded root code
                call cpc_desktop_code_high
                jp nc,cpc_desktop_bind_reject
                ld a,h
                call cpc_desktop_code_high
                jp nc,cpc_desktop_bind_reject
                ld bc,11
                add hl,bc                  ; full descriptor remains in loaded code
                ld a,h
                call cpc_desktop_code_high
                jp nc,cpc_desktop_bind_reject
                ld a,(ix+0)
                or (ix+1)
                jp nz,cpc_desktop_bind_reject
                ld a,(ix+2)
                cp CPC_COLUMNS
                jp nz,cpc_desktop_bind_reject
                ld a,(ix+3)
                cp CPC_LINES
                jp nz,cpc_desktop_bind_reject
                ld a,(ix+5)                ; frame/repaint/event code pointers
                call cpc_desktop_code_high
                jp nc,cpc_desktop_bind_reject
                ld a,(ix+7)
                call cpc_desktop_code_high
                jp nc,cpc_desktop_bind_reject
                ld a,(ix+9)
                call cpc_desktop_code_high
                jp nc,cpc_desktop_bind_reject
                ld a,(ix+10)               ; the real document menu is installed later
                or (ix+11)
                jp nz,cpc_desktop_bind_reject
                ; Publish only after all checks; keep page/flags/owner/z-order.
                ld (BAR_HANDLER),de
                push ix
                pop hl
                ld de,WM_TABLE+1
                ld bc,12
                ldir
                ld a,1
                ld (CPC_DESKTOP_STATUS),a
                pop ix
                ret
cpc_desktop_bind_reject
                ld a,2
                ld (CPC_DESKTOP_STATUS),a
                pop ix
                ret
cpc_desktop_code_high
                cp CPC_APP_BASE >> 8
                jr nc,cpc_desktop_code_end
                or a                      ; below start is failure (CF=0)
                ret
cpc_desktop_code_end
                cp cpc_bar_end >> 8
                ret                       ; CF=1 iff inside loaded root slot

cpc_desktop_collect
                call cpc_pointer_service   ; service input before region preparation
                ld hl,(cpc_runtime_turns)
                inc hl
                ld (cpc_runtime_turns),hl
                call cpc_timer_collect
                jp clip_set_full
