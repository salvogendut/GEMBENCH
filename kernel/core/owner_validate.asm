; Shared generation-tagged owner validation, also usable by fixed modules.
; DE = handle -> CF valid, NC stale/invalid. Clobbers A,C,HL.
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
mov_bad         or    a
                ret
