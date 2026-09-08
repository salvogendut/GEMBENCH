; Shared owner/page policy. Platform state and hooks are defined by
; owner_page_contract.inc; this file performs no native bank switch or I/O.
; Kept as an ordered include so existing MSX2 code addresses do not move.

; Refresh the allocatable count. The first eight entries have a compatibility
; busy mirror used by older picture clients, so either metadata view reserves
; those pages. Entries 8..31 exist only in the general allocator.
page_count_free
                ld    a,(CORE_PAGE_TOTAL)
                ld    b,a
                ld    c,0
                ld    d,0
mpcf_scan       ld    hl,CORE_PAGE_STATE
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    a
                jr    nz,mpcf_next
                ld    a,c
                cp    CORE_WINDOW_MAX
                jr    nc,mpcf_free
                ld    hl,CORE_LEGACY_BUSY
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    a
                jr    nz,mpcf_next
mpcf_free       inc   d
mpcf_next       inc   c
                djnz  mpcf_scan
                ld    a,d
                ld    (CORE_PAGE_FREE),a
                OWNER_PAGE_PUBLISH_FREE
                ret
