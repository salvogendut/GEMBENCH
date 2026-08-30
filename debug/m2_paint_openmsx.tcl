# Exercise the MSX2 Milestone-2 application/window lifecycle with in-tree Paint.
set throttle off
set pause_on_lost_focus false
set pause off

set p2_output $::env(GEMBENCH_M2_PAINT_OUTPUT)
set p2_screenshot $::env(GEMBENCH_M2_PAINT_SCREENSHOT)
set p2_deadline 0
set p2_target_x 0
set p2_target_y 0
set p2_callback ""
set p2_page0_slot -1
set p2_page0_ppi -1
set p2_page0_secondary -1
set p2_slot_candidate -1
set p2_slot_samples 0
set p2_initial_free 0
set p2_owner 0
set p2_app_slot -1
set p2_tool_slot -1
set p2_preview_slot -1
set p2_work_slot -1
set p2_work_generation 0
set p2_max_nwin 0
set p2_refocused 0

proc p2_word {address} {
    expr {[peek $address] + 256 * [peek [expr {$address + 1}]]}
}

proc p2_owner_count {} {
    set count 0
    for {set i 0} {$i < 8} {incr i} {
        if {[peek [expr {0xC2C0 + $i}]] != 0} {incr count}
    }
    return $count
}

proc p2_entry {slot} { expr {0x1352 + 25 * $slot} }

proc p2_slot_owner {slot} {
    expr {[peek [expr {0xC2D0 + $slot}]] |
          ([peek [expr {0xC2D8 + $slot}]] << 8)}
}

proc p2_owned_slot {owner width height} {
    for {set slot 0} {$slot < 8} {incr slot} {
        set entry [p2_entry $slot]
        if {[p2_slot_owner $slot] == $owner &&
            ([peek [expr {$entry + 13}]] & 1) != 0 &&
            [peek [expr {$entry + 3}]] == $width &&
            [peek [expr {$entry + 4}]] == $height} {
            return $slot
        }
    }
    return -1
}

proc p2_release_all {} {
    catch {keymatrixup 8 0x01}
    catch {keymatrixup 8 0x10}
    catch {keymatrixup 8 0x20}
    catch {keymatrixup 8 0x40}
    catch {keymatrixup 8 0x80}
}

proc p2_lowram_ready {} {
    expr {$::p2_page0_slot >= 0 &&
          [debug read ioports 0xA8] == $::p2_page0_ppi &&
          [peek 0xFFFF] == $::p2_page0_secondary &&
          [peek 0x1350] <= 8 && [peek 0x1351] < 8 &&
          [peek 0x1306] <= 127 && [peek 0x1307] <= 211}
}

proc p2_finish {status} {
    p2_release_all
    set out [open $::p2_output w]
    puts $out "STATUS=$status"
    puts $out [format "PAINT_OWNER=%04X" $::p2_owner]
    puts $out "APP_SLOT=$::p2_app_slot"
    puts $out "TOOL_SLOT=$::p2_tool_slot"
    puts $out "PREVIEW_SLOT=$::p2_preview_slot"
    puts $out "WORK_SLOT=$::p2_work_slot"
    puts $out "WORK_GENERATION=$::p2_work_generation"
    puts $out "INITIAL_FREE=$::p2_initial_free"
    puts $out "FINAL_FREE=[peek 0xC2E5]"
    puts $out "ACTIVE_OWNERS=[p2_owner_count]"
    puts $out "LIVE_WINDOWS=[peek 0x1350]"
    puts $out "FOCUS=[peek 0x1351]"
    puts $out "MAX_WINDOWS=$::p2_max_nwin"
    puts $out [format "FINAL_PC=%04X" [reg PC]]
    close $out
    if {$status ne "PASS"} { catch {screenshot -raw $::p2_screenshot} }
    exit
}

proc p2_move_tick {} {
    if {![p2_lowram_ready]} {
        if {[machine_info time] >= $::p2_deadline} {
            p2_finish "TIMEOUT waiting for low RAM while moving pointer"
            return
        }
        after time 0.002 p2_move_tick
        return
    }
    set x [peek 0x1306]
    set y [peek 0x1307]
    p2_release_all
    if {[expr {abs($x - $::p2_target_x)}] <= 1 &&
        [expr {abs($y - $::p2_target_y)}] <= 3} {
        after time 0.08 $::p2_callback
        return
    }
    if {[machine_info time] >= $::p2_deadline} {
        p2_finish "TIMEOUT moving pointer"
        return
    }
    if {$x < $::p2_target_x - 1} {
        set mask 0x80
    } elseif {$x > $::p2_target_x + 1} {
        set mask 0x10
    } elseif {$y < $::p2_target_y - 3} {
        set mask 0x40
    } else {
        set mask 0x20
    }
    keymatrixdown 8 $mask
    after time 0.08 [list keymatrixup 8 $mask]
    after time 0.16 p2_move_tick
}

proc p2_move_to {x y callback} {
    p2_release_all
    set ::p2_target_x $x
    set ::p2_target_y $y
    set ::p2_callback $callback
    set ::p2_deadline [expr {[machine_info time] + 30.0}]
    p2_move_tick
}

