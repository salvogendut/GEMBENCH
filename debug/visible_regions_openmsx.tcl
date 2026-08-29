# Validate the MSX2 Desktop's bounded visible-region repaint path. The test
# launches File Manager and Clock, tops and moves File Manager, then closes both.

set throttle off
set pause_on_lost_focus false
set pause off

proc vr_env_addr {name} { expr {$::env($name) + 0} }

set vr_output $::env(GEMBENCH_REGION_OUTPUT)
set vr_screen_dir $::env(GEMBENCH_REGION_SCREEN_DIR)
set vr_screenshots [expr {$::env(GEMBENCH_REGION_SCREENSHOTS) + 0}]
set vr_main [vr_env_addr GEMBENCH_REGION_MAIN]
set vr_sig0 [vr_env_addr GEMBENCH_REGION_SIG0]
set vr_sig1 [vr_env_addr GEMBENCH_REGION_SIG1]
set vr_sig2 [vr_env_addr GEMBENCH_REGION_SIG2]
set vr_paint_visible [vr_env_addr GEMBENCH_REGION_PAINT_VISIBLE]
set vr_paint_return [vr_env_addr GEMBENCH_REGION_PAINT_RETURN]
set vr_begin [vr_env_addr GEMBENCH_REGION_BEGIN]
set vr_after_begin [vr_env_addr GEMBENCH_REGION_AFTER_BEGIN]
set vr_state [vr_env_addr GEMBENCH_REGION_STATE]
set vr_rect_copy [vr_env_addr GEMBENCH_REGION_RECT_COPY]
set vr_rect_intersect [vr_env_addr GEMBENCH_REGION_RECT_INTERSECT]
set vr_emit [vr_env_addr GEMBENCH_REGION_EMIT]
set vr_subtract [vr_env_addr GEMBENCH_REGION_SUBTRACT]

set vr_deadline 0
# File Manager's post-list icon probes and the asynchronous V9938 command
# engine can outlive the Desktop callback by many seconds. Evidence is captured
# only after this conservative emulated-time drain.
set vr_settle 40.0
set vr_target_x 0
set vr_target_y 0
set vr_callback ""
set vr_page0_slot -1
set vr_fm_slot -1
set vr_clock_slot -1
set vr_initial_fm {}
set vr_moved_fm {}
set vr_topped 0
set vr_closed_fm 0
set vr_closed_clock 0
set vr_begin_active 0
set vr_begin_start 0
set vr_begin_sp 0
set vr_stack_bytes 0
set vr_begin_hits 0
set vr_raw_begin_hits 0
set vr_raw_paint_hits 0
set vr_optimized_passes 0
set vr_fallback_passes 0
set vr_empty_passes 0
set vr_single_optimized 0
set vr_saved_max 0
set vr_visible_min 65535
set vr_begin_ms_max 0.0
set vr_paint_active 0
set vr_paint_start 0
set vr_paint_ms_max 0.0
set vr_paint_completions 0
set vr_expected_paints 0
set vr_pass_log {}

proc vr_is_desktop {} {
    expr {[peek $::vr_main] == $::vr_sig0 &&
          [peek [expr {$::vr_main + 1}]] == $::vr_sig1 &&
          [peek [expr {$::vr_main + 2}]] == $::vr_sig2}
}

proc vr_release_all {} {
    foreach mask {0x01 0x10 0x20 0x40 0x80} {
        catch {keymatrixup 8 $mask}
    }
}

proc vr_lowram_ready {} {
    if {$::vr_page0_slot < 0 ||
        [expr {[debug read ioports 0xA8] & 3}] != $::vr_page0_slot} {
        return 0
    }
    set nwin [peek 0x1350]
    set repaint [expr {[peek 0x1359] + 256 * [peek 0x135A]}]
    expr {$nwin >= 1 && $nwin <= 8 && $repaint == $::vr_paint_visible}
}

proc vr_rect_valid {rect} {
    lassign $rect x y w h
    expr {[llength $rect] == 4 && $x >= 0 && $x < 128 &&
          $y >= 0 && $y < 212 && $w > 0 && $h > 0 &&
          $x + $w <= 128 && $y + $h <= 212}
}

proc vr_slot_rect {slot} {
    set p [expr {0x1352 + 25 * $slot + 1}]
    list [peek $p] [peek [expr {$p + 1}]] \
         [peek [expr {$p + 2}]] [peek [expr {$p + 3}]]
}

