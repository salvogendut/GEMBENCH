; Shared native shell lookup extracted from MSX (#77). Serialized root work;
; live unique z-order, generation-tagged owner links; scratch must be fixed.
; B=class or C=accessory ID -> A=slot+1, zero if absent. No registration here.
ksh_find
                ld    c,0                           ; coarse lookup: no exact ID
                jr    kshf_start
ksh_find_accessory
                ld    a,c
                or    a
                ret   z
                ld    b,CORE_LOOKUP_ACCESSORY_CLASS
kshf_start
                ld    a,b
                and   CORE_LOOKUP_CLASS_MASK
                ret   z
                ld    (CORE_LOOKUP_CLASS),a                  ; requested encoded class
                ld    a,c
                ld    (CORE_LOOKUP_ID),a             ; optional exact accessory ID
                ld    a,(CORE_LIVE_WINDOWS)
                ld    (CORE_LOOKUP_CURSOR),a                    ; z-order cursor, top to bottom
kshf_loop
                ld    a,(CORE_LOOKUP_CURSOR)
                or    a
                jr    z,kshf_missing
                dec   a
                ld    (CORE_LOOKUP_CURSOR),a
                ld    hl,CORE_Z_ORDER
                add   a,l
                ld    l,a
                ld    a,(hl)
                ld    (CORE_LOOKUP_SLOT),a                 ; candidate slot (repaint is not active)
                call  app_service_for_window
                ld    b,a
                ld    a,(CORE_LOOKUP_CLASS)
                cp    b
                jr    nz,kshf_loop
                ld    a,(CORE_LOOKUP_ID)              ; an exact accessory lookup also
                or    a                             ; matches its private stable ID
                jr    z,kshf_found
                ld    c,a
                ld    a,(CORE_LOOKUP_SLOT)
                ld    hl,CORE_WIN_OWNER
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    a
                jr    z,kshf_loop
                dec   a
                ld    hl,CORE_APP_ACCESSORY
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    c
                jr    nz,kshf_loop
kshf_found
                ld    a,(CORE_LOOKUP_SLOT)
                inc   a
                ret
kshf_missing    xor   a
                ret
