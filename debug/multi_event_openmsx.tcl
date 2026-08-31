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
set me_clock_worker [me_env_addr GEMBENCH_EVENT_CLOCK_WORKER]
set me_after_collect [me_env_addr GEMBENCH_EVENT_AFTER_COLLECT]
set me_main [me_env_addr GEMBENCH_EVENT_MAIN]
set me_sig0 [me_env_addr GEMBENCH_EVENT_SIG0]
set me_sig1 [me_env_addr GEMBENCH_EVENT_SIG1]
set me_sig2 [me_env_addr GEMBENCH_EVENT_SIG2]
set me_show_sec [me_env_addr GEMBENCH_EVENT_SHOW_SEC]
set me_timer_part [me_env_addr GEMBENCH_EVENT_TIMER_PART]
set me_timer_digit_due [me_env_addr GEMBENCH_EVENT_TIMER_DIGIT_DUE]
set me_timer_window [me_env_addr GEMBENCH_EVENT_TIMER_WINDOW]
set me_subscription [me_env_addr GEMBENCH_EVENT_SUBSCRIPTION]
set me_event [me_env_addr GEMBENCH_EVENT_RECORD]
set me_timer_collect [me_env_addr GEMBENCH_EVENT_TIMER_COLLECT]
set me_k_poll [me_env_addr GEMBENCH_EVENT_K_POLL]
set me_paintlock [me_env_addr GEMBENCH_EVENT_PAINTLOCK]
set me_fm_total [me_env_addr GEMBENCH_EVENT_FM_TOTAL]
set me_fm_names [me_env_addr GEMBENCH_EVENT_FM_NAMES]
set me_fm_order [me_env_addr GEMBENCH_EVENT_FM_ORDER]
set me_fm_list_state [me_env_addr GEMBENCH_EVENT_FM_LIST_STATE]
set me_fm_view [me_env_addr GEMBENCH_EVENT_FM_VIEW]
set me_deadline 0
set me_target_x 0
set me_target_y 0
set me_callback ""
set me_draw_hits 0
set me_main_hits 0
set me_app_index -1
set me_app_target {}
set me_filemgr_slot -1
set me_clock_slot -1
set me_frame_hits 0
set me_worker_hits 0
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
set me_bg_draw_start 0
set me_bg_frame_start 0
set me_bg_draw_delta 0
set me_bg_frame_delta 0
set me_bg_hash_start 0
set me_bg_hash_final 0
set me_bg_hash_rect {}
set me_bg_damage_hits 0
set me_bg_damage_rect {}
set me_bg_damage_rects {}
set me_bg_expected_damage {}
set me_bg_client_rect {}
set me_bg_timer_parts {}
set me_bg_digit_due {}
set me_bg_timer_windows {}
set me_bg_active_owners {}
set me_bg_validation {}
set me_bg_pointer_parked 0
set me_bg_recording 0
set me_hidden_worker_start 0
set me_hidden_draw_start 0
set me_hidden_damage_start 0
set me_hidden_hash_start 0
set me_hidden_hash_final 0
set me_hidden_pixels {}
set me_hidden_diff {}
set me_hidden_rect {}
set me_hidden_worker_delta -1
set me_hidden_draw_delta -1
set me_hidden_damage_delta -1
set me_poll_events {}
set me_poll_bp ""

proc me_is_loaded {} {
    expr {[peek $::me_main] == $::me_sig0 &&
          [peek [expr {$::me_main + 1}]] == $::me_sig1 &&
          [peek [expr {$::me_main + 2}]] == $::me_sig2}
}

# Timed callbacks can land while the BIOS has ROM mapped over low RAM. Queue
# state-sensitive work for the public poll entry, where the kernel mapping and
# window/application tables are stable.
proc me_poll_after {delay callback} {
    after time $delay [list me_poll_arm $callback]
}

proc me_poll_arm {callback} {
    lappend ::me_poll_events $callback
    if {$::me_poll_bp eq ""} {
        set ::me_poll_bp [debug set_bp $::me_k_poll {} {me_poll_tick}]
    }
}

