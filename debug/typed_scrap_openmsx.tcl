# Exercise GEMBENCH's typed clipboard through two real MSX2 Notepad windows.
# The source copies typed text through Edit; the destination first rejects the
# same bytes while tagged bitmap, then accepts them when restored to text.

set throttle off
set pause_on_lost_focus false
set pause off

proc sc_env_addr {name} { expr {$::env($name) + 0} }

set sc_output $::env(GEMBENCH_SCRAP_OUTPUT)
set sc_main [sc_env_addr GEMBENCH_SCRAP_MAIN]
set sc_sig0 [sc_env_addr GEMBENCH_SCRAP_SIG0]
set sc_sig1 [sc_env_addr GEMBENCH_SCRAP_SIG1]
set sc_sig2 [sc_env_addr GEMBENCH_SCRAP_SIG2]
set sc_len [sc_env_addr GEMBENCH_SCRAP_LEN]
set sc_buf [sc_env_addr GEMBENCH_SCRAP_BUF]
set sc_paste_return [sc_env_addr GEMBENCH_SCRAP_PASTE_RETURN]
set sc_paste_entry [sc_env_addr GEMBENCH_SCRAP_PASTE_ENTRY]
set sc_select_all [sc_env_addr GEMBENCH_SCRAP_SELECT_ALL]
set sc_copy_sel [sc_env_addr GEMBENCH_SCRAP_COPY_SEL]

set sc_clip_len 0x3E00
set sc_clip_data 0x3E02
set sc_type 0x133D
set sc_text "SCRAP13"
set sc_deadline 0
set sc_target_x 0
set sc_target_y 0
set sc_callback ""
set sc_menu_row 0
set sc_menu_callback ""
set sc_source_slot -1
set sc_source_rect {}
set sc_page0_slot -1
set sc_finish_status ""
set sc_paste_stage 0
set sc_paste_hits 0
set sc_copy_deadline 0
set sc_select_hits 0
set sc_copy_hits 0
set sc_destination_attempts 0
set sc_rejected_len -1
set sc_accepted_len -1
set sc_accepted_text ""
set sc_destination_len -1
set sc_destination_text ""
set sc_rejected_before_len -1
set sc_rejected_before_text ""
set sc_accepted_before_len -1
set sc_accepted_before_text ""

proc sc_is_notepad {} {
    expr {[peek $::sc_main] == $::sc_sig0 &&
          [peek [expr {$::sc_main + 1}]] == $::sc_sig1 &&
          [peek [expr {$::sc_main + 2}]] == $::sc_sig2}
}

proc sc_lowram_ready {} {
    expr {$::sc_page0_slot >= 0 &&
          ([debug read ioports 0xA8] & 3) == $::sc_page0_slot}
}

proc sc_u16 {address} {
    expr {[peek $address] + 256 * [peek [expr {$address + 1}]]}
}

proc sc_bytes {address length} {
    set value ""
    for {set i 0} {$i < $length} {incr i} {
        append value [format %c [peek [expr {$address + $i}]]]
    }
    return $value
}

proc sc_clip_text {} {
    sc_bytes $::sc_clip_data [sc_u16 $::sc_clip_len]
}

proc sc_slot_rect {slot} {
    set p [expr {0x1352 + 25 * $slot + 1}]
    list [peek $p] [peek [expr {$p + 1}]] \
         [peek [expr {$p + 2}]] [peek [expr {$p + 3}]]
}

proc sc_release_all {} {
    foreach mask {0x01 0x10 0x20 0x40 0x80} {
        catch {keymatrixup 8 $mask}
    }
    catch {type -cancel}
}

