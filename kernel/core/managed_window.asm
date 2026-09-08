; Shared native WM policy extracted from the production MSX2 kernel (#77).
; State, frozen record offsets and drawing/bank hooks are supplied by the provider.
mw_publish
                push  hl
                inc   hl                     ; entry+1
                ld    de,MW_RECT
                ld    bc,4
                ldir                         ; MW_RECT = x,y,w,h ; HL = entry+5
                ld    e,(hl)
                inc   hl
                ld    d,(hl)
                ld    (mw_desc),de           ; desc ptr
                pop   hl
                ret

; Load the append-only kind byte only for a window explicitly registered through
; gb_wm_managed_kind. Legacy descriptors never have bytes read beyond offset 11.
mw_kind_load
                ld    a,GB_WK_LEGACY
                ld    (mw_kind),a
                ; HL is the PAINTED entry, not necessarily the focused window.
                CHROME_ENTRY_FLAGS           ; HL -> this entry's native flags
                bit   4,(hl)                  ; MW_KIND_V1
                ret   z
                ld    hl,(mw_desc)
                ld    de,12                  ; desc.kind
                add   hl,de
                ld    a,(hl)
                and   GB_WK_STANDARD
                or    GB_WK_EXTENDED         ; internal opt-in marker
                ld    (mw_kind),a
                ret
                CHROME_KIND_STORAGE

; mw_hook: A = a GB_MSG_* window message. Set gb_msg.type, then dispatch to the
; window's single proc (desc+6). The proc switches on the type. Clobbers HL,DE,A.
mw_hook
                ld    (GB_MSG),a              ; gb_msg.type = the message being delivered
                ld    hl,(mw_desc)
                ld    de,6
                add   hl,de                  ; HL = &desc.proc
                ld    a,(hl)
                inc   hl
                ld    h,(hl)
                ld    l,a                     ; HL = proc ptr
                ld    a,h
                or    l
                ret   z                       ; no proc -> skip (shouldn't happen)
                jp    md_call                 ; jp (hl); the proc rets to mw_hook's caller

; wm_chrome_draw: HL = entry. Draw frame+title (gb_open_window) then the content (on_draw).
wm_chrome_draw
                call  mw_publish
                call  mw_kind_load
                ld    hl,(mw_desc)           ; title = *(desc+8)
                ld    de,8
                add   hl,de
                ld    e,(hl)
                inc   hl
                ld    d,(hl)
                ex    de,hl                  ; HL = title ptr (caller page)
                ld    a,(MW_RECT)
                ld    b,a                     ; x
                ld    a,(MW_RECT+1)
                ld    c,a                     ; y
                ld    a,(MW_RECT+2)
                ld    d,a                     ; w
                ld    a,(MW_RECT+3)
                ld    e,a                     ; h
                call  gb_open_window_kind    ; frame + selected furniture
                ld    a,GB_MSG_DRAW          ; -> the proc draws the content
                jr    mw_hook
