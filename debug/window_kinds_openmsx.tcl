# Exercise the first explicitly versioned GEMBENCH window kind through real MSX keyboard-
# matrix pointer input. The File Manager is maximised/restored, moved and
# resized entirely by kernel-owned title/grip furniture.

set throttle off
set pause_on_lost_focus false
set pause off

set wk_output $::env(GEMBENCH_WINDOW_KINDS_OUTPUT)
set wk_screenshot $::env(GEMBENCH_WINDOW_KINDS_SCREENSHOT)
set wk_screenshots [expr {$::env(GEMBENCH_WINDOW_KINDS_SCREENSHOTS) + 0}]
set wk_fm_proc [expr {$::env(GEMBENCH_WINDOW_KINDS_FM_PROC)}]
set wk_list_state [expr {$::env(GEMBENCH_WINDOW_KINDS_LIST_STATE)}]
set wk_cursor_x [expr {$::env(GEMBENCH_WINDOW_KINDS_CURSOR_X)}]
set wk_deadline 0
set wk_target_x 0
set wk_target_y 0
set wk_callback ""
set wk_initial {}
set wk_maximized {}
set wk_restored {}
set wk_moved {}
set wk_sized {}
set wk_moved_messages 0
set wk_sized_messages 0
set wk_maximized_messages 0
set wk_move_attempts 0
set wk_resize_attempts 0
set wk_page0_slot -1
set wk_registered 0
set wk_list_ready 0
set wk_started 0

proc wk_release_all {} {
    catch {keymatrixup 8 0x01}
    catch {keymatrixup 8 0x10}
    catch {keymatrixup 8 0x20}
    catch {keymatrixup 8 0x40}
    catch {keymatrixup 8 0x80}
}

proc wk_rect {} {
    list [peek 0x1448] [peek 0x1449] [peek 0x144A] [peek 0x144B]
}

proc wk_rect_valid {rect} {
    lassign $rect x y w h
    expr {$x >= 0 && $x < 128 && $y >= 0 && $y < 212 &&
          $w > 0 && $h > 0 && $x + $w <= 128 && $y + $h <= 212}
}

proc wk_finish {status} {
    wk_release_all
    set handle [open $::wk_output w]
    puts $handle "STATUS=$status"
    puts $handle "INITIAL=$::wk_initial"
    puts $handle "MAXIMIZED=$::wk_maximized"
    puts $handle "RESTORED=$::wk_restored"
    puts $handle "MOVED=$::wk_moved"
    puts $handle "SIZED=$::wk_sized"
    puts $handle "MOVED_MESSAGES=$::wk_moved_messages"
    puts $handle "SIZED_MESSAGES=$::wk_sized_messages"
    puts $handle "MAXIMIZED_MESSAGES=$::wk_maximized_messages"
    puts $handle "MOVE_ATTEMPTS=$::wk_move_attempts"
    puts $handle "RESIZE_ATTEMPTS=$::wk_resize_attempts"
    puts $handle "FINAL_POINTER=[peek 0x1306],[peek 0x1307]"
    puts $handle [format "FINAL_PC=%04X" [reg PC]]
    puts $handle [format "FINAL_SP=%04X" [reg SP]]
    puts $handle [format "FINAL_PPI_A8=%02X" [debug read ioports 0xA8]]
    set raw_x [expr {[peek $::wk_cursor_x] + 256 * [peek [expr {$::wk_cursor_x + 1}]]}]
    set raw_y [expr {[peek [expr {$::wk_cursor_x + 2}]] +
                     256 * [peek [expr {$::wk_cursor_x + 3}]]}]
    puts $handle "FINAL_CURSOR_RAW=$raw_x,$raw_y"
    close $handle
    if {$::wk_screenshots && $status ne "PASS"} {
        catch {screenshot -raw $::wk_screenshot}
    }
    exit
}

proc wk_proc_break {} {
    set type [peek 0x1302]
    if {$type == 5 && [peek $::wk_list_state] == 0} {
        set ::wk_list_ready 1
    } elseif {$type == 8} {
        incr ::wk_moved_messages
    } elseif {$type == 9} {
        incr ::wk_sized_messages
    } elseif {$type == 10} {
        incr ::wk_maximized_messages
    }
    set pause off
}

