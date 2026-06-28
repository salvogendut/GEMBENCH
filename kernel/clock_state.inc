; kernel/clock_state.inc - clock state emitted after memdetect to preserve layout.
sw_sec          db    0            ; software clock (when no RTC); advanced by sw_tick,
sw_min          db    0            ; read by gb_time. The desktop draws/formats the bar.
sw_hour         db    0
clk_frames      db    0
have_rtc        db    0
