; IRQ service owns a guarded stack only while sampling time. Restore the raw
; interrupted-PC stack and ALL registers before entering shared dispatch.
; No firmware, display/AY access, bank change or nested maskable interrupts.
cpc_irq_entry
                ld (CPC_IRQ_OLD_SP),sp
                ld sp,CPC_IRQ_TOP
                push af
                push hl
                ld hl,(CPC_IRQ_COUNT)
                inc hl
                ld (CPC_IRQ_COUNT),hl
                ld hl,(CPC_HW_TICKS)
                inc hl
                ld (CPC_HW_TICKS),hl
                ld hl,(CPC_HW_DIVIDER)
                dec hl
                ld (CPC_HW_DIVIDER),hl
                ld a,h
                or l
                jr nz,cpc_irq_tick_done
                ld hl,300
                ld (CPC_HW_DIVIDER),hl
                ld hl,(CPC_HW_SECONDS)
                inc hl
                ld (CPC_HW_SECONDS),hl
cpc_irq_tick_done
                pop hl
                pop af
                ld sp,(CPC_IRQ_OLD_SP)
                jp sched_irq_body

; Atomic software tick read. IFF preserved; A/HL/flags volatile.
; The CPC has no mandatory RTC; ticks lost during DI/bus hold are not recovered.
cpc_ticks_read
                ld a,i
                push af
                di
                ld hl,(CPC_HW_TICKS)
                pop af
                ret po
                ei
                ret
