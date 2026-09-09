# Same real Desk driver and read-only return observer; no injected guest calls.
source debug/portable_fs_openmsx.tcl
set page_cycles 0
after time 58 {
    if {[peek 0x1350]!=1} {fs_finish "FAIL data pages desktop baseline"}
    set ::page_baseline [debug read_block memory 0xC220 32]
    set ::page_free_baseline [peek 0xC2E5]
}
rename fs_window fs_window_filesystem
proc fs_window {} {
    if {$::fs_entered} {
        # Only at this actual application registration call is low RAM known
        # to be mapped. Timer callbacks can otherwise observe BIOS ROM there.
        set ::page_primary [expr {[debug read ioports 0xA8]&3}]
        set ::page_secondary [expr {[peek 0xFFFF]&3}]
        set value [peek $::fs_state]
        set count [expr {[peek [expr {$::fs_state+1}]]+256*[peek [expr {$::fs_state+2}]]}]
        set old [peek [expr {$::fs_state+4}]]
        if {$value!=85 || $count<130 || $old!=($::page_cycles>0) || $::fs_count!=$::fs_restorations} {
            fs_finish "FAIL data pages cycle=$::page_cycles state=$value checks=$count old=$old"
        }
        puts stderr "DATA_PAGES cycle=$::page_cycles checks=$count old=$old"
        incr ::page_cycles
        after time 2 {fs_move 13 70 {fs_click page_closed}}
    }
    set ::pause off
}
proc page_closed {} {
    if {([debug read ioports 0xA8]&3)!=$::page_primary ||
        ([peek 0xFFFF]&3)!=$::page_secondary} {
        after time 0.002 page_closed
        return
    }
    if {[peek 0x1350]!=1 || [peek 0xC2E5]!=$::page_free_baseline ||
        [debug read_block memory 0xC220 32] ne $::page_baseline} {
        fs_finish "FAIL data pages teardown: windows=[peek 0x1350] free=[peek 0xC2E5] baseline=$::page_free_baseline"
    }
    if {$::page_cycles==3} {fs_finish PASS; return}
    fs_move 11 4 {fs_click {fs_move 12 14 {fs_click {}}}}
}