proc wk_move_tick {} {
    # CALSLT briefly maps the BIOS ROM over page 0. Sampling 0x1306/0x1307 in
    # that interval can look like a valid (0,0) pointer and phase-lock the
    # steering timer to ROM reads. Only consume samples from the normal low-RAM
    # primary slot captured after File Manager registers.
    if {$::wk_page0_slot >= 0 &&
        [expr {[debug read ioports 0xA8] & 3}] != $::wk_page0_slot} {
        after time 0.002 wk_move_tick
        return
    }
    set x [peek 0x1306]
    set y [peek 0x1307]
    set mask 0
    catch {keymatrixup 8 0x10}
    catch {keymatrixup 8 0x20}
    catch {keymatrixup 8 0x40}
    catch {keymatrixup 8 0x80}
    if {$x > 127 || $y > 211} {
        after time 0.002 wk_move_tick
        return
    }
    if {[expr {abs($x - $::wk_target_x)}] <= 1 &&
        [expr {abs($y - $::wk_target_y)}] <= 3} {
        after time 0.08 $::wk_callback
        return
    }
    if {[machine_info time] >= $::wk_deadline} {
        wk_finish "TIMEOUT moving pointer"
        return
    }
    if {$x < $::wk_target_x - 1} {
        set mask 0x80
    } elseif {$x > $::wk_target_x + 1} {
        set mask 0x10
    } elseif {$y < $::wk_target_y - 3} {
        set mask 0x40
    } else {
        set mask 0x20
    }
    keymatrixdown 8 $mask
    # Hold across several 50 Hz polls, then leave an equally long released
    # interval. The release is long enough to reset the kernel acceleration
    # ramp regardless of timer/VBlank phase, avoiding boundary oscillation.
    after time 0.08 [list keymatrixup 8 $mask]
    after time 0.16 wk_move_tick
}

proc wk_move_to {x y callback} {
    wk_release_all
    set ::wk_target_x $x
    set ::wk_target_y $y
    set ::wk_callback $callback
    set ::wk_deadline [expr {[machine_info time] + 30.0}]
    wk_move_tick
}

proc wk_click_up {callback} {
    keymatrixup 8 0x01
    after time 1.0 $callback
}

proc wk_click {callback} {
    keymatrixdown 8 0x01
    after time 0.08 [list wk_click_up $callback]
}

proc wk_double_second_up {callback} {
    keymatrixup 8 0x01
    after time 0.10 $callback
}

proc wk_double_second {callback} {
    keymatrixdown 8 0x01
    after time 0.06 [list wk_double_second_up $callback]
}

proc wk_double_first_up {callback} {
    keymatrixup 8 0x01
    after time 0.10 [list wk_double_second $callback]
}

proc wk_double_click {callback} {
    keymatrixdown 8 0x01
    after time 0.06 [list wk_double_first_up $callback]
}

proc wk_wait_rect {expected callback label} {
    set current [wk_rect]
    if {![wk_rect_valid $current]} {
        after time 0.002 [list wk_wait_rect $expected $callback $label]
    } elseif {$current eq $expected} {
        after time 1.0 $callback
    } elseif {[machine_info time] >= $::wk_deadline} {
        wk_finish "FAIL $label geometry: [wk_rect]"
    } else {
        after time 0.1 [list wk_wait_rect $expected $callback $label]
    }
}

proc wk_wait_changed {before callback label} {
    set current [wk_rect]
    if {![wk_rect_valid $current]} {
        after time 0.002 [list wk_wait_changed $before $callback $label]
    } elseif {$current ne $before} {
        after time 1.0 $callback
    } elseif {[machine_info time] >= $::wk_deadline} {
        wk_finish "FAIL $label geometry did not change"
    } else {
        after time 0.1 [list wk_wait_changed $before $callback $label]
    }
}

