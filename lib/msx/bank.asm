; ---------------------------------------------------------------------------
; lib/msx/bank.asm - page-1 mapper-segment paging for the MSX2 target (#287).
;
; The MSX counterpart of lib/bank.asm. A "page value" is a DOS 2 memory-mapper
; SEGMENT NUMBER; switching goes through the DOS 2 mapper support routine
; PUT_P1 (address in the page-3 glue), never raw ports #FC-#FF - PUT_P1 also
; updates DOS's own page-1 shadow, which BDOS relies on to restore the user
; mapping around its calls (so loads straight into a mapped app segment work).
;
; Same interface + shadow discipline as the CPC pager: bank_set (A = segment),
; bank_normal (back to the TPA's own page-1 segment), bank_cur shadow.
; bank_page (bank,block) has no MSX meaning and is not provided - the app-page
; pool is built from ALL_SEG results (kernel/boot_msx.asm).
;
; CRITICAL (same as CPC): callers + stack must live outside #4000-#7FFF.
; ---------------------------------------------------------------------------

; bank_set: A = segment number -> map it at #4000-#7FFF and record it.
; Preserves the CPC contract (clobbers A,B,C at most).
bank_set
                ld    (bank_cur),a
                push  hl
                push  de
                ld    hl,(MSX_PUTP1)
                call  jp_hl
                pop   de
                pop   hl
                ret
jp_hl           jp    (hl)

; bank_normal: restore the TPA's own page-1 segment (the pre-GEOBENCH mapping).
bank_normal
                ld    a,(MSX_TPASEG)
                jr    bank_set
