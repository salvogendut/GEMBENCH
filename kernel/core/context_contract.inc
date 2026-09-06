; Shared Z80 context/IRQ provider contract (#76).
;
; This preserves the existing algorithm, not a new scheduler or public ABI.
; A task's live BOOT_SP-SP bytes (1..255) live on one fixed runtime stack.
; Switching saves them into the owning app's 7F00..7FFF reserve, changes bank
; using a fixed temporary stack, and restores the selected snapshot. Contexts
; save AF, BC, DE, HL, IX, IY, AF', BC', DE', HL' plus their continuation and PC.
; I and IM are kernel-owned; arbitrary per-task IFF is NOT saved. Yield and
; task-enable require ordinary interrupt-enabled callers and return enabled.
;
; Init runs once with IRQ excluded; all eight state cells are contiguous.
; An IRQ adapter normalizes entry to a raw interrupted-PC stack, with original
; registers intact and IRQ excluded. Shared dispatch saves them before using
; scratch. CTX_IRQ_FINISH consumes saved AF then completes exactly one IRQ on
; the selected fixed stack. IRQ_PENDING is a global outstanding interrupt,
; NOT a property of a snapshot: IRQ->yield and yield->IRQ restores use the
; same pending decision. A two-byte first-run snapshot starts the worker loop
; directly, rather than passing through the register-restore path; its first
; ordinary yield establishes the complete register frame. A non-switching IRQ may not
; use the temporary stack, touch app snapshots or map another app.
;
; CTX_DI / CTX_EI: exclude/enable maskable IRQ, preserve all registers.
; CTX_IRQ_INSTALL: preserve balanced SP; hook once with IRQ already excluded.
; CTX_IRQ_FINISH: nonreturning, restores AF and returns to interrupted PC;
;   other restored registers/SP must survive the platform interrupt chain.
; CTX_MAP_BANK: A=page -> hardware AND software bank shadow changed, IRQ stays
;   excluded; A/BC/DE/HL/flags may be clobbered, balanced fixed temporary SP.
; CTX_WINDOW_ENTRY: A=slot -> HL=fixed record, page at +0; preserve A/C,
;   clobber B/DE/flags. Same records as the visibility provider.
; CTX_FLAGS_FROM_ENTRY / CTX_ENTRY_FROM_FLAGS: translate HL between record
;   and flags cell; preserve A/BC; clobber DE/flags, balanced SP.
; CTX_WORKER_POINTER: HL=record -> HL=worker callback in mapped app; clobber
;   A/DE/flags, preserve BC. Native descriptor interpretation is provider-owned.
; CTX_CALL_WORKER: CALL to HL; callback follows native compute-only contract.
; CTX_SAMPLE_STACK / CTX_SAMPLE_FAULT: optional A telemetry, no clobbers.
;
; Only the root/compositor may enter kernel/modules or use shared scratch.
; LOCK excludes switching while those are live; eligible workers execute in
; 4000..7FFF with their OWN app bank mapped. Root is never timer-preempted.
; Shared worker_select.asm owns all priority/visibility decisions. It runs
; between context_save and context_restore with the old-SP item still live.
; Yield sets the current slot's runnable bit before saving the context.
; Task-enable retains the native precondition of a fresh registered managed
; descriptor: it writes its initial snapshot before checking runnable/managed
; flags. Repeated enable is not a snapshot-preserving operation.
;
; Oversize/zero live-stack faults resume the untouched original stack. An
; empty target snapshot faults after mapping; the old bank is restored before
; resuming. Existing fault behavior does not cancel runnable state.
;
; Bounds below prove local placement/adjacency only. A production provider
; must separately prove code, fixed state, window records, runtime/temporary
; stacks and IRQ/mapper leaves never alias framebuffer, ROM, each other or
; active scratch. BOOT_SP is a runtime word: its value and full 255-byte span
; must be fixed, writable and disjoint. Nested/NMI interrupts, worst-case
; mapper/firmware stack depth and latency are separate hardware obligations.

                assert CORE_CONTEXT_IRQ_PENDING==CORE_CONTEXT_LOCK+1,"context state must be contiguous"
                assert CORE_CONTEXT_CURRENT==CORE_CONTEXT_LOCK+2,"context state must be contiguous"
                assert CORE_CONTEXT_QUANTUM==CORE_CONTEXT_LOCK+3,"context state must be contiguous"
                assert CORE_CONTEXT_RUNNABLE==CORE_CONTEXT_LOCK+4,"context state must be contiguous"
                assert CORE_CONTEXT_LAST==CORE_CONTEXT_LOCK+5,"context state must be contiguous"
                assert CORE_CONTEXT_STACK_MAX==CORE_CONTEXT_LOCK+6,"context state must be contiguous"
                assert CORE_CONTEXT_FAULT==CORE_CONTEXT_LOCK+7,"context state must be contiguous"
                assert CORE_CONTEXT_CURRENT==CORE_WORKER_CURRENT,"context/visibility current mismatch"
                assert CORE_CONTEXT_LAST==CORE_WORKER_LAST,"context/visibility cursor mismatch"
                assert (CORE_CONTEXT_RUN_BIT>=1)&(CORE_CONTEXT_RUN_BIT<=7),"invalid context runnable bit"
                assert (CORE_CONTEXT_MANAGED_BIT>=1)&(CORE_CONTEXT_MANAGED_BIT<=7)&(CORE_CONTEXT_MANAGED_BIT!=CORE_CONTEXT_RUN_BIT),"invalid context managed bit"
                assert CORE_WORKER_READY==(1|(1<<CORE_CONTEXT_RUN_BIT)),"context/visibility ready mismatch"
                assert (CORE_CONTEXT_QUANTUM_TICKS>=1)&(CORE_CONTEXT_QUANTUM_TICKS<=255),"invalid context quantum"
                assert (CORE_CONTEXT_TIMER==0)|(CORE_CONTEXT_TIMER==1),"invalid context timer mode"
                assert (CORE_CONTEXT_SWITCH==0)|(CORE_CONTEXT_SWITCH==1),"invalid context switch mode"
                assert (CORE_CONTEXT_APP_FIRST_HI==#40)&(CORE_CONTEXT_APP_END_HI==#80),"context app aperture is frozen"
                assert (CORE_CONTEXT_SNAPSHOT==#7F00)&(CORE_CONTEXT_STACK_DATA==#7F01)&(CORE_CONTEXT_STACK_CAP==255),"context snapshot ABI is frozen"
                assert CORE_CONTEXT_TMP_TOP-CORE_CONTEXT_TMP_BOTTOM>=6,"context temporary stack too small"
                assert CORE_CONTEXT_CODE_END>CORE_CONTEXT_CODE_BASE,"invalid context code allocation"
                assert ((CORE_CONTEXT_LOCK>=0)&(CORE_CONTEXT_LOCK+8<=#4000))|((CORE_CONTEXT_LOCK>=#8000)&(CORE_CONTEXT_LOCK+8<=#10000)),"CORE_CONTEXT_LOCK must remain fixed"
                assert ((CORE_CONTEXT_BOOT_SP>=0)&(CORE_CONTEXT_BOOT_SP+2<=#4000))|((CORE_CONTEXT_BOOT_SP>=#8000)&(CORE_CONTEXT_BOOT_SP+2<=#10000)),"CORE_CONTEXT_BOOT_SP must remain fixed"
                assert ((CORE_CONTEXT_BANK>=0)&(CORE_CONTEXT_BANK+1<=#4000))|((CORE_CONTEXT_BANK>=#8000)&(CORE_CONTEXT_BANK+1<=#10000)),"CORE_CONTEXT_BANK must remain fixed"
                assert ((CORE_CONTEXT_FOCUS>=0)&(CORE_CONTEXT_FOCUS+1<=#4000))|((CORE_CONTEXT_FOCUS>=#8000)&(CORE_CONTEXT_FOCUS+1<=#10000)),"CORE_CONTEXT_FOCUS must remain fixed"
                assert ((CORE_CONTEXT_TMP_BOTTOM>=0)&(CORE_CONTEXT_TMP_BOTTOM+CORE_CONTEXT_TMP_TOP-CORE_CONTEXT_TMP_BOTTOM<=#4000))|((CORE_CONTEXT_TMP_BOTTOM>=#8000)&(CORE_CONTEXT_TMP_BOTTOM+CORE_CONTEXT_TMP_TOP-CORE_CONTEXT_TMP_BOTTOM<=#10000)),"CORE_CONTEXT_TMP_BOTTOM must remain fixed"
                assert ((CORE_CONTEXT_CODE_BASE>=0)&(CORE_CONTEXT_CODE_BASE+CORE_CONTEXT_CODE_END-CORE_CONTEXT_CODE_BASE<=#4000))|((CORE_CONTEXT_CODE_BASE>=#8000)&(CORE_CONTEXT_CODE_BASE+CORE_CONTEXT_CODE_END-CORE_CONTEXT_CODE_BASE<=#10000)),"CORE_CONTEXT_CODE_BASE must remain fixed"
                assert (CORE_CONTEXT_LOCK+8<=CORE_CONTEXT_BOOT_SP)|(CORE_CONTEXT_BOOT_SP+2<=CORE_CONTEXT_LOCK),"CORE_CONTEXT_LOCK overlaps CORE_CONTEXT_BOOT_SP"
                assert (CORE_CONTEXT_LOCK+8<=CORE_CONTEXT_BANK)|(CORE_CONTEXT_BANK+1<=CORE_CONTEXT_LOCK),"CORE_CONTEXT_LOCK overlaps CORE_CONTEXT_BANK"
                assert (CORE_CONTEXT_LOCK+8<=CORE_CONTEXT_FOCUS)|(CORE_CONTEXT_FOCUS+1<=CORE_CONTEXT_LOCK),"CORE_CONTEXT_LOCK overlaps CORE_CONTEXT_FOCUS"
                assert (CORE_CONTEXT_LOCK+8<=CORE_CONTEXT_TMP_BOTTOM)|(CORE_CONTEXT_TMP_BOTTOM+CORE_CONTEXT_TMP_TOP-CORE_CONTEXT_TMP_BOTTOM<=CORE_CONTEXT_LOCK),"CORE_CONTEXT_LOCK overlaps CORE_CONTEXT_TMP_BOTTOM"
                assert (CORE_CONTEXT_LOCK+8<=CORE_CONTEXT_CODE_BASE)|(CORE_CONTEXT_CODE_BASE+CORE_CONTEXT_CODE_END-CORE_CONTEXT_CODE_BASE<=CORE_CONTEXT_LOCK),"CORE_CONTEXT_LOCK overlaps CORE_CONTEXT_CODE_BASE"
                assert (CORE_CONTEXT_BOOT_SP+2<=CORE_CONTEXT_BANK)|(CORE_CONTEXT_BANK+1<=CORE_CONTEXT_BOOT_SP),"CORE_CONTEXT_BOOT_SP overlaps CORE_CONTEXT_BANK"
                assert (CORE_CONTEXT_BOOT_SP+2<=CORE_CONTEXT_FOCUS)|(CORE_CONTEXT_FOCUS+1<=CORE_CONTEXT_BOOT_SP),"CORE_CONTEXT_BOOT_SP overlaps CORE_CONTEXT_FOCUS"
                assert (CORE_CONTEXT_BOOT_SP+2<=CORE_CONTEXT_TMP_BOTTOM)|(CORE_CONTEXT_TMP_BOTTOM+CORE_CONTEXT_TMP_TOP-CORE_CONTEXT_TMP_BOTTOM<=CORE_CONTEXT_BOOT_SP),"CORE_CONTEXT_BOOT_SP overlaps CORE_CONTEXT_TMP_BOTTOM"
                assert (CORE_CONTEXT_BOOT_SP+2<=CORE_CONTEXT_CODE_BASE)|(CORE_CONTEXT_CODE_BASE+CORE_CONTEXT_CODE_END-CORE_CONTEXT_CODE_BASE<=CORE_CONTEXT_BOOT_SP),"CORE_CONTEXT_BOOT_SP overlaps CORE_CONTEXT_CODE_BASE"
                assert (CORE_CONTEXT_BANK+1<=CORE_CONTEXT_FOCUS)|(CORE_CONTEXT_FOCUS+1<=CORE_CONTEXT_BANK),"CORE_CONTEXT_BANK overlaps CORE_CONTEXT_FOCUS"
                assert (CORE_CONTEXT_BANK+1<=CORE_CONTEXT_TMP_BOTTOM)|(CORE_CONTEXT_TMP_BOTTOM+CORE_CONTEXT_TMP_TOP-CORE_CONTEXT_TMP_BOTTOM<=CORE_CONTEXT_BANK),"CORE_CONTEXT_BANK overlaps CORE_CONTEXT_TMP_BOTTOM"
                assert (CORE_CONTEXT_BANK+1<=CORE_CONTEXT_CODE_BASE)|(CORE_CONTEXT_CODE_BASE+CORE_CONTEXT_CODE_END-CORE_CONTEXT_CODE_BASE<=CORE_CONTEXT_BANK),"CORE_CONTEXT_BANK overlaps CORE_CONTEXT_CODE_BASE"
                assert (CORE_CONTEXT_FOCUS+1<=CORE_CONTEXT_TMP_BOTTOM)|(CORE_CONTEXT_TMP_BOTTOM+CORE_CONTEXT_TMP_TOP-CORE_CONTEXT_TMP_BOTTOM<=CORE_CONTEXT_FOCUS),"CORE_CONTEXT_FOCUS overlaps CORE_CONTEXT_TMP_BOTTOM"
                assert (CORE_CONTEXT_FOCUS+1<=CORE_CONTEXT_CODE_BASE)|(CORE_CONTEXT_CODE_BASE+CORE_CONTEXT_CODE_END-CORE_CONTEXT_CODE_BASE<=CORE_CONTEXT_FOCUS),"CORE_CONTEXT_FOCUS overlaps CORE_CONTEXT_CODE_BASE"
                assert (CORE_CONTEXT_TMP_BOTTOM+CORE_CONTEXT_TMP_TOP-CORE_CONTEXT_TMP_BOTTOM<=CORE_CONTEXT_CODE_BASE)|(CORE_CONTEXT_CODE_BASE+CORE_CONTEXT_CODE_END-CORE_CONTEXT_CODE_BASE<=CORE_CONTEXT_TMP_BOTTOM),"CORE_CONTEXT_TMP_BOTTOM overlaps CORE_CONTEXT_CODE_BASE"
