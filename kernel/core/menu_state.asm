; Shared native menu publication. MENU_DEF is a fixed 37-byte snapshot;
; descriptor pointers remain owned by the registered window's mapped page.
k_menu                                          ; HL = def ptr in the focused app's page.
                ; Also record it as the focused window's menu, so a later focus change
                ; re-installs it instead of clearing the bar (#142: gb_menu must persist
                ; like a static gb_win_t.menu does).
                push  hl
                ld    a,(WM_FOCUS)
                call  wm_entry                  ; HL = focused window's WM entry
                ld    de,WM_FR_MENU
                add   hl,de                     ; -> its menu-def-ptr field
                pop   de                         ; DE = the def ptr
                ld    (hl),e
                inc   hl
                ld    (hl),d
                ex    de,hl                       ; HL = def ptr (fall into the copy)
menu_install                                    ; HL = menu def (mapped page) -> MENU_DEF
                ld    a,(hl)                  ; count
                cp    5
                ret   nc                       ; > 4 titles unsupported -> ignore
                ld    e,a                       ; len = count*9 + 1
                add   a,a
                add   a,a
                add   a,a
                add   a,e
                inc   a
                ld    c,a
                ld    b,0
                ld    de,MENU_DEF
                ldir
                ret
; menu_clear: empty the top-bar menu (focus moved to a window with no menu).
menu_clear
                xor   a
                ld    (MENU_DEF),a
                ret
