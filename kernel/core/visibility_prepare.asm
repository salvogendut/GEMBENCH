; Shared existing visible-region/priority policy (#71).
; Provider obligations: visibility_contract.inc.
; Capture one immutable source-damage rectangle for the complete z pass, then
; refresh visibility. Every surface iterator restarts from this damage instead
; of inheriting the last fragment emitted for the preceding surface.
sched_compositor_prepare
                ld    hl,CORE_CLIP_X
                ld    de,CORE_COMPOSITOR_DAMAGE
                ld    bc,4
                ldir
                ld    hl,CORE_COMPOSITOR_EXTRA_PENDING
                ld    a,(hl)
                inc   hl
                ld    (hl),a
                dec   hl
                ld    (hl),0
                jp    sched_visibility_refresh
