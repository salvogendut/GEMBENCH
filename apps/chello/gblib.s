;; gblib.s - C bindings for the GEOBENCH kernel API (see gb.h).
;;
;; Maps SDCC's calling convention (__sdcccall, callee-cleans) onto the kernel
;; jump table. SDCC packs the first small args into A then L, and pushes the
;; trailing pointer arg on the stack; an unsigned-char result comes back in A.
;; The jump-table addresses mirror lib/gbapp.inc.
        .module gblib
        .globl  _gb_cls
        .globl  _gb_text
        .globl  _gb_poll

        .area   _CODE

;; void gb_cls(void);
_gb_cls:
        jp      0x8003          ; GB_CLS

;; void gb_text(unsigned char col, unsigned char line, const char *s);
;;   SDCC: A = col, L = line, [SP+2] = s (pushed), caller does NOT clean up.
;;   GB_TEXT wants B = col, C = line, D = pen, E = paper, HL = string.
;;   The pop / ex (sp),hl pair loads HL = s and collapses the pushed arg into the
;;   return slot, so a plain `ret` cleans the stack (callee-clean).
_gb_text:
        ld      b, a            ; B = col
        ld      c, l            ; C = line
        ld      d, #1           ; pen   = 1 (white)
        ld      e, #0           ; paper = 0 (blue backdrop)
        pop     hl              ; HL = return address; SP -> s
        ex      (sp), hl        ; HL = s; return address into the arg slot
        call    0x800C          ; GB_TEXT
        ret

;; unsigned char gb_poll(void);    -> flags in A
_gb_poll:
        call    0x801E          ; GB_POLL -> B=col C=line D=flags
        ld      a, d
        ret
