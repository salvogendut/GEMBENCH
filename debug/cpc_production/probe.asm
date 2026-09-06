; Synthetic records exercise real shared context/visibility code, NOT a WM.
cpc_probe_start
                di
                ld sp,CPC_MAIN_TOP
                ld hl,CPC_MAIN_TOP
                ld (BOOT_SP),hl
                ld hl,magic_bytes
                ld de,CPC_RESULT
                ld bc,6
                ldir
                call cpc_memory_admit
                ld a,8
                jp nc,cpc_probe_fail
                ld hl,300
                ld (CPC_HW_DIVIDER),hl
                call sched_init_impl
                xor a
                ld (SCHED_CURRENT),a
                ld a,1
                ld (SCHED_RUNNABLE),a
                ld (WM_FOCUS),a
                ld (WM_Z+1),a
                ld (CPC_WIN_OWNER),a
                ld a,2
                ld (WM_NWIN),a
                ld (CPC_WIN_OWNER+1),a
                ld hl,CPC_APP_WORKER_WIN
                ld b,8
cpc_workers_clear
                ld (hl),#FF
                inc hl
                djnz cpc_workers_clear
                ld a,1
                ld (CPC_APP_WORKER_WIN+1),a
                ld hl,root_record
                ld de,WM_TABLE
                ld bc,50
                ldir
                ; Seed full pages, not merely two bank-shadow values.
                ld a,#C4
                call foundation_bank_set
                ld hl,#4000
                ld de,#4001
                ld bc,#3FFF
                ld (hl),#A9
                ldir
                ld hl,worker_code
                ld de,#4000
                ld bc,worker_code_end-worker_code
                ldir
                ld hl,#4000
                ld (#410A),hl                 ; managed desc.task_worker
                ld hl,0
                ld (#4200),hl
                call k_task_enable            ; real shared two-byte startup
                di
                ld a,#C0
                call foundation_bank_set
                ld a,80
                ld (WM_CLIP_W),a
                ld a,200
                ld (WM_CLIP_H),a
                call sched_compositor_prepare ; real shared visible classification
                ld a,2
                ld (CPC_PHASE),a
                ei
; The host presses Right through the emulated CPC keyboard, not RAM injection.
cpc_wait_input
                call cpc_input_scan
                ld a,(CPC_KEYS)
                bit 1,a
                jr nz,cpc_wait_input
                ld (CPC_KEY_OBSERVED),a
                ld a,3
                ld (CPC_PHASE),a
cpc_root_loop
                di
                xor a
                ld (SCHED_LOCK),a
                call sched_yield
                di
                ld a,(SCHED_FAULT)
                or a
                ld a,1
                jp nz,cpc_probe_fail
                ld a,(BANK_CUR)
                cp #C0
                ld a,2
                jp nz,cpc_probe_fail
                ld hl,(CPC_ROOT_TURNS)
                inc hl
                ld (CPC_ROOT_TURNS),hl
                ; Primary-page request/buffer, same real M4 leaf as bootstrap.
                ld hl,io_request
                ld de,#4300
                ld bc,16
                ldir
                ld hl,io_path
                ld de,#4320
                ld bc,10
                ldir
                ld a,(CPC_ROOT_TURNS)
                and 1
                jr z,cpc_io_di
                ei
cpc_io_di
                ld hl,#4300
                ld bc,16
                call storage_gate
                or a
                ld a,3
                jp nz,cpc_probe_fail
                ld a,e
                cp 64
                ld a,4
                jp nz,cpc_probe_fail
                ld a,i
                ld a,0
                jp po,cpc_io_iff
                inc a
cpc_io_iff
                ld b,a
                di
                ld a,(CPC_ROOT_TURNS)
                and 1
                cp b
                ld a,5
                jp nz,cpc_probe_fail
                if CPC_FAULT_RESTORE
                ld a,#C4
                call foundation_bank_set
                endif
                ld hl,#4340
                ld b,64
cpc_verify_io
                ld a,(hl)
                cp b
                ld a,6
                jp nz,cpc_probe_fail
                inc hl
                djnz cpc_verify_io
                ld a,(BANK_CUR)
                cp #C0
                ld a,7
                jp nz,cpc_probe_fail
                ld hl,(CPC_IO_CHECKS)
                inc hl
                ld (CPC_IO_CHECKS),hl
                ld a,(CPC_ROOT_TURNS)
                cp 64
                jp nz,cpc_root_loop
                ld a,#C4
                call foundation_bank_set
                ld hl,(#4200)
                ld (CPC_WORKER_COUNTER),hl       ; wrapping compute counter
                ld a,#C0
                call foundation_bank_set
                if CPC_FAULT_GUARD
                ld hl,CPC_MAIN_STACK-1
                inc (hl)
                endif
                ld a,#A5
                ld (CPC_PHASE),a
                jr cpc_probe_stop
cpc_probe_fail
                ld (CPC_FAILURE),a
                ld a,#FF
                ld (CPC_PHASE),a
cpc_probe_stop
                di
                ld (CPC_FINAL_SP),sp
                halt
                jr cpc_probe_stop

magic_bytes db "CPR3D",1
root_record
                db #C0,0,0,80,200
                dw 0,0,0,0
                db 9
                ds 11,0
                db #C4,8,20,24,30
                dw #4100,0,0,0
                db 3
                ds 11,0
worker_code
                ld hl,(#4200)
                inc hl
                ld (#4200),hl
                jr worker_code
worker_code_end
io_request db 1,1
                dw #4320
                db 10,0
                dw #4340,64,0,0,0
io_path db "/DATA.BIN",0
