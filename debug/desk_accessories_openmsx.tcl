# Exercise the generated Desk catalog through real keyboard-matrix pointer input.

set throttle off
set pause_on_lost_focus false
set pause off
after time 240 {da_finish "TIMEOUT harness watchdog"}

proc da_env {name} { expr {$::env($name) + 0} }

set da_output $::env(GEMBENCH_ACCESSORY_OUTPUT)
set da_screenshot $::env(GEMBENCH_ACCESSORY_SCREENSHOT)
set da_failure_png [file join [file dirname $da_output] desk-accessories-failure.png]
set da_clock_main [da_env GEMBENCH_ACCESSORY_CLOCK_MAIN]
set da_clock_sig [list [da_env GEMBENCH_ACCESSORY_CLOCK_SIG0] \
                            [da_env GEMBENCH_ACCESSORY_CLOCK_SIG1] \
                            [da_env GEMBENCH_ACCESSORY_CLOCK_SIG2]]
set da_calc_main [da_env GEMBENCH_ACCESSORY_CALC_MAIN]
set da_calc_sig [list [da_env GEMBENCH_ACCESSORY_CALC_SIG0] \
                           [da_env GEMBENCH_ACCESSORY_CALC_SIG1] \
                           [da_env GEMBENCH_ACCESSORY_CALC_SIG2]]
set da_page0_slot -1
set da_deadline 0
set da_target_x 0
set da_target_y 0
set da_callback ""
set da_choice_y 0
set da_choice_callback ""
set da_focus_callback ""
set da_register_hits 0
set da_defer_register_hits 0
set da_find_hits 0
set da_send_hits 0
set da_register_ids {}
set da_find_ids {}
set da_first_clock_slot -1
set da_calc_slot -1
set da_before_close_busy -1
set da_closed_busy -1
set da_final_busy -1
set da_max_nwin 1
set da_final_accessory_ok -1
set da_clock_text_hits 0
set da_calc_text_hits 0
set da_clock_border_ok 0
set da_calc_border_ok 0
set da_clock_menu_ok 0
set da_calc_menu_ok 0

proc da_entry {slot} { expr {0x1352 + 25 * $slot} }

proc da_sig_loaded {address signature} {
    expr {[peek $address] == [lindex $signature 0] &&
          [peek [expr {$address + 1}]] == [lindex $signature 1] &&
          [peek [expr {$address + 2}]] == [lindex $signature 2]}
}

proc da_accessory_ok {slot identity} {
    set entry [da_entry $slot]
    expr {([peek [expr {$entry + 13}]] & 0xE0) == 0xA0 &&
          [peek [expr {$entry + 24}]] == $identity}
}

proc da_busy_count {} {
    set count 0
    for {set i 0} {$i < 8} {incr i} {
        if {[peek [expr {0x1440 + $i}]] != 0} { incr count }
    }
    return $count
}

proc da_menu_clock_ok {} {
    expr {[peek 0x1310] == 2 &&
          [peek 0x1311] == 10 && [peek 0x1312] == 86 &&
          [peek 0x1313] == 105 && [peek 0x1314] == 101 &&
          [peek 0x1315] == 119 && [peek 0x131A] == 17 &&
          [peek 0x131B] == 79 && [peek 0x131C] == 112}
}

proc da_menu_calc_ok {} {
    expr {[peek 0x1310] == 1 &&
          [peek 0x1311] == 10 && [peek 0x1312] == 69 &&
          [peek 0x1313] == 100 && [peek 0x1314] == 105 &&
          [peek 0x1315] == 116}
}

# Release media boots Screen 7: each logical four-pixel column is two native
# VRAM bytes.  Pen 2 is nibble value 2, hence 0x22 on both bytes.  Sampling the
# side and bottom edges catches an app repaint that overwrites WM-owned chrome.
proc da_border_ok {slot} {
    set entry [da_entry $slot]
    set x [peek [expr {$entry + 1}]]
    set y [peek [expr {$entry + 2}]]
    set w [peek [expr {$entry + 3}]]
    set h [peek [expr {$entry + 4}]]
    foreach point [list [list $x [expr {$y + 20}]] \
                         [list [expr {$x + $w - 1}] [expr {$y + 20}]] \
                         [list [expr {$x + 5}] [expr {$y + $h - 1}]]] {
        lassign $point px py
        if {[peek 0xCF05] == 7} {
            set address [expr {$py * 256 + $px * 2}]
            if {[debug read VRAM $address] != 0x22 ||
                [debug read VRAM [expr {$address + 1}]] != 0x22} { return 0 }
        } else {
            if {[debug read VRAM [expr {$py * 128 + $px}]] != 0xAA} { return 0 }
        }
    }
    return 1
}

