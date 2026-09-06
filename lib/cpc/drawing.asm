; #77 parameter -> Mode-1 hardware adapters. Shared GB_PARAMS owns validation,
; IX, IFF and SCHED_LOCK; these leaves preserve IX and restore the caller bank.
; Line endpoints are bounded by the shared receiver. The compositor clip is
; in byte columns/scanlines. Hardware rendering may service IRQs while locked.

; D=byte column E=row -> CF visible. Saturating clip ends; A/BC volatile.
cpc_byte_visible
                ld a,d
                cp CPC_COLUMNS
                jr nc,cpc_byte_out
                ld a,e
                cp CPC_LINES
                jr nc,cpc_byte_out
                ifndef CPC_FAULT_DRAW_CLIP
                ld a,(WM_CLIP_X)
                cp d
                jr z,cpc_byte_xstart
                jr nc,cpc_byte_out
cpc_byte_xstart
                ld b,a
                ld a,(WM_CLIP_W)
                or a
                jr z,cpc_byte_out
                add a,b
                jr c,cpc_byte_y
                cp d
                jr c,cpc_byte_out
                jr z,cpc_byte_out
cpc_byte_y
                ld a,(WM_CLIP_Y)
                cp e
                jr z,cpc_byte_ystart
                jr nc,cpc_byte_out
cpc_byte_ystart
                ld b,a
                ld a,(WM_CLIP_H)
                or a
                jr z,cpc_byte_out
                add a,b
                jr c,cpc_byte_in
                cp e
                jr c,cpc_byte_out
                jr z,cpc_byte_out
                endif
cpc_byte_in
                scf
                ret
cpc_byte_out
                or a
                ret

; Restrict damage bounds to visible clip BEFORE excluding a software pointer.
cpc_damage_begin
                ld a,(rect_w)
                ld b,a
                ld a,(WM_CLIP_X)
                ld d,a
                ld a,(WM_CLIP_W)
                ld e,a
                ld a,(rect_x)
                ld c,CPC_COLUMNS
                call clip_axis
                jr nc,cpc_damage_empty
                ld (rect_x),a
                ld a,b
                ld (rect_w),a
                ld a,(rect_h)
                ld b,a
                ld a,(WM_CLIP_Y)
                ld d,a
                ld a,(WM_CLIP_H)
                ld e,a
                ld a,(rect_y)
                ld c,CPC_LINES
                call clip_axis
                jr nc,cpc_damage_empty
                ld (rect_y),a
                ld a,b
                ld (rect_h),a
                jp pointer_exclude
cpc_damage_empty
                xor a
                ld (pointer_excluded),a
                ret
cpc_damage_end
                ld a,(pointer_excluded)
                or a
                jp nz,pointer_show
                ret

cpc_draw_text
                ld a,b
                ld (tc_x),a
                ld (rect_x),a
                ld a,c
                ld (tc_y),a
                ld (rect_y),a
                push hl
                ld b,d
                ld c,e
                call set_text_pens
                ld a,(up_request+8)
                ld b,a
                ld hl,0
                ld a,(font_w)
                ld e,a
                ld d,0
cpc_text_width
                add hl,de
                djnz cpc_text_width
                ld de,3
                add hl,de
                srl h
                rr l
                srl h
                rr l
                ld a,l
                ld (rect_w),a
                ld a,(font_h)
                ld (rect_h),a
                call cpc_damage_begin
                pop hl
                ; All text is fixed scratch before font replaces caller aperture.
                ld a,(BANK_CUR)
                ld (draw_bank),a
                push hl
                ld a,CPC_DATA_PAGE
                call foundation_bank_set
                pop hl
                ifdef CPC_FAULT_DRAW_COPY
                ld hl,#4500               ; deliberate late caller read from F7
                endif
                call cpc_draw_sample_begin
                ei                        ; shared lock prevents task reentry
                call draw_text
                di
                call cpc_draw_sample_end
                ld a,(draw_bank)
                call foundation_bank_set
                jp cpc_damage_end

cpc_draw_line
                ld hl,(up_request+2)
                ld (line_x),hl
                ld de,(up_request+6)
                or a
                sbc hl,de
                ld bc,1
                jr c,cpc_line_x_forward
                ld bc,-1
                jr cpc_line_dx
