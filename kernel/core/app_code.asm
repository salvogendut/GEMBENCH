; Shared existing application/window policy (#69). State and platform hooks
; are supplied by app_lifetime_contract.inc. Ordered inclusion preserves bytes.

; app_bind_code_page: A = native mapper segment and DE = page handle returned
; by page_alloc_owned. Publish them in the pending application record. Returns
; A = native segment so loader call sites can continue unchanged.
app_bind_code_page
                ld    (CORE_ALLOC_NATIVE),a
                ld    (CORE_ALLOC_HANDLE),de
                ld    de,(CORE_PENDING_OWNER)
                call  owner_validate
                jr    nc,mabcp_done
                ld    a,e
                dec   a
                ld    c,a
                ld    hl,CORE_APP_CODE_NATIVE
                add   a,l
                ld    l,a
                ld    a,(CORE_ALLOC_NATIVE)
                ld    (hl),a
                ld    hl,CORE_APP_CODE_PAGE
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(CORE_ALLOC_HANDLE)
                ld    (hl),a
                ld    hl,CORE_APP_CODE_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(CORE_ALLOC_HANDLE+1)
                ld    (hl),a
mabcp_done     ld    a,(CORE_ALLOC_NATIVE)
                ret
