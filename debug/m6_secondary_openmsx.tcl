# Validate the MSX2 M6 application-owned secondary-code gate through the normal
# Desktop -> File Manager loader path. A fixed-RAM trampoline invokes only
# rejected calls while FormRef's primary page is mapped; the unmodified app draw
# then makes the real valid call. Finally the close gadget proves owner cleanup.
set throttle off
set pause_on_lost_focus false
set pause off

set m6_output $::env(GEMBENCH_M6_OUTPUT)
set m6_k_poll [expr {$::env(GEMBENCH_M6_K_POLL)}]
set m6_app_draw [expr {$::env(GEMBENCH_M6_APP_DRAW)}]
set m6_call [expr {$::env(GEMBENCH_M6_CALL)}]
set m6_handle_addr [expr {$::env(GEMBENCH_M6_HANDLE)}]
set m6_deadline 0
set m6_target_x 0
set m6_target_y 0
set m6_callback ""
set m6_page0_ppi -1
set m6_page0_secondary -1
set m6_slot_candidate -1
set m6_slot_samples 0
set m6_poll_events {}
set m6_poll_bp ""
set m6_initial_free 0
set m6_probe_installed 0
set m6_handle 0
set m6_page_index -1
set m6_owner 0
set m6_foreign_handle 0
set m6_gate_hits 0
set m6_secondary_hits 0
set m6_return_hits 0
set m6_gate_sp 0
set m6_gate_word 0
set m6_primary_bank 0
set m6_entry_sp 0
set m6_entry_word 0
set m6_secondary_bank 0
set m6_return_sp 0
set m6_return_word 0
set m6_return_bank 0
set m6_launch_valid 0
set m6_cleanup_valid 0

proc m6_word {address} {
    expr {[peek $address] | ([peek [expr {$address + 1}]] << 8)}
}

proc m6_owner_count {} {
    set count 0
    for {set i 0} {$i < 8} {incr i} {
        if {[peek [expr {0xC2C0 + $i}]] != 0} {incr count}
    }
    return $count
}

proc m6_release_all {} {
    catch {keymatrixup 8 0x01}
    catch {keymatrixup 8 0x10}
    catch {keymatrixup 8 0x20}
    catch {keymatrixup 8 0x40}
    catch {keymatrixup 8 0x80}
}

proc m6_poll_after {delay callback} {
    after time $delay [list m6_poll_arm $callback]
}

proc m6_poll_arm {callback} {
    lappend ::m6_poll_events $callback
    if {$::m6_poll_bp eq ""} {
        set ::m6_poll_bp [debug set_bp $::m6_k_poll {} {m6_poll_tick}]
    }
}

