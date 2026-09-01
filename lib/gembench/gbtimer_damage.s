;; MSX2 M8 worker-side background timer damage publication.
;;
;; This leaf is deliberately kernel-free and reentrant with the root task. The
;; four rectangle bytes are written before the pending byte, so a preemption at
;; any instruction exposes either the previous complete request or no request.
        .module gbtimer_damage
        .globl  _gb_timer_damage

GB_TIMER_OWNER   = 0x3FF9
GB_TIMER_RECT    = 0x3FFA
GB_TIMER_GEN     = 0x3FFE
WM_FULLSCREEN   = 0x130A
SCHED_CURRENT    = 0x1342
MSX_WIN_GEN      = 0xC358

        .area   _CODE

;; void gb_timer_damage(u8 x, u8 y, u8 w, u8 h)
;; SDCC: x=A, y=L, packed w/h word at SP+2. Do not use the shared gblib sv_ret:
;; a worker can be preempted while the root task is using another trampoline.
_gb_timer_damage::
        push    ix
        ld      ix, #0
        add     ix, sp
        ld      c, a
        ld      a, (WM_FULLSCREEN)
        or      a
        jr      nz, timer_done
        ld      a, (GB_TIMER_OWNER)
        or      a
        jr      nz, timer_done
        ld      a, c
        ld      (GB_TIMER_RECT+0), a
        ld      a, l
        ld      (GB_TIMER_RECT+1), a
        ld      a, 4(ix)
        or      a
        jr      z, timer_bad_rect
        ld      (GB_TIMER_RECT+2), a
        ld      a, 5(ix)
        or      a
        jr      z, timer_bad_rect
        ld      (GB_TIMER_RECT+3), a
        ld      a, (SCHED_CURRENT)
        cp      #8
        jr      nc, timer_bad_rect
        ld      b, a
        ld      hl, #MSX_WIN_GEN
        add     a, l
        ld      l, a
        ld      a, (hl)
        ld      (GB_TIMER_GEN), a
        ld      a, b
        inc     a
        ld      (GB_TIMER_OWNER), a     ; publish generation-tagged owner last
timer_bad_rect:
timer_done:
        pop     ix
        pop     hl                      ; callee-cleans packed w/h word
        inc     sp
        inc     sp
        jp      (hl)
