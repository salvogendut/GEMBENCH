; overscan_spike - bare-metal CRTC overscan test (experiment #79).
;
; Loaded + run by AMSDOS (RUN"SPIKE), then it goes bare metal: disables both ROMs,
; sets Mode 1, programs the 6845 CRTC for a large (over)scan with a 32K screen at
; #4000-#BFFF, and fills it with horizontal stripes so the displayed extent (how far
; it reaches into the border) is obvious. Halts. Purely to learn whether 1984 shows
; overscan and roughly how big - before touching GEOBENCH's renderer.
        org   #1200

GA      equ   #7F00            ; gate array port
CRTC_S  equ   #BC00            ; CRTC register select
CRTC_W  equ   #BD00            ; CRTC register write
SCR     equ   #4000            ; 32K screen base (#4000..#BFFF)

start
        di
        ld    sp,#3FFF          ; stack just below the screen

        ; --- gate array: Mode 1, both ROMs disabled (full 64K RAM) ---
        ld    bc,GA
        ld    a,#8D             ; 100011_01 = ROM regsel, upper+lower ROM off, mode 1
        out   (c),a

        ; --- palette: pens 0..3 + border, distinct so the screen vs border shows ---
        ld    hl,pal
        ld    e,0               ; pen number
pl_loop
        ld    bc,GA
        ld    a,e               ; PENR: select pen e
        out   (c),a
        ld    a,(hl)            ; PCR: hardware colour (already 0x40|c in the table)
        out   (c),a
        inc   hl
        inc   e
        ld    a,e
        cp    5                 ; pens 0..3 then the border (pen 16 below)
        jr    nz,pl_loop
        ld    bc,GA             ; border = pen 16
        ld    a,#10
        out   (c),a
        ld    a,(hl)
        out   (c),a

        ; --- CRTC: write registers 0..15 from the table ---
        ld    hl,crtc
        ld    d,0               ; register number
cr_loop
        ld    bc,CRTC_S
        out   (c),d             ; select register d
        ld    bc,CRTC_W
        ld    a,(hl)
        out   (c),a             ; write value
        inc   hl
        inc   d
        ld    a,d
        cp    16
        jr    nz,cr_loop

        ; --- fill the 32K screen with horizontal-ish stripes ---
        ; alternate #F0 / #0F every 8 bytes so we get a visible texture across the
        ; whole displayed area (the exact mapping doesn't matter - we just want to
        ; see how far the filled area reaches vs the border).
        ld    hl,SCR
        ld    de,#8000          ; 32K to fill
fl_loop
        ld    a,h
        and   #08               ; toggle pattern by a high bit of the address
        jr    z,fl_a
        ld    (hl),#F0
        jr    fl_next
fl_a
        ld    (hl),#0F
fl_next
        inc   hl
        dec   de
        ld    a,d
        or    e
        jr    nz,fl_loop

halt_loop
        jr    halt_loop

; palette (gate array hardware colour codes, 0x40 | colour):
;   pen0 blue, pen1 yellow, pen2 cyan, pen3 red, border green
pal     db    #44, #5E, #5B, #4C, #55

; CRTC registers 0..15 - first attempt at a large overscan (iterate from the shot):
;   R1=48 (96 bytes wide), R6=35 (280 lines), sync shifted to centre the bigger area,
;   R12/R13 = screen base for #4000 (page 1).
crtc    db    63               ; R0  horizontal total
        db    48               ; R1  horizontal displayed (chars; *2 bytes)
        db    50               ; R2  horizontal sync position
        db    #8E              ; R3  sync widths
        db    38               ; R4  vertical total
        db    0                ; R5  vertical total adjust
        db    35               ; R6  vertical displayed (char rows)
        db    35               ; R7  vertical sync position
        db    0                ; R8  interlace
        db    7                ; R9  max raster (8 lines/row)
        db    0                ; R10 cursor start
        db    0                ; R11 cursor end
        db    #10              ; R12 display start hi (page 1 = #4000)
        db    #00              ; R13 display start lo
        db    0                ; R14 cursor hi
        db    0                ; R15 cursor lo
spike_end
        save  "build/SPIKE.RAW",start,spike_end-start
