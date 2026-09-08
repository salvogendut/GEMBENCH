; Shared resident caller/worker identity gate; the module owns context policy.
k_fsctx
                ld    (FSCTX_GATE_OP),a
                FSCTX_PRIVATE_DISPATCH
                FSCTX_CHECK_WORKER
                call  owner_current
                ld    (FSCTX_GATE_OWNER),de
                ld    a,d
                or    e
                jr    z,kfsctx_context
                ld    hl,gbfsctx_modname
                call  FSCTX_MODULE_RUN
                jr    c,kfsctx_result
                ld    a,GB_FSCTX_ERR_UNSUPPORTED
                jr    kfsctx_store
kfsctx_context ld    a,GB_FSCTX_ERR_CONTEXT
kfsctx_store   ld    (FSCTX_GATE_STATUS),a
kfsctx_result  ld    a,(FSCTX_GATE_STATUS)
                ld    de,(FSCTX_GATE_HANDLE)
                ret
