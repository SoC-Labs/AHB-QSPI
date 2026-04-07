##-----------------------------------------------------------------------------
## AHB QSPI Core Synthesis - TSMC 65nm
## Targets top_ahb_qspi (no IO pads)
##-----------------------------------------------------------------------------

set_host_options -max_cores 8
set top_module top_ahb_qspi
set report_path $env(SOCLABS_AHB_QSPI_DIR)/imp/ASIC/

## Library setup - standard cells only (no IO pads)
set search_path [list . $search_path /research/AAA/phys_ip_library/arm/tsmc/cln65lp/sc12_base_rvt/r0p0/db]
set target_library "sc12_cln65lp_base_rvt_ss_typical_max_0p90v_125c.db"
set link_library "* sc12_cln65lp_base_rvt_ss_typical_max_0p90v_125c.db"

## Include path for CG092 IP
set CG092_VLOG_DIR $env(ARM_IP_LIBRARY_PATH)/CG092/CG092-BU-50000-r2p0-00rel0/p_flash_cache_f0/logical/p_flash_cache_f0/verilog

define_design_lib WORK -path ./work

##-----------------------------------------------------------------------------
## Read ARM CG092 Flash Cache IP
##-----------------------------------------------------------------------------
analyze -format verilog -lib WORK [list \
    $CG092_VLOG_DIR/p_flash_cache_f0_bus_logic.v \
    $CG092_VLOG_DIR/p_flash_cache_f0_mrb.v \
    $CG092_VLOG_DIR/p_flash_cache_f0_core.v \
    $CG092_VLOG_DIR/p_flash_cache_f0.v \
    $CG092_VLOG_DIR/p_flash_cache_f0_reg_block.v \
] -define {POWER_PINS}

## CG092 generic models
analyze -format verilog -lib WORK [list \
    $env(ARM_IP_LIBRARY_PATH)/CG092/CG092-BU-50000-r2p0-00rel0/p_flash_cache_f0/logical/models/cells/generic/p_flash_cache_f0_capt_sync.v \
    $env(ARM_IP_LIBRARY_PATH)/CG092/CG092-BU-50000-r2p0-00rel0/p_flash_cache_f0/logical/models/cells/generic/cdc_capt_sync.v \
    $env(ARM_IP_LIBRARY_PATH)/CG092/CG092-BU-50000-r2p0-00rel0/p_flash_cache_f0/logical/models/modules/generic/p_flash_cache_f0_static_reg.v \
    $env(ARM_IP_LIBRARY_PATH)/CG092/CG092-BU-50000-r2p0-00rel0/p_flash_cache_f0/logical/models/modules/generic/static_reg.v \
]

## CG092 generic RAM model
analyze -format verilog -lib WORK \
    $env(ARM_IP_LIBRARY_PATH)/CG092/CG092-BU-50000-r2p0-00rel0/p_flash_cache_f0/logical/testbench/execution_tb/verilog/p_flash_cache_f0_sp_ram.v

##-----------------------------------------------------------------------------
## Read Corstone-101 IP
##-----------------------------------------------------------------------------
analyze -format verilog -lib WORK \
    $env(ARM_IP_LIBRARY_PATH)/latest/Corstone-101/logical/cmsdk_apb_slave_mux/verilog/cmsdk_apb_slave_mux.v

##-----------------------------------------------------------------------------
## Read AHB QSPI RTL (Verilog)
##-----------------------------------------------------------------------------
analyze -format verilog -lib WORK [list \
    $env(SOCLABS_AHB_QSPI_DIR)/logical/top_ahb_qspi/logical/top_ahb_qspi.v \
    $env(SOCLABS_AHB_QSPI_DIR)/logical/apb_qspi_regs/logical/apb_qspi_regs.v \
    $env(SOCLABS_AHB_QSPI_DIR)/logical/qspi_controller/logical/qspi_controller_mux.v \
    $env(SOCLABS_AHB_QSPI_DIR)/logical/qspi_controller/logical/qspi_clock_div.v \
    $env(SOCLABS_AHB_QSPI_DIR)/logical/cache_subsytem/logical/cache_subsystem.v \
    $env(SOCLABS_AHB_QSPI_DIR)/logical/cache_models/generic/cache_ram.v \
]

##-----------------------------------------------------------------------------
## Read AHB QSPI RTL (SystemVerilog)
##-----------------------------------------------------------------------------
analyze -format sverilog -lib WORK [list \
    $env(SOCLABS_AHB_QSPI_DIR)/logical/ahb_qspi_interface/logical/ahb_qspi_interface.sv \
    $env(SOCLABS_AHB_QSPI_DIR)/logical/qspi_controller/logical/qspi_controller.sv \
]

##-----------------------------------------------------------------------------
## Elaborate and link
##-----------------------------------------------------------------------------
elaborate $top_module
current_design $top_module
link

##-----------------------------------------------------------------------------
## Constraints
##-----------------------------------------------------------------------------
set HCLK "HCLK"
set PCLK "PCLK"
set HCLK_PERIOD 10
set PCLK_PERIOD 10

create_clock -name "$HCLK" -period $HCLK_PERIOD [get_ports HCLK]
create_clock -name "$PCLK" -period $PCLK_PERIOD [get_ports PCLK]
create_generated_clock -name "QSPI_SCLK" -source [get_ports HCLK] -divide_by 2 [get_pins u_qspi_clock_div/QSPI_SCLK_i]

set_max_fanout 10 [all_inputs]

set_input_delay  1 -clock "QSPI_SCLK" [get_ports QSPI_IO_i[*]]
set_output_delay 1 -clock "QSPI_SCLK" [get_ports QSPI_IO_o[*]]
set_output_delay 1 -clock "QSPI_SCLK" [get_ports QSPI_IO_e[*]]
set_output_delay 1 -clock "QSPI_SCLK" [get_ports QSPI_SCLK]
set_output_delay 1 -clock "QSPI_SCLK" [get_ports QSPI_nCS]

##-----------------------------------------------------------------------------
## Synthesize
##-----------------------------------------------------------------------------
compile_ultra

##-----------------------------------------------------------------------------
## Write outputs
##-----------------------------------------------------------------------------
write -format verilog -hierarchy -output ${report_path}/${top_module}_gates.v
write_sdf -version 2.1 ${report_path}/${top_module}.sdf

##-----------------------------------------------------------------------------
## Reports
##-----------------------------------------------------------------------------
redirect [format "%s%s%s" $report_path $top_module "_area.rep"]    { report_area -hierarchy }
redirect [format "%s%s%s" $report_path $top_module "_power.rep"]   { report_power -hierarchy }
redirect [format "%s%s%s" $report_path $top_module "_timing.rep"]  \
  { report_timing -path full -max_paths 20 -nets -transition_time -capacitance -significant_digits 3 -nosplit }
redirect [format "%s%s%s" $report_path $top_module "_qor.rep"]    { report_qor }

puts "Synthesis complete. Reports written to $report_path"
exit
