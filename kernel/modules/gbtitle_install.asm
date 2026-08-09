; GBTITLE.MOD installer. The existing arbitrary paged-module service loads this
; at #6000. It copies the renderer payload to its permanent PAGE_DATA slot and
; optionally replaces the fallback tile from the low-RAM copy buffer.

DATA_MODTOP     equ   #6000
DATA_TITLE      equ   #5E00
DATA_TITLE_SIZE equ   106
TITLE_READY     equ   #124F
TITLE_VALID     equ   #1710
TITLE_XFER      equ   #2200

                org   DATA_MODTOP
gbtitle_install
                ld    hl,gbtitle_payload
                ld    de,DATA_TITLE
                ld    bc,gbtitle_payload_e-gbtitle_payload
                ldir
                ifdef TITLE_NATIVE
                ld    hl,DATA_TITLE           ; convert the embedded fallback theme in place
                ld    de,DATA_TITLE
                ld    b,DATA_TITLE_SIZE
                call  gti_convert
                endif
                ld    a,(TITLE_VALID)
                or    a
                jr    z,gti_ready
                ld    hl,TITLE_XFER
                ld    de,DATA_TITLE
                cp    2
                ld    b,56                    ; legacy theme: keep fallback gadgets
                jr    c,gti_copy
                ld    b,DATA_TITLE_SIZE
gti_copy
                ifdef TITLE_NATIVE
                call  gti_convert
                else
                ld    c,b
                ld    b,0
                ldir
                endif
                jr    gti_ready

                ifdef TITLE_NATIVE
gti_convert
                ld    a,(hl)
                inc   hl
                ld    c,a
                and   #0F                    ; CPC lower nibble = high bit of each pen
                ld    (gti_high+1),a
gti_high        ld    a,(gti_spread)
                add   a,a                    ; spread into output bits 7,5,3,1
                ex    af,af'
                ld    a,c
                rrca
                rrca
                rrca
                rrca
                and   #0F                    ; CPC upper nibble = low bit of each pen
                ld    (gti_low+1),a
gti_low         ld    a,(gti_spread)
                ld    c,a
                ex    af,af'
                or    c                     ; packed four-pen Screen-6/UI byte
                ld    (de),a
                inc   de
                djnz  gti_convert
                ret
                endif
gti_ready
                ld    a,1
                ld    (TITLE_READY),a
                ret

gbtitle_payload incbin "../../build/GBTITLE.PAY"
gbtitle_payload_e

                ifdef TITLE_NATIVE
                align 256
gti_spread      db    #00,#01,#04,#05,#10,#11,#14,#15
                db    #40,#41,#44,#45,#50,#51,#54,#55
                assert (gti_spread & #FF)==0,"title conversion table must be page-aligned"
                endif
gbtitle_install_e

                ifdef PLATFORM_MSX
                save  "build/msx/GBTITLE.RAW",DATA_MODTOP,gbtitle_install_e-DATA_MODTOP
                else
                ifdef PLATFORM_PCW
                save  "build/pcw/GBTITLE.RAW",DATA_MODTOP,gbtitle_install_e-DATA_MODTOP
                else
                save  "build/GBTITLE.RAW",DATA_MODTOP,gbtitle_install_e-DATA_MODTOP
                endif
                endif
