# Exercise GB_SYSINFO, GB_OWNER and GB_PAGE, then verify owner teardown/reuse.
set throttle off
set pause_on_lost_focus false
set pause off

set m1_tests [expr {$::env(GEMBENCH_M1_TESTS)}]
set m1_initial [expr {$::env(GEMBENCH_M1_INITIAL)}]
set m1_final [expr {$::env(GEMBENCH_M1_FINAL)}]
set m1_owner [expr {$::env(GEMBENCH_M1_OWNER)}]
set m1_retained [expr {$::env(GEMBENCH_M1_RETAINED)}]
set m1_output $::env(GEMBENCH_M1_OUTPUT)
set m1_screenshot $::env(GEMBENCH_M1_SCREENSHOT)
set m1_deadline 0
set m1_target_x 0
set m1_target_y 0
set m1_callback ""
set m1_first_owner 0
set m1_first_initial 0
set m1_first_final 0
set m1_first_closed_free 0
set m1_second_owner 0
set m1_second_initial 0
set m1_second_final 0
set m1_final_free 0
set m1_first_gen 0
set m1_closed_gen 0
set m1_second_gen 0
set m1_first_window_gen 0
set m1_second_window_gen 0
set m1_page0_slot -1
set m1_page0_ppi -1
set m1_page0_secondary -1
set m1_slot_candidate -1
set m1_slot_samples 0

proc m1_word {address} {
    expr {[peek $address] + 256 * [peek [expr {$address + 1}]]}
}

proc m1_owner_count {} {
    set count 0
    for {set i 0} {$i < 8} {incr i} {
        if {[peek [expr {0xC2C0 + $i}]] != 0} {incr count}
    }
    return $count
}

proc m1_window_owner_gen {owner} {
    set owner_slot [expr {$owner & 0xFF}]
    set owner_gen [expr {($owner >> 8) & 0xFF}]
    for {set i 0} {$i < 8} {incr i} {
        if {[peek [expr {0xC2D0 + $i}]] == $owner_slot &&
            [peek [expr {0xC2D8 + $i}]] == $owner_gen} {
            return $owner_gen
        }
    }
    return 0
}

proc m1_release_all {} {
    catch {keymatrixup 8 0x01}
    catch {keymatrixup 8 0x10}
    catch {keymatrixup 8 0x20}
    catch {keymatrixup 8 0x40}
    catch {keymatrixup 8 0x80}
}

proc m1_lowram_ready {} {
    expr {$::m1_page0_slot >= 0 &&
          [debug read ioports 0xA8] == $::m1_page0_ppi &&
          [peek 0xFFFF] == $::m1_page0_secondary &&
          [peek 0x1350] <= 8 && [peek 0x1351] < 8 &&
          [peek 0x1306] <= 127 && [peek 0x1307] <= 211}
}

proc m1_finish {status} {
    m1_release_all
    set out [open $::m1_output w]
    puts $out "STATUS=$status"
    puts $out [format "POOL_TOTAL=%d" [peek 0xC2E4]]
    puts $out "FIRST_OWNER=[format %04X $::m1_first_owner]"
    puts $out "SECOND_OWNER=[format %04X $::m1_second_owner]"
    puts $out "OWNER_GEN_FIRST=$::m1_first_gen"
    puts $out "OWNER_GEN_CLOSED=$::m1_closed_gen"
    puts $out "OWNER_GEN_SECOND=$::m1_second_gen"
    puts $out "WINDOW_GEN_FIRST=$::m1_first_window_gen"
    puts $out "WINDOW_GEN_SECOND=$::m1_second_window_gen"
    puts $out "FIRST_INITIAL=$::m1_first_initial"
    puts $out "FIRST_HELD=$::m1_first_final"
    puts $out "FIRST_CLOSED_FREE=$::m1_first_closed_free"
    puts $out "SECOND_INITIAL=$::m1_second_initial"
    puts $out "SECOND_HELD=$::m1_second_final"
    puts $out "FINAL_FREE=$::m1_final_free"
    puts $out "ACTIVE_OWNERS=[m1_owner_count]"
    puts $out "LIVE_WINDOWS=[peek 0x1350]"
    puts $out "PAGE0_SLOT=$::m1_page0_slot"
    puts $out [format "PAGE0_PPI=%02X" $::m1_page0_ppi]
    puts $out [format "PAGE0_SECONDARY=%02X" $::m1_page0_secondary]
    puts $out [format "PPI_A8=%02X" [debug read ioports 0xA8]]
    puts $out [format "FINAL_PC=%04X" [reg PC]]
    close $out
    if {$status ne "PASS"} { catch {screenshot -raw $::m1_screenshot} }
    exit
}