proc sc_finish {status} {
    set ::sc_finish_status $status
    if {$::sc_page0_slot >= 0 && ![sc_lowram_ready]} {
        after time 0.002 {sc_finish $::sc_finish_status}
        return
    }
    sc_release_all
    if {$status ne "PASS"} {
        catch {screenshot -raw "build/msx/typed-scrap-failure.png"}
    }
    set handle [open $::sc_output w]
    puts $handle "STATUS=$status"
    puts $handle "CLIP_TYPE=[peek $::sc_type]"
    puts $handle "CLIP_LENGTH=[sc_u16 $::sc_clip_len]"
    puts $handle "CLIP_TEXT=[sc_clip_text]"
    puts $handle "PASTE_HITS=$::sc_paste_hits"
    puts $handle "SELECT_HITS=$::sc_select_hits"
    puts $handle "COPY_HITS=$::sc_copy_hits"
    puts $handle "DESTINATION_ATTEMPTS=$::sc_destination_attempts"
    puts $handle "REJECTED_LENGTH=$::sc_rejected_len"
    puts $handle "ACCEPTED_LENGTH=$::sc_accepted_len"
    puts $handle "ACCEPTED_TEXT=$::sc_accepted_text"
    puts $handle "DESTINATION_INITIAL_LENGTH=$::sc_destination_len"
    puts $handle "DESTINATION_INITIAL_TEXT=$::sc_destination_text"
    puts $handle "REJECTED_BEFORE_LENGTH=$::sc_rejected_before_len"
    puts $handle "REJECTED_BEFORE_TEXT=$::sc_rejected_before_text"
    puts $handle "ACCEPTED_BEFORE_LENGTH=$::sc_accepted_before_len"
    puts $handle "ACCEPTED_BEFORE_TEXT=$::sc_accepted_before_text"
    puts $handle "SOURCE_RECT=$::sc_source_rect"
    puts $handle "SOURCE_SLOT=$::sc_source_slot"
    puts $handle "TOP_SLOT=[peek 0x1351]"
    puts $handle "FINAL_NWIN=[peek 0x1350]"
    puts $handle [format "FINAL_PC=%04X" [reg PC]]
    puts $handle [format "FINAL_SP=%04X" [reg SP]]
    close $handle
    exit
}

proc sc_paste_return_hit {} {
    if {[sc_lowram_ready] && [sc_is_notepad]} {
        incr ::sc_paste_hits
        set n [sc_u16 $::sc_len]
        if {$::sc_paste_stage == 1} {
            set ::sc_rejected_len $n
        } elseif {$::sc_paste_stage == 2} {
            set ::sc_accepted_len $n
            set ::sc_accepted_text [sc_bytes $::sc_buf $n]
        }
    }
    set ::pause off
}

proc sc_paste_entry_hit {} {
    if {[sc_lowram_ready] && [sc_is_notepad]} {
        set n [sc_u16 $::sc_len]
        if {$::sc_paste_stage == 1} {
            set ::sc_rejected_before_len $n
            set ::sc_rejected_before_text [sc_bytes $::sc_buf $n]
        } elseif {$::sc_paste_stage == 2} {
            set ::sc_accepted_before_len $n
            set ::sc_accepted_before_text [sc_bytes $::sc_buf $n]
        }
    }
    set ::pause off
}

proc sc_select_hit {} {
    if {[sc_is_notepad]} { incr ::sc_select_hits }
    set ::pause off
}

proc sc_copy_hit {} {
    if {[sc_is_notepad]} { incr ::sc_copy_hits }
    set ::pause off
}

proc sc_move_tick {} {
    if {![sc_lowram_ready]} {
        after time 0.002 sc_move_tick
        return
    }
    set x [peek 0x1306]
    set y [peek 0x1307]
    foreach mask {0x10 0x20 0x40 0x80} { catch {keymatrixup 8 $mask} }
    if {$x > 127 || $y > 211} {
        after time 0.002 sc_move_tick
        return
    }
    if {[expr {abs($x - $::sc_target_x)}] <= 1 &&
        [expr {abs($y - $::sc_target_y)}] <= 3} {
        sc_release_all
        after time 0.10 $::sc_callback
        return
    }
    if {[machine_info time] >= $::sc_deadline} {
        sc_finish "TIMEOUT moving pointer"
        return
    }
    if {$x < $::sc_target_x - 1} {
        set mask 0x80
    } elseif {$x > $::sc_target_x + 1} {
        set mask 0x10
    } elseif {$y < $::sc_target_y - 3} {
        set mask 0x40
    } else {
        set mask 0x20
    }
    keymatrixdown 8 $mask
    after time 0.08 [list keymatrixup 8 $mask]
    after time 0.16 sc_move_tick
}

proc sc_move_to {x y callback} {
    sc_release_all
    set ::sc_target_x $x
    set ::sc_target_y $y
    set ::sc_callback $callback
    set ::sc_deadline [expr {[machine_info time] + 30.0}]
    sc_move_tick
}

proc sc_click_up {callback} {
    keymatrixup 8 0x01
    after time 1.0 $callback
}

proc sc_click {callback} {
    keymatrixdown 8 0x01
    after time 0.08 [list sc_click_up $callback]
}

proc sc_double_second_up {callback} {
    keymatrixup 8 0x01
    after time 0.10 $callback
}

proc sc_double_second {callback} {
    keymatrixdown 8 0x01
    after time 0.06 [list sc_double_second_up $callback]
}

proc sc_double_first_up {callback} {
    keymatrixup 8 0x01
    after time 0.10 [list sc_double_second $callback]
}

proc sc_double_click {callback} {
    keymatrixdown 8 0x01
    after time 0.06 [list sc_double_first_up $callback]
}

proc sc_select_menu_row {} {
    sc_click $::sc_menu_callback
}

