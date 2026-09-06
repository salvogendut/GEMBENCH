; Mode-1 adapter proof. Addressing, fill/copy loops and interleaved mask/data
; composition are adapted from lib/screen.asm and lib/cursor.asm at 56478578.
; Changes: explicit fixed scratch, validated nonempty bounds, no ROM/IFF side
; effects, four pointer phases, pixel/top-down coordinates, idempotent hide.

; D=byte column, E=line (already clipped); HL=screen. Clobbers AF/BC.
scr_addr
                ld a,e
                and 7
                add a,a
                add a,a
                add a,a
                or #C0
                ld h,a
                ld l,0
                ld a,e
                srl a
                srl a
                srl a
                add a,a
                ld c,a
                ld b,0
                push hl
                ld hl,row80
                add hl,bc
                ld c,(hl)
                inc hl
                ld b,(hl)
                pop hl
                add hl,bc
                ld b,0
                ld c,d
                add hl,bc
                ret

rectangle_fill
                ld a,(request_packet+9)
                ld e,a
                ld d,0
                ld hl,solid_pens
                add hl,de
                ld a,(hl)
                ld (fill_value),a
                ld a,(rect_y)
                ld (draw_y),a
                ld a,(rect_h)
                ld (draw_rows),a
fill_row
                ld a,(rect_x)
                ld d,a
                ld a,(draw_y)
                ld e,a
                call scr_addr
                ld a,(rect_w)
                ld b,a
                ld a,(fill_value)
fill_byte
                ld (hl),a
                inc hl
                djnz fill_byte
                ld hl,draw_y
                inc (hl)
                ld hl,draw_rows
                dec (hl)
                jr nz,fill_row
                ret

rectangle_block
                ld hl,rect_x
                ld de,block_x
                ld bc,4
                ldir
                ld hl,transfer_buffer
                ld (block_buffer),hl
                ret
rectangle_save
                call rectangle_block
                xor a
                jp block_copy
rectangle_restore
                call rectangle_block
                ld a,1
                jp block_copy

; A=0 screen->buffer, A=1 buffer->screen. Compact canonical w*h bytes.
; Caller provides validated nonzero bounds and sufficient fixed buffer.
block_copy
                ld (copy_direction),a
                ld a,(block_y)
                ld (draw_y),a
                ld a,(block_h)
                ld (draw_rows),a
                ld hl,(block_buffer)
                ld (copy_pointer),hl
copy_row
                ld a,(block_x)
                ld d,a
                ld a,(draw_y)
                ld e,a
                call scr_addr
                ld de,(copy_pointer)
                ld a,(copy_direction)
                or a
                jr z,copy_save
                ex de,hl
copy_save
                ld a,(block_w)
                ld c,a
                ld b,0
                ldir
                ld a,(copy_direction)
                or a
                jr z,copy_saved
                ex de,hl
copy_saved
                ld (copy_pointer),de
                ld hl,draw_y
                inc (hl)
                ld hl,draw_rows
                dec (hl)
                jr nz,copy_row
                ret

pointer_block
                ld hl,pointer_col
                ld de,block_x
                ld bc,4
                ldir
                ld hl,pointer_background
                ld (block_buffer),hl
                ret
pointer_hide
                ld a,(pointer_visible)
                or a
                ret z
                call pointer_block
                ld a,1
                call block_copy
                xor a
                ld (pointer_visible),a
                ld hl,(pointer_restores)
                inc hl
                ld (pointer_restores),hl
                ret

pointer_show
                ld a,(pointer_visible)
                or a
                ret nz
                ld hl,(pointer_x)
                ld a,l
                and 3
                ld b,a
                ld de,48
                push hl
                ld hl,cursor_phases
                or a
                jr z,pointer_phase_ok
pointer_phase_add
                add hl,de
                djnz pointer_phase_add
pointer_phase_ok
                ld (pointer_sprite),hl
                pop hl
                srl h
                rr l
                srl h
                rr l
                ld a,l
                ld (pointer_col),a
                ld b,a
                ld a,80
                sub b
                cp 3
                jr c,pointer_width_ok
                ld a,3
pointer_width_ok
                ld (pointer_w),a
                ld a,(pointer_y)
                ld (pointer_line),a
                ld b,a
                ld a,200
                sub b
                cp 8
                jr c,pointer_height_ok
                ld a,8
pointer_height_ok
                ld (pointer_h),a
                call pointer_block
                xor a
                call block_copy
                ld a,(pointer_line)
                ld (draw_y),a
                ld a,(pointer_h)
                ld (draw_rows),a
                ld hl,(pointer_sprite)
                ld de,pointer_background
pointer_row
                push hl
                push de
                ld a,(pointer_col)
                ld d,a
                ld a,(draw_y)
                ld e,a
                call scr_addr
                ld b,h
                ld c,l
                pop de
                pop hl
                ld a,(pointer_w)
                ld (draw_cols),a
pointer_byte
                ld a,(de)
                inc de
                and (hl)
                inc hl
                or (hl)
                inc hl
                ld (bc),a
                inc bc
                ld a,(draw_cols)
                dec a
                ld (draw_cols),a
                jr nz,pointer_byte
                ld a,(pointer_w)
                ld b,a
                ld a,3
                sub b
                add a,a
                ld c,a
                ld b,0
                add hl,bc
                ld a,(draw_y)
                inc a
                ld (draw_y),a
                ld a,(draw_rows)
                dec a
                ld (draw_rows),a
                jr nz,pointer_row
                ld a,1
                ld (pointer_visible),a
                ld hl,(pointer_saves)
                inc hl
                ld (pointer_saves),hl
                ret

; Hide only if the affected byte rectangle intersects the saved pointer block.
; The draw operation can then update content and re-show against NEW pixels.
pointer_exclude
                xor a
                ld (pointer_excluded),a
                ld a,(pointer_visible)
                or a
                ret z
                ld a,(pointer_col)
                ld b,a
                ld a,(rect_w)
                ld c,a
                ld a,(rect_x)
                add a,c
                cp b
                ret c
                ret z
                ld a,(pointer_w)
                add a,b
                ld b,a
                ld a,(rect_x)
                cp b
                ret nc
                ld a,(pointer_line)
                ld b,a
                ld a,(rect_h)
                ld c,a
                ld a,(rect_y)
                add a,c
                cp b
                ret c
                ret z
                ld a,(pointer_h)
                add a,b
                ld b,a
                ld a,(rect_y)
                cp b
                ret nc
                ld a,1
                ld (pointer_excluded),a
                jp pointer_hide

solid_pens      db #00,#F0,#0F,#FF
row80           dw 0,80,160,240,320,400,480,560,640,720,800,880,960
                dw 1040,1120,1200,1280,1360,1440,1520,1600,1680,1760,1840,1920
