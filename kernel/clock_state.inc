; kernel/clock_state.inc - clock state emitted after memdetect to preserve layout.
; The software time aliases the public buffer. Besides reclaiming three resident
; bytes, this lets the app-linked CPC setter update the running clock without a
; new kernel routine.
sw_hour         equ   GB_TIME_BUF+0
sw_min          equ   GB_TIME_BUF+1
sw_sec          equ   GB_TIME_BUF+2
clk_frames      db    0
have_rtc        db    0
