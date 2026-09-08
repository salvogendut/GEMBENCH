;; crt0_v4.s - platform-neutral guarded startup for a GBAP v4 application.
;; The transactional loader validates package bounds and CRC. This in-page
;; guard independently repeats the ABI/sysinfo/capability checks before SDCC
;; initialisation or application publication.
        .module crt0_v4
        .globl  _main
        .globl  l__INITIALIZER
        .globl  s__INITIALIZER
        .globl  s__INITIALIZED
        .globl  l__DATA
        .globl  s__DATA
        .globl  l__BSS
        .globl  s__BSS

        .area   _CODE
_start::
        call    gbap4_guard
        or      a
        ret     Z
        call    gsinit
        call    _main
        ret

gbap4_guard:
        ld      a,(0x4007)
        cp      #4
        jp      nz,gbap4_bad
        ld      a,(0x4008)
        or      a
        jp      z,gbap4_bad
        cp      #9
        jp      nc,gbap4_bad
        ld      b,a
        add     a,a
        add     a,a
        add     a,a
        add     a,#16
        ld      c,a
        ld      a,(0x400e)
        cp      c
        jp      nz,gbap4_bad
        ld      a,(0x400f)
        or      a
        jp      nz,gbap4_bad
        ld      l,c
        ld      h,#0
        ld      de,#0x4000
        add     hl,de
        push    hl
        pop     ix

        ;; Fixed GBM4 v1 / universal-z80 / all-platform prefix.
        ld      a,(ix+0)
        cp      #0x47                  ; G
        jp      nz,gbap4_bad
        ld      a,(ix+1)
        cp      #0x42                  ; B
        jp      nz,gbap4_bad
        ld      a,(ix+2)
        cp      #0x4d                  ; M
        jp      nz,gbap4_bad
        ld      a,(ix+3)
        cp      #0x34                  ; 4
        jp      nz,gbap4_bad
        ld      a,(ix+4)
        cp      #64
        jp      nz,gbap4_bad
        ld      a,(ix+5)
        cp      #1
        jp      nz,gbap4_bad
        ld      a,(ix+6)
        cp      #3
        jp      nz,gbap4_bad
        ld      a,(ix+7)
        cp      #7
        jp      nz,gbap4_bad
        ld      a,(ix+44)
        cp      #0x47                  ; GEOBNCH2
        jp      nz,gbap4_bad
        ld      a,(ix+45)
        cp      #0x45
        jp      nz,gbap4_bad
        ld      a,(ix+46)
        cp      #0x4f
        jp      nz,gbap4_bad
        ld      a,(ix+47)
        cp      #0x42
        jp      nz,gbap4_bad
        ld      a,(ix+48)
        cp      #0x4e
        jp      nz,gbap4_bad
        ld      a,(ix+49)
        cp      #0x43
        jp      nz,gbap4_bad
        ld      a,(ix+50)
        cp      #0x48
        jp      nz,gbap4_bad
        ld      a,(ix+51)
        cp      #0x32
        jp      nz,gbap4_bad
        ld      a,(0x400a)
        cp      (ix+38)
        jp      nz,gbap4_bad
        ld      a,(0x400b)
        cp      (ix+39)
        jp      nz,gbap4_bad

        ;; GB_SYSINFO must expose the complete v6 suffix requested by GBM4.
        call    0x80c3                ; GB_SYSINFO -> DE
        ld      a,d
        or      a,e
        jp      z,gbap4_bad
        push    de
        pop     iy
        ld      a,(iy+0)
        cp      (ix+11)
        jp      c,gbap4_bad
        ld      a,(iy+1)
        cp      (ix+10)
        jp      c,gbap4_bad
        ;; The inherited prefix remains GEMBENCH-1. Universal ABI identity is
        ;; append-only in the v6 suffix, so compare the manifest against it.
        ld      a,(iy+44)
        cp      (ix+8)
        jp      c,gbap4_bad
        jr      nz,gbap4_abi_ok
        ld      a,(iy+45)
        cp      (ix+9)
        jp      c,gbap4_bad
gbap4_abi_ok:
        ld      a,(iy+14)             ; free pages + allocated primary
        inc     a
        cp      (ix+32)
        jp      c,gbap4_bad

        ;; Required low/high capability words must be subsets of the live mask.
        ld      a,(iy+16)
        cpl
        and     (ix+12)
        jp      nz,gbap4_bad
        ld      a,(iy+17)
        cpl
        and     (ix+13)
        jp      nz,gbap4_bad
        ld      a,(iy+32)
        cpl
        and     (ix+14)
        jp      nz,gbap4_bad
        ld      a,(iy+33)
        cpl
        and     (ix+15)
        jp      nz,gbap4_bad

        ;; Pin the execution view and semantic renderer promised by v2.
        ld      a,(iy+36)
        cp      #4
        jp      nz,gbap4_bad
        ld      a,(iy+37)
        cp      #4
        jp      nz,gbap4_bad
        ld      a,(iy+38)
        or      a
        jp      nz,gbap4_bad
        ld      a,(iy+39)
        cp      #0x40
        jp      nz,gbap4_bad
        ld      a,(iy+40)
        or      a
        jp      nz,gbap4_bad
        ld      a,(iy+41)
        cp      #0x7f
        jp      nz,gbap4_bad
        ld      a,(iy+42)
        or      a
        jp      nz,gbap4_bad
        ld      a,(iy+43)
        cp      #0x80
        jp      nz,gbap4_bad
        ld      a,(iy+44)
        cp      #2
        jp      nz,gbap4_bad
        ld      a,(iy+45)
        cp      #1                    ; ABI 2.1 or a compatible newer minor
        jp      c,gbap4_bad
        ld      a,(iy+46)
        cp      #3
        jp      nz,gbap4_bad

        ld      a,#1
        ret
gbap4_bad:
        xor     a
        ret

zero_region:
        ld      a,b
        or      a,c
        ret     Z
        ld      (hl),#0x00
        dec     bc
        ld      a,b
        or      a,c
        ret     Z
        ld      d,h
        ld      e,l
        inc     de
        ldir
        ret

        .area   _GSINIT
gsinit::
        ld      hl,#s__DATA
        ld      bc,#l__DATA
        call    zero_region
        ld      hl,#s__BSS
        ld      bc,#l__BSS
        call    zero_region
        ld      bc,#l__INITIALIZER
        ld      a,b
        or      a,c
        jr      Z,gsinit_done
        ld      de,#s__INITIALIZED
        ld      hl,#s__INITIALIZER
        ldir
gsinit_done:
        .area   _GSFINAL
        ret

        .area   _HOME
        .area   _INITIALIZER
        .area   _DATA
        .area   _INITIALIZED
        .area   _BSS
        .area   _HEAP
