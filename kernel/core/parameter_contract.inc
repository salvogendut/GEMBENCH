; Shared GEOBENCH-2.1 receiving-side GB_PARAMS contract (#75).
; HL=16-byte descriptor in caller primary, BC=16 -> A=status, E=boolean.
; Public records/codes/app range stay frozen. Validate complete spans before
; copying; no app pointer survives native mapping or return. Text copy is 49B
; including NUL; callbacks must preserve IX pointing at the stable request.
; CURRENT_OWNER -> DE exact mapped owner (zero if absent), trusted ID bounds.
; WINDOW_CALL A=5, HL=handle validates live generation and implicit caller,
; returning native APP status (0/2/3 -> params OK/stale/owner). It preserves IX.
; DRAW_LINE consumes the nine canonical bytes at up_request+2; DRAW_TEXT takes
; B/C=x/y, D/E=pen/paper, HL=fixed NUL text. Restore module bank/stack on return.
; ENTER saves IX/IFF/lock and serializes before copying. LEAVE restores them,
; retaining A status/E result, and may branch to up_return to restore IFF.
; Native rendering may enable IRQs; the provider's scheduler lock must prevent
; worker/root reentry until LEAVE. No callbacks may overwrite this scratch.
; Root-only rendering; timer ops may run from the mapped app's worker. Pending
; rect/gen precede identity; active timer identity is not cancelled. Dropped
; acknowledgement is generation-tagged. No additional queue or new fairness.
; The caller-primary 4000..7EFF span is the universal ABI, not an MSX mailbox.
; Local bounds/indexing checks don't prove the complete provider memory map,
; hook register promises, instruction timing or overall stack budget.
                assert ((universal_parameters>=0)&(up_text_copy+49<=#4000))|((universal_parameters>=#8000)&(up_text_copy+49<=#10000)),"parameter code and scratch must remain fixed"
                assert (CORE_PARAM_OWNER_MAX>=1)&(CORE_PARAM_OWNER_MAX<=127),"invalid parameter owner capacity"
                assert (CORE_PARAM_COLUMNS>=1)&(CORE_PARAM_COLUMNS<=254),"invalid parameter columns"
                assert (CORE_PARAM_WIDTH==CORE_PARAM_COLUMNS*4),"invalid four-pixel-column geometry"
                assert (CORE_PARAM_HEIGHT>=1)&(CORE_PARAM_HEIGHT<=254),"invalid parameter height"
                assert (CORE_PARAM_APP_NATIVE & #FF)+CORE_PARAM_OWNER_MAX<=#100,"parameter owner table crosses index page"
                assert ((CORE_PARAM_APP_NATIVE>=0)&(CORE_PARAM_APP_NATIVE+CORE_PARAM_OWNER_MAX<=#4000))|((CORE_PARAM_APP_NATIVE>=#8000)&(CORE_PARAM_APP_NATIVE+CORE_PARAM_OWNER_MAX<=#10000)),"CORE_PARAM_APP_NATIVE must remain fixed"
                assert ((CORE_PARAM_MAPPED_NATIVE>=0)&(CORE_PARAM_MAPPED_NATIVE+1<=#4000))|((CORE_PARAM_MAPPED_NATIVE>=#8000)&(CORE_PARAM_MAPPED_NATIVE+1<=#10000)),"CORE_PARAM_MAPPED_NATIVE must remain fixed"
                assert ((CORE_PARAM_CURRENT>=0)&(CORE_PARAM_CURRENT+1<=#4000))|((CORE_PARAM_CURRENT>=#8000)&(CORE_PARAM_CURRENT+1<=#10000)),"CORE_PARAM_CURRENT must remain fixed"
                assert ((CORE_PARAM_LOCK>=0)&(CORE_PARAM_LOCK+1<=#4000))|((CORE_PARAM_LOCK>=#8000)&(CORE_PARAM_LOCK+1<=#10000)),"CORE_PARAM_LOCK must remain fixed"
                assert ((CORE_PARAM_TIMER_OWNER>=0)&(CORE_PARAM_TIMER_OWNER+1<=#4000))|((CORE_PARAM_TIMER_OWNER>=#8000)&(CORE_PARAM_TIMER_OWNER+1<=#10000)),"CORE_PARAM_TIMER_OWNER must remain fixed"
                assert ((CORE_PARAM_TIMER_RECT>=0)&(CORE_PARAM_TIMER_RECT+4<=#4000))|((CORE_PARAM_TIMER_RECT>=#8000)&(CORE_PARAM_TIMER_RECT+4<=#10000)),"CORE_PARAM_TIMER_RECT must remain fixed"
                assert ((CORE_PARAM_TIMER_GEN>=0)&(CORE_PARAM_TIMER_GEN+1<=#4000))|((CORE_PARAM_TIMER_GEN>=#8000)&(CORE_PARAM_TIMER_GEN+1<=#10000)),"CORE_PARAM_TIMER_GEN must remain fixed"
                assert ((CORE_PARAM_DROPPED>=0)&(CORE_PARAM_DROPPED+1<=#4000))|((CORE_PARAM_DROPPED>=#8000)&(CORE_PARAM_DROPPED+1<=#10000)),"CORE_PARAM_DROPPED must remain fixed"
                assert ((CORE_PARAM_DROPPED_GEN>=0)&(CORE_PARAM_DROPPED_GEN+1<=#4000))|((CORE_PARAM_DROPPED_GEN>=#8000)&(CORE_PARAM_DROPPED_GEN+1<=#10000)),"CORE_PARAM_DROPPED_GEN must remain fixed"
                assert ((up_request>=0)&(up_request+16<=#4000))|((up_request>=#8000)&(up_request+16<=#10000)),"up_request must remain fixed"
                assert ((up_text_copy>=0)&(up_text_copy+49<=#4000))|((up_text_copy>=#8000)&(up_text_copy+49<=#10000)),"up_text_copy must remain fixed"
