; 3D-T. Asset policy and icon geometry are shared with MSX; publication and
; Mode-1 raster operations own CPC addresses. All loads are root-serialized.
KCFG_ICONNAME equ CPC_CFG_OUTPUT+2
ICON_LOAD_MAX equ CPC_ICON_LIMIT-DATA_ICONS
ICON_LOAD_DST equ CPC_APP_BASE
                macro ICON_ENTER
                ld a,CPC_SYSTEM_PAGE
                call foundation_bank_set
                mend
                macro ICON_LEAVE
                mend
                macro ICON_APPLY
                call cpc_icon_publish
                mend
                include "core/icon_asset.asm"
                include "core/icon_full_geom.asm"
                include "core/icon_half_geom.asm"

; The same configured/default helper invokes this typed, bounded reader.
; Rejected candidates stay in F6. It never overwrites a live F7 asset.
cpc_asset_read
                ld hl,CPC_FONT_ATTEMPT
                inc (hl)
                ld a,CPC_SYSTEM_PAGE
                call foundation_bank_set
                ld hl,CPC_APP_BASE
                ld (fs_load_dst),hl
                ld hl,APP_LOAD_MAX
                ld (fs_load_max),hl
                call fs_load_sys
                ret nc
                ld a,(CPC_ASSET_KIND)
                or a
                jp z,cpc_font_read
                dec a
                jp z,cpc_icon_validate
                dec a
                jr z,cpc_cursor_validate
                dec a
                jp nz,cpc_title_validate
                ld de,64
                jr cpc_asset_exact
cpc_cursor_validate
                ld de,256
                call cpc_asset_exact
                ret nc
                ld hl,#4000
                ld b,128
cpc_cursor_pair
                ld a,(hl)
                ld c,a
                rrca
                rrca
                rrca
                rrca
                xor c
                and #0F                     ; whole Mode-1 pixels, not half masks
                jp nz,cpc_icon_invalid
                inc hl
                ld a,(hl)
                and c
                jp nz,cpc_icon_invalid
                inc hl
                djnz cpc_cursor_pair
                scf
                ret
cpc_asset_exact
                ld hl,(fs_ent_size)
                or a
                sbc hl,de
                jp nz,cpc_icon_invalid
                scf
                ret

; Canonical GBIS v2, positional 21-slot desktop catalogue or a superset.
; Require nonempty, contiguous directory payloads wholly within the file.
; Width/height may vary; no renderer ever sees an unchecked directory entry.
cpc_icon_validate
                ld hl,(fs_ent_size)
                ld de,CPC_ICON_LIMIT-DATA_ICONS+1
                or a
                sbc hl,de
                ret nc
                ld hl,#4000
                ld de,cpc_icon_header
                ld b,5
cpc_icon_magic
                ld a,(de)
                cp (hl)
                jr nz,cpc_icon_invalid
                inc de
                inc hl
                djnz cpc_icon_magic
                ld a,(hl)
                cp 21
                jr c,cpc_icon_invalid
                ld (CPC_ASSET_ENTRIES),a
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                ld de,16
                add hl,de
                ld (CPC_ASSET_EXPECT),hl
                ld de,(fs_ent_size)
                or a
                sbc hl,de
                jr nc,cpc_icon_invalid
                ld hl,#4010
cpc_icon_entry
                ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                push hl
                ld hl,(CPC_ASSET_EXPECT)
                or a
                sbc hl,de
                pop hl
                jr nz,cpc_icon_invalid
                ld a,(hl)
                inc hl
                or a
                jr z,cpc_icon_invalid
                cp CPC_COLUMNS+1
                jr nc,cpc_icon_invalid
                ld c,a
                ld a,(hl)
                inc hl
                cp 2                         ; half-icon height must be nonzero
                jr c,cpc_icon_invalid
                cp CPC_LINES+1
                jr nc,cpc_icon_invalid
                ld (CPC_ASSET_DIR),hl
                ld b,a
                ld e,c
                ld d,0
                ld hl,(CPC_ASSET_EXPECT)
cpc_icon_extent
                add hl,de
                djnz cpc_icon_extent
                ld (CPC_ASSET_EXPECT),hl
                ld de,(fs_ent_size)
                or a
                sbc hl,de
                jr c,cpc_icon_more
                jr nz,cpc_icon_invalid
