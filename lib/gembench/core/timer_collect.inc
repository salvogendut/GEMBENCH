;; Shared existing root-side timer collection policy (#73), SDAS dialect.
;; Provider contract: core/timer_collect_contract.inc. No worker-side drawing.
_gb_timer_collect::
        ld      a, (CORE_TIMER_OWNER)
        or      a
        ret     z
        ret     m                       ; recursive Desktop draw during consume
        dec     a
        cp      #CORE_TIMER_WINDOW_MAX
        jr      nc, timer_stale
        ld      c, a                    ; C = source window slot
        ld      hl, #CORE_TIMER_WIN_GEN
        add     a, l
        ld      l, a
        ld      a, (CORE_TIMER_GEN)
        cp      (hl)
        jr      nz, timer_stale
        ld      hl, #CORE_TIMER_WIN_OWNER
        ld      a, c
        add     a, l
        ld      l, a
        ld      a, (hl)                 ; detached/dead slots have no owner
        or      a
        jr      z, timer_stale
        ld      hl, #CORE_TIMER_VISIBILITY  ; M9: a completely occluded timer surface
        ld      a, c                    ; has no effective damage. Drop a request
        add     a, l                    ; queued before it was parked instead of
        ld      l, a                    ; repainting the foreground window over it.
        ld      a, (hl)
        or      a
        jr      z, timer_occluded
        ld      a, (CORE_TIMER_FULLSCREEN)
        or      a
        jr      nz, timer_stale
        ld      bc, (CORE_TIMER_RECT+0)
        ld      de, (CORE_TIMER_RECT+2)
        call    TIMER_SET_DAMAGE
        ld      a, (CORE_TIMER_OWNER)
        dec     a
        call    TIMER_TEST_VISIBLE       ; effective damage after higher opaque windows
        or      a
        jr      z, timer_occluded
        ld      a, (CORE_TIMER_OWNER)
        or      #0x80
        ld      (CORE_TIMER_OWNER), a     ; retain active source through callbacks
        ld      bc, (CORE_TIMER_RECT+0)   ; region test installed a fragment: restore
        ld      de, (CORE_TIMER_RECT+2)   ; the immutable component damage for the pass
        call    TIMER_SET_DAMAGE
        call    TIMER_REPAINT
        xor     a
        ld      (CORE_TIMER_OWNER), a
        ret
timer_occluded:
        ld      a, (CORE_TIMER_GEN)
        ld      (CORE_TIMER_DROPPED_GEN), a
        ld      a, (CORE_TIMER_OWNER)     ; acknowledge a valid but invisible component
        ld      (CORE_TIMER_DROPPED), a   ; so its worker can advance to another component
        jr      timer_stale
timer_stale:
        xor     a
        ld      (CORE_TIMER_OWNER), a
        ret
