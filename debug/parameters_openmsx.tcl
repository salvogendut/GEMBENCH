# First run the real Desk/Clock/Calculator workflow. Then intercept the next
# root application GB_PARAMS entry, exercise the real loaded service, restore
# the intercepted machine state, and leave ordinary execution intact. These
# injected calls are boundary tests, not evidence of a successful UI gesture.
source debug/desk_accessories_openmsx.tcl
rename da_finish da_finish_base
set pp_armed 0
set pp_count 0
set pp_workers 0
set pp_root_draws 0
set pp_cases {}
proc da_finish {status} {
    if {$status ne "PASS"} { da_finish_base $status; return }
    set ::pp_armed 1
    after time 5 {if {$::pp_armed == 1} {da_finish_base "FAIL no root parameter callback"}}
}

proc pp_record {op data {version 1}} {
    set result [list $op $version {*}$data]
    while {[llength $result] < 16} {lappend result 0}
    return $result
}
proc pp_add {name record status {value 0} {pointer 0x7EE0} {size 16} {writes {}} {worker 0}} {
    lappend ::pp_cases [list $name $record $status $value $pointer $size $writes $worker]
}
proc pp_hook {} {
    set op [peek [reg HL]]
    if {[peek 0x1342] != 0 && $op == 3} {incr ::pp_workers}
    if {[peek 0x1342] == 0 && $op in {1 2}} {incr ::pp_root_draws}
    if {$::pp_armed == 1 && [peek 0x1342] == 0} {
        set ::pp_armed 2
        if {[catch {pp_begin} message]} {da_finish_base "FAIL parameter setup: $message"}
    }
    set ::pause off
}
set pp_bp [debug set_bp 0x80D5 {} pp_hook]

