# Normal System > Settings, real picker selection, close and cold-boot readback.
# The host checks the actual private disk bytes between the two emulator runs.
source debug/desk_accessories_openmsx.tcl
set ss_phase $::env(MSX_SETTINGS_PHASE)
set ss_cfgaddr $::env(MSX_SETTINGS_CFGBUF)
set ss_main $::env(MSX_SETTINGS_MAIN)
set ss_sig [split $::env(MSX_SETTINGS_SIGNATURE) ,]
set ss_deadline 0
set ss_popup_ready 0
debug set_bp 0x801E {} {
    if {[peek 0x1705] && [peek 0x1701] == 34 && [peek 0x1702] == 61} {
        set ::ss_popup_ready 1
    }
    set ::pause off
}

proc da_click {callback} {
    keymatrixdown 8 0x01
    after time 0.30 [list da_click_up $callback]
}
proc da_finish {status} {
    da_release_all
    set out [open $::env(MSX_SETTINGS_RESULT) w]
    puts $out "STATUS=$status"
    puts $out "PHASE=$::ss_phase"
    puts $out "TIME=[machine_info time]"
    puts $out "RAM_MAPPED=[da_lowram_ready]"
    if {[da_lowram_ready]} {
        puts $out "NWIN=[peek 0x1350]"
        puts $out "STACK_FAULT=[peek 0x1347]"
    }
    puts $out "POPUP_READY=$::ss_popup_ready"
    close $out
    exit
}
proc ss_cfg {} { debug read_block memory $::ss_cfgaddr 512 }
proc ss_loaded {} {expr {[da_lowram_ready] && [da_sig_loaded $::ss_main $::ss_sig]}}
proc da_start {} {
    if {[peek 0xCF00] != 48 || [peek 0x1350] != 1 || [peek 0x1310] != 2} {
        after time 0.002 da_start
        return
    }
    set ::da_page0_slot [expr {[debug read ioports 0xA8] & 3}]
    set ::ss_deadline [expr {[machine_info time]+180}]
    da_move_to 22 4 {da_click {da_move_to 24 45 {da_click ss_wait}}}
}
proc ss_wait {} {
    if {[machine_info time] >= $::ss_deadline} {da_finish "FAIL Settings launch"; return}
    if {![ss_loaded] || [peek 0x1350] != 2 || [peek 0x1351] != 1} {
        after time 0.05 ss_wait
        return
    }
    if {$::ss_phase eq "verify"} {
        if {[string first "TITLEBAR=FANCY" [ss_cfg]] < 0} {
            da_finish "FAIL Settings did not reload saved titlebar"
        } else {after time 2 ss_close}
    } else {
        if {[string first "TITLEBAR=ORIGINAL" [ss_cfg]] < 0} {
            after time 0.05 ss_wait
        } else {da_move_to 40 64 {da_click ss_popup}}
    }
}
proc ss_popup {} {
    if {[machine_info time] >= $::ss_deadline} {da_finish "FAIL titlebar picker"; return}
    if {![da_lowram_ready] || !$::ss_popup_ready || ![peek 0x1705] || [peek 0x1701] != 34} {
        after time 0.05 ss_popup
        return
    }
    set count [peek 0x1703]
    set labels [split [debug read_block memory 0x1718 256] "\x00"]
    set selected [lsearch -exact [lrange $labels 0 [expr {$count-1}]] FANCY]
    if {$selected < 0 || $count > 10} {da_finish "FAIL expected FANCY picker row"; return}
    set y [peek 0x1702]
    if {$y+$count*10+4 > 198} {set y [expr {198-$count*10-4}]}
    da_move_to 38 [expr {$y+6+$selected*10}] {da_click ss_saved}
}
proc ss_saved {} {
    if {[machine_info time] >= $::ss_deadline} {da_finish "FAIL titlebar selection"; return}
    if {[ss_loaded] && ![peek 0x1705] && [string first "TITLEBAR=FANCY" [ss_cfg]] >= 0} {
        after time 2 ss_close
    } else {after time 0.05 ss_saved}
}
proc ss_close {} {
    if {![ss_loaded]} {after time 0.002 ss_close; return}
    set entry [da_entry 1]
    da_move_to [expr {[peek [expr {$entry+1}]]+2}] [expr {[peek [expr {$entry+2}]]+4}] {da_click ss_closed}
}
proc ss_closed {} {
    if {[machine_info time] >= $::ss_deadline} {da_finish "FAIL Settings close"; return}
    if {![da_lowram_ready] || [peek 0x1350] != 1} {after time 0.05 ss_closed; return}
    if {[peek 0x1347] != 0} {da_finish "FAIL scheduler stack guard"; return}
    da_finish PASS
}
