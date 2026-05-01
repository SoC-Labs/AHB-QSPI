###-----------------------------------------------------------------------------
### AHB QSPI Subsystem - JTAG Bitstream Programming Script
### A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
###
### Contributors
###
### David Mapstone (d.a.mapstone@soton.ac.uk)
###
### Copyright (C) 2026, SoC Labs (www.soclabs.org)
###-----------------------------------------------------------------------------
### Programs the Pynq-Z2 PL via Vivado Hardware Manager. Requires the board's
### micro-USB connected to this host.
###
### Usage:
###   vivado -mode batch -source program_bitstream.tcl -tclargs <bitfile>
###-----------------------------------------------------------------------------

set bitfile [lindex $argv 0]
if { ![file exists $bitfile] } {
    puts "ERROR: bitfile not found: $bitfile"
    exit 1
}

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target

set device [lindex [get_hw_devices xc7z020_1] 0]
current_hw_device $device
refresh_hw_device $device

set_property PROGRAM.FILE $bitfile $device
program_hw_devices $device
refresh_hw_device $device

close_hw_manager
puts "Programmed $bitfile via JTAG."
