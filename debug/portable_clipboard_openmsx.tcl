# Reuse the read-only parameter/VRAM/stack observer and real Desk input driver.
# No injected calls in this test: the same diagnostic APP executes all cases.
source debug/portable_fs_openmsx.tcl
set scrap_cycles 0
rename fs_window fs_window_filesystem
proc fs_window {} {
    if {$::fs_entered} {
        set value [peek $::fs_state]
        set count [peek [expr {$::fs_state+1}]]
        set shared [peek [expr {$::fs_state+2}]]
        if {$value!=85 || $count!=49+($::scrap_cycles>0) ||
            $shared!=($::scrap_cycles>0) || $::fs_count!=$::fs_restorations} {
            fs_finish "FAIL clipboard cycle=$::scrap_cycles state=$value checks=$count shared=$shared"
        }
        puts stderr "CLIPBOARD cycle=$::scrap_cycles checks=$count shared=$shared"
        incr ::scrap_cycles
        after time 2 {fs_move 13 70 {fs_click scrap_closed}}
    }
    set ::pause off
}
proc scrap_closed {} {
    if {[peek 0x133D]!=1 || [peek 0x3E00]!=6 || [peek 0x3E01]!=0 ||
        [debug read_block memory 0x3E02 6] ne "SHARED"} {
        fs_finish "FAIL clipboard lost across close"
    }
    if {[peek 0x1350]!=1} {fs_finish "FAIL clipboard close/window cleanup"}
    if {$::scrap_cycles==3} {fs_finish PASS; return}
    fs_move 11 4 {fs_click {fs_move 12 14 {fs_click {}}}}
}
