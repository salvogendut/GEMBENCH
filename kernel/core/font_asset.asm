; Shared configured font selection/fallback/geometry policy. Providers own the
; bank/IRQ boundary, bounded reader and publication into their font allocation.
font_init
                FONT_ENTER
                ld    hl,KCFG_FONTNAME
                ld    de,fs_req_name
                call  copy11
                ld    hl,FONT_LOAD_MAX
                ld    (fs_load_max),hl
                ld    hl,DATA_FONT
                ld    (fs_load_dst),hl
                ld    hl,def_fnt
                call  load_or_default
                ld    hl,DATA_FONT
                call  FONT_APPLY
                FONT_LEAVE
                ret
def_fnt         db    "DEFAULT FNT"
def_ist         db    "DEFAULT IST"

; HL = default padded 8.3 name. A failed read (including a provider's format
; rejection) tries the default using the same destination and capacity.
load_or_default
                push  hl
                call  FONT_READ
                pop   hl
                ret   c
                ld    de,fs_req_name
                call  copy11
                jp    FONT_READ
