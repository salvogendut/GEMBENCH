; Shared owner/page policy. Platform state and hooks are defined by
; owner_page_contract.inc; this file performs no native bank switch or I/O.
; Kept as an ordered include so existing MSX2 code addresses do not move.

; app_record_reset: C = application slot. Clear every reusable field while
; preserving the independent active/generation pair.
app_record_reset
                xor   a
                ld    hl,CORE_APP_CODE_NATIVE
                add   a,c
                add   a,l
                ld    l,a
                ld    (hl),0
                ld    hl,CORE_APP_CODE_PAGE
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),0
                ld    hl,CORE_APP_CODE_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),0
                ld    hl,CORE_APP_WINDOW_COUNT
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),0
                ld    hl,CORE_APP_FLAGS
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),0
                ld    hl,CORE_APP_SERVICE
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),0
                ld    hl,CORE_APP_ACCESSORY
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),0
                ld    hl,CORE_APP_PRIMARY_WIN
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),#FF
                ld    hl,CORE_APP_WORKER_WIN
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),#FF
                ld    hl,CORE_DEFER_HANDLER_LO
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),0
                ld    hl,CORE_DEFER_HANDLER_HI
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),0
                ret

; owner_alloc -> DE = generation-tagged application handle, CF set; DE=0, NC
; if the fixed application table is full. GB_OWNER remains a source-compatible
; name for this same identity.
owner_alloc
                ld    hl,CORE_OWNER_ACTIVE
                ld    b,GB_OWNER_MAX
                ld    c,0
moa_scan       ld    a,(hl)
                or    a
                jr    z,moa_take
                inc   hl
                inc   c
                djnz  moa_scan
                ld    de,0
                or    a
                ret
moa_take       ld    (hl),1
                ld    hl,CORE_OWNER_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                inc   a
                jr    nz,moa_gen_ok
                inc   a                       ; generation zero is never published
moa_gen_ok     ld    (hl),a
                ld    d,a
                ld    a,c
                inc   a
                ld    e,a
                push  de
                call  app_record_reset
                pop   de
                scf
                ret

; owner_validate: DE = handle -> CF valid, NC stale/invalid. Clobbers A,C,HL.
owner_validate
                ld    a,e
                or    a
                jr    z,mov_bad
                dec   a
                cp    GB_OWNER_MAX
                jr    nc,mov_bad
                ld    c,a
                ld    hl,CORE_OWNER_ACTIVE
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    a
                jr    z,mov_bad
                ld    hl,CORE_OWNER_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    d
                jr    nz,mov_bad
                scf
                ret
mov_bad         or    a                       ; clear carry
                ret