proc vr_capture {name} {
    if {!$::vr_screenshots} return
    if {[catch {screenshot -raw "$::vr_screen_dir/$name.png"} error]} {
        vr_finish "FAIL screenshot $name: $error"
    }
}

proc vr_finish {status} {
    vr_release_all
    set handle [open $::vr_output w]
    puts $handle "STATUS=$status"
    puts $handle "BEGIN_HITS=$::vr_begin_hits"
    puts $handle "RAW_BEGIN_HITS=$::vr_raw_begin_hits"
    puts $handle "RAW_PAINT_HITS=$::vr_raw_paint_hits"
    puts $handle "OPTIMIZED_PASSES=$::vr_optimized_passes"
    puts $handle "FALLBACK_PASSES=$::vr_fallback_passes"
    puts $handle "EMPTY_PASSES=$::vr_empty_passes"
    puts $handle "SINGLE_WINDOW_OPTIMIZED=$::vr_single_optimized"
    puts $handle "MAX_SAVED_AREA=$::vr_saved_max"
    puts $handle "MIN_VISIBLE_AREA=$::vr_visible_min"
    puts $handle [format "BEGIN_MAX_MS=%.3f" $::vr_begin_ms_max]
    puts $handle [format "PAINT_MAX_MS=%.3f" $::vr_paint_ms_max]
    puts $handle "PAINT_COMPLETIONS=$::vr_paint_completions"
    puts $handle "PASS_LOG=$::vr_pass_log"
    puts $handle "STACK_BYTES=$::vr_stack_bytes"
    puts $handle "INITIAL_FILEMGR=$::vr_initial_fm"
    puts $handle "MOVED_FILEMGR=$::vr_moved_fm"
    puts $handle "TOPPED=$::vr_topped"
    puts $handle "CLOSED_FILEMGR=$::vr_closed_fm"
    puts $handle "CLOSED_CLOCK=$::vr_closed_clock"
    puts $handle "FINAL_NWIN=[peek 0x1350]"
    puts $handle [format "DESKTOP_REPAINT=%02X%02X" [peek 0x135A] [peek 0x1359]]
    puts $handle [format "CURRENT_BANK=%02X" [peek 0x134F]]
    puts $handle [format "FINAL_PC=%04X" [reg PC]]
    puts $handle [format "FINAL_SP=%04X" [reg SP]]
    close $handle
    exit
}

proc vr_stack_sample {extra} {
    if {!$::vr_begin_active || ![vr_is_desktop]} return
    set depth [expr {$::vr_begin_sp - [reg SP] + $extra}]
    if {$depth > $::vr_stack_bytes} { set ::vr_stack_bytes $depth }
}

proc vr_begin_enter {} {
    incr ::vr_raw_begin_hits
    if {[vr_is_desktop]} {
        set ::vr_begin_active 1
        set ::vr_begin_start [machine_info time]
        set ::vr_begin_sp [reg SP]
        incr ::vr_begin_hits
    }
    set ::pause off
}

proc vr_begin_return {} {
    if {$::vr_begin_active && [vr_is_desktop]} {
        set elapsed [expr {1000.0 * ([machine_info time] - $::vr_begin_start)}]
        if {$elapsed > $::vr_begin_ms_max} { set ::vr_begin_ms_max $elapsed }
        set count [peek [expr {$::vr_state + 36}]]
        set overflow [peek [expr {$::vr_state + 38}]]
        set active [peek [expr {$::vr_state + 39}]]
        set pass_visible 0
        if {!$active || !$count} {
            incr ::vr_empty_passes
        } elseif {$overflow} {
            incr ::vr_fallback_passes
        } else {
            set visible 0
            for {set i 0} {$i < $count} {incr i} {
                set p [expr {$::vr_state + 4 * $i}]
                incr visible [expr {[peek [expr {$p + 2}]] * [peek [expr {$p + 3}]]}]
            }
            set pass_visible $visible
            set dx [peek [expr {$::vr_state + 32}]]
            set dy [peek [expr {$::vr_state + 33}]]
            set dw [peek [expr {$::vr_state + 34}]]
            set dh [peek [expr {$::vr_state + 35}]]
            set desktop [vr_slot_rect 0]
            lassign $desktop wx wy ww wh
            set left [expr {max($dx, $wx)}]
            set top [expr {max($dy, $wy)}]
            set right [expr {min($dx + $dw, $wx + $ww)}]
            set bottom [expr {min($dy + $dh, $wy + $wh)}]
            set base_area [expr {max(0, $right - $left) * max(0, $bottom - $top)}]
            set saved [expr {$base_area - $visible}]
            if {$count > 1 && $saved > 0} {
                incr ::vr_optimized_passes
                if {$saved > $::vr_saved_max} { set ::vr_saved_max $saved }
                if {$visible < $::vr_visible_min} { set ::vr_visible_min $visible }
                if {[peek 0x1350] == 2} { set ::vr_single_optimized 1 }
            }
        }
        lappend ::vr_pass_log [list [peek 0x1350] $count $overflow $active \
            [peek [expr {$::vr_state + 32}]] [peek [expr {$::vr_state + 33}]] \
            [peek [expr {$::vr_state + 34}]] [peek [expr {$::vr_state + 35}]] \
            $pass_visible]
        if {!$active && $::vr_paint_active} {
            # paint_visible will take its immediate zero-return path.
            set paint_elapsed [expr {1000.0 * ([machine_info time] - $::vr_paint_start)}]
            if {$paint_elapsed > $::vr_paint_ms_max} {
                set ::vr_paint_ms_max $paint_elapsed
            }
            incr ::vr_paint_completions
            set ::vr_paint_active 0
        }
    }
    set ::vr_begin_active 0
    set ::pause off
}

