    push af                         ; retain the TBR/GDT selector
    or a
    jr z,cl_title_key
    ld a,#8
    push af
    inc sp
    ld hl,#cl_gadget_key
    call _cfg_val                  ; DE = value offset
    jr cl_have_pos
cl_title_key:
    ld a,#9
    push af
    inc sp
    ld hl,#cl_title_key_text
    call _cfg_val
cl_have_pos:
    push de
    ld hl,#cl_default
    ld de,#_chrome_name
    ld bc,#11
    ldir
    pop de
    ld hl,(#CHROME_CFG_LEN)                ; KCFG_LEN
    ld a,d
    cp h
    jr c,cl_copy_stem
    jr nz,cl_extension
    ld a,e
    cp l
    jr nc,cl_extension
cl_copy_stem:
    push de
    ld hl,#_chrome_name
    ld (hl),#0x20
    ld de,#_chrome_name+1
    ld bc,#7
    ldir
    pop hl
    ld de,#CHROME_CFG_TEXT                  ; KCFG_TEXT
    add hl,de
    ld de,#_chrome_name
    ld b,#8
cl_stem_loop:
#ifdef CHROME_BOUNDED_TEXT
    push hl
    push de
    ld de,(#CHROME_CFG_LEN)
    push bc
    ld bc,#CHROME_CFG_TEXT
    ex de,hl
    add hl,bc
    ex de,hl
    pop bc
    or a
    sbc hl,de
    pop de
    pop hl
    jr nc,cl_extension
#endif
    ld a,(hl)
#ifdef CHROME_BOUNDED_TEXT
    or a
    jr z,cl_extension
#endif
    cp #13
    jr z,cl_extension
    cp #10
    jr z,cl_extension
    cp #'.'
    jr z,cl_extension
    ld (de),a
    inc hl
    inc de
    djnz cl_stem_loop
cl_extension:
    pop af
    or a
    jr z,cl_load
    ld hl,#_chrome_name+8
    ld (hl),#'G'
    inc hl
    ld (hl),#'D'
    inc hl
    ld (hl),#'T'
