# Extend the real Desk lifecycle regression with read-only execution probes.
# Input is ordinary S/Desk clicks; never inject application state or guest RAM.
source debug/desk_accessories_openmsx.tcl
set cr_workers 0
set cr_timer_fragments 0
set cr_rim_repairs 0
set cr_seconds_requested 0
set cr_file [open $::env(GEMBENCH_CLOCK_KERNEL_SYMBOLS) r]
foreach line [split [read $cr_file] "\n"] {
    if {[regexp {^([A-Z0-9_]+) #([0-9A-Fa-f]+) } $line -> name value]} {
        set cr_kernel($name) [expr "0x$value"]
    }
}
close $cr_file
set cr_file [open build/universal-obj/uclock/main.sym r]
foreach line [split [read $cr_file] "\n"] {
    if {[regexp {^\s+0\s+(_main|_clock_timer|_draw_face)\s+([0-9A-Fa-f]+)\s} $line -> name value]} {
        set cr_app($name) [expr "0x$value"]
    }
    if {[regexp {^\s+1\s+_show_sec\s+([0-9A-Fa-f]+)\s} $line -> value]} {
        set cr_seconds_offset [expr "0x$value"]
    }
}
close $cr_file
set cr_file [open build/universal-obj/uclock/app.noi r]
foreach line [split [read $cr_file] "\n"] {
    if {[regexp {^DEF s__DATA (0x[0-9A-Fa-f]+)} $line -> value]} {
        set cr_seconds_address [expr {$value + $cr_seconds_offset}]
    }
}
close $cr_file
set cr_base [expr {$da_clock_main - $cr_app(_main)}]

proc cr_worker {} {
    if {[da_sig_loaded $::da_clock_main $::da_clock_sig] && [peek 0x1342] != 0} {
        incr ::cr_workers
    }
    set ::pause off
}
proc cr_fragment {} {
    set source [peek 0xC3CA]
    if {$source & 0x80} {
        if {[peek 0xC1D0] != (($source & 0x7F) - 1)} {
            da_finish "FAIL timer repainted a different window"
        }
        incr ::cr_timer_fragments
    }
    set ::pause off
}
proc cr_rim {} {
    if {[da_sig_loaded $::da_clock_main $::da_clock_sig] && ([peek 0xC3CA] & 0x80)} {
        incr ::cr_rim_repairs
    }
    set ::pause off
}
debug set_bp [expr {$cr_base + $cr_app(_clock_timer)}] {} {cr_worker}
debug set_bp [expr {$cr_base + $cr_app(_draw_face)}] {} {cr_rim}
debug set_bp $cr_kernel(WRA_FRAGMENT) {} {cr_fragment}

# Background line drawing on a 3.58 MHz MSX may outlast the base harness's
# short key pulses. Keep its real-key steering, but allow the longer route.
rename da_move_to cr_move_to
proc da_move_to {x y callback} {
    cr_move_to $x $y $callback
    set ::da_deadline [expr {[machine_info time] + 100.0}]
}

rename da_focus_desktop cr_focus_desktop
# Observe a real unfocused update before Calculator can cover the Clock.
# A fixed one-second delay raced the timer and made missing background evidence
# depend on input timing. Wait for execution, without changing guest state.
proc cr_wait_background {callback} {
    if {$::cr_workers && $::cr_timer_fragments && $::cr_rim_repairs} {
        uplevel #0 $callback
    } elseif {[machine_info time] > $::cr_background_deadline} {
        da_finish "FAIL visible unfocused Clock did not repaint"
    } else {
        after time 0.05 [list cr_wait_background $callback]
    }
}
proc cr_begin_background {callback} {
    set ::cr_background_deadline [expr {[machine_info time] + 20.0}]
    cr_wait_background $callback
}
proc cr_wait_seconds {callback} {
    if {[da_sig_loaded $::da_clock_main $::da_clock_sig] &&
        [peek $::cr_seconds_address]} {
        keymatrixup 5 0x01
        after time 1.0 [list cr_focus_desktop [list cr_begin_background $callback]]
    } elseif {[machine_info time] > $::cr_seconds_deadline} {
        keymatrixup 5 0x01
        da_finish "FAIL Clock did not acknowledge seconds key"
    } else {
        after time 0.05 [list cr_wait_seconds $callback]
    }
}
proc da_focus_desktop {callback} {
    if {!$::cr_seconds_requested} {
        set ::cr_seconds_requested 1
        set ::cr_seconds_deadline [expr {[machine_info time] + 20.0}]
        keymatrixdown 5 0x01
        cr_wait_seconds $callback
    } else { cr_focus_desktop $callback }
}
rename da_finish cr_finish_base
proc da_finish {status} {
    if {$status eq "PASS" && (!$::cr_workers || !$::cr_timer_fragments || !$::cr_rim_repairs)} {
        set status "FAIL missing worker/timer/rim execution evidence"
    }
    set out [open $::env(GEMBENCH_CLOCK_REFERENCE_OUTPUT) w]
    puts $out "STATUS=$status"
    puts $out "WORKER_CALLS=$::cr_workers"
    puts $out "TIMER_SOURCE_FRAGMENTS=$::cr_timer_fragments"
    puts $out "CLIPPED_RIM_REPAIRS=$::cr_rim_repairs"
    puts $out "POINTER=[peek 0x1306],[peek 0x1307] TARGET=$::da_target_x,$::da_target_y"
    close $out
    cr_finish_base $status
}