proc da_lowram_ready {} {
    set n [peek 0x1350]
    if {$n > $::da_max_nwin && $n <= 8} { set ::da_max_nwin $n }
    expr {$::da_page0_slot >= 0 &&
          ([debug read ioports 0xA8] & 3) == $::da_page0_slot &&
          ([reg PC] >= 0x4000 || ([reg PC] >= 0x0400 && [reg PC] < 0x1000)) &&
          $n >= 1 && $n <= 8 && [peek 0x1351] < 8}
}

proc da_release_all {} {
    foreach mask {0x01 0x10 0x20 0x40 0x80} { catch {keymatrixup 8 $mask} }
    catch {type -cancel}
}

proc da_finish {status} {
    if {$status eq "PASS" && [peek 0x1347] != 0} {set status "FAIL scheduler stack fault"}
    da_release_all
    if {$status ne "PASS"} { catch {screenshot -raw $::da_failure_png} }
    set out [open $::da_output w]
    puts $out "STATUS=$status"
    puts $out "REGISTER_HITS=$::da_register_hits"
    puts $out "DEFER_REGISTER_HITS=$::da_defer_register_hits"
    puts $out "REGISTER_IDS=$::da_register_ids"
    puts $out "EXACT_FIND_HITS=$::da_find_hits"
    puts $out "EXACT_FIND_IDS=$::da_find_ids"
    puts $out "SEND_HITS=$::da_send_hits"
    puts $out "FIRST_CLOCK_SLOT=$::da_first_clock_slot"
    puts $out "CALCULATOR_SLOT=$::da_calc_slot"
    puts $out "BEFORE_CLOSE_BUSY_PAGES=$::da_before_close_busy"
    puts $out "CLOSED_BUSY_PAGES=$::da_closed_busy"
    puts $out "FINAL_BUSY_PAGES=$::da_final_busy"
    puts $out "FINAL_ACCESSORY_OK=$::da_final_accessory_ok"
    puts $out "CLOCK_TEXT_HITS=$::da_clock_text_hits"
    puts $out "CALCULATOR_TEXT_HITS=$::da_calc_text_hits"
    puts $out "CLOCK_BORDER_OK=$::da_clock_border_ok"
    puts $out "CALCULATOR_BORDER_OK=$::da_calc_border_ok"
    puts $out "CLOCK_MENU_OK=$::da_clock_menu_ok"
    puts $out "CALCULATOR_MENU_OK=$::da_calc_menu_ok"
    puts $out "MAX_NWIN=$::da_max_nwin"
    puts $out "STACK_MAX=[peek 0x1346]"
    puts $out "STACK_FAULT=[peek 0x1347]"
    puts $out "FINAL_NWIN=[peek 0x1350]"
    puts $out "FINAL_FOCUS=[peek 0x1351]"
    puts $out "SHELL_BUSY=[peek 0x133E]"
    puts $out "DEFER_COUNT=[peek 0xC376]"
    puts $out "DEFER_BUSY=[peek 0xC377]"
    puts $out [format "FINAL_PC=%04X" [reg PC]]
    puts $out [format "FINAL_SP=%04X" [reg SP]]
    close $out
    exit
}

proc da_api_hit {} {
    set op [reg A]
    if {$op == 3} {
        incr ::da_register_hits
        lappend ::da_register_ids [reg C]
    }
    set ::pause off
}

proc da_defer_api_hit {} {
    set op [reg A]
    if {$op == 0} {
        incr ::da_defer_register_hits
    } elseif {$op == 5} {
        incr ::da_find_hits
        lappend ::da_find_ids [reg C]
    } elseif {$op == 1} {
        incr ::da_send_hits
    }
    set ::pause off
}

proc da_text_hit {} {
    if {[da_sig_loaded $::da_clock_main $::da_clock_sig] &&
        [reg D] == 1 && [reg E] == 0} {
        incr ::da_clock_text_hits
    } elseif {[da_sig_loaded $::da_calc_main $::da_calc_sig] &&
              (([reg D] == 2 && [reg E] == 1) ||
               ([reg D] == 3 && [reg E] == 2))} {
        incr ::da_calc_text_hits
    }
    set ::pause off
}

