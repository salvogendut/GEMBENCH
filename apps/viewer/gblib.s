;; gblib.s - C bindings for the GEOBENCH kernel API (see gb.h).
;;
;; Maps SDCC's __sdcccall(1) convention onto the kernel jump table:
;;   args:   first small args pack into A then L; remaining args are pushed
;;           (the caller does NOT clean up - callee-clean).
;;   return: unsigned char in A, 16-bit (int/pointer) in DE.
;; Addresses mirror lib/gbapp.inc.
        .module gblib
        .globl  _gb_window
        .globl  _gb_text
        .globl  _gb_curshow
        .globl  _gb_poll
        .globl  _gb_fs_load

        .area   _BSS
gw_ret: .ds     2               ; saved return addr across the 5-arg gb_window

        .area   _CODE

;; void gb_window(u8 col, u8 line, u8 w, u8 h, const char *title);
;;   SDCC: A=col, L=line; pushed (in order) title, then the (w,h) word (w=low,
;;   h=high). Stack at entry: [ret][w,h][title]. GB_WINDOW wants B=x C=y D=w E=h
;;   HL=title. Pop all three args (callee-clean) and jump back via the saved ret.
_gb_window:
        ld      b, a            ; B = col (x)
        ld      c, l            ; C = line (y)
        pop     hl              ; HL = return address
        ld      (gw_ret), hl
        pop     hl              ; HL = (w,h) word: L=w, H=h
        ld      d, l            ; D = w
        ld      e, h            ; E = h
        pop     hl              ; HL = title
        call    0x800F          ; GB_WINDOW
        ld      hl, (gw_ret)
        jp      (hl)

;; void gb_text(u8 col, u8 line, const char *s);
;;   A=col, L=line, [SP+2]=s. pop/ex (sp),hl loads HL=s and collapses the pushed
;;   arg into the return slot so a plain ret cleans the stack.
_gb_text:
        ld      b, a            ; B = col
        ld      c, l            ; C = line
        ld      d, #1           ; pen   = 1 (white)
        ld      e, #0           ; paper = 0 (window fill)
        pop     hl              ; HL = return address; SP -> s
        ex      (sp), hl        ; HL = s; return address into the arg slot
        call    0x800C          ; GB_TEXT
        ret

;; void gb_curshow(void);
_gb_curshow:
        jp      0x801B          ; GB_CURSHOW

;; unsigned char gb_poll(void);    -> flags in A
_gb_poll:
        call    0x801E          ; GB_POLL -> B=col C=line D=flags
        ld      a, d
        ret

;; unsigned int gb_fs_load(char *buf);   buf in HL; max baked in -> count in DE
_gb_fs_load:
        ld      de, #6144       ; max bytes (matches filebuf[] in main.c)
        call    0x803F          ; GB_FSLOAD -> BC = byte count
        ld      d, b
        ld      e, c
        ret
