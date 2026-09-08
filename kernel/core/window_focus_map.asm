; Shared working focus/stack policy (#70); see window_focus_contract.inc.
; wm_map_focus: bank to the focused window's page and point CORE_FOCUS_HANDLER at its
; on_event (so menu_dispatch in k_poll delivers top-bar clicks to the focused app).
; On a focus change, also swap the top-bar menu to the focused window's (or clear
; it) so the bar shows the right menu and clicks reach the right handler.
wm_map_focus
                ld    a,(CORE_FOCUS_SLOT)
                FOCUS_NATIVE_CELL
                ld    a,(hl)                       ; page (+0)
                call  FOCUS_SET_BANK                     ; preserves HL
                push  hl
                FOCUS_EVENT_POINTER
                ld    (CORE_FOCUS_HANDLER),hl
                pop   hl                            ; HL = entry
                ld    a,(CORE_FOCUS_SLOT)               ; focus changed since last frame?
                ld    de,CORE_PREVIOUS_FOCUS
                ld    a,(de)
                ld    b,a
                ld    a,(CORE_FOCUS_SLOT)
                cp    b
                ret   z                            ; no change -> leave the bar as is
                ld    (de),a                       ; CORE_PREVIOUS_FOCUS = focus
                FOCUS_MENU_POINTER
                ld    a,h
                or    l
                jp    z,FOCUS_MENU_CLEAR                 ; no menu -> empty the bar
                jp    FOCUS_MENU_INSTALL                 ; install the focused window's menu