proc p2_click_up {callback} {
    keymatrixup 8 0x01
    after time 0.8 $callback
}

proc p2_click {callback} {
    keymatrixdown 8 0x01
    after time 0.08 [list p2_click_up $callback]
}

proc p2_double_second_up {callback} {
    keymatrixup 8 0x01
    after time 0.10 $callback
}

proc p2_double_second {callback} {
    keymatrixdown 8 0x01
    after time 0.06 [list p2_double_second_up $callback]
}

proc p2_double_first_up {callback} {
    keymatrixup 8 0x01
    after time 0.10 [list p2_double_second $callback]
}

proc p2_double_click {callback} {
    keymatrixdown 8 0x01
    after time 0.06 [list p2_double_first_up $callback]
}

proc p2_close_tool_done {} {
    if {![p2_lowram_ready]} {
        after time 0.05 p2_close_tool_done
        return
    }
    if {[peek 0x1350] == 2} {
        if {[peek [expr {0xC2C0 + $::p2_app_slot}]] != 0 ||
            [peek 0xC2E5] != $::p2_initial_free || [p2_owner_count] != 2} {
            p2_finish "FAIL final application teardown"
        } else { p2_finish "PASS" }
    } elseif {[machine_info time] >= $::p2_deadline} {
        p2_finish "FAIL Toolchest close timeout"
    } else { after time 0.1 p2_close_tool_done }
}

proc p2_close_preview_done {} {
    if {![p2_lowram_ready]} {
        after time 0.05 p2_close_preview_done
        return
    }
    if {[peek 0x1350] == 3} {
        if {[peek [expr {0xC320 + $::p2_app_slot}]] != 1 ||
            [peek 0xC2E5] != $::p2_initial_free - 1 ||
            [p2_slot_owner $::p2_tool_slot] != $::p2_owner} {
            p2_finish "FAIL document-window teardown"
            return
        }
        set entry [p2_entry $::p2_tool_slot]
        set ::p2_deadline [expr {[machine_info time] + 20.0}]
        p2_move_to [expr {[peek [expr {$entry + 1}]] + 2}] \
                   [expr {[peek [expr {$entry + 2}]] + 6}] \
                   {p2_click p2_close_tool_done}
    } elseif {[machine_info time] >= $::p2_deadline} {
        p2_finish "FAIL Preview close timeout"
    } else { after time 0.1 p2_close_preview_done }
}

proc p2_close_work_done {} {
    if {![p2_lowram_ready]} {
        after time 0.05 p2_close_work_done
        return
    }
    if {[peek 0x1350] == 4} {
        if {[peek [expr {0xC320 + $::p2_app_slot}]] != 2 ||
            [p2_slot_owner $::p2_work_slot] != 0 ||
            [peek [expr {[p2_entry $::p2_work_slot] + 13}]] & 1} {
            p2_finish "FAIL independent Canvas close"
            return
        }
        set entry [p2_entry $::p2_preview_slot]
        set ::p2_deadline [expr {[machine_info time] + 20.0}]
        p2_move_to [expr {[peek [expr {$entry + 1}]] + 2}] \
                   [expr {[peek [expr {$entry + 2}]] + 6}] \
                   {p2_click p2_close_preview_done}
    } elseif {[machine_info time] >= $::p2_deadline} {
        p2_finish "FAIL Canvas close timeout"
    } else { after time 0.1 p2_close_work_done }
}

proc p2_wait_work {} {
    if {![p2_lowram_ready]} {
        after time 0.05 p2_wait_work
        return
    }
    set nwin [peek 0x1350]
    if {$nwin > $::p2_max_nwin} { set ::p2_max_nwin $nwin }
    if {$nwin == 5 &&
        [peek [expr {0xC320 + $::p2_app_slot}]] == 3} {
        set ::p2_work_slot [p2_owned_slot $::p2_owner 42 175]
        if {$::p2_work_slot < 0} {
            p2_finish "FAIL Canvas record missing"
            return
        }
        set ::p2_work_generation [peek [expr {0xC350 + $::p2_work_slot}]]
        set entry [p2_entry $::p2_work_slot]
        if {$::p2_work_generation == 0 ||
            [peek $entry] != [peek [p2_entry $::p2_tool_slot]]} {
            p2_finish "FAIL Canvas ownership/code page"
            return
        }
        set ::p2_deadline [expr {[machine_info time] + 20.0}]
        p2_move_to [expr {[peek [expr {$entry + 1}]] + 2}] \
                   [expr {[peek [expr {$entry + 2}]] + 6}] \
                   {p2_click p2_close_work_done}
    } elseif {[machine_info time] >= $::p2_deadline} {
        p2_finish "FAIL Canvas did not register"
    } else { after time 0.1 p2_wait_work }
}

