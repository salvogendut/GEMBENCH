; Close one live window slot while keeping its application alive whenever it
; still owns another window. This is also the internal target of GB_APP's
; generation-checked close operation. C = live slot owned by the caller.
app_window_close_slot
                ld    a,c
                ld    (CORE_WINDOW_SLOT),a
                ld    a,(CORE_MAPPED_NATIVE)
                ld    (CORE_CALLER_BANK),a
                ld    a,c
                ld    hl,CORE_WIN_OWNER
                add   a,l
                ld    l,a
                ld    e,(hl)
                ld    hl,CORE_WIN_OWNER_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    d,(hl)
                ld    (CORE_CLOSE_OWNER),de
                ld    a,c
                LIFETIME_PREPARE_CLOSE
                LIFETIME_DROP_WORKER
                ld    (hl),0                       ; dead before identity detaches
                ld    a,(CORE_WINDOW_SLOT)
                ld    c,a
                call  LIFETIME_REMOVE_Z
                ld    de,(CORE_CLOSE_OWNER)
                ld    a,(CORE_WINDOW_SLOT)
                ld    c,a
                call  app_window_detach
                ld    (CORE_APP_REMAIN),a
                call  LIFETIME_FOCUS_TOP
                cpl
                ld    (CORE_PREVIOUS_FOCUS),a
                call  LIFETIME_MAP_FOCUS
                ld    a,(CORE_CALLER_BANK)
                call  LIFETIME_SET_BANK                     ; closing callback must finish in its code page
                ld    de,(CORE_CLOSE_OWNER)
                ld    a,d
                or    e
                jr    z,mkwc_raw_free
                ld    a,(CORE_APP_REMAIN)
                or    a
                jr    nz,mkwc_repaint               ; another owned window keeps the app alive
                call  owner_release                 ; last window: legacy one-window lifecycle
                jr    mkwc_repaint
mkwc_raw_free   ld   a,(CORE_ALLOC_NATIVE)
                call  wm_free_page
mkwc_repaint    jp   LIFETIME_REPAINT