proc me_poll_tick {} {
    if {$::me_poll_bp ne ""} {
        debug remove_bp $::me_poll_bp
        set ::me_poll_bp ""
    }
    set callbacks $::me_poll_events
    set ::me_poll_events {}
    foreach callback $callbacks {uplevel #0 $callback}
    set ::pause off
}

proc me_entry {slot} { expr {0x1352 + 25 * $slot} }

proc me_rect {slot} {
    set entry [me_entry $slot]
    list [peek [expr {$entry + 1}]] [peek [expr {$entry + 2}]] \
         [peek [expr {$entry + 3}]] [peek [expr {$entry + 4}]]
}

# The release image boots Screen 7: two VRAM bytes per logical byte-column in
# each 256-byte scanline. Hash a foreground-owned overlap to prove Clock's
# clipped background repaint cannot punch through the raised File Manager.
proc me_vram_hash {x y w h} {
    set hash 2166136261
    for {set row 0} {$row < $h} {incr row} {
        for {set col 0} {$col < $w} {incr col} {
            set address [expr {($y + $row) * 256 + ($x + $col) * 2}]
            foreach offset {0 1} {
                set value [debug read VRAM [expr {$address + $offset}]]
                set hash [expr {(($hash ^ $value) * 16777619) & 0xFFFFFFFF}]
            }
        }
    }
    return $hash
}

proc me_vram_pixels {x y w h} {
    set pixels {}
    for {set row 0} {$row < $h} {incr row} {
        for {set col 0} {$col < $w} {incr col} {
            set address [expr {($y + $row) * 256 + ($x + $col) * 2}]
            lappend pixels [debug read VRAM $address]
            lappend pixels [debug read VRAM [expr {$address + 1}]]
        }
    }
    return $pixels
}

proc me_vram_diff {before x y w h} {
    set after [me_vram_pixels $x $y $w $h]
    set diff {}
    set count [llength $after]
    for {set i 0} {$i < $count} {incr i} {
        set old [lindex $before $i]
        set new [lindex $after $i]
        if {$old != $new} {
            set pixel [expr {$i / 2}]
            lappend diff [list [expr {$x + ($pixel % $w)}] \
                                    [expr {$y + ($pixel / $w)}] \
                                    [expr {$i & 1}] $old $new]
            if {[llength $diff] >= 32} {break}
        }
    }
    return $diff
}

proc me_filemgr_mapped {} {
    set focus [peek 0x1351]
    expr {$focus < 8 && [peek 0x134F] == [peek [me_entry $focus]]}
}

proc me_filemgr_app_index {} {
    for {set i 0} {$i < [peek $::me_fm_total]} {incr i} {
        set raw [peek [expr {$::me_fm_order + $i}]]
        set base [expr {$::me_fm_names + $raw * 11}]
        set expected {65 32 32 32 32 32 32 32 65 80 80}
        set match 1
        for {set j 0} {$j < 11} {incr j} {
            if {[peek [expr {$base + $j}]] != [lindex $expected $j]} {
                set match 0
                break
            }
        }
        if {$match} {return $i}
    }
    return -1
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
    catch {screenshot -raw $::me_output.png}
    set handle [open $::me_output w]
    puts $handle "STATUS=$status"
    puts $handle "DRAW_HITS=$::me_draw_hits"
    puts $handle "MAIN_HITS=$::me_main_hits"
    puts $handle "APP_INDEX=$::me_app_index"
    puts $handle "APP_TARGET=$::me_app_target"
    puts $handle "FILEMGR_SLOT=$::me_filemgr_slot"
    if {$::me_filemgr_slot >= 0} {puts $handle "FILEMGR_RECT=[me_rect $::me_filemgr_slot]"}
    puts $handle "CLOCK_SLOT=$::me_clock_slot"
    puts $handle "TIMER_HITS=$::me_frame_hits"
    puts $handle "WORKER_HITS=$::me_worker_hits"
    puts $handle "POINTER_CLICK_HITS=$::me_click_hits"
    puts $handle "POINTER_WINDOW_HITS=$::me_pointer_window_hits"
    puts $handle "KEY_HITS=$::me_key_hits"
    puts $handle "LAST_KEY=$::me_last_key"
    puts $handle "SHOW_SECONDS=$::me_show_value"
    puts $handle "EVENT_CLASSES=$::me_classes_value"
    puts $handle "POINTER_SEEN=$::me_pointer_seen_value"
    puts $handle "POINTER_LAST=$::me_pointer_x_value,$::me_pointer_y_value"
    puts $handle "BACKGROUND_DRAW_DELTA=$::me_bg_draw_delta"
    puts $handle "BACKGROUND_FRAME_DELTA=$::me_bg_frame_delta"
    puts $handle "BACKGROUND_HASH_RECT=$::me_bg_hash_rect"
    puts $handle "BACKGROUND_HASH=$::me_bg_hash_start,$::me_bg_hash_final"
    puts $handle "BACKGROUND_DAMAGE_HITS=$::me_bg_damage_hits"
    puts $handle "BACKGROUND_DAMAGE_RECT=$::me_bg_damage_rect"
    puts $handle "BACKGROUND_DAMAGE_RECTS=$::me_bg_damage_rects"
    puts $handle "BACKGROUND_EXPECTED_DAMAGE=$::me_bg_expected_damage"
    puts $handle "BACKGROUND_CLIENT_RECT=$::me_bg_client_rect"
    puts $handle "BACKGROUND_TIMER_PARTS=$::me_bg_timer_parts"
    puts $handle "BACKGROUND_DIGIT_DUE=$::me_bg_digit_due"
    puts $handle "BACKGROUND_TIMER_WINDOWS=$::me_bg_timer_windows"
    puts $handle "BACKGROUND_ACTIVE_OWNERS=$::me_bg_active_owners"
    puts $handle "BACKGROUND_VALIDATION=$::me_bg_validation"
    puts $handle "BACKGROUND_POINTER_PARKED=$::me_bg_pointer_parked"
    puts $handle "HIDDEN_WORKER_DELTA=$::me_hidden_worker_delta"
    puts $handle "HIDDEN_DRAW_DELTA=$::me_hidden_draw_delta"
    puts $handle "HIDDEN_DAMAGE_DELTA=$::me_hidden_damage_delta"
    puts $handle "HIDDEN_HASH_RECT=$::me_hidden_rect"
    puts $handle "HIDDEN_HASH=$::me_hidden_hash_start,$::me_hidden_hash_final"
    puts $handle "HIDDEN_DIFF=$::me_hidden_diff"
    puts $handle "LIVE_WINDOWS=[peek 0x1350]"
    puts $handle "FOCUS=[peek 0x1351]"
    puts $handle "RUNNABLE=[peek 0x1344]"
    puts $handle "TIMER_OWNER=[peek 0xC3CA]"
    puts $handle "TIMER_GENERATION=[peek 0xC3CF]"
    puts $handle "BANK_CUR=[peek 0x134F]"
    puts $handle "FINAL_POINTER=[peek 0x1306],[peek 0x1307]"
    puts $handle [format "FINAL_PC=%04X" [reg PC]]
    puts $handle [format "FINAL_SP=%04X" [reg SP]]
    set surface_visibility {}
    set task_visibility {}
    for {set i 0} {$i < 8} {incr i} {
        lappend surface_visibility [peek [expr {0xC1C0 + $i}]]
        lappend task_visibility [peek [expr {0xC1C8 + $i}]]
    }
    puts $handle "SURFACE_VISIBILITY=$surface_visibility"
    puts $handle "TASK_VISIBILITY=$task_visibility"
    set region_state {}
    for {set address 0xC1D0} {$address <= 0xC1DF} {incr address} {
        lappend region_state [peek $address]
    }
    puts $handle "REGION_STATE=$region_state"
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
    after time 0.16 [list me_double_second_up $callback]
}

proc me_double_first_up {callback} {
    keymatrixup 8 0x01
    after time 0.20 [list me_double_second $callback]
}

proc me_double_click {callback} {
    keymatrixdown 8 0x01
    after time 0.16 [list me_double_first_up $callback]
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
        me_background_begin
    }
}

