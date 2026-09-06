; Bounded firmware-free CPC 8255/AY keyboard scan, root task only.
; Publishes ten active-low rows, including joystick row 9. No AY tone writes,
; fake mouse-presence assumption, key repeat or text translation policy here.
; Owns PPI/AY during takeover; leaves port A output and AY inactive. IRQ only
; samples fixed time cells, so cannot race these I/O registers.
cpc_input_scan
                ld a,i
                push af
                di
                ld bc,#F782
                out (c),c
                ld bc,#F40E
                out (c),c
                ld bc,#F6C0
                out (c),c
                ld bc,#F600
                out (c),c
                ld bc,#F792
                out (c),c
                ld hl,CPC_KEYS
                ld c,#40
cpc_input_row
                ld b,#F6
                out (c),c
                ld b,#F4
                in a,(c)
                ld (hl),a
                inc hl
                inc c
                ld a,c
                cp #4A
                jr nz,cpc_input_row
                ld bc,#F782
                out (c),c
                ld bc,#F600
                out (c),c
                pop af
                ret po
                ei
                ret
