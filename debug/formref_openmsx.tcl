# Exercise the resource-driven MSX2 FormRef with real keyboard-matrix events.
# The driver opens the test image's root-level A.APP (an exact copy of the
# shipped /GBENCH/FORMREF.APP), opens its form, traverses focus with Tab,
# activates Style and Level with Return, saves, and captures both states.

set throttle off
set pause_on_lost_focus false
set pause off

set fr_output $::env(GEMBENCH_FORMREF_OUTPUT)
set fr_focus_screenshot $::env(GEMBENCH_FORMREF_FOCUS_SCREENSHOT)
set fr_final_screenshot $::env(GEMBENCH_FORMREF_FINAL_SCREENSHOT)
set fr_deadline 0
set fr_target_x 0
set fr_target_y 0
set fr_callback ""
set fr_entry_seen 0
set fr_start_seen 0
set fr_main_seen 0
set fr_resource_seen 0
set fr_resource_return_seen 0
set fr_wm_call_seen 0
set fr_wm_seen 0
set fr_outer_draw_seen 0
set fr_modal_seen 0
set fr_modal_draw_seen 0
set fr_save_seen 0
set fr_restore_seen 0
set fr_restore_deadline 0
set fr_focus_capture_deadline 0
set fr_final_capture_deadline 0
set fr_launch_clicks 0
set fr_form_clicks 0
set fr_tree_count -1
set fr_main_sp -1
set fr_saved_style -1
set fr_saved_level -1

proc fr_release_all {} {
    catch {keymatrixup 8 0x01}
    catch {keymatrixup 8 0x10}
    catch {keymatrixup 8 0x20}
    catch {keymatrixup 8 0x40}
    catch {keymatrixup 8 0x80}
    catch {keymatrixup 7 0x08}
    catch {keymatrixup 7 0x80}
}

proc fr_is_loaded {} {
    # Breakpoints in the #4000-#7FFF application page are shared by every
    # application. Match FormRef's main call sequence and GBR descriptor so
    # File Manager activity cannot satisfy the launch checks.
    expr {[peek 0x487B] == 0xCD && [peek 0x487C] == 0xF7 &&
          [peek 0x487D] == 0x44 && [peek 0x487E] == 0x32 &&
          [peek 0x7454] == 0x95 && [peek 0x7459] == 0x01}
}

proc fr_screen_ready {} {
    set x [peek 0x1306]
    set y [peek 0x1307]
    set vdp_status [debug read {VDP status regs} 2]
    expr {$x <= 127 && $y <= 211 && !($vdp_status & 0x01) &&
          [fr_is_loaded]}
}

proc fr_finish {status} {
    fr_release_all
    if {$status ne "PASS"} {
        catch {screenshot -raw $::fr_final_screenshot}
    }
    set handle [open $::fr_output w]
    puts $handle "STATUS=$status"
    puts $handle "ENTRY_SEEN=$::fr_entry_seen"
    puts $handle "START_SEEN=$::fr_start_seen"
    puts $handle "MAIN_SEEN=$::fr_main_seen"
    puts $handle "RESOURCE_SEEN=$::fr_resource_seen"
    puts $handle "RESOURCE_RETURN_SEEN=$::fr_resource_return_seen"
    puts $handle "WM_CALL_SEEN=$::fr_wm_call_seen"
    puts $handle "WM_SEEN=$::fr_wm_seen"
    puts $handle "OUTER_DRAW_SEEN=$::fr_outer_draw_seen"
    puts $handle "MODAL_SEEN=$::fr_modal_seen"
    puts $handle "MODAL_DRAW_SEEN=$::fr_modal_draw_seen"
    puts $handle "SAVE_SEEN=$::fr_save_seen"
    puts $handle "RESTORE_SEEN=$::fr_restore_seen"
    puts $handle "TREE_COUNT=$::fr_tree_count"
    puts $handle "MAIN_SP=$::fr_main_sp"
    puts $handle "LAUNCH_CLICKS=$::fr_launch_clicks"
    puts $handle "FORM_CLICKS=$::fr_form_clicks"
    puts $handle "SAVED_STYLE=$::fr_saved_style"
    puts $handle "SAVED_LEVEL=$::fr_saved_level"
    puts $handle "FINAL_POINTER=[peek 0x1306],[peek 0x1307]"
    close $handle
    exit
}

