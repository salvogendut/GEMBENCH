# Independent openMSX confirmation for the compile-once two-bank FormRef.
# Reuse the established keyboard-pointer Desktop/File Manager navigation; the
# short root A.APP alias occupies the same deterministic first cell on row two.
source debug/gbr_object_openmsx.tcl

set fr_focus [expr {$::env(GEMBENCH_FORM_FOCUS)}]
set fr_ready [expr {$::env(GEMBENCH_FORM_READY)}]
set fr_states [expr {$::env(GEMBENCH_FORM_STATES)}]
set fr_calls [expr {$::env(GEMBENCH_FORM_CALLS)}]
set fr_status [expr {$::env(GEMBENCH_FORM_STATUS)}]
set fr_modal [expr {$::env(GEMBENCH_FORM_MODAL)}]
set fr_modal_seen 0
set fr_deadline 0

proc fr_low_ready {} {
    expr {[peek 0x403] == 71 && [peek 0x404] == 66 &&
          [peek 0x1350] <= 8 && [peek 0x1351] < 8 &&
          [peek 0x1306] <= 127 && [peek 0x1307] <= 211}
}

proc fr_app_mapped {} {
    expr {[peek 0x4000] == 0xC3 && [peek 0x4003] == 71 &&
          [peek 0x4004] == 66 && [peek 0x4007] == 4}
}

# BIOS calls briefly map ROM over page 0. Keep the test's harmless modifier
# held while steering and accept coordinates only from the GEOBENCH low page.
rename gbr_move_tick fr_base_move_tick
proc gbr_move_tick {} {
    if {![fr_low_ready]} {
        if {[machine_info time] >= $::gbr_deadline} {
            gbr_finish "FAIL FormRef low RAM unavailable while moving"
        } else {
            after time 0.002 gbr_move_tick
        }
        return
    }
    keymatrixdown 6 0x02
    fr_base_move_tick
}

rename gbr_open_drive fr_base_open_drive
proc gbr_open_drive {} {
    if {![fr_low_ready]} {after time 0.002 gbr_open_drive;return}
    keymatrixup 6 0x02
    set ::gbr_drive_x [peek 0x1306]
    set ::gbr_drive_y [peek 0x1307]
    # The current preemptive File Manager publishes its listing and probes
    # embedded APP icons incrementally. Wait for that real work to settle.
    gbr_double_click {after time 20.0 gbr_open_resource}
}

rename gbr_open_resource_first_click fr_base_open_resource_first_click
proc gbr_open_resource_first_click {} {
    if {![fr_low_ready]} {
        after time 0.002 gbr_open_resource_first_click
        return
    }
    keymatrixup 6 0x02
    fr_base_open_resource_first_click
}

proc fr_check {condition message} {
    if {!$condition} {
        catch {screenshot -raw $::gbr_screenshot}
        gbr_finish "FAIL FormRef $message"
    }
}

proc fr_key_up {row mask callback} {
    keymatrixup $row $mask
    after time 1.0 $callback
}

proc fr_key {row mask callback} {
    keymatrixdown $row $mask
    after time 0.12 [list fr_key_up $row $mask $callback]
}

proc fr_click {callback} {
    set ::fr_click_callback $callback
    set ::fr_click_deadline [expr {[machine_info time] + 4.0}]
    keymatrixdown 8 0x01
    after time 0.02 fr_click_polled
}

proc fr_click_polled {} {
    if {[fr_low_ready] && ([peek 0x1308] & 4)} {
        keymatrixup 8 0x01
        keymatrixup 6 0x02
        after time 1.0 $::fr_click_callback
    } elseif {[machine_info time] >= $::fr_click_deadline} {
        keymatrixup 8 0x01
        gbr_finish "FAIL FormRef close click was not polled"
    } else {
        after time 0.02 fr_click_polled
    }
}

proc fr_forward_checked {} {
    if {![fr_app_mapped]} {after time 0.002 fr_forward_checked;return}
    fr_check [expr {[peek $::fr_focus] == 3}] forward_tab
    # Escape cancels the synchronous modal without committing state.
    fr_key 7 0x04 fr_modal_cancelled
}

