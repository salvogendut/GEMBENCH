;; Minimal libgb bindings for BROWSER.APP. The ASxxxx linker retains a complete
;; assembly object, so using the general gblib.s would spend scarce app-bank
;; space on API trampolines that Browser never calls.
        .module gblib_browser
        .globl  _gb_cls
        .globl  _gb_text
        .globl  _gb_textk
        .globl  _gb_textbw
        .globl  _gb_textrev
        .globl  _gb_window
        .globl  _gb_restorerect
        .globl  _gb_saverect
        .globl  _gb_mxp
        .globl  _gb_clip_set
        .globl  _gb_clip_get
        .globl  _gb_clip_len
        .globl  _gb_ui
        .globl  _gb_net
        .globl  _gb_fill
        .globl  _gb_frame
        .globl  _gb_curshow
        .globl  _gb_curhide
        .globl  _gb_mx
        .globl  _gb_my
        .globl  _gb_fs_save
        .globl  _gb_getkey
        .globl  _gb_menu
        .globl  _gb_set_name
        .globl  _gb_pic_edit
        .globl  _gb_pic_close
        .globl  _gb_restore_parent
        .globl  _gb_wm_managed
        .globl  _gb_wm_open
        .globl  _gb_wm_close
        .globl  _gb_back
        .globl  _gb_drives
        .globl  _gb_set_drive

        .area   _BSS
sv_ret: .ds     2

        .area   _CODE

_gb_cls:
        jp      0x8003

_gb_text:
        ld      b, a
        ld      c, l
        ld      d, #1
        ld      e, #0
        pop     hl
        ex      (sp), hl
        call    0x800C
        ret

_gb_textk:
        ld      b, a
        ld      c, l
        ld      d, #2
        ld      e, #0
        pop     hl
        ex      (sp), hl
        call    0x800C
        ret

_gb_textbw:
        ld      b, a
        ld      c, l
        ld      d, #2
        ld      e, #1
        pop     hl
        ex      (sp), hl
        call    0x800C
        ret

_gb_textrev:
        ld      b, a
        ld      c, l
        ld      d, #1
        ld      e, #2
        pop     hl
        ex      (sp), hl
        call    0x800C
        ret

_gb_window:
        ld      b, a
        ld      c, l
        pop     hl
        ld      (sv_ret), hl
        pop     hl
        ld      d, l
        ld      e, h
        pop     hl
        call    0x800F
        ld      hl, (sv_ret)
        jp      (hl)

_gb_saverect:
        ld      b, a
        ld      c, l
        pop     hl
        ld      (sv_ret), hl
        pop     hl
        ld      d, l
        ld      e, h
        pop     hl
        call    0x8036
        ld      hl, (sv_ret)
        jp      (hl)

_gb_restorerect:
        ld      b, a
        ld      c, l
        pop     hl
        ld      (sv_ret), hl
        pop     hl
        ld      d, l
        ld      e, h
        pop     hl
        call    0x8039
        ld      hl, (sv_ret)
        jp      (hl)

_gb_mxp:
        call    0x80A2
        ex      de, hl
        ret

_gb_clip_set:
        jp      0x80A5
_gb_clip_get:
        call    0x80A8
        ld      d, b
        ld      e, c
        ret
_gb_clip_len:
        call    0x80AB
        ld      d, b
        ld      e, c
        ret

_gb_ui:
        xor     a
        call    0x80AE
        ld      a, c
        ret

_gb_net:
        call    0x80BD
        ld      a, c
        ret

_gb_fill:
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
        call    0x8033
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
        call    0x8021
        ld      hl, (sv_ret)
        jp      (hl)

_gb_curshow:
        jp      0x801B
_gb_curhide:
        jp      0x8024

_gb_mx:
        ld      a, (0x1306)
        ret
_gb_my:
        ld      a, (0x1307)
        ret

_gb_fs_save:
        call    0x8042
        ld      a, #0
        adc     a, #0
        ld      c, a
        xor     a
        ld      (0x1705), a
        ld      a, c
        ret

_gb_getkey:
        jp      0x8045
_gb_menu:
        jp      0x804E
_gb_set_name:
        jp      0x8051
_gb_pic_edit:
        jp      0x8048
_gb_pic_close:
        jp      0x8069
_gb_restore_parent:
        jp      0x8057
_gb_wm_managed:
        jp      0x80B1
_gb_wm_open:
        jp      0x8060
_gb_wm_close:
        jp      0x8063
_gb_back:
        jp      0x8072
_gb_drives:
        jp      0x807E
_gb_set_drive:
        jp      0x8081
