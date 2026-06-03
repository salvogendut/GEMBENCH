;; gblib.s - C bindings for the GEOBENCH kernel API used by FILEMGR (see gb.h).
;;
;; Maps SDCC's __sdcccall(1) convention onto the kernel jump table:
;;   args:   first small args pack into A then L; the rest are pushed (adjacent
;;           u8 args pack two-per-word). Callee-clean (no caller cleanup).
;;   return: unsigned char in A, 16-bit (int/pointer) in DE.
;; Addresses mirror lib/gbapp.inc.
        .module gblib
        .globl  _gb_window
        .globl  _gb_text
        .globl  _gb_curshow
        .globl  _gb_curhide
        .globl  _gb_poll
        .globl  _gb_mx
        .globl  _gb_my
        .globl  _gb_dir1
        .globl  _gb_dirn
        .globl  _gb_blite
        .globl  _gb_frame
        .globl  _gb_launch

        .area   _BSS
gw_ret: .ds     2               ; saved return addr (gb_window)
gf_ret: .ds     2               ; saved return addr (gb_frame)
mx_v:   .ds     1               ; cursor byte col from the last gb_poll
my_v:   .ds     1               ; cursor line from the last gb_poll

        .area   _CODE

;; void gb_window(u8 col, u8 line, u8 w, u8 h, const char *title);
;;   A=col, L=line; stack [ret][w,h][title]. -> B=x C=y D=w E=h HL=title.
_gb_window:
        ld      b, a
        ld      c, l
        pop     hl              ; ret addr
        ld      (gw_ret), hl
        pop     hl              ; L=w, H=h
        ld      d, l
        ld      e, h
        pop     hl              ; title
        call    0x800F          ; GB_WINDOW
        ld      hl, (gw_ret)
        jp      (hl)

;; void gb_text(u8 col, u8 line, const char *s);   A=col, L=line, [SP+2]=s
_gb_text:
        ld      b, a
        ld      c, l
        ld      d, #1           ; pen   = 1 (white)
        ld      e, #0           ; paper = 0 (window fill)
        pop     hl              ; ret addr; SP -> s
        ex      (sp), hl        ; HL = s; ret addr into the arg slot
        call    0x800C          ; GB_TEXT
        ret

;; void gb_curshow(void);
_gb_curshow:
        jp      0x801B          ; GB_CURSHOW

;; void gb_curhide(void);
_gb_curhide:
        jp      0x8024          ; GB_CURHIDE

;; unsigned char gb_poll(void);  -> flags in A; caches cursor col/line for gb_mx/gb_my
_gb_poll:
        call    0x801E          ; GB_POLL -> B=col C=line D=flags
        ld      a, b
        ld      (mx_v), a
        ld      a, c
        ld      (my_v), a
        ld      a, d
        ret
;; unsigned char gb_mx(void); / gb_my(void);   last poll's cursor col / line
_gb_mx:
        ld      a, (mx_v)
        ret
_gb_my:
        ld      a, (my_v)
        ret

;; char *gb_dir1(void); / char *gb_dirn(void);  -> name ptr in DE, or 0 at end
_gb_dir1:
        call    0x8012          ; GB_DIR1 -> CF + HL=name, NC = empty
        jr      nc, gd_none
        ex      de, hl
        ret
_gb_dirn:
        call    0x8015          ; GB_DIRN -> CF + HL=name, NC = end
        jr      nc, gd_none
        ex      de, hl
        ret
gd_none:
        ld      de, #0
        ret

;; void gb_blite(u8 col, u8 line);   A=col, L=line -> B=col C=line
_gb_blite:
        ld      b, a
        ld      c, l
        jp      0x8018          ; GB_BLITE

;; void gb_frame(u8 col, u8 line, u8 w, u8 h, u8 pen);
;;   A=col, L=line; stack [ret][w(1 byte)][h,pen(word)]. -> B=x C=y D=w E=h A=pen.
;;   w is a lone pushed byte, so after popping w+h the pen sits 1 byte deep: read
;;   it with an extra pop and dec sp to reclaim the over-read byte (callee-clean).
_gb_frame:
        ld      b, a
        ld      c, l
        pop     hl              ; ret addr
        ld      (gf_ret), hl
        pop     hl              ; L=w, H=h
        ld      d, l
        ld      e, h
        pop     hl              ; L=pen, H=overshoot byte
        dec     sp              ; give back the overshoot (only pen was ours)
        ld      a, l            ; A = pen
        call    0x8021          ; GB_FRAME
        ld      hl, (gf_ret)
        jp      (hl)

;; void gb_launch(void);   launch the current dir entry; returns when it quits
_gb_launch:
        jp      0x8027          ; GB_LAUNCH
