; Shared existing application/window policy (#69). State and platform hooks
; are supplied by app_lifetime_contract.inc. Ordered inclusion preserves bytes.

; app_mark_root_current: the first Desktop registration owns the immortal root
; application. Explicit quit rejects this record.
app_mark_root_current
                call  LIFETIME_CURRENT_OWNER
                call  owner_validate
                ret   nc
                ld    a,e
                dec   a
                ld    hl,CORE_APP_FLAGS
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    GB_APP_F_PUBLISHED|GB_APP_F_ROOT
                ld    (hl),a
                ret

; app_mark_worker_current: record which window supplies the application-owned
; worker callback. The fixed scheduler still snapshots by window slot, but the
; application table is authoritative for lifecycle cleanup and allows only one
; worker registration per application in this milestone.
app_mark_worker_current
                call  LIFETIME_CURRENT_OWNER
                call  owner_validate
                ret   nc
                ld    a,e
                dec   a
                ld    c,a
                ld    hl,CORE_APP_WORKER_WIN
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    #FF
                ret   nz
                ld    a,(CORE_FOCUS_SLOT)
                ld    (hl),a
                ret

; app_service_for_window: A = WM slot -> A = owning application's registered
; shell service class, or zero for an ownerless/stale window.
app_service_for_window
                cp    CORE_WINDOW_MAX
                jr    nc,masfw_none
                ld    c,a
                ld    hl,CORE_WIN_OWNER
                add   a,l
                ld    l,a
                ld    e,(hl)
                ld    hl,CORE_WIN_OWNER_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    d,(hl)
                call  owner_validate
                jr    nc,masfw_none
                ld    a,e
                dec   a
                ld    hl,CORE_APP_SERVICE
                add   a,l
                ld    l,a
                ld    a,(hl)
                ret
masfw_none      xor  a
                ret

; app_find_window: DE = application -> A = one owned slot, CF; NC when none.
app_find_window
                ld    (CORE_ALLOC_OWNER),de
                ld    b,CORE_WINDOW_MAX
                ld    c,0
mafw_scan       ld   hl,CORE_WIN_OWNER
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(CORE_ALLOC_OWNER)
                cp    (hl)
                jr    nz,mafw_next
                ld    hl,CORE_WIN_OWNER_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(CORE_ALLOC_OWNER+1)
                cp    (hl)
                jr    nz,mafw_next
                ld    a,c
                scf
                ret
mafw_next       inc  c
                djnz  mafw_scan
                xor   a
                ret

; GB_APP #80CC dispatcher (MSX2 Architecture Milestone 2):
;   A=0                    -> DE=current application handle
;   A=1                    -> A=status, publish a windowless application
;   A=2                    -> A=status, terminate current application
;   A=3                    -> DE=current focused window handle
;   A=4, HL=window handle  -> A=status, close an owned window
;   A=5, HL=window handle  -> A=status, validate an owned window
;   A=6                    -> A=free compositor window slots
;   A=7                    -> A=current application live-window count
;   A=8                    -> A=status, drag the focused owned window
k_app
                or    a
                jp    z,LIFETIME_CURRENT_OWNER
                dec   a
                jr    z,kapp_publish
                dec   a
                jr    z,kapp_quit
                dec   a
                jp    z,kapp_window_current
                dec   a
                jp    z,kapp_window_close
                dec   a
                jp    z,kapp_window_check
                dec   a
                jp    z,kapp_window_free
                dec   a
                jp    z,kapp_window_count
                dec   a
                jp    z,kapp_window_drag
                ld    a,GB_APP_ERR_BADARG
                ret

kapp_publish    call  LIFETIME_CURRENT_OWNER
                call  owner_validate
                jp    nc,kapp_owner
                ld    a,e
                dec   a
                ld    c,a
                ld    hl,CORE_APP_FLAGS
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    GB_APP_F_PUBLISHED
                ld    (hl),a
                ld    hl,CORE_APP_WINDOW_COUNT
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    a
                jr    nz,kapp_publish_done
                ld    hl,CORE_APP_FLAGS
                ld    a,c
                add   a,l
                ld    l,a
                set   3,(hl)
kapp_publish_done
                ld    hl,0
                ld    (CORE_PENDING_OWNER),hl
                xor   a
                ret

kapp_quit       call  LIFETIME_CURRENT_OWNER
                call  owner_validate
                jp    nc,kapp_owner
                ld    (CORE_CLOSE_OWNER),de
                ld    a,e
                dec   a
                ld    c,a
                ld    hl,CORE_APP_FLAGS
                add   a,l
                ld    l,a
                bit   1,(hl)
                jp    nz,kapp_root
                set   2,(hl)
kapp_quit_windows
                ld    de,(CORE_CLOSE_OWNER)
                call  app_find_window
                jr    nc,kapp_quit_release
                ld    c,a
                call  LIFETIME_CLOSE_WINDOW
                ld    de,(CORE_CLOSE_OWNER)
                call  owner_validate
                jr    c,kapp_quit_windows
                xor   a
                ret
kapp_quit_release
                ld    de,(CORE_CLOSE_OWNER)
                call  owner_release
                xor   a
                ret

kapp_window_current
                call  LIFETIME_CURRENT_OWNER
                ld    (CORE_ALLOC_OWNER),de
                call  owner_validate
                jr    nc,kapp_window_none
                ld    a,(CORE_FOCUS_SLOT)
                cp    CORE_WINDOW_MAX
                jr    nc,kapp_window_none
                call  window_handle_slot
                ld    (CORE_WINDOW_HANDLE),de
                ex    de,hl
                ld    de,(CORE_ALLOC_OWNER)
                call  window_validate_owned
                or    a
                jr    nz,kapp_window_none
                ld    de,(CORE_WINDOW_HANDLE)
                ret
kapp_window_none
                ld    de,0
                ret

kapp_window_close
                push  hl
                call  LIFETIME_CURRENT_OWNER
                pop   hl
                call  window_validate_owned
                ret   nz
                call  LIFETIME_CLOSE_WINDOW
                xor   a
                ret

kapp_window_check
                push  hl
                call  LIFETIME_CURRENT_OWNER
                pop   hl
                jp    window_validate_owned

kapp_window_free
                ld    a,(CORE_LIVE_WINDOWS)
                ld    b,a
                ld    a,CORE_WINDOW_MAX
                sub   b
                ret

kapp_window_count
                call  LIFETIME_CURRENT_OWNER
                call  owner_validate
                jp    nc,kapp_owner
                ld    a,e
                dec   a
                ld    hl,CORE_APP_WINDOW_COUNT
                add   a,l
                ld    l,a
                ld    a,(hl)
                ret

kapp_window_drag
                call  kapp_window_current
                ld    a,d
                or    e
                jr    z,kapp_owner
                LIFETIME_DRAG_CURRENT
                xor   a
                ret

kapp_root       ld   a,GB_APP_ERR_ROOT
                ret
kapp_owner      ld   a,GB_APP_ERR_OWNER
                ret
