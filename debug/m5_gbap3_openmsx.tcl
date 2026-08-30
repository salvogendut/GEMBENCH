# Validate GBAP v3 guarded publication/rollback by replacing FILEMGR.APP in a
# disposable image. The Desktop drive icon launches the candidate through the
# ordinary owner/page loader.
set throttle off
set pause_on_lost_focus false
set pause off

set m5_mode $::env(GEMBENCH_M5_MODE)
set m5_output $::env(GEMBENCH_M5_OUTPUT)
set m5_k_poll [expr {$::env(GEMBENCH_M5_K_POLL)}]
set m5_main [expr {$::env(GEMBENCH_M5_MAIN)}]
set m5_entry [expr {$::env(GEMBENCH_M5_ENTRY)}]
set m5_pages [expr {$::env(GEMBENCH_M5_PAGES)}]
set m5_deadline 0
set m5_target_x 0
set m5_target_y 0
set m5_callback ""
set m5_initial_free 0
set m5_guard_hits 0
set m5_main_hits 0
set m5_page0_ppi -1
set m5_page0_secondary -1
set m5_slot_candidate -1
set m5_slot_samples 0
set m5_poll_events {}
set m5_poll_bp ""

proc m5_owner_count {} {
    set count 0
    for {set i 0} {$i < 8} {incr i} {
        if {[peek [expr {0xC2C0 + $i}]] != 0} {incr count}
    }
    return $count
}

proc m5_release_all {} {
    catch {keymatrixup 8 0x01}
    catch {keymatrixup 8 0x10}
    catch {keymatrixup 8 0x20}
    catch {keymatrixup 8 0x40}
    catch {keymatrixup 8 0x80}
}

proc m5_poll_after {delay callback} {
    after time $delay [list m5_poll_arm $callback]
}

proc m5_poll_arm {callback} {
    lappend ::m5_poll_events $callback
    if {$::m5_poll_bp eq ""} {
        set ::m5_poll_bp [debug set_bp $::m5_k_poll {} {m5_poll_tick}]
    }
}