proc da_move_tick {} {
    if {![da_lowram_ready]} { after time 0.002 da_move_tick; return }
    set x [peek 0x1306]
    set y [peek 0x1307]
    foreach mask {0x10 0x20 0x40 0x80} { catch {keymatrixup 8 $mask} }
    if {$x > 127 || $y > 211} { after time 0.002 da_move_tick; return }
    if {[expr {abs($x - $::da_target_x)}] <= 1 &&
        [expr {abs($y - $::da_target_y)}] <= 3} {
        da_release_all
        after time 0.10 $::da_callback
        return
    }
    if {[machine_info time] >= $::da_deadline} {
        da_finish "TIMEOUT moving pointer"
        return
    }
    if {$x < $::da_target_x - 1} {
        set mask 0x80
    } elseif {$x > $::da_target_x + 1} {
        set mask 0x10
    } elseif {$y < $::da_target_y - 3} {
        set mask 0x40
    } else {
        set mask 0x20
    }
    keymatrixdown 8 $mask
    after time 0.08 [list keymatrixup 8 $mask]
    after time 0.16 da_move_tick
}

proc da_move_to {x y callback} {
    da_release_all
    set ::da_target_x $x
    set ::da_target_y $y
    set ::da_callback $callback
    set ::da_deadline [expr {[machine_info time] + 30.0}]
    da_move_tick
}

proc da_click_up {callback} {
    keymatrixup 8 0x01
    after time 0.8 $callback
}

proc da_click {callback} {
    keymatrixdown 8 0x01
    after time 0.08 [list da_click_up $callback]
}

proc da_choose_accessory {row callback} {
    set ::da_choice_y [expr {14 + 10 * $row}]
    set ::da_choice_callback $callback
    da_move_to 11 4 da_choose_title
}

proc da_choose_title {} { da_click da_choose_popup }
proc da_choose_popup {} { da_move_to 12 $::da_choice_y da_choose_row }
proc da_choose_row {} { da_click $::da_choice_callback }

proc da_focus_desktop {callback} {
    set ::da_focus_callback $callback
    da_move_to 110 190 da_focus_desktop_click
}

proc da_focus_desktop_click {} {
    da_click da_wait_desktop_focus
}

proc da_wait_desktop_focus {} {
    if {![da_lowram_ready]} { after time 0.002 da_wait_desktop_focus; return }
    if {[peek 0x1351] == 0} {
        after time 1.0 $::da_focus_callback
    } elseif {[machine_info time] >= $::da_deadline} {
        da_finish "FAIL Desktop did not focus"
    } else {
        after time 0.1 da_wait_desktop_focus
    }
}

proc da_wait_first_clock {} {
    if {![da_lowram_ready]} { after time 0.002 da_wait_first_clock; return }
    set slot [peek 0x1351]
    if {[peek 0x1350] == 2 && $slot > 0 &&
        [da_sig_loaded $::da_clock_main $::da_clock_sig] &&
        $::da_clock_text_hits > 0} {
        if {![da_accessory_ok $slot 1]} {
            if {[machine_info time] >= $::da_deadline} {
                da_finish "FAIL Clock did not register exact ID 1"
            } else {
                after time 0.1 da_wait_first_clock
            }
            return
        }
        set ::da_clock_border_ok [da_border_ok $slot]
        set ::da_clock_menu_ok [da_menu_clock_ok]
        if {!$::da_clock_border_ok || !$::da_clock_menu_ok} {
            da_finish "FAIL Clock visual/menu contract"
            return
        }
        set ::da_first_clock_slot $slot
        da_focus_desktop {da_choose_accessory 1 da_wait_calculator}
    } elseif {[machine_info time] >= $::da_deadline} {
        da_finish "FAIL Clock did not launch from Desk"
    } else {
        after time 0.1 da_wait_first_clock
    }
}

proc da_wait_calculator {} {
    if {![da_lowram_ready]} { after time 0.002 da_wait_calculator; return }
    set slot [peek 0x1351]
    if {[peek 0x1350] == 3 && $slot > 0 &&
        [da_sig_loaded $::da_calc_main $::da_calc_sig] &&
        $::da_calc_text_hits >= 21} {
        if {![da_accessory_ok $slot 2]} {
            if {[machine_info time] >= $::da_deadline} {
                da_finish "FAIL Calculator did not register exact ID 2"
            } else {
                after time 0.1 da_wait_calculator
            }
            return
        }
        set ::da_calc_border_ok [da_border_ok $slot]
        set ::da_calc_menu_ok [da_menu_calc_ok]
        if {!$::da_calc_border_ok || !$::da_calc_menu_ok} {
            da_finish "FAIL Calculator visual/menu contract"
            return
        }
        set ::da_calc_slot $slot
        after time 0.5 da_capture_calculator
    } elseif {[machine_info time] >= $::da_deadline} {
        da_finish "FAIL Calculator did not launch from Desk"
    } else {
        after time 0.1 da_wait_calculator
    }
}

