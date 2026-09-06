# Native TASKDEMO workers never yield. The focused worker may starve the lower
# visibility tier by existing policy; do not require round-robin across tiers.
# This is IRQ switching evidence, not fault injection or CPC hardware evidence.
set throttle off
set pause_on_lost_focus false
set pause off
set ci_switches 0
set ci_returns 0
set ci_root_choices 0
set ci_worker_choices 0
set ci_chain 0
set ci_tick -1
set ci_max 0
set ci_file [open $::env(GEOBENCH_CONTEXT_SYMBOLS) r]
foreach line [split [read $ci_file] "\n"] {
    if {[regexp {^(\w+) #([0-9A-Fa-f]+) } $line -> name value]} {
        set ci($name) [expr "0x$value"]
    }
}
close $ci_file

proc ci_finish {status} {
    set out [open $::env(GEOBENCH_CONTEXT_OUTPUT) w]
    puts $out "STATUS=$status"
    foreach key {switches returns root_choices worker_choices chain max} {
        puts $out "[string toupper $key]=[set ::ci_$key]"
    }
    puts $out "STACK_FAULT=[peek $::ci(SCHED_FAULT)]"
    close $out
    exit
}
proc ci_ready {} {
    expr {[peek $::ci(SCHED_RUNNABLE)] == 3 && [peek 0x0038] == 0xC3 &&
          [peek16 0x0039] == $::ci(SCHED_IRQ_VECTOR)}
}
proc ci_check {} {
    if {![ci_ready]} {set ::pause off; return}
    set sp [reg SP]
    set top [peek16 $::ci(BOOT_SP)]
    set depth [expr {$top-$sp}]
    if {$depth < 0 || $depth > 255 || [peek $::ci(SCHED_FAULT)] != 0} {
        ci_finish "FAIL fixed stack SP=$sp top=$top"
    }
    if {$depth > $::ci_max} {set ::ci_max $depth}
    set mapper [debug read ioports 0xFD]
    set bank [peek $::ci(BANK_CUR)]
    # The fixed 512-KiB runner decodes five segment bits. Unimplemented port
    # bits read high; they are not part of DOS's logical segment identifier.
    if {$bank > 31 || ($mapper & 31) != $bank} {
        ci_finish "FAIL mapper/shadow mismatch: port=$mapper shadow=$bank"
    }
    set tick [peek16 $::ci(MSX_TICK)]
    if {$::ci_tick < 0} {set ::ci_tick $tick}
    if {$::ci_switches >= 8 && $::ci_returns >= 8 && $::ci_root_choices >= 8 &&
        $::ci_worker_choices >= 8 && $::ci_chain >= 8 && $tick != $::ci_tick} {
        ci_finish PASS
    }
    set ::pause off
}
debug set_bp $ci(SCHED_IRQ_SWITCH) {} {
    if {[ci_ready]} {incr ::ci_switches}
    ci_check
}
debug set_bp $ci(SCHED_IRQ_RESTORE) {} {
    if {[ci_ready]} {incr ::ci_returns}
    ci_check
}
debug set_bp $ci(SCHED_RESTORE_SLOT) {} {
    if {[ci_ready]} {
        if {[reg C] == 0 && [peek $::ci(SCHED_RESERVED)] == 1} {incr ::ci_root_choices}
        if {[reg C] == [peek $::ci(WM_FOCUS)] && [reg C] != 0} {incr ::ci_worker_choices}
    }
    # This entry is on the temporary stack, not the fixed task stack.
    set ::pause off
}
debug set_bp $ci(SCHED_IRQ_CHAIN) {} {
    if {[ci_ready]} {incr ::ci_chain}
    ci_check
}
after time 120 {ci_finish "TIMEOUT waiting for real IRQ context switches"}
