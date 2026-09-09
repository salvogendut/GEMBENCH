# Diagnostic only: preserve the existing Clock/Desk actor and its 80 ms clicks.
# Observe input sampling and menu dispatch without changing guest state.
source debug/clock_runtime_openmsx.tcl
set dc_out [open $::env(GEOBENCH_DESK_CLICK_TRACE) {WRONLY CREAT EXCL}]
set dc_until 0
set dc_ring {}
set dc_click 0
proc dc_snapshot {event} {
    set mapped [expr {([debug read ioports 0xA8] & 3) == $::da_page0_slot}]
    set state [list time [machine_info time] event $event click $::dc_click \
        pc [reg PC] a [reg A] d [reg D] primary_matches $mapped \
        ready [da_lowram_ready] mapper0 [debug read ioports 0xFC] \
        slot [peek 0x1342] focus [peek 0x1351] modal [peek 0x1705] \
        x [peek 0x1306] y [peek 0x1307] flags [peek 0x1308] \
        byte [peek 0x14A2] line [peek 0x14A3] \
        fire [peek $::cr_kernel(IN_FIRE)] lastfire [peek $::cr_kernel(POLL_LASTFIRE)] \
        source [peek 0xC3CA]]
    if {[machine_info time] < $::dc_until} {
        puts $::dc_out $state
        flush $::dc_out
    }
    lappend ::dc_ring $state
    set ::dc_ring [lrange $::dc_ring end-19 end]
    set ::pause off
}
rename da_click dc_click_base
proc da_click {callback} {
    incr ::dc_click
    foreach state $::dc_ring {puts $::dc_out $state}
    set ::dc_until [expr {[machine_info time] + 1.0}]
    dc_snapshot [list DOWN $callback]
    dc_click_base $callback
}
rename da_click_up dc_up_base
proc da_click_up {callback} {
    dc_snapshot [list UP $callback]
    dc_up_base $callback
}
rename da_finish dc_finish_base
proc da_finish {status} {
    set ::dc_until [expr {[machine_info time] + 1}]
    dc_snapshot [list FINISH $status]
    close $::dc_out
    dc_finish_base $status
}
foreach {name event} {INPUT_POLL INPUT MENU_DISPATCH MENU WRA_FRAGMENT FRAGMENT} {
    debug set_bp $cr_kernel($name) {} [list dc_snapshot $event]
}
# READ_TRIG is LD IX,nn (4 bytes), CALL msx_bios (3), OR A.
# Check the return instruction before placing a read-only trigger-result hook.
after time 60 {
    set address [expr {$::cr_kernel(READ_TRIG) + 7}]
    if {[peek $address] != 0xB7} {error "READ_TRIG return opcode mismatch"}
    debug set_bp $address {} {dc_snapshot TRIGGER_RETURN}
}