proc fr_move_tick {} {
    set x [peek 0x1306]
    set y [peek 0x1307]
    catch {keymatrixup 8 0x10}
    catch {keymatrixup 8 0x20}
    catch {keymatrixup 8 0x40}
    catch {keymatrixup 8 0x80}
    if {$x > 127 || $y > 211} {
        after time 0.002 fr_move_tick
        return
    }
    if {[expr {abs($x - $::fr_target_x)}] <= 1 &&
        [expr {abs($y - $::fr_target_y)}] <= 3} {
        after time 0.08 $::fr_callback
        return
    }
    if {[machine_info time] >= $::fr_deadline} {
        fr_finish "TIMEOUT moving pointer"
        return
    }
    if {$x < $::fr_target_x - 1} {
        keymatrixdown 8 0x80
    } elseif {$x > $::fr_target_x + 1} {
        keymatrixdown 8 0x10
    } elseif {$y < $::fr_target_y - 3} {
        keymatrixdown 8 0x40
    } else {
        keymatrixdown 8 0x20
    }
    after time 0.025 fr_move_tick
}

proc fr_move_to {x y callback} {
    set ::fr_target_x $x
    set ::fr_target_y $y
    set ::fr_callback $callback
    set ::fr_deadline [expr {[machine_info time] + 15.0}]
    fr_move_tick
}

proc fr_click_up {callback delay} {
    keymatrixup 8 0x01
    after time $delay $callback
}

proc fr_single_click {callback delay} {
    keymatrixdown 8 0x01
    after time 0.08 [list fr_click_up $callback $delay]
}

proc fr_double_second_up {callback} {
    keymatrixup 8 0x01
    after time 0.08 $callback
}

proc fr_double_second {callback} {
    keymatrixdown 8 0x01
    after time 0.06 [list fr_double_second_up $callback]
}

proc fr_double_first_up {callback} {
    keymatrixup 8 0x01
    after time 0.10 [list fr_double_second $callback]
}

proc fr_double_click {callback} {
    keymatrixdown 8 0x01
    after time 0.06 [list fr_double_first_up $callback]
}

proc fr_key_up {row mask callback delay} {
    keymatrixup $row $mask
    after time $delay $callback
}

proc fr_key {row mask callback {delay 0.75}} {
    keymatrixdown $row $mask
    after time 0.08 [list fr_key_up $row $mask $callback $delay]
}

proc fr_capture_final {} {
    if {!$::fr_final_capture_deadline} {
        set ::fr_final_capture_deadline [expr {[machine_info time] + 30.0}]
    }
    if {![fr_screen_ready]} {
        if {[machine_info time] >= $::fr_final_capture_deadline} {
            fr_finish "FAIL final screen never became capture-ready"
        } else {
            after time 0.01 fr_capture_final
        }
    } elseif {!$::fr_entry_seen || !$::fr_start_seen || !$::fr_main_seen ||
        !$::fr_resource_seen || !$::fr_resource_return_seen ||
        !$::fr_wm_call_seen || !$::fr_wm_seen || !$::fr_outer_draw_seen ||
        !$::fr_modal_seen ||
        !$::fr_modal_draw_seen || !$::fr_save_seen ||
        !$::fr_restore_seen ||
        $::fr_tree_count != 1 || $::fr_saved_style != 1 ||
        $::fr_saved_level != 2} {
        fr_finish "FAIL FormRef launch trace incomplete"
    } else {
        fr_finish PASS
    }
}

proc fr_wait_restore {} {
    if {$::fr_restore_seen} {
        after time 1.0 fr_capture_final
    } elseif {[machine_info time] >= $::fr_restore_deadline} {
        fr_finish "FAIL modal restore did not complete"
    } else {
        after time 0.1 fr_wait_restore
    }
}

proc fr_save {} {
    set ::fr_restore_deadline [expr {[machine_info time] + 20.0}]
    fr_key 7 0x80 fr_wait_restore
}

proc fr_tab_save {} {
    fr_key 7 0x08 fr_save 5.0
}

proc fr_tab_increment {} {
    fr_key 7 0x08 fr_tab_save 5.0
}

