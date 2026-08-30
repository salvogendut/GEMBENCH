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
WM_FULLSCREEN   = 0x130A
MSX_WIN_OWNER   = 0xC2D0
MSX_WIN_GEN     = 0xC358
GB_RESTPAR       = 0x8057
GB_WMDAMAGE      = 0x80B4

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
        ld      a, c
        add     a, #0x81
        ld      (GB_TIMER_OWNER), a     ; retain active source through callbacks
        ld      bc, (GB_TIMER_RECT+0)   ; snapshot while owner remains published
        ld      de, (GB_TIMER_RECT+2)   ; and workers therefore leave it untouched
        ld      a, (WM_FULLSCREEN)
        or      a
        jr      nz, timer_stale
        call    GB_WMDAMAGE
        call    GB_RESTPAR
        xor     a
        ld      (GB_TIMER_OWNER), a
        ret
timer_stale:
        xor     a
        ld      (GB_TIMER_OWNER), a
        ret