proc me_background_check {} {
    set bad_damage 0
    set ::me_bg_draw_delta [expr {$::me_draw_hits - $::me_bg_draw_start}]
    set ::me_bg_frame_delta [expr {$::me_frame_hits - $::me_bg_frame_start}]
    lassign $::me_bg_client_rect client_x client_y client_w client_h
    foreach rect $::me_bg_damage_rects {
        lassign $rect x y w h
        if {$w <= 0 || $h <= 0 || $x < $client_x || $y < $client_y ||
            $x + $w > $client_x + $client_w ||
            $y + $h > $client_y + $client_h ||
            ($w == $client_w && $h == $client_h)} {
            set bad_damage 1
        }
    }
    lassign $::me_bg_hash_rect x y w h
    set ::me_bg_hash_final [me_vram_hash $x $y $w $h]
    if {[peek 0x1351] != $::me_filemgr_slot} {
        me_finish "FAIL background timer changed focus"
    } elseif {$::me_bg_frame_delta != 0} {
        me_finish "FAIL unfocused Clock received focused frames"
    } elseif {$::me_bg_draw_delta != 0} {
        me_finish "FAIL occluded Clock component repainted"
    } elseif {$::me_bg_damage_hits < 2 ||
              [lsearch -exact $::me_bg_damage_rects $::me_bg_expected_damage] < 0} {
        me_finish "FAIL timer did not isolate the seconds digits"
    } elseif {$bad_damage} {
        me_finish "FAIL timer damage escaped its changed content"
    } elseif {[llength $::me_bg_active_owners] != 0} {
        me_finish "FAIL occluded component entered a draw callback"
    } elseif {$::me_bg_pointer_parked} {
        me_finish "FAIL timer repaint parked the hardware pointer"
    } elseif {$::me_bg_hash_final != $::me_bg_hash_start} {
        me_finish "FAIL background repaint damaged foreground"
    } else {
        me_hidden_begin
    }
}

