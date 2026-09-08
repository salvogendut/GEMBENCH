; Native drawing leaves for the shared chrome. Calls are serialized under the
; WM lock; each fill is physically clipped without changing compositor state.
; Preserve fb_x/y/w/h: the shared stripe renderer reuses them across fills.
fill_xywh
                ld a,b
                ld (fb_x),a
                ld a,c
                ld (fb_y),a
                ld a,d
                ld (fb_w),a
                ld a,e
                ld (fb_h),a
fill_block
                ifdef CPC_RUNTIME
                ; During a compositor pass the existing pointer service knows
                ; the WHOLE pending damage and can move safely before a fill.
                ; Do not sample ordinary primitives here: their damage_begin
                ; has already excluded the pointer at its previous position.
                ld a,(CORE_POINTER_PAINTLOCK)
                or a
                call nz,cpc_pointer_service
                endif
                ld a,(fb_w)
                ld b,a
                ld a,(WM_CLIP_X)
                ld d,a
                ld a,(WM_CLIP_W)
                ld e,a
                ld a,(fb_x)
                ld c,CPC_COLUMNS
                call clip_axis
                ret nc
                ld (rect_x),a
                ld a,b
                ld (rect_w),a
                ld a,(fb_h)
                ld b,a
                ld a,(WM_CLIP_Y)
                ld d,a
                ld a,(WM_CLIP_H)
                ld e,a
                ld a,(fb_y)
                ld c,CPC_LINES
                call clip_axis
                ret nc
                ld (rect_y),a
                ld a,b
                ld (rect_h),a
                ld a,(fb_val)
                ld (fill_value),a
                ld a,(rect_y)
                ld (draw_y),a
                ld a,(rect_h)
                ld (draw_rows),a
                call cpc_draw_sample_begin
                ei                          ; lock prevents task switching during drawing
                call fill_row                ; existing bounded Mode-1 fill loop
                di
                jp cpc_draw_sample_end

; Copy caller title BEFORE the data page overlays the caller aperture.
gtd_copy
                ld b,48
cpc_title_copy
                ld a,(hl)
                ld (de),a
                or a
                ret z
                inc hl
                inc de
                djnz cpc_title_copy
                xor a
                ld (de),a
                ret
copy11
                ld bc,11
                ldir
                ret
to_data
                ld a,(BANK_CUR)
                ld (dp_save),a
                ld a,CPC_DATA_PAGE
                jp foundation_bank_set
from_data
                ld a,(dp_save)
                jp foundation_bank_set
