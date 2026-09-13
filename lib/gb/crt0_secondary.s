;; Restricted GBS4 computation entry. Kernel passes HL=block, BC=count.
;; SDCC call 1 expects HL=first pointer, DE=second integer; initialise once per
;; zeroed allocation, not once per call, so the editor model retains its state.
        .module crt0_secondary
        .globl _secondary_main
        .globl l__INITIALIZER
        .globl s__INITIALIZER
        .globl s__INITIALIZED
        .globl l__DATA
        .globl s__DATA
        .globl l__BSS
        .globl s__BSS
        .area _CODE
_start::
        jp entry
        .ascii "GBS4"
        .db 1
entry:
        ld a,(started)
        or a
        jr nz,ready
        push hl
        push bc
        call gsinit
        ld a,#1
        ld (started),a
        pop bc
        pop hl
ready:
        ld d,b
        ld e,c
        jp _secondary_main
zero_region:
        ld a,b
        or c
        ret z
        ld (hl),#0
        dec bc
        ld a,b
        or c
        ret z
        ld d,h
        ld e,l
        inc de
        ldir
        ret
        .area _GSINIT
gsinit:
        ld hl,#s__DATA
        ld bc,#l__DATA
        call zero_region
        ld hl,#s__BSS
        ld bc,#l__BSS
        call zero_region
        ld bc,#l__INITIALIZER
        ld a,b
        or c
        jr z,done
        ld de,#s__INITIALIZED
        ld hl,#s__INITIALIZER
        ldir
done:
        .area _GSFINAL
        ret
        .area _HOME
        .area _INITIALIZER
        .area _DATA
started: .ds 1
        .area _INITIALIZED
        .area _BSS
