; Minimal kernel-owned launch surface, not a replacement Desktop application.
; Bootstrap/register through the same ownership/window/loader policy as MSX.
cpc_runtime_status equ #1D60
cpc_runtime_launches equ #1D61
cpc_runtime_f3 equ #1D62
cpc_runtime_turns equ #1D64
cpc_runtime_f4 equ #1D66
cpc_runtime_fs_calls equ #1D67
cpc_runtime_fs_status equ #1D68
cpc_runtime_free equ #1D69
cpc_runtime_key equ #1D6B
cpc_runtime_surface_calls equ #1D6C
cpc_runtime_surface_status equ #1D6D
cpc_runtime_f5 equ #1D6E
cpc_runtime_start
                di
                ld sp,CPC_MAIN_TOP
                ld hl,CPC_MAIN_TOP
                ld (BOOT_SP),hl
                call cpc_memory_admit
                jp nc,cpc_runtime_failed
                ld hl,300
                ld (CPC_HW_DIVIDER),hl
                call sched_init_impl
                xor a
                ld (SCHED_CURRENT),a
                ld a,1
                ld (SCHED_RUNNABLE),a
                ld (KCFG_FRAMEPEN),a
                ld hl,cpc_memory_pages
                ld de,CORE_PAGE_NATIVE
                ld bc,CPC_POOL_PAGES
                ldir
                ld a,CPC_POOL_PAGES
                ld (CORE_PAGE_TOTAL),a
                call owner_alloc
                ld (CORE_PENDING_OWNER),de
                ld b,1
                call page_alloc_owned
                call app_bind_code_page
                ld a,#C0
                call foundation_bank_set
                ld hl,cpc_root_desc
                call wm_register
                call app_mark_root_current
                ld a,#FF
                ld (CORE_PREVIOUS_FOCUS),a
                ld hl,cpc_sysinfo_template
                ld de,CPC_SYSINFO_BASE
                ld bc,48
                ldir
                ld a,CPC_DATA_PAGE
                call foundation_bank_set
                ld hl,cpc_font_payload
                ld de,#4000
                ld bc,cpc_font_end-cpc_font_payload
                ldir
                ld hl,#4000
                call font_apply_header
                ld a,#C0
                call foundation_bank_set
                call cpc_fs_load_module
                jp nc,cpc_runtime_failed
                ; Palette is hardware-only: blue, white, black, bright red.
                ld hl,cpc_runtime_palette
                ld d,0
cpc_runtime_ink
                ld bc,#7F00
                out (c),d
                ld a,(hl)
                out (c),a
                inc hl
                inc d
                ld a,d
                cp 4
                jr c,cpc_runtime_ink
                ld a,16
                out (c),a
                ld a,#44
                out (c),a
                ld hl,cpc_root_bar
                ld (BAR_HANDLER),hl
                ld a,10
                ld (poll_byte),a
                ld hl,40
                ld (pointer_x),hl
                ld a,30
                ld (poll_line),a
                ld (pointer_y),a
                call clip_set_full
                call wm_repaint_all
                call cpc_runtime_launch
                ld a,1
                ld (cpc_runtime_status),a
                jp wm_loop
cpc_runtime_launch
                ld hl,cpc_runtime_app
                call k_wm_open
                ld hl,cpc_runtime_launches
                inc (hl)
                ret
cpc_runtime_failed
                ld a,#FF
                ld (cpc_runtime_status),a
                di
                halt
                jr cpc_runtime_failed
cpc_root_idle
                call #8045                   ; GB_GETKEY, root launcher only
                or a
                ret z
                ld (cpc_runtime_key),a
                cp 's'
                ret nz
                ; Small public-ABI exercise on the empty launch surface. Keep
                ; the same pixels afterwards; S is not a Desktop service.
                call #8024                   ; GB_CURHIDE
                ld bc,#0428
                ld de,#0804
                ld hl,#6100
                call #8036                   ; 32 canonical bytes in root's page
                ld bc,#0428
                ld de,#0804
                ld a,1
                call #8033                   ; GB_FILL
                ld hl,cpc_runtime_line
                ld de,#6200
                ld bc,16
                ldir
                ld hl,#6200
                ld bc,16
                call #80D5                   ; GB_PARAMS, caller-owned line
                ld (cpc_runtime_surface_status),a
                ld bc,#0428
                ld de,#0804
                ld hl,#6100
                call #8039                   ; GB_RESTORERECT
                call #801B
                ld hl,cpc_runtime_surface_calls
                inc (hl)
                ret
cpc_runtime_line db 1,1
                dw 16,40,47,43
                db 3,0,0,0,0,0
cpc_root_bar
                ld hl,(cpc_runtime_turns)
                inc hl
                ld (cpc_runtime_turns),hl
                call cpc_time
                call cpc_runtime_storage
                call cpc_runtime_fsprobe
                ; F3 opens another copy using the real M4 launch transaction.
                ld a,(CPC_KEYS)
                and #20
                ld b,a
                ld a,(cpc_runtime_f3)
                cp b
                ld a,b
                ld (cpc_runtime_f3),a
                ret z
                or a
                ret nz
                jp cpc_runtime_launch

; F5 launches the compile-once FS diagnostic, which writes only UFSTEST.
cpc_runtime_fsprobe
                ld a,(CPC_KEYS+1)
                and #10
                ld b,a
                ld a,(cpc_runtime_f5)
                cp b
                ld a,b
                ld (cpc_runtime_f5),a
                ret z
                or a
                ret nz
                ld hl,cpc_runtime_fsapp
                jp k_wm_open

; F4 exercises the composed private FS service while windows remain live.
; This is root-owned, serialized, read-only M4 work, not a public SDK mailbox.
cpc_runtime_storage
                ld a,(CPC_KEYS+2)
                and #10
                ld b,a
                ld a,(cpc_runtime_f4)
                cp b
                ld a,b
                ld (cpc_runtime_f4),a
                ret z
                or a
                ret nz
                xor a
                ld (CPC_FS_REQUEST+6),a
                call cpc_fsctx_call
                or a
                jr nz,cpc_runtime_fs_done
                push de
                ld a,10
                call cpc_fsctx_call
                ld (cpc_runtime_fs_status),a
                ld hl,(CPC_FS_REQUEST+10)
                ld (cpc_runtime_free),hl
                pop de
                ld (CPC_FS_REQUEST+2),de
                ld a,1
                call cpc_fsctx_call
                or a
                jr nz,cpc_runtime_fs_done
                ld a,(cpc_runtime_fs_status)
cpc_runtime_fs_done
                ld (cpc_runtime_fs_status),a
                ld hl,cpc_runtime_fs_calls
                inc (hl)
                ret
cpc_root_paint
                xor a
                ld bc,0
                ld de,#50C8
                call k_fill
                ld a,1
                ld bc,0
                ld de,#5008
                call k_fill
                ld bc,#0100
                ld de,#0201
                ld hl,cpc_runtime_label
                jp gb_text_draw
cpc_root_desc
                db 0,0,CPC_COLUMNS,CPC_LINES
                dw cpc_root_idle,cpc_root_paint,cpc_root_idle,0
cpc_runtime_label db "CPC F3: APP F4: M4 F5: FS S: save",0
cpc_runtime_app db "ABIPROBEAPP"
cpc_runtime_fsapp db "FSPROBE APP"
cpc_runtime_palette db #44,#4B,#54,#4C
                assert cpc_runtime_f5+1<CPC_ADAPTER_STATE_END,"launcher state overflow"
