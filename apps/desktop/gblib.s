;; gblib.s - C bindings for the GEOBENCH kernel API used by the desktop (see gb.h).
;;
;; Maps SDCC's __sdcccall(1) convention onto the kernel jump table:
;;   args:   first small args pack into A then L; the rest are pushed (adjacent
;;           u8 args pack two-per-word, an odd one as a lone byte). Callee-clean.
;;   return: unsigned char in A, 16-bit in DE.
;; Addresses mirror lib/gbapp.inc.
        .module gblib
        .globl  _gb_fill
        .globl  _gb_text
        .globl  _gb_icon
        .globl  _gb_frame
        .globl  _gb_run
        .globl  _gb_curshow
        .globl  _gb_curhide
        .globl  _gb_poll
        .globl  _gb_mx
        .globl  _gb_my

        .area   _BSS
sv_ret: .ds     2               ; saved return addr (fill/frame/icon wrappers)
mx_v:   .ds     1               ; cursor byte col from the last gb_poll
my_v:   .ds     1               ; cursor line from the last gb_poll

        .area   _CODE

;; void gb_fill(u8 col,u8 line,u8 w,u8 h,u8 pen);   filled rect -> GB_FILL
_gb_fill:
        ld      b, a
        ld      c, l
        pop     hl              ; ret addr
        ld      (sv_ret), hl
        pop     hl              ; L=w, H=h
        ld      d, l
        ld      e, h
        pop     hl              ; L=pen, H=overshoot
        dec     sp              ; reclaim the overshoot byte (only pen was ours)
        ld      a, l            ; A = pen
        call    0x8033          ; GB_FILL
        ld      hl, (sv_ret)
        jp      (hl)

;; void gb_frame(u8 col,u8 line,u8 w,u8 h,u8 pen);  rect outline -> GB_FRAME
_gb_frame:
        ld      b, a
        ld      c, l
        pop     hl
        ld      (sv_ret), hl
        pop     hl              ; L=w, H=h
        ld      d, l
        ld      e, h
        pop     hl              ; L=pen, H=overshoot
        dec     sp
        ld      a, l
        call    0x8021          ; GB_FRAME
        ld      hl, (sv_ret)
        jp      (hl)

;; void gb_text(u8 col,u8 line,const char *s);   A=col, L=line, [SP+2]=s
_gb_text:
        ld      b, a
        ld      c, l
        ld      d, #1           ; pen   = 1 (white)
        ld      e, #0           ; paper = 0 (backdrop)
        pop     hl              ; ret addr; SP -> s
        ex      (sp), hl        ; HL = s; ret addr into the arg slot
        call    0x800C          ; GB_TEXT
        ret

;; void gb_icon(u8 slot,u8 col,u8 line);
;;   A=slot, L=col, [SP+2]=line (lone byte). -> A=slot B=col C=line.
_gb_icon:
        ld      b, l            ; B = col (A still holds slot)
        pop     hl              ; ret addr
        ld      (sv_ret), hl
        pop     hl              ; L=line, H=overshoot
        dec     sp              ; reclaim the overshoot byte
        ld      c, l            ; C = line
        call    0x8030          ; GB_ICON (A=slot unchanged)
        ld      hl, (sv_ret)
        jp      (hl)

;; void gb_run(const char *name);   name in HL -> GB_RUN
_gb_run:
        jp      0x802D          ; GB_RUN

;; void gb_curshow(void); / gb_curhide(void);
_gb_curshow:
        jp      0x801B          ; GB_CURSHOW
_gb_curhide:
        jp      0x8024          ; GB_CURHIDE

;; unsigned char gb_poll(void);  -> flags in A; caches cursor col/line
_gb_poll:
        call    0x801E          ; GB_POLL -> B=col C=line D=flags
        ld      a, b
        ld      (mx_v), a
        ld      a, c
        ld      (my_v), a
        ld      a, d
        ret
_gb_mx:
        ld      a, (mx_v)
        ret
_gb_my:
        ld      a, (my_v)
        ret
