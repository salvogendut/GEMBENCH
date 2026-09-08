; Shared resident owner-context cleanup (#74).
fsctx_owner_cleanup
                ld    ix,CORE_FSCTX_TABLE
                ld    b,CORE_FSCTX_MAX
kfoc_loop      ld    a,(ix+CORE_FSCTX_ACTIVE)
                or    a
                jr    z,kfoc_next
                ld    a,(CORE_ALLOC_OWNER)
                cp    (ix+CORE_FSCTX_OWNER)
                jr    nz,kfoc_next
                ld    a,(CORE_ALLOC_OWNER+1)
                cp    (ix+CORE_FSCTX_OWNER+1)
                jr    nz,kfoc_next
                ld    (ix+CORE_FSCTX_ACTIVE),0
kfoc_next      ld    de,CORE_FSCTX_RECORD_SIZE
                add   ix,de
                djnz  kfoc_loop
                ret
