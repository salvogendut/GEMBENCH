; Shared native WM policy extracted from the production MSX2 kernel (#77).
; State, frozen record offsets and drawing/bank hooks are supplied by the provider.
wm_free_slot
                ld    hl,WM_TABLE+WM_FR_FLAGS
                ld    de,WM_ESZ
                ld    c,0
wfs_l           ld    a,(hl)
                and   1
                jr    z,wfs_found
                add   hl,de
                inc   c
                ld    a,c
                cp    WM_MAXWIN
                jr    c,wfs_l
                ld    c,#FF
wfs_found       ld    a,c
                ret
