; tools/gbspike_msx.asm - M0 toolchain spike for the MSX2 port (issue #287).
;
; A standalone MSX-DOS 2 / Nextor .COM program that proves, before any kernel
; code moves, every platform mechanism the GEOBENCH MSX2 target depends on:
;
;   1. BDOS console I/O + _DOSVER (requires a DOS 2.x kernel).
;   2. EXTBIO mapper support: variable table (total/free segments - the key
;      open number on 128K machines) and the jump table (ALL_SEG/FRE_SEG/
;      PUT_P1/GET_P1). Allocates a segment, maps it at #4000, does a
;      write/read-back check, restores the TPA segment.
;   3. CHGMOD 6 via CALSLT (V9938 Screen 6: 512x212, 4 colours, 2bpp).
;   4. V9938 palette writes (R#16 + port #9A pairs).
;   5. HMMV command fills (colour bars) via indirect register access (R#17).
;   6. H.TIMI hook: a tick counter driving an animated marker, then a clean
;      unhook (the GEOBENCH k_poll frame pacer will use the same mechanism).
;      GOTCHA (found by this spike): the BIOS calls H.TIMI with the BIOS ROM
;      mapped into page 0, so the handler and its tick cell must live in
;      page 3 RAM (here: copied to #C000), never in the page-0 .COM image.
;   7. INITXT + BDOS _TERM0: clean return to the DOS prompt.
;
; It prints its findings (DOS version, mapper segment counts, tick total) so a
; screenshot of the final text screen is a complete verification record.
;
; Build: rasm tools/gbspike_msx.asm   (emits GBSPIKE.COM via the save below)
; Run:   copy onto a Nextor FAT image with AUTOEXEC.BAT "GBSPIKE" and boot it
;        under tools/run_msx.sh.

BDOS            equ   #0005        ; DOS function dispatcher in page 0
_CONOUT         equ   #02
_STROUT         equ   #09
_DOSVER         equ   #6F
_TERM0          equ   #00

EXTBIO          equ   #FFCA        ; extended BIOS hook (mapper support lives here)
CALSLT          equ   #001C        ; inter-slot call (main BIOS entries)
EXPTBL          equ   #FCC1        ; main BIOS slot byte
H_TIMI          equ   #FD9F        ; VBLANK interrupt hook (5 bytes)

CHGMOD          equ   #005F        ; BIOS: set screen mode (A = mode)
INITXT          equ   #006C        ; BIOS: init 40-col text mode

VDP_DATA        equ   #98          ; V9938 ports
VDP_CTRL        equ   #99
VDP_PAL         equ   #9A

JIFFY           equ   #FC9E        ; BIOS 50/60Hz tick (page 3, always visible)

; The H.TIMI handler runs with the BIOS ROM in page 0, so it is copied into
; page-3 RAM. #C000+ is inside our TPA and far below the DOS work area.
HOOK_CODE       equ   #C000        ; relocated tick handler
TICKVAR         equ   #C010        ; tick counter the handler increments

TICK_TARGET     equ   250          ; ~5s at 50Hz

                org   #100

start:
                ld    de,msg_banner
                call  strout

; --- 1. DOS version (Nextor/DOS2 kernel required) --------------------------
                ld    c,_DOSVER
                call  BDOS
                ld    a,b                    ; B = kernel major
                cp    2
                jr    nc,dos_ok
                ld    de,msg_baddos
                call  strout
                jp    quit
dos_ok:         ld    (dosver),a
                ld    de,msg_dos
                call  strout
                ld    a,(dosver)
                call  print_a_dec
                call  crlf

; --- 2. mapper support: variable table (D=4,E=1) ----------------------------
                xor   a
                ld    de,#0401
                ld    hl,0
                call  EXTBIO
                ld    a,h
                or    l
                jr    nz,map_ok
                ld    de,msg_nomap
                call  strout
                jp    quit
map_ok:
                inc   hl                     ; +1 total segments in primary mapper
                ld    a,(hl)
                ld    (seg_total),a
                inc   hl                     ; +2 free segments
                ld    a,(hl)
                ld    (seg_free),a

                ld    de,msg_segtotal
                call  strout
                ld    a,(seg_total)
                call  print_a_dec
                call  crlf
                ld    de,msg_segfree
                call  strout
                ld    a,(seg_free)
                call  print_a_dec
                call  crlf

; --- mapper support: jump table (D=4,E=2) -----------------------------------
                xor   a
                ld    de,#0402
                call  EXTBIO                 ; HL -> jump table
                ld    (maptab),hl

; ALL_SEG: allocate one user segment ------------------------------------------
                xor   a                      ; A=0 user segment
                ld    b,a                    ; B=0 primary mapper
                ld    ix,(maptab)            ; +0 = ALL_SEG
                call  jpix
                jr    nc,alloc_ok
                ld    de,msg_allocfail
                call  strout
                jp    quit
alloc_ok:       ld    (test_seg),a
                ld    de,msg_alloc
                call  strout
                ld    a,(test_seg)
                call  print_a_dec
                call  crlf

; GET_P1 current TPA segment, PUT_P1 test segment, write/readback at #4000 ----
                ld    ix,(maptab)
                ld    de,33                  ; +33 = GET_P1
                add   ix,de
                call  jpix
                ld    (tpa_p1),a

                ld    a,(test_seg)
                ld    ix,(maptab)
                ld    de,30                  ; +30 = PUT_P1
                add   ix,de
                call  jpix

                ld    hl,#4000               ; write a signature into the segment
                ld    de,#A55A
                ld    (hl),d
                inc   hl
                ld    (hl),e
                dec   hl
                ld    a,(hl)
                cp    d
                jr    nz,rwfail
                inc   hl
                ld    a,(hl)
                cp    e
                jr    nz,rwfail
                ld    a,1
                ld    (rw_ok),a
rwfail:
                ld    a,(tpa_p1)             ; restore the TPA page-1 segment
                ld    ix,(maptab)
                ld    de,30
                add   ix,de
                call  jpix

                ld    a,(test_seg)           ; FRE_SEG the test segment
                ld    ix,(maptab)
                ld    de,3                   ; +3 = FRE_SEG
                add   ix,de
                call  jpix

                ld    a,(rw_ok)
                or    a
                jr    z,rw_bad
                ld    de,msg_rwok
                jr    rw_msg
rw_bad:         ld    de,msg_rwbad
rw_msg:         call  strout

; hold the text screen ~3s (JIFFY-paced) so a timed screenshot can record it
                call  pause3s

; --- 3. Screen 6 via CHGMOD (CALSLT into the main BIOS) ----------------------
                ld    a,6
                ld    ix,CHGMOD
                call  bioscall

; --- 4. palette: 4 GEOBENCH-ish pens (blue, white, black, red) ---------------
                call  set_palette

; --- 5. HMMV fills: clear to pen 0, then 4 vertical bars, pens 0..3 ----------
                call  clear_screen
                ld    b,0                    ; pen index 0..3
bars:           push  bc
                ld    a,b
                call  draw_bar
                pop   bc
                inc   b
                ld    a,b
                cp    4
                jr    c,bars

; --- 6. H.TIMI hook + animated marker ----------------------------------------
; Copy the handler to page-3 RAM first: the hook runs with BIOS ROM in page 0.
                ld    hl,tick_irq
                ld    de,HOOK_CODE
                ld    bc,tick_irq_end-tick_irq
                ldir
                ld    hl,0
                ld    (TICKVAR),hl
                di
                ld    hl,H_TIMI              ; save the 5 hook bytes
                ld    de,hook_save
                ld    bc,5
                ldir
                ld    a,#C3                  ; JP HOOK_CODE
                ld    (H_TIMI),a
                ld    hl,HOOK_CODE
                ld    (H_TIMI+1),hl
                ei

anim:           halt                         ; pace on the interrupt itself
                ld    hl,(TICKVAR)
                ld    a,l                    ; marker x = (tick & 127) * 4 px
                and   #7F
                ld    d,a
                call  draw_marker
                ld    hl,(TICKVAR)
                ld    de,TICK_TARGET
                or    a
                sbc   hl,de
                jr    c,anim

                di                           ; unhook H.TIMI
                ld    hl,hook_save
                ld    de,H_TIMI
                ld    bc,5
                ldir
                ei

; --- 7. back to text, report, clean exit -------------------------------------
                ld    ix,INITXT
                call  bioscall

                ld    de,msg_dos             ; final report repeats everything:
                call  strout                 ; INITXT wiped the first text page
                ld    a,(dosver)
                call  print_a_dec
                call  crlf
                ld    de,msg_segtotal
                call  strout
                ld    a,(seg_total)
                call  print_a_dec
                call  crlf
                ld    de,msg_segfree
                call  strout
                ld    a,(seg_free)
                call  print_a_dec
                call  crlf
                ld    de,msg_alloc
                call  strout
                ld    a,(test_seg)
                call  print_a_dec
                call  crlf
                ld    a,(rw_ok)
                or    a
                ld    de,msg_rwbad
                jr    z,fin_rw
                ld    de,msg_rwok
fin_rw:         call  strout
                ld    de,msg_ticks
                call  strout
                ld    hl,(TICKVAR)
                call  print_hl_dec
                call  crlf
                ld    de,msg_ok
                call  strout
quit:           ld    c,_TERM0
                jp    BDOS

; ---------------------------------------------------------------------------
; helpers
; ---------------------------------------------------------------------------

jpix:           jp    (ix)                   ; call through IX (mapper routines)

; call a main-BIOS entry (IX = entry) via CALSLT
bioscall:       ld    iy,(EXPTBL-1)          ; IYh = main BIOS slot
                call  CALSLT
                ei                           ; CALSLT may return with DI
                ret

strout:         ld    c,_STROUT
                jp    BDOS

crlf:           ld    de,msg_crlf
                jr    strout

; print A as decimal (0..255)
print_a_dec:    ld    l,a
                ld    h,0
; print HL as decimal (0..65535)
print_hl_dec:   ld    de,10000
                call  dec_digit
                ld    de,1000
                call  dec_digit
                ld    de,100
                call  dec_digit
                ld    de,10
                call  dec_digit
                ld    a,l
                add   a,'0'
                jr    conout
dec_digit:      ld    a,'0'-1
dd_loop:        inc   a
                or    a
                sbc   hl,de
                jr    nc,dd_loop
                add   hl,de
                push  hl
conout_p:       push  af
                ld    c,_CONOUT
                pop   af
                ld    e,a
                call  BDOS
                pop   hl
                ret
conout:         push  hl                     ; plain char out, keeps HL
                jr    conout_p

; V9938: write A to register C (direct register write, ports #99)
vdp_reg:        di
                out   (VDP_CTRL),a
                ld    a,c
                or    #80
                out   (VDP_CTRL),a
                ei
                ret

; wait for the command engine (CE flag, S#2 bit 0); leaves R#15 = 0
vdp_wait_ce:    di
                ld    a,2
                ld    c,15
                out   (VDP_CTRL),a
                ld    a,15|#80
                out   (VDP_CTRL),a
wce:            in    a,(VDP_CTRL)
                rrca
                jr    c,wce
                xor   a
                out   (VDP_CTRL),a
                ld    a,15|#80
                out   (VDP_CTRL),a
                ei
                ret

; palette: pen 0 = CPC blue, 1 = bright white, 2 = black, 3 = bright red;
; border (R#7 low bits = pen 2 in screen 6 text... keep 0) — set after bars.
set_palette:    ld    a,0                    ; R#16 = palette index 0
                ld    c,16
                call  vdp_reg
                di
                ld    hl,pal_data
                ld    b,8                    ; 4 entries x 2 bytes
palw:           ld    a,(hl)
                out   (VDP_PAL),a
                inc   hl
                djnz  palw
                ei
                ret

; clear the whole 512x212 bitmap to pen 0 (blue backdrop)
clear_screen:   call  vdp_wait_ce
                ld    hl,0
                ld    (cmd_dx),hl
                ld    (cmd_dy),hl
                ld    hl,512
                ld    (cmd_nx),hl
                ld    hl,212
                ld    (cmd_ny),hl
                xor   a                      ; pen 0 replicated = #00
                ld    (cmd_clr),a
                jp    do_hmmv

; draw one vertical bar: A = pen (0..3); x = 64 + pen*96, y=40, w=96, h=120
draw_bar:       push  af
                call  vdp_wait_ce
                pop   af
                push  af
                ld    l,a                    ; DX = 64 + pen*96
                ld    h,0
                add   hl,hl                  ; *2
                ld    d,h
                ld    e,l
                add   hl,hl                  ; *4
                add   hl,hl                  ; *8
                add   hl,hl                  ; *16
                add   hl,hl                  ; *32
                ld    b,h
                ld    c,l                    ; BC = pen*32
                add   hl,hl                  ; *64
                add   hl,bc                  ; *96
                ld    bc,64
                add   hl,bc
                ld    (cmd_dx),hl
                ld    hl,40
                ld    (cmd_dy),hl
                ld    hl,96
                ld    (cmd_nx),hl
                ld    hl,120
                ld    (cmd_ny),hl
                pop   af
                and   3                      ; CLR byte: pen replicated 4x (2bpp)
                ld    b,a
                add   a,a
                add   a,a
                or    b
                ld    b,a
                add   a,a
                add   a,a
                add   a,a
                add   a,a
                or    b                      ; pen * #55
                ld    (cmd_clr),a
                jr    do_hmmv

; draw the tick marker: D = column 0..127 -> x = D*4, small 4x6 box, pen 1
draw_marker:    push  de
                call  vdp_wait_ce
                pop   de
                ld    l,d
                ld    h,0
                add   hl,hl
                add   hl,hl                  ; x = D*4
                ld    (cmd_dx),hl
                ld    hl,175
                ld    (cmd_dy),hl
                ld    hl,4
                ld    (cmd_nx),hl
                ld    hl,6
                ld    (cmd_ny),hl
                ld    a,#55                  ; pen 1 (white) replicated
                ld    (cmd_clr),a
                ; fall through

; issue HMMV from the cmd_* block (indirect register access R#17 -> R#36..46)
do_hmmv:        ld    a,36                   ; R#17 = 36, autoincrement
                ld    c,17
                call  vdp_reg
                di
                ld    hl,cmd_dx
                ld    b,11                   ; R#36..R#46
                ld    c,#9B
hmv:            outi
                jr    nz,hmv
                ei
                ret

; pause ~3s: JIFFY (page-3 BIOS tick) keeps running under the stock ISR
pause3s:        ld    hl,(JIFFY)
                ld    de,150
                add   hl,de
                ex    de,hl                  ; DE = target
p3_wait:        halt
                ld    hl,(JIFFY)
                or    a
                sbc   hl,de
                jr    c,p3_wait
                ret

; H.TIMI handler template - COPIED to HOOK_CODE (#C000, page 3) before use;
; it must be position-independent and reference only page-3 addresses.
; The BIOS interrupt saved all registers before running the hook.
tick_irq:       push  hl
                ld    hl,(TICKVAR)
                inc   hl
                ld    (TICKVAR),hl
                pop   hl
                ret
tick_irq_end:

; ---------------------------------------------------------------------------
; data
; ---------------------------------------------------------------------------

msg_banner:     db    "GBSPIKE - GEOBENCH MSX2 M0 toolchain spike",13,10
                db    "-------------------------------------------",13,10,"$"
msg_baddos:     db    "FAIL: MSX-DOS 2 / Nextor kernel required$"
msg_dos:        db    "DOS kernel major: $"
msg_nomap:      db    "FAIL: no DOS2 mapper support (EXTBIO D=4)$"
msg_segtotal:   db    "Mapper segments total: $"
msg_segfree:    db    "Mapper segments free:  $"
msg_allocfail:  db    "FAIL: ALL_SEG returned CF$"
msg_alloc:      db    "ALL_SEG allocated seg: $"
msg_rwok:       db    "PUT_P1 map + RAM r/w at #4000: OK",13,10,"$"
msg_rwbad:      db    "FAIL: r/w through mapped segment$"
msg_ticks:      db    "H.TIMI ticks counted: $"
msg_ok:         db    13,10,"GBSPIKE OK",13,10,"$"
msg_crlf:       db    13,10,"$"

; V9938 palette: 2 bytes per entry, byte0 = R<<4 | B, byte1 = G (0..7 each)
pal_data:       db    #05,#00              ; pen 0: CPC ink 1 (blue)
                db    #77,#07              ; pen 1: CPC ink 26 (bright white)
                db    #00,#00              ; pen 2: CPC ink 0 (black)
                db    #70,#00              ; pen 3: CPC ink 6 (bright red)

; HMMV register block, streamed to R#36..R#46
cmd_dx:         dw    0                    ; R36-37 DX
cmd_dy:         dw    0                    ; R38-39 DY
cmd_nx:         dw    0                    ; R40-41 NX
cmd_ny:         dw    0                    ; R42-43 NY
cmd_clr:        db    0                    ; R44 colour byte
cmd_arg:        db    0                    ; R45 direction/expansion
cmd_cmd:        db    #C0                  ; R46 = HMMV

dosver:         db    0
seg_total:      db    0
seg_free:       db    0
test_seg:       db    0
tpa_p1:         db    0
rw_ok:          db    0
maptab:         dw    0
hook_save:      ds    5

spike_end:
                save"GBSPIKE.COM",#100,spike_end-#100