proc fr_capture_focus {} {
    if {!$::fr_focus_capture_deadline} {
        set ::fr_focus_capture_deadline [expr {[machine_info time] + 30.0}]
    }
    if {![fr_screen_ready]} {
        if {[machine_info time] >= $::fr_focus_capture_deadline} {
            fr_finish "FAIL focus screen never became capture-ready"
        } else {
            after time 0.01 fr_capture_focus
        }
    } elseif {[catch {screenshot -raw $::fr_focus_screenshot} error]} {
        fr_finish "FAIL focus screenshot: $error"
    } else {
        after time 5.0 fr_tab_increment
    }
}

proc fr_decrement {} {
    fr_key 7 0x80 {after time 30.0 fr_capture_focus}
}

proc fr_tab_decrement {} {
    fr_key 7 0x08 fr_decrement 5.0
}

proc fr_choose_style {} {
    fr_key 7 0x80 fr_tab_decrement 10.0
}

proc fr_tab_style {} {
    fr_key 7 0x08 fr_choose_style 5.0
}

proc fr_modal_check {} {
    if {$::fr_modal_draw_seen} {
        after time 12.0 fr_tab_style
    } elseif {$::fr_form_clicks >= 6} {
        fr_finish "FAIL FormRef modal was not drawn"
    } else {
        fr_open_form
    }
}

proc fr_open_form {} {
    incr ::fr_form_clicks
    fr_single_click fr_modal_check 1.0
}

proc fr_launch_wait {} {
    if {$::fr_outer_draw_seen} {
        after time 5.0 {fr_move_to 30 103 fr_open_form}
    } elseif {[machine_info time] >= $::fr_deadline} {
        fr_finish "FAIL FORMREF entry was not reached"
    } else {
        after time 0.1 fr_launch_wait
    }
}

proc fr_launch_formref {} {
    set ::fr_entry_seen 0
    set ::fr_launch_clicks 2
    debug set_bp 0x4000 {} {if {[fr_is_loaded]} {set ::fr_entry_seen 1}; set ::pause off}
    debug set_bp 0x4320 {} {if {[fr_is_loaded]} {set ::fr_start_seen 1}; set ::pause off}
    debug set_bp 0x487B {} {if {[fr_is_loaded]} {set ::fr_main_seen 1; set ::fr_tree_count [peek 0x764D]; set ::fr_main_sp [reg SP]}; set ::pause off}
    debug set_bp 0x44F7 {} {if {[fr_is_loaded]} {set ::fr_resource_seen 1}; set ::pause off}
    debug set_bp 0x487E {} {if {[fr_is_loaded]} {set ::fr_resource_return_seen 1}; set ::pause off}
    debug set_bp 0x4884 {} {if {[fr_is_loaded]} {set ::fr_wm_call_seen 1}; set ::pause off}
    debug set_bp 0x738C {} {if {[fr_is_loaded]} {set ::fr_wm_seen 1}; set ::pause off}
    debug set_bp 0x470C {} {if {[fr_is_loaded]} {set ::fr_outer_draw_seen 1}; set ::pause off}
    debug set_bp 0x467C {} {if {[fr_is_loaded]} {set ::fr_modal_seen 1}; set ::pause off}
    debug set_bp 0x6A2E {} {if {[fr_is_loaded]} {set ::fr_modal_draw_seen 1}; set ::pause off}
    debug set_bp 0x4596 {} {if {[fr_is_loaded]} {set ::fr_save_seen 1; set ::fr_saved_style [peek 0x760D]; set ::fr_saved_level [peek 0x7647]}; set ::pause off}
    debug set_bp 0x52D0 {} {if {[fr_is_loaded]} {set ::fr_restore_seen 1}; set ::pause off}
    set ::fr_deadline [expr {[machine_info time] + 30.0}]
    fr_double_click fr_launch_wait
}

proc fr_open_drive {} {
    # The three root folders occupy row one; A.APP is the first cell of row two.
    fr_double_click {after time 4.0 {fr_move_to 16 104 fr_launch_formref}}
}

# The generated Nextor image reaches the desktop after about 50 emulated
# seconds on the reference NMS 8250.
after time 62.0 {fr_move_to 4 40 fr_open_drive}