# Maximise File Manager over Clock, then prove both paint and worker execution
# stop for the fully occluded application. Restoring File Manager must expose a
# current-time Clock through the ordinary compositor without replaying ticks.
proc me_hidden_begin {} {
    set ::me_bg_recording 0
    lassign [me_rect $::me_filemgr_slot] x y w h
    set ::me_deadline [expr {[machine_info time] + 10.0}]
    me_move_to [expr {$x + $w - 2}] [expr {$y + 4}] me_hidden_max_click
}

proc me_hidden_max_click {} {
    me_click me_hidden_wait
}

proc me_hidden_wait {} {
    set rect [me_rect $::me_filemgr_slot]
    if {$rect eq {0 8 128 204} && [peek $::me_paintlock] == 0 &&
        [peek [expr {0xC1C0 + $::me_clock_slot}]] == 0 &&
        [peek [expr {0xC1C8 + $::me_clock_slot}]] == 0 && [peek 0xC3CA] == 0} {
        set ::me_hidden_rect [me_rect $::me_clock_slot]
        lassign $::me_hidden_rect x y w h
        set ::me_hidden_hash_start [me_vram_hash $x $y $w $h]
        set ::me_hidden_pixels [me_vram_pixels $x $y $w $h]
        set ::me_hidden_worker_start $::me_worker_hits
        set ::me_hidden_draw_start $::me_draw_hits
        set ::me_hidden_damage_start $::me_bg_damage_hits
        after time 3.0 me_hidden_check
    } elseif {[machine_info time] >= $::me_deadline} {
        me_finish "FAIL Clock did not become fully occluded"
    } else {
        after time 0.1 me_hidden_wait
    }
}

