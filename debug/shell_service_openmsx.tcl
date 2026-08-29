# Exercise File Manager -> live Notepad shell delivery through real pointer input.

set throttle off
set pause_on_lost_focus false
set pause off

proc ss_env_addr {name} { expr {$::env($name) + 0} }

set ss_output $::env(GEMBENCH_SHELL_OUTPUT)
set ss_screenshot [file join [file dirname $ss_output] shell-service-failure.png]
set ss_main [ss_env_addr GEMBENCH_SHELL_MAIN]
set ss_sig0 [ss_env_addr GEMBENCH_SHELL_SIG0]
set ss_sig1 [ss_env_addr GEMBENCH_SHELL_SIG1]
set ss_sig2 [ss_env_addr GEMBENCH_SHELL_SIG2]
set ss_len [ss_env_addr GEMBENCH_SHELL_LEN]
set ss_buf [ss_env_addr GEMBENCH_SHELL_BUF]
set ss_deliver [ss_env_addr GEMBENCH_SHELL_DELIVER]
set ss_proc [ss_env_addr GEMBENCH_SHELL_PROC]
set ss_page0_slot -1
set ss_source_slot -1
set ss_source_rect {}
set ss_deadline 0
set ss_target_x 0
set ss_target_y 0
set ss_callback ""
set ss_shell_hits 0
set ss_register_hits 0
set ss_find_hits 0
set ss_send_hits 0
set ss_find_class -1
set ss_find_nwin -1
set ss_find_z {}
set ss_find_flags {}
set ss_send_sp -1
set ss_deliver_sp -1
set ss_target_sp -1
set ss_first_nwin -1
set ss_final_nwin -1
set ss_final_text ""
set ss_final_arg ""

proc ss_is_notepad {} {
    expr {[peek $::ss_main] == $::ss_sig0 &&
          [peek [expr {$::ss_main + 1}]] == $::ss_sig1 &&
          [peek [expr {$::ss_main + 2}]] == $::ss_sig2}
}

proc ss_lowram_ready {} {
    expr {$::ss_page0_slot >= 0 &&
          ([debug read ioports 0xA8] & 3) == $::ss_page0_slot &&
          [reg PC] >= 0x4000 &&
          [peek 0x1350] <= 8 && [peek 0x1351] < 8}
}

proc ss_u16 {address} {
    expr {[peek $address] + 256 * [peek [expr {$address + 1}]]}
}

proc ss_bytes {address length} {
    set value ""
    for {set i 0} {$i < $length} {incr i} {
        append value [format %c [peek [expr {$address + $i}]]]
    }
    return $value
}

proc ss_slot_entry {slot} { expr {0x1352 + 25 * $slot} }

proc ss_slot_rect {slot} {
    set p [expr {[ss_slot_entry $slot] + 1}]
    list [peek $p] [peek [expr {$p + 1}]] \
         [peek [expr {$p + 2}]] [peek [expr {$p + 3}]]
}

proc ss_slot_arg {slot} {
    ss_bytes [expr {[ss_slot_entry $slot] + 14}] 11
}

proc ss_release_all {} {
    foreach mask {0x01 0x10 0x20 0x40 0x80} {
        catch {keymatrixup 8 $mask}
    }
    catch {type -cancel}
}

proc ss_finish {status} {
    if {$::ss_page0_slot >= 0 && ![ss_lowram_ready]} {
        after time 0.002 [list ss_finish $status]
        return
    }
    ss_release_all
    if {$status ne "PASS"} {
        catch {screenshot -raw $::ss_screenshot}
    }
    set handle [open $::ss_output w]
    puts $handle "STATUS=$status"
    puts $handle "SHELL_HITS=$::ss_shell_hits"
    puts $handle "REGISTER_HITS=$::ss_register_hits"
    puts $handle "FIND_HITS=$::ss_find_hits"
    puts $handle "SEND_HITS=$::ss_send_hits"
    puts $handle "FIND_CLASS=$::ss_find_class"
    puts $handle "FIND_NWIN=$::ss_find_nwin"
    puts $handle "FIND_Z=$::ss_find_z"
    puts $handle "FIND_FLAGS=$::ss_find_flags"
    puts $handle [format "SEND_SP=%04X" $::ss_send_sp]
    puts $handle [format "DELIVER_SP=%04X" $::ss_deliver_sp]
    puts $handle [format "TARGET_SP=%04X" $::ss_target_sp]
    if {$::ss_send_sp >= 0 && $::ss_target_sp >= 0} {
        puts $handle "SHELL_STACK_DELTA=[expr {$::ss_send_sp - $::ss_target_sp}]"
    } else {
        puts $handle "SHELL_STACK_DELTA=-1"
    }
    puts $handle "SOURCE_SLOT=$::ss_source_slot"
    puts $handle "SOURCE_RECT=$::ss_source_rect"
    puts $handle "FILEMGR_RECT=[ss_slot_rect 1]"
    puts $handle "NOTEPAD_RECT=[ss_slot_rect 2]"
    puts $handle "FIRST_NWIN=$::ss_first_nwin"
    puts $handle "FINAL_NWIN=$::ss_final_nwin"
    puts $handle "CURRENT_NWIN=[peek 0x1350]"
    puts $handle "FINAL_FOCUS=[peek 0x1351]"
    puts $handle "POINTER=[peek 0x1306],[peek 0x1307]"
    puts $handle "FINAL_TEXT=$::ss_final_text"
    puts $handle "FINAL_ARG=$::ss_final_arg"
    puts $handle "SHELL_BUSY=[peek 0x133E]"
    puts $handle "SHELL_ARGUMENT=[ss_bytes 0x1423 11]"
    puts $handle [format "FINAL_PC=%04X" [reg PC]]
    puts $handle [format "FINAL_SP=%04X" [reg SP]]
    close $handle
    exit
}

