; kernel/clock_msx_rtc.asm - MSX2 RP-5C01 startup-time reader.
;
; This sits after the MSX screen driver's page-aligned picture lookup tables.
; Keeping it there avoids turning a small clock reader into 256 bytes of padding.

; Read two consecutive decimal-digit registers, starting at A, and return their
; binary value. D/E are scratch; B keeps the caller's saved RTC mode.
msx_rtc_read_pair
                out   (MSX_RTC_ADDR),a
                in    a,(MSX_RTC_DATA)
                and   #0F
                ld    e,a
                inc   c
                ld    a,c
                out   (MSX_RTC_ADDR),a
                in    a,(MSX_RTC_DATA)
                and   #0F
                ld    d,a
                add   a,a
                add   a,a
                add   a,d
                add   a,a
                add   a,e
                ret

; Seed sw_hour/min/sec from RTC block 0. The mode register is restored before
; returning. Reading seconds on both sides of minutes/hours avoids a mixed value
; when the RTC rolls over during the read. Carry means a valid HH:MM:SS result.
msx_rtc_read_time
                ld    a,MSX_RTC_MODE
                out   (MSX_RTC_ADDR),a
                in    a,(MSX_RTC_DATA)
                and   #0F
                ld    b,a
                and   #0C                    ; preserve timer/alarm, select block 0
                ld    d,a
                ld    a,MSX_RTC_MODE
                out   (MSX_RTC_ADDR),a
                ld    a,d
                out   (MSX_RTC_DATA),a
mrr_retry
                ld    c,0
                ld    a,c
                call  msx_rtc_read_pair
                cp    60
                jr    nc,mrr_bad
                ld    (sw_sec),a
                ld    c,2
                ld    a,c
                call  msx_rtc_read_pair
                cp    60
                jr    nc,mrr_bad
                ld    (sw_min),a
                ld    c,4
                ld    a,c
                call  msx_rtc_read_pair
                cp    24
                jr    nc,mrr_bad
                ld    (sw_hour),a
                ld    c,0
                ld    a,c
                call  msx_rtc_read_pair
                ld    hl,sw_sec
                cp    (hl)
                jr    nz,mrr_retry
                scf
                jr    mrr_restore
mrr_bad
                or    a                       ; clear carry
mrr_restore
                push  af
                ld    a,MSX_RTC_MODE
                out   (MSX_RTC_ADDR),a
                ld    a,b
                out   (MSX_RTC_DATA),a
                pop   af
                ret
