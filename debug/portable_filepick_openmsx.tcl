# Real Desk/click workflow; the shared observer also checks every FS return.
source debug/portable_fs_openmsx.tcl
rename fs_window fs_window_unused
proc fs_window {} {set ::pause off}
set pick_object $::env(GEOBENCH_PICK_OBJECT)
set pick_text $::env(GEOBENCH_PICK_TEXT)
set pick_stage 0
set pick_wait 0
set pick_cases {
    {{0 5 1 0 2 6 3 1 4 0 5 0 10 0} /DOCUI {} 26 119}
    {{0 5 2 6 3 0 5 6} {} {} 11 119}
    {{0 5 2 6 3 1 5 0} {} {} 11 64}
    {{0 5 2 0 3 0} /DOCUI/EMPTY {} 39 119}
    {{0 5 2 6 3 1} /DOCUI {} 11 54}
    {{0 5 2 1 3 0} /DOCUI/DIR {} 11 54}
    {{0 7 4 0 8 42 9 0 10 2} /DOCUI/DIR {HELLO   TXT} 21 4}
    {{0 5 1 1 2 6 3 1 10 0} /DOCUI {} 11 74}
    {{0 5 1 1 4 0 10 0} {} {} 11 148}
    {{0 7 1 1 4 0 10 3} /DOCUI {FILE00  TXT} 12 4}
    {{0 5 1 0 2 6 10 0} {} {} 55 119}
    {{0 8 4 0 10 0} {} {} 12 4}
    {{0 5 1 0 2 6 10 0} {} {} 6 24}
}
proc pick_read_string {at n} {
    return [lindex [split [debug read_block memory $at $n] \x00] 0]
}
proc pick_tick {} {
    if {$::pick_stage == [llength $::pick_cases]} {
        if {[peek 0x1350]!=1} {fs_finish "FAIL chooser close"}
        for {set i 0} {$i<4} {incr i} {
            if {[peek [expr {0xC600+144*$i}]]} {fs_finish "FAIL chooser leaked context"}
        }
        fs_finish PASS; return
    }
    lassign [lindex $::pick_cases $::pick_stage] fields path name x y
    set valid [expr {[peek 0x1350]==2 && [peek 0x1351]==1}]
    foreach {offset expected} $fields {
        if {[peek [expr {$::fs_state+$offset}]]!=$expected} {set valid 0}
    }
    if {!$valid} {
        incr ::pick_wait
        if {$::pick_wait>300} {
            fs_finish "FAIL chooser stage=$::pick_stage state=[debug read_block memory $::fs_state 12]"
        }
        after time 0.2 pick_tick; return
    }
    if {[peek [expr {$::fs_state+11}]]!=85} {fs_finish "FAIL chooser document guard"}
    if {$path ne "" && [pick_read_string [expr {$::pick_object+17}] 48] ne $path} {
        fs_finish "FAIL chooser path stage=$::pick_stage"
    }
    if {$name ne "" && [debug read_block memory [expr {$::pick_object+65}] 11] ne $name} {
        fs_finish "FAIL chooser name stage=$::pick_stage"
    }
    if {$::pick_stage==6 && [debug read_block memory [expr {$::pick_text+1}] 42] ne
            "Chosen through the portable file dialog.\r\n"} {fs_finish "FAIL chooser readback"}
    puts stderr "CHOOSER stage=$::pick_stage PASS"
    # Renderer-none runs still qualify the exact VRAM preservation of every FS
    # call. A screenshot is additional evidence when a renderer is available.
    catch {screenshot -raw [file join [file dirname $::fs_output] "chooser-$::pick_stage.png"]}
    incr ::pick_stage;set ::pick_wait 0
    fs_move $x $y {fs_click {after time 1 pick_tick}}
}
after time 65 pick_tick