proc m1_move_tick {} {
    if {![m1_lowram_ready]} {
        if {[machine_info time] >= $::m1_deadline} {
            m1_finish "TIMEOUT waiting for low RAM while moving pointer"
            return
        }
        after time 0.002 m1_move_tick
        return
    }
    set x [peek 0x1306]
    set y [peek 0x1307]
    m1_release_all
    if {$x > 127 || $y > 211} {
        after time 0.002 m1_move_tick
        return
    }
    if {[expr {abs($x - $::m1_target_x)}] <= 1 &&
        [expr {abs($y - $::m1_target_y)}] <= 3} {
        after time 0.08 $::m1_callback
        return
    }
    if {[machine_info time] >= $::m1_deadline} {
        m1_finish "TIMEOUT moving pointer"
        return
    }
    if {$x < $::m1_target_x - 1} {
        set mask 0x80
    } elseif {$x > $::m1_target_x + 1} {
        set mask 0x10
    } elseif {$y < $::m1_target_y - 3} {
        set mask 0x40
    } else {
        set mask 0x20
    }
    keymatrixdown 8 $mask
    after time 0.08 [list keymatrixup 8 $mask]
    after time 0.16 m1_move_tick
}

proc m1_move_to {x y callback} {
    m1_release_all
    set ::m1_target_x $x
    set ::m1_target_y $y
    set ::m1_callback $callback
    set ::m1_deadline [expr {[machine_info time] + 30.0}]
    m1_move_tick
}

proc m1_click_up {callback} {
    keymatrixup 8 0x01
    after time 1.0 $callback
}

proc m1_click {callback} {
    keymatrixdown 8 0x01
    after time 0.08 [list m1_click_up $callback]
}

proc m1_double_second_up {callback} {
    keymatrixup 8 0x01
    after time 0.10 $callback
}

proc m1_double_second {callback} {
    keymatrixdown 8 0x01
    after time 0.06 [list m1_double_second_up $callback]
}

proc m1_double_first_up {callback} {
    keymatrixup 8 0x01
    after time 0.10 [list m1_double_second $callback]
}

proc m1_double_click {callback} {
    keymatrixdown 8 0x01
    after time 0.06 [list m1_double_first_up $callback]
}

proc m1_validate_sysinfo {} {
    expr {
        [peek 0xC2F0] == 20 && [peek 0xC2F1] == 1 &&
        [peek 0xC2F4] == 1 && [peek 0xC2F5] == 7 &&
        [m1_word 0xC2F6] == 512 && [m1_word 0xC2F8] == 212 &&
        [peek 0xC2FA] == 4 && [peek 0xC2FB] == 16 &&
        [peek 0xC2FD] == [peek 0xC2E4] &&
        ([m1_word 0xC300] & 0x01C0) == 0x01C0
    }
}

proc m1_wait_first {} {
    if {![m1_lowram_ready]} {
        if {[machine_info time] >= $::m1_deadline} {
            m1_finish "FAIL low RAM unavailable during first run"
        } else { after time 0.002 m1_wait_first }
        return
    }
    if {[peek 0x1350] >= 3 && [m1_word $::m1_tests] == 0x03FF} {
        set ::m1_first_owner [m1_word $::m1_owner]
        set ::m1_first_gen [peek 0xC2CA]
        set ::m1_first_window_gen [m1_window_owner_gen $::m1_first_owner]
        set ::m1_first_initial [peek $::m1_initial]
        set ::m1_first_final [peek $::m1_final]
        if {![m1_validate_sysinfo] || $::m1_first_owner == 0 ||
            $::m1_first_gen != (($::m1_first_owner >> 8) & 0xFF) ||
            $::m1_first_window_gen != $::m1_first_gen ||
            $::m1_first_final != $::m1_first_initial - 1 ||
            [m1_word $::m1_retained] == 0 ||
            [peek 0xC2E5] != $::m1_first_final || [m1_owner_count] != 3} {
            m1_finish "FAIL first API run"
            return
        }
        set x [peek 0x1448]
        set y [peek 0x1449]
        m1_move_to [expr {$x + 2}] [expr {$y + 6}] {m1_click m1_wait_first_close}
    } elseif {[machine_info time] >= $::m1_deadline} {
        m1_finish "FAIL SYSINFO did not complete first run"
    } else {
        after time 0.1 m1_wait_first
    }
}

proc m1_wait_first_close {} {
    if {![m1_lowram_ready]} {
        if {[machine_info time] >= $::m1_deadline} {
            m1_finish "FAIL low RAM unavailable after first close"
        } else { after time 0.002 m1_wait_first_close }
        return
    }
    if {[peek 0x1350] == 2} {
        set ::m1_first_closed_free [peek 0xC2E5]
        set ::m1_closed_gen [peek 0xC2CA]
        if {$::m1_first_closed_free != $::m1_first_initial + 1 ||
            [m1_owner_count] != 2} {
            m1_finish "FAIL owner teardown"
            return
        }
        set ::m1_deadline [expr {[machine_info time] + 30.0}]
        m1_move_to 16 104 {m1_double_click m1_wait_second}
    } elseif {[machine_info time] >= $::m1_deadline} {
        m1_finish "FAIL first close timeout"
    } else {
        after time 0.1 m1_wait_first_close
    }
}

