; ---------------------------------------------------------------------------
; lib/pcw/glue.inc - Amstrad PCW platform constants for GEOBENCH (#331).
;
; The PCW counterpart of the MSX glue: hardware ports and the fixed physical
; memory plan. The PCW is an all-RAM machine (no ROM, no firmware): four 16K
; CPU slots are mapped onto physical 16K blocks via ports #F0-#F3 (write
; bit7|block). GEOBENCH runs fully DI - all timing is polled.
;
; Physical block plan (256K = blocks 0-15, 512K = 0-31):
;   0      CPU slot 0 fixed: low-RAM contracts (#1000+)
;   1      roller table at #4000 (rest reserve)
;   2      CPU slot 2 fixed: kernel at GB_KERNEL=#8000, stack at top
;   3      keyboard matrix at offset #3FF0 (CPU #FFF0 when mapped in slot 3)
;   4-5    framebuffer (never CPU-mapped except while drawing)
;   6+     app bank pool
;
; CPU slot 3 (#C000-#FFFF) is a shared bank WINDOW: the screen driver maps
; blocks 4/5 into it per drawing row, the input driver maps block 3 to read
; the keyboard. Every user maps what it needs before use; nothing may assume
; slot 3 persists across calls. (Interrupts are off, so no ISR can interleave.)
;
; Video: 720x256 1bpp roller RAM, displayed by the 1985 emulator's
; video_mode=cga2 as 2bpp 360x256 (pixel i of a byte = (byte>>(6-2i))&3 -
; the MSX Screen 6 packing) with the FIXED palette 0=black 1=cyan 2=magenta
; 3=white. GEOBENCH assets stay in GB pen space (identical bytes to the MSX
; build); the driver permutes pens on the way to the screen:
;     GB pen 0 blue -> 1 cyan     GB pen 1 white -> 3 white
;     GB pen 2 black-> 0 black    GB pen 3 red   -> 2 magenta
; which is the bit transform h1=g0, h0=~g1, i.e. for a whole byte
;     screen = ((gb & #55)<<1) | ((~gb & #AA)>>1)
; so no lookup table is needed and pen-0 transparency masks keep working on
; the GB-space source bytes.
;
; The roller word for row address A (17-bit physical) is
;     w = ((A>>1) & #FFF8) | (A & 7)          (A bit3 must be 0)
; and the in-row layout is hardware-fixed char-cell interleave:
;     byte(xcol, y) = rowbase(y>>3) + xcol*8 + (y&7)
; GEOBENCH gives each cellrow a 1K-aligned home (720 of 1024 bytes used):
;     cellrow r -> phys #10000 + r*1024   (block 4 + (r>>4))
; The desktop is 248 lines (31 cellrows): heights up to 256 would overflow
; the byte-wide clip/fill cells. Scanlines 248-255 show cellrow 31, a static
; black letterbox strip painted once at init.
; ---------------------------------------------------------------------------

PCW_BANK0       equ   #F0          ; slot 0 (#0000) bank register
PCW_BANK1       equ   #F1          ; slot 1 (#4000) - the app paging window
PCW_BANK3       equ   #F3          ; slot 3 (#C000) - screen/keyboard window
PCW_SYSCTL      equ   #F8          ; system control (cmds) / status (read)
PCW_ROLLER      equ   #F5          ; roller-RAM base register
PCW_SCROLL      equ   #F6          ; vertical scroll
PCW_DISPCTL     equ   #F7          ; bit6 = screen enable, bit7 = inverse

PCW_BLK_KBD     equ   #80|3        ; keyboard block for the slot-3 window
PCW_BLK_SCR0    equ   #80|4        ; framebuffer, cellrows 0-15
PCW_BLK_SCR1    equ   #80|5        ; framebuffer, cellrows 16-31

PCW_RTABLE      equ   #4000        ; roller table: 512 bytes at the START of phys
                                   ; block 1 (otherwise unused; block 0's #3E00 is
                                   ; the kernel clipboard). Written once at video
                                   ; init through the identity slot-1 mapping.
PCW_RTREG       equ   #20          ; phys #4000 encoded for the roller base port

PCW_COLS        equ   90           ; byte columns (360 px at 4 px/byte)
PCW_LINES       equ   248          ; desktop lines (31 cellrows)

PCW_KBDMAT      equ   #FFF0        ; keyboard matrix (block 3 in slot 3)
