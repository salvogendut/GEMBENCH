# Diagnostic variant: open/cancel Desk repeatedly with Clock seconds running.
# The title click remains the base actor's 80 ms; no app/kernel state injection.
source $::env(GEOBENCH_DESK_TRACE_SCRIPT)
set ds_choice 0
set ds_count 0
rename da_choose_accessory ds_accessory_base
proc da_choose_accessory {row callback} {
    set ::ds_choice $row
    ds_accessory_base $row $callback
}
rename da_choose_row ds_row_base
proc da_choose_row {} {
    if {$::ds_choice == 0} {ds_row_base; return}
    incr ::ds_count
    set ::dc_until [expr {[machine_info time]+1}]
    dc_snapshot [list POPUP_OPEN $::ds_count]
    keymatrixdown 7 0x04
    after time 0.08 {keymatrixup 7 0x04}
    after time 0.10 ds_wait_closed
}
proc ds_wait_closed {} {
    if {![da_lowram_ready] || [peek 0x1705]} {
        if {[machine_info time] > $::da_deadline} {da_finish "FAIL Desk cancel timeout"; return}
        after time 0.01 ds_wait_closed
    } elseif {$::ds_count >= 50} {
        da_finish PASS
    } else {
        after time 0.137 {da_choose_accessory 1 da_wait_calculator}
    }
}
