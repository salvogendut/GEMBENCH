# Exercise GB_SYSINFO, GB_OWNER and GB_PAGE, then verify owner teardown/reuse.
set throttle off
set pause_on_lost_focus false
set pause off

set m1_tests [expr {$::env(GEMBENCH_M1_TESTS)}]
set m1_initial [expr {$::env(GEMBENCH_M1_INITIAL)}]
set m1_final [expr {$::env(GEMBENCH_M1_FINAL)}]
set m1_owner [expr {$::env(GEMBENCH_M1_OWNER)}]
set m1_retained [expr {$::env(GEMBENCH_M1_RETAINED)}]
set m1_sysinfo_pointer [expr {$::env(GEMBENCH_M1_SYSINFO)}]
set m1_sysinfo_record [expr {$::env(GEMBENCH_M1_SYSINFO_RECORD)}]
set m3_tests [expr {$::env(GEMBENCH_M3_TESTS)}]
set m4_tests [expr {$::env(GEMBENCH_M4_TESTS)}]
set fm_total [expr {$::env(GEMBENCH_FM_TOTAL)}]
set fm_names [expr {$::env(GEMBENCH_FM_NAMES)}]
set fm_order [expr {$::env(GEMBENCH_FM_ORDER)}]
set fm_list_state [expr {$::env(GEMBENCH_FM_LIST_STATE)}]
set fm_icon_pos [expr {$::env(GEMBENCH_FM_ICON_POS)}]
set fm_view [expr {$::env(GEMBENCH_FM_VIEW)}]
set m1_k_poll [expr {$::env(GEMBENCH_K_POLL)}]
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
set m1_phase "boot"
set m1_poll_events {}
set m1_poll_bp ""

proc m1_mem {address} {
    return [peek $address]
}

proc m1_after {delay callback} {
    set ::m1_phase "armed:$callback"
    after time $delay $callback
}

# Memory observations run only at the public poll entry, where the kernel's
# low-RAM and focused application mappings are stable. Input transitions stay
# on ordinary emulation-time timers so a key remains held across a real poll.
proc m1_poll_after {delay callback} {
    after time $delay [list m1_poll_arm $callback]
}

proc m1_poll_arm {callback} {
    lappend ::m1_poll_events $callback
    if {$::m1_poll_bp eq ""} {
        set ::m1_poll_bp [debug set_bp $::m1_k_poll {} {m1_poll_tick}]
    }
}

