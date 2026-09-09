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
cpc_runtime_f6 equ #1D6F
cpc_runtime_f7 equ #1D70
cpc_runtime_f2 equ #1D71
cpc_runtime_worker_calls equ #1D72 ; private diagnostic observation, no scheduling policy
cpc_runtime_draw_calls equ #1D74   ; backend transactions, including transient redraws
                assert cpc_runtime_draw_calls+2<=CPC_ADAPTER_STATE_END,"runtime state overflow"
                assert cpc_runtime_draw_calls+2<=CPC_PICK_PATH,"runtime/picker state overlap"
cpc_runtime_start
                di
                ld sp,CPC_MAIN_TOP
                ld hl,CPC_MAIN_TOP
                ld (BOOT_SP),hl
                ld hl,0
                ld (CPC_CLIPBOARD_BASE),hl
                ld a,l
                ld (CPC_SCRAP_TYPE),a
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
                call cpc_fs_load_module
                jp nc,cpc_runtime_failed
                call cpc_config
                jp nc,cpc_runtime_failed
                call cpc_visual_apply
                call cpc_desktop_load
                jp nc,cpc_runtime_failed
                ifdef CPC_NATIVE_DESKTOP
                xor a
                ld (CPC_DESKTOP_STATUS),a
                call cpc_bar_payload         ; actual Desktop CRT, initialization and binding
                ld a,(CPC_DESKTOP_STATUS)
                cp 1
                jp nz,cpc_runtime_failed
                else
                ld hl,cpc_bar_data
                ld de,cpc_bar_data+1
                ld bc,cpc_bar_data_end-cpc_bar_data-1
                ld (hl),0
                ldir                           ; explicit native root BSS initialization
                call cpc_bar_payload          ; initialize root-owned bar state
                call cpc_bar_payload+12       ; actual Desktop Desk registration
                ld hl,cpc_root_bar
                ld (BAR_HANDLER),hl
                endif
                ld a,10
                ld (poll_byte),a
                ld hl,40
                ld (pointer_x),hl
                ld a,30
                ld (poll_line),a
                ld (pointer_y),a
                call clip_set_full
                call wm_repaint_all
                ifndef CPC_NATIVE_DESKTOP
                call cpc_runtime_launch
                endif
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
                call cpc_bar_payload+15       ; same gb_doc event/popup/activation path
                call #8045                   ; GB_GETKEY, root launcher only
                or a
                ret z
                ld (cpc_runtime_key),a
                cp 'r'
                jp z,cpc_runtime_config
                cp 'a'
                jp z,cpc_runtime_assets_demo
                cp 'v'
                jp z,cpc_runtime_cursor_phase
                cp 'p'
                jp z,cpc_bar_payload+21
                cp 'u'
                jp z,cpc_bar_payload+24
                cp 'i'
                jp z,cpc_bar_payload+27
                cp 'n'
                jp z,cpc_bar_payload+30
                cp 'o'
                jp z,cpc_bar_payload+36
                cp 'd'
                jp z,cpc_bar_payload+39
                cp 'w'
                jp z,cpc_bar_payload+42
                cp 'e'
                jp z,cpc_bar_payload+45
                cp 'l'
                jp z,cpc_bar_payload+48       ; actual File Manager VIEW=LIST binding
                cp 'b'
                jp z,cpc_bar_payload+51       ; VIEW=DEFAULT (icons)
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
cpc_runtime_config
                push ix
                ld a,i
                push af
                di
                ld a,(SCHED_LOCK)
                push af
                ld a,1
                ld (SCHED_LOCK),a
                call cpc_config
                jr nc,cpc_runtime_config_done
                call cpc_visual_apply
                ; Explicit global font/theme change invalidates all surfaces;
                ; ordinary focus, damage and timer repaints remain clipped.
                ld a,(CPC_VISUAL_DIRTY)
                or a
                call nz,wm_repaint_all
cpc_runtime_config_done
                ld hl,(CPC_CFG_CALLS)
                inc hl
                ld (CPC_CFG_CALLS),hl
                pop af
                ld (SCHED_LOCK),a
                pop af
                pop ix
                ret po
                ei
                ret
cpc_runtime_assets_demo
                ld a,(CPC_ICON_DEMO)
                xor 1
                ld (CPC_ICON_DEMO),a
                jp wm_repaint_all