proc m6_poll_tick {} {
    if {$::m6_poll_bp ne ""} {
        debug remove_bp $::m6_poll_bp
        set ::m6_poll_bp ""
    }
    set callbacks $::m6_poll_events
    set ::m6_poll_events {}
    foreach callback $callbacks {
        if {[catch {uplevel #0 $callback} message]} {
            m6_finish "ERROR poll callback: $message"
            return
        }
    }
    set ::pause off
}

proc m6_lowram_ready {} {
    expr {$::m6_page0_ppi >= 0 &&
          [debug read ioports 0xA8] == $::m6_page0_ppi &&
          [peek 0xFFFF] == $::m6_page0_secondary &&
          [peek 0x1350] <= 8 && [peek 0x1351] < 8 &&
          [peek 0x1306] <= 127 && [peek 0x1307] <= 211}
}

proc m6_finish {status} {
    m6_release_all
    set out [open $::m6_output w]
    puts $out "STATUS=$status"
    puts $out "INVALID_ENTRY=[peek 0xC88C]"
    puts $out "NESTED_BUSY=[peek 0xC88D]"
    puts $out "STALE_HANDLE=[peek 0xC88E]"
    puts $out "FOREIGN_OWNER=[peek 0xC88F]"
    puts $out "TEARDOWN_CALL=[peek 0xC890]"
    puts $out "GATE_HITS=$::m6_gate_hits"
    puts $out "SECONDARY_HITS=$::m6_secondary_hits"
    puts $out "RETURN_HITS=$::m6_return_hits"
    puts $out [format "GATE_SP=%04X" $::m6_gate_sp]
    puts $out [format "ENTRY_SP=%04X" $::m6_entry_sp]
    puts $out [format "RETURN_SP=%04X" $::m6_return_sp]
    puts $out [format "PRIMARY_BANK=%02X" $::m6_primary_bank]
    puts $out [format "SECONDARY_BANK=%02X" $::m6_secondary_bank]
    puts $out [format "RETURN_BANK=%02X" $::m6_return_bank]
    puts $out [format "SECONDARY_HANDLE=%04X" $::m6_handle]
    puts $out [format "SECONDARY_OWNER=%04X" $::m6_owner]
    puts $out "INITIAL_FREE=$::m6_initial_free"
    puts $out "FINAL_FREE=[peek 0xC2E5]"
    puts $out "FINAL_OWNERS=[m6_owner_count]"
    puts $out "FINAL_WINDOWS=[peek 0x1350]"
    puts $out "LAUNCH_VALID=$::m6_launch_valid"
    puts $out "CLEANUP_VALID=$::m6_cleanup_valid"
    puts $out [format "FINAL_PC=%04X" [reg PC]]
    close $out
    exit
}

proc m6_after {delay callback} { after time $delay $callback }

proc m6_move_tick {} {
    if {![m6_lowram_ready]} {
        if {[machine_info time] >= $::m6_deadline} {
            m6_finish "FAIL low RAM unavailable while moving pointer"
        } else {m6_after 0.002 m6_move_tick}
        return
    }
    set x [peek 0x1306]
    set y [peek 0x1307]
    m6_release_all
    if {[expr {abs($x - $::m6_target_x)}] <= 1 &&
        [expr {abs($y - $::m6_target_y)}] <= 3} {
        m6_after 0.08 $::m6_callback
        return
    }
    if {[machine_info time] >= $::m6_deadline} {
        m6_finish "FAIL pointer move timeout"
        return
    }
    if {$x < $::m6_target_x - 1} {
        set mask 0x80
    } elseif {$x > $::m6_target_x + 1} {
        set mask 0x10
    } elseif {$y < $::m6_target_y - 3} {
        set mask 0x40
    } else {
        set mask 0x20
    }
    keymatrixdown 8 $mask
    m6_after 0.08 [list keymatrixup 8 $mask]
    m6_after 0.16 m6_move_tick
}

proc m6_move_to {x y callback} {
    set ::m6_target_x $x
    set ::m6_target_y $y
    set ::m6_callback $callback
    set ::m6_deadline [expr {[machine_info time] + 30.0}]
    m6_move_tick
}

proc m6_click_up {callback} {
    keymatrixup 8 0x01
    m6_poll_after 0.15 $callback
}

proc m6_click {callback} {
    keymatrixdown 8 0x01
    m6_after 0.16 [list m6_click_up $callback]
}

proc m6_double_second_up {} {
    keymatrixup 8 0x01
    set ::m6_deadline [expr {[machine_info time] + 20.0}]
    m6_poll_after 0.5 m6_wait_launch
}

proc m6_double_second {} {
    keymatrixdown 8 0x01
    m6_after 0.16 m6_double_second_up
}

proc m6_double_first_up {} {
    keymatrixup 8 0x01
    m6_after 0.20 m6_double_second
}

proc m6_emit {value} {
    poke $::m6_emit_at [expr {$value & 0xFF}]
    incr ::m6_emit_at
}

proc m6_emit_word {value} {
    m6_emit $value
    m6_emit [expr {$value >> 8}]
}

proc m6_emit_call {handle entry result} {
    m6_emit 0x21
    m6_emit_word $handle
    m6_emit 0x11
    m6_emit_word $entry
    m6_emit 0xCD
    m6_emit_word $::m6_call
    m6_emit 0x32
    m6_emit_word $result
}

proc m6_install_rejection_probe {} {
    if {$::m6_probe_installed} {set ::pause off; return}
    set ::m6_probe_installed 1
    set ::m6_handle [m6_word $::m6_handle_addr]
    set low [expr {$::m6_handle & 0xFF}]
    set gen [expr {$::m6_handle >> 8}]
    if {$low == 0 || $low > 32} {
        m6_finish "FAIL invalid secondary handle"
        return
    }
    set ::m6_page_index [expr {$low - 1}]
    set owner_low [peek [expr {0xC240 + $::m6_page_index}]]
    set owner_gen [peek [expr {0xC260 + $::m6_page_index}]]
    set ::m6_owner [expr {$owner_low | ($owner_gen << 8)}]

    set foreign -1
    for {set i 0} {$i < [peek 0xC2E4]} {incr i} {
        if {[peek [expr {0xC220 + $i}]] &&
            [peek [expr {0xC240 + $i}]] != $owner_low} {
            set foreign $i
            break
        }
    }
    if {$foreign < 0} {m6_finish "FAIL no foreign page"; return}
    set ::m6_foreign_handle [expr {($foreign + 1) |
        ([peek [expr {0xC280 + $foreign}]] << 8)}]
    poke 0xC480 [expr {$::m6_foreign_handle & 0xFF}]
    poke 0xC481 [expr {$::m6_foreign_handle >> 8}]
    poke 0xC482 0x10
    poke 0xC483 0

    set stale_gen [expr {$gen ^ 0x80}]
    if {$stale_gen == 0} {set stale_gen 1}
    set flags_addr [expr {0xC338 + $owner_low - 1}]
    set flags [peek $flags_addr]
    set ::m6_emit_at 0xC400

    # Out-of-range entry -> BADARG.
    m6_emit_call $::m6_handle_addr 0xFFFF 0xC88C

    # A nested call sees the already-held serialized gate -> BUSY.
    m6_emit 0x3E; m6_emit 1
    m6_emit 0x32; m6_emit_word 0xC3D7
    m6_emit_call $::m6_handle_addr 8 0xC88D
    m6_emit 0xAF
    m6_emit 0x32; m6_emit_word 0xC3D7

    # Same slot, wrong generation -> STALE; restore before continuing.
    m6_emit 0x3E; m6_emit $stale_gen
    m6_emit 0x32; m6_emit_word [expr {$::m6_handle_addr + 1}]
    m6_emit_call $::m6_handle_addr 8 0xC88E
    m6_emit 0x3E; m6_emit $gen
    m6_emit 0x32; m6_emit_word [expr {$::m6_handle_addr + 1}]

    # A live page owned by Desktop -> OWNER.
    m6_emit_call 0xC480 8 0xC88F

    # Once the application record is terminating no new call may start.
    m6_emit 0x3E; m6_emit [expr {$flags | 4}]
    m6_emit 0x32; m6_emit_word $flags_addr
    m6_emit_call $::m6_handle_addr 8 0xC890
    m6_emit 0x3E; m6_emit $flags
    m6_emit 0x32; m6_emit_word $flags_addr

    m6_emit 0xC3
    m6_emit_word $::m6_app_draw
    reg PC 0xC400
    set ::pause off
}

proc m6_gate_enter {} {
    if {[peek 0xC3D7] == 1 && [peek 0xC8E3] == 0xF5} {
        incr ::m6_gate_hits
        set ::m6_gate_sp [reg SP]
        set ::m6_gate_word [m6_word $::m6_gate_sp]
        set ::m6_primary_bank [peek 0x134F]
    }
    set ::pause off
}

proc m6_secondary_enter {} {
    incr ::m6_secondary_hits
    set ::m6_entry_sp [reg SP]
    set ::m6_entry_word [m6_word $::m6_entry_sp]
    set ::m6_secondary_bank [peek 0x134F]
    set ::pause off
}

proc m6_gate_return {} {
    if {[peek 0xC3D7] == 1} {
        incr ::m6_return_hits
        set ::m6_return_sp [reg SP]
        set ::m6_return_word [m6_word $::m6_return_sp]
        set ::m6_return_bank [peek 0x134F]
    }
    set ::pause off
}

proc m6_open_drive {} {
    debug set_bp $::m6_app_draw {} {m6_install_rejection_probe}
    debug set_bp 0xC8E0 {} {m6_gate_enter}
    debug set_bp 0x4008 {[peek 0xC3D7] == 1} {m6_secondary_enter}
    debug set_bp 0xC8FE {[peek 0xC3D7] == 1} {m6_gate_return}
    keymatrixdown 8 0x01
    m6_after 0.16 m6_double_first_up
}

proc m6_find_form_slot {} {
    set owner_low [expr {$::m6_owner & 0xFF}]
    set owner_gen [expr {$::m6_owner >> 8}]
    for {set slot 0} {$slot < [peek 0x1350]} {incr slot} {
        if {[peek [expr {0xC2D0 + $slot}]] == $owner_low &&
            [peek [expr {0xC2D8 + $slot}]] == $owner_gen} {return $slot}
    }
    return -1
}

proc m6_close_form {} {
    set slot [m6_find_form_slot]
    if {$slot < 0} {m6_finish "FAIL FormRef window owner link"; return}
    set entry [expr {0x1352 + 25 * $slot}]
    set x [peek [expr {$entry + 1}]]
    set y [peek [expr {$entry + 2}]]
    set ::m6_deadline [expr {[machine_info time] + 20.0}]
    m6_move_to [expr {$x + 2}] [expr {$y + 6}] {m6_click m6_wait_cleanup}
}

proc m6_wait_launch {} {
    if {![m6_lowram_ready]} {
        if {[machine_info time] >= $::m6_deadline} {
            m6_finish "FAIL low RAM unavailable after launch"
        } else {m6_poll_after 0.05 m6_wait_launch}
        return
    }
    if {[peek 0x1350] == 2 && [m6_owner_count] == 2 &&
        $::m6_probe_installed && $::m6_secondary_hits >= 1 &&
        [peek 0xC3D7] == 0} {
        set index $::m6_page_index
        set native [peek [expr {0xC200 + $index}]]
        set handle_gen [expr {$::m6_handle >> 8}]
        set owner_low [expr {$::m6_owner & 0xFF}]
        set owner_gen [expr {$::m6_owner >> 8}]
        if {[peek 0xC88C] != 5 || [peek 0xC88D] != 4 ||
            [peek 0xC88E] != 2 || [peek 0xC88F] != 3 ||
            [peek 0xC890] != 9 ||
            $::m6_gate_hits < 1 || $::m6_return_hits < 1 ||
            $::m6_entry_word != 0xC8F5 ||
            $::m6_entry_sp != (($::m6_gate_sp - 4) & 0xFFFF) ||
            $::m6_return_sp != $::m6_gate_sp ||
            $::m6_return_word != $::m6_gate_word ||
            $::m6_secondary_bank != $native ||
            $::m6_return_bank != $::m6_primary_bank ||
            [peek [expr {0xC220 + $index}]] != 1 ||
            [peek [expr {0xC280 + $index}]] != $handle_gen ||
            [peek [expr {0xC2A0 + $index}]] != 7 ||
            [peek [expr {0xC240 + $index}]] != $owner_low ||
            [peek [expr {0xC260 + $index}]] != $owner_gen ||
            [peek 0xC2E5] + 2 != $::m6_initial_free ||
            ([m6_word 0xC300] & 0x2000) == 0 ||
            [m6_word 0xC2E0] != 0} {
            m6_finish "FAIL secondary call-gate contract"
            return
        }
        set ::m6_launch_valid 1
        m6_close_form
        return
    }
    if {[machine_info time] >= $::m6_deadline} {
        m6_finish "FAIL FormRef secondary launch timeout"
    } else {m6_poll_after 0.1 m6_wait_launch}
}

proc m6_wait_cleanup {} {
    if {![m6_lowram_ready]} {
        if {[machine_info time] >= $::m6_deadline} {
            m6_finish "FAIL low RAM unavailable after close"
        } else {m6_poll_after 0.05 m6_wait_cleanup}
        return
    }
    if {[peek 0x1350] == 1 && [m6_owner_count] == 1} {
        set owner_slot [expr {($::m6_owner & 0xFF) - 1}]
        if {[peek 0xC2E5] != $::m6_initial_free ||
            [peek [expr {0xC220 + $::m6_page_index}]] != 0 ||
            [peek [expr {0xC2C0 + $owner_slot}]] != 0 ||
            [m6_word 0xC2E0] != 0 || [peek 0xC3D7] != 0} {
            m6_finish "FAIL secondary owner cleanup"
            return
        }
        set ::m6_cleanup_valid 1
        m6_finish PASS
        return
    }
    if {[machine_info time] >= $::m6_deadline} {
        m6_finish "FAIL FormRef close timeout"
    } else {m6_poll_after 0.1 m6_wait_cleanup}
}

proc m6_desktop_ready {} {
    if {[peek 0x1350] == 1 && [peek 0x1351] == 0 &&
        [m6_owner_count] == 1 && [peek 0xC2F0] >= 20} {
        set ppi [debug read ioports 0xA8]
        set secondary [peek 0xFFFF]
        set candidate [expr {($ppi << 8) | $secondary}]
        if {$candidate == $::m6_slot_candidate} {
            incr ::m6_slot_samples
        } else {
            set ::m6_slot_candidate $candidate
            set ::m6_slot_samples 1
        }
        if {$::m6_slot_samples >= 4} {
            set ::m6_page0_ppi $ppi
            set ::m6_page0_secondary $secondary
            set ::m6_initial_free [peek 0xC2E5]
            m6_move_to 4 40 m6_open_drive
            return
        }
    }
    if {[machine_info time] >= $::m6_deadline} {
        m6_finish "FAIL Desktop readiness"
    } else {m6_poll_after 0.013 m6_desktop_ready}
}

proc m6_start {} {
    set ::m6_deadline [expr {[machine_info time] + 30.0}]
    m6_poll_after 0.0 m6_desktop_ready
}

m6_after 62.0 m6_start
after realtime 90.0 {m6_finish "TIMEOUT harness watchdog"}
