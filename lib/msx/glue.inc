; ---------------------------------------------------------------------------
; lib/msx/glue.inc - the page-3 resident glue cells for the MSX2 target (#287).
;
; #C000-#F37F is ordinary TPA RAM under MSX-DOS (the screen lives in VRAM), and
; unlike pages 0-2 it is NEVER remapped: not by our own segment switching, and -
; crucially - not by the BIOS interrupt, which runs the H.TIMI hook with the
; BIOS ROM in page 0 (the M0 spike found handlers in page 0/1 are invisible at
; interrupt time). Everything the ISR or the mapper path touches lives here.
;
; The bootstrap stub (kernel/msx_stub.asm) fills these before jumping to
; GB_INIT; the kernel treats them as read-mostly platform facts.
; ---------------------------------------------------------------------------

MSX_TICK        equ   #C000        ; word: H.TIMI frame counter (the 50/60Hz pace base)
MSX_HOOKCODE    equ   #C004        ; the relocated H.TIMI handler lives here (<=12 bytes)
MSX_ALLSEG      equ   #C010        ; word: ALL_SEG entry (DOS 2 mapper support routine)
MSX_FRESEG      equ   #C012        ; word: FRE_SEG entry
MSX_PUTP1       equ   #C014        ; word: PUT_P1 entry (switch page 1 + DOS shadow)
MSX_GETP1       equ   #C016        ; word: GET_P1 entry
MSX_TPASEG      equ   #C018        ; byte: the TPA's own page-1 segment (= "bank_normal")
MSX_TOTSEG      equ   #C019        ; byte: primary-mapper total segments
MSX_FREESEG     equ   #C01A        ; byte: primary-mapper free segments at entry
MSX_HOOKSAVE    equ   #C01B        ; 5 bytes: original H.TIMI content (restored on exit)
MSX_PAGE_DATA   equ   #C020        ; byte: the allocated PAGE_DATA mapper segment
MSX_ROWBUF      equ   #C080        ; 128-byte row buffer for VRAM read-modify-write
MSX_BDSTRIP     equ   #C100        ; 16 x 128-byte pre-rendered backdrop tile strip
                                   ; (#C100..#C8FF; fill_pattern streams rows from it)
; NOTE (#287 M1 debugging): DOS 2 / Nextor's kernel data occupies page 3 well
; below #F380 (the mapper jump table itself sits around #F200, jumping into
; code near #EC00) - the DOS 1 "system area starts at #F380" rule does NOT
; hold. The real TPA ceiling is the BDOS entry pointer at #0006/7: the stub
; sets SP from it, and everything fixed here stays at #C000..#C8FF, which the
; stub verifies is below that ceiling.
MSX_GLUE_TOP    equ   #C900        ; end of the fixed glue area (stub-verified < TPA top)
