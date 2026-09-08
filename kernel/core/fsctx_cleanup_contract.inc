; Root teardown, CORE_ALLOC_OWNER=exact owner+generation. No native handles
; survive a bounded operation. Purge neither generations nor launch handoff.
; Clobbers AF/B/DE/IX; same stack/call placement as the original MSX2 routine.
; The paged C layout and resident bindings must agree. Platform map owns safety
; outside these local spans, including non-overlap with code/framebuffer.
                assert (CORE_FSCTX_MAX>=1)&(CORE_FSCTX_MAX<=255),"invalid FSCTX capacity"
                assert (CORE_FSCTX_RECORD_SIZE>=4)&(CORE_FSCTX_RECORD_SIZE<=255),"invalid FSCTX stride"
                assert (CORE_FSCTX_ACTIVE>=0)&(CORE_FSCTX_ACTIVE<CORE_FSCTX_RECORD_SIZE)&(CORE_FSCTX_ACTIVE<=127),"invalid active field"
                assert (CORE_FSCTX_OWNER>=0)&(CORE_FSCTX_OWNER+2<=CORE_FSCTX_RECORD_SIZE)&(CORE_FSCTX_OWNER<=126),"invalid owner field"
                assert (CORE_FSCTX_ACTIVE<CORE_FSCTX_OWNER)|(CORE_FSCTX_ACTIVE>CORE_FSCTX_OWNER+1),"overlapping FSCTX fields"
                assert ((CORE_FSCTX_TABLE>=0)&(CORE_FSCTX_TABLE+CORE_FSCTX_MAX*CORE_FSCTX_RECORD_SIZE<=#4000))|((CORE_FSCTX_TABLE>=#8000)&(CORE_FSCTX_TABLE+CORE_FSCTX_MAX*CORE_FSCTX_RECORD_SIZE<=#10000)),"FSCTX table must remain fixed"
                assert ((CORE_ALLOC_OWNER>=0)&(CORE_ALLOC_OWNER+2<=#4000))|((CORE_ALLOC_OWNER>=#8000)&(CORE_ALLOC_OWNER+2<=#10000)),"cleanup owner must remain fixed"
                assert (CORE_ALLOC_OWNER+2<=CORE_FSCTX_TABLE)|(CORE_FSCTX_TABLE+CORE_FSCTX_MAX*CORE_FSCTX_RECORD_SIZE<=CORE_ALLOC_OWNER),"cleanup owner overlaps context table"
