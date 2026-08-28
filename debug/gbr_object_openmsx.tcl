# Exercise the shipped File Manager association for HELLO.GBR with real MSX
# keyboard-matrix input.  The build stages the document in the drive root:
# open the first desktop drive, open the first item on the grid's second row,
# then click the resource-defined button and capture the settled Screen 7 frame.

set throttle off
set pause_on_lost_focus false
set pause off

set gbr_output $::env(GEMBENCH_GBR_OUTPUT)
set gbr_screenshot $::env(GEMBENCH_GBR_SCREENSHOT)
set gbr_deadline 0
set gbr_target_x 0
set gbr_target_y 0
set gbr_callback ""
set gbr_drive_x 0
set gbr_drive_y 0
set gbr_resource_x 0
set gbr_resource_y 0
set gbr_button_x 0
set gbr_button_y 0
set gbr_entry_seen 0
set gbr_resource_clicks 0

proc gbr_release_directions {} {
    catch {keymatrixup 8 0x10}
    catch {keymatrixup 8 0x20}
    catch {keymatrixup 8 0x40}
    catch {keymatrixup 8 0x80}
}

proc gbr_finish {status} {
    gbr_release_directions
    catch {keymatrixup 8 0x01}
    set handle [open $::gbr_output w]
    puts $handle "STATUS=$status"
    puts $handle "DRIVE_TARGET=$::gbr_drive_x,$::gbr_drive_y"
    puts $handle "RESOURCE_TARGET=$::gbr_resource_x,$::gbr_resource_y"
    puts $handle "BUTTON_TARGET=$::gbr_button_x,$::gbr_button_y"
    puts $handle "RESOURCE_CLICKS=$::gbr_resource_clicks"
    close $handle
    exit
}

proc gbr_move_tick {} {
    set x [peek 0x1306]
    set y [peek 0x1307]
    gbr_release_directions

    # BIOS calls temporarily map ROM into page 0.  During those brief windows a
    # logical peek does not expose GEMBENCH's low-RAM poll cells; discard such
    # impossible Screen 7 coordinates instead of steering on ROM bytes.
    if {$x > 127 || $y > 211} {
        after time 0.002 gbr_move_tick
        return
    }

    if {[expr {abs($x - $::gbr_target_x)}] <= 1 &&
        [expr {abs($y - $::gbr_target_y)}] <= 3} {
        after time 0.08 $::gbr_callback
        return
    }
    if {[machine_info time] >= $::gbr_deadline} {
        gbr_finish "TIMEOUT moving pointer"
        return
    }

    if {$x < $::gbr_target_x - 1} {
        keymatrixdown 8 0x80
    } elseif {$x > $::gbr_target_x + 1} {
        keymatrixdown 8 0x10
    } elseif {$y < $::gbr_target_y - 3} {
        keymatrixdown 8 0x40
    } else {
        keymatrixdown 8 0x20
    }
    after time 0.025 gbr_move_tick
}

proc gbr_move_to {x y callback} {
    set ::gbr_target_x $x
    set ::gbr_target_y $y
    set ::gbr_callback $callback
    set ::gbr_deadline [expr {[machine_info time] + 15.0}]
    gbr_move_tick
}

proc gbr_click_up_two {callback} {
    keymatrixup 8 0x01
    after time 0.08 $callback
}

proc gbr_click_down_two {callback} {
    keymatrixdown 8 0x01
    after time 0.06 [list gbr_click_up_two $callback]
}

proc gbr_click_up_one {callback} {
    keymatrixup 8 0x01
    after time 0.10 [list gbr_click_down_two $callback]
}

proc gbr_double_click {callback} {
    keymatrixdown 8 0x01
    after time 0.06 [list gbr_click_up_one $callback]
}

proc gbr_single_click {callback delay} {
    keymatrixdown 8 0x01
    after time 0.08 [list gbr_single_click_up $callback $delay]
}

proc gbr_single_click_up {callback delay} {
    keymatrixup 8 0x01
    after time $delay $callback
}

proc gbr_capture {} {
    if {[catch {screenshot -raw $::gbr_screenshot} error]} {
        gbr_finish "FAIL screenshot: $error"
    } else {
        gbr_finish CAPTURED
    }
}

proc gbr_button_release {} {
    keymatrixup 8 0x01
    # Three-window Screen 7 restacking is deliberately observed after the VDP
    # command queue has settled on the reference 3.58 MHz NMS 8250.
    after time 20.0 gbr_capture
}

proc gbr_button_press {} {
    set ::gbr_button_x 64
    set ::gbr_button_y 124
    keymatrixdown 8 0x01
    after time 0.10 gbr_button_release
}

proc gbr_resource_click {} {
    incr ::gbr_resource_clicks
    gbr_single_click gbr_resource_click_check 0.75
}

proc gbr_resource_click_check {} {
    if {$::gbr_entry_seen} {
        after time 12.0 {gbr_move_to 64 124 gbr_button_press}
    } elseif {$::gbr_resource_clicks >= 6} {
        gbr_finish "FAIL GBRDEMO entry was not reached"
    } else {
        gbr_resource_click
    }
}

proc gbr_open_resource_first_click {} {
    set ::gbr_resource_x [peek 0x1306]
    set ::gbr_resource_y [peek 0x1307]
    # File Manager's drag-aware click path needs a longer release interval than
    # the desktop icon path, still safely within its 75-frame double-click span.
    set ::gbr_entry_seen 0
    set ::gbr_resource_clicks 0
    debug set_bp 0x4000 {} {set ::gbr_entry_seen 1; set ::pause off}
    gbr_resource_click
}

proc gbr_open_resource {} {
    # FILEMGR.APP: x=4, y=26; content x=8, y=40.  HELLO.GBR is the
    # first cell on row two after the DIAG, GBENCH, and PICS folders.
    gbr_move_to 16 104 gbr_open_resource_first_click
}

proc gbr_open_drive {} {
    set ::gbr_drive_x [peek 0x1306]
    set ::gbr_drive_y [peek 0x1307]
    gbr_double_click {after time 4.0 gbr_open_resource}
}

# This Nextor image reaches the GEMBENCH desktop after roughly 50 emulated
# seconds on the reference NMS 8250.  The first drive icon then occupies byte
# columns 0..7 and lines 20..63.
after time 62.0 {gbr_move_to 4 40 gbr_open_drive}
