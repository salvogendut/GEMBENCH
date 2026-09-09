# Real keyboard/Desk launch of a disposable CLOCK.APP alias. Read-only hooks.
set throttle off
set speed 9999
set fs_count 0
set fs_entered 0
set fs_restorations 0
set fs_state $::env(GEOBENCH_FS_STATE)
set fs_output $::env(GEOBENCH_FS_OUTPUT)
set fs_operation [expr {[info exists ::env(GEOBENCH_FS_OPERATION)] ? $::env(GEOBENCH_FS_OPERATION) : 8}]
proc fs_finish {status} {
    set f [open $::fs_output w]
    puts $f "STATUS=$status"
    puts $f "PARAMETER_CALLS=$::fs_count"
    puts $f "RESTORATION_CHECKS=$::fs_restorations"
    close $f
    exit
}
proc fs_parameters {} {
    # This CPU address also exists in ROM during Nextor boot/slot calls. Only
    # observe the actual resident GB_PARAMS jump vector, never an unrelated ROM
    # instruction with an incidental operation byte at HL.
    if {[peek 0xCF00]!=48 || [peek 0xCF01]!=6 ||
        [peek 0x80D5]!=195 || [peek 0x80D6]!=8 || [peek 0x80D7]!=4} {
        if {[info exists ::env(GEOBENCH_TRACE_FS)] && [peek [reg HL]]==$::fs_operation} {
            puts stderr "IGNORED non-kernel PC=80D5 vector=[peek 0x80D5],[peek 0x80D6],[peek 0x80D7] sysinfo=[peek 0xCF00],[peek 0xCF01] slot=[debug read ioports 0xA8]"
        }
        set ::pause off; return
    }
    if {[peek [reg HL]]==$::fs_operation} {
        if {[info exists ::env(GEOBENCH_TRACE_FS)]} {
            puts stderr "FS_ENTRY windowcount=[peek 0x1350] focus=[peek 0x1351] PC=[reg PC] HL=[reg HL] SP=[reg SP] return=[peek [reg SP]],[peek [expr {[reg SP]+1}]]"
        }
        incr ::fs_count; set ::fs_entered 1
        set ::fs_sp [reg SP]
        set ::fs_iff [expr {[reg IFF]&3}]
        set ::fs_bank [peek 0x134F]
        set ::fs_mapper [debug read ioports 0xFD]
        set ::fs_lock [peek 0x1340]
        set ::fs_guard [debug read_block memory 0x7F00 256]
        set ::fs_slot [debug read ioports 0xA8]
        if {[info exists ::env(GEOBENCH_TRACE_FS)]} {
            set ::fs_trace_count 0
            set ::fs_trace_watch [debug set_watchpoint write_mem {0x7F00 0x7FFF} {} fs_trace_guard]
        }
        set ::fs_vram [debug read_block VRAM 0 131072]
        set return_pc [expr {[peek $::fs_sp] + 256*[peek [expr {$::fs_sp+1}]]}]
        # The continuation is in banked page 1. Nextor ROM may execute the
        # SAME numeric PC while the service is still running: wait for the
        # caller's slot/mapper as well as its PC. A missing real return still
        # fails the workload timeout; none of the preservation checks is waived.
        set ::fs_return_bp [debug set_bp $return_pc {
            [debug read ioports 0xA8]==$::fs_slot && [debug read ioports 0xFD]==$::fs_mapper
        } fs_returned]
    }
    set ::pause off
}
proc fs_returned {} {
    debug remove_bp $::fs_return_bp
    if {[info exists ::fs_trace_watch]} {
        debug remove_watchpoint $::fs_trace_watch
        unset ::fs_trace_watch
    }
    if {[reg SP]!=$::fs_sp+2 || ([reg IFF]&3)!=$::fs_iff ||
        [peek 0x134F]!=$::fs_bank || [debug read ioports 0xFD]!=$::fs_mapper ||
        [peek 0x1340]!=$::fs_lock} {fs_finish "FAIL caller restoration"}
    if {[debug read_block memory 0x7F00 256] ne $::fs_guard} {
        binary scan $::fs_guard cu* before
        binary scan [debug read_block memory 0x7F00 256] cu* after
        for {set i 0} {$i<256} {incr i} {
            if {[lindex $before $i]!=[lindex $after $i]} {
                puts stderr "SNAPSHOT offset=$i before=[lindex $before $i] after=[lindex $after $i] SP=$::fs_sp bank=$::fs_bank lock=$::fs_lock"
            }
        }
        puts stderr "SLOTS before=$::fs_slot after=[debug read ioports 0xA8] mapper=$::fs_mapper PAGE_DATA=[peek 0xC020]"
        fs_finish "FAIL snapshot guard"
    }
    if {[debug read_block VRAM 0 131072] ne $::fs_vram} {fs_finish "FAIL parameter service changed pixels"}
    incr ::fs_restorations
    set ::pause off
}
proc fs_trace_guard {} {
    if {[debug read ioports 0xFD]==$::fs_mapper && $::fs_trace_count<8} {
        incr ::fs_trace_count
        puts stderr "GUARD_WRITE PC=[reg PC] HL=[reg HL] DE=[reg DE] BC=[reg BC] IX=[reg IX] IY=[reg IY] BANK=[peek 0x134F] MAPPER=[debug read ioports 0xFD] SLOT=[debug read ioports 0xA8]"
    }
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
after time [expr {[info exists ::env(GEOBENCH_FS_DEADLINE)] ? $::env(GEOBENCH_FS_DEADLINE) : 180}] {
    fs_finish "FAIL timeout entered=$::fs_entered calls=$::fs_count"
}
