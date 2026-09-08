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
                ifdef CORE_VIS_TIMER_OWNER
                ; A validated content-only consume cannot change stacking or
                ; ownership. Keep its exact damage sources/region iterator,
                ; but do not reclassify every surface for each timer component.
                ; Queued requests (bit 7 clear) still refresh ordinary damage.
                ld    a,(CORE_VIS_TIMER_OWNER)
                bit   7,a
                ret   nz
                endif
                jp    sched_visibility_refresh