cpc_runtime_cursor_phase
                call pointer_hide
                ld a,(pointer_x)
                ld b,a
                inc a
                and 3
                ld c,a
                ld a,b
                and #FC
                or c
                ld (pointer_x),a
                jp pointer_show
cpc_runtime_line db 1,1
                dw 16,40,47,43
                db 3,0,0,0,0,0
cpc_root_bar
                call cpc_pointer_service   ; same pre-collector boundary as Desktop
                ld hl,(cpc_runtime_turns)
                inc hl
                ld (cpc_runtime_turns),hl
                call cpc_timer_collect        ; same order as the real Desktop bar hook
                ; A fully covered timer component is dropped without repaint,
                ; so its narrow clip is still installed. The root bar must not
                ; cache a menu/time update that was clipped away.
                call clip_set_full
                call cpc_bar_payload+3        ; existing Desktop delta-refresh policy
                call cpc_runtime_storage
                call cpc_runtime_fsprobe
                call cpc_runtime_menuprobe
                call cpc_runtime_calculator
                call cpc_runtime_clock
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

; F6 opens the universal menu client; no fake Desk/accessory service.
cpc_runtime_menuprobe
                ld a,(CPC_KEYS)
                and #10
                ld b,a
                ld a,(cpc_runtime_f6)
                cp b
                ld a,b
                ld (cpc_runtime_f6),a
                ret z
                or a
                ret nz
                ld hl,cpc_runtime_menuapp
                jp k_wm_open

; F7 uses the SAME Desktop identity-first activation/normal-launch policy.
; The root loop has mapped C0; the shared code's send record is a C stack local.
cpc_runtime_calculator
                ld a,(CPC_KEYS+1)
                and #04                       ; CPC F7: matrix row 1, bit 2
                ld b,a
                ld a,(cpc_runtime_f7)
                cp b
                ld a,b
                ld (cpc_runtime_f7),a
                ret z
                or a
                ret nz
                jp cpc_bar_payload+6

; F2 activates the universal Clock through the same Desktop accessory policy.
; 1984 reserves host F8 for its monitor; F2 reaches the CPC keyboard normally.
cpc_runtime_clock
                ld a,(CPC_KEYS+1)
                and #40                       ; CPC F2: matrix row 1, bit 6
                ld b,a
                ld a,(cpc_runtime_f2)
                cp b
                ld a,b
                ld (cpc_runtime_f2),a
                ret z
                or a
                ret nz
                jp cpc_bar_payload+9

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
                ld bc,0
                ld de,#50C8
                call k_backdrop
                ld a,(CPC_ICON_DEMO)
                or a
                call nz,cpc_icon_gallery
                ; Content-only exposure must not invalidate the top bar.
                ld a,(WM_CLIP_Y)
                or a
                ret nz
                jp cpc_bar_payload+33        ; clipped repair must not publish full-bar cache
cpc_root_desc
                db 0,0,CPC_COLUMNS,CPC_LINES
                dw cpc_root_idle,cpc_root_paint,cpc_root_event,0
cpc_root_event
                jp cpc_bar_payload+18
; Native trusted root component; reuse the exact M4 application reader. Its
; load envelope stops before the root snapshot. Reject any length other than
; the budgeted/padded module BEFORE initialization or execution.
cpc_desktop_load
                ld hl,cpc_desktop_name
                ld de,fs_req_name
                ld bc,11
                ldir
                ld hl,CPC_APP_BASE
                ld (fs_load_dst),hl
                ld hl,APP_LOAD_MAX
                ld (fs_load_max),hl
                call fs_load_sys
                ret nc
                ld hl,(fs_ent_size)
                ld de,cpc_bar_end-cpc_bar_payload
                or a
                sbc hl,de
                jr nz,cpc_desktop_invalid
                scf
                ret
cpc_desktop_invalid
                or a
                ret
cpc_desktop_name db "ROOTUI  BIN"
cpc_runtime_app db "ABIPROBEAPP"
cpc_runtime_fsapp db "FSPROBE APP"
cpc_runtime_menuapp db "MENUPRBEAPP"
                ifdef CPC_NATIVE_DESKTOP
                include "cpc_desktop_boot.inc"
                endif
                assert cpc_runtime_f7+1<CPC_ADAPTER_STATE_END,"launcher state overflow"