proc m1_wait_second {} {
    if {![m1_lowram_ready]} {
        if {[machine_info time] >= $::m1_deadline} {
            m1_finish "FAIL low RAM unavailable during second run"
        } else { after time 0.002 m1_wait_second }
        return
    }
    if {[peek 0x1350] >= 3 && [m1_word $::m1_tests] == 0x03FF} {
        set ::m1_second_owner [m1_word $::m1_owner]
        set ::m1_second_gen [peek 0xC2CA]
        set ::m1_second_window_gen [m1_window_owner_gen $::m1_second_owner]
        set ::m1_second_initial [peek $::m1_initial]
        set ::m1_second_final [peek $::m1_final]
        if {$::m1_second_owner == $::m1_first_owner ||
            ($::m1_second_owner & 0xFF) != ($::m1_first_owner & 0xFF) ||
            $::m1_closed_gen != $::m1_first_gen ||
            $::m1_second_gen != (($::m1_second_owner >> 8) & 0xFF) ||
            $::m1_second_window_gen != $::m1_second_gen ||
            $::m1_second_initial != $::m1_first_initial ||
            $::m1_second_final != $::m1_first_final} {
            m1_finish "FAIL generation/reopen"
            return
        }
        set x [peek 0x1448]
        set y [peek 0x1449]
        m1_move_to [expr {$x + 2}] [expr {$y + 6}] {m1_click m1_wait_final_close}
    } elseif {[machine_info time] >= $::m1_deadline} {
        m1_finish "FAIL SYSINFO did not complete second run"
    } else {
        after time 0.1 m1_wait_second
    }
}

proc m1_wait_final_close {} {
    if {![m1_lowram_ready]} {
        if {[machine_info time] >= $::m1_deadline} {
            m1_finish "FAIL low RAM unavailable after final close"
        } else { after time 0.002 m1_wait_final_close }
        return
    }
    if {[peek 0x1350] == 2} {
        set ::m1_final_free [peek 0xC2E5]
        if {$::m1_final_free == $::m1_first_closed_free && [m1_owner_count] == 2} {
            m1_finish "PASS"
        } else {
            m1_finish "FAIL final cleanup"
        }
    } elseif {[machine_info time] >= $::m1_deadline} {
        m1_finish "FAIL final close timeout"
    } else {
        after time 0.1 m1_wait_final_close
    }
}

proc m1_launch_first {} {
    set ::m1_deadline [expr {[machine_info time] + 30.0}]
    m1_double_click m1_wait_first
}

proc m1_filemgr_ready {} {
    if {![m1_lowram_ready]} {
        if {[machine_info time] >= $::m1_deadline} {
            m1_finish "FAIL low RAM unavailable while opening File Manager"
        } else { after time 0.002 m1_filemgr_ready }
        return
    }
    if {[peek 0x1350] == 2 && [peek 0x1351] == 1 &&
        [peek 0x144A] == 56 && [peek 0x144B] == 158} {
        after time 4.0 {m1_move_to 16 104 m1_launch_first}
    } elseif {[machine_info time] >= $::m1_deadline} {
        m1_finish "FAIL File Manager did not register"
    } else {
        after time 0.1 m1_filemgr_ready
    }
}

proc m1_open_drive {} {
    set ::m1_deadline [expr {[machine_info time] + 30.0}]
    m1_double_click m1_filemgr_ready
}

proc m1_desktop_ready {} {
    # BIOS CALSLT briefly replaces low RAM with ROM. Require four matching,
    # fully sane Desktop samples before remembering the normal primary slot;
    # this is independent of any particular MSX machine slot layout.
    if {[peek 0x1350] == 1 && [peek 0x1351] == 0 &&
        [peek 0x1306] <= 127 && [peek 0x1307] <= 211 &&
        [m1_owner_count] == 1 && [m1_validate_sysinfo]} {
        set ppi [debug read ioports 0xA8]
        set secondary [peek 0xFFFF]
        set candidate [expr {($ppi << 8) | $secondary}]
        if {$candidate == $::m1_slot_candidate} {
            incr ::m1_slot_samples
        } else {
            set ::m1_slot_candidate $candidate
            set ::m1_slot_samples 1
        }
        if {$::m1_slot_samples >= 4} {
            set ::m1_page0_ppi $ppi
            set ::m1_page0_secondary $secondary
            set ::m1_page0_slot [expr {$ppi & 3}]
            m1_move_to 4 40 m1_open_drive
            return
        }
    }
    if {[machine_info time] >= $::m1_deadline} {
        m1_finish "FAIL Desktop slot discovery"
    } else {
        after time 0.013 m1_desktop_ready
    }
}

proc m1_start {} {
    set ::m1_deadline [expr {[machine_info time] + 30.0}]
    m1_desktop_ready
}

after time 62.0 m1_start
