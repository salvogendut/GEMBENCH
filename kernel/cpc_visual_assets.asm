; Configured font/palette provider for the private production runtime. No new
; Desktop, parser or font renderer. Native GB_RELOAD stays gated until the
; other asset families are implemented. Caller has serialized root context.
                include "../lib/cpc/visual_assets_layout.inc"
KCFG_FONTNAME equ CPC_CFG_OUTPUT+13
DATA_FONT equ CPC_FONT_BASE
FONT_LOAD_MAX equ CPC_FONT_LIMIT-CPC_FONT_BASE
FONT_READ equ cpc_asset_read
FONT_APPLY equ cpc_font_publish
                macro FONT_ENTER
                ld a,CPC_SYSTEM_PAGE
                call foundation_bank_set
                mend
                macro FONT_LEAVE
                ; Outer transaction restores mapping, lock and interrupt state.
                mend
                include "core/font_asset.asm"

; Boot and explicit root reload only; no callback or worker can observe a
; half-published font. Preserve the caller's bank, IX, IFF and scheduler lock.
cpc_visual_apply
                push ix
                ld a,i
                push af
                di
                ld a,(SCHED_LOCK)
                push af
                ld a,1
                ld (SCHED_LOCK),a
                ld a,(BANK_CUR)
                push af
                ld hl,(fs_load_dst)
                push hl
                ld hl,(fs_load_max)
                push hl
                xor a
                ld (CPC_FONT_ATTEMPT),a
                ld (CPC_VISUAL_DIRTY),a
                ld (CPC_ASSET_KIND),a
                call font_init
                call cpc_other_assets
                call cpc_config_palette
                ld a,(CPC_CFG_OUTPUT+62)
                ld hl,KCFG_FRAMEPEN
                cp (hl)
                jr z,cpc_visual_frame_same
                ld hl,CPC_VISUAL_DIRTY
                ld (hl),1
cpc_visual_frame_same
                ld (KCFG_FRAMEPEN),a          ; same parser's contrast choice
                ld hl,(CPC_VISUAL_CALLS)
                inc hl
                ld (CPC_VISUAL_CALLS),hl
                pop hl
                ld (fs_load_max),hl
                pop hl
                ld (fs_load_dst),hl
                pop af
                call foundation_bank_set
                pop af
                ld (SCHED_LOCK),a
                pop af
                pop ix
                ret po
                ei
                ret

; Use the qualified executable reader's owned F6 scratch and strict /GBENCH
; path handling. Its 0x3F00 cap is an I/O limit, NOT the font admission limit.
; Nothing reaches F7 unless the complete candidate is a valid <=1024-byte FNT.
cpc_font_read
                ld hl,(fs_ent_size)
                ld de,CPC_FONT_LIMIT-CPC_FONT_BASE+1
                or a
                sbc hl,de
                ret nc                       ; too large for F7
                ld hl,CPC_FONT_BASE
                ld de,cpc_font_header
                ld b,10
cpc_font_check_header
                ld a,(de)
                cp (hl)
                jr nz,cpc_font_invalid
                inc hl
                inc de
                djnz cpc_font_check_header
                ; Current Desktop/dialog geometry requires 6x8 cells and all
                ; 100 ASCII/UI glyphs. Admit artwork variants, not a new ABI.
                ld hl,(fs_ent_size)
                ld de,816
                or a
                sbc hl,de
                jr nz,cpc_font_invalid
                scf
                ret
cpc_font_invalid
                or a
                ret
cpc_font_header db "GBFN",1,32,131,6,8,1

cpc_font_publish
                jr nc,cpc_font_embedded
                ld a,(CPC_FONT_ATTEMPT)
                dec a
                ld (CPC_FONT_STATUS),a
                ld hl,CPC_FONT_BASE
                ld (CPC_FONT_SOURCE),hl
                ld (CPC_FONT_DEST),hl
                ld hl,816
                ld (CPC_FONT_LEFT),hl
                ld (CPC_FONT_BYTES),hl
cpc_font_copy
                ld a,CPC_SYSTEM_PAGE
                call foundation_bank_set
                ld hl,(CPC_FONT_LEFT)
                ld bc,128
                ld a,h
                or a
                jr nz,cpc_font_chunk
                ld a,l
                cp 128
                jr nc,cpc_font_chunk
                ld c,l
cpc_font_chunk
                push bc
                or a
                sbc hl,bc
                ld (CPC_FONT_LEFT),hl
                ld hl,(CPC_FONT_SOURCE)
                ld de,CPC_DRAW_STAGING_BASE
                ldir
                ld (CPC_FONT_SOURCE),hl
                ld a,CPC_DATA_PAGE
                call foundation_bank_set
                pop bc
                ld hl,CPC_DRAW_STAGING_BASE
                ld de,(CPC_FONT_DEST)
                call cpc_font_commit_chunk
                ld (CPC_FONT_DEST),de
                ld hl,(CPC_FONT_LEFT)
                ld a,h
                or l
                jr nz,cpc_font_copy
                jr cpc_font_geometry
cpc_font_embedded
                ld a,2
                ld (CPC_FONT_STATUS),a
                ld a,CPC_DATA_PAGE
                call foundation_bank_set
                ld hl,cpc_font_payload
                ld de,CPC_FONT_BASE
                ld bc,cpc_font_end-cpc_font_payload
                ld (CPC_FONT_BYTES),bc
                call cpc_font_commit_chunk
cpc_font_geometry
                ld hl,CPC_FONT_BASE
                jp font_apply_header

; Both pointers are now visible. Detect a real glyph change before publishing
; so a same-config R reload does not invalidate all windows gratuitously.
cpc_font_commit_chunk
                push hl
                push de
                push bc
cpc_font_compare
                ld a,(de)
                cp (hl)
                jr nz,cpc_font_changed
                inc hl
                inc de
                dec bc
                ld a,b
                or c
                jr nz,cpc_font_compare
                jr cpc_font_commit
cpc_font_changed
                ld a,1
                ld (CPC_VISUAL_DIRTY),a
cpc_font_commit
                pop bc
                pop de
                pop hl
                ldir
                ret

; Canonical INKS values remain CPC firmware colour numbers (as on MSX).
; Hardware-only boundary: select pen, then translate to a Gate Array command.
cpc_config_palette
                ld hl,CPC_CFG_OUTPUT+44
                ld d,0
cpc_config_ink
                ld a,(hl)
                inc hl
                push hl
                cp 27
                jr c,cpc_config_ink_valid
                xor a                       ; defensive, parser already clamps
cpc_config_ink_valid
                ld l,a
                ld h,0
                ld bc,cpc_firmware_inks
                add hl,bc
                ld bc,#7F00
                out (c),d
                ld a,(hl)
                out (c),a
                pop hl
                inc d
                ld a,d
                cp 4
                jr c,cpc_config_ink
                cp 17
                ret z
                ld d,16                     ; fifth entry is the border
                jr cpc_config_ink
cpc_firmware_inks db #54,#44,#55,#5C,#58,#5D,#4C,#45,#4D
                  db #56,#46,#57,#5E,#40,#5F,#4E,#47,#4F
                  db #52,#42,#53,#5A,#59,#5B,#4A,#43,#4B
