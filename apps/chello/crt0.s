;; crt0.s - SDCC startup for a GEOBENCH banked C app.
;;
;; The kernel loads the app image at APP_BASE (#4000) and CALLs it there, with a
;; resident stack already set up. So the entry just runs SDCC's static init
;; (empty for apps with no initialised globals) and main(), then RETs back to
;; the kernel launcher. Link this object FIRST so _start lands at #4000.
        .module crt0
        .globl  _main

        .area   _CODE
_start::
        call    gsinit          ; SDCC global/static initialisers
        call    _main
        ret                     ; back to the kernel's launch_app

        .area   _GSINIT
gsinit::
        .area   _GSFINAL
        ret

        ;; area ordering for the linker
        .area   _HOME
        .area   _INITIALIZER
        .area   _DATA
        .area   _INITIALIZED
        .area   _BSS
        .area   _HEAP
