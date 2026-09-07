; Native config/UI adapters. Policy/renderer are shared; only the fixed memory,
; bank, bounded M4 read and context boundary are CPC-specific.
                include "../lib/cpc/native_modules_layout.inc"
UI_RES equ CPC_UI_REQUEST+4
DATA_MODTOP equ CPC_MODULE_BASE
MODULE_LOAD_MAX equ APP_LOAD_MAX
MODULE_READ equ cpc_module_read
                macro MODULE_MAP_PAGE
                ld a,CPC_SYSTEM_PAGE
                mend
                macro UI_SELECT_MODULE
                ld hl,gbui_modname            ; alternate modules rejected at entry
                mend
                include "core/data_module.asm"
                include "core/ui_module.asm"

cpc_module_read
                call fs_load_sys
                ret nc
                ld hl,(fs_ent_size)
                ld de,CPC_MODULE_CODE_END-CPC_MODULE_BASE
                or a
                sbc hl,de
                jr nz,cpc_module_bad
                scf
                ret
cpc_module_bad
                or a
                ret

; Root context only. Preserve IFF, scheduler lock, clip and caller mapping;
; IRQ time/input can progress while modal but no worker or app callback may run
; from the swapped-out page. Every error returns a deterministic cancel.
cpc_ui
                push af
                ld a,(CPC_UI_REQUEST)
                cp 1
                jr z,cpc_ui_cancel_ff
                cp 6
                jr z,cpc_ui_cancel_ff
                xor a
                jr cpc_ui_cancel_set
cpc_ui_cancel_ff
                ld a,#FF
cpc_ui_cancel_set
                ld (UI_RES),a
                ld c,a
                ld a,3                       ; context/selector error
                ld (CPC_UI_STATUS),a
                pop af
                or a
                ret nz
                ld a,(SCHED_CURRENT)
                or a
                ret nz
                ld a,(UI_MODAL)
                or a
                ret nz
                push ix
                ld a,i
                push af
                di
                ld a,(SCHED_LOCK)
                push af
                ld a,1
                ld (SCHED_LOCK),a
                ld hl,(WM_CLIP_X)
                push hl
                ld hl,(WM_CLIP_W)
                push hl
                call clip_set_full
                ld a,1                       ; loader failure until renderer runs
                ld (CPC_UI_STATUS),a
                ld hl,(CPC_UI_CALLS)
                inc hl
                ld (CPC_UI_CALLS),hl
                xor a
                call k_ui
                di
                pop hl
                ld (WM_CLIP_W),hl
                pop hl
                ld (WM_CLIP_X),hl
                pop af
                ld (SCHED_LOCK),a
                pop af
                pop ix
                ret po
                ei
                ret

; Config boot/reload uses the same parser/default-output wrapper as MSX.
; Missing/failed/oversized text falls back to length zero; a missing executable
; fails instead of pretending that uninitialized outputs are valid defaults.
cpc_config
                ld a,(BANK_CUR)
                push af
                ld a,CPC_DATA_PAGE
                call foundation_bank_set
                ld hl,0
                ld (CPC_CFG_OUTPUT),hl
                ld (CPC_CFG_OFFSET),hl
                ld hl,cpc_cfg_request
                ld de,CPC_APP_IO_REQUEST
                ld bc,16
                ldir
                ld hl,cpc_cfg_path
                ld de,CPC_APP_IO_PATH
                ld bc,14
                ldir
cpc_cfg_next
                ld hl,(CPC_CFG_OFFSET)
                ld (CPC_APP_IO_REQUEST+10),hl
                ld de,CPC_CFG_TEXT_END-CPC_CFG_TEXT
                or a
                sbc hl,de
                jr nz,cpc_cfg_read
                ld a,1                       ; exact capacity EOF probe
                ld (CPC_APP_IO_REQUEST+8),a
cpc_cfg_read
                ld hl,CPC_APP_IO_REQUEST
                ld bc,16
                call storage_gate
                cp 2
                jr nc,cpc_cfg_error
                ld (CPC_CFG_STATUS),a
                ld hl,(CPC_CFG_OFFSET)
                add hl,de
                ld bc,CPC_CFG_TEXT_END-CPC_CFG_TEXT+1
                or a
                sbc hl,bc
                jr nc,cpc_cfg_oversize
                ld a,d
                or e
                jr z,cpc_cfg_done
                ld b,d
                ld c,e
                ld hl,(CPC_CFG_OFFSET)
                add hl,de
                ld (CPC_CFG_OFFSET),hl
                ld hl,(CPC_CFG_OUTPUT)
                ld de,CPC_CFG_TEXT
                add hl,de
                ex de,hl
                ld hl,CPC_APP_IO_BUFFER
                ldir
                ld hl,(CPC_CFG_OFFSET)
                ld (CPC_CFG_OUTPUT),hl
                ld a,(CPC_CFG_STATUS)
                or a
                jr z,cpc_cfg_next
cpc_cfg_done
                xor a
                jr cpc_cfg_parsing
cpc_cfg_oversize
                ld a,2
                jr cpc_cfg_empty
cpc_cfg_error
                add a,16                     ; preserve hardware error diagnosis
cpc_cfg_empty
                ld hl,0
                ld (CPC_CFG_OUTPUT),hl
cpc_cfg_parsing
                ld (CPC_CFG_STATUS),a
                ld hl,512
                ld (CPC_CFG_OUTPUT+24),hl
                ld hl,cpc_cfg_module
                call run_data_module
                jr c,cpc_cfg_module_done
                ld a,3                       ; parser executable absent/invalid
                ld (CPC_CFG_STATUS),a
                or a
cpc_cfg_module_done
                ex af,af'
                pop af
                call foundation_bank_set
                ex af,af'
                ret
cpc_cfg_request db 1,1
                dw CPC_APP_IO_PATH
                db 14,0
                dw CPC_APP_IO_BUFFER,128,0,0,0
cpc_cfg_path db "/GEOBENCH.CFG",0
cpc_cfg_module db "GBCFG   MOD"
