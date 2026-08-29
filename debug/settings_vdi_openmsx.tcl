# Launch the staged Settings alias, open Desktop colours, and require the
# compact VDI init/fill/frame entry points to execute before capturing.
set throttle off
set pause_on_lost_focus false
set pause off

set sv_output $::env(GEMBENCH_SETTINGS_OUTPUT)
set sv_screenshot $::env(GEMBENCH_SETTINGS_SCREENSHOT)
set sv_screenshots [expr {$::env(GEMBENCH_SETTINGS_SCREENSHOTS) + 0}]
set sv_addr_init [expr {$::env(GEMBENCH_SETTINGS_VDI_INIT) + 0}]
set sv_addr_fill [expr {$::env(GEMBENCH_SETTINGS_VDI_FILL) + 0}]
set sv_addr_frame [expr {$::env(GEMBENCH_SETTINGS_VDI_FRAME) + 0}]
set sv_addr_gb_fill [expr {$::env(GEMBENCH_SETTINGS_GB_FILL) + 0}]
set sv_addr_gb_frame [expr {$::env(GEMBENCH_SETTINGS_GB_FRAME) + 0}]
set sv_addr_main [expr {$::env(GEMBENCH_SETTINGS_MAIN) + 0}]
set sv_addr_draw [expr {$::env(GEMBENCH_SETTINGS_DRAW) + 0}]
set sv_addr_draw_ret [expr {$::env(GEMBENCH_SETTINGS_DRAW_RET) + 0}]
set sv_addr_colp_ret [expr {$::env(GEMBENCH_SETTINGS_COLP_RET) + 0}]
set sv_addr_picker [expr {$::env(GEMBENCH_SETTINGS_PICKER_STATE) + 0}]
set sv_probe [split $::env(GEMBENCH_SETTINGS_PROBE) ,]
set sv_main_seen 0
set sv_outer_draw_seen 0
set sv_outer_draw_done 0
set sv_draw_calls {}
set sv_init_hits 0
set sv_fill_hits 0
set sv_frame_hits 0
set sv_editor_draws 0
set sv_editor_ready 0
set sv_target_x 0
set sv_target_y 0
set sv_callback ""
set sv_deadline 0
set sv_capture_deadline 0

proc sv_is_loaded {} {
    set index 0
    foreach expected $::sv_probe {
        if {[peek [expr {$::sv_addr_init + $index}]] != $expected} {
            return 0
        }
        incr index
    }
    return 1
}

proc sv_release {} {
    catch {keymatrixup 8 0x01}
    catch {keymatrixup 8 0x10}
    catch {keymatrixup 8 0x20}
    catch {keymatrixup 8 0x40}
    catch {keymatrixup 8 0x80}
}

proc sv_finish {status} {
    sv_release
    set handle [open $::sv_output w]
    puts $handle "STATUS=$status"
    puts $handle "VDI_INIT_HITS=$::sv_init_hits"
    puts $handle "VDI_FILL_HITS=$::sv_fill_hits"
    puts $handle "VDI_FRAME_HITS=$::sv_frame_hits"
    puts $handle "MAIN_SEEN=$::sv_main_seen"
    puts $handle "OUTER_DRAW_SEEN=$::sv_outer_draw_seen"
    puts $handle "OUTER_DRAW_DONE=$::sv_outer_draw_done"
    puts $handle "PICKER_STATE=[peek $::sv_addr_picker]"
    puts $handle "EDITOR_DRAWS=$::sv_editor_draws"
    puts $handle "DRAW_CALLS=[join $::sv_draw_calls { }]"
    puts $handle "SETTINGS_PAGE_LOADED=[sv_is_loaded]"
    puts $handle "FINAL_PC=[reg PC]"
    puts $handle "FINAL_POINTER=[peek 0x1306],[peek 0x1307]"
    set window_count [peek 0x1350]
    set zorder {}
    for {set index 0} {$index < $window_count} {incr index} {
        lappend zorder [peek [expr {0x141A + $index}]]
    }
    puts $handle "WINDOW_COUNT=$window_count"
    puts $handle "WINDOW_FOCUS=[peek 0x1351]"
    puts $handle "WINDOW_Z=[join $zorder ,]"
    close $handle
    exit
}

proc sv_move_tick {} {
    set x [peek 0x1306]
    set y [peek 0x1307]
    sv_release
    if {$x > 127 || $y > 211} {
        after time 0.002 sv_move_tick
        return
    }
    if {[expr {abs($x - $::sv_target_x)}] <= 1 &&
        [expr {abs($y - $::sv_target_y)}] <= 3} {
        after time 0.12 sv_move_settled
        return
    }
    if {[machine_info time] >= $::sv_deadline} {
        sv_finish "FAIL pointer timeout"
        return
    }
    if {$x < $::sv_target_x - 1} {
        keymatrixdown 8 0x80
    } elseif {$x > $::sv_target_x + 1} {
        keymatrixdown 8 0x10
    } elseif {$y < $::sv_target_y - 3} {
        keymatrixdown 8 0x40
    } else {
        keymatrixdown 8 0x20
    }
    after time 0.025 sv_move_tick
}

proc sv_move_settled {} {
    set x [peek 0x1306]
    set y [peek 0x1307]
    sv_release
    if {$x <= 127 && $y <= 211 &&
        [expr {abs($x - $::sv_target_x)}] <= 1 &&
        [expr {abs($y - $::sv_target_y)}] <= 3} {
        after time 0.08 $::sv_callback
    } else {
        after time 0.002 sv_move_tick
    }
}