proc sc_edit_menu_open {} {
    set y [expr {15 + 10 * $::sc_menu_row}]
    sc_click [list sc_move_to 20 $y sc_select_menu_row]
}

proc sc_edit_menu {row callback} {
    set ::sc_menu_row $row
    set ::sc_menu_callback $callback
    # Notepad's generated menu columns are File=10 and Edit=17.
    sc_move_to 18 4 sc_edit_menu_open
}

proc sc_after_accepted {} {
    if {![sc_lowram_ready]} { after time 0.002 sc_after_accepted; return }
    set expected "$::sc_accepted_before_text$::sc_text"
    if {$::sc_paste_hits < 2 ||
        $::sc_accepted_len != $::sc_accepted_before_len + 7 ||
        $::sc_accepted_text ne $expected ||
        [peek $::sc_type] != 1 || [sc_u16 $::sc_clip_len] != 7 ||
        [sc_clip_text] ne $::sc_text} {
        sc_finish "FAIL typed text paste"
    }
    sc_finish PASS
}

proc sc_wait_accepted {} {
    if {$::sc_paste_hits >= 2} {
        after time 1.0 sc_after_accepted
    } elseif {[machine_info time] >= $::sc_deadline} {
        sc_finish "FAIL accepted paste did not return"
    } else {
        after time 0.1 sc_wait_accepted
    }
}

proc sc_paste_typed {} {
    poke $::sc_type 1
    set ::sc_paste_stage 2
    set ::sc_deadline [expr {[machine_info time] + 20.0}]
    sc_edit_menu 2 sc_wait_accepted
}

proc sc_after_rejected {} {
    if {![sc_lowram_ready]} { after time 0.002 sc_after_rejected; return }
    if {$::sc_paste_hits < 1 ||
        $::sc_rejected_len != $::sc_rejected_before_len ||
        [peek $::sc_type] != 2 || [sc_u16 $::sc_clip_len] != 7 ||
        [sc_clip_text] ne $::sc_text} {
        sc_finish "FAIL non-text paste was not atomic"
    }
    sc_paste_typed
}

proc sc_wait_rejected {} {
    if {$::sc_paste_hits >= 1} {
        after time 1.0 sc_after_rejected
    } elseif {[machine_info time] >= $::sc_deadline} {
        sc_finish "FAIL rejected paste did not return"
    } else {
        after time 0.1 sc_wait_rejected
    }
}

proc sc_try_mismatch {} {
    if {![sc_lowram_ready]} { after time 0.002 sc_try_mismatch; return }
    set ::sc_destination_len [sc_u16 $::sc_len]
    set ::sc_destination_text [sc_bytes $::sc_buf $::sc_destination_len]
    poke $::sc_type 2
    set ::sc_paste_stage 1
    set ::sc_deadline [expr {[machine_info time] + 20.0}]
    sc_edit_menu 2 sc_wait_rejected
}

proc sc_wait_destination {} {
    if {![sc_lowram_ready]} {
        after time 0.002 sc_wait_destination
    } elseif {[peek 0x1350] >= 4 && [sc_is_notepad] && [sc_u16 $::sc_len] == 0} {
        # Drain launch-click keyboard residue before taking the atomic baseline.
        after time 12.0 sc_try_mismatch
    } elseif {[machine_info time] >= $::sc_deadline} {
        if {$::sc_destination_attempts < 3 && [peek 0x1350] == 3} {
            # Background focus can coincide with a delayed V9938/File Manager
            # repaint. Retry the same real title/focus/launch path, bounded.
            after time 40.0 {sc_move_to 20 32 sc_top_filemgr}
        } else {
            sc_finish "FAIL second Notepad did not open empty"
        }
    } else {
        after time 0.1 sc_wait_destination
    }
}

proc sc_launch_destination {} {
    incr ::sc_destination_attempts
    set ::sc_deadline [expr {[machine_info time] + 30.0}]
    sc_double_click sc_wait_destination
}

proc sc_top_filemgr {} {
    # Raise File Manager through its exposed title, drain its repaint, then
    # approach B.APP as a normal foreground double-click.
    sc_click {after time 40.0 {sc_move_to 33 104 sc_launch_destination}}
}

proc sc_wait_moved {} {
    if {![sc_lowram_ready]} { after time 0.002 sc_wait_moved; return }
    set rect [sc_slot_rect $::sc_source_slot]
    lassign $rect x y w h
    if {$x >= 38} {
        set ::sc_source_rect $rect
        after time 40.0 {sc_move_to 20 32 sc_top_filemgr}
    } elseif {[machine_info time] >= $::sc_deadline} {
        sc_finish "FAIL source Notepad did not expose B.APP"
    } else {
        after time 0.2 sc_wait_moved
    }
}