proc wk_check_final {} {
    set moved $::wk_moved
    set sized $::wk_sized
    if {[llength $moved] != 4 || [llength $sized] != 4 ||
        [lindex $moved 0] <= [lindex $::wk_initial 0] ||
        [lindex $moved 1] >= [lindex $::wk_initial 1] ||
        [lindex $sized 0] != [lindex $moved 0] ||
        [lindex $sized 1] != [lindex $moved 1] ||
        [lindex $sized 2] <= [lindex $moved 2] ||
        [lindex $sized 3] <= [lindex $moved 3] ||
        $::wk_moved_messages < 1 || $::wk_sized_messages < 1 ||
        $::wk_maximized_messages < 2} {
        wk_finish "FAIL incomplete window-kind interaction"
        return
    }
    if {!$::wk_screenshots} {
        wk_finish PASS
    } elseif {[catch {screenshot -raw $::wk_screenshot} error]} {
        wk_finish "FAIL screenshot: $error"
    } else {
        wk_finish PASS
    }
}

proc wk_resize_done {} {
    set ::wk_deadline [expr {[machine_info time] + 5.0}]
    wk_resize_wait
}

proc wk_resize_wait {} {
    set current [wk_rect]
    if {[wk_rect_valid $current] && $current ne $::wk_moved} {
        after time 1.0 wk_resize_record
    } elseif {[machine_info time] >= $::wk_deadline} {
        if {$::wk_resize_attempts < 5} {
            after time 0.5 wk_resize_prepare
        } else {
            wk_finish "FAIL resize geometry did not change"
        }
    } else {
        after time 0.1 wk_resize_wait
    }
}

proc wk_resize_record {} {
    set current [wk_rect]
    if {![wk_rect_valid $current]} {
        after time 0.002 wk_resize_record
        return
    }
    set ::wk_sized $current
    after time 2.0 wk_check_final
}

proc wk_resize_release {} {
    catch {keymatrixup 8 0x80}
    catch {keymatrixup 8 0x40}
    after time 0.10 {keymatrixup 8 0x01; after time 1.0 wk_resize_done}
}

proc wk_resize_start {} {
    incr ::wk_resize_attempts
    keymatrixdown 8 0x01
    after time 0.12 {keymatrixdown 8 0x80; keymatrixdown 8 0x40}
    after time 0.65 wk_resize_release
}

proc wk_resize_prepare {} {
    set rect [wk_rect]
    set px [peek 0x1306]
    set py [peek 0x1307]
    if {![wk_rect_valid $rect] || $rect ne $::wk_moved ||
        $px > 127 || $py > 211} {
        if {[machine_info time] >= $::wk_deadline} {
            wk_finish "FAIL resize target never became mapper-safe"
        } else {
            after time 0.002 wk_resize_prepare
        }
        return
    }
    lassign $rect x y w h
    # Stay inside the 6-byte x 14-line friendly grip hit area even with the
    # pointer driver's +/-1 byte, +/-3 line arrival tolerance.
    wk_move_to [expr {$x + $w - 2}] [expr {$y + $h - 4}] wk_resize_start
}

proc wk_move_done {} {
    set ::wk_deadline [expr {[machine_info time] + 5.0}]
    wk_window_move_wait
}

proc wk_window_move_wait {} {
    set current [wk_rect]
    if {[wk_rect_valid $current] && $current ne $::wk_restored} {
        after time 1.0 wk_move_record
    } elseif {[machine_info time] >= $::wk_deadline} {
        if {$::wk_move_attempts < 5} {
            after time 0.5 wk_move_prepare
        } else {
            wk_finish "FAIL move geometry did not change"
        }
    } else {
        after time 0.1 wk_window_move_wait
    }
}

proc wk_move_record {} {
    set current [wk_rect]
    if {![wk_rect_valid $current]} {
        after time 0.002 wk_move_record
        return
    }
    set ::wk_moved $current
    # Geometry is published before the full compositor repaint returns. Leave
    # enough emulated time for that repaint so short steering pulses are not
    # consumed while the root task is still drawing the moved window.
    set ::wk_deadline [expr {[machine_info time] + 30.0}]
    after time 3.0 wk_resize_prepare
}

