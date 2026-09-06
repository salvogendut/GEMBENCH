; Native leaves and capability view for the unified, experimental APP launcher.
; FS contexts use caller-owned GB_PARAMS; the old native SDK C3D0/C400
; mailboxes are pixels on CPC. The legacy GB_FSCTX slot remains unavailable.
CPC_RUNTIME_CAPS_LOW equ #0F8B ; add GB_CAP_SHELL (#0008), keep other services gated
CPC_RUNTIME_CAPS_HIGH equ #009F
cpc_unavailable
                ld de,0
                ld a,1
                or a
                ret
cpc_sysinfo
                push ix
                call page_count_free
                ld (CPC_SYSINFO_BASE+14),a
                pop ix
                ld de,CPC_SYSINFO_BASE
                ret
cpc_sysinfo_template
                db 48,6,1,0,2,1
                dw CPC_WIDTH,CPC_LINES
                db 2,4,32,CPC_POOL_PAGES,0,CPC_WINDOW_MAX
                dw CPC_RUNTIME_CAPS_LOW,0
                db CPC_OWNER_MAX,1,CPC_WINDOW_MAX,0,8,4,1,0
                db 4,0,2,1                   ; four contexts, 512 bytes, API v1
                dw CPC_RUNTIME_CAPS_HIGH
                db CPC_COLUMNS,CPC_LINES,4,4
                dw CPC_APP_BASE,CPC_APP_LIMIT,CPC_KERNEL_BASE
                db 2,1,3,0
                assert $-cpc_sysinfo_template==48,"sysinfo size"

; The shared package validator handles format/CRC/length. This receiver accepts
; only universal v4 (no old native MSX/CPC binaries) with live required masks.
cpc_runtime_admission
                ld a,(APP_BASE)
                cp #C3
                jr nz,cpc_runtime_reject
                ld hl,(APP_BASE+3)
                ld de,#4247
                or a
                sbc hl,de
                jr nz,cpc_runtime_reject
                ld hl,(APP_BASE+5)
                ld de,#5041
                or a
                sbc hl,de
                jr nz,cpc_runtime_reject
                ld a,(APP_BASE+7)
                cp 4
                jr nz,cpc_runtime_reject
                ld a,(ix+9)                  ; ABI 2.0 mailboxes alias CPC pixels
                cp 1
                jr nz,cpc_runtime_reject
                ld a,CPC_RUNTIME_CAPS_LOW & 255
                cpl
                and (ix+12)
                jr nz,cpc_runtime_reject
                ld a,CPC_RUNTIME_CAPS_LOW >> 8
                cpl
                and (ix+13)
                jr nz,cpc_runtime_reject
                ld a,CPC_RUNTIME_CAPS_HIGH
                cpl
                and (ix+14)
                jr nz,cpc_runtime_reject
                ld a,(ix+15)
                or a
                jr nz,cpc_runtime_reject
                scf
                ret
cpc_runtime_reject
                or a
                ret
cpc_close_focus
                ld a,(WM_FOCUS)
                or a                         ; kernel launcher's immortal surface
                ret z
                ld c,a
                jp app_window_close_slot
cpc_on_bar
                ld (BAR_HANDLER),hl
                ret
cpc_pointer_pixel
                ld hl,(pointer_x)
                ret
cpc_time
                ld hl,(CPC_HW_SECONDS)
                ld b,0
cpc_time_hours
                ld de,3600
                or a
                sbc hl,de
                jr c,cpc_time_hour_remainder
                inc b
                jr cpc_time_hours
cpc_time_hour_remainder
                add hl,de
                ld a,b
                ld (#1240),a
                ld b,0
cpc_time_minutes
                ld de,60
                or a
                sbc hl,de
                jr c,cpc_time_remainder
                inc b
                jr cpc_time_minutes
cpc_time_remainder
                add hl,de
                ld a,l
                ld (#1242),a
                ld a,b
                ld (#1241),a
                ld a,1
                ld (#1243),a
                ret

; Frozen GB_TEXT copies before mapping the font. Keep the active compositor
; clip and let the same CPC drawing leaf exclude only intersecting pointer bits.
gb_text_draw
                push bc
                push de
                ld de,#1450
                call gtd_copy
                ld hl,#1450
                ex de,hl
                or a
                sbc hl,de
                ld a,l
                ld (up_request+8),a
                pop de
                pop bc
                or a
                ret z
                ld hl,#1450
                jp cpc_draw_text
k_fill
                ld (cpc_fill_pen),a
                ld a,b
                ld (fb_x),a
                ld (rect_x),a
                ld a,c
                ld (fb_y),a
                ld (rect_y),a
                ld a,d
                ld (fb_w),a
                ld (rect_w),a
                ld a,e
                ld (fb_h),a
                ld (rect_h),a
                ld a,(cpc_fill_pen)
                call pen_to_byte
                ld (fb_val),a
                call cpc_damage_begin
                call fill_block
                jp cpc_damage_end

; Publish the SAME focus-owned menu snapshot as MSX, not merely its pointer.
; This fixed low-RAM view is read by the root Desktop bar, never by APPs.
MENU_DEF equ #1310
WM_FR_MENU equ 11
cpc_menu_clear equ menu_clear
cpc_menu_install equ menu_install
cpc_set_menu equ k_menu
                include "core/menu_state.asm"
                assert MENU_DEF+37<=WM_CLIP_X,"menu/clip state overlap"

; CPC Mode 1 bytes already ARE canonical 2-bpp semantic pixels. The inherited
; save-under API requires an in-bounds rectangle and an app-primary buffer.
; Callers bracket their own pointer visibility, as on MSX (popup contract).
cpc_save_rect
                xor a
                jr cpc_rect_transfer
cpc_restore_rect
                ld a,1
cpc_rect_transfer
                ld (cpc_rect_direction),a
                ld a,(SCHED_CURRENT)
                or a
                ret nz
                ld a,b
                ld (block_x),a
                ld a,c
                ld (block_y),a
                ld a,d
                or a
                ret z
                ld (block_w),a
                add a,b
                ret c
                cp CPC_COLUMNS+1
                ret nc
                ld a,e
                or a
                ret z
                ld (block_h),a
                add a,c
                ret c
                cp CPC_LINES+1
                ret nc
                push hl
                ld b,e
                ld e,d
                ld d,0
                ld hl,0
cpc_rect_size
                add hl,de
                djnz cpc_rect_size
                ld b,h
                ld c,l
                pop hl
                call validate_span
                ret nc
                ld (block_buffer),hl
                ld a,(cpc_rect_direction)
                jp block_copy
cpc_rect_direction equ #3358
cpc_fill_pen equ #3359
                assert MW_RECT==#1448,"frozen universal managed rectangle"
                assert CORE_LEGACY_BUSY+8<=MW_RECT,"page flags/SDK rectangle overlap"
                assert MW_RECT+4<=#1450,"SDK rectangle/text scratch overlap"
                assert #1450+49<=fs_ent_name,"text/loader scratch overlap"
                assert cpc_fill_pen+1<CPC_REG_END,"runtime service state overflow"