proc ss_deliver_hit {} {
    incr ::ss_shell_hits
    set ::ss_deliver_sp [reg SP]
    set ::pause off
}

proc ss_proc_hit {} {
    if {[peek 0x133E] != 0 && [peek 0x1302] == 11 && [ss_is_notepad]} {
        set ::ss_target_sp [reg SP]
    }
    set ::pause off
}

proc ss_api_hit {} {
    set op [reg A]
    if {$op == 0} { incr ::ss_register_hits }
    if {$op == 1} {
        incr ::ss_find_hits
        set ::ss_find_class [reg B]
        set ::ss_find_nwin [peek 0x1350]
        set ::ss_find_z {}
        set ::ss_find_flags {}
        for {set i 0} {$i < $::ss_find_nwin && $i < 8} {incr i} {
            set slot [peek [expr {0x141A + $i}]]
            lappend ::ss_find_z $slot
            lappend ::ss_find_flags [peek [expr {[ss_slot_entry $slot] + 13}]]
        }
    }
    if {$op == 2} {
        incr ::ss_send_hits
        set ::ss_send_sp [reg SP]
    }
    set ::pause off
}

proc ss_move_tick {} {
    if {![ss_lowram_ready]} {
        after time 0.002 ss_move_tick
        return
    }
    set x [peek 0x1306]
    set y [peek 0x1307]
    foreach mask {0x10 0x20 0x40 0x80} { catch {keymatrixup 8 $mask} }
    if {$x > 127 || $y > 211} {
        after time 0.002 ss_move_tick
        return
    }
    if {[expr {abs($x - $::ss_target_x)}] <= 1 &&
        [expr {abs($y - $::ss_target_y)}] <= 3} {
        ss_release_all
        after time 0.10 $::ss_callback
        return
    }
    if {[machine_info time] >= $::ss_deadline} {
        ss_finish "TIMEOUT moving pointer"
        return
    }
    if {$x < $::ss_target_x - 1} {
        set mask 0x80
    } elseif {$x > $::ss_target_x + 1} {
        set mask 0x10
    } elseif {$y < $::ss_target_y - 3} {
        set mask 0x40
    } else {
        set mask 0x20
    }
    keymatrixdown 8 $mask
    after time 0.08 [list keymatrixup 8 $mask]
    after time 0.16 ss_move_tick
}

proc ss_move_to {x y callback} {
    ss_release_all
    set ::ss_target_x $x
    set ::ss_target_y $y
    set ::ss_callback $callback
    set ::ss_deadline [expr {[machine_info time] + 30.0}]
    ss_move_tick
}

proc ss_click_up {callback} {
    keymatrixup 8 0x01
    after time 1.0 $callback
}

proc ss_click {callback} {
    keymatrixdown 8 0x01
    after time 0.08 [list ss_click_up $callback]
}

proc ss_double_second_up {callback} {
    keymatrixup 8 0x01
    after time 0.10 $callback
}

proc ss_double_second {callback} {
    keymatrixdown 8 0x01
    after time 0.06 [list ss_double_second_up $callback]
}

proc ss_double_first_up {callback} {
    keymatrixup 8 0x01
    after time 0.10 [list ss_double_second $callback]
}

proc ss_double_click {callback} {
    keymatrixdown 8 0x01
    after time 0.06 [list ss_double_first_up $callback]
}

