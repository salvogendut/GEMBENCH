; ---------------------------------------------------------------------------
; lib/bank.asm - expansion-RAM bank paging for 128K+ machines.
;
; The gate-array RAM-config port (&7F00) selects which 16K block lives in the
; #4000-#7FFF window: value &C4 + bank*8 + block, where bank is the 64K
; expansion bank (0 = first expansion) and block is 0..3 (configs &C4..&C7,
; i.e. the four 16K blocks of that bank). Value &C0 restores the normal
; all-main-RAM layout. Configs &C4..&C7 swap ONLY #4000-#7FFF; #0000-#3FFF,
; #8000-#BFFF and the #C000 screen stay main RAM.
;
; The port is WRITE-ONLY, so the current selection can't be read back. We keep
; a shadow (bank_cur) so a kernel service can save the caller's page, swap to
; its own data page, then restore the caller's page.
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
; block into #4000-#7FFF and records it. Falls into bank_set. Clobbers A,B,C.
bank_page
                add   a,a
                add   a,a
                add   a,a                     ; A = bank*8
                or    #C4
                or    c                        ; A = &C4 + bank*8 + block
; bank_set: A = raw port value (e.g. a PAGE_* constant or &C0) -> page + record.
bank_set
                ld    (bank_cur),a
                ld    bc,BANK_PORT
                out   (c),a
                ret

; bank_normal: restore the normal all-main-RAM layout (&C0). Clobbers A,B,C.
bank_normal
                ld    a,#C0
                jr    bank_set

bank_cur        db    #C0          ; shadow of the current #4000-#7FFF paging