proc da_capture_calculator {} {
    catch {screenshot -raw $::da_screenshot}
    after time 0.5 {da_focus_desktop {da_choose_accessory 1 da_wait_calculator_reused}}
}

proc da_wait_calculator_reused {} {
    if {![da_lowram_ready]} { after time 0.002 da_wait_calculator_reused; return }
    if {[peek 0x1350] == 3 && [peek 0x1351] == $::da_calc_slot &&
        [da_sig_loaded $::da_calc_main $::da_calc_sig]} {
        da_focus_desktop {da_choose_accessory 0 da_wait_clock_reused}
    } elseif {[peek 0x1350] > 3} {
        da_finish "FAIL duplicate Calculator launched"
    } elseif {[machine_info time] >= $::da_deadline} {
        da_finish "FAIL live Calculator was not activated"
    } else {
        after time 0.1 da_wait_calculator_reused
    }
}

proc da_wait_clock_reused {} {
    if {![da_lowram_ready]} { after time 0.002 da_wait_clock_reused; return }
    if {[peek 0x1350] == 3 && [peek 0x1351] == $::da_first_clock_slot &&
        [da_sig_loaded $::da_clock_main $::da_clock_sig]} {
        set ::da_before_close_busy [da_busy_count]
        set entry [da_entry $::da_first_clock_slot]
        set x [expr {[peek [expr {$entry + 1}]] + 2}]
        set y [expr {[peek [expr {$entry + 2}]] + 4}]
        da_move_to $x $y da_close_clock
    } elseif {[peek 0x1350] > 3} {
        da_finish "FAIL duplicate Clock launched"
    } elseif {[machine_info time] >= $::da_deadline} {
        da_finish "FAIL live Clock was not activated"
    } else {
        after time 0.1 da_wait_clock_reused
    }
}

proc da_close_clock {} { da_click da_wait_clock_closed }

proc da_wait_clock_closed {} {
    if {![da_lowram_ready]} { after time 0.002 da_wait_clock_closed; return }
    if {[peek 0x1350] == 2 &&
        ([peek [expr {[da_entry $::da_first_clock_slot] + 13}]] & 1) == 0} {
        set ::da_closed_busy [da_busy_count]
        da_focus_desktop {da_choose_accessory 0 da_wait_clock_relaunched}
    } elseif {[machine_info time] >= $::da_deadline} {
        da_finish "FAIL closing Clock did not release its window"
    } else {
        after time 0.1 da_wait_clock_closed
    }
}

proc da_wait_clock_relaunched {} {
    if {![da_lowram_ready]} { after time 0.002 da_wait_clock_relaunched; return }
    set slot [peek 0x1351]
    if {[peek 0x1350] == 3 && $slot > 0 &&
        [da_sig_loaded $::da_clock_main $::da_clock_sig]} {
        set ::da_final_accessory_ok [da_accessory_ok $slot 1]
        if {$::da_final_accessory_ok} {
            set ::da_final_busy [da_busy_count]
            if {$::da_register_hits == 3 && $::da_defer_register_hits == 3 &&
                $::da_find_hits == 5 &&
                $::da_send_hits == 2 &&
                $::da_clock_text_hits > 0 && $::da_calc_text_hits >= 21 &&
                $::da_clock_border_ok && $::da_calc_border_ok &&
                $::da_clock_menu_ok && $::da_calc_menu_ok &&
                $::da_closed_busy == ($::da_before_close_busy - 1) &&
                $::da_final_busy == $::da_before_close_busy &&
                $::da_max_nwin == 3 && [peek 0x133E] == 0 &&
                [peek 0xC376] == 0 && [peek 0xC377] == 0} {
                da_finish PASS
                return
            }
        }
    } elseif {[peek 0x1350] > 3} {
        da_finish "FAIL relaunch created too many windows"
        return
    }
    if {[machine_info time] >= $::da_deadline} {
        da_finish "FAIL final accessory lifecycle contract"
    } else {
        after time 0.1 da_wait_clock_relaunched
    }
}

proc da_start {} {
    set candidate [expr {[debug read ioports 0xA8] & 3}]
    if {[peek 0x1350] != 1 || [peek 0x1306] > 127 || [peek 0x1307] > 211 ||
        [peek 0x1310] != 2} {
        after time 0.002 da_start
        return
    }
    set ::da_page0_slot $candidate
    set ::da_deadline [expr {[machine_info time] + 35.0}]
    da_choose_accessory 0 da_wait_first_clock
}

debug set_bp 0x80C0 {} {da_api_hit}
debug set_bp 0x80CF {} {da_defer_api_hit}
debug set_bp 0x800C {} {da_text_hit}
after time 62.0 da_start
