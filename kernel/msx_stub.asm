; kernel/msx_stub.asm - GBMSX.COM bootstrap for the MSX2 target (#287).
;
; A small MSX-DOS .COM stub that carries the resident kernel image (assembled
; separately at #8000, incbin'd below) and prepares the machine:
;
;   1. _DOSVER: require a DOS 2.x / Nextor kernel (mapper support needs it).
;   2. EXTBIO D=4: capture the mapper support routines (ALL_SEG/FRE_SEG/
;      PUT_P1/GET_P1) and the segment counts into the page-3 glue, plus the
;      TPA's own page-1 segment (GET_P1) - the kernel's "bank_normal".
;   3. Copy the H.TIMI tick handler into page-3 RAM and hook it (the BIOS
;      runs hooks with the BIOS ROM in page 0 - the M0 spike's lesson).
;   4. Copy the kernel image to #8000-#BFFF.
;   5. CHGMOD 6 via the BIOS (Screen 6, BIOS variables kept consistent).
;   6. SP = MSX_STACK_TOP, jp GB_INIT.
;
; Build (tools/build_kernel_msx.sh): rasm assembles gbkern.asm with
; -DPLATFORM_MSX=1 to GBKERNM.RAW first, then this file emits GBMSX.COM.

                include "../lib/msx/bios.inc"
                include "../lib/msx/glue.inc"

GB_KERNEL       equ   #8000
_STROUT         equ   #09

                org   #100

start
                ld    a,'1'
                call  ckpt
                ld    c,_DOSVER              ; 1. need a DOS 2.x kernel
                call  BDOS
                ld    a,b
                cp    2
                jr    nc,dos_ok
                ld    de,msg_baddos
                ld    c,_STROUT
                call  BDOS
                ld    c,_TERM0
                jp    BDOS
dos_ok
                ld    hl,(#0006)             ; the TPA ceiling must clear the page-3
                ld    de,MSX_GLUE_TOP        ; glue at #C000..#C8FF
                or    a
                sbc   hl,de
                jr    nc,tpa_ok
                ld    de,msg_tpa
                ld    c,_STROUT
                call  BDOS
                ld    c,_TERM0
                jp    BDOS
tpa_ok
                xor   a                       ; 2. mapper support jump table
                ld    de,#0402
                ld    hl,0
                call  EXTBIO
                ld    a,h
                or    l
                jr    nz,map_ok
                ld    de,msg_nomap
                ld    c,_STROUT
                call  BDOS
                ld    c,_TERM0
                jp    BDOS
map_ok
                ; The table is a row of 3-byte JP instructions (like the GEOBENCH
                ; API table): the ENTRY POINTS are table+offset - store those, do
                ; NOT dereference the JP opcode bytes as pointers.
                ld    (MSX_ALLSEG),hl        ; +0  ALL_SEG
                ld    de,3
                add   hl,de
                ld    (MSX_FRESEG),hl        ; +3  FRE_SEG
                ld    de,27
                add   hl,de
                ld    (MSX_PUTP1),hl         ; +30 PUT_P1
                inc   hl
                inc   hl
                inc   hl
                ld    (MSX_GETP1),hl         ; +33 GET_P1

                xor   a                       ; mapper variable table: counts
                ld    de,#0401
                ld    hl,0
                call  EXTBIO
                inc   hl                      ; +1 total segments (primary mapper)
                ld    a,(hl)
                ld    (MSX_TOTSEG),a
                inc   hl                      ; +2 free segments
                ld    a,(hl)
                ld    (MSX_FREESEG),a

                ld    a,'2'
                call  ckpt
                ld    hl,(MSX_GETP1)         ; TPA's own page-1 segment
                call  stub_jphl
                ld    (MSX_TPASEG),a
                ld    a,'3'
                call  ckpt

                di                            ; 3. page-3 tick handler + H.TIMI hook
                ld    hl,tick_code
                ld    de,MSX_HOOKCODE
                ld    bc,tick_code_end-tick_code
                ldir
                ld    hl,0
                ld    (MSX_TICK),hl
                ld    hl,H_TIMI              ; save the original hook for exit
                ld    de,MSX_HOOKSAVE
                ld    bc,5
                ldir
                ld    a,#C3                   ; H.TIMI: jp MSX_HOOKCODE
                ld    (H_TIMI),a
                ld    hl,MSX_HOOKCODE
                ld    (H_TIMI+1),hl
                ei

                ld    a,'4'
                call  ckpt
                ld    hl,kern_img            ; 4. kernel image -> #8000
                ld    de,GB_KERNEL
                ld    bc,kern_img_end-kern_img
                ldir
                ld    a,'5'
                call  ckpt

                ld    a,6                     ; 5. Screen 6 via the BIOS
                ld    ix,CHGMOD
                ld    iy,(EXPTBL-1)
                call  CALSLT
                ei

                ld    hl,(#0006)             ; 6. SP = the real TPA ceiling: the BDOS
                ld    sp,hl                   ;    entry pointer = lowest DOS address
                jp    GB_KERNEL              ; GB_INIT

stub_jphl       jp    (hl)

ckpt                                          ; debug: print a checkpoint char
                push  bc
                push  de
                push  hl
                ld    e,a
                ld    c,#02                   ; _CONOUT
                call  BDOS
                pop   hl
                pop   de
                pop   bc
                ret

; The H.TIMI handler template, copied to MSX_HOOKCODE (page 3). Position-
; independent; page-3 addresses only. The BIOS saved all registers already.
tick_code
                push  hl
                ld    hl,(MSX_TICK)
                inc   hl
                ld    (MSX_TICK),hl
                pop   hl
                ret
tick_code_end

msg_baddos      db    "GEOBENCH needs MSX-DOS 2 / Nextor",13,10,"$"
msg_nomap       db    "GEOBENCH: no DOS2 mapper support",13,10,"$"
msg_tpa         db    "GEOBENCH: TPA too small",13,10,"$"

kern_img        incbin "../build/msx/GBKERNM.RAW"
kern_img_end

                save  "GBMSX.COM",#100,kern_img_end-#100
