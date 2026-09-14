# Same real input / stream / exact-return observers, but execute compiled code
# in the sealed bank and check its C model's persistent 4-KiB state.
source debug/portable_launch_openmsx.tcl
proc fs_window {} {
    if {$::fs_entered} {
        set ::page_primary [expr {[debug read ioports 0xA8]&3}]
        set ::page_secondary [expr {[peek 0xFFFF]&3}]
        set value [peek $::fs_state]
        set count [peek [expr {$::fs_state+1}]]
        if {$value!=85 || $count!=54 || $::fs_count!=$::fs_restorations} {
            fs_finish "FAIL computation cycle=$::page_cycles state=$value checks=$count calls=$::fs_count"
        }
        puts stderr "COMPUTE cycle=$::page_cycles checks=$count"
        set owner [peek 0x21D0]
        set seal [expr {0x2180+8*($owner-1)}]
        launch_check [expr {$owner>0 && $owner<=8 && [peek $seal]==[peek 0x21D1] &&
            [debug read_block memory [expr {$seal+1}] 6] eq [debug read_block memory 0x21D2 6]}] live_seal
        set ::compute_seals [debug read_block memory 0x2180 64]
        incr ::page_cycles
        after time 2 compute_alive
    }
    set ::pause off
}
proc compute_alive {} {
    if {([debug read ioports 0xA8]&3)!=$::page_primary ||
        ([peek 0xFFFF]&3)!=$::page_secondary} {
        after time 0.002 compute_alive
        return
    }
    launch_check [expr {[debug read_block memory 0x2180 64] eq $::compute_seals}] seal_survives_ui
    fs_move 13 70 {fs_click page_closed}
}
rename page_closed compute_page_closed_parent
proc page_closed {} {
    if {([debug read ioports 0xA8]&3)==$::page_primary &&
        ([peek 0xFFFF]&3)==$::page_secondary} {
        launch_check [expr {[debug read_block memory 0x2180 64] eq [string repeat \x00 64]}] seals_reclaimed
        launch_check [expr {[peek 0x21C0]==0}] call_idle
    }
    compute_page_closed_parent
}
rename launch_rejected compute_launch_rejected_parent
proc launch_rejected {} {
    if {[peek 0x403]==71 && [peek 0x404]==66} {
        launch_check [expr {[debug read_block memory 0x2180 64] eq [string repeat \x00 64]}] rejected_seals
        launch_check [expr {[peek 0x21C0]==0}] rejected_call_idle
    }
    compute_launch_rejected_parent
}