proc m1_poll_tick {} {
    if {$::m1_poll_bp ne ""} {
        debug remove_bp $::m1_poll_bp
        set ::m1_poll_bp ""
    }
    set callbacks $::m1_poll_events
    set ::m1_poll_events {}
    set failed ""
    foreach callback $callbacks {
        if {[catch {uplevel #0 $callback} message]} {
            set failed $message
            break
        }
    }
    set ::pause off
    if {$failed ne ""} {m1_abort "ERROR poll callback: $failed"}
}

proc m1_abort {status} {
    m1_release_all
    set out [open $::m1_output w]
    puts $out "STATUS=$status"
    puts $out "PHASE=$::m1_phase"
    puts $out [format "FINAL_PC=%04X" [reg PC]]
    puts $out "PAUSE=$::pause"
    puts $out "EMU_TIME=[machine_info time]"
    close $out
    catch {screenshot -raw $::m1_screenshot}
    exit
}

proc m1_word {address} {
    expr {[m1_mem $address] + 256 * [m1_mem [expr {$address + 1}]]}
}

proc m1_owner_count {} {
    set count 0
    for {set i 0} {$i < 8} {incr i} {
        if {[m1_mem [expr {0xC2C0 + $i}]] != 0} {incr count}
    }
    return $count
}

proc m4_context_count {} {
    set count 0
    for {set i 0} {$i < 4} {incr i} {
        if {[m1_mem [expr {0xC600 + $i * 144}]] != 0} {incr count}
    }
    return $count
}

proc m1_window_owner_gen {owner} {
    set owner_slot [expr {$owner & 0xFF}]
    set owner_gen [expr {($owner >> 8) & 0xFF}]
    for {set i 0} {$i < 8} {incr i} {
        if {[m1_mem [expr {0xC2D0 + $i}]] == $owner_slot &&
            [m1_mem [expr {0xC2D8 + $i}]] == $owner_gen} {
            return [m1_mem [expr {0xC358 + $i}]]
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

proc m1_filemgr_app_index {} {
    for {set i 0} {$i < [m1_mem $::fm_total]} {incr i} {
        set raw [m1_mem [expr {$::fm_order + $i}]]
        set base [expr {$::fm_names + $raw * 11}]
        set expected {65 32 32 32 32 32 32 32 65 80 80}
        set match 1
        for {set j 0} {$j < 11} {incr j} {
            if {[m1_mem [expr {$base + $j}]] != [lindex $expected $j]} {
                set match 0
                break
            }
        }
        if {$match} {return $i}
    }
    return -1
}

proc m1_filemgr_mapped {} {
    set focus [m1_mem 0x1351]
    expr {$focus < 8 &&
          [m1_mem 0x134F] == [m1_mem [expr {0x1352 + $focus * 25}]]}
}

proc m1_launch_filemgr_app {callback} {
    if {![m1_filemgr_mapped]} {
        if {[machine_info time] >= $::m1_deadline} {
            m1_finish "FAIL File Manager page unavailable"
        } else {
            m1_poll_after 0.0 [list m1_launch_filemgr_app $callback]
        }
        return
    }
    set index [m1_filemgr_app_index]
    if {$index < 0} {
        m1_finish "FAIL A.APP absent from File Manager"
        return
    }
    set x [m1_mem 0x1448]
    set y [m1_mem 0x1449]
    if {[m1_mem $::fm_view] == 1} {
        set cell_w [expr {([m1_mem 0x144A] - 5) / 3}]
        set target_x [expr {$x + 4 + ($index % 3) * $cell_w + $cell_w / 2}]
        set target_y [expr {$y + 14 + ($index / 3) * 44 + 16}]
    } else {
        set target_x [expr {$x + 12}]
        set target_y [expr {$y + 14 + $index * 18 + 8}]
    }
    m1_move_to $target_x $target_y [list m1_double_click $callback]
}

proc m1_lowram_ready {} {
    expr {$::m1_page0_slot >= 0 &&
          [debug read ioports 0xA8] == $::m1_page0_ppi &&
          [peek 0xFFFF] == $::m1_page0_secondary &&
          [m1_mem 0x1350] <= 8 && [m1_mem 0x1351] < 8 &&
          [m1_mem 0x1306] <= 127 && [m1_mem 0x1307] <= 211}
}

proc m1_finish {status} {
    set ::m1_phase "finish:$status"
    m1_release_all
    set out [open $::m1_output w]
    puts $out "STATUS=$status"
    puts $out [format "POOL_TOTAL=%d" [m1_mem 0xC2E4]]
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
    puts $out "ACTIVE_FS_CONTEXTS=[m4_context_count]"
    puts $out "FSCTX_LAST_OP=[m1_mem 0xC880]"
    puts $out "FSCTX_LAST_STATUS=[m1_mem 0xC881]"
    puts $out "FSCTX_CALLS=[m1_word 0xC882]"
    puts $out "FILEMGR_TOTAL=[m1_mem $::fm_total]"
    puts $out "FILEMGR_LIST_STATE=[m1_mem $::fm_list_state]"
    puts $out "FILEMGR_ICON_POS=[m1_mem $::fm_icon_pos]"
    puts $out "LIVE_WINDOWS=[m1_mem 0x1350]"
    for {set i 0} {$i < [m1_mem 0x1350] && $i < 8} {incr i} {
        set base [expr {0x1352 + $i * 25}]
        puts $out [format "WINDOW%d=%d,%d,%d,%d,%d" $i \
            [m1_mem $base] [m1_mem [expr {$base + 1}]] \
            [m1_mem [expr {$base + 2}]] [m1_mem [expr {$base + 3}]] \
            [m1_mem [expr {$base + 4}]]]
    }
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
        m1_after 0.002 m1_move_tick
        return
    }
    set x [m1_mem 0x1306]
    set y [m1_mem 0x1307]
    m1_release_all
    if {$x > 127 || $y > 211} {
        m1_after 0.002 m1_move_tick
        return
    }
    if {[expr {abs($x - $::m1_target_x)}] <= 1 &&
        [expr {abs($y - $::m1_target_y)}] <= 3} {
        m1_after 0.08 $::m1_callback
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
    m1_after 0.08 [list keymatrixup 8 $mask]
    m1_after 0.16 m1_move_tick
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
    m1_poll_after 1.0 $callback
}

proc m1_click {callback} {
    keymatrixdown 8 0x01
    m1_after 0.16 [list m1_click_up $callback]
}

proc m1_double_second_up {callback} {
    keymatrixup 8 0x01
    m1_after 0.10 $callback
}

proc m1_double_second {callback} {
    keymatrixdown 8 0x01
    m1_after 0.16 [list m1_double_second_up $callback]
}

proc m1_double_first_up {callback} {
    keymatrixup 8 0x01
    m1_after 0.20 [list m1_double_second $callback]
}

proc m1_double_click {callback} {
    keymatrixdown 8 0x01
    m1_after 0.16 [list m1_double_first_up $callback]
}

proc m1_validate_sysinfo {{base ""}} {
    # At boot SYSINFO.APP is not loaded yet. Use the kernel symbol for the
    # readiness check; after launch validate the pointer returned to the app.
    if {$base eq ""} { set base $::m1_sysinfo_record }
    expr {
        $base != 0 &&
        [m1_mem $base] == 48 && [m1_mem [expr {$base+1}]] == 6 &&
        [m1_mem [expr {$base+4}]] == 1 && [m1_mem [expr {$base+5}]] == 7 &&
        [m1_word [expr {$base+6}]] == 512 && [m1_word [expr {$base+8}]] == 212 &&
        [m1_mem [expr {$base+10}]] == 4 && [m1_mem [expr {$base+11}]] == 16 &&
        [m1_mem [expr {$base+13}]] == [m1_mem 0xC2E4] &&
        ([m1_word [expr {$base+16}]] & 0x5FC0) == 0x5FC0 &&
        [m1_mem [expr {$base+20}]] == 8 && [m1_mem [expr {$base+21}]] == 1 &&
        [m1_mem [expr {$base+22}]] == 8 && [m1_mem [expr {$base+23}]] == 0 &&
        [m1_mem [expr {$base+24}]] == 8 && [m1_mem [expr {$base+25}]] == 4 &&
        [m1_mem [expr {$base+26}]] == 1 && [m1_mem [expr {$base+27}]] == 0 &&
        [m1_mem [expr {$base+28}]] == 4 && [m1_word [expr {$base+29}]] == 512 &&
        [m1_mem [expr {$base+31}]] == 1 &&
        ([m1_word [expr {$base+32}]] & 0x00CF) == 0x00CF &&
        [m1_mem [expr {$base+34}]] == 128 && [m1_mem [expr {$base+35}]] == 212 &&
        [m1_mem [expr {$base+36}]] == 4 && [m1_mem [expr {$base+37}]] == 4 &&
        [m1_word [expr {$base+38}]] == 0x4000 &&
        [m1_word [expr {$base+40}]] == 0x7F00 &&
        [m1_word [expr {$base+42}]] == 0x8000 &&
        [m1_mem [expr {$base+44}]] == 2 && [m1_mem [expr {$base+45}]] == 1 &&
        [m1_mem [expr {$base+46}]] == 3 && [m1_mem [expr {$base+47}]] == 0
    }
}

proc m1_wait_first {} {
    if {![m1_lowram_ready]} {
        if {[machine_info time] >= $::m1_deadline} {
            m1_finish "FAIL low RAM unavailable during first run"
        } else { m1_poll_after 0.002 m1_wait_first }
        return
    }
    if {[m1_mem 0x1350] < 3} {
        if {[machine_info time] >= $::m1_deadline} {
            m1_finish "FAIL SYSINFO did not register first run"
        } else { m1_poll_after 0.1 m1_wait_first }
        return
    }
    if {![m1_filemgr_mapped]} {
        m1_poll_after 0.0 m1_wait_first
        return
    }
    if {[m1_word $::m1_tests] == 0xFFFF &&
        [m1_mem $::m3_tests] == 0xFF && [m1_mem $::m4_tests] == 0x7F &&
        [m1_mem 0xC376] == 8} {
        set ::m1_first_owner [m1_word $::m1_owner]
        set ::m1_first_gen [m1_mem 0xC2CA]
        set ::m1_first_window_gen [m1_window_owner_gen $::m1_first_owner]
        set ::m1_first_initial [m1_mem $::m1_initial]
        set ::m1_first_final [m1_mem $::m1_final]
        if {![m1_validate_sysinfo [m1_word $::m1_sysinfo_pointer]] || $::m1_first_owner == 0 ||
            $::m1_first_gen != (($::m1_first_owner >> 8) & 0xFF) ||
            $::m1_first_window_gen == 0 ||
            $::m1_first_final != $::m1_first_initial - 1 ||
            [m1_word $::m1_retained] == 0 ||
            [m1_mem 0xC2E5] != $::m1_first_final || [m1_owner_count] != 3 ||
            [m4_context_count] != 2 ||
            [m1_mem [expr {0xC366 + (($::m1_first_owner & 0xFF) - 1)}]] == 0} {
            m1_finish "FAIL first API run"
            return
        }
        set x [m1_mem 0x1448]
        set y [m1_mem 0x1449]
        m1_move_to [expr {$x + 2}] [expr {$y + 6}] {m1_click m1_wait_first_close}
    } elseif {[machine_info time] >= $::m1_deadline} {
        m1_finish "FAIL SYSINFO did not complete first run"
    } else {
        m1_poll_after 0.1 m1_wait_first
    }
}

proc m1_wait_first_close {} {
    if {![m1_lowram_ready]} {
        if {[machine_info time] >= $::m1_deadline} {
            m1_finish "FAIL low RAM unavailable after first close"
        } else { m1_poll_after 0.002 m1_wait_first_close }
        return
    }
    if {[m1_mem 0x1350] == 2} {
        set ::m1_first_closed_free [m1_mem 0xC2E5]
        set ::m1_closed_gen [m1_mem 0xC2CA]
        if {$::m1_first_closed_free != $::m1_first_initial + 1 ||
            [m1_owner_count] != 2 || [m4_context_count] != 1 ||
            [m1_mem 0xC376] != 0 ||
            [m1_mem [expr {0xC366 + (($::m1_first_owner & 0xFF) - 1)}]] != 0 ||
            [m1_mem [expr {0xC36E + (($::m1_first_owner & 0xFF) - 1)}]] != 0} {
            m1_finish "FAIL owner teardown"
            return
        }
        set ::m1_deadline [expr {[machine_info time] + 30.0}]
        m1_launch_filemgr_app m1_wait_second
    } elseif {[machine_info time] >= $::m1_deadline} {
        m1_finish "FAIL first close timeout"
    } else {
        m1_poll_after 0.1 m1_wait_first_close
    }
}

proc m1_wait_second {} {
    if {![m1_lowram_ready]} {
        if {[machine_info time] >= $::m1_deadline} {
            m1_finish "FAIL low RAM unavailable during second run"
        } else { m1_poll_after 0.002 m1_wait_second }
        return
    }
    if {[m1_mem 0x1350] < 3} {
        if {[machine_info time] >= $::m1_deadline} {
            m1_finish "FAIL SYSINFO did not register second run"
        } else { m1_poll_after 0.1 m1_wait_second }
        return
    }
    if {![m1_filemgr_mapped]} {
        m1_poll_after 0.0 m1_wait_second
        return
    }
    if {[m1_word $::m1_tests] == 0xFFFF &&
        [m1_mem $::m3_tests] == 0xFF && [m1_mem $::m4_tests] == 0x7F &&
        [m1_mem 0xC376] == 8} {
        set ::m1_second_owner [m1_word $::m1_owner]
        set ::m1_second_gen [m1_mem 0xC2CA]
        set ::m1_second_window_gen [m1_window_owner_gen $::m1_second_owner]
        set ::m1_second_initial [m1_mem $::m1_initial]
        set ::m1_second_final [m1_mem $::m1_final]
        if {![m1_validate_sysinfo [m1_word $::m1_sysinfo_pointer]] ||
            $::m1_second_owner == $::m1_first_owner ||
            ($::m1_second_owner & 0xFF) != ($::m1_first_owner & 0xFF) ||
            $::m1_closed_gen != $::m1_first_gen ||
            $::m1_second_gen != (($::m1_second_owner >> 8) & 0xFF) ||
            $::m1_second_window_gen == 0 ||
            $::m1_second_window_gen == $::m1_first_window_gen ||
            $::m1_second_initial != $::m1_first_initial ||
            $::m1_second_final != $::m1_first_final ||
            [m4_context_count] != 2} {
            m1_finish "FAIL generation/reopen"
            return
        }
        set x [m1_mem 0x1448]
        set y [m1_mem 0x1449]
        m1_move_to [expr {$x + 2}] [expr {$y + 6}] {m1_click m1_wait_final_close}
    } elseif {[machine_info time] >= $::m1_deadline} {
        m1_finish "FAIL SYSINFO did not complete second run"
    } else {
        m1_poll_after 0.1 m1_wait_second
    }
}

proc m1_wait_final_close {} {
    if {![m1_lowram_ready]} {
        if {[machine_info time] >= $::m1_deadline} {
            m1_finish "FAIL low RAM unavailable after final close"
        } else { m1_poll_after 0.002 m1_wait_final_close }
        return
    }
    if {[m1_mem 0x1350] == 2} {
        set ::m1_final_free [m1_mem 0xC2E5]
        if {$::m1_final_free == $::m1_first_closed_free && [m1_owner_count] == 2 &&
            [m4_context_count] == 1 && [m1_mem 0xC376] == 0} {
            m1_finish "PASS"
        } else {
            m1_finish "FAIL final cleanup"
        }
    } elseif {[machine_info time] >= $::m1_deadline} {
        m1_finish "FAIL final close timeout"
    } else {
        m1_poll_after 0.1 m1_wait_final_close
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
        } else { m1_poll_after 0.002 m1_filemgr_ready }
        return
    }
    if {[m1_mem 0x1350] == 2 && [m1_mem 0x1351] == 1 &&
        [m1_mem 0x144A] == 56 && [m1_mem 0x144B] == 158} {
        if {![m1_filemgr_mapped]} {
            m1_poll_after 0.0 m1_filemgr_ready
        } elseif {[m1_mem $::fm_list_state] == 0 && [m1_filemgr_app_index] >= 0} {
            m1_poll_after 0.5 {m1_launch_filemgr_app m1_wait_first}
        } else {
            m1_poll_after 0.1 m1_filemgr_ready
        }
    } elseif {[machine_info time] >= $::m1_deadline} {
        m1_finish "FAIL File Manager did not register"
    } else {
        m1_poll_after 0.1 m1_filemgr_ready
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
    if {[m1_mem 0x1350] == 1 && [m1_mem 0x1351] == 0 &&
        [m1_mem 0x1306] <= 127 && [m1_mem 0x1307] <= 211 &&
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
        m1_poll_after 0.013 m1_desktop_ready
    }
}

proc m1_start {} {
    set ::m1_phase "start"
    set ::m1_deadline [expr {[machine_info time] + 30.0}]
    m1_poll_after 0.0 m1_desktop_ready
}

m1_after 62.0 m1_start
after realtime 60.0 {m1_abort "TIMEOUT harness watchdog"}