proc sv_move_to {x y callback} {
    set ::sv_target_x $x
    set ::sv_target_y $y
    set ::sv_callback $callback
    set ::sv_deadline [expr {[machine_info time] + 15.0}]
    sv_move_tick
}

proc sv_click_up {callback delay} {
    keymatrixup 8 0x01
    after time $delay $callback
}

proc sv_click {callback {delay 0.75}} {
    keymatrixdown 8 0x01
    after time 0.08 [list sv_click_up $callback $delay]
}

proc sv_double_second_up {callback} {
    keymatrixup 8 0x01
    after time 0.08 $callback
}

proc sv_double_second {callback} {
    keymatrixdown 8 0x01
    after time 0.06 [list sv_double_second_up $callback]
}

proc sv_double_first_up {callback} {
    keymatrixup 8 0x01
    after time 0.10 [list sv_double_second $callback]
}

proc sv_double_click {callback} {
    keymatrixdown 8 0x01
    after time 0.06 [list sv_double_first_up $callback]
}

proc sv_capture {} {
    if {!$::sv_capture_deadline} {
        set ::sv_capture_deadline [expr {[machine_info time] + 20.0}]
    }
    set vdp_status [debug read {VDP status regs} 2]
    set pointer_x [peek 0x1306]
    set pointer_y [peek 0x1307]
    if {![sv_is_loaded] || !$::sv_editor_ready ||
        $pointer_x > 127 || $pointer_y > 211 ||
        ($vdp_status & 0x01)} {
        if {[machine_info time] >= $::sv_capture_deadline} {
            sv_finish "FAIL Settings page did not remain capture-ready"
        } else {
            after time 0.002 sv_capture
        }
        return
    }
    if {!$::sv_main_seen || !$::sv_init_hits || !$::sv_fill_hits ||
        !$::sv_frame_hits} {
        sv_finish "FAIL incomplete VDI trace"
        return
    }
    if {$::sv_screenshots &&
        [catch {screenshot -raw $::sv_screenshot} error]} {
        sv_finish "FAIL screenshot: $error"
        return
    }
    sv_finish PASS
}

proc sv_wait_vdi {} {
    if {$::sv_init_hits && $::sv_fill_hits && $::sv_frame_hits &&
        $::sv_editor_ready} {
        after time 60.0 sv_capture
    } elseif {[machine_info time] >= $::sv_deadline} {
        sv_finish "FAIL VDI path was not reached"
    } else {
        after time 0.1 sv_wait_vdi
    }
}

proc sv_wait_launch {} {
    if {$::sv_main_seen && $::sv_outer_draw_seen && $::sv_outer_draw_done} {
        after time 1.0 {sv_move_to 20 105 sv_open_colours}
    } elseif {[machine_info time] >= $::sv_deadline} {
        sv_finish "FAIL Settings main was not reached"
    } else {
        after time 0.1 sv_wait_launch
    }
}

proc sv_open_colours {} {
    set ::sv_deadline [expr {[machine_info time] + 120.0}]
    sv_click sv_wait_vdi 0.5
}

proc sv_launch_settings {} {
    debug set_bp $::sv_addr_main {} {
        if {[sv_is_loaded]} {set ::sv_main_seen 1}
        set ::pause off
    }
    debug set_bp $::sv_addr_draw {} {
        if {[sv_is_loaded]} {set ::sv_outer_draw_seen 1}
        set ::pause off
    }
    debug set_bp $::sv_addr_draw_ret {} {
        if {[sv_is_loaded]} {set ::sv_outer_draw_done 1}
        set ::pause off
    }
    debug set_bp $::sv_addr_init {} {
        if {[sv_is_loaded]} {
            incr ::sv_init_hits
            set ::sv_editor_ready 0
        }
        set ::pause off
    }
    debug set_bp $::sv_addr_colp_ret {} {
        if {[sv_is_loaded]} {
            incr ::sv_editor_draws
            set ::sv_editor_ready 1
        }
        set ::pause off
    }
    debug set_bp $::sv_addr_fill {} {
        if {[sv_is_loaded]} {incr ::sv_fill_hits}
        set ::pause off
    }
    debug set_bp $::sv_addr_frame {} {
        if {[sv_is_loaded]} {incr ::sv_frame_hits}
        set ::pause off
    }
    debug set_bp $::sv_addr_gb_fill {} {
        if {[sv_is_loaded] && $::sv_init_hits &&
            [llength $::sv_draw_calls] < 24} {
            lappend ::sv_draw_calls [format "F:%d,%d,%d,%d,%d" \
                [reg A] [reg L] [peek [expr {[reg SP] + 2}]] \
                [peek [expr {[reg SP] + 3}]] \
                [peek [expr {[reg SP] + 4}]]]
        }
        set ::pause off
    }
    debug set_bp $::sv_addr_gb_frame {} {
        if {[sv_is_loaded] && $::sv_init_hits &&
            [llength $::sv_draw_calls] < 24} {
            lappend ::sv_draw_calls [format "R:%d,%d,%d,%d,%d" \
                [reg A] [reg L] [peek [expr {[reg SP] + 2}]] \
                [peek [expr {[reg SP] + 3}]] \
                [peek [expr {[reg SP] + 4}]]]
        }
        set ::pause off
    }
    set ::sv_deadline [expr {[machine_info time] + 180.0}]
    sv_double_click sv_wait_launch
}

proc sv_open_drive {} {
    # Three root folders occupy row one; staged A.APP is row two, cell one.
    sv_double_click {after time 4.0 {sv_move_to 16 104 sv_launch_settings}}
}

after time 62.0 {sv_move_to 4 40 sv_open_drive}
