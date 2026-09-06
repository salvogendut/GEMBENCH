; CPC context hooks: fixed memory, owned IM1 and no firmware chaining (#77).
CORE_CONTEXT_LOCK equ SCHED_LOCK
CORE_CONTEXT_IRQ_PENDING equ SCHED_RESERVED
CORE_CONTEXT_CURRENT equ SCHED_CURRENT
CORE_CONTEXT_QUANTUM equ SCHED_QUANTUM
CORE_CONTEXT_RUNNABLE equ SCHED_RUNNABLE
CORE_CONTEXT_LAST equ SCHED_FLAGS
CORE_CONTEXT_STACK_MAX equ SCHED_STACK_MAX
CORE_CONTEXT_FAULT equ SCHED_FAULT
CORE_CONTEXT_BOOT_SP equ BOOT_SP
CORE_CONTEXT_BANK equ BANK_CUR
CORE_CONTEXT_FOCUS equ WM_FOCUS
CORE_CONTEXT_TMP_BOTTOM equ CPC_TMP_STACK
CORE_CONTEXT_TMP_TOP equ CPC_TMP_TOP
CORE_CONTEXT_SNAPSHOT equ #7F00
CORE_CONTEXT_STACK_DATA equ CORE_CONTEXT_SNAPSHOT+1
CORE_CONTEXT_STACK_CAP equ 255
CORE_CONTEXT_APP_FIRST_HI equ #40
CORE_CONTEXT_APP_END_HI equ #80
CORE_CONTEXT_QUANTUM_TICKS equ 6
CORE_CONTEXT_TIMER equ 1
CORE_CONTEXT_SWITCH equ 1
CORE_CONTEXT_RUN_BIT equ 3
CORE_CONTEXT_MANAGED_BIT equ 1
CORE_CONTEXT_CODE_BASE equ CPC_SCHED_BASE
CORE_CONTEXT_CODE_END equ CPC_SCHED_END
                macro CTX_DI
                di
                mend
                macro CTX_EI
                ei
                mend
                macro CTX_IRQ_INSTALL
                call sched_irq_install
                mend
                macro CTX_IRQ_FINISH
                pop af
                ei
                reti
                mend
                macro CTX_WINDOW_ENTRY
                call sched_wm_entry
                mend
                macro CTX_FLAGS_FROM_ENTRY
                ld de,WM_FR_FLAGS
                add hl,de
                mend
                macro CTX_ENTRY_FROM_FLAGS
                ld de,-WM_FR_FLAGS
                add hl,de
                mend
                macro CTX_WORKER_POINTER
                ld de,WM_FR_FRAME
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ex de,hl
                ld de,10                    ; managed descriptor's task_worker
                add hl,de
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                mend
                macro CTX_CALL_WORKER
                call sched_md_call
                mend
                macro CTX_MAP_BANK
                call sched_bank_set
                mend
                macro CTX_SAMPLE_STACK
                mend
                macro CTX_SAMPLE_FAULT
                mend