proc me_hidden_check {} {
    lassign $::me_hidden_rect x y w h
    set ::me_hidden_hash_final [me_vram_hash $x $y $w $h]
    set ::me_hidden_diff [me_vram_diff $::me_hidden_pixels $x $y $w $h]
    set ::me_hidden_worker_delta [expr {$::me_worker_hits - $::me_hidden_worker_start}]
    set ::me_hidden_draw_delta [expr {$::me_draw_hits - $::me_hidden_draw_start}]
    set ::me_hidden_damage_delta [expr {$::me_bg_damage_hits - $::me_hidden_damage_start}]
    if {$::me_hidden_worker_delta != 0} {
        me_finish "FAIL fully occluded Clock received worker CPU"
    } elseif {$::me_hidden_draw_delta != 0 || $::me_hidden_damage_delta != 0} {
        me_finish "FAIL fully occluded Clock generated paint work"
    } elseif {$::me_hidden_hash_final != $::me_hidden_hash_start} {
        me_finish "FAIL hidden Clock disturbed foreground pixels"
    } else {
        set ::me_deadline [expr {[machine_info time] + 10.0}]
        me_move_to 126 12 me_hidden_restore_click
    }
}

proc me_hidden_restore_click {} {
    me_click me_hidden_restore_wait
}

proc me_hidden_restore_wait {} {
    if {[me_rect $::me_filemgr_slot] ne {0 8 128 204} &&
        [peek [expr {0xC1C0 + $::me_clock_slot}]] != 0 &&
        $::me_draw_hits > $::me_hidden_draw_start} {
        me_finish PASS
    } elseif {[machine_info time] >= $::me_deadline} {
        me_finish "FAIL exposed Clock did not repaint current state"
    } else {
        after time 0.1 me_hidden_restore_wait
    }
}

proc me_background_focused {} {
    if {[peek 0x1351] != $::me_filemgr_slot ||
        [peek $::me_paintlock] != 0 || ![me_filemgr_mapped]} {
        if {[machine_info time] >= $::me_deadline} {
            me_finish "FAIL File Manager focus repaint did not complete"
        } else {
            after time 0.1 me_background_focused
        }
        return
    }
    lassign [me_rect $::me_filemgr_slot] fx fy fw fh
    lassign [me_rect $::me_clock_slot] cx cy cw ch
    set left [expr {$fx > $cx ? $fx : $cx}]
    set top [expr {$fy > $cy ? $fy : $cy}]
    set right [expr {$fx + $fw < $cx + $cw ? $fx + $fw : $cx + $cw}]
    set bottom [expr {$fy + $fh < $cy + $ch ? $fy + $fh : $cy + $ch}]
    set iw [expr {$right - $left}]
    set ih [expr {$bottom - $top}]
    set w [expr {$iw < 16 ? $iw : 16}]
    set h [expr {$ih < 48 ? $ih : 48}]
    if {$w <= 0 || $h <= 0} {
        me_finish "FAIL Clock and File Manager do not overlap"
        return
    }
    set ::me_bg_hash_rect [list $left $top $w $h]
    set ::me_bg_expected_damage [list \
        [expr {$cx + ($cw - 12) / 2 + 9}] \
        [expr {$cy + $ch - 16}] 3 8]
    set ::me_bg_client_rect [list \
        [expr {$cx + 1}] [expr {$cy + 14}] \
        [expr {$cw - 2}] [expr {$ch - 15}]]
    set ::me_bg_damage_hits 0
    set ::me_bg_damage_rect {}
    set ::me_bg_damage_rects {}
    set ::me_bg_timer_parts {}
    set ::me_bg_digit_due {}
    set ::me_bg_timer_windows {}
    set ::me_bg_active_owners {}
    set ::me_bg_validation {}
    set ::me_bg_pointer_parked 0
    set ::me_bg_recording 1
    set ::me_bg_hash_start [me_vram_hash $left $top $w $h]
    set ::me_bg_draw_start $::me_draw_hits
    set ::me_bg_frame_start $::me_frame_hits
    me_poll_after 4.2 me_background_check
}

