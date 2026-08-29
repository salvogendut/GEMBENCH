# Exercise Clock's GEMBENCH multi-event subscription through the shipped MSX2
# window manager.  A root-level A.APP alias keeps File Manager navigation
# deterministic; the payload is the exact staged CLOCK.RAW.

set throttle off
set pause_on_lost_focus false
set pause off

proc me_env_addr {name} { expr {$::env($name) + 0} }

set me_output $::env(GEMBENCH_EVENT_OUTPUT)
set me_c_draw [me_env_addr GEMBENCH_EVENT_C_DRAW]
set me_c_frame [me_env_addr GEMBENCH_EVENT_C_FRAME]
set me_c_click [me_env_addr GEMBENCH_EVENT_C_CLICK]
set me_after_collect [me_env_addr GEMBENCH_EVENT_AFTER_COLLECT]
set me_main [me_env_addr GEMBENCH_EVENT_MAIN]
set me_sig0 [me_env_addr GEMBENCH_EVENT_SIG0]
set me_sig1 [me_env_addr GEMBENCH_EVENT_SIG1]
set me_sig2 [me_env_addr GEMBENCH_EVENT_SIG2]
set me_show_sec [me_env_addr GEMBENCH_EVENT_SHOW_SEC]
set me_subscription [me_env_addr GEMBENCH_EVENT_SUBSCRIPTION]
set me_event [me_env_addr GEMBENCH_EVENT_RECORD]
set me_deadline 0
set me_target_x 0
set me_target_y 0
set me_callback ""
set me_draw_hits 0
set me_frame_hits 0
set me_click_hits 0
set me_pointer_window_hits 0
set me_key_hits 0
set me_last_key 0
set me_started 0
set me_show_value -1
set me_classes_value -1
set me_pointer_seen_value -1
set me_pointer_x_value -1
set me_pointer_y_value -1

proc me_is_loaded {} {
    expr {[peek $::me_main] == $::me_sig0 &&
          [peek [expr {$::me_main + 1}]] == $::me_sig1 &&
          [peek [expr {$::me_main + 2}]] == $::me_sig2}
}

proc me_release_all {} {
    catch {keymatrixup 8 0x01}
    catch {keymatrixup 8 0x10}
    catch {keymatrixup 8 0x20}
    catch {keymatrixup 8 0x40}
    catch {keymatrixup 8 0x80}
    catch {keymatrixup 5 0x01}
    catch {type -cancel}
}

proc me_capture_state {} {
    set ::me_show_value [peek $::me_show_sec]
    set ::me_classes_value [peek $::me_event]
    set ::me_pointer_seen_value [peek [expr {$::me_subscription + 5}]]
    set ::me_pointer_x_value [peek [expr {$::me_subscription + 3}]]
    set ::me_pointer_y_value [peek [expr {$::me_subscription + 4}]]
}

proc me_finish {status} {
    me_release_all
    set handle [open $::me_output w]
    puts $handle "STATUS=$status"
    puts $handle "DRAW_HITS=$::me_draw_hits"
    puts $handle "TIMER_HITS=$::me_frame_hits"
    puts $handle "POINTER_CLICK_HITS=$::me_click_hits"
    puts $handle "POINTER_WINDOW_HITS=$::me_pointer_window_hits"
    puts $handle "KEY_HITS=$::me_key_hits"
    puts $handle "LAST_KEY=$::me_last_key"
    puts $handle "SHOW_SECONDS=$::me_show_value"
    puts $handle "EVENT_CLASSES=$::me_classes_value"
    puts $handle "POINTER_SEEN=$::me_pointer_seen_value"
    puts $handle "POINTER_LAST=$::me_pointer_x_value,$::me_pointer_y_value"
    puts $handle "FINAL_POINTER=[peek 0x1306],[peek 0x1307]"
    puts $handle [format "FINAL_PC=%04X" [reg PC]]
    puts $handle [format "FINAL_SP=%04X" [reg SP]]
    close $handle
    exit
}

proc me_move_tick {} {
    set x [peek 0x1306]
    set y [peek 0x1307]
    catch {keymatrixup 8 0x10}
    catch {keymatrixup 8 0x20}
    catch {keymatrixup 8 0x40}
    catch {keymatrixup 8 0x80}
    if {$x > 127 || $y > 211} {
        after time 0.002 me_move_tick
        return
    }
    if {[expr {abs($x - $::me_target_x)}] <= 1 &&
        [expr {abs($y - $::me_target_y)}] <= 3} {
        after time 0.12 me_move_settled
        return
    }
    if {[machine_info time] >= $::me_deadline} {
        me_finish "TIMEOUT moving pointer"
        return
    }
    if {$x < $::me_target_x - 1} {
        keymatrixdown 8 0x80
    } elseif {$x > $::me_target_x + 1} {
        keymatrixdown 8 0x10
    } elseif {$y < $::me_target_y - 3} {
        keymatrixdown 8 0x40
    } else {
        keymatrixdown 8 0x20
    }
    after time 0.025 me_move_tick
}

