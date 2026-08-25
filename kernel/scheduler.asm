; kernel/scheduler.asm - fixed low-RAM scheduler image (issue #477).
;
; This file is assembled by scheduler_image.asm, not included in GBKERN. The
; preemptive desktop carries the resulting image in its app page and copies it
; to SCHED_BASE before entering the window-manager loop. CPC/PCW reserve
; #3C00-#3DFF; MSX uses fixed page-3 RAM at #C900.
;
; An active task continues to use the platform's existing fixed stack.  On a
; switch, only BOOT_SP-SP live bytes are copied into the owning app bank.  This
; avoids eight fixed-RAM stacks and keeps the stack visible while kernel APIs
; temporarily map PAGE_DATA over #4000-#7FFF.

TASK_SNAPSHOT   equ   #7F00        ; top 256 bytes of a participating app bank
TASK_STACK_LEN  equ   TASK_SNAPSHOT ; byte: saved stack length
TASK_STACK_DATA equ   TASK_SNAPSHOT+1
TASK_STACK_CAP  equ   255          ; includes interrupt-saved Z80 context
TASK_STACK_SIZE equ   256          ; length byte plus TASK_STACK_CAP payload
SCHED_QUANTUM_TICKS equ 6          ; six 300 Hz firmware ticks per 50 Hz slice

; #1450..#1480 is write-before-read kernel scratch. A real switch may use it
; as a tiny emergency stack only after SCHED_LOCK reaches zero. Interrupts
; arriving while kernel scratch is live return without switching.
SCHED_TMP_BOTTOM equ #1450
SCHED_TMP_TOP    equ   #1481

                org   SCHED_BASE
                jp    sched_init_impl
                jp    sched_yield
                jp    k_task_enable
                jp    sched_irq_uninstall

sched_init_impl
                xor   a
                ld    hl,SCHED_LOCK
                ld    de,SCHED_LOCK+1
                ld    bc,7
                ld    (hl),a
                ldir                          ; clear all eight scheduler bytes
                ld    a,#FF
                ld    (SCHED_CURRENT),a
                ld    a,1
                ld    (SCHED_LOCK),a          ; kernel owns execution at boot
                if PREEMPTIVE_CONTEXT
                ld    a,SCHED_QUANTUM_TICKS
                ld    (SCHED_QUANTUM),a
                endif
                ret

                if PREEMPTIVE_CONTEXT
; sched_switch_context: switch from one fully saved app context to the next
; runnable WM slot. The interrupt wrapper must have pushed, in order:
;
;   AF, BC, DE, HL, IX, IY, AF', BC', DE', HL'
;
; and CALLed this routine. The CALL return address is intentionally part of the
; copied stack. Restoring another snapshot and RET therefore continues in that
; task's copy of the yield/interrupt wrapper, which restores its registers and
; either returns from a yield or completes the pending firmware tick. I and the
; interrupt mode are kernel-owned, not task-local.
;
; Preconditions: SCHED_LOCK=0, SCHED_CURRENT names a runnable slot, the current
; app bank is mapped, and participating app layouts reserve #7F00-#7FFF.
; Clobbers every register (the wrapper has already saved them).
sched_switch_context
                ld    hl,0
                add   hl,sp
                ex    de,hl                   ; DE = old SP
                ld    hl,(BOOT_SP)
                or    a
                sbc   hl,de                   ; HL = live fixed-stack bytes
                ld    a,h
                or    a
                jp    nz,sched_switch_fault
                ld    a,l                     ; zero is impossible (CALL is live)
                or    a
                jp    z,sched_switch_fault
                ld    hl,SCHED_STACK_MAX      ; always retain the observed high-water mark
                cp    (hl)
                jr    c,sched_stack_sampled
                ld    (hl),a
sched_stack_sampled

                ld    sp,SCHED_TMP_TOP        ; kernel scratch is dead while unlocked
                push  de                      ; old SP, below scheduler call frames
                ld    (TASK_STACK_LEN),a      ; current app bank is still mapped
                ld    c,a
                ld    b,0
                ex    de,hl                   ; HL = old SP
                ld    de,TASK_STACK_DATA
                ldir

                ; Search the other seven slots round-robin. A runnable flag is
                ; set only after its initial snapshot has been constructed. Build
                ; the first entry pointer once and then advance it directly; the
                ; old wm_entry-per-candidate loop was needlessly quadratic.
                ld    a,(SCHED_CURRENT)
                inc   a
                and   WM_MAXWIN-1             ; WM_MAXWIN is deliberately a power of two
                ld    c,a
                call  sched_wm_entry
                ld    de,WM_FR_FLAGS
                add   hl,de
                ld    b,WM_MAXWIN-1
sched_next_slot
                ld    a,(hl)
                and   WM_TASK_RUNNABLE|1      ; both alive and runnable must be set
                cp    WM_TASK_RUNNABLE|1
                jr    z,sched_restore_slot
                inc   c
                ld    a,c
                cp    WM_MAXWIN
                jr    nc,sched_scan_wrap
                ld    de,WM_ESZ
                add   hl,de
sched_scan_count
                djnz  sched_next_slot

                ; No peer is runnable. The original fixed stack was never
                ; overwritten, so resume it without copying back.
sched_resume_old
                pop   hl
                ld    sp,hl
                ret
sched_scan_wrap
                ld    c,0
                ld    hl,WM_TABLE+WM_FR_FLAGS
                jr    sched_scan_count

sched_restore_slot
                ld    a,c
                push  af                      ; target slot above the saved old SP
                ld    de,-WM_FR_FLAGS
                add   hl,de                   ; flags pointer -> entry/page pointer
                ld    a,(hl)                  ; target app page from WM entry +0
                call  sched_bank_set
                ld    a,(TASK_STACK_LEN)
                or    a
                jr    z,sched_restore_fault
                ld    c,a
                ld    b,0
                ld    e,a
                ld    d,0
                ld    hl,(BOOT_SP)
                or    a
                sbc   hl,de                   ; target fixed-stack bottom
                push  hl                      ; keep target SP below mapper call frames
                ex    de,hl                   ; DE = fixed destination
                ld    hl,TASK_STACK_DATA
                ldir
                pop   hl                      ; target SP
                pop   af                      ; target slot
                ld    (SCHED_CURRENT),a
                pop   de                      ; discard old SP
                ld    sp,hl
                ret

sched_restore_fault
                ; The old bank was already replaced. Map the old task again,
                ; then resume its still-intact fixed stack.
                pop   af                      ; discard target slot above the saved old SP
                ld    a,(SCHED_CURRENT)
                call  sched_wm_entry
                ld    a,(hl)
                call  sched_bank_set
                ld    a,1
                ld    (SCHED_FAULT),a
                jr    sched_resume_old

sched_switch_fault
                ld    a,1
                ld    (SCHED_FAULT),a
                ret                             ; original SP is still active

; sched_yield: safe-point counterpart of the interrupt wrapper. Every task
; context has the same register image; only its continuation differs. A system
; or finite worker task uses this path, while a timer-preempted worker resumes
; through sched_irq_restore below.
sched_yield
                di
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
                ld    a,(SCHED_CURRENT)
                call  sched_wm_entry
                ld    de,WM_FR_FLAGS
                add   hl,de
                set   3,(hl)                   ; root becomes runnable with its first snapshot
                call  sched_switch_context
sched_yield_restore
                ld    a,1
                ld    (SCHED_LOCK),a
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
                ifndef PLATFORM_MSX
                ifndef PLATFORM_PCW
                ld    hl,SCHED_RESERVED
                bit   0,(hl)
                jr    z,sched_restore_yield
                res   0,(hl)
                pop   af
                jp    CPC_FW_IRQ               ; finish the IRQ in the restored task context
sched_restore_yield
                endif
                endif
                pop   af
                ei
                ret

; k_task_enable: opt an already-registered legacy WM window into task service.
; Its on_frame callback becomes a compute-only callback: it must not call kernel
; APIs or paint directly. on_repaint remains compositor-owned. The app build
; must reserve #7F00-#7FFF.
k_task_enable
                di
                ld    a,(WM_FOCUS)
                call  sched_wm_entry
                push  hl
                ld    a,(BANK_CUR)
                cp    (hl)                    ; only the calling app may enable itself
                jr    nz,sched_task_enable_fail
                ld    a,2
                ld    (TASK_STACK_LEN),a
                ld    hl,sched_task_start
                ld    (TASK_STACK_DATA),hl
                pop   hl
                ld    de,WM_FR_FLAGS
                add   hl,de
                bit   3,(hl)
                jr    nz,sched_task_enable_done
                set   3,(hl)                  ; publish only after snapshot is complete
                ld    hl,SCHED_RUNNABLE
                inc   (hl)
                if PREEMPTIVE_CONTEXT
                ifndef PLATFORM_MSX
                ifndef PLATFORM_PCW
                if PREEMPTIVE_TIMER
                ld    a,(hl)
                cp    2
                call  z,sched_irq_install     ; no frame event until a peer can run
                endif
                endif
                endif
                endif
sched_task_enable_done
                ei
                ret
sched_task_enable_fail
                pop   hl
                ei
                ret

; A task-enabled legacy on_frame runs outside the compositor. Existing apps are
; not opted in: the normal WM continues to drive their callbacks exactly as it
; does in release builds. A worker is deliberately a pure compute function;
; kernel and paged-module work belongs in compositor callbacks on the root task.
sched_task_start
sched_task_loop
                ld    a,(SCHED_CURRENT)
                call  sched_wm_entry
                push  hl
                ld    de,WM_FR_FLAGS
                add   hl,de
                ld    a,(hl)
                and   WM_TASK_RUNNABLE|1
                cp    WM_TASK_RUNNABLE|1
                pop   hl
                jr    nz,sched_task_sleep
                ld    de,WM_FR_FRAME
                add   hl,de
                ld    a,(hl)
                inc   hl
                ld    h,(hl)
                ld    l,a
                ld    a,h
                or    l
                jr    z,sched_task_sleep
                xor   a
                ld    (SCHED_LOCK),a
                ei                              ; first-run snapshots inherit sched_yield's DI
                call  sched_md_call
                ld    a,1
                ld    (SCHED_LOCK),a
sched_task_sleep
                call  sched_yield
                jr    sched_task_loop

                ifndef PLATFORM_MSX
                ifndef PLATFORM_PCW
; CPC IM 1 enters through writable RAM at #0038. The scheduler runs before the
; firmware tick. Fast paths tail-call B941 immediately. A context switch marks
; the shared restore path, which tail-calls B941 after the target registers and
; stack are active. Firmware therefore always sees its native interrupt stack
; contract and returns directly to the selected task. External interrupts skip
; scheduler work because B941 owns a different stack contract for them.
CPC_IRQ_VECTOR  equ #0038
CPC_FW_IRQ      equ #B941

sched_irq_install
                ld    hl,sched_irq_vector
                jr    sched_irq_set_vector

; Restore the standard firmware vector before returning to BASIC/DOS.
sched_irq_uninstall
                ld    hl,CPC_FW_IRQ
sched_irq_set_vector
                di
                ld    a,#C3
                ld    (CPC_IRQ_VECTOR),a
                ld    (CPC_IRQ_VECTOR+1),hl
                ret

sched_irq_vector
                ex    af,af'
                jr    nc,sched_irq_normal
                ex    af,af'                  ; restore app AF and leave firmware's stack untouched
                jp    CPC_FW_IRQ
sched_irq_normal
                ex    af,af'
sched_irq_body
                push  af
                ld    a,(SCHED_CURRENT)
                or    a
                jr    nz,sched_irq_worker
                pop   af
                jp    CPC_FW_IRQ
sched_irq_worker
                if !PREEMPTIVE_SWITCH
                jp    sched_irq_fast          ; diagnostic: prove the firmware trampoline alone
                endif
                ld    a,(SCHED_QUANTUM)
                dec   a
                ld    (SCHED_QUANTUM),a
                jr    nz,sched_irq_fast
                ld    a,SCHED_QUANTUM_TICKS
                ld    (SCHED_QUANTUM),a
                ld    a,(SCHED_LOCK)
                or    a
                jr    z,sched_irq_switch
sched_irq_fast
                pop   af
                jp    CPC_FW_IRQ

sched_irq_switch
                inc   a                       ; A is zero after the SCHED_LOCK test
                ld    (SCHED_RESERVED),a      ; common restore must complete this firmware tick
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
                ld    hl,21                   ; interrupted PC high byte after ten PUSHes
                add   hl,sp
                ld    a,(hl)
                cp    #40                     ; only code in the mapped app bank is preemptible
                jr    c,sched_irq_defer
                cp    #80
                jr    nc,sched_irq_defer
                ld    a,(SCHED_CURRENT)
                cp    #FF
                jr    z,sched_irq_defer
                call  sched_wm_entry
                ld    a,(BANK_CUR)
                cp    (hl)                    ; reject kernel modules mapped over the app bank
                jr    nz,sched_irq_defer
                call  sched_switch_context
sched_irq_restore
                xor   a
                ld    (SCHED_LOCK),a
                jp    sched_context_restore
sched_irq_defer
                jp    sched_context_restore
                else
sched_irq_uninstall
                ret
                endif
                else
sched_irq_uninstall
                ret
                endif

; Fixed-address scheduler helpers. They duplicate only the small pieces that
; cannot be called through profile-dependent resident labels.
sched_wm_entry
                ld    hl,WM_TABLE
                or    a
                ret   z
                ld    b,a
                ld    de,WM_ESZ
sched_we_add
                add   hl,de
                djnz  sched_we_add
                ret

sched_md_call
                jp    (hl)

sched_bank_set
                ld    (BANK_CUR),a
                ifdef PLATFORM_MSX
                push  af
                push  hl
                push  de
                ld    hl,(MSX_PUTP1)
                call  sched_md_call
                pop   de
                pop   hl
                pop   af
                ret
                else
                ifdef PLATFORM_PCW
                out   (PCW_BANK1),a
                else
                ld    bc,#7F00
                out   (c),a
                endif
                ret
                endif

                endif                         ; PREEMPTIVE_CONTEXT

sched_image_end
                assert sched_image_end-SCHED_BASE<=512,"scheduler exceeds fixed 512-byte slot"
