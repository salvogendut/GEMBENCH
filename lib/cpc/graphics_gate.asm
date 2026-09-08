; Prototype only, not a published GB_* entry. HL -> 16-byte caller descriptor,
; BC = exact length. Returns A=status; other registers/flags volatile.
; Calls are serialized; descriptor and actual buffer span must lie in
; 4000..7EFF. Copy before page replacement, restore page before copy-out.
; No pointer is retained for deferred work. Caller IFF and fixed SP restored.
graphics_gate
                ld a,i
                push af
                di
                ld a,(bank_shadow)
                push af
                ld a,b
                or a
                jp nz,gate_bad_descriptor
                ld a,c
                cp 16
                jp nz,gate_bad_descriptor
                call validate_span
                jp nc,gate_bad_descriptor
                if FAULT_COPY
                push hl
                ld a,#F7
                call foundation_bank_set
                pop hl
                endif
                ld de,request_packet
                ld bc,16
                ldir
                xor a
                ld (transfer_count),a
                ld a,(request_packet)
                or a
                jp z,gate_bad_operation
                cp 7
                jp nc,gate_bad_operation
                cp 4
                jr nc,gate_pointer
                cp 1
                jr nz,gate_rect
                ld a,(request_packet+9)
                cp 4
                jp nc,gate_bad_pen
gate_rect
                call clip_rectangle
                ld a,(request_packet)
                cp 1
                jp z,gate_execute
                ld a,(rect_w)
                or a
                jp z,gate_execute
                ld e,a
                ld d,0
                ld hl,0
                ld a,(rect_h)
                ld b,a
gate_area
                add hl,de
                djnz gate_area
                ld a,h
                or a
                jp nz,gate_bad_capacity
                ld a,l
                cp 65
                jp nc,gate_bad_capacity
                ld (transfer_count),a
                ld de,(request_packet+12)
                or a
                sbc hl,de
                jr c,gate_capacity_ok
                jp nz,gate_bad_capacity
gate_capacity_ok
                ld hl,(request_packet+10)
                ld a,(transfer_count)
                ld c,a
                ld b,0
                call validate_span
                jp nc,gate_bad_range
                ld a,(request_packet)
                cp 3
                jr nz,gate_execute
                ld de,transfer_buffer
                ldir                         ; restore input copied while caller mapped
                jr gate_execute
gate_pointer
                cp 6
                jr z,gate_execute
                ld hl,(request_packet+14)
                ld de,320
                or a
                sbc hl,de
                jp nc,gate_bad_range
                ld a,(request_packet+2)
                cp 200
                jp nc,gate_bad_range
gate_execute
                ld a,#F7                    ; prove descriptors don't alias caller page
                call foundation_bank_set
                ld a,(request_packet)
                cp 4
                jr z,gate_show
                cp 5
                jr z,gate_move
                cp 6
                jr z,gate_hide
                ld a,(rect_w)
                or a
                jr z,gate_ok
                ld a,(request_packet)
                cp 2
                jr z,gate_save
                ; Draw transactions exclude the pointer only on intersection.
                call pointer_exclude
                ld a,(request_packet)
                cp 1
                call z,rectangle_fill
                ld a,(request_packet)
                cp 3
                call z,rectangle_restore
                ld a,(pointer_excluded)
                or a
                call nz,pointer_show
                jr gate_ok
gate_save
                ; Save content, never pointer pixels; restores the visible pointer.
                call pointer_exclude
                call rectangle_save
                ld a,(pointer_excluded)
                or a
                call nz,pointer_show
                jr gate_ok
gate_move
                ld hl,(request_packet+14)
                ld de,(pointer_x)
                or a
                sbc hl,de
                jr nz,gate_move_changed
                ld a,(request_packet+2)
                ld hl,pointer_y
                cp (hl)
                jr nz,gate_move_changed
                ld a,(pointer_visible)
                or a
                jr nz,gate_ok
gate_move_changed
                call pointer_hide
