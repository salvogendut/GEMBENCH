; 3D-U: native title/gadget providers. Selection is the actual Desktop helper;
; window kinds/hit tests/furniture are core/window_chrome.asm. This adapter
; only owns M4 admission, bank publication and the CPC raster entry boundary.
;
; Executable module: exact build-sized trusted native payload, not a sandbox
; or signature check. TBR: exactly 56 (background) or 106 (legacy combined).
; GDT: exactly 50. No partly loaded candidate reaches live drawing memory.
cpc_title_validate
                ; cpc_asset_read has reduced kind by three.
                dec a
                jr nz,cpc_title_not_module
                ld de,CPC_TITLE_MODULE_SIZE
                jp cpc_asset_exact
cpc_title_not_module
                dec a
                ld de,50
                jp nz,cpc_asset_exact
                ld de,56
                call cpc_asset_exact
                ret c
                ld de,106
                jp cpc_asset_exact

cpc_title_assets
                ld a,(TITLE_READY)
                ld (CPC_TITLE_PREVIOUS),a
                xor a
                ld (TITLE_READY),a
                inc a
                ld (CPC_TITLE_MODULE_STATUS),a
                ld (CPC_TITLE_STATUS),a
                ld (CPC_GADGET_STATUS),a
                ld a,4
                ld (CPC_ASSET_KIND),a
                ld hl,cpc_title_modname
                ld de,fs_req_name
                call copy11
                call cpc_asset_read
                jr nc,cpc_title_recovery
                ; Keep fallback artwork in fixed candidate storage. Remaining
                ; bytes are a bounded renderer, published with banked chunks.
                ld hl,CPC_APP_BASE
                ld de,CPC_TITLE_XFER
                ld bc,106
                ldir
                ld hl,CPC_APP_BASE+106
                ld (CPC_FONT_SOURCE),hl
                ld hl,DATA_TITLE_RUN
                ld (CPC_FONT_DEST),hl
                ld hl,CPC_TITLE_MODULE_SIZE-106
                ld (CPC_FONT_LEFT),hl
                call cpc_title_copy_code
                xor a
                ld (CPC_TITLE_MODULE_STATUS),a
                inc a
                ld (TITLE_READY),a
                ld a,5
                ld (CPC_ASSET_KIND),a
                ld hl,CPC_TITLE_NAME
                ld de,fs_req_name
                call copy11
                call cpc_asset_read
                jr nc,cpc_title_gadgets
                ld hl,CPC_APP_BASE
                ld de,CPC_TITLE_XFER
                ld bc,(fs_ent_size)
                ldir
                xor a
                ld (CPC_TITLE_STATUS),a
cpc_title_gadgets
                ld a,6
                ld (CPC_ASSET_KIND),a
                ld hl,CPC_GADGET_NAME
                ld de,fs_req_name
                call copy11
                call cpc_asset_read
                jr nc,cpc_title_publish
                ld hl,CPC_APP_BASE
                ld de,CPC_TITLE_XFER+56
                ld bc,50
                ldir
                xor a
                ld (CPC_GADGET_STATUS),a
                jr cpc_title_publish
cpc_title_recovery
                ; No callable renderer: plain title band and safe embedded
                ; gadgets. Do not execute stale or partly loaded module bytes.
                ld hl,cpc_title_fallback
                ld de,CPC_TITLE_XFER
                ld bc,106
                ldir
cpc_title_publish
                ld a,CPC_DATA_PAGE
                call foundation_bank_set
                ld hl,CPC_TITLE_XFER
                ld de,DATA_TITLE
                ld bc,106
                call cpc_font_commit_chunk
                ld a,(CPC_TITLE_PREVIOUS)
                ld hl,TITLE_READY
                cp (hl)
                ret z
                ld a,1
                ld (CPC_VISUAL_DIRTY),a
                ret

; F6 candidate -> fixed staging -> F7, preserving all other bank allocations.
cpc_title_copy_code
                ld a,CPC_SYSTEM_PAGE
                call foundation_bank_set
                ld hl,(CPC_FONT_LEFT)
                ld bc,128
                ld a,h
                or a
                jr nz,cpc_title_chunk
                ld a,l
                cp 128
                jr nc,cpc_title_chunk
                ld c,l
cpc_title_chunk
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
                jr nz,cpc_title_copy_code
                ret

; F7 is already mapped by the shared gb_open_window entry. Limit pointer
; exclusion to the physical intersection; allow time IRQs under the WM lock.
fill_title_pattern
                ld hl,(fb_x)
                ld (rect_x),hl
                ld hl,(fb_w)
                ld (rect_w),hl
                call cpc_damage_begin
                ret nc
                call cpc_draw_sample_begin
                ei
                call DATA_TITLE_RUN
                di
                call cpc_draw_sample_end
                jp cpc_damage_end
cpc_title_modname db "GBTITLE MOD"
cpc_title_fallback
                incbin "ORIGINAL.TBR"
                incbin "ORIGINAL.GDT"
                assert $-cpc_title_fallback==106,"CPC embedded chrome geometry"
