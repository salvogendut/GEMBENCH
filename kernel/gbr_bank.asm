; MSX2 auxiliary mapper-segment transport for GBR resources (milestone 7).
; Operation in A through the retired GB_BLITE slot:
;   0 load MSX_GBR_NAME from /GBENCH -> A=segment, MSX_GBR_SIZE
;   1 copy MSX_GBR_LEN bytes at MSX_GBR_OFF -> MSX_GBR_DST, A=1/0
;   2 release MSX_GBR_PAGE
; All code, state and stack live outside page 1. The caller's app segment is
; restored before every return.
k_gbr_segment
                cp    1
                jp    z,kgs_read
                cp    2
                jp    z,kgs_free
                or    a
                jp    nz,k_ret0

kgs_load
                call  wm_alloc_page
                or    a
                ret   z
                ld    (MSX_GBR_PAGE),a
                ld    hl,MSX_GBR_NAME
                ld    de,fs_req_name
                ld    bc,11
                ldir
                ld    a,(bank_cur)
                push  af
                di
                ld    a,(MSX_GBR_PAGE)
                call  bank_set
                ld    hl,#4000
                ld    (fs_load_dst),hl
                ld    (fs_load_max),hl
                call  fs_load_sys
                jr    nc,kgs_load_fail
                ld    hl,(fs_ent_size)
                ld    (MSX_GBR_SIZE),hl
                pop   af
                call  bank_set
                ei
                ld    a,(MSX_GBR_PAGE)
                scf
                ret
kgs_load_fail
                pop   af
                call  bank_set
                ld    a,(MSX_GBR_PAGE)
                call  wm_free_page
                xor   a
                ld    (MSX_GBR_PAGE),a
                ld    (MSX_GBR_SIZE),a
                ld    (MSX_GBR_SIZE+1),a
                ei
                ret

kgs_read
                ld    a,(MSX_GBR_PAGE)
                call  kgs_page_busy
                jp    z,k_ret0
                ld    a,(MSX_GBR_LEN)
                or    a
                jp    z,k_ret0
                cp    MSX_GBR_MAXREAD+1
                jp    nc,k_ret0
                ld    hl,(MSX_GBR_OFF)
                ld    de,#4000
                or    a
                sbc   hl,de
                jp    nc,k_ret0               ; offset must be below the segment end
                add   hl,de                   ; restore offset
                ld    a,(MSX_GBR_LEN)
                ld    c,a
                ld    b,0
                add   hl,bc                   ; one-past-last byte
                ld    de,#4001
                or    a
                sbc   hl,de
                jp    nc,k_ret0               ; end may equal #4000, never exceed it

                ld    a,(bank_cur)
                push  af
                di
                ld    a,(MSX_GBR_PAGE)
                call  bank_set
                ld    hl,(MSX_GBR_OFF)
                ld    de,#4000
                add   hl,de
                ld    de,MSX_GBR_BUF
                ld    a,(MSX_GBR_LEN)
                ld    c,a
                ld    b,0
                ldir
                pop   af
                call  bank_set
                ld    hl,MSX_GBR_BUF
                ld    de,(MSX_GBR_DST)
                ld    a,(MSX_GBR_LEN)
                ld    c,a
                ld    b,0
                ldir
                ei
                ld    a,1
                ret

kgs_free
                ld    a,(MSX_GBR_PAGE)
                or    a
                ret   z
                call  wm_free_page
                xor   a
                ld    (MSX_GBR_PAGE),a
                ld    a,1
                ret

; A = page. Return NZ only when it is a currently claimed app-pool segment.
kgs_page_busy
                ld    b,a
                ld    a,(APP_NPAGES)
                ld    c,a
                ld    hl,APP_PAGES
                ld    de,APP_BUSY
kgs_page_loop
                ld    a,c
                or    a
                ret   z
                ld    a,(hl)
                cp    b
                jr    z,kgs_page_hit
                inc   hl
                inc   de
                dec   c
                jr    kgs_page_loop
kgs_page_hit
                ld    a,(de)
                or    a
                ret
