# Real keyboard/Desk launch of a disposable CLOCK.APP alias. Read-only hooks.
set throttle off
set speed 9999
set fs_count 0
set fs_entered 0
set fs_restorations 0
set fs_state $::env(GEOBENCH_FS_STATE)
set fs_output $::env(GEOBENCH_FS_OUTPUT)
proc fs_finish {status} {
    set f [open $::fs_output w]
    puts $f "STATUS=$status"
    puts $f "PARAMETER_CALLS=$::fs_count"
    puts $f "RESTORATION_CHECKS=$::fs_restorations"
    close $f
    exit
}
proc fs_parameters {} {
    if {[peek [reg HL]]==8} {
        incr ::fs_count; set ::fs_entered 1
        set ::fs_sp [reg SP]
        set ::fs_iff [expr {[reg IFF]&3}]
        set ::fs_bank [peek 0x134F]
        set ::fs_mapper [debug read ioports 0xFD]
        set ::fs_lock [peek 0x1340]
        set ::fs_guard [debug read_block memory 0x7F00 256]
        set ::fs_vram [debug read_block VRAM 0 131072]
        set return_pc [expr {[peek $::fs_sp] + 256*[peek [expr {$::fs_sp+1}]]}]
        set ::fs_return_bp [debug set_bp $return_pc {} fs_returned]
    }
    set ::pause off
}
proc fs_returned {} {
    debug remove_bp $::fs_return_bp
    if {[reg SP]!=$::fs_sp+2 || ([reg IFF]&3)!=$::fs_iff ||
        [peek 0x134F]!=$::fs_bank || [debug read ioports 0xFD]!=$::fs_mapper ||
        [peek 0x1340]!=$::fs_lock} {fs_finish "FAIL caller restoration"}
    if {[debug read_block memory 0x7F00 256] ne $::fs_guard} {fs_finish "FAIL snapshot guard"}
    if {[debug read_block VRAM 0 131072] ne $::fs_vram} {fs_finish "FAIL filesystem changed pixels"}
    incr ::fs_restorations
    set ::pause off
}
proc fs_window {} {
    if {$::fs_entered} {
        set value [peek $::fs_state]
        set count [peek [expr {$::fs_state+1}]]
        if {$value!=85 || $count!=46 || $::fs_count!=$::fs_restorations} {
            fs_finish "FAIL state=$value checks=$count restorations=$::fs_restorations"
        }
        for {set i 0} {$i<4} {incr i} {
            if {[peek [expr {0xC600+144*$i}]]} {fs_finish "FAIL leaked context"}
        }
        set ::fs_done 1
        after time 2 {fs_finish PASS}
    }
    set ::pause off
}
debug set_bp 0x80D5 {} fs_parameters
debug set_bp 0x80B1 {} fs_window
proc fs_move {x y callback} {
    set ::fs_x $x; set ::fs_y $y; set ::fs_callback $callback
    fs_move_tick
}
proc fs_move_tick {} {
    foreach mask {0x10 0x20 0x40 0x80} {catch {keymatrixup 8 $mask}}
    set x [peek 0x1306]; set y [peek 0x1307]
    if {abs($x-$::fs_x)<=1 && abs($y-$::fs_y)<=2} {
        after time 0.15 $::fs_callback
        return
    }
    if {$x<$::fs_x-1} {set mask 0x80} elseif {$x>$::fs_x+1} {set mask 0x10} \
    elseif {$y<$::fs_y-2} {set mask 0x40} else {set mask 0x20}
    keymatrixdown 8 $mask
    after time 0.08 [list keymatrixup 8 $mask]
    after time 0.16 fs_move_tick
}
proc fs_click {callback} {
    keymatrixdown 8 0x01
    after time 0.08 {keymatrixup 8 0x01}
    after time 0.9 $callback
}
after time 60 {fs_move 11 4 {fs_click {fs_move 12 14 {fs_click {}}}}}
after time 180 {fs_finish "FAIL timeout entered=$::fs_entered calls=$::fs_count"}
