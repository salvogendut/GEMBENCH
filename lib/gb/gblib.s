;; gblib.s - shared C bindings for the GEOBENCH kernel API (see gb.h).
;;
;; Every GEOBENCH C app links this one libgb. Each function is a thin trampoline
;; mapping SDCC's __sdcccall(1) convention onto the kernel jump table:
;;   args:   first small args pack into A then L; the rest are pushed (adjacent
;;           u8 args pack two-per-word, an odd one as a lone byte). Callee-clean
;;           (no caller cleanup), so wrappers consume their pushed args.
;;   return: unsigned char in A, 16-bit (int/pointer) in DE.
;; The jump-table addresses mirror lib/gbapp.inc.
        .module gblib
        .globl  _gb_cls
        .globl  _gb_text
        .globl  _gb_window
        .globl  _gb_fill
        .globl  _gb_frame
        .globl  _gb_icon
        .globl  _gb_blite
        .globl  _gb_curshow
        .globl  _gb_curhide
        .globl  _gb_poll
        .globl  _gb_mx
        .globl  _gb_my
        .globl  _gb_dir1
        .globl  _gb_dirn
        .globl  _gb_launch
        .globl  _gb_run
        .globl  _gb_fs_load
        .globl  _gb_fs_save
        .globl  _gb_getkey
        .globl  _gb_vsync
        .globl  _gb_on_event

        .area   _BSS
sv_ret: .ds     2               ; saved return addr for the multi-pop wrappers
mx_v:   .ds     1               ; cursor byte col cached by the last gb_poll
my_v:   .ds     1               ; cursor line cached by the last gb_poll

        .area   _CODE

;; void gb_cls(void);
_gb_cls:
        jp      0x8003          ; GB_CLS

;; void gb_text(u8 col, u8 line, const char *s);
;;   A=col, L=line, [SP+2]=s. pop/ex (sp),hl loads HL=s and collapses the pushed
;;   arg into the return slot so a plain ret cleans the stack.
_gb_text:
        ld      b, a
        ld      c, l
        ld      d, #1           ; pen   = 1 (white)
        ld      e, #0           ; paper = 0
        pop     hl
        ex      (sp), hl
        call    0x800C          ; GB_TEXT
        ret

;; void gb_window(u8 col, u8 line, u8 w, u8 h, const char *title);
;;   A=col, L=line; stack [ret][w,h][title]. -> B=x C=y D=w E=h HL=title.
_gb_window:
        ld      b, a
        ld      c, l
        pop     hl
        ld      (sv_ret), hl
        pop     hl              ; L=w, H=h
        ld      d, l
        ld      e, h
        pop     hl              ; title
        call    0x800F          ; GB_WINDOW
        ld      hl, (sv_ret)
        jp      (hl)

;; void gb_fill(u8 col, u8 line, u8 w, u8 h, u8 pen);    -> GB_FILL
;; void gb_frame(u8 col, u8 line, u8 w, u8 h, u8 pen);   -> GB_FRAME
;;   A=col, L=line; stack [ret][w(lone byte)][h,pen(word)]. w is an odd pushed
;;   byte, so the pen sits 1 byte deep: read it with an extra pop + dec sp.
_gb_fill:
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
        call    0x8033          ; GB_FILL
        ld      hl, (sv_ret)
        jp      (hl)
_gb_frame:
        ld      b, a
        ld      c, l
        pop     hl
        ld      (sv_ret), hl
        pop     hl
        ld      d, l
        ld      e, h
        pop     hl
        dec     sp
        ld      a, l
        call    0x8021          ; GB_FRAME
        ld      hl, (sv_ret)
        jp      (hl)

;; void gb_icon(u8 slot, u8 col, u8 line);
;;   A=slot, L=col, [SP+2]=line (lone byte). -> A=slot B=col C=line.
_gb_icon:
        ld      b, l            ; B = col (A still holds slot)
        pop     hl
        ld      (sv_ret), hl
        pop     hl              ; L=line, H=overshoot
        dec     sp
        ld      c, l
        call    0x8030          ; GB_ICON
        ld      hl, (sv_ret)
        jp      (hl)

;; void gb_blite(u8 col, u8 line);   A=col, L=line -> B=col C=line
_gb_blite:
        ld      b, a
        ld      c, l
        jp      0x8018          ; GB_BLITE

;; void gb_curshow(void); / gb_curhide(void);
_gb_curshow:
        jp      0x801B          ; GB_CURSHOW
_gb_curhide:
        jp      0x8024          ; GB_CURHIDE

;; unsigned char gb_poll(void);   -> flags in A; caches cursor col/line
_gb_poll:
        call    0x801E          ; GB_POLL -> B=col C=line D=flags
        ld      a, b
        ld      (mx_v), a
        ld      a, c
        ld      (my_v), a
        ld      a, d
        ret
;; unsigned char gb_mx(void); / gb_my(void);
_gb_mx:
        ld      a, (mx_v)
        ret
_gb_my:
        ld      a, (my_v)
        ret

;; char *gb_dir1(void); / char *gb_dirn(void);   -> name ptr in DE, 0 at end
_gb_dir1:
        call    0x8012          ; GB_DIR1
        jr      nc, gd_none
        ex      de, hl
        ret
_gb_dirn:
        call    0x8015          ; GB_DIRN
        jr      nc, gd_none
        ex      de, hl
        ret
gd_none:
        ld      de, #0
        ret

;; void gb_launch(void);   launch the current dir entry; returns when it quits
_gb_launch:
        jp      0x8027          ; GB_LAUNCH

;; void gb_run(const char *name);   name in HL
_gb_run:
        jp      0x802D          ; GB_RUN

;; unsigned int gb_fs_load(char *buf, unsigned int max);   buf=HL, max=DE -> count
_gb_fs_load:
        call    0x803F          ; GB_FSLOAD -> BC = byte count
        ld      d, b
        ld      e, c
        ret

;; unsigned char gb_fs_save(char *buf, unsigned int len);   buf=HL, len=DE -> 1/0
_gb_fs_save:
        call    0x8042          ; GB_FSSAVE -> CF = saved
        ld      a, #0
        ret     nc
        inc     a
        ret

;; unsigned char gb_getkey(void);   -> typed char in A, or 0 if none
_gb_getkey:
        jp      0x8045          ; GB_GETKEY (returns the char in A)

;; void gb_vsync(void);   wait one frame (50 Hz), no pointer/clock side effects
_gb_vsync:
        jp      0x8048          ; GB_VSYNC

;; void gb_on_event(void (*handler)(void));   handler ptr in HL -> kernel stores it
_gb_on_event:
        jp      0x804B          ; GB_ONEVENT
