; ---------------------------------------------------------------------------
; lib/bank.asm - expansion-RAM bank paging for 128K+ machines.
;
; The gate-array RAM-config port (&7F00) selects which 16K block lives in the
; #4000-#7FFF window: value &C4 + bank*8 + block, where bank is the 64K
; expansion bank (0 = first expansion) and block is 0..3 (the four 16K blocks
; of that bank). Value &C0 restores the normal all-main-RAM layout. Configs
; &C4..&C7 swap ONLY #4000-#7FFF; #0000-#3FFF, #8000-#BFFF and the #C000 screen
; stay main RAM.
;
; CRITICAL: this code (and anything that calls it, plus its stack) MUST live
; outside the #4000-#7FFF window - i.e. >= #8000 (or < #4000) - or paging would
; swap the running code out from under itself. Call with interrupts disabled if
; an ISR might also touch the window.
;
; Matches the probe convention in desktop/main.asm (mem_detect / md_port).
; ---------------------------------------------------------------------------

BANK_PORT       equ   #7F00

; bank_page: A = bank index (0..n-1), C = 16K block (0..3). Pages that bank
; block into #4000-#7FFF. Clobbers A, B, C.
bank_page
                add   a,a
                add   a,a
                add   a,a                     ; A = bank*8
                or    #C4
                or    c                        ; A = &C4 + bank*8 + block
                ld    bc,BANK_PORT
                out   (c),a
                ret

; bank_normal: restore the normal all-main-RAM layout (&C0). Clobbers A, B, C.
bank_normal
                ld    bc,BANK_PORT
                ld    a,#C0
                out   (c),a
                ret
