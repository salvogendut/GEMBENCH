;; GEOBENCH-2.1 parameter bridge. SDCC call(1): HL=request -> DE=result.
;; Stack records belong to each saved context. Copy under DI to app-primary
;; storage, including text on that stack. GB_PARAMS validates/copies it again.
        .module gbuniversal_draw
        .globl _gb_parameters
        .globl _gb_uparam_call
        .area _CODE

_gb_parameters:
        push ix
        ld bc, #16
        call 0x80D5
        ld d, a
        pop ix
        ret

_gb_uparam_call:
        push ix
        ld a, i
        push af
        di
        ld de, #u_request
        ld bc, #16
        ldir
        ld a, (u_request)
        cp #2
        jr nz, u_call
        ld a, (u_request+8)
        or a
        jr z, u_call
        ld c, a
        ld b, #0
        ld hl, (u_request+6)
        ld de, #u_text
        ldir
        ld hl, #u_text
        ld (u_request+6), hl
u_call:
        ld hl, #u_request
        ld bc, #16
        call 0x80D5
        ld d, a
        pop af
        pop ix
        jp po, u_return
        ei
u_return:
        ret

        .area _DATA
u_request: .ds 16
u_text:    .ds 48