proc me_move_settled {} {
    set x [peek 0x1306]
    set y [peek 0x1307]
    me_release_all
    if {$x <= 127 && $y <= 211 &&
        [expr {abs($x - $::me_target_x)}] <= 1 &&
        [expr {abs($y - $::me_target_y)}] <= 3} {
        after time 0.08 $::me_callback
    } else {
        after time 0.002 me_move_tick
    }
}

proc me_move_to {x y callback} {
    me_release_all
    set ::me_target_x $x
    set ::me_target_y $y
    set ::me_callback $callback
    set ::me_deadline [expr {[machine_info time] + 30.0}]
    me_move_tick
}

proc me_click_up {callback} {
    keymatrixup 8 0x01
    after time 0.8 $callback
}

proc me_click {callback} {
    keymatrixdown 8 0x01
    after time 0.08 [list me_click_up $callback]
}

proc me_double_second_up {callback} {
    keymatrixup 8 0x01
    after time 0.10 $callback
}

proc me_double_second {callback} {
    keymatrixdown 8 0x01
    after time 0.06 [list me_double_second_up $callback]
}

proc me_double_first_up {callback} {
    keymatrixup 8 0x01
    after time 0.10 [list me_double_second $callback]
}

proc me_double_click {callback} {
    keymatrixdown 8 0x01
    after time 0.06 [list me_double_first_up $callback]
}

proc me_pointer_check {} {
    if {$::me_click_hits < 1 || $::me_pointer_window_hits < 1 ||
        !$::me_pointer_seen_value ||
        [expr {abs($::me_pointer_x_value - 49)}] > 1 ||
        [expr {abs($::me_pointer_y_value - 138)}] > 3} {
        me_finish "FAIL pointer subscription/click"
    } elseif {$::me_draw_hits < 1 || $::me_frame_hits < 2} {
        me_finish "FAIL window/timer delivery"
    } elseif {$::me_show_value != 1} {
        me_finish "FAIL keyboard subscription"
    } else {
        me_finish PASS
    }
}

proc me_pointer_click {} {
    me_click me_pointer_check
}

proc me_key_check {} {
    if {$::me_show_value != 1} {
        me_finish "FAIL S shortcut did not toggle seconds"
    } else {
        me_move_to 49 138 me_pointer_click
    }
}

proc me_key_release {} {
    keymatrixup 5 0x01
    # The S action repaints every live window; leave the 3.58 MHz target enough
    # emulated time to return to Clock before sampling its banked state.
    after time 8.0 me_key_check
}

proc me_type_key {} {
    # Standard MSX matrix row 5, bit 0 is S.
    keymatrixdown 5 0x01
    after time 0.60 me_key_release
}

proc me_clock_ready {} {
    if {[me_is_loaded] && [peek 0x1350] >= 3 &&
        $::me_draw_hits >= 1 && $::me_frame_hits >= 2} {
        after time 0.5 me_type_key
    } elseif {[machine_info time] >= $::me_deadline} {
        me_finish "FAIL Clock did not enter multi-event loop"
    } else {
        after time 0.1 me_clock_ready
    }
}

proc me_launch_clock {} {
    debug set_bp $::me_c_draw {} {
        if {[me_is_loaded]} {incr ::me_draw_hits; me_capture_state}
        set ::pause off
    }
    debug set_bp $::me_c_frame {} {
        if {[me_is_loaded]} {incr ::me_frame_hits; me_capture_state}
        set ::pause off
    }
    debug set_bp $::me_c_click {} {
        if {[me_is_loaded]} {incr ::me_click_hits; me_capture_state}
        set ::pause off
    }
    debug set_bp $::me_after_collect {} {
        if {[me_is_loaded]} {
            me_capture_state
            if {($::me_classes_value & 1) != 0} {
                incr ::me_key_hits
                set ::me_last_key [peek [expr {$::me_event + 1}]]
            }
            if {($::me_classes_value & 10) == 10} {
                incr ::me_pointer_window_hits
            }
        }
        set ::pause off
    }
    set ::me_deadline [expr {[machine_info time] + 30.0}]
    me_double_click me_clock_ready
}

proc me_open_drive {} {
    # The root folders occupy row one; the staged A.APP alias is row two, cell one.
    me_double_click {after time 4.0 {me_move_to 16 104 me_launch_clock}}
}

# The generated Nextor image reaches the desktop after roughly 50 emulated seconds.
after time 62.0 {me_move_to 4 40 me_open_drive}
