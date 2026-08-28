set throttle off
set pause_on_lost_focus false
set pause off

proc preempt_keep_running {} {
    set ::pause off
    after realtime 0.25 preempt_keep_running
}

after realtime 0.25 preempt_keep_running
set scheduler_samples {}
set scheduler_deadline 0
set scheduler_tick_start 0
array set scheduler_seen {0 0 1 0 2 0}

proc dump_bytes {address count} {
    set bytes {}
    for {set i 0} {$i < $count} {incr i} {
        lappend bytes [format %02X [peek [expr {$address + $i}]]]
    }
    return [join $bytes " "]
}

proc write_scheduler_probe {status} {
    set handle [open "build/msx/preempt-probe.txt" w]
    puts $handle "STATUS=$status"
    puts $handle [format "PC=%04X SP=%04X I=%02X IM=%s" \
        [reg PC] [reg SP] [reg I] [reg IM]]
    puts $handle [format "PPI_A8=%02X" [debug read ioports 0xA8]]
    puts $handle "IM1=[dump_bytes 0x0038 8]"
    puts $handle "LOWRAM=[dump_bytes 0x1340 16]"
    puts $handle "HTIMI=[dump_bytes 0xFD9F 8]"
    puts $handle "GLUE=[dump_bytes 0xC000 48]"
    foreach sample $::scheduler_samples { puts $handle $sample }
    close $handle
}

proc finish_scheduler_probe {status} {
    write_scheduler_probe $status
    exit
}

proc sample_scheduler {} {
    lappend ::scheduler_samples [format \
        "T=%0.3f PC=%04X SP=%04X CUR=%02X Q=%02X RUN=%02X MAX=%02X FAULT=%02X TICK=%02X%02X" \
        [machine_info time] [reg PC] [reg SP] [peek 0x1342] [peek 0x1343] \
        [peek 0x1344] [peek 0x1346] [peek 0x1347] [peek 0xC001] [peek 0xC000]]
    set current [peek 0x1342]
    if {$current >= 0 && $current <= 2} { set ::scheduler_seen($current) 1 }
    set tick [expr {([peek 0xC001] << 8) | [peek 0xC000]}]
    if {[peek 0x1347] != 0} {
        finish_scheduler_probe "FAIL scheduler stack fault"
    }
    if {$::scheduler_seen(0) && $::scheduler_seen(1) && $::scheduler_seen(2) &&
        $tick != $::scheduler_tick_start && [peek 0x1346] > 0 &&
        ([peek 0x1378] & 0x0B) == 0x0B &&
        ([peek 0x1391] & 0x0B) == 0x0B &&
        [llength $::scheduler_samples] >= 6} {
        finish_scheduler_probe PASS
    } elseif {[machine_info time] >= $::scheduler_deadline} {
        finish_scheduler_probe "TIMEOUT waiting for slots 0,1,2"
    } else {
        after time 0.005 sample_scheduler
    }
}

proc wait_scheduler_ready {} {
    if {[peek 0x1344] == 3 && [peek 0x0038] == 0xC3 && [peek 0x003A] >= 0xC9} {
        set ::scheduler_deadline [expr {[machine_info time] + 1.0}]
        set ::scheduler_tick_start [expr {([peek 0xC001] << 8) | [peek 0xC000]}]
        sample_scheduler
    } elseif {[machine_info time] >= 60.0} {
        finish_scheduler_probe "TIMEOUT waiting for preemptive desktop"
    } else {
        after time 0.10 wait_scheduler_ready
    }
}

after time 10.0 wait_scheduler_ready