proc p2_wait_paint {} {
    if {![p2_lowram_ready]} {
        after time 0.05 p2_wait_paint
        return
    }
    set nwin [peek 0x1350]
    if {$nwin > $::p2_max_nwin} { set ::p2_max_nwin $nwin }
    if {$nwin == 3 && !$::p2_refocused} {
        # File Manager's second click can remain the focus for one frame after
        # synchronous launch. Focus the durable Toolchest so Paint's chunked
        # launch-document job receives frames and can publish Preview.
        for {set app 0} {$app < 8} {incr app} {
            if {[peek [expr {0xC2C0 + $app}]] != 0 &&
                [peek [expr {0xC320 + $app}]] == 1 && $app > 1} {
                set owner [expr {($app + 1) |
                    ([peek [expr {0xC2C8 + $app}]] << 8)}]
                set slot [p2_owned_slot $owner 29 126]
                if {$slot >= 0} {
                    set ::p2_refocused 1
                    set entry [p2_entry $slot]
                    p2_move_to [expr {[peek [expr {$entry + 1}]] + 10}] \
                               [expr {[peek [expr {$entry + 2}]] + 45}] \
                               {p2_click p2_wait_paint}
                    return
                }
            }
        }
    }
    if {$nwin == 4} {
        for {set app 0} {$app < 8} {incr app} {
            if {[peek [expr {0xC2C0 + $app}]] != 0 &&
                [peek [expr {0xC320 + $app}]] == 2} {
                set ::p2_app_slot $app
                set ::p2_owner [expr {($app + 1) |
                    ([peek [expr {0xC2C8 + $app}]] << 8)}]
                break
            }
        }
        set ::p2_tool_slot [p2_owned_slot $::p2_owner 29 126]
        set ::p2_preview_slot [p2_owned_slot $::p2_owner 33 92]
        if {$::p2_app_slot < 0 || $::p2_tool_slot < 0 ||
            $::p2_preview_slot < 0 || [p2_owner_count] != 3 ||
            [peek 0xC2E5] != $::p2_initial_free - 2 ||
            [peek [p2_entry $::p2_tool_slot]] !=
                [peek [p2_entry $::p2_preview_slot]] ||
            [peek [expr {0xC308 + $::p2_app_slot}]] !=
                [peek [p2_entry $::p2_tool_slot]]} {
            p2_finish "FAIL Paint application/window records"
            return
        }
        set entry [p2_entry $::p2_preview_slot]
        set ::p2_deadline [expr {[machine_info time] + 30.0}]
        p2_move_to [expr {[peek [expr {$entry + 1}]] + 12}] \
                   [expr {[peek [expr {$entry + 2}]] + 35}] \
                   {p2_click p2_wait_work}
    } elseif {[machine_info time] >= $::p2_deadline} {
        p2_finish "FAIL Paint Toolchest/Preview did not register"
    } else { after time 0.1 p2_wait_paint }
}

proc p2_launch_paint {} {
    set ::p2_deadline [expr {[machine_info time] + 45.0}]
    p2_double_click p2_wait_paint
}

proc p2_filemgr_ready {} {
    if {![p2_lowram_ready]} {
        after time 0.05 p2_filemgr_ready
        return
    }
    if {[peek 0x1350] == 2 && [peek 0x1351] == 1 &&
        [peek 0x144A] == 56 && [peek 0x144B] == 158} {
        set ::p2_initial_free [peek 0xC2E5]
        # Three folders fill row one. HELLO.GBR is the first app-ranked item
        # on row two; A.PIC is the next cell because pictures sort immediately
        # after applications/resources.
        after time 3.0 {p2_move_to 33 104 p2_launch_paint}
    } elseif {[machine_info time] >= $::p2_deadline} {
        p2_finish "FAIL File Manager did not register"
    } else { after time 0.1 p2_filemgr_ready }
}

proc p2_open_drive {} {
    set ::p2_deadline [expr {[machine_info time] + 30.0}]
    p2_double_click p2_filemgr_ready
}

proc p2_desktop_ready {} {
    if {[peek 0x1350] == 1 && [peek 0x1351] == 0 &&
        [peek 0x1306] <= 127 && [peek 0x1307] <= 211 &&
        [p2_owner_count] == 1 && [peek 0xC2F0] == 24 &&
        [peek 0xC2F1] == 2} {
        set ppi [debug read ioports 0xA8]
        set secondary [peek 0xFFFF]
        set candidate [expr {($ppi << 8) | $secondary}]
        if {$candidate == $::p2_slot_candidate} {
            incr ::p2_slot_samples
        } else {
            set ::p2_slot_candidate $candidate
            set ::p2_slot_samples 1
        }
        if {$::p2_slot_samples >= 4} {
            set ::p2_page0_ppi $ppi
            set ::p2_page0_secondary $secondary
            set ::p2_page0_slot [expr {$ppi & 3}]
            p2_move_to 4 40 p2_open_drive
            return
        }
    }
    if {[machine_info time] >= $::p2_deadline} {
        p2_finish "FAIL Desktop slot discovery"
    } else { after time 0.013 p2_desktop_ready }
}

proc p2_start {} {
    set ::p2_deadline [expr {[machine_info time] + 30.0}]
    p2_desktop_ready
}

after time 62.0 p2_start
