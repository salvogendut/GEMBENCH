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
        .globl  l__BSS                  ; ... length of the zero-init area
        .globl  s__BSS                  ; ... start of it (RAM)

        .area   _CODE
_start::
        call    gsinit
        call    _main
        ret                     ; back to the kernel's launch_app

        .area   _GSINIT
gsinit::
        ;; Zero _BSS. C requires uninitialised globals to start at 0, and a relaunched
        ;; app (Exit to DOS -> run"GBKERN) must NOT inherit the previous run's BSS - the
        ;; desktop's bar_init stayed set, so its top bar never redrew. The image holds
        ;; no BSS bytes (it's RAM), so the loader can't clear it; we do, here.
        ld      bc, #l__BSS
        ld      a, b
        or      a, c
        jr      Z, bss_done
        ld      hl, #s__BSS
        ld      (hl), #0x00
        dec     bc
        ld      a, b
        or      a, c
        jr      Z, bss_done             ; exactly one BSS byte -> already cleared
        ld      de, #s__BSS+1
        ldir                            ; propagate the zero across the rest
bss_done:
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
