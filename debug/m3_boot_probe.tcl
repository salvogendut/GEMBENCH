# Short architecture boot probe used by the Milestone-3 Screen 6/7 smoke test.
set throttle off
set pause_on_lost_focus false
set pause off

proc m3_probe_finish {} {
    set out [open $::env(GEMBENCH_M3_BOOT_OUTPUT) w]
    puts $out [format "PC=%04X" [reg PC]]
    puts $out [format "SP=%04X" [reg SP]]
    puts $out "NWIN=[peek 0x1350]"
    puts $out "FOCUS=[peek 0x1351]"
    puts $out "POOL_TOTAL=[peek 0xC2E4]"
    puts $out "SYS_SIZE=[peek 0xC2F0]"
    puts $out "SYS_VERSION=[peek 0xC2F1]"
    puts $out "DEFER_COUNT=[peek 0xC376]"
    close $out
    catch {screenshot -raw $::env(GEMBENCH_M3_BOOT_SCREENSHOT)}
    exit
}

after time 65.0 m3_probe_finish