proc me_background_click {} {
    set ::me_deadline [expr {[machine_info time] + 10.0}]
    me_click me_background_focused
}

proc me_background_begin {} {
    lassign [me_rect $::me_filemgr_slot] x y w h
    # File Manager extends below the default Clock. Activate that exposed,
    # otherwise empty content strip so it becomes the static foreground layer.
    me_move_to [expr {$x + 2}] [expr {$y + $h - 6}] me_background_click
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
    debug set_bp $::me_main {} {
        incr ::me_main_hits
        set ::pause off
    }
    debug set_bp $::me_c_draw {} {
        if {[me_is_loaded]} {
            incr ::me_draw_hits
            me_capture_state
            if {$::me_bg_recording && ([peek 0xC3CA] & 0x80)} {
                lappend ::me_bg_timer_parts [peek $::me_timer_part]
                lappend ::me_bg_digit_due [peek $::me_timer_digit_due]
                lappend ::me_bg_timer_windows [peek $::me_timer_window]
                lappend ::me_bg_active_owners [peek 0xC3CA]
                if {[debug read VRAM 0xFA00] == 217} {
                    set ::me_bg_pointer_parked 1
                }
            }
        }
        set ::pause off
    }
    debug set_bp $::me_c_frame {} {
        if {[me_is_loaded]} {
            incr ::me_frame_hits
            me_capture_state
            set slot [peek 0x1351]
            if {$slot < 8} {set ::me_clock_slot $slot}
        }
        set ::pause off
    }
    debug set_bp $::me_clock_worker {} {
        if {[me_is_loaded]} {incr ::me_worker_hits}
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
    set ::me_deadline [expr {[machine_info time] + 30.0}]
    me_double_click me_filemgr_ready
}

proc me_filemgr_ready {} {
    if {[peek 0x1350] == 2 && [peek 0x1351] == 1 &&
        [me_filemgr_mapped] && [peek $::me_fm_list_state] == 0} {
        set ::me_filemgr_slot [peek 0x1351]
        set index [me_filemgr_app_index]
        if {$index >= 0} {
            set ::me_app_index $index
            set x [peek 0x1448]
            set y [peek 0x1449]
            if {[peek $::me_fm_view] == 1} {
                set cell_w [expr {([peek 0x144A] - 5) / 3}]
                set target_x [expr {$x + 4 + ($index % 3) * $cell_w + $cell_w / 2}]
                set target_y [expr {$y + 14 + ($index / 3) * 44 + 16}]
            } else {
                set target_x [expr {$x + 12}]
                set target_y [expr {$y + 14 + $index * 18 + 8}]
            }
            set ::me_app_target [list $target_x $target_y]
            me_move_to $target_x $target_y me_launch_clock
            return
        }
    }
    if {[machine_info time] >= $::me_deadline} {
        me_finish "FAIL staged A.APP was not listed"
    } else {
        after time 0.05 me_filemgr_ready
    }
}

# The generated Nextor image reaches the desktop after roughly 50 emulated seconds.
debug set_bp $me_timer_collect {} {
    if {$::me_bg_recording && [peek 0xC3CA] != 0 && !([peek 0xC3CA] & 0x80)} {
        incr ::me_bg_damage_hits
        set ::me_bg_damage_rect [list \
            [peek 0xC3CB] [peek 0xC3CC] [peek 0xC3CD] [peek 0xC3CE]]
        lappend ::me_bg_damage_rects $::me_bg_damage_rect
        set owner [peek 0xC3CA]
        set slot [expr {$owner - 1}]
        lappend ::me_bg_validation [list \
            [peek 0xC3CF] [peek [expr {0xC358 + $slot}]] \
            [peek [expr {0xC2D0 + $slot}]] [peek [expr {0xC1C0 + $slot}]] \
            [peek 0x130A]]
    }
    set ::pause off
}
after time 62.0 {me_move_to 4 40 me_open_drive}
