set_host_options -max_cores 8
set top_module ahb_qspi_pads
set report_path $env(SOCLABS_AHB_QSPI_DIR)/imp/ASIC/

set search_path [list . $search_path /research/AAA/phys_ip_library/arm/tsmc/cln65lp/sc12_base_rvt/r0p0/db /home/dwn1c21/SoC-Labs/phys_ip/TSMC/65/CMOS/LP/IO2.5V/iolib/linear/tpdn65lpnv2od3_200a_FE/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tpdn65lpnv2od3_200a]

set target_library "sc12_cln65lp_base_rvt_ss_typical_max_0p90v_125c.db tpdn65lpnv2od3wc1.db"
set link_library "sc12_cln65lp_base_rvt_ss_typical_max_0p90v_125c.db tpdn65lpnv2od3wc1.db"

source $env(SOCLABS_AHB_QSPI_DIR)/imp/ASIC/flist/dc_flist.tcl
analyze -format verilog -lib WORK -define POWER_PINS $env(SOCLABS_AHB_QSPI_DIR)/pad_level/tsmc65nm/ahb_qspi_pads.v
elaborate $top_module
current_design $top_module

link

read_sdc ./ahb_qspi_constraints.sdc

compile_ultra 

write -format verilog -hierarchy -output $env(SOCLABS_AHB_QSPI_DIR)/imp/ASIC/top_ahb_qspi_gates.v
write_sdf -version 2.1 $env(SOCLABS_AHB_QSPI_DIR)/imp/ASIC/top_ahb_qspi.sdf

redirect [format "%s%s%s" $report_path $top_module _area.rep] { report_area }
redirect [format "%s%s%s" $report_path $top_module _power.rep] { report_power }
redirect [format "%s%s%s" $report_path $top_module _timing.rep] \
  { report_timing -path full -max_paths 100 -nets -transition_time -capacitance -significant_digits 3 -nosplit}
