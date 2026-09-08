;; Shared timer collector contract, SDAS dialect (#73).
;;
;; App-linked root hook, with kernel/scheduler lock held. Fixed state survives
;; app banking; not called from workers. Existing producers serialize writes:
;; rectangle/generation first, slot+1 last, and never overwrite pending/active
;; owner. One coalesced mailbox, not a FIFO or per-window timer allocation.
;; Window generations and attachment/visibility tables are initialized before
;; publication. IDs 1..WINDOW_MAX are pending; bit 7 marks active consumption.
;;
;; Validate slot, window generation and attachment before use; hidden windows
;; are acknowledged without painting. Fullscreen/stale entries are cleared.
;; TEST_VISIBLE checks the component against current z-order; it may install
;; a fragment, so reload the immutable mailbox rectangle before REPAINT.
;; Active identity remains published across callbacks to reject recursive
;; collector entry and associate component painting with its source.
;; A dropped component records generation before slot. Finish clears owner.
;; No fairness, timer cadence, lifetime-generation redesign or new normalization.
;;
;; SET_DAMAGE: BC=y:x, DE=h:w -> native WM clip; TEST_VISIBLE: A=slot -> A=0/Z
;; if hidden, nonzero/NZ if visible; REPAINT consumes prepared damage. Hooks must
;; retain mailbox and table lifetimes and honor serialized compositor behavior.
;; Called callbacks may inspect active owner but must not overwrite this mailbox.
;; Code remains in the mapped root app; hooks must restore that bank on return.
;;
;; Fixed-span and indexed-page checks are local; provider must prove non-overlap
;; with framebuffer, ROM, other state and stacks. Assembly fixtures do not prove
;; concurrency or execute a CPC provider. Every .error below is a build failure.
        .iflt CORE_TIMER_WINDOW_MAX-1
        .error 1
        .endif
        .ifgt CORE_TIMER_WINDOW_MAX-127
        .error 1
        .endif

;; CORE_TIMER_OWNER: fixed, complete span
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

;; CORE_TIMER_RECT: fixed, complete span
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

;; CORE_TIMER_GEN: fixed, complete span
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

;; CORE_TIMER_DROPPED: fixed, complete span
        .iflt CORE_TIMER_DROPPED
        .error 1
        .endif
        .ifgt CORE_TIMER_DROPPED+1-65536
        .error 1
        .endif
        .iflt CORE_TIMER_DROPPED-0x8000
        .ifgt CORE_TIMER_DROPPED+1-0x4000
        .error 1
        .endif
        .endif

;; CORE_TIMER_DROPPED_GEN: fixed, complete span
        .iflt CORE_TIMER_DROPPED_GEN
        .error 1
        .endif
        .ifgt CORE_TIMER_DROPPED_GEN+1-65536
        .error 1
        .endif
        .iflt CORE_TIMER_DROPPED_GEN-0x8000
        .ifgt CORE_TIMER_DROPPED_GEN+1-0x4000
        .error 1
        .endif
        .endif

;; CORE_TIMER_FULLSCREEN: fixed, complete span
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

;; CORE_TIMER_WIN_OWNER: fixed, complete span
        .iflt CORE_TIMER_WIN_OWNER
        .error 1
        .endif
        .ifgt CORE_TIMER_WIN_OWNER+CORE_TIMER_WINDOW_MAX-65536
        .error 1
        .endif
        .iflt CORE_TIMER_WIN_OWNER-0x8000
        .ifgt CORE_TIMER_WIN_OWNER+CORE_TIMER_WINDOW_MAX-0x4000
        .error 1
        .endif
        .endif

;; CORE_TIMER_WIN_GEN: fixed, complete span
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

;; CORE_TIMER_VISIBILITY: fixed, complete span
        .iflt CORE_TIMER_VISIBILITY
        .error 1
        .endif
        .ifgt CORE_TIMER_VISIBILITY+CORE_TIMER_WINDOW_MAX-65536
        .error 1
        .endif
        .iflt CORE_TIMER_VISIBILITY-0x8000
        .ifgt CORE_TIMER_VISIBILITY+CORE_TIMER_WINDOW_MAX-0x4000
        .error 1
        .endif
        .endif

        .ifgt (CORE_TIMER_WIN_OWNER & 0xff)+CORE_TIMER_WINDOW_MAX-256
        .error 1
        .endif

        .ifgt (CORE_TIMER_WIN_GEN & 0xff)+CORE_TIMER_WINDOW_MAX-256
        .error 1
        .endif

        .ifgt (CORE_TIMER_VISIBILITY & 0xff)+CORE_TIMER_WINDOW_MAX-256
        .error 1
        .endif
