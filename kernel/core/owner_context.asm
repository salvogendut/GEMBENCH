; Shared existing application/window policy (#69). State and platform hooks
; are supplied by app_lifetime_contract.inc. Ordered inclusion preserves bytes.

; owner_current -> DE = pending loader application, mapped application, focused
; window application, or zero. The mapped page is authoritative during
; callbacks for windows below the focus in z-order.
owner_current
                ld    de,(CORE_PENDING_OWNER)
                ld    a,d
                or    e
                jr    nz,moc_validate
                ld    a,(CORE_MAPPED_NATIVE)
                call  owner_for_native
                ld    a,d
                or    e
                jr    nz,moc_validate
                ld    a,(CORE_FOCUS_SLOT)
                cp    CORE_WINDOW_MAX
                jr    nc,moc_none
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
moc_validate    call  owner_validate
                ret   c
moc_none        ld    de,0
                ret

; owner_bind_pending_window: attach the pending application (or the application
; already associated with the caller page) to the registering slot, then consume the pending
; handle. Later windows from the same mapped code page take the second path.
owner_bind_pending_window
                ld    de,(CORE_PENDING_OWNER)
                ld    a,d
                or    e
                jr    nz,mob_have
                ld    a,(CORE_MAPPED_NATIVE)
                call  owner_for_native
                ld    a,d
                or    e
                ret   z
mob_have
                LIFETIME_REGISTER_SLOT
                call  app_window_attach
                ret   nc
                ld    hl,0
                ld    (CORE_PENDING_OWNER),hl
                ret
