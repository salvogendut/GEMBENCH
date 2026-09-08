; Shared owner/page policy. Platform state and hooks are defined by
; owner_page_contract.inc; this file performs no native bank switch or I/O.
; Kept as an ordered include so existing MSX2 code addresses do not move.

; owner_for_native: A = native page tag -> DE = page owner, or zero.
owner_for_native
                ld    (CORE_ALLOC_PURPOSE),a   ; byte scratch: native target
                ld    a,(CORE_PAGE_TOTAL)
                ld    b,a
                ld    c,0
                ld    hl,CORE_PAGE_NATIVE
mof_scan        ld    a,(hl)
                push  hl
                ld    hl,CORE_ALLOC_PURPOSE
                cp    (hl)
                pop   hl
                jr    z,mof_hit
                inc   hl
                inc   c
                djnz  mof_scan
                ld    de,0
                ret
mof_hit         ld    hl,CORE_PAGE_STATE
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    a
                jr    z,mof_none
                ld    hl,CORE_PAGE_OWNER
                ld    a,c
                add   a,l
                ld    l,a
                ld    e,(hl)
                ld    hl,CORE_PAGE_OWNER_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    d,(hl)
                ret
mof_none        ld    de,0
                ret

; page_alloc_owned: DE = valid owner, B = purpose -> A native segment and
; DE page handle, CF set. On failure A=0, DE=0, NC.
page_alloc_owned
                ld    (CORE_ALLOC_OWNER),de
                ld    a,b
                ld    (CORE_ALLOC_PURPOSE),a
                call  page_count_free
                ld    de,(CORE_ALLOC_OWNER)
                call  owner_validate
                jr    nc,mpa_fail
                ld    a,(CORE_PAGE_TOTAL)
                ld    b,a
                ld    c,0
                ld    hl,CORE_PAGE_STATE
mpa_scan        ld    a,(hl)
                or    a
                jr    nz,mpa_next
                ld    a,c
                cp    CORE_WINDOW_MAX
                jr    nc,mpa_take
                push  hl
                ld    hl,CORE_LEGACY_BUSY
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    a
                pop   hl
                jr    z,mpa_take
mpa_next
                inc   hl
                inc   c
                djnz  mpa_scan
mpa_fail        ld    de,0
                xor   a
                ret
mpa_take        ld    (hl),1
                ld    hl,CORE_PAGE_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                inc   a
                jr    nz,mpa_gen_ok
                inc   a
mpa_gen_ok      ld    (hl),a
                ld    d,a
                ld    a,c
                inc   a
                ld    e,a
                ld    (CORE_ALLOC_HANDLE),de
                ld    de,(CORE_ALLOC_OWNER)
                ld    hl,CORE_PAGE_OWNER
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),e
                ld    hl,CORE_PAGE_OWNER_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),d
                ld    hl,CORE_PAGE_PURPOSE
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(CORE_ALLOC_PURPOSE)
                ld    (hl),a
                ld    a,c
                cp    CORE_WINDOW_MAX
                jr    nc,mpa_count
                ld    hl,CORE_LEGACY_BUSY
                add   a,l
                ld    l,a
                ld    (hl),1
mpa_count       push  bc
                call  page_count_free
                pop   bc
                ld    hl,CORE_PAGE_NATIVE
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                ld    de,(CORE_ALLOC_HANDLE)
                scf
                ret

; page_check_owned: HL = page handle, DE = owner -> A = GB_PAGE_* result.
page_check_owned
                ld    (CORE_ALLOC_HANDLE),hl
                ld    (CORE_ALLOC_OWNER),de
                call  owner_validate
                jr    nc,mpc_owner
                ld    hl,(CORE_ALLOC_HANDLE)
                ld    a,l
                or    a
                jr    z,mpc_stale
                dec   a
                ld    c,a
                ld    a,(CORE_PAGE_TOTAL)
                cp    c
                jr    z,mpc_stale
                jr    c,mpc_stale
                ld    hl,CORE_PAGE_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(CORE_ALLOC_HANDLE+1)
                cp    (hl)
                jr    nz,mpc_stale
                ld    hl,CORE_PAGE_STATE
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    a
                jr    z,mpc_free
                ld    de,(CORE_ALLOC_OWNER)
                ld    hl,CORE_PAGE_OWNER
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    e
                jr    nz,mpc_owner
                ld    hl,CORE_PAGE_OWNER_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    d
                jr    nz,mpc_owner
                xor   a
                ret
mpc_stale       ld    a,GB_PAGE_ERR_STALE
                ret
mpc_owner       ld    a,GB_PAGE_ERR_OWNER
                ret
mpc_free        ld    a,GB_PAGE_ERR_FREE
                ret

; page_release_index: C = pool index. Privileged internal primitive.
page_release_index
                ld    hl,CORE_PAGE_STATE
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),0
                ld    hl,CORE_PAGE_OWNER
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),0
                ld    hl,CORE_PAGE_OWNER_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),0
                ld    hl,CORE_PAGE_PURPOSE
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),0
                ld    a,c
                cp    CORE_WINDOW_MAX
                jr    nc,mpri_count
                ld    hl,CORE_LEGACY_BUSY
                add   a,l
                ld    l,a
                ld    (hl),0
mpri_count      jp    page_count_free

page_free_owned
                push  hl
                call  page_check_owned
                pop   hl
                or    a
                ret   nz
                ld    a,l
                dec   a
                ld    c,a
                call  page_release_index
                xor   a
                ret

; Adopt a page reserved through the old CORE_LEGACY_BUSY compatibility mirror. Legacy
; Browser/Icon Editor picture clients still need the native segment for
; GB_PICEDIT, but their first kernel transfer makes the reservation owned and
; therefore eligible for automatic release. A = native segment. Best effort;
; an unknown, free, or already-owned page is left unchanged.
page_claim_legacy_native
                ld    (CORE_ALLOC_NATIVE),a
                ld    a,(CORE_PAGE_TOTAL)
                ld    b,a
                ld    c,0
                ld    hl,CORE_PAGE_NATIVE
mpcl_scan       ld    a,(hl)
                push  hl
                ld    hl,CORE_ALLOC_NATIVE
                cp    (hl)
                pop   hl
                jr    z,mpcl_found
                inc   hl
                inc   c
                djnz  mpcl_scan
                ret
mpcl_found      ld    a,c
                cp    CORE_WINDOW_MAX
                ret   nc                       ; only the mirror can reserve outside metadata
                ld    hl,CORE_PAGE_STATE
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    a
                ret   nz                       ; already owned by the general allocator
                ld    a,c
                ld    hl,CORE_LEGACY_BUSY
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    a
                ret   z                        ; not actually reserved
                ld    a,c
                ld    (CORE_ALLOC_INDEX),a
                call  OWNER_PAGE_CURRENT_OWNER
                ld    a,d
                or    e
                ret   z
                ld    (CORE_ALLOC_OWNER),de
                ld    a,(CORE_ALLOC_INDEX)
                ld    c,a
                ld    hl,CORE_PAGE_STATE
                add   a,l
                ld    l,a
                ld    (hl),1
                ld    hl,CORE_PAGE_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                inc   a
                jr    nz,mpcl_gen_ok
                inc   a
mpcl_gen_ok     ld    (hl),a
                ld    de,(CORE_ALLOC_OWNER)
                ld    hl,CORE_PAGE_OWNER
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),e
                ld    hl,CORE_PAGE_OWNER_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),d
                ld    hl,CORE_PAGE_PURPOSE
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),GB_PAGE_RESOURCE
                jp    page_count_free