proc fr_modal_cancelled {} {
    if {![fr_low_ready]} {after time 0.002 fr_modal_cancelled;return}
    if {[peek 0x1350] != 3 || [peek 0x1351] != 2} {
        if {[machine_info time] < $::fr_deadline} {
            after time 0.05 fr_modal_cancelled
            return
        }
        gbr_finish "FAIL FormRef modal cancel/window state"
        return
    }
    # Wait for the compositor to execute the bounded post-modal redraw and its
    # second sealed call before injecting teardown input. On a 3.58 MHz target
    # that repaint can legitimately outlive a fixed wall-clock delay.
    set ::fr_deadline [expr {[machine_info time] + 30.0}]
    after time 0.05 fr_refresh_done
}

proc fr_refresh_done {} {
    if {![fr_app_mapped]} {after time 0.002 fr_refresh_done;return}
    if {[peek $::fr_calls] >= 2 && [peek $::fr_status] == 0} {
        after time 0.25 fr_close_key
    } elseif {[machine_info time] >= $::fr_deadline} {
        gbr_finish "FAIL FormRef post-modal secondary refresh calls=[peek $::fr_calls] status=[peek $::fr_status]"
    } else {
        after time 0.05 fr_refresh_done
    }
}

proc fr_close_key {} {
    set ::fr_deadline [expr {[machine_info time] + 10.0}]
    keymatrixdown 7 0x04
    after time 0.02 fr_close_polled
}

proc fr_close_polled {} {
    if {[fr_low_ready] && ([peek 0x1308] & 2)} {
        keymatrixup 7 0x04
        after time 1.0 fr_app_closed
    } elseif {[machine_info time] >= $::fr_deadline} {
        keymatrixup 7 0x04
        gbr_finish "FAIL FormRef close key was not polled"
    } else {
        after time 0.02 fr_close_polled
    }
}

proc fr_app_closed {} {
    if {![fr_low_ready]} {after time 0.002 fr_app_closed;return}
    if {[peek 0x1350] != 2} {
        if {[machine_info time] < $::fr_deadline} {
            after time 0.05 fr_app_closed
            return
        }
        gbr_finish "FAIL FormRef app cleanup nwin=[peek 0x1350] focus=[peek 0x1351] pointer=[peek 0x1306],[peek 0x1307]"
        return
    }
    catch {screenshot -raw $::gbr_screenshot}
    gbr_finish PASS
}

proc fr_modal_entered {} {
    set ::fr_modal_seen 1
    set ::pause off
    after time 1.0 fr_modal_ready
}

proc fr_modal_ready {} {
    if {![fr_app_mapped]} {after time 0.002 fr_modal_ready;return}
    fr_check [expr {$::fr_modal_seen && [peek $::fr_ready] == 1}] resource
    fr_check [expr {[peek $::fr_focus] == 2}] initial_focus
    fr_check [expr {[peek [expr {$::fr_states+4}]] == 8 &&
                    [peek [expr {$::fr_states+6}]] == 4 &&
                    [peek [expr {$::fr_states+8}]] == 4}] initial_states
    fr_key 7 0x08 fr_forward_checked
}

proc fr_open_form {} {
    keymatrixup 6 0x02
    debug set_bp $::fr_modal {} {fr_modal_entered}
    gbr_single_click fr_wait_modal 1.0
}

proc fr_wait_modal {} {
    if {$::fr_modal_seen} {return}
    if {[machine_info time] >= $::fr_deadline} {
        gbr_finish "FAIL FormRef modal entry"
    } else {
        after time 0.05 fr_wait_modal
    }
}

# Replace GBRDEMO's post-launch button path. The base layer still performs the
# real drive/File Manager/A.APP double-click sequence and watches APP entry.
rename gbr_resource_click fr_base_resource_click
proc gbr_resource_click {} {
    incr ::gbr_resource_clicks
    set delay [expr {$::gbr_resource_clicks == 2 ? 20.0 : 0.75}]
    gbr_single_click gbr_resource_click_check $delay
}
rename gbr_resource_click_check fr_base_resource_click_check
proc gbr_resource_click_check {} {
    if {![fr_low_ready]} {
        after time 0.002 gbr_resource_click_check
        return
    }
    if {$::gbr_entry_seen || ([peek 0x1350] == 3 && [peek 0x1351] == 2)} {
        set ::fr_deadline [expr {[machine_info time] + 30.0}]
        after time 4.0 {gbr_move_to 30 103 fr_open_form}
    } elseif {$::gbr_resource_clicks >= 6} {
        gbr_finish "FAIL FormRef window was not published"
    } else {
        gbr_resource_click
    }
}
