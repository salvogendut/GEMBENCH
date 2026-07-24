; ---------------------------------------------------------------------------
; lib/msx/bios.inc - MSX2 system equates for the GEOBENCH MSX-DOS 2 target (#287).
;
; The MSX counterpart of lib/firmware.inc: equates only, no code. The kernel
; runs as a Nextor/MSX-DOS 2 application, so file I/O goes through the BDOS
; entry in page 0 and the machine services come from the main BIOS ROM via
; inter-slot calls (CALSLT). The V9938 is driven directly through its ports.
; ---------------------------------------------------------------------------

; --- MSX-DOS 2 (BDOS entry + function numbers used) ------------------------
BDOS            equ   #0005        ; jp into the DOS kernel dispatcher
_TERM0          equ   #00          ; program terminate (CP/M style)
_ALLOC          equ   #1B          ; get allocation info (free space)
_FFIRST         equ   #40          ; find first entry -> FIB at IX
_FNEXT          equ   #41          ; find next entry (FIB from _FFIRST)
_DOPEN          equ   #43          ; open file handle: DE=ASCIIZ, A=mode
_CREATE         equ   #44          ; create/truncate: DE=ASCIIZ, A=mode, B=attr
_DCLOSE         equ   #45          ; close file handle: B=handle
_READ           equ   #48          ; read: B=handle DE=buf HL=count -> HL=actual
_WRITE          equ   #49          ; write: B=handle DE=buf HL=count
_SEEK           equ   #4A          ; seek: B=handle A=method(0=start,2=end) DE:HL=offset
_DELETE         equ   #4D          ; delete: DE=ASCIIZ
_GETCD          equ   #59          ; get current directory: B=drive DE=64B buf
_CHDIR          equ   #5A          ; change current directory: DE=ASCIIZ
_DOSVER         equ   #6F          ; get DOS version: B=kernel major

FIB_NAME        equ   1            ; FIB offsets: +1..13 ASCIIZ filename
FIB_ATTR        equ   14           ;              +14 attributes byte
FIB_SIZE        equ   21           ;              +21..24 file size (LE)

; --- main BIOS entries (via CALSLT; IY high = (EXPTBL)) ---------------------
CALSLT          equ   #001C        ; inter-slot call: IX=address, IYh=slot
CHGMOD          equ   #005F        ; A = screen mode
INITXT          equ   #006C        ; init 40-col text mode (exit path)
INIPLT          equ   #0141        ; SUB-ROM: reset the MSX2 palette + VRAM mirror
GTSTCK          equ   #00D5        ; A = stick id (0 kbd, 1/2 joy) -> A = 0..8
GTTRIG          equ   #00D8        ; A = trigger id (0 space, 1..4) -> A = 0/FF
GTPAD           equ   #00DB        ; A = pad function -> A (12/13/14 = mouse latch/X/Y)
CHSNS           equ   #009C        ; ZF clear if a key is waiting
CHGET           equ   #009F        ; A = next char (blocking - gate with CHSNS)
SNSMAT          equ   #0141        ; A = keyboard matrix row -> A = bits (0=held)

EXPTBL          equ   #FCC1        ; main BIOS slot byte (page-3 system RAM)
EXBRSA          equ   #FAF8        ; MSX2 SUB-ROM slot byte (for RST #30 CALLF)
JIFFY           equ   #FC9E        ; BIOS 50/60Hz frame counter (word)
H_TIMI          equ   #FD9F        ; VBLANK interrupt hook (5 bytes)
EXTBIO          equ   #FFCA        ; extended BIOS hook (mapper support)

; --- V9938 -------------------------------------------------------------------
VDP_DATA        equ   #98          ; VRAM data (autoincrement)
VDP_CTRL        equ   #99          ; VRAM address / register / status
VDP_PAL         equ   #9A          ; palette data pairs (after R#16)
VDP_IND         equ   #9B          ; indirect register data (after R#17)

                ifdef MSX_SCREEN7
; Screen 7 / Graphic 6: 512x212, 16 colours, 4bpp linear -> 256 bytes/line.
; Page 0 occupies VRAM #00000..#0D3FF; CHGMOD places the sprite tables above it.
MSX_SCREEN_MODE equ   7
SPR_PATTERN     equ   #F000
SPR_COLOUR      equ   #F800
SPR_ATTR        equ   #FA00
                else
; Screen 6 / Graphic 5: 512x212, 4 colours, 2bpp linear -> 128 bytes/line.
; These are the table addresses installed by CHGMOD 6.
MSX_SCREEN_MODE equ   6
SPR_PATTERN     equ   #7800
SPR_COLOUR      equ   #7400
SPR_ATTR        equ   #7600
                endif

MSX_KEY_ESC     equ   2            ; ESC = keyboard matrix row 7, bit 2
