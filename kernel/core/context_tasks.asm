; Shared Z80 context mechanism (#76); see context_contract.inc.
; sched_yield: safe-point counterpart of the interrupt wrapper. Every task
; context has the same register image; only its continuation differs. A system
; or finite worker task uses this path, while a timer-preempted worker resumes
; through sched_irq_restore below.
sched_yield
                CTX_DI
                push  af
                push  bc
                push  de
                push  hl
                push  ix
                push  iy
                ex    af,af'
                push  af
                ex    af,af'
                exx
                push  bc
                push  de
                push  hl
                exx
                ld    a,(CORE_CONTEXT_CURRENT)
                CTX_WINDOW_ENTRY
                CTX_FLAGS_FROM_ENTRY
                set   CORE_CONTEXT_RUN_BIT,(hl)                   ; root becomes runnable with its first snapshot
                call  sched_switch_context
sched_yield_restore
                ld    a,1
                ld    (CORE_CONTEXT_LOCK),a
sched_context_restore
                exx
                pop   hl
                pop   de
                pop   bc
                exx
                ex    af,af'
                pop   af
                ex    af,af'
                pop   iy
                pop   ix
                pop   hl
                pop   de
                pop   bc
                ld    a,(CORE_CONTEXT_IRQ_PENDING)      ; AF is still saved, so restored HL stays untouched
                rra
                jr    nc,sched_restore_yield
                xor   a
                ld    (CORE_CONTEXT_IRQ_PENDING),a
                CTX_IRQ_FINISH
sched_restore_yield
                pop   af
                CTX_EI
                ret

; k_task_enable: opt an already-registered managed window into task service.
; desc.task_worker becomes the compute-only callback; desc.proc stays on the
; root/compositor task for draw, input, and lifecycle. The app build must reserve
; #7F00-#7FFF.
k_task_enable
                CTX_DI
                ld    a,(CORE_CONTEXT_FOCUS)
                CTX_WINDOW_ENTRY
                push  hl
                ld    a,(CORE_CONTEXT_BANK)
                cp    (hl)                    ; only the calling app may enable itself
                jr    nz,sched_task_enable_fail
                ld    a,2
                ld    (CORE_CONTEXT_SNAPSHOT),a
                ld    hl,sched_task_start
                ld    (CORE_CONTEXT_STACK_DATA),hl
                pop   hl
                CTX_FLAGS_FROM_ENTRY
                bit   CORE_CONTEXT_MANAGED_BIT,(hl)                   ; only managed windows have a task_worker field
                jr    z,sched_task_enable_done
                bit   CORE_CONTEXT_RUN_BIT,(hl)
                jr    nz,sched_task_enable_done
                set   CORE_CONTEXT_RUN_BIT,(hl)                  ; publish only after snapshot is complete
                ld    hl,CORE_CONTEXT_RUNNABLE
                inc   (hl)
sched_task_enable_done
                CTX_EI
                ret
sched_task_enable_fail
                pop   hl
                CTX_EI
                ret

; A task-enabled managed descriptor's task_worker runs outside the compositor.
; Existing apps are not opted in: the normal WM continues to drive their proc
; exactly as it does in release builds. A worker is deliberately pure compute;
; kernel and paged-module work belongs in proc callbacks on the root task.
sched_task_start
sched_task_loop
                ld    a,(CORE_CONTEXT_CURRENT)
                CTX_WINDOW_ENTRY
                push  hl
                CTX_FLAGS_FROM_ENTRY
                ld    a,(hl)
                and   CORE_WORKER_READY
                cp    CORE_WORKER_READY
                pop   hl
                jr    nz,sched_task_sleep
                CTX_WORKER_POINTER
                ld    a,h
                or    l
                jr    z,sched_task_sleep
                xor   a
                ld    (CORE_CONTEXT_LOCK),a
                CTX_EI                              ; first-run snapshots inherit sched_yield's DI
                CTX_CALL_WORKER
                ld    a,1
                ld    (CORE_CONTEXT_LOCK),a
sched_task_sleep
                call  sched_yield
                jr    sched_task_loop