proc vr_paint_enter {} {
    incr ::vr_raw_paint_hits
    if {[vr_is_desktop]} {
        set ::vr_paint_active 1
        set ::vr_paint_start [machine_info time]
    }
    set ::pause off
}

proc vr_paint_return {} {
    if {$::vr_paint_active && [vr_is_desktop]} {
        set elapsed [expr {1000.0 * ([machine_info time] - $::vr_paint_start)}]
        if {$elapsed > $::vr_paint_ms_max} { set ::vr_paint_ms_max $elapsed }
        incr ::vr_paint_completions
    }
    set ::vr_paint_active 0
    set ::pause off
}

proc vr_move_tick {} {
    if {$::vr_page0_slot >= 0 &&
        [expr {[debug read ioports 0xA8] & 3}] != $::vr_page0_slot} {
        after time 0.002 vr_move_tick
        return
    }
    set x [peek 0x1306]
    set y [peek 0x1307]
    foreach mask {0x10 0x20 0x40 0x80} { catch {keymatrixup 8 $mask} }
    if {$x > 127 || $y > 211} {
        after time 0.002 vr_move_tick
        return
    }
    if {[expr {abs($x - $::vr_target_x)}] <= 1 &&
        [expr {abs($y - $::vr_target_y)}] <= 3} {
        after time 0.08 $::vr_callback
        return
    }
    if {[machine_info time] >= $::vr_deadline} {
        vr_finish "TIMEOUT moving pointer"
        return
    }
    if {$x < $::vr_target_x - 1} {
        set mask 0x80
    } elseif {$x > $::vr_target_x + 1} {
        set mask 0x10
    } elseif {$y < $::vr_target_y - 3} {
        set mask 0x40
    } else {
        set mask 0x20
    }
    keymatrixdown 8 $mask
    after time 0.08 [list keymatrixup 8 $mask]
    after time 0.16 vr_move_tick
}

proc vr_move_to {x y callback} {
    vr_release_all
    set ::vr_target_x $x
    set ::vr_target_y $y
    set ::vr_callback $callback
    set ::vr_deadline [expr {[machine_info time] + 30.0}]
    vr_move_tick
}

proc vr_click_up {callback} {
    keymatrixup 8 0x01
    after time 1.0 $callback
}
proc vr_click {callback} {
    keymatrixdown 8 0x01
    after time 0.08 [list vr_click_up $callback]
}
proc vr_double_second_up {callback} {
    keymatrixup 8 0x01
    after time 0.10 $callback
}
proc vr_double_second {callback} {
    keymatrixdown 8 0x01
    after time 0.06 [list vr_double_second_up $callback]
}
proc vr_double_first_up {callback} {
    keymatrixup 8 0x01
    after time 0.10 [list vr_double_second $callback]
}
proc vr_double_click {callback} {
    keymatrixdown 8 0x01
    after time 0.06 [list vr_double_first_up $callback]
}

