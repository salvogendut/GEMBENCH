;; crt0_v3_msx.s - guarded SDCC startup for an MSX2 GBAP v3 application.
;;
;; The kernel has only three resident bytes free in its Screen-7 build. Keeping
;; the v3 preflight in the application preserves that hard limit: the primary
;; page is loaded, this guard checks the complete M5 manifest/primary descriptor
;; against GB_SYSINFO, and only a compatible image reaches gsinit/main. Returning
;; before main publishes a window makes the existing loader release its pending
;; owner and page transactionally.
;;
;; M5 intentionally accepts one uncompressed fixed-origin primary segment. The
;; v3 descriptor format already names later resource/data/secondary-code kinds;
;; their mapping/call gate belongs to the following milestone.
        .module crt0_v3_msx
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
        call    gbap3_guard
        or      a
        ret     Z
        call    gsinit
        call    _main
        ret

;; Return A=1 only for a well-formed, compatible M5 package.
gbap3_guard:
        ;; The outer JP has already entered this guard. Version/count and the
        ;; exact manifest position are the executable fields needed here; the
        ;; host packager strictly validates icon-only directory metadata.
        ld      a,(0x4007)
        cp      #3
        jp      nz,gbap3_bad
        ld      a,(0x4008)
        or      a
        jp      z,gbap3_bad
        cp      #9
        jp      nc,gbap3_bad
        ld      b,a

        ;; Manifest follows the N eight-byte icon descriptors exactly.
        ld      a,b
        add     a,a
        add     a,a
        add     a,a
        add     a,#16
        ld      c,a
        ld      a,(0x400e)
        cp      c
        jp      nz,gbap3_bad
        ld      a,(0x400f)
        or      a
        jp      nz,gbap3_bad
        ld      l,c
        ld      h,#0
        ld      de,#0x4000
        add     hl,de
        push    hl
        pop     ix

        ;; Fixed GBM3 manifest prefix, target profile, and platform mask.
        ld      a,(ix+0)
        cp      #0x47                  ; G
        jp      nz,gbap3_bad
        ld      a,(ix+1)
        cp      #0x42                  ; B
        jp      nz,gbap3_bad
        ld      a,(ix+2)
        cp      #0x4d                  ; M
        jp      nz,gbap3_bad
        ld      a,(ix+3)
        cp      #0x33                  ; 3
        jp      nz,gbap3_bad
        ld      a,(ix+4)
        cp      #40
        jp      nz,gbap3_bad
        ld      a,(ix+5)
        cp      #1
        jp      nz,gbap3_bad
        ld      a,(ix+6)
        dec     a                      ; profiles 1 and 2 are defined
        cp      #2
        jp      nc,gbap3_bad
        bit     1,(ix+7)               ; GBAP platform mask: MSX2
        jp      z,gbap3_bad
        ld      a,(ix+26)
        or      a
        jp      z,gbap3_bad
        ld      a,(ix+28)
        cp      #1                     ; M5: one primary segment
        jp      nz,gbap3_bad
        ld      a,(ix+29)
        cp      #12
        jp      nz,gbap3_bad
        ;; Segment directory follows this 40-byte manifest.
        ld      a,(0x400e)
        add     a,#40
        cp      (ix+30)
        jp      nz,gbap3_bad
        ld      a,(ix+31)
        or      a
        jp      nz,gbap3_bad
        ld      a,(0x400a)
        cp      (ix+32)
        jp      nz,gbap3_bad
        ld      a,(0x400b)
        cp      (ix+33)
        jp      nz,gbap3_bad

        ;; Image must fit the MSX loader's 0x3F00-byte page ceiling. Preserve
        ;; its length in BC while IX is changed to the segment descriptor.
        ld      c,(ix+34)
        ld      b,(ix+35)
        ld      a,b
        cp      #0x3f
        jr      c,gbap3_image_ok
        jp      nz,gbap3_bad
        ld      a,c
        or      a
        jp      nz,gbap3_bad
gbap3_image_ok:

        ;; Query the immutable resident capability record.
        call    0x80c3                ; GB_SYSINFO -> DE
        push    de
        pop     iy
        ld      a,(iy+0)
        cp      (ix+11)               ; minimum sysinfo size
        jp      c,gbap3_bad
        ld      a,(iy+1)
        cp      (ix+10)               ; minimum sysinfo version
        jp      c,gbap3_bad
        ld      a,(iy+2)
        cp      (ix+8)                ; minimum ABI major
        jp      c,gbap3_bad
        jr      nz,gbap3_abi_ok
        ld      a,(iy+3)
        cp      (ix+9)                ; minimum ABI minor
        jp      c,gbap3_bad
gbap3_abi_ok:
        ld      a,(iy+14)             ; primary page is already allocated
        inc     a                     ; so available total = free + primary
        cp      (ix+26)
        jp      c,gbap3_bad
        ld      a,(iy+16)
        cpl
        and     (ix+12)
        jp      nz,gbap3_bad
        ld      a,(iy+17)
        cpl
        and     (ix+13)
        jp      nz,gbap3_bad

        ;; Validate the complete M5 primary segment descriptor.
        ld      c,(ix+34)              ; k_sysinfo uses BC internally
        ld      b,(ix+35)
        ld      l,(ix+30)
        ld      h,(ix+31)
        ld      de,#0x4000
        add     hl,de
        push    hl
        pop     ix
        ld      a,(ix+0)
        cp      #1                     ; primary
        jp      nz,gbap3_bad
        bit     1,(ix+1)               ; available on MSX2
        jp      z,gbap3_bad
        ld      a,(ix+2)
        and     #3                     ; required + executable
        cp      #3
        jp      nz,gbap3_bad
        ld      a,(ix+3)
        or      a                      ; compression none
        jp      nz,gbap3_bad
        ld      a,(0x400a)
        cp      (ix+4)
        jp      nz,gbap3_bad
        ld      a,(0x400b)
        cp      (ix+5)
        jp      nz,gbap3_bad
        ld      a,(ix+6)
        or      (ix+7)
        jp      z,gbap3_bad
        ld      a,(ix+6)
        cp      (ix+8)
        jp      nz,gbap3_bad
        ld      a,(ix+7)
        cp      (ix+9)
        jp      nz,gbap3_bad
        ld      a,(0x4001)
        cp      (ix+10)                ; fixed load address = JP target
        jp      nz,gbap3_bad
        ld      a,(0x4002)
        cp      (ix+11)
        jp      nz,gbap3_bad

        ;; preamble + stored primary bytes must equal manifest image size.
        ld      e,(ix+6)
        ld      d,(ix+7)
        ld      hl,(0x400a)
        add     hl,de
        ld      a,l
        cp      c
        jp      nz,gbap3_bad
        ld      a,h
        cp      b
        jp      nz,gbap3_bad
        ld      a,#1
        ret
gbap3_bad:
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
