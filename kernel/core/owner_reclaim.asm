; Shared owner/page policy. Platform state and hooks are defined by
; owner_page_contract.inc; this file performs no native bank switch or I/O.
; Kept as an ordered include so existing MSX2 code addresses do not move.

; owner_release: DE = owner. Reclaim all its pages and invalidate the owner.
owner_release
                ld    (CORE_ALLOC_OWNER),de
                call  owner_validate
                jp    nc,mor_stale
                ld    de,(CORE_ALLOC_OWNER)      ; queued sender/receiver endpoints die atomically
                call  OWNER_PAGE_PURGE_MESSAGES
                ld    de,(CORE_ALLOC_OWNER)
                call  OWNER_PAGE_CLOSE_CONTEXTS       ; no file context survives its application
                ld    a,(CORE_PAGE_TOTAL)
                ld    b,a
                ld    c,0
mor_pages       push  bc
                ld    hl,CORE_PAGE_STATE
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    a
                jr    z,mor_next
                ld    de,(CORE_ALLOC_OWNER)
                ld    hl,CORE_PAGE_OWNER
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    e
                jr    nz,mor_next
                ld    hl,CORE_PAGE_OWNER_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    d
                jr    nz,mor_next
                call  page_release_index
mor_next        pop   bc
                inc   c
                djnz  mor_pages
                ld    de,(CORE_ALLOC_OWNER)
                ld    a,e
                dec   a
                ld    hl,CORE_OWNER_ACTIVE
                add   a,l
                ld    l,a
                ld    (hl),0
                ld    a,e
                dec   a
                ld    c,a
                call  app_record_reset
                ld    b,CORE_WINDOW_MAX
                ld    c,0
mor_windows     ld    hl,CORE_WIN_OWNER
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    e
                jr    nz,mor_win_next
                ld    hl,CORE_WIN_OWNER_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    d
                jr    nz,mor_win_next
                ld    (hl),0
                ld    hl,CORE_WIN_OWNER
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),0
mor_win_next    inc   c
                djnz  mor_windows
                ld    hl,(CORE_PENDING_OWNER)
                or    a
                sbc   hl,de
                jr    nz,mor_ok
                ld    hl,0
                ld    (CORE_PENDING_OWNER),hl
mor_ok          xor   a
                ret
mor_stale       ld    a,GB_PAGE_ERR_STALE
                ret

; Legacy internal allocation: use the pending loader owner or focused owner,
; and return the raw page tag expected by the existing bank code.
wm_alloc_page
                call  OWNER_PAGE_CURRENT_OWNER
                ld    a,d
                or    e
                jr    z,mwa_fail
                ld    b,GB_PAGE_RESOURCE
                call  page_alloc_owned
                ret   c
mwa_fail        xor   a
                ret

; Privileged raw-segment free used by existing picture/GBR code. Public clients
; can only free generation-tagged handles through GB_PAGE.
wm_free_page
                ld    (CORE_ALLOC_PURPOSE),a
                ld    a,(CORE_PAGE_TOTAL)
                ld    b,a
                ld    c,0
                ld    hl,CORE_PAGE_NATIVE
mwf_scan        ld    a,(hl)
                push  hl
                ld    hl,CORE_ALLOC_PURPOSE
                cp    (hl)
                pop   hl
                jr    z,mwf_hit
                inc   hl
                inc   c
                djnz  mwf_scan
                ret
mwf_hit         jp    page_release_index