gate_show
                ld a,(pointer_visible)
                or a
                jr z,gate_show_new
                if FAULT_CURSOR
                xor a
                ld (pointer_visible),a        ; WRONG: duplicate show saves pointer pixels
                else
                jr gate_ok
                endif
gate_show_new
                ld hl,(request_packet+14)
                ld (pointer_x),hl
                ld a,(request_packet+2)
                ld (pointer_y),a
                call pointer_show
                jr gate_ok
gate_hide
                call pointer_hide
gate_ok
                xor a
                jr gate_finish
gate_bad_descriptor
                ld a,1
                jr gate_finish
gate_bad_operation
                ld a,2
                jr gate_finish
gate_bad_pen
                ld a,3
                jr gate_finish
gate_bad_range
                ld a,4
                jr gate_finish
gate_bad_capacity
                ld a,5
gate_finish
                ld (gate_status),a
                pop af                       ; caller's original page
                call foundation_bank_set
                ld a,(gate_status)
                or a
                jr nz,gate_return
                ld a,(request_packet)
                cp 2
                jr nz,gate_return
                ld a,(transfer_count)
                or a
                jr z,gate_return
                ld c,a
                ld b,0
                ld hl,transfer_buffer
                ld de,(request_packet+10)
                ldir                         ; copy-out only after caller page restored
gate_return
                pop af                       ; parity contains entry IFF2
                ld a,(gate_status)
                ret po                       ; caller had DI
                ei
                ret

; HL/BC retained on success. Reject below-window, wrap and end beyond 7F00.
validate_span
                ld a,h
                cp #40
                jr c,span_bad
                push hl
                add hl,bc
                jr c,span_pop_bad
                ld de,#7F00
                or a
                sbc hl,de
                jr c,span_ok
                jr nz,span_pop_bad
span_ok
                pop hl
                scf
                ret
span_pop_bad
                pop hl
span_bad
                or a
                ret

; A/B=request start/extent, D/E=clip start/extent, C=screen bound.
; Saturate both 8-bit additions on carry BEFORE intersecting, never wrap.
; Return CF=1, A=start, B=extent; CF=0 means empty.
clip_axis
                ld (axis_x),a
                ld a,b
                or a
                ret z
                ld a,e
                or a
                ret z
                ld a,(axis_x)
                cp d
                jr nc,axis_start_ok
                ld a,d
axis_start_ok
                ld (axis_start),a
                ld a,(axis_x)
                add a,b
                jr c,axis_end_limit
                cp c
                jr c,axis_end_ok
axis_end_limit
                ld a,c
axis_end_ok
                ld (axis_end),a
                ld a,d
                add a,e
                jr c,axis_clip_limit
                cp c
                jr c,axis_clip_ok
axis_clip_limit
                ld a,c
axis_clip_ok
                ld b,a
                ld a,(axis_end)
                cp b
                jr c,axis_min_ok
                ld a,b
axis_min_ok
                ld b,a
                ld a,(axis_start)
                cp b
                jr nc,axis_empty
                ld c,a
                ld a,b
                sub c
                ld b,a
                ld a,c
                scf
                ret
axis_empty
                or a
                ret

clip_rectangle
                if FAULT_CLIP
                xor a
                ld (request_packet+5),a
                ld (request_packet+6),a
                ld a,80
                ld (request_packet+7),a
                ld a,200
                ld (request_packet+8),a
                endif
                ld a,(request_packet+3)
                ld b,a
                ld a,(request_packet+5)
                ld d,a
                ld a,(request_packet+7)
                ld e,a
                ld a,(request_packet+1)
                ld c,80
                call clip_axis
                jr nc,rectangle_empty
                ld (rect_x),a
                ld a,b
                ld (rect_w),a
                ld a,(request_packet+4)
                ld b,a
                ld a,(request_packet+6)
                ld d,a
                ld a,(request_packet+8)
                ld e,a
                ld a,(request_packet+2)
                ld c,200
                call clip_axis
                jr nc,rectangle_empty
                ld (rect_y),a
                ld a,b
                ld (rect_h),a
                ret
rectangle_empty
                xor a
                ld (rect_w),a
                ld (rect_h),a
                ret