cpc_icon_more
                ld hl,CPC_ASSET_ENTRIES
                dec (hl)
                ld hl,(CPC_ASSET_DIR)
                jr nz,cpc_icon_entry
                ld hl,(CPC_ASSET_EXPECT)
                ld de,(fs_ent_size)
                or a
                sbc hl,de
                jr nz,cpc_icon_invalid
                scf
                ret
cpc_icon_invalid
                or a
                ret
cpc_icon_header db "GBIS",2

cpc_other_assets
                ld a,1
                ld (CPC_ASSET_KIND),a
                xor a
                ld (CPC_FONT_ATTEMPT),a
                call icon_init
                ; Cursor does not require a desktop repaint. Exclude the old
                ; save-under before changing phases; preserve explicit hiding.
                ld a,(pointer_visible)
                push af
                call pointer_hide
                ld a,2
                ld (CPC_ASSET_KIND),a
                xor a
                ld (CPC_FONT_ATTEMPT),a
                ld hl,CPC_CFG_OUTPUT+33
                ld de,fs_req_name
                call copy11
                ld hl,cpc_default_spr
                call load_or_default
                jr nc,cpc_cursor_fallback
                ld hl,#4000
                ld a,(CPC_FONT_ATTEMPT)
                dec a
                jr cpc_cursor_ready
cpc_cursor_fallback
                ld a,2
                ld hl,cpc_cursor_default
cpc_cursor_ready
                ld (CPC_CURSOR_STATUS),a
                call cpc_cursor_publish
                pop af
                or a
                call nz,pointer_show
                ld a,3
                ld (CPC_ASSET_KIND),a
                xor a
                ld (CPC_FONT_ATTEMPT),a
                ld a,(CPC_BACKDROP_STATUS)
                ld (CPC_ASSET_PREVIOUS),a
                ld a,1
                ld (CPC_BACKDROP_STATUS),a
                ld a,(CPC_CFG_OUTPUT+61)
                or a
                jr nz,cpc_backdrop_state
                ; Single-volume M4 only. Explicit other drive selection is
                ; unavailable; never silently read the wrong drive's tile.
                ld a,(CPC_CFG_OUTPUT+60)
                inc a
                jr nz,cpc_backdrop_state
                ld hl,CPC_CFG_OUTPUT+49
                ld de,fs_req_name
                call copy11
                call cpc_asset_read
                jr nc,cpc_backdrop_state
                ld hl,#4000
                ld de,CPC_BD_TILE
                ld bc,64
                call cpc_font_commit_chunk
                xor a
                ld (CPC_BACKDROP_STATUS),a
cpc_backdrop_state
                ld a,(CPC_ASSET_PREVIOUS)
                ld hl,CPC_BACKDROP_STATUS
                cp (hl)
                ret z
                ld a,1
                ld (CPC_VISUAL_DIRTY),a
                ret
cpc_default_spr db "DEFAULT SPR"

