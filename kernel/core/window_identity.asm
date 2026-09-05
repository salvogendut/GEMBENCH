; Shared existing application/window policy (#69). State and platform hooks
; are supplied by app_lifetime_contract.inc. Ordered inclusion preserves bytes.

; window_generation_next: A = reusable WM slot -> DE = new opaque window
; handle. A generation is advanced before the slot is published alive.
window_generation_next
                ld    c,a
                ld    hl,CORE_WIN_GEN
                add   a,l
                ld    l,a
                ld    a,(hl)
                inc   a
                jr    nz,mwgn_ok
                inc   a
mwgn_ok         ld    (hl),a
                ld    d,a
                ld    a,c
                inc   a
                ld    e,a
                ret

; window_handle_slot: A = live slot -> DE = generation-tagged handle.
window_handle_slot
                ld    c,a
                ld    hl,CORE_WIN_GEN
                add   a,l
                ld    l,a
                ld    d,(hl)
                ld    a,c
                inc   a
                ld    e,a
                ret

; app_window_attach: A = WM slot, DE = application. Bind the parallel window
; owner link, increment the application window count, and publish its first
; primary window. Returns CF on success.
app_window_attach
                ld    (CORE_WINDOW_SLOT),a
                ld    (CORE_ALLOC_OWNER),de
                call  owner_validate
                ret   nc
                ld    a,e
                dec   a
                ld    (CORE_APP_SLOT),a
                ld    c,a
                ld    a,(CORE_WINDOW_SLOT)
                ld    b,a
                ld    hl,CORE_WIN_OWNER
                add   a,l
                ld    l,a
                ld    (hl),e
                ld    hl,CORE_WIN_OWNER_GEN
                ld    a,b
                add   a,l
                ld    l,a
                ld    (hl),d
                ld    hl,CORE_APP_WINDOW_COUNT
                ld    a,c
                add   a,l
                ld    l,a
                inc   (hl)
                ld    hl,CORE_APP_PRIMARY_WIN
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    #FF
                jr    nz,mawa_primary_ok
                ld    a,b
                ld    (hl),a
mawa_primary_ok ld   hl,CORE_APP_FLAGS
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                and   #FF-GB_APP_F_WINDOWLESS
                or    GB_APP_F_PUBLISHED
                ld    (hl),a
                scf
                ret

; app_window_detach: C = WM slot, DE = owning application. Clear the parallel
; link and update primary/worker metadata. Returns A = remaining window count.
app_window_detach
                ld    a,c
                ld    (CORE_WINDOW_SLOT),a
                ld    (CORE_ALLOC_OWNER),de
                call  owner_validate
                jp    nc,mawd_none
                ld    a,e
                dec   a
                ld    (CORE_APP_SLOT),a
                ld    b,a
                ld    hl,CORE_APP_WINDOW_COUNT
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    a
                jr    z,mawd_counted
                dec   (hl)
                dec   a
mawd_counted    ld   (CORE_APP_REMAIN),a
                ld    a,(CORE_WINDOW_SLOT)
                ld    c,a
                ld    hl,CORE_WIN_OWNER
                add   a,l
                ld    l,a
                ld    (hl),0
                ld    hl,CORE_WIN_OWNER_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),0
                ld    hl,CORE_APP_WORKER_WIN
                ld    a,b
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    c
                jr    nz,mawd_primary
                ld    (hl),#FF
mawd_primary    ld   hl,CORE_APP_PRIMARY_WIN
                ld    a,b
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    c
                jr    nz,mawd_flags
                ld    (hl),#FF
                ld    a,(CORE_ALLOC_OWNER)
                ld    e,a
                ld    a,(CORE_ALLOC_OWNER+1)
                ld    d,a
                ld    b,CORE_WINDOW_MAX
                ld    c,0
mawd_find       ld   hl,CORE_WIN_OWNER
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    e
                jr    nz,mawd_next
                ld    hl,CORE_WIN_OWNER_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    d
                jr    nz,mawd_next
                ld    a,(CORE_APP_SLOT)
                ld    hl,CORE_APP_PRIMARY_WIN
                add   a,l
                ld    l,a
                ld    (hl),c
                jr    mawd_flags
mawd_next       inc   c
                djnz  mawd_find
mawd_flags      ld   a,(CORE_APP_REMAIN)
                or    a
                jr    nz,mawd_done
                ld    a,(CORE_APP_SLOT)
                ld    hl,CORE_APP_FLAGS
                add   a,l
                ld    l,a
                set   3,(hl)
mawd_done       ld   a,(CORE_APP_REMAIN)
                ret
mawd_none       xor  a
                ret

; window_validate_owned: HL = opaque window handle, DE = current application.
; Returns A=GB_APP_OK and C=slot, or an explicit stale/owner result.
window_validate_owned
                ld    (CORE_WINDOW_HANDLE),hl
                ld    (CORE_ALLOC_OWNER),de
                call  owner_validate
                jr    nc,mwvo_owner
                ld    hl,(CORE_WINDOW_HANDLE)
                ld    a,l
                or    a
                jr    z,mwvo_stale
                dec   a
                cp    CORE_WINDOW_MAX
                jr    nc,mwvo_stale
                ld    c,a
                ld    hl,CORE_WIN_GEN
                add   a,l
                ld    l,a
                ld    a,(CORE_WINDOW_HANDLE+1)
                cp    (hl)
                jr    nz,mwvo_stale
                LIFETIME_TEST_WINDOW_ALIVE
                jr    z,mwvo_stale
                ld    de,(CORE_ALLOC_OWNER)
                ld    hl,CORE_WIN_OWNER
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    e
                jr    nz,mwvo_owner
                ld    hl,CORE_WIN_OWNER_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    d
                jr    nz,mwvo_owner
                xor   a
                ret
mwvo_stale      ld   a,GB_APP_ERR_STALE
                ret
mwvo_owner      ld   a,GB_APP_ERR_OWNER
                ret