proc m5_poll_tick {} {
    if {$::m5_poll_bp ne ""} {
        debug remove_bp $::m5_poll_bp
        set ::m5_poll_bp ""
    }
    set callbacks $::m5_poll_events
    set ::m5_poll_events {}
    foreach callback $callbacks {
        if {[catch {uplevel #0 $callback} message]} {
            m5_finish "ERROR poll callback: $message"
            return
        }
    }
    set ::pause off
}

proc m5_trace_guard {} {
    if {[peek 0xC2E0] || [peek 0xC2E1]} {incr ::m5_guard_hits}
    set ::pause off
}

proc m5_trace_main {} {
    if {[peek 0xC2E0] || [peek 0xC2E1]} {incr ::m5_main_hits}
    set ::pause off
}

proc m5_lowram_ready {} {
    expr {$::m5_page0_ppi >= 0 &&
          [debug read ioports 0xA8] == $::m5_page0_ppi &&
          [peek 0xFFFF] == $::m5_page0_secondary &&
          [peek 0x1350] <= 8 && [peek 0x1351] < 8 &&
          [peek 0x1306] <= 127 && [peek 0x1307] <= 211}
}

proc m5_finish {status} {
    m5_release_all
    set out [open $::m5_output w]
    puts $out "STATUS=$status"
    puts $out "MODE=$::m5_mode"
    puts $out "GUARD_HITS=$::m5_guard_hits"
    puts $out "MAIN_HITS=$::m5_main_hits"
    puts $out "INITIAL_FREE=$::m5_initial_free"
    puts $out "FINAL_FREE=[peek 0xC2E5]"
    puts $out "ACTIVE_OWNERS=[m5_owner_count]"
    puts $out "LIVE_WINDOWS=[peek 0x1350]"
    puts $out [format "PENDING_OWNER=%04X" \
        [expr {[peek 0xC2E0] | ([peek 0xC2E1] << 8)}]]
    puts $out [format "FINAL_PC=%04X" [reg PC]]
    close $out
    exit
}

proc m5_after {delay callback} {
    after time $delay $callback
}

proc m5_move_tick {} {
    if {![m5_lowram_ready]} {
        if {[machine_info time] >= $::m5_deadline} {
            m5_finish "FAIL low RAM unavailable while moving pointer"
        } else {m5_after 0.002 m5_move_tick}
        return
    }
    set x [peek 0x1306]
    set y [peek 0x1307]
    m5_release_all
    if {[expr {abs($x - $::m5_target_x)}] <= 1 &&
        [expr {abs($y - $::m5_target_y)}] <= 3} {
        m5_after 0.08 $::m5_callback
        return
    }
    if {[machine_info time] >= $::m5_deadline} {
        m5_finish "FAIL pointer move timeout"
        return
    }
    if {$x < $::m5_target_x - 1} {
        set mask 0x80
    } elseif {$x > $::m5_target_x + 1} {
        set mask 0x10
    } elseif {$y < $::m5_target_y - 3} {
        set mask 0x40
    } else {
        set mask 0x20
    }
    keymatrixdown 8 $mask
    m5_after 0.08 [list keymatrixup 8 $mask]
    m5_after 0.16 m5_move_tick
}

proc m5_move_to {x y callback} {
    set ::m5_target_x $x
    set ::m5_target_y $y
    set ::m5_callback $callback
    set ::m5_deadline [expr {[machine_info time] + 30.0}]
    m5_move_tick
}

proc m5_double_second_up {} {
    keymatrixup 8 0x01
    set ::m5_deadline [expr {[machine_info time] + 20.0}]
    m5_poll_after 1.0 m5_wait_result
}

proc m5_double_second {} {
    keymatrixdown 8 0x01
    m5_after 0.16 m5_double_second_up
}

proc m5_double_first_up {} {
    keymatrixup 8 0x01
    m5_after 0.20 m5_double_second
}

proc m5_open_drive {} {
    debug set_bp $::m5_entry {} {m5_trace_guard}
    debug set_bp $::m5_main {} {m5_trace_main}
    keymatrixdown 8 0x01
    m5_after 0.16 m5_double_first_up
}

proc m5_wait_result {} {
    if {![m5_lowram_ready]} {
        if {[machine_info time] >= $::m5_deadline} {
            m5_finish "FAIL low RAM unavailable after launch"
        } else {m5_poll_after 0.05 m5_wait_result}
        return
    }
    set windows [peek 0x1350]
    set owners [m5_owner_count]
    set free [peek 0xC2E5]
    set pending [expr {[peek 0xC2E0] | ([peek 0xC2E1] << 8)}]
    if {$::m5_mode eq "good"} {
        if {$::m5_guard_hits >= 1 && $::m5_main_hits >= 1 &&
            $windows == 2 && $owners == 2 &&
            $free + $::m5_pages == $::m5_initial_free && $pending == 0} {
            m5_finish PASS
            return
        }
    } else {
        if {$::m5_guard_hits >= 1 && $::m5_main_hits == 0 &&
            $windows == 1 && $owners == 1 &&
            $free == $::m5_initial_free && $pending == 0} {
            m5_finish PASS
            return
        }
    }
    if {[machine_info time] >= $::m5_deadline} {
        m5_finish "FAIL guarded launch state"
    } else {m5_poll_after 0.1 m5_wait_result}
}

proc m5_desktop_ready {} {
    if {[peek 0x1350] == 1 && [peek 0x1351] == 0 &&
        [m5_owner_count] == 1 && [peek 0xC2F0] >= 20} {
        set ppi [debug read ioports 0xA8]
        set secondary [peek 0xFFFF]
        set candidate [expr {($ppi << 8) | $secondary}]
        if {$candidate == $::m5_slot_candidate} {
            incr ::m5_slot_samples
        } else {
            set ::m5_slot_candidate $candidate
            set ::m5_slot_samples 1
        }
        if {$::m5_slot_samples >= 4} {
            set ::m5_page0_ppi $ppi
            set ::m5_page0_secondary $secondary
            set ::m5_initial_free [peek 0xC2E5]
            m5_move_to 4 40 m5_open_drive
            return
        }
    }
    if {[machine_info time] >= $::m5_deadline} {
        m5_finish "FAIL Desktop readiness"
    } else {m5_poll_after 0.013 m5_desktop_ready}
}

proc m5_start {} {
    set ::m5_deadline [expr {[machine_info time] + 30.0}]
    m5_poll_after 0.0 m5_desktop_ready
}

m5_after 62.0 m5_start
after realtime 60.0 {m5_finish "TIMEOUT harness watchdog"}