cpc_icon_publish
                jr nc,cpc_icon_missing
                ld a,(CPC_FONT_ATTEMPT)
                dec a
                ld (CPC_ICON_STATUS),a
                ld a,(#4005)
                ld hl,CPC_ICON_COUNT
                cp (hl)
                jr z,cpc_icon_count_same
                ld (hl),a
                ld a,1
                ld (CPC_VISUAL_DIRTY),a
cpc_icon_count_same
                ld hl,(fs_ent_size)
                ld (CPC_ICON_BYTES),hl
                ld (CPC_FONT_LEFT),hl
                ld hl,#4000
                ld (CPC_FONT_SOURCE),hl
                ld hl,DATA_ICONS
                ld (CPC_FONT_DEST),hl
                ; Same staging/chunk comparison primitive as font publication,
                ; without applying a font header to the icon allocation.
cpc_icon_copy
                ld a,CPC_SYSTEM_PAGE
                call foundation_bank_set
                ld hl,(CPC_FONT_LEFT)
                ld bc,128
                ld a,h
                or a
                jr nz,cpc_icon_chunk
                ld a,l
                cp 128
                jr nc,cpc_icon_chunk
                ld c,l
cpc_icon_chunk
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
                jr nz,cpc_icon_copy
                ret
cpc_icon_missing
                ld a,2
                ld (CPC_ICON_STATUS),a
                ld a,(CPC_ICON_COUNT)
                or a
                jr z,cpc_icon_empty
                ld a,1
                ld (CPC_VISUAL_DIRTY),a
cpc_icon_empty
                xor a
                ld (CPC_ICON_COUNT),a
                ld hl,0
                ld (CPC_ICON_BYTES),hl
                ret

; CPC .SPR: two 4-byte x 16-row mask/data phases (0,2), 256 bytes.
; Copy both, deriving 1/3 by independently shifting the Mode-1 nibbles.
cpc_cursor_publish
                ld de,cursor_phases
                ld bc,128
                ldir
                ld de,cursor_phases+256
                ld bc,128
                ldir
                ld hl,cursor_phases
                ld de,cursor_phases+128
                call cpc_cursor_shift
                ld hl,cursor_phases+256
                ld de,cursor_phases+384
cpc_cursor_shift
                ld b,16
cpc_cursor_shift_row
                push bc
                ld b,8
                xor a
                ld (CPC_ASSET_REMAIN+1),a
                ld c,#88                    ; incoming transparent mask pixel
cpc_cursor_shift_byte
                ld a,(hl)
                and #11
                add a,a
                add a,a
                add a,a
                ld (CPC_ASSET_REMAIN),a
                ld a,(hl)
                rrca
                and #77
                or c
                ld (de),a
                inc hl
                inc de
                ; Mask/data have separate carries. Carry of mask byte crosses
                ; the data byte, and vice versa.
                ld a,(CPC_ASSET_REMAIN+1)
                ld c,a
                ld a,(CPC_ASSET_REMAIN)
                ld (CPC_ASSET_REMAIN+1),a
                djnz cpc_cursor_shift_byte
                pop bc
                djnz cpc_cursor_shift_row
                ret

; Native GB_ICON / GB_ICONHALF, with the same shared directory geometry and
; pen-0 transparency only for full root icons. No file-type routing here.
k_icon_half
                ld (gi_slot),a
                ld a,1
                jr cpc_icon_draw
k_icon
                ld (gi_slot),a
                xor a
cpc_icon_draw
                ld (CPC_ICON_HALF),a
                ld a,b
                ld (gi_x),a
                ld a,c
                ld (gi_y),a
                ld a,(gi_slot)
                ld hl,CPC_ICON_COUNT
                cp (hl)
                ret nc
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
                xor a
                ld (bm_keep),a
                ld a,(CPC_ICON_HALF)
                or a
                jr nz,cpc_icon_map
                ld a,(BANK_CUR)
                cp #C0
                jr nz,cpc_icon_map
                ld a,1
                ld (bm_keep),a
cpc_icon_map
                ld a,CPC_DATA_PAGE
                call foundation_bank_set
                ld a,(CPC_ICON_HALF)
                or a
                ld a,(gi_slot)
                jr z,cpc_icon_full
                call icon_geom
                jr cpc_icon_render
cpc_icon_full
                call icon_full_geom
cpc_icon_render
                call blit_bitmap
                jp cpc_icon_draw_end

; Shared native chrome uses the same clipped opaque blitter as icon assets.
; Caller owns the bank/lock; no extra policy or geometry is introduced here.
blit_bitmap
                ld hl,bm_w
                ld de,rect_w
                ld bc,2
                ldir
                ld hl,(bm_x)
                ld (rect_x),hl
                call cpc_damage_begin
                ret nc
                ; Advance into the original bitmap, but iterate ONLY the
                ; clipped rectangle. Tall assets near the bottom must not
                ; wrap the 8-bit row counter and paint the top of the screen.
                ld hl,(bm_src)
                ld a,(bm_w)
                ld e,a
                ld d,0
                ld a,(bm_y)
                ld b,a
                ld a,(rect_y)
                sub b
                jr z,cpc_icon_skip_columns
                ld b,a
cpc_icon_skip_rows
                add hl,de
                djnz cpc_icon_skip_rows
cpc_icon_skip_columns
                ld a,(bm_x)
                ld b,a
                ld a,(rect_x)
                sub b
                ld e,a
                add hl,de
                push hl
                call cpc_draw_sample_begin
                ei
                ld a,(rect_h)
                ld (draw_rows),a
                ld a,(rect_y)
                ld (draw_y),a
                pop hl
cpc_icon_row
                ld a,(rect_x)
                ld d,a
                ld a,(draw_y)
                ld e,a
                ld a,(rect_w)
                ld (draw_cols),a
cpc_icon_byte
                push hl
                push de
                call scr_addr
                ex de,hl
                pop bc
                pop hl
                push hl
                push bc
                ld a,(bm_keep)
                or a
                ld a,(hl)
                jr z,cpc_icon_store
                ld b,a
                rrca
                rrca
                rrca
                rrca
                or b
                and #0F
                ld c,a
                add a,a
                add a,a
                add a,a
                add a,a
                or c
                cpl
                ld c,a
                ld a,(de)
                and c
                or b
cpc_icon_store
                ld (de),a
cpc_icon_skip
                pop de
                pop hl
                inc hl
                inc d
                ld a,(draw_cols)
                dec a
                ld (draw_cols),a
                jr nz,cpc_icon_byte
                ld a,(rect_w)
                ld b,a
                ld a,(bm_w)
                sub b
                ld e,a
                ld d,0
                add hl,de
                ld a,(draw_y)
                inc a
                ld (draw_y),a
                ld a,(draw_rows)
                dec a
                ld (draw_rows),a
                jr nz,cpc_icon_row
                di
                call cpc_draw_sample_end
                jp cpc_damage_end
cpc_icon_draw_end
                pop af
                call foundation_bank_set
                pop af
                ld (SCHED_LOCK),a
                pop af
                pop ix
                ret po
                ei
                ret

; Absolute-phase 16x16 canonical tile, clipped BEFORE pointer exclusion.
k_backdrop
                ld a,b
                ld (rect_x),a
                ld a,c
                ld (rect_y),a
                ld a,d
                ld (rect_w),a
                ld a,e
                ld (rect_h),a
                call cpc_damage_begin
                ret nc
                call cpc_draw_sample_begin
                ei
                ld a,(CPC_BACKDROP_STATUS)
                or a
                jr z,cpc_backdrop_tiled
                xor a
                ld (fill_value),a
                ld a,(rect_y)
                ld (draw_y),a
                ld a,(rect_h)
                ld (draw_rows),a
                call fill_row
                jr cpc_backdrop_done
cpc_backdrop_tiled
                ld a,(rect_y)
                ld (draw_y),a
                ld a,(rect_h)
                ld (draw_rows),a
cpc_backdrop_row
                ld a,(rect_x)
                ld d,a
                ld a,(draw_y)
                ld e,a
                call scr_addr
                ex de,hl
                ld a,(draw_y)
                and 15
                add a,a
                add a,a
                ld l,a
                ld h,0
                ld bc,CPC_BD_TILE
                add hl,bc
                ld a,(rect_x)
                and 3
                add a,l
                ld l,a
                ld a,(rect_w)
                ld b,a
cpc_backdrop_byte
                ld a,(CPC_BACKDROP_STATUS)
                or a
                ld a,0
                jr nz,cpc_backdrop_store
                ld a,(hl)
cpc_backdrop_store
                ld (de),a
                inc de
                inc l
                ld a,l
                and 3
                jr nz,cpc_backdrop_next
                ld a,l
                sub 4
                ld l,a
cpc_backdrop_next
                djnz cpc_backdrop_byte
                ld hl,draw_y
                inc (hl)
                ld hl,draw_rows
                dec (hl)
                jr nz,cpc_backdrop_row
cpc_backdrop_done
                di
                call cpc_draw_sample_end
                jp cpc_damage_end

; A toggles a bounded native asset gallery on the diagnostic root. This is
; not a second Desktop: no launch/file/type/layout/interaction policy.
cpc_icon_gallery
                ld a,0
                ld bc,#0220
                call k_icon
                ld a,3
                ld bc,#2220
                call k_icon
                ld a,20
                ld bc,#4820
                call k_icon
                ld a,8
                ld bc,#1290
                call k_icon_half
                ld a,255                    ; refused slot, must draw nothing
                ld bc,#0220
                jp k_icon
