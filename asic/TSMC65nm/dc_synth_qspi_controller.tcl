##-----------------------------------------------------------------------------
## QSPI Controller standalone synthesis - TSMC 65nm
## Used to get baseline area/timing for the SV core only.
##-----------------------------------------------------------------------------
set_host_options -max_cores 8
set top_module qspi_controller
set report_path $env(SOCLABS_AHB_QSPI_DIR)/imp/ASIC/qspi_controller_only/

set search_path [list . $search_path /research/AAA/phys_ip_library/arm/tsmc/cln65lp/sc12_base_rvt/r0p0/db]
set target_library "sc12_cln65lp_base_rvt_ss_typical_max_0p90v_125c.db"
set link_library "* sc12_cln65lp_base_rvt_ss_typical_max_0p90v_125c.db"

define_design_lib WORK -path ./work_qc

analyze -format sverilog -lib WORK \
    $env(SOCLABS_AHB_QSPI_DIR)/logical/qspi_controller/logical/qspi_controller.sv

elaborate $top_module
current_design $top_module
link

## Constraints
set HCLK "HCLK"
set QSPI_SCLK_PERIOD 10
create_clock -name "HCLK"      -period 4  [get_ports HCLK]
create_clock -name "QSPI_SCLK" -period $QSPI_SCLK_PERIOD [get_ports QSPI_SCLK_i]
set_max_fanout 10 [all_inputs]
set_input_delay  1 -clock "QSPI_SCLK" [get_ports QSPI_IO_i[*]]
set_output_delay 1 -clock "QSPI_SCLK" [get_ports QSPI_IO_o[*]]
set_output_delay 1 -clock "QSPI_SCLK" [get_ports QSPI_IO_e[*]]
set_output_delay 1 -clock "QSPI_SCLK" [get_ports QSPI_SCLK]
set_output_delay 1 -clock "QSPI_SCLK" [get_ports QSPI_nCS]

compile_ultra

redirect ${report_path}/${top_module}_area.rep    { report_area -hierarchy }
redirect ${report_path}/${top_module}_power.rep   { report_power -hierarchy }
redirect ${report_path}/${top_module}_timing.rep  { report_timing -path full -max_paths 20 -nets -transition_time -capacitance -significant_digits 3 -nosplit }
redirect ${report_path}/${top_module}_qor.rep     { report_qor }
redirect ${report_path}/${top_module}_refs.rep    { report_reference }
redirect ${report_path}/${top_module}_levels.rep  { report_timing -nworst 10 -max_paths 30 -path full -nets -input_pins }

puts "Synthesis complete. Reports in $report_path"
exit