proc wk_window_release {} {
    catch {keymatrixup 8 0x80}
    catch {keymatrixup 8 0x20}
    after time 0.10 {keymatrixup 8 0x01; after time 1.0 wk_move_done}
}

proc wk_window_move_start {} {
    incr ::wk_move_attempts
    keymatrixdown 8 0x01
    after time 0.12 {keymatrixdown 8 0x80; keymatrixdown 8 0x20}
    after time 0.45 wk_window_release
}

proc wk_move_prepare {} {
    set rect [wk_rect]
    set px [peek 0x1306]
    set py [peek 0x1307]
    if {![wk_rect_valid $rect] || $rect ne $::wk_restored ||
        $px > 127 || $py > 211} {
        if {[machine_info time] >= $::wk_deadline} {
            wk_finish "FAIL move target never became mapper-safe"
        } else {
            after time 0.002 wk_move_prepare
        }
        return
    }
    lassign $rect x y w h
    wk_move_to [expr {$x + 20}] [expr {$y + 6}] wk_window_move_start
}

proc wk_restore_check {} {
    set ::wk_restored [wk_rect]
    if {$::wk_restored ne $::wk_initial} {
        wk_finish "FAIL restore geometry: $::wk_restored"
    } else {
        set ::wk_deadline [expr {[machine_info time] + 30.0}]
        after time 1.0 wk_move_prepare
    }
}

proc wk_restore_click {} {
    set ::wk_deadline [expr {[machine_info time] + 15.0}]
    wk_click {wk_wait_rect $::wk_initial wk_restore_check restore}
}

proc wk_max_check {} {
    set ::wk_maximized [wk_rect]
    if {$::wk_maximized ne {0 8 128 204}} {
        wk_finish "FAIL maximize geometry: $::wk_maximized"
    } else {
        wk_move_to 126 14 wk_restore_click
    }
}

proc wk_max_click {} {
    set ::wk_deadline [expr {[machine_info time] + 15.0}]
    wk_click {wk_wait_rect {0 8 128 204} wk_max_check maximize}
}

proc wk_start_interaction {} {
    set rect [wk_rect]
    set x [peek 0x1306]
    set y [peek 0x1307]
    if {![wk_rect_valid $rect] || $x > 127 || $y > 211} {
        if {[machine_info time] >= $::wk_deadline} {
            wk_finish "FAIL interaction start never became mapper-safe"
        } else {
            after time 0.002 wk_start_interaction
        }
        return
    }
    set ::wk_initial $rect
    lassign $::wk_initial x y w h
    wk_move_to [expr {$x + $w - 2}] [expr {$y + 6}] wk_max_click
}

proc wk_filemgr_ready {} {
    if {[peek 0x1350] >= 2 && [peek 0x144A] == 56 && [peek 0x144B] == 158} {
        if {!$::wk_registered} {
            set ::wk_registered 1
            set ::wk_page0_slot [expr {[debug read ioports 0xA8] & 3}]
            debug set_bp $::wk_fm_proc {} {wk_proc_break}
        }
        if {$::wk_list_ready && !$::wk_started} {
            set ::wk_started 1
            # Let the post-list application-icon probes finish before driving
            # pointer gestures; they temporarily switch mapper/BIOS slots.
            set ::wk_deadline [expr {[machine_info time] + 30.0}]
            after time 10.0 wk_start_interaction
        } elseif {[machine_info time] >= $::wk_deadline} {
            wk_finish "FAIL File Manager list did not become ready"
        } else {
            after time 0.1 wk_filemgr_ready
        }
    } elseif {[machine_info time] >= $::wk_deadline} {
        wk_finish "FAIL File Manager did not register: [wk_rect]"
    } else {
        after time 0.1 wk_filemgr_ready
    }
}

proc wk_open_drive {} {
    set ::wk_deadline [expr {[machine_info time] + 20.0}]
    wk_double_click wk_filemgr_ready
}

after time 62.0 {wk_move_to 4 40 wk_open_drive}