proc vr_final_check {} {
    if {![vr_lowram_ready]} { after time 0.002 vr_final_check; return }
    if {[peek 0x1350] != 1 || !$::vr_closed_fm || !$::vr_closed_clock ||
        !$::vr_topped || $::vr_initial_fm eq $::vr_moved_fm ||
        !$::vr_single_optimized || $::vr_optimized_passes < 1 ||
        $::vr_saved_max <= 0 || $::vr_stack_bytes <= 0} {
        vr_finish "FAIL incomplete visible-region workflow"
    } else {
        vr_capture 05-final-desktop
        vr_finish PASS
    }
}

proc vr_wait_clock_closed {} {
    if {![vr_lowram_ready]} { after time 0.002 vr_wait_clock_closed; return }
    if {[peek 0x1350] == 1 &&
        $::vr_paint_completions >= $::vr_expected_paints} {
        set ::vr_closed_clock 1
        # Window count changes before the compositor has finished erasing the
        # old rectangle. Capture only after that repaint returns.
        after time $::vr_settle vr_final_check
    } elseif {[machine_info time] >= $::vr_deadline} {
        vr_finish "FAIL Clock did not close"
    } else {
        after time 0.1 vr_wait_clock_closed
    }
}

proc vr_close_clock {} {
    if {![vr_lowram_ready]} { after time 0.002 vr_close_clock; return }
    set rect [vr_slot_rect $::vr_clock_slot]
    if {![vr_rect_valid $rect]} { vr_finish "FAIL invalid Clock rectangle"; return }
    lassign $rect x y w h
    set ::vr_expected_paints [expr {$::vr_paint_completions + 1}]
    set ::vr_deadline [expr {[machine_info time] + 15.0}]
    vr_move_to [expr {$x + 2}] [expr {$y + 6}] {vr_click vr_wait_clock_closed}
}

proc vr_wait_fm_closed {} {
    if {![vr_lowram_ready]} { after time 0.002 vr_wait_fm_closed; return }
    if {[peek 0x1350] == 2 &&
        $::vr_paint_completions >= $::vr_expected_paints} {
        set ::vr_closed_fm 1
        after time $::vr_settle vr_fm_closed_settled
    } elseif {[machine_info time] >= $::vr_deadline} {
        vr_finish "FAIL File Manager did not close"
    } else {
        after time 0.1 vr_wait_fm_closed
    }
}

proc vr_fm_closed_settled {} {
    vr_capture 04-filemgr-closed
    vr_close_clock
}

proc vr_close_fm {} {
    if {![vr_lowram_ready]} { after time 0.002 vr_close_fm; return }
    lassign $::vr_moved_fm x y w h
    set ::vr_expected_paints [expr {$::vr_paint_completions + 1}]
    set ::vr_deadline [expr {[machine_info time] + 15.0}]
    vr_move_to [expr {$x + 2}] [expr {$y + 6}] {vr_click vr_wait_fm_closed}
}

proc vr_wait_moved {} {
    if {![vr_lowram_ready]} { after time 0.002 vr_wait_moved; return }
    set rect [vr_slot_rect $::vr_fm_slot]
    if {[vr_rect_valid $rect] && $rect ne $::vr_initial_fm &&
        $::vr_single_optimized &&
        $::vr_paint_completions >= $::vr_expected_paints} {
        set ::vr_moved_fm $rect
        after time $::vr_settle vr_moved_settled
    } elseif {[machine_info time] >= $::vr_deadline} {
        vr_finish "FAIL File Manager did not move"
    } else {
        after time 0.1 vr_wait_moved
    }
}

proc vr_moved_settled {} {
    vr_capture 00-filemgr-moved
    lassign $::vr_moved_fm x y w h
    vr_move_to [expr {$x + 12}] [expr {$y + 78}] vr_launch_clock
}

proc vr_drag_release {} {
    catch {keymatrixup 8 0x80}
    catch {keymatrixup 8 0x20}
    after time 0.10 {keymatrixup 8 0x01; after time 1.0 vr_wait_moved}
}
proc vr_drag_start {} {
    keymatrixdown 8 0x01
    after time 0.12 {keymatrixdown 8 0x80; keymatrixdown 8 0x20}
    after time 0.45 vr_drag_release
}
proc vr_move_fm {} {
    if {![vr_lowram_ready]} { after time 0.002 vr_move_fm; return }
    lassign $::vr_initial_fm x y w h
    set ::vr_expected_paints [expr {$::vr_paint_completions + 1}]
    set ::vr_deadline [expr {[machine_info time] + 15.0}]
    vr_move_to [expr {$x + 20}] [expr {$y + 6}] vr_drag_start
}

