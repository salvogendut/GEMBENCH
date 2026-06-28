; kernel/clock.asm - RTC/software clock service and GB_TIME.

; ===========================================================================
; Top bar (kernel-owned): total RAM (left) + clock (right) on lines 0-7. The
; kernel keeps the clock ticking via clock_tick in k_poll, so it stays live
; whatever app is focused. Apps must keep clear of the top 8 lines.
; ===========================================================================
CLK_COL         equ   68
TICKS_PER_SEC   equ   50
RTC_ADDR        equ   #FD15        ; Dallas RTC on SymbiFace II / Cyboard
RTC_DATA        equ   #FD14

; clock_tick: once per frame from k_poll. Advances the software clock (when there is
; no RTC) every 50 frames, so gb_time stays correct. The desktop draws the bar now,
; so there is no clock drawing here (#77).
clock_tick
                ld    a,(clk_frames)
                inc   a
                cp    TICKS_PER_SEC
                jr    c,ct_keep
                xor   a
                ld    (clk_frames),a
                ld    a,(have_rtc)
                or    a
                call  z,sw_tick
                ret
ct_keep
                ld    (clk_frames),a
                ret

clock_init                                      ; detect the RTC + seed the software clock
                xor   a
                ld    (sw_sec),a
                ld    (sw_min),a
                ld    (sw_hour),a
                ld    (clk_frames),a
                call  rtc_detect
                ret
rtc_detect
                ld    e,#5A
                call  rtc_nvram_rw
                cp    #5A
                jr    nz,rd_none
                ld    e,#A5
                call  rtc_nvram_rw
                cp    #A5
                jr    nz,rd_none
                ld    a,1
                ld    (have_rtc),a
                ret
rd_none
                xor   a
                ld    (have_rtc),a
                ret
rtc_nvram_rw                                   ; E = value -> A = read-back of NVRAM 0x0E
                ld    a,#0E
                ld    bc,RTC_ADDR
                out   (c),a
                ld    bc,RTC_DATA
                out   (c),e
                ld    a,#0E
                ld    bc,RTC_ADDR
                out   (c),a
                ld    bc,RTC_DATA
                in    a,(c)
                ret
read_rtc_reg                                   ; A = reg -> A = value
                ld    bc,RTC_ADDR
                out   (c),a
                ld    bc,RTC_DATA
                in    a,(c)
                ret
; (read_time / put_bcd2 / bin_to_bcd removed: the desktop formats the clock from
; gb_time now - #77. sw_tick stays: it advances the software clock for gb_time.)
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

; k_time (GB_TIME #808D): current time -> GB_TIME_BUF (raw h, m, s + binmode). From
; the Dallas RTC (regs 4/2/0; binmode = reg B bit2) or the software clock (binary).
; The app converts BCD->binary when binmode is 0. Kept tiny (#72).
k_time
                ld    a,(have_rtc)
                or    a
                jr    z,kt_soft
                ld    a,#0B
                call  read_rtc_reg
                and   #04
                ld    (GB_TIME_BUF+3),a       ; binmode (0 = BCD)
                ld    a,#04
                call  read_rtc_reg
                and   #3F
                ld    (GB_TIME_BUF+0),a
                ld    a,#02
                call  read_rtc_reg
                ld    (GB_TIME_BUF+1),a
                ld    a,#00
                call  read_rtc_reg
                ld    (GB_TIME_BUF+2),a
                ret
kt_soft
                ld    a,(sw_hour)
                ld    (GB_TIME_BUF+0),a
                ld    a,(sw_min)
                ld    (GB_TIME_BUF+1),a
                ld    a,(sw_sec)
                ld    (GB_TIME_BUF+2),a
                ld    a,4                       ; nonzero -> already binary, no convert
                ld    (GB_TIME_BUF+3),a
                ret
