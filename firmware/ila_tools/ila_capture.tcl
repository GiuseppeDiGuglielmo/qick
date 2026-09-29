# Host side of the NN ILA capture (Vivado batch). Args: hw_server ltx outdir shots rdir
# For each shot: arm the ILA on a rising edge of probe1 (the trigger NN_0 sees),
# tell the board to fire (ssh touch go_<i>), wait for the capture, save it as CSV.
lassign $argv hw_url ltx outdir shots rdir
set remote xilinx@rfsoc216-ml01.dhcp.fnal.gov

proc rexists {path} {
    global remote
    return [expr {[catch {exec ssh $remote test -f $path < /dev/null}] == 0}]
}

proc wait_remote {path secs} {
    for {set t 0} {$t < $secs * 10} {incr t} {
        if {[rexists $path]} { return 1 }
        after 100
    }
    return 0
}

puts "CAP waiting for the board to load the bitstream"
if {![wait_remote $rdir/ready 300]} { puts "CAP ERROR board not ready"; exit 1 }

open_hw_manager
connect_hw_server -url $hw_url -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices xczu49dr_0] 0]
current_hw_device $dev
set_property PROBES.FILE $ltx $dev
set_property FULL_PROBES.FILE $ltx $dev
refresh_hw_device $dev

set ila [lindex [get_hw_ilas -of_objects $dev] 0]
puts "CAP ILA $ila depth [get_property CONTROL.DATA_DEPTH $ila]"
foreach p [get_hw_probes -of_objects $ila] { puts "CAP probe $p width [get_property WIDTH $p]" }
set trig [get_hw_probes -of_objects $ila -filter {NAME =~ *probe1_1*}]
puts "CAP trigger probe $trig"

set_property CONTROL.TRIGGER_CONDITION AND $ila
set_property CONTROL.TRIGGER_POSITION 512 $ila
set_property TRIGGER_COMPARE_VALUE {eq1'bR} $trig

for {set i 0} {$i < $shots} {incr i} {
    run_hw_ila $ila
    after 300
    exec ssh $remote touch $rdir/go_$i < /dev/null
    if {[catch {wait_on_hw_ila -timeout 1 $ila} err]} {
        puts "CAP shot $i: no trigger ($err)"
    } else {
        set data [upload_hw_ila_data $ila]
        write_hw_ila_data -force -csv_file $outdir/shot_$i.csv $data
        puts "CAP shot $i: captured"
    }
    if {![wait_remote $rdir/done_$i 60]} { puts "CAP ERROR board did not finish shot $i"; break }
}
close_hw_target
disconnect_hw_server
puts "CAP finished"
