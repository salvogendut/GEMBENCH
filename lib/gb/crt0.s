;; crt0.s - shared SDCC startup for a GEOBENCH banked C app.
;;
;; The kernel loads the app image at APP_BASE (#4000) and CALLs it there, with a
;; resident stack already set up. The entry runs SDCC's global initialisers
;; (gsinit) and main(), then RETs to the launcher. Linked FIRST so _start lands
;; at #4000.
;;
;; gsinit copies initialised globals from _INITIALIZER (in the loaded image) to
;; _INITIALIZED (RAM); without it any mutable initialised data holds garbage
;; (e.g. the desktop's draggable icon-position arrays).
        .module crt0
        .globl  _main
        .globl  l__INITIALIZER          ; linker-defined: length of _INITIALIZER
        .globl  s__INITIALIZER          ; ... start of the source (in the image)
        .globl  s__INITIALIZED          ; ... start of the dest (RAM)
        .globl  l__DATA                  ; ... uninitialised globals (SDCC puts them
        .globl  s__DATA                  ;     here, NOT _BSS) - length + start
        .globl  l__BSS                   ; ... the (small) _BSS area too
        .globl  s__BSS

        .area   _CODE
_start::
        call    gsinit
        call    _main
        ret                     ; back to the kernel's launch_app

        ;; zero_region: HL = start, BC = length -> fill with 0. (Self-propagating
        ;; ldir: set the first byte, then copy it forward.)
zero_region:
        ld      a, b
        or      a, c
        ret     Z
        ld      (hl), #0x00
        dec     bc
        ld      a, b
        or      a, c
        ret     Z
        ld      d, h
        ld      e, l
        inc     de
        ldir
        ret

        .area   _GSINIT
gsinit::
        ;; Zero the uninitialised globals. C requires them to start at 0, and a
        ;; relaunched app (Exit to DOS -> run"GBKERN) must NOT inherit the previous
        ;; run's values - the desktop's bar_init stayed set, so its top bar never
        ;; redrew. SDCC keeps these in _DATA (with _BSS a small extra); the image has
        ;; no bytes for either (they're RAM) so the loader can't clear them, we do.
        ld      hl, #s__DATA
        ld      bc, #l__DATA
        call    zero_region
        ld      hl, #s__BSS
        ld      bc, #l__BSS
        call    zero_region
        ;; copy initialised globals from the image to RAM (_INITIALIZED sits between
        ;; _DATA and _BSS, so it survives the zeroing above and gets its values here)
        ld      bc, #l__INITIALIZER
        ld      a, b
        or      a, c
        jr      Z, gsinit_done
        ld      de, #s__INITIALIZED
        ld      hl, #s__INITIALIZER
        ldir
gsinit_done:
        .area   _GSFINAL
        ret

        ;; area ordering for the linker (low group is in the image; data is RAM)
        .area   _HOME
        .area   _INITIALIZER
        .area   _DATA
        .area   _INITIALIZED
        .area   _BSS
        .area   _HEAP
