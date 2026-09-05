;; Native worker publisher contract (#75), SDAS/SDCC call(1).
;; A=x, L=y, packed w/h on stack; preserves IX, callee-cleans two bytes.
;; No kernel call or shared return scratch; fixed state must survive preemption.
;; CURRENT is a trusted zero-based worker window slot, not an owner ID. Call
;; only from that window's worker, never the root. No new owner validation.
;; Reject fullscreen/busy, zero width/height, invalid slot. RECT/GEN before OWNER
;; retains existing publication order. Invalid input may alter unpublished
;; rectangle bytes. No extra geometry check, DI or multi-producer atomicity is
;; introduced. The scheduler/provider must preserve the existing single-writer
;; protocol, including root/worker mailbox serialization; slots match collector.
;; Bit 7 belongs to active consumption. No native addresses in shared code.
;; Provider must prove complete state non-overlap and module/stack/IRQ safety.
        .iflt CORE_TIMER_WINDOW_MAX-1
        .error 1
        .endif
        .ifgt CORE_TIMER_WINDOW_MAX-127
        .error 1
        .endif

;; CORE_TIMER_OWNER fixed span
        .iflt CORE_TIMER_OWNER
        .error 1
        .endif
        .ifgt CORE_TIMER_OWNER+1-65536
        .error 1
        .endif
        .iflt CORE_TIMER_OWNER-0x8000
        .ifgt CORE_TIMER_OWNER+1-0x4000
        .error 1
        .endif
        .endif

;; CORE_TIMER_RECT fixed span
        .iflt CORE_TIMER_RECT
        .error 1
        .endif
        .ifgt CORE_TIMER_RECT+4-65536
        .error 1
        .endif
        .iflt CORE_TIMER_RECT-0x8000
        .ifgt CORE_TIMER_RECT+4-0x4000
        .error 1
        .endif
        .endif

;; CORE_TIMER_GEN fixed span
        .iflt CORE_TIMER_GEN
        .error 1
        .endif
        .ifgt CORE_TIMER_GEN+1-65536
        .error 1
        .endif
        .iflt CORE_TIMER_GEN-0x8000
        .ifgt CORE_TIMER_GEN+1-0x4000
        .error 1
        .endif
        .endif

;; CORE_TIMER_FULLSCREEN fixed span
        .iflt CORE_TIMER_FULLSCREEN
        .error 1
        .endif
        .ifgt CORE_TIMER_FULLSCREEN+1-65536
        .error 1
        .endif
        .iflt CORE_TIMER_FULLSCREEN-0x8000
        .ifgt CORE_TIMER_FULLSCREEN+1-0x4000
        .error 1
        .endif
        .endif

;; CORE_TIMER_CURRENT fixed span
        .iflt CORE_TIMER_CURRENT
        .error 1
        .endif
        .ifgt CORE_TIMER_CURRENT+1-65536
        .error 1
        .endif
        .iflt CORE_TIMER_CURRENT-0x8000
        .ifgt CORE_TIMER_CURRENT+1-0x4000
        .error 1
        .endif
        .endif

;; CORE_TIMER_WIN_GEN fixed span
        .iflt CORE_TIMER_WIN_GEN
        .error 1
        .endif
        .ifgt CORE_TIMER_WIN_GEN+CORE_TIMER_WINDOW_MAX-65536
        .error 1
        .endif
        .iflt CORE_TIMER_WIN_GEN-0x8000
        .ifgt CORE_TIMER_WIN_GEN+CORE_TIMER_WINDOW_MAX-0x4000
        .error 1
        .endif
        .endif

        .ifgt (CORE_TIMER_WIN_GEN & 0xFF)+CORE_TIMER_WINDOW_MAX-256
        .error 1
        .endif
