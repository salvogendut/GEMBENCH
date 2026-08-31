# Headless GB-BASIC integration smoke test. The private image configures the
# built-in BASRUN graphics program as the one-minute saver. A matching window,
# loaded engine jump table and resident program text prove that boot, staging,
# overlay loading and interpreter startup all succeeded.

set throttle off
set ::gbb_deadline 210.0

proc gbb_mem {address} {
    return [debug read memory $address]
}

proc gbb_finish {status slot} {
    set out [open $::env(GEMBENCH_GBBASIC_OUTPUT) w]
    puts $out "STATUS=$status"
    puts $out "LIVE_WINDOWS=[gbb_mem 0x1350]"
    puts $out "FOCUS=[gbb_mem 0x1351]"
    puts $out [format "ENGINE_HEAD=%02X" [gbb_mem 0x2200]]
    puts $out [format "PROGRAM_HEAD=%02X,%02X,%02X" \
        [gbb_mem 0x3010] [gbb_mem 0x3011] [gbb_mem 0x3012]]
    if {$slot >= 0} {
        set base [expr {0x1352 + $slot * 25}]
        puts $out [format "BASRUN_SLOT=%d" $slot]
        puts $out [format "BASRUN_RECT=%d,%d,%d,%d" \
            [gbb_mem [expr {$base + 1}]] [gbb_mem [expr {$base + 2}]] \
            [gbb_mem [expr {$base + 3}]] [gbb_mem [expr {$base + 4}]]]
    }
    close $out
    exit
}

proc gbb_poll {} {
    set count [gbb_mem 0x1350]
    for {set slot 1} {$slot < $count && $slot < 8} {incr slot} {
        set base [expr {0x1352 + $slot * 25}]
        if {[gbb_mem [expr {$base + 1}]] == 8 &&
            [gbb_mem [expr {$base + 2}]] == 14 &&
            [gbb_mem [expr {$base + 3}]] == 64 &&
            [gbb_mem [expr {$base + 4}]] == 178} {
            if {[gbb_mem 0x2200] != 0xC3} {
                gbb_finish "FAIL engine overlay missing" $slot
            } elseif {[gbb_mem 0x3010] != 0x31 ||
                      [gbb_mem 0x3011] != 0x30 ||
                      [gbb_mem 0x3012] != 0x20} {
                gbb_finish "FAIL built-in program missing" $slot
            } else {
                gbb_finish PASS $slot
            }
            return
        }
    }
    if {[machine_info time] >= $::gbb_deadline} {
        gbb_finish "TIMEOUT waiting for BASRUN" -1
        return
    }
    after time 0.1 gbb_poll
}

after time 55.0 gbb_poll
