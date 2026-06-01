; ---------------------------------------------------------------------------
; savetest - validate save_block / restore_block (screen-RAM read path).
;
;   1. blit the floppy at (10,50)
;   2. save_block that 8x32 region into a buffer  (screen READ, ROM paged out)
;   3. blit the floppy again at (10,96) as an untouched reference
;   4. blit the CLOCK over (10,50)                (overwrite the saved region)
;   5. restore_block -> (10,50) should become the floppy again
;
; PASS: both (10,50) and (10,96) show the floppy (top one is restored).
; FAIL: top shows the clock (restore did nothing) or garbage (read read ROM).
;
; Build: rasm tests/savetest.asm -eo   (-> build/savetest.dsk, SAVETEST.BIN)
; ---------------------------------------------------------------------------

                include "../lib/firmware.inc"

                org   #4000
savetest
                jp    start
                include "../lib/screen.asm"
                include "../lib/icon_floppy.asm"
                include "../lib/icon_clock.asm"

start
                ld    a,1
                call  SCR_SET_MODE
                call  TXT_CUR_DISABLE
                call  set_palette

                ld    hl,icon_floppy         ; 1) floppy at (10,50)
                ld    b,10
                ld    c,50
                call  blit_at

                ld    a,10                   ; 2) save that region
                ld    (sb_x),a
                ld    a,50
                ld    (sb_y),a
                ld    a,8
                ld    (sb_w),a
                ld    a,32
                ld    (sb_h),a
                ld    hl,savebuf
                ld    (sb_buf),hl
                call  save_block

                ld    hl,icon_floppy         ; 3) reference floppy at (10,96)
                ld    b,10
                ld    c,96
                call  blit_at

                ld    hl,icon_clock          ; 4) overwrite (10,50) with the clock
                ld    b,10
                ld    c,50
                call  blit_at

                call  restore_block          ; 5) restore the floppy at (10,50)
idle            jr    idle

; blit_at: HL = bitmap, B = xbyte, C = y. (8x32 icons.)
blit_at
                ld    (bm_src),hl
                ld    a,b
                ld    (bm_x),a
                ld    a,c
                ld    (bm_y),a
                ld    a,8
                ld    (bm_w),a
                ld    a,32
                ld    (bm_h),a
                jp    blit_bitmap

set_palette
                ld    a,0
                ld    b,1
                ld    c,1
                call  SCR_SET_INK
                ld    a,1
                ld    b,26
                ld    c,26
                call  SCR_SET_INK
                ld    a,2
                ld    b,0
                ld    c,0
                call  SCR_SET_INK
                ld    a,3
                ld    b,6
                ld    c,6
                call  SCR_SET_INK
                ld    b,1
                ld    c,1
                call  SCR_SET_BORDER
                ret

savebuf         defs  8*32

end
                save  "SAVETEST.BIN",savetest,end-savetest,DSK,"build/savetest.dsk"
