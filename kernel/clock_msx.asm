; kernel/clock_msx.asm - software clock for the MSX2 target (#287).
;
; M1 keeps the CPC's RTC-less path only: clock_tick advances a software clock
; once per 50 frames from k_poll, and GB_TIME reports it as already-binary.
; The MSX's own RTC (ports #B4/#B5) joins in a later milestone.

clock_tick
                ld    a,(clk_frames)
                inc   a
                ld    hl,msx_tps              ; 50 (PAL) or 60 (NTSC), set at clock_init
                cp    (hl)
                jr    c,ct_keep
                xor   a
                ld    (clk_frames),a
                call  sw_tick
                ret
ct_keep
                ld    (clk_frames),a
                ret

clock_init
                xor   a
                ld    (sw_sec),a
                ld    (sw_min),a
                ld    (sw_hour),a
                ld    (clk_frames),a
                ld    (have_rtc),a
                ld    a,(#FFE8)               ; RG9SAV: R#9 NT bit1 = 1 -> PAL/50Hz
                and   #02
                ld    a,50
                jr    nz,ci_tps
                ld    a,60                    ; NTSC machine -> 60 ticks per second
ci_tps
                ld    (msx_tps),a
                ret
msx_tps         db    50

sw_tick
                ld    a,(sw_sec)
                inc   a
                cp    60
                jr    c,swt_sec
                xor   a
                ld    (sw_sec),a
                ld    a,(sw_min)
                inc   a
                cp    60
                jr    c,swt_min
                xor   a
                ld    (sw_min),a
                ld    a,(sw_hour)
                inc   a
                cp    24
                jr    c,swt_hour
                xor   a
swt_hour
                ld    (sw_hour),a
                ret
swt_min
                ld    (sw_min),a
                ret
swt_sec
                ld    (sw_sec),a
                ret

; k_time (GB_TIME): software clock -> GB_TIME_BUF, flagged already-binary.
k_time
                ld    a,(sw_hour)
                ld    (GB_TIME_BUF+0),a
                ld    a,(sw_min)
                ld    (GB_TIME_BUF+1),a
                ld    a,(sw_sec)
                ld    (GB_TIME_BUF+2),a
                ld    a,4
                ld    (GB_TIME_BUF+3),a
                ret

; k_settime (GB_RUN on MSX): set the software clock from binary B=hour C=min D=sec.
k_settime
                ld    a,b
                cp    24
                ret   nc
                ld    a,c
                cp    60
                ret   nc
                ld    a,d
                cp    60
                ret   nc
                ld    a,b
                ld    (sw_hour),a
                ld    a,c
                ld    (sw_min),a
                ld    a,d
                ld    (sw_sec),a
                xor   a
                ld    (clk_frames),a
                ret
