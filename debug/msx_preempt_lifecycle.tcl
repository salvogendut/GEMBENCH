set throttle off
set pause_on_lost_focus false
set pause off
set lifecycle_lines {}
set lifecycle_uninstall_seen 0
set lifecycle_active_vector {}
set lifecycle_failed 0

proc lifecycle_keep_running {} {
    set ::pause off
    after realtime 0.25 lifecycle_keep_running
}

proc lifecycle_flush {} {
    set handle [open "build/msx/preempt-lifecycle.txt" w]
    foreach line $::lifecycle_lines { puts $handle $line }
    close $handle
}

proc lifecycle_sample {label} {
    lappend ::lifecycle_lines [format \
        "%s PC=%04X CUR=%02X RUN=%02X LOCK=%02X BANK=%02X MAX=%02X FAULT=%02X FOCUS=%02X POLL=%02X/%02X/%02X FLAGS=%02X,%02X,%02X VECTOR=%02X%02X%02X" \
        $label [reg PC] [peek 0x1342] [peek 0x1344] [peek 0x1340] \
        [peek 0x134F] [peek 0x1346] [peek 0x1347] [peek 0x1351] \
        [peek 0x1306] [peek 0x1307] [peek 0x1308] \
        [peek 0x135F] [peek 0x1378] [peek 0x1391] [peek 0x0038] [peek 0x0039] [peek 0x003A]]
    lifecycle_flush
}

proc lifecycle_fail {message} {
    set ::lifecycle_failed 1
    lappend ::lifecycle_lines "FAIL $message"
    lifecycle_flush
}

proc after_delta {delta command} {
    after time $delta $command
}

proc press_escape {} {
    keymatrixdown 7 0x04
}

proc wait_closed {target label next_command} {
    if {[peek 0x1344] == $target} {
        keymatrixup 7 0x04
        if {[peek 0x1347] != 0} { lifecycle_fail "scheduler stack fault after $label" }
        set closed_slot $target
        if {[peek [expr {0x135F + $closed_slot * 25}]] != 0} {
            lifecycle_fail "slot $closed_slot still alive after $label"
        }
        lifecycle_sample $label
        after_delta 0.10 $next_command
    } elseif {[machine_info time] >= $::lifecycle_deadline} {
        keymatrixup 7 0x04
        lappend ::lifecycle_lines "TIMEOUT waiting for runnable count $target"
        lifecycle_finish
    } else {
        after_delta 0.005 [list wait_closed $target $label $next_command]
    }
}

proc close_second {} {
    press_escape
    wait_closed 1 CLOSED_A request_exit
}

proc request_exit {} {
    if {[peek 0x1342] == 0} {
        lifecycle_sample BEFORE_EXIT
        reg PC 0x8090
        after_delta 0.10 wait_dos
    } else {
        after_delta 0.005 request_exit
    }
}

proc lifecycle_uninstalled {} {
    set ::lifecycle_uninstall_seen 1
    lifecycle_sample UNINSTALLED
}

proc wait_dos {} {
    set vector [list [peek 0x0038] [peek 0x0039] [peek 0x003A]]
    set active [expr {$vector eq $::lifecycle_active_vector}]
    if {$::lifecycle_uninstall_seen && !$active} {
        lifecycle_sample DOS
        if {!$::lifecycle_failed} { lappend ::lifecycle_lines "STATUS=PASS" }
        lifecycle_finish
    } elseif {[machine_info time] >= $::lifecycle_deadline} {
        lifecycle_sample EXIT_TIMEOUT
        lappend ::lifecycle_lines "TIMEOUT waiting for DOS vector restoration"
        lifecycle_flush
        lifecycle_finish
    } else {
        after_delta 0.01 wait_dos
    }
}

proc lifecycle_finish {} {
    lifecycle_flush
    exit
}

proc lifecycle_start {} {
    set ::lifecycle_deadline [expr {[machine_info time] + 8.0}]
    set ::lifecycle_active_vector [list [peek 0x0038] [peek 0x0039] [peek 0x003A]]
    if {([peek 0x1378] & 0x0B) != 0x0B || ([peek 0x1391] & 0x0B) != 0x0B} {
        lifecycle_fail "workers are not managed runnable windows"
    }
    lifecycle_sample START
    press_escape
    wait_closed 2 CLOSED_B close_second
}

proc wait_ready {} {
    if {[peek 0x1344] == 3 && [peek 0x0038] == 0xC3 && [peek 0x003A] >= 0xC9} {
        lifecycle_start
    } elseif {[machine_info time] >= 60.0} {
        lappend ::lifecycle_lines "TIMEOUT waiting for preemptive desktop"
        lifecycle_finish
    } else {
        after_delta 0.10 wait_ready
    }
}

lappend lifecycle_lines "SCRIPT loaded"
lifecycle_flush
debug set_bp 0x8130 {} {lifecycle_uninstalled}
after realtime 0.25 lifecycle_keep_running
after time 10.0 wait_ready
