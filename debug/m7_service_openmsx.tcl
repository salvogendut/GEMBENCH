# Architecture M7 target probe. FILEMGR.APP is replaced by the self-driving
# client A, so no coordinate-sensitive UI automation is needed.
set throttle off
set pause_on_lost_focus false
set pause off

set m7_output $::env(GEMBENCH_M7_SERVICE_OUTPUT)
set m7_k_poll [expr {$::env(GEMBENCH_M7_K_POLL)}]
set m7_deadline 0
set m7_page0_ppi -1
set m7_page0_secondary -1
set m7_slot_candidate -1
set m7_slot_samples 0
set m7_target_x 0
set m7_target_y 0
set m7_callback ""
set m7_poll_events {}
set m7_poll_bp ""

proc m7_byte {offset} { peek [expr {0xC040 + $offset}] }
proc m7_word {address} {
    expr {[peek $address] | ([peek [expr {$address + 1}]] << 8)}
}
proc m7_owner_count {} {
    set count 0
    for {set i 0} {$i < 8} {incr i} {
        if {[peek [expr {0xC2C0 + $i}]] != 0} {incr count}
    }
    return $count
}
proc m7_provider_count {} {
    set count 0
    for {set i 0} {$i < 2} {incr i} {
        if {[peek [expr {0xC884 + $i * 7 + 4}]] != 0} {incr count}
    }
    return $count
}
proc m7_lease_count {} {
    set count 0
    for {set i 0} {$i < 3} {incr i} {
        if {[peek [expr {0xC892 + $i * 4}]] != 0} {incr count}
    }
    return $count
}
proc m7_release_all {} {
    catch {keymatrixup 8 0x01}
    catch {keymatrixup 8 0x10}
    catch {keymatrixup 8 0x20}
    catch {keymatrixup 8 0x40}
    catch {keymatrixup 8 0x80}
}
proc m7_poll_after {delay callback} {
    after time $delay [list m7_poll_arm $callback]
}
proc m7_poll_arm {callback} {
    lappend ::m7_poll_events $callback
    if {$::m7_poll_bp eq ""} {
        set ::m7_poll_bp [debug set_bp $::m7_k_poll {} {m7_poll_tick}]
    }
}
proc m7_poll_tick {} {
    if {$::m7_poll_bp ne ""} {
        debug remove_bp $::m7_poll_bp
        set ::m7_poll_bp ""
    }
    set callbacks $::m7_poll_events
    set ::m7_poll_events {}
    foreach callback $callbacks {
        if {[catch {uplevel #0 $callback} message]} {
            m7_finish "ERROR poll callback: $message"
            return
        }
    }
    set ::pause off
}
proc m7_lowram_ready {} {
    expr {$::m7_page0_ppi >= 0 &&
          [debug read ioports 0xA8] == $::m7_page0_ppi &&
          [peek 0xFFFF] == $::m7_page0_secondary &&
          [peek 0x1350] <= 8 && [peek 0x1351] < 8 &&
          [peek 0x1306] <= 127 && [peek 0x1307] <= 211}
}
proc m7_move_tick {} {
    if {![m7_lowram_ready]} {
        if {[machine_info time] >= $::m7_deadline} {
            m7_finish "FAIL low RAM unavailable while moving pointer"
        } else {after time 0.002 m7_move_tick}
        return
    }
    set x [peek 0x1306]
    set y [peek 0x1307]
    m7_release_all
    if {[expr {abs($x - $::m7_target_x)}] <= 1 &&
        [expr {abs($y - $::m7_target_y)}] <= 3} {
        after time 0.08 $::m7_callback
        return
    }
    if {[machine_info time] >= $::m7_deadline} {
        m7_finish "FAIL pointer move timeout"
        return
    }
    if {$x < $::m7_target_x - 1} {
        set mask 0x80
    } elseif {$x > $::m7_target_x + 1} {
        set mask 0x10
    } elseif {$y < $::m7_target_y - 3} {
        set mask 0x40
    } else {
        set mask 0x20
    }
    keymatrixdown 8 $mask
    after time 0.08 [list keymatrixup 8 $mask]
    after time 0.16 m7_move_tick
}
proc m7_move_to {x y callback} {
    set ::m7_target_x $x
    set ::m7_target_y $y
    set ::m7_callback $callback
    set ::m7_deadline [expr {[machine_info time] + 30.0}]
    m7_move_tick
}
proc m7_double_second_up {} {
    keymatrixup 8 0x01
    set ::m7_deadline [expr {[machine_info time] + 45.0}]
    m7_poll_after 0.2 m7_poll
}
proc m7_double_second {} {
    keymatrixdown 8 0x01
    after time 0.16 m7_double_second_up
}
proc m7_double_first_up {} {
    keymatrixup 8 0x01
    after time 0.20 m7_double_second
}
proc m7_open_drive {} {
    keymatrixdown 8 0x01
    after time 0.16 m7_double_first_up
}

proc m7_finish {status} {
    m7_release_all
    set out [open $::m7_output w]
    puts $out "STATUS=$status"
    puts $out "PHASE=[m7_byte 1]"
    puts $out "FAILURE=[m7_byte 2]"
    puts $out "RESPONSES=[m7_byte 3]"
    puts $out "ROLLBACK_STATUS=[m7_byte 6]"
    puts $out "ACQUIRE_A=[m7_byte 7]"
    puts $out "DUPLICATE_A=[m7_byte 8]"
    puts $out "REQUEST_A=[m7_byte 9]"
    puts $out "ACQUIRE_B=[m7_byte 10]"
    puts $out "FOREIGN_B=[m7_byte 11]"
    puts $out "REQUEST_B=[m7_byte 12]"
    puts $out "ACQUIRE_C=[m7_byte 13]"
    puts $out "REQUEST_C=[m7_byte 14]"
    puts $out "ACQUIRE_D=[m7_byte 15]"
    puts $out "RELEASE_C=[m7_byte 16]"
    puts $out "RELEASE_A=[m7_byte 17]"
    puts $out "STALE_B=[m7_byte 18]"
    puts $out "REFS=[m7_byte 19],[m7_byte 20],[m7_byte 21],[m7_byte 22]"
    puts $out "PROVIDER_SEEN=[m7_byte 23]"
    puts $out "PROVIDER_GONE=[m7_byte 24]"
    puts $out "OWNERS=[m7_byte 25],[m7_byte 26],[m7_owner_count]"
    puts $out "LEASES=[m7_byte 27],[m7_lease_count]"
    puts $out "PROVIDERS=[m7_provider_count]"
    puts $out "LOCK=[peek 0xC89E]"
    puts $out "SYSINFO=[peek 0xC2F1],[format %04X [m7_word 0xC300]]"
    puts $out "RESP_STATUS=[m7_byte 41],[m7_byte 42],[m7_byte 43]"
    puts $out "WINDOWS=[peek 0x1350]"
    puts $out [format "FINAL_PC=%04X" [reg PC]]
    close $out
    exit
}

proc m7_poll {} {
    if {[m7_byte 0] == 0xA7} {
        set phase [m7_byte 1]
        if {$phase == 0xEE} {
            m7_finish "FAIL guest diagnostic [m7_byte 2]"
            return
        }
        if {$phase == 7} {
            if {[m7_byte 2] != 0 || [m7_byte 3] != 7 ||
                [m7_byte 6] != 10 ||
                [m7_byte 7] != 0 || [m7_byte 8] != 9 || [m7_byte 9] != 0 ||
                [m7_byte 10] != 0 || [m7_byte 11] != 3 || [m7_byte 12] != 0 ||
                [m7_byte 13] != 0 || [m7_byte 14] != 0 || [m7_byte 15] != 4 ||
                [m7_byte 16] != 0 || [m7_byte 17] != 0 || [m7_byte 18] != 2 ||
                [m7_byte 19] != 3 || [m7_byte 20] != 2 ||
                [m7_byte 21] != 1 || [m7_byte 22] != 0 ||
                [m7_byte 23] != 1 || [m7_byte 24] != 1 ||
                [m7_byte 25] != [m7_byte 26] ||
                [m7_byte 25] != [m7_owner_count] ||
                [m7_byte 27] != 0 || [m7_lease_count] != 0 ||
                [m7_provider_count] != 0 || [peek 0xC89E] != 0 ||
                [peek 0xC2F1] != 5 || ([m7_word 0xC300] & 0x4000) == 0 ||
                [m7_byte 41] != 11 || [m7_byte 42] != 11 ||
                [m7_byte 43] != 11} {
                m7_finish "FAIL final contract"
            } else {
                m7_finish PASS
            }
            return
        }
    }
    if {[machine_info time] >= $::m7_deadline} {
        m7_finish "TIMEOUT waiting for service lifecycle"
    } else {
        after time 0.1 m7_poll
    }
}

proc m7_desktop_ready {} {
    if {[peek 0x1350] == 1 && [peek 0x1351] == 0 &&
        [m7_owner_count] == 1 && [peek 0xC2F1] == 5} {
        set ppi [debug read ioports 0xA8]
        set secondary [peek 0xFFFF]
        set candidate [expr {($ppi << 8) | $secondary}]
        if {$candidate == $::m7_slot_candidate} {
            incr ::m7_slot_samples
        } else {
            set ::m7_slot_candidate $candidate
            set ::m7_slot_samples 1
        }
        if {$::m7_slot_samples >= 4} {
            set ::m7_page0_ppi $ppi
            set ::m7_page0_secondary $secondary
            m7_move_to 4 40 m7_open_drive
            return
        }
    }
    if {[machine_info time] >= $::m7_deadline} {
        m7_finish "FAIL Desktop readiness"
    } else {m7_poll_after 0.013 m7_desktop_ready}
}

proc m7_start {} {
    set ::m7_deadline [expr {[machine_info time] + 30.0}]
    m7_poll_after 0.0 m7_desktop_ready
}

after time 62.0 m7_start
after realtime 90.0 {m7_finish "TIMEOUT harness watchdog"}