proc sc_drag_release {} {
    catch {keymatrixup 8 0x80}
    after time 0.10 {keymatrixup 8 0x01; after time 1.5 sc_wait_moved}
}

proc sc_drag_start {} {
    keymatrixdown 8 0x01
    after time 0.12 {keymatrixdown 8 0x80}
    after time 1.35 sc_drag_release
}

proc sc_move_source {} {
    if {![sc_lowram_ready]} { after time 0.002 sc_move_source; return }
    set ::sc_source_slot [peek 0x1351]
    set rect [sc_slot_rect $::sc_source_slot]
    lassign $rect x y w h
    set ::sc_deadline [expr {[machine_info time] + 20.0}]
    sc_move_to [expr {$x + 20}] [expr {$y + 6}] sc_drag_start
}

proc sc_after_copy {} {
    if {![sc_lowram_ready]} { after time 0.002 sc_after_copy; return }
    if {[peek $::sc_type] == 1 && [sc_u16 $::sc_clip_len] == 7 &&
        [sc_clip_text] eq $::sc_text} {
        sc_move_source
    } elseif {[machine_info time] >= $::sc_copy_deadline} {
        sc_finish "FAIL Edit > Copy did not publish typed text"
    } else {
        after time 0.1 sc_after_copy
    }
}

proc sc_copy_source {} {
    set ::sc_copy_deadline [expr {[machine_info time] + 20.0}]
    sc_edit_menu 1 sc_after_copy
}

proc sc_select_source {} {
    # Select All repaints the complete 4 KiB editor body on the 3.58 MHz target.
    # Do not steer the next menu while that focused-window repaint is still live.
    sc_edit_menu 0 {after time 40.0 sc_copy_source}
}

proc sc_wait_typed {} {
    if {![sc_lowram_ready]} {
        after time 0.002 sc_wait_typed
    } elseif {[sc_is_notepad] && [sc_u16 $::sc_len] == 7 &&
        [sc_bytes $::sc_buf 7] eq $::sc_text} {
        # File Manager can finish its asynchronous initial repaint after launch.
        # Explicitly top the source through its exposed title before using its bar.
        set ::sc_deadline [expr {[machine_info time] + 20.0}]
        sc_move_to 40 20 {sc_click {after time 12.0 sc_wait_source_top}}
    } elseif {[machine_info time] >= $::sc_deadline} {
        sc_finish "FAIL source text was not entered"
    } else {
        after time 0.1 sc_wait_typed
    }
}

proc sc_wait_source_top {} {
    if {![sc_lowram_ready]} { after time 0.002 sc_wait_source_top; return }
    if {[peek 0x1351] == $::sc_source_slot} {
        sc_select_source
    } elseif {[machine_info time] >= $::sc_deadline} {
        sc_finish "FAIL source Notepad did not focus"
    } else {
        after time 0.1 sc_wait_source_top
    }
}

proc sc_type_source {} {
    catch {type $::sc_text}
    set ::sc_deadline [expr {[machine_info time] + 20.0}]
    after time 4.0 sc_wait_typed
}

proc sc_wait_source {} {
    if {![sc_lowram_ready]} {
        after time 0.002 sc_wait_source
    } elseif {[peek 0x1350] >= 3 && [sc_is_notepad] && [sc_u16 $::sc_len] == 0} {
        set ::sc_source_slot [peek 0x1351]
        after time 1.0 sc_type_source
    } elseif {[machine_info time] >= $::sc_deadline} {
        sc_finish "FAIL first Notepad did not open empty"
    } else {
        after time 0.1 sc_wait_source
    }
}

proc sc_launch_source {} {
    set ::sc_deadline [expr {[machine_info time] + 30.0}]
    sc_double_click sc_wait_source
}

proc sc_open_drive {} {
    # Root folders occupy row one; A.APP and B.APP are row two cells one/two.
    sc_double_click {after time 4.0 {sc_move_to 16 104 sc_launch_source}}
}

proc sc_start {} {
    # BIOS CALSLT briefly maps ROM over low RAM. Capture its normal primary slot
    # only once the permanent Desktop window table and pointer are readable.
    set candidate [expr {[debug read ioports 0xA8] & 3}]
    if {[peek 0x1350] != 1 || [peek 0x1306] > 127 || [peek 0x1307] > 211} {
        after time 0.002 sc_start
        return
    }
    set ::sc_page0_slot $candidate
    sc_move_to 4 40 sc_open_drive
}

debug set_bp $sc_paste_return {} {sc_paste_return_hit}
debug set_bp $sc_paste_entry {} {sc_paste_entry_hit}
debug set_bp $sc_select_all {} {sc_select_hit}
debug set_bp $sc_copy_sel {} {sc_copy_hit}
after time 62.0 sc_start