proc pp_begin {} {
    debug remove_bp $::pp_bp
    if {[peek 0xCF2D] != 1 || !([peek 0xCF20] & 0x80)} {error "ABI 2.1 not published"}
    set ::pp_regs [debug read_block "CPU regs" 0 28]
    set ::pp_sp [reg SP]
    set ::pp_stack [debug read_block memory [expr {$::pp_sp - 256}] 256]
    set ::pp_app [debug read_block memory 0x7E80 128]
    set ::pp_guard [debug read_block memory 0x7F00 256]
    set ::pp_vram [debug read_block VRAM 0 131072]
    set ::pp_bank [peek 0x134F]
    set ::pp_mapper [debug read ioports 0xFD]
    set ::pp_current [peek 0x1342]
    set ::pp_lock [peek 0x1340]
    set ::pp_timer [debug read_block memory 0xC3CA 6]
    set ::pp_drop [peek 0xC1EC]
    set ::pp_drop_gen [peek 0xC03F]
    set ::pp_code [debug read_block memory 0x0400 [expr {$::env(GEOBENCH_PARAMETER_CODE_END) - 0x0400}]]
    set own -1
    set other -1
    for {set slot 0} {$slot < 8} {incr slot} {
        set entry [expr {0x1352 + 25 * $slot}]
        if {([peek [expr {$entry + 13}]] & 1) == 0} {continue}
        if {[peek $entry] == $::pp_bank} {set own $slot} else {set other $slot}
    }
    if {$own < 0 || $other < 0} {error "need own and foreign live windows"}
    set slot [expr {$own + 1}]
    set gen [peek [expr {0xC358 + $own}]]
    set stale [expr {$gen == 255 ? 1 : $gen + 1}]
    set handle [list $slot $gen]
    set busy [pp_record 6 {}]
    foreach pointer {0 0x3FFF 0x7EF1 0x7F00 0xC000 0xFFF8} {
        pp_add "record-pointer-$pointer" $busy 1 0 $pointer
    }
    foreach size {0 15 17 256 65535} {pp_add "record-size-$size" $busy 1 0 0x7EE0 $size}
    pp_add record-exact-end $busy 0 0 0x7EF0
    pp_add version [pp_record 6 {} 2] 6
    pp_add operation [pp_record 8 {}] 6
    pp_add line-outside [pp_record 1 {0 2 10 0 20 0 10 0 3}] 1
    pp_add line-y-outside [pp_record 1 {10 0 212 0 20 0 10 0 3}] 1
    pp_add line-pen [pp_record 1 {10 0 10 0 20 0 10 0 4}] 1
    pp_add text-overflow [pp_record 2 {10 10 1 0 255 255 2}] 1
    pp_add text-snapshot [pp_record 2 {10 10 1 0 255 126 2}] 1
    pp_add text-low [pp_record 2 {10 10 1 0 255 63 2}] 1
    pp_add text-too-long [pp_record 2 {10 10 1 0 128 126 49}] 1
    pp_add text-empty [pp_record 2 {10 10 1 0 0 0 0}] 0
    pp_add timer-zero [pp_record 3 {0 0 1 10 2 3}] 3
    pp_add timer-stale [pp_record 3 [list $slot $stale 1 10 2 3]] 3
    pp_add timer-foreign [pp_record 3 [list [expr {$other+1}] [peek [expr {0xC358+$other}]] 1 10 2 3]] 4
    pp_add timer-empty [pp_record 3 [list {*}$handle 1 10 0 3]] 1
    pp_add timer-outside [pp_record 3 [list {*}$handle 127 10 2 3]] 1
    pp_add timer-overflow [pp_record 3 [list {*}$handle 255 10 2 3]] 1
    set publish [pp_record 3 [list {*}$handle 1 10 2 3]]
    set cancel [pp_record 7 $handle]
    pp_add publish $publish 0 1
    pp_add coalesce $publish 5
    pp_add busy $busy 0 1
    pp_add pending-not-active [pp_record 4 $handle] 0
    pp_add cancel $cancel 0
    pp_add idle $busy 0
    pp_add active [pp_record 4 $handle] 0 1 0x7EE0 16 [list 0xC3CA [expr {$slot|0x80}]]
    pp_add cancel-keeps-active $cancel 0
    pp_add still-active $busy 0 1
    pp_add drop-stale [pp_record 5 $handle] 0 0 0x7EE0 16 [list 0xC3CA 0 0xC1EC $slot 0xC03F $stale]
    pp_add drop-valid [pp_record 5 $handle] 0 1 0x7EE0 16 [list 0xC03F $gen]
    pp_add drop-cleared [pp_record 5 $handle] 0
    pp_add worker-draw [pp_record 1 {10 0 10 0 20 0 10 0 3}] 2 0 0x7EE0 16 {} 1
    pp_add worker-publish $publish 0 1 0x7EE0 16 {} 1
    pp_add worker-cancel $cancel 0 0 0x7EE0 16 {} 1
    # Positive rendering is covered by the normal UI above. These exercise
    # exact-end and maximum-length text with no terminator in the source span.
    pp_add text-exact-end [pp_record 2 {10 10 1 0 254 126 2}] 0 0 0x7EE0 16 {0x7EFE 65 0x7EFF 66}
    pp_add text-maximum [pp_record 2 {10 10 1 0 128 126 48}] 0
    set ::pp_original_cases $::pp_cases
    set ::pp_iff 0
    set ::pp_return_bp [debug set_bp 0x03FF {} {if {[catch {pp_return} message]} {da_finish_base "FAIL parameters: $message"}; set ::pause off}]
    pp_round
}
proc pp_round {} {
    poke 0xC3CA 0
    poke 0xC1EC 0
    for {set i 0} {$i < 48} {incr i} {poke [expr {0x7E80+$i}] 65}
    set ::pp_cases $::pp_original_cases
    pp_next
}
proc pp_next {} {
    if {[llength $::pp_cases] == 0} {
        if {$::pp_iff == 0} {set ::pp_iff 3; pp_round; return}
        pp_finish
        return
    }
    set ::pp_case [lindex $::pp_cases 0]
    set ::pp_cases [lrange $::pp_cases 1 end]
    lassign $::pp_case name record status value pointer size writes worker
    # Invalid pointer cases never write into the invalid address under test.
    set destination [expr {$pointer == 0x7EF0 ? $pointer : 0x7EE0}]
    foreach byte $record {poke $destination $byte; incr destination}
    foreach {address byte} $writes {poke $address $byte}
    poke 0x1342 $worker
    poke 0x1340 [expr {$::pp_iff == 0 ? 0 : 1}]
    set ::pp_case_lock [peek 0x1340]
    set ::pp_before_vram [debug read_block VRAM 0 131072]
    set ::pp_canary [expr {$::pp_sp - 128}]
    for {set i 0} {$i < 8} {incr i} {poke [expr {$::pp_canary+$i}] 0xA5}
    reg SP [expr {$::pp_sp - 2}]
    poke [reg SP] 0xFF
    poke [expr {[reg SP]+1}] 3
    reg HL $pointer
    reg BC $size
    reg IFF $::pp_iff
    reg PC 0x80D5
}
proc pp_return {} {
    lassign $::pp_case name record status value pointer size writes worker
    if {[reg A] != $status || [reg E] != $value} {
        error "$name IFF=$::pp_iff returned [reg A]/[reg E], expected $status/$value"
    }
    if {[reg SP] != $::pp_sp || ([reg IFF] & 3) != $::pp_iff ||
        [peek 0x134F] != $::pp_bank || [debug read ioports 0xFD] != $::pp_mapper ||
        [peek 0x1340] != $::pp_case_lock} {error "$name changed SP/IFF/bank/lock"}
    for {set i 0} {$i < 8} {incr i} {
        if {[peek [expr {$::pp_canary+$i}]] != 0xA5} {error "$name stack canary"}
    }
    if {[debug read_block memory 0x7F00 256] ne $::pp_guard} {error "$name app snapshot guard"}
    if {$status != 0 && [debug read_block VRAM 0 131072] ne $::pp_before_vram} {
        error "$name rejection changed VRAM"
    }
    incr ::pp_count
    pp_next
}
proc pp_finish {} {
    if {[debug read_block memory 0x0400 [string length $::pp_code]] ne $::pp_code} {error "module code corrupted"}
    debug remove_bp $::pp_return_bp
    debug write_block memory [expr {$::pp_sp-256}] $::pp_stack
    debug write_block memory 0x7E80 $::pp_app
    debug write_block memory 0xC3CA $::pp_timer
    debug write_block VRAM 0 $::pp_vram
    poke 0xC1EC $::pp_drop
    poke 0xC03F $::pp_drop_gen
    poke 0x1342 $::pp_current
    poke 0x1340 $::pp_lock
    debug write_block "CPU regs" 0 $::pp_regs
    if {$::pp_workers == 0 || $::pp_root_draws == 0} {error "missing real worker/root calls"}
    puts stderr "PARAMETERS_PASS cases=$::pp_count real_worker_calls=$::pp_workers root_draws=$::pp_root_draws"
    da_finish_base PASS
}
