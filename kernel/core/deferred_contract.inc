; Shared deferred-message provider contract (#73).
;
; Fixed code/state under serialized root/kernel execution; not IRQ/worker work.
; Mutating API entry checks belong to REQUIRE_ROOT (a no-op only in the existing
; cooperative build). Queued records contain copied values, never app pointers.
; Eight-byte ABI record = sender owner word, receiver owner word, type,p0,p1,p2.
; Send input is receiver,type,p0,p1,p2 (six bytes). Owner words are id+generation.
; Count is published only after all bytes copy. The live FIFO prefix is trusted;
; count<=capacity; remove_index requires C<count; record_ptr requires index<count.
; Capacity<=32 and one byte-index page keep shift/multiply arithmetic bounded.
;
; Validation order is unchanged: caller/context and input, receiver generation/
; terminating state, endpoint, then queue capacity. No new error precedence.
; unregister purges sender AND receiver messages before clearing the endpoint;
; explicit cancel matches sender only. Generation is part of each comparison.
; Scratch SEND+4/+5 is phase-local: saved pointer, handler, or purge mode/count.
; Unregister retains SEND[0..1] across purge; helpers must honor those lifetimes.
;
; One root-loop call removes at most one queue head, before validation/delivery.
; Busy suppresses nested dispatch; CURRENT stays stable while callbacks may send
; or cancel queued messages. Stale/terminating/no-handler receivers are dropped.
; Delivery validates RECEIVER, not sender liveness; teardown normally purges both.
; The handler runs in the receiver code bank, not with changed WM focus. Existing
; owner_current resolves the mapped receiver. Caller bank and busy are restored
; before optional activation; response byte 3 requests it.
;
; Activation retains the pre-callback primary slot and existing live-slot check,
; not a new post-callback generation/owner validation. Hooks/callbacks must obey
; the existing lifecycle protocol. This is not a new guarantee against arbitrary
; self-destruction/slot reuse inside a callback or a change to FS/focus context.
;
; Hooks/macros:
; CURRENT_OWNER -> DE=generation-tagged current owner. VALIDATE_OWNER takes DE,
;   returns carry iff live, retains DE/B; clobbers A/C/HL as the existing helper.
; REQUIRE_ROOT branches to kdefer_context on worker entry; stack balanced.
; CHECK_CALLBACK accepts nonzero HL in caller executable memory, rejects via
;   kdefer_bad; preserve DE (owner), HL. Zero unregister was already handled.
; CHECK_SEND_RECORD accepts full readable six-byte caller buffer at HL, rejects
;   via kdefer_bad; preserve HL, balance stack. It may clobber A/DE/flags.
;   Address arithmetic/ROM/TPA ownership are provider obligations, not this core.
; FIND_SERVICE: B=class,C=0 -> A=window handle (slot+1), or zero.
; FIND_ACCESSORY: C=exact ID -> same result; owner tables are validated afterward.
; SET_BANK: A=native tag, preserve HL handler, update MAPPED_NATIVE.
; CALL: HL=handler -> returns; callback reads CURRENT and writes MESSAGE+3.
; ACTIVATE_WINDOW: A=C=primary slot -> tail hook: validate alive, clip, raise,
;   repaint. Does not create a new delivery or rewrite the stable current record.
; All hooks preserve FIFO/current/scratch except their documented effects and
; callback API use; no added stack frames are required by the MSX macros.
;
; Local bounds do not prove non-overlap with ROM/framebuffer/other state/stacks.
; Provider must enforce a full fixed-memory map and bounded macro expansion/JRs.
                assert (CORE_OWNER_CAPACITY>=1)&(CORE_OWNER_CAPACITY<=255),"invalid CORE_OWNER_CAPACITY"
                assert (CORE_WINDOW_MAX>=1)&(CORE_WINDOW_MAX<=255),"invalid CORE_WINDOW_MAX"
                assert (CORE_DEFER_CAPACITY>=1)&(CORE_DEFER_CAPACITY<=32),"invalid CORE_DEFER_CAPACITY"
                assert GB_DEFER_RECORD_SIZE==8,"deferred ABI record must be eight bytes"
                assert (CORE_APP_TERMINATING_BIT>=0)&(CORE_APP_TERMINATING_BIT<=7),"invalid CORE_APP_TERMINATING_BIT"
                assert (CORE_DEFER_EVENT>=1)&(CORE_DEFER_EVENT<=255),"invalid CORE_DEFER_EVENT"
                assert (CORE_DEFER_QUEUE & #FF)+CORE_DEFER_CAPACITY*8<=#100,"deferred queue crosses a byte-index page"
                assert (CORE_DEFER_HANDLER_LO & #FF)+CORE_OWNER_CAPACITY<=#100,"CORE_DEFER_HANDLER_LO crosses a byte-index page"
                assert (CORE_DEFER_HANDLER_HI & #FF)+CORE_OWNER_CAPACITY<=#100,"CORE_DEFER_HANDLER_HI crosses a byte-index page"
                assert (CORE_APP_FLAGS & #FF)+CORE_OWNER_CAPACITY<=#100,"CORE_APP_FLAGS crosses a byte-index page"
                assert (CORE_APP_CODE_NATIVE & #FF)+CORE_OWNER_CAPACITY<=#100,"CORE_APP_CODE_NATIVE crosses a byte-index page"
                assert (CORE_APP_PRIMARY_WIN & #FF)+CORE_OWNER_CAPACITY<=#100,"CORE_APP_PRIMARY_WIN crosses a byte-index page"
                assert (CORE_WIN_OWNER & #FF)+CORE_WINDOW_MAX<=#100,"CORE_WIN_OWNER crosses a byte-index page"
                assert (CORE_WIN_OWNER_GEN & #FF)+CORE_WINDOW_MAX<=#100,"CORE_WIN_OWNER_GEN crosses a byte-index page"
                assert ((CORE_DEFER_HANDLER_LO>=0)&(CORE_DEFER_HANDLER_LO+CORE_OWNER_CAPACITY<=#4000))|((CORE_DEFER_HANDLER_LO>=#8000)&(CORE_DEFER_HANDLER_LO+CORE_OWNER_CAPACITY<=#10000)),"CORE_DEFER_HANDLER_LO must remain in fixed address space"
                assert ((CORE_DEFER_HANDLER_HI>=0)&(CORE_DEFER_HANDLER_HI+CORE_OWNER_CAPACITY<=#4000))|((CORE_DEFER_HANDLER_HI>=#8000)&(CORE_DEFER_HANDLER_HI+CORE_OWNER_CAPACITY<=#10000)),"CORE_DEFER_HANDLER_HI must remain in fixed address space"
                assert ((CORE_APP_FLAGS>=0)&(CORE_APP_FLAGS+CORE_OWNER_CAPACITY<=#4000))|((CORE_APP_FLAGS>=#8000)&(CORE_APP_FLAGS+CORE_OWNER_CAPACITY<=#10000)),"CORE_APP_FLAGS must remain in fixed address space"
                assert ((CORE_APP_CODE_NATIVE>=0)&(CORE_APP_CODE_NATIVE+CORE_OWNER_CAPACITY<=#4000))|((CORE_APP_CODE_NATIVE>=#8000)&(CORE_APP_CODE_NATIVE+CORE_OWNER_CAPACITY<=#10000)),"CORE_APP_CODE_NATIVE must remain in fixed address space"
                assert ((CORE_APP_PRIMARY_WIN>=0)&(CORE_APP_PRIMARY_WIN+CORE_OWNER_CAPACITY<=#4000))|((CORE_APP_PRIMARY_WIN>=#8000)&(CORE_APP_PRIMARY_WIN+CORE_OWNER_CAPACITY<=#10000)),"CORE_APP_PRIMARY_WIN must remain in fixed address space"
                assert ((CORE_WIN_OWNER>=0)&(CORE_WIN_OWNER+CORE_WINDOW_MAX<=#4000))|((CORE_WIN_OWNER>=#8000)&(CORE_WIN_OWNER+CORE_WINDOW_MAX<=#10000)),"CORE_WIN_OWNER must remain in fixed address space"
                assert ((CORE_WIN_OWNER_GEN>=0)&(CORE_WIN_OWNER_GEN+CORE_WINDOW_MAX<=#4000))|((CORE_WIN_OWNER_GEN>=#8000)&(CORE_WIN_OWNER_GEN+CORE_WINDOW_MAX<=#10000)),"CORE_WIN_OWNER_GEN must remain in fixed address space"
                assert ((CORE_DEFER_QUEUE>=0)&(CORE_DEFER_QUEUE+CORE_DEFER_CAPACITY*GB_DEFER_RECORD_SIZE<=#4000))|((CORE_DEFER_QUEUE>=#8000)&(CORE_DEFER_QUEUE+CORE_DEFER_CAPACITY*GB_DEFER_RECORD_SIZE<=#10000)),"CORE_DEFER_QUEUE must remain in fixed address space"
                assert ((CORE_DEFER_SEND>=0)&(CORE_DEFER_SEND+6<=#4000))|((CORE_DEFER_SEND>=#8000)&(CORE_DEFER_SEND+6<=#10000)),"CORE_DEFER_SEND must remain in fixed address space"
                assert ((CORE_DEFER_CURRENT>=0)&(CORE_DEFER_CURRENT+8<=#4000))|((CORE_DEFER_CURRENT>=#8000)&(CORE_DEFER_CURRENT+8<=#10000)),"CORE_DEFER_CURRENT must remain in fixed address space"
                assert ((CORE_DEFER_PURGE_OWNER>=0)&(CORE_DEFER_PURGE_OWNER+2<=#4000))|((CORE_DEFER_PURGE_OWNER>=#8000)&(CORE_DEFER_PURGE_OWNER+2<=#10000)),"CORE_DEFER_PURGE_OWNER must remain in fixed address space"
                assert ((CORE_DEFER_COUNT>=0)&(CORE_DEFER_COUNT+1<=#4000))|((CORE_DEFER_COUNT>=#8000)&(CORE_DEFER_COUNT+1<=#10000)),"CORE_DEFER_COUNT must remain in fixed address space"
                assert ((CORE_DEFER_BUSY>=0)&(CORE_DEFER_BUSY+1<=#4000))|((CORE_DEFER_BUSY>=#8000)&(CORE_DEFER_BUSY+1<=#10000)),"CORE_DEFER_BUSY must remain in fixed address space"
                assert ((CORE_DEFER_INDEX>=0)&(CORE_DEFER_INDEX+1<=#4000))|((CORE_DEFER_INDEX>=#8000)&(CORE_DEFER_INDEX+1<=#10000)),"CORE_DEFER_INDEX must remain in fixed address space"
                assert ((CORE_DEFER_ACTIVATE>=0)&(CORE_DEFER_ACTIVATE+1<=#4000))|((CORE_DEFER_ACTIVATE>=#8000)&(CORE_DEFER_ACTIVATE+1<=#10000)),"CORE_DEFER_ACTIVATE must remain in fixed address space"
                assert ((CORE_MESSAGE>=0)&(CORE_MESSAGE+4<=#4000))|((CORE_MESSAGE>=#8000)&(CORE_MESSAGE+4<=#10000)),"CORE_MESSAGE must remain in fixed address space"
                assert ((CORE_MAPPED_NATIVE>=0)&(CORE_MAPPED_NATIVE+1<=#4000))|((CORE_MAPPED_NATIVE>=#8000)&(CORE_MAPPED_NATIVE+1<=#10000)),"CORE_MAPPED_NATIVE must remain in fixed address space"