proc ss_wait_second {} {
    if {![ss_lowram_ready]} {
        after time 0.002 ss_wait_second
        return
    }
    set ::ss_final_nwin [peek 0x1350]
    if {$::ss_final_nwin > 3} {
        ss_finish "FAIL duplicate Notepad launched"
        return
    }
    if {$::ss_final_nwin == 3 && [peek 0x1351] == $::ss_source_slot &&
        [ss_is_notepad] && [ss_u16 $::ss_len] == 8 &&
        [ss_bytes $::ss_buf 8] eq "SECOND14"} {
        set ::ss_final_text [ss_bytes $::ss_buf 8]
        set ::ss_final_arg [ss_slot_arg $::ss_source_slot]
        set flags [peek [expr {[ss_slot_entry $::ss_source_slot] + 13}]]
        if {$::ss_shell_hits != 1 || ($flags & 0xE0) != 0x20 ||
            [peek 0x133E] != 0 || $::ss_final_arg ne "B       TXT" ||
            [ss_bytes 0x1423 11] ne "B       TXT"} {
            ss_finish "FAIL shell contract state"
        } else {
            ss_finish PASS
        }
        return
    }
    if {[machine_info time] >= $::ss_deadline} {
        ss_finish "FAIL live Notepad did not load B.TXT"
    } else {
        after time 0.1 ss_wait_second
    }
}

proc ss_launch_second {} {
    set ::ss_deadline [expr {[machine_info time] + 35.0}]
    ss_double_click ss_wait_second
}

proc ss_wait_filemgr_top {} {
    if {![ss_lowram_ready]} { after time 0.002 ss_wait_filemgr_top; return }
    if {[peek 0x1351] == 1} {
        # Raising a background managed window triggers a complete compositor
        # pass on a 3.58 MHz target. Drain it before steering toward B.TXT.
        after time 40.0 {ss_move_to 50 104 ss_launch_second}
    } elseif {[machine_info time] >= $::ss_deadline} {
        ss_finish "FAIL File Manager did not focus"
    } else {
        after time 0.1 ss_wait_filemgr_top
    }
}

proc ss_focus_filemgr_up {} {
    keymatrixup 8 0x01
    after time 1.0 ss_wait_filemgr_top
}

proc ss_focus_filemgr {} {
    # A managed Notepad frame can take longer than a short synthetic tap. Hold
    # the button across several polls so the background title definitely sees
    # one fresh edge.
    keymatrixdown 8 0x01
    after time 0.8 ss_focus_filemgr_up
}

proc ss_top_filemgr {} {
    set ::ss_deadline [expr {[machine_info time] + 20.0}]
    # The initial Notepad overlaps File Manager except for its bottom strip.
    # Click that exposed, empty content area so focus and z-order change through
    # the real WM path without first having to synthesize a window drag.
    ss_move_to 20 180 ss_focus_filemgr
}

proc ss_wait_first {} {
    if {![ss_lowram_ready]} {
        after time 0.002 ss_wait_first
        return
    }
    if {[peek 0x1350] >= 3 && [ss_is_notepad] && [ss_u16 $::ss_len] == 7 &&
        [ss_bytes $::ss_buf 7] eq "FIRST14"} {
        set ::ss_first_nwin [peek 0x1350]
        set ::ss_source_slot [peek 0x1351]
        set flags [peek [expr {[ss_slot_entry $::ss_source_slot] + 13}]]
        if {($flags & 0xE0) != 0x20} {
            ss_finish "FAIL Notepad did not register text-editor service"
        } else {
            set ::ss_source_rect [ss_slot_rect $::ss_source_slot]
            after time 40.0 ss_top_filemgr
        }
    } elseif {[machine_info time] >= $::ss_deadline} {
        ss_finish "FAIL first Notepad did not load A.TXT"
    } else {
        after time 0.1 ss_wait_first
    }
}

proc ss_launch_first {} {
    catch {screenshot -raw $::ss_screenshot}
    set ::ss_deadline [expr {[machine_info time] + 35.0}]
    ss_double_click ss_wait_first
}

proc ss_open_drive {} {
    # Root folders occupy row one. HELLO.GBR precedes the text group, so A.TXT
    # and B.TXT are row two cells two/three.
    ss_double_click {after time 40.0 {ss_move_to 33 104 ss_launch_first}}
}

proc ss_start {} {
    set candidate [expr {[debug read ioports 0xA8] & 3}]
    if {[peek 0x1350] != 1 || [peek 0x1306] > 127 || [peek 0x1307] > 211} {
        after time 0.002 ss_start
        return
    }
    set ::ss_page0_slot $candidate
    ss_move_to 4 40 ss_open_drive
}

debug set_bp $ss_deliver {} {ss_deliver_hit}
debug set_bp $ss_proc {} {ss_proc_hit}
debug set_bp 0x80C0 {} {ss_api_hit}
after time 62.0 ss_start
