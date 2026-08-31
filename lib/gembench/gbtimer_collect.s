;; MSX2 M8 root-side background timer damage collector.
;;
;; Desktop calls this from its global bar hook. The worker never draws: this
;; collector snapshots the complete mailbox while it remains published,
;; validates its live generation-tagged owner, marks that owner active through
;; the ordinary bottom-up compositor, then clears it after occluders are safe.
        .module gbtimer_collect
        .globl  _gb_timer_collect

GB_TIMER_OWNER   = 0xC3CA
GB_TIMER_RECT    = 0xC3CB
GB_TIMER_GEN     = 0xC3CF
GB_TIMER_DROPPED = 0xC1EC
WM_FULLSCREEN   = 0x130A
MSX_WIN_OWNER   = 0xC2D0
MSX_WIN_GEN     = 0xC358
MSX_WM_VISIBILITY = 0xC1C0
GB_RESTPAR       = 0x8057
GB_WMDAMAGE      = 0x80B4
GB_DAMAGE_VISIBLE = 0xC915

        .area   _CODE

_gb_timer_collect::
        ld      a, (GB_TIMER_OWNER)
        or      a
        ret     z
        ret     m                       ; recursive Desktop draw during consume
        dec     a
        cp      #8
        jr      nc, timer_stale
        ld      c, a                    ; C = source window slot
        ld      hl, #MSX_WIN_GEN
        add     a, l
        ld      l, a
        ld      a, (GB_TIMER_GEN)
        cp      (hl)
        jr      nz, timer_stale
        ld      hl, #MSX_WIN_OWNER
        ld      a, c
        add     a, l
        ld      l, a
        ld      a, (hl)                 ; detached/dead slots have no owner
        or      a
        jr      z, timer_stale
        ld      hl, #MSX_WM_VISIBILITY  ; M9: a completely occluded timer surface
        ld      a, c                    ; has no effective damage. Drop a request
        add     a, l                    ; queued before it was parked instead of
        ld      l, a                    ; repainting the foreground window over it.
        ld      a, (hl)
        or      a
        jr      z, timer_occluded
        ld      a, (WM_FULLSCREEN)
        or      a
        jr      nz, timer_stale
        ld      bc, (GB_TIMER_RECT+0)
        ld      de, (GB_TIMER_RECT+2)
        call    GB_WMDAMAGE
        ld      a, (GB_TIMER_OWNER)
        dec     a
        call    GB_DAMAGE_VISIBLE       ; effective damage after higher opaque windows
        or      a
        jr      z, timer_occluded
        ld      a, (GB_TIMER_OWNER)
        or      #0x80
        ld      (GB_TIMER_OWNER), a     ; retain active source through callbacks
        ld      bc, (GB_TIMER_RECT+0)   ; region test installed a fragment: restore
        ld      de, (GB_TIMER_RECT+2)   ; the immutable component damage for the pass
        call    GB_WMDAMAGE
        call    GB_RESTPAR
        xor     a
        ld      (GB_TIMER_OWNER), a
        ret
timer_occluded:
        ld      a, (GB_TIMER_OWNER)     ; acknowledge a valid but invisible component
        ld      (GB_TIMER_DROPPED), a   ; so its worker can advance to another component
        jr      timer_stale
timer_stale:
        xor     a
        ld      (GB_TIMER_OWNER), a
        ret
