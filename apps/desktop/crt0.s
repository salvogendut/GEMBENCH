;; crt0.s - SDCC startup for a GEOBENCH banked C app.
;;
;; The kernel loads the app image at APP_BASE (#4000) and CALLs it there, with a
;; resident stack already set up. The entry runs SDCC's global initialisers
;; (gsinit) and main(), then RETs to the launcher. Link this object FIRST so
;; _start lands at #4000.
;;
;; gsinit copies initialised globals from _INITIALIZER (in the loaded image) to
;; _INITIALIZED (RAM) - needed by any app with mutable initialised data (e.g. the
;; desktop's draggable icon-position arrays).
        .module crt0
        .globl  _main
        .globl  l__INITIALIZER          ; linker-defined: length of _INITIALIZER
        .globl  s__INITIALIZER          ; ... start of the source (in the image)
        .globl  s__INITIALIZED          ; ... start of the dest (RAM)

        .area   _CODE
_start::
        call    gsinit
        call    _main
        ret                     ; back to the kernel's launch_app

        .area   _GSINIT
gsinit::
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
