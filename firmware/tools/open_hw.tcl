# Open the Vivado Hardware Manager and connect to an hw_server.
#
# Usage (after `source envsetup.sh`):
#   vivado -source open_hw.tcl                          # GUI, hw_server on localhost:3121
#   vivado -source open_hw.tcl -tclargs host:3121       # GUI, remote hw_server
#   vivado -mode tcl -source open_hw.tcl                # Tcl shell, no GUI
#
# If no hw_server is listening at the given URL, Vivado starts a local one.

set hw_url "localhost:3121"
if {[llength $argv] > 0} {
	set hw_url [lindex $argv 0]
}

open_hw_manager

puts "INFO: connecting to hw_server at $hw_url"
if {[catch {connect_hw_server -url $hw_url -allow_non_jtag} err]} {
	puts "ERROR: cannot connect to hw_server at $hw_url: $err"
	return
}

refresh_hw_server
set targets [get_hw_targets -quiet]
if {[llength $targets] == 0} {
	puts "WARNING: hw_server is up but no JTAG targets found (board powered? cable connected?)"
	return
}

puts "INFO: hardware targets: $targets"

# Open the first target only when it is unambiguous; otherwise leave the
# choice to the user (Hardware window in the GUI, or open_hw_target <name>)
if {[llength $targets] == 1} {
	open_hw_target [lindex $targets 0]
	puts "INFO: hardware devices: [get_hw_devices]"
}