proc vr_wait_topped {} {
    if {![vr_lowram_ready]} { after time 0.002 vr_wait_topped; return }
    if {[peek 0x1351] == $::vr_fm_slot} {
        set ::vr_topped 1
        after time $::vr_settle vr_topped_settled
    } elseif {[machine_info time] >= $::vr_deadline} {
        vr_finish "FAIL File Manager did not top"
    } else {
        after time 0.1 vr_wait_topped
    }
}
proc vr_topped_settled {} {
    vr_capture 02-filemgr-topped
    vr_close_fm
}
proc vr_top_fm {} {
    set ::vr_deadline [expr {[machine_info time] + 15.0}]
    lassign $::vr_moved_fm x y w h
    # Use the exposed bottom-left content below Clock's default 142-line edge.
    vr_move_to [expr {$x + 2}] [expr {$y + $h - 8}] \
        {vr_click vr_wait_topped}
}

proc vr_wait_clock {} {
    if {![vr_lowram_ready]} { after time 0.002 vr_wait_clock; return }
    if {[peek 0x1350] >= 3 &&
        $::vr_paint_completions >= $::vr_expected_paints} {
        set ::vr_clock_slot [peek 0x1351]
        after time $::vr_settle vr_clock_settled
    } elseif {[machine_info time] >= $::vr_deadline} {
        vr_finish "FAIL Clock did not register"
    } else {
        after time 0.1 vr_wait_clock
    }
}
proc vr_clock_settled {} {
    vr_capture 01-clock-overlap
    vr_top_fm
}
proc vr_launch_clock {} {
    set ::vr_expected_paints [expr {$::vr_paint_completions + 1}]
    set ::vr_deadline [expr {[machine_info time] + 30.0}]
    vr_double_click vr_wait_clock
}

proc vr_wait_filemgr {} {
    if {![vr_lowram_ready]} { after time 0.002 vr_wait_filemgr; return }
    if {[peek 0x1350] >= 2} {
        set ::vr_fm_slot [peek 0x1351]
        set ::vr_initial_fm [vr_slot_rect $::vr_fm_slot]
        if {![vr_rect_valid $::vr_initial_fm]} {
            vr_finish "FAIL invalid File Manager rectangle"
            return
        }
        set ::vr_page0_slot [expr {[debug read ioports 0xA8] & 3}]
        # The preemptive File Manager deliberately publishes with repaint-top,
        # so its initial open does not redraw Desktop. Let its bounded scan and
        # icon probes settle, then a real title drag supplies the first full
        # compositor pass and the single-window visibility measurement.
        set ::vr_deadline [expr {[machine_info time] + 30.0}]
        after time 8.0 vr_move_fm
    } elseif {[machine_info time] >= $::vr_deadline} {
        vr_finish "FAIL File Manager did not reach optimized repaint"
    } else {
        after time 0.1 vr_wait_filemgr
    }
}
proc vr_open_drive {} {
    set ::vr_deadline [expr {[machine_info time] + 30.0}]
    vr_double_click vr_wait_filemgr
}

proc vr_start {} {
    # Capture the normal low-RAM primary slot only while the permanent Desktop
    # table is readable; BIOS CALSLT briefly maps ROM over these addresses.
    set candidate [expr {[debug read ioports 0xA8] & 3}]
    set repaint [expr {[peek 0x1359] + 256 * [peek 0x135A]}]
    if {[peek 0x1350] != 1 || $repaint != $::vr_paint_visible} {
        after time 0.002 vr_start
        return
    }
    set ::vr_page0_slot $candidate
    vr_move_to 4 40 vr_open_drive
}

debug set_bp $vr_paint_visible {} {vr_paint_enter}
debug set_bp $vr_paint_return {} {vr_paint_return}
debug set_bp $vr_begin {} {vr_begin_enter}
debug set_bp $vr_after_begin {} {vr_begin_return}
debug set_bp $vr_rect_copy {} {vr_stack_sample 4; set ::pause off}
debug set_bp $vr_rect_intersect {} {vr_stack_sample 13; set ::pause off}
debug set_bp $vr_emit {} {vr_stack_sample 4; set ::pause off}
debug set_bp $vr_subtract {} {vr_stack_sample 26; set ::pause off}

after time 62.0 vr_start