cpc_line_x_forward
                ex de,hl
                ld hl,0
                or a
                sbc hl,de
cpc_line_dx
                ld (line_dx),hl
                ld (line_sx),bc
                ld hl,(up_request+4)
                ld (line_y),hl
                ld de,(up_request+8)
                or a
                sbc hl,de
                ld bc,1
                jr c,cpc_line_y_forward
                ld bc,-1
                jr cpc_line_dy
cpc_line_y_forward
                ex de,hl
                ld hl,0
                or a
                sbc hl,de
cpc_line_dy
                ld (line_dy),hl
                ld (line_sy),bc
                ld de,(line_dx)
                ex de,hl
                or a
                sbc hl,de
                ld (line_err),hl
                ; Bounding rectangle is conservative; exact per-pixel clip below.
                ld hl,(up_request+2)
                ld de,(up_request+6)
                call cpc_line_min
                srl h
                rr l
                srl h
                rr l
                ld a,l
                ld (rect_x),a
                ld hl,(line_dx)
                ld de,7
                add hl,de
                srl h
                rr l
                srl h
                rr l
                ld a,l
                ld (rect_w),a
                ld hl,(up_request+4)
                ld de,(up_request+8)
                call cpc_line_min
                ld a,l
                ld (rect_y),a
                ld hl,(line_dy)
                inc hl
                ld a,l
                ld (rect_h),a
                call cpc_damage_begin
                call cpc_draw_sample_begin
                ei
cpc_line_step
                call cpc_line_pixel
                ld hl,(line_x)
                ld de,(up_request+6)
                or a
                sbc hl,de
                jr nz,cpc_line_more
                ld hl,(line_y)
                ld de,(up_request+8)
                or a
                sbc hl,de
                jr z,cpc_line_done
cpc_line_more
                ld hl,(line_err)
                add hl,hl
                ld (line_e2),hl
                ld de,(line_dy)
                add hl,de
                bit 7,h
                jr nz,cpc_line_check_y
                ld hl,(line_err)
                or a
                sbc hl,de
                ld (line_err),hl
                ld hl,(line_x)
                ld de,(line_sx)
                add hl,de
                ld (line_x),hl
cpc_line_check_y
                ld hl,(line_e2)
                ld de,(line_dx)
                or a
                sbc hl,de
                bit 7,h
                jr nz,cpc_line_inc_y
                ld a,h
                or l
                jr nz,cpc_line_step
cpc_line_inc_y
                ld hl,(line_err)
                add hl,de
                ld (line_err),hl
                ld hl,(line_y)
                ld de,(line_sy)
                add hl,de
                ld (line_y),hl
                jr cpc_line_step
cpc_line_done
                di
                call cpc_draw_sample_end
                jp cpc_damage_end
cpc_line_min
                push hl
                or a
                sbc hl,de
                pop hl
                ret c
                ex de,hl
                ret

; Diagnostic telemetry, no timing deadline claim. Both sample sites are DI;
; the measured interval is the backend's interrupt-enabled drawing loop.
cpc_draw_sample_begin
                push hl
                ld hl,(CPC_IRQ_COUNT)
                ld (draw_tick_start),hl
                pop hl
                ret
cpc_draw_sample_end
                ld hl,(CPC_IRQ_COUNT)
                ld de,(draw_tick_start)
                or a
                sbc hl,de
                ld de,(draw_irq_total)
                add hl,de
                ld (draw_irq_total),hl
                ret

cpc_line_pixel
                ld hl,(line_x)
                ld a,l
                and 3
                ld b,a
                ld a,#88
                jr z,cpc_pixel_mask
cpc_pixel_shift
                srl a
                djnz cpc_pixel_shift
cpc_pixel_mask
                ld (pixel_mask),a
                ld a,(up_request+10)
                ld e,a
                ld d,0
                push hl
                ld hl,solid_pens
                add hl,de
                ld a,(hl)
                ld (pixel_ink),a
                pop hl
                srl h
                rr l
                srl h
                rr l
                ld d,l
                ld a,(line_y)
                ld e,a
                call cpc_byte_visible
                ret nc
                call scr_addr
                ld a,(pixel_mask)
                cpl
                and (hl)
                ld b,a
                ld a,(pixel_mask)
                ld c,a
                ld a,(pixel_ink)
                and c
                or b
                ld (hl),a
                ret
