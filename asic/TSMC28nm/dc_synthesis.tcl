set_host_options -max_cores 8
set top_module top_ahb_qspi

set search_path [list . $search_path /home/dwn1c21/SoC-Labs/phys_ip/arm/tsmc/cln28ht/sc12mcpp140z_base_svt_c35/r2p0/db]

set target_library "sc12mcpp140z_cln28ht_base_svt_c35_ssg_cworstt_max_0p81v_125c.db"
set link_library "sc12mcpp140z_cln28ht_base_svt_c35_ssg_cworstt_max_0p81v_125c.db"

source $env(SOCLABS_AHB_QSPI_DIR)/imp/ASIC/flist/dc_flist.tcl
elaborate $top_module
current_design $top_module

link

read_sdc ./ahb_qspi_constraints.sdc

compile_ultra 

write -format verilog -hierarchy -output $env(SOCLABS_AHB_QSPI_DIR)/imp/ASIC/top_ahb_qspi_gates.v
write_sdf -version 2.1 $env(SOCLABS_AHB_QSPI_DIR)/imp/ASIC/top_ahb_qspi.sdf
