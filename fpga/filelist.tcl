###-----------------------------------------------------------------------------
### AHB QSPI Subsystem - Vivado Filelist
### A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
###
### Contributors
###
### David Mapstone (d.a.mapstone@soton.ac.uk)
###
### Copyright (C) 2026, SoC Labs (www.soclabs.org)
###-----------------------------------------------------------------------------
### RTL source manifest for IP packaging. Mirrors the content of
### flist/Top/ahb_QSPI.flist with Vivado TCL syntax.
###
### Required environment variables:
###   SOCLABS_AHB_QSPI_DIR - Root of ahb_qspi repository
###   ARM_IP_LIBRARY_PATH  - Root of ARM IP library (for CG092 and Corstone-101)
###-----------------------------------------------------------------------------

set QSPI_HOME $env(SOCLABS_AHB_QSPI_DIR)
set ARM_IP    $env(ARM_IP_LIBRARY_PATH)

# CG092 Flash Cache include dir
set CG092_DIR $ARM_IP/CG092/CG092-BU-50000-r2p0-00rel0/p_flash_cache_f0/logical/p_flash_cache_f0/verilog

set_property include_dirs [list $CG092_DIR] [current_fileset]

read_verilog [list \
    $QSPI_HOME/logical/top_ahb_qspi/logical/top_ahb_qspi.v \
    $QSPI_HOME/logical/apb_qspi_regs/logical/apb_qspi_regs.v \
    $QSPI_HOME/logical/qspi_controller/logical/qspi_controller_mux.v \
    $QSPI_HOME/logical/qspi_controller/logical/qspi_clock_div.v \
    $QSPI_HOME/logical/cache_subsytem/logical/cache_subsystem.v \
    $QSPI_HOME/logical/cache_models/generic/cache_ram.v \
    $CG092_DIR/p_flash_cache_f0_bus_logic.v \
    $CG092_DIR/p_flash_cache_f0_mrb.v \
    $CG092_DIR/p_flash_cache_f0_core.v \
    $CG092_DIR/p_flash_cache_f0.v \
    $CG092_DIR/p_flash_cache_f0_reg_block.v \
    $ARM_IP/CG092/CG092-BU-50000-r2p0-00rel0/p_flash_cache_f0/logical/models/cells/generic/p_flash_cache_f0_capt_sync.v \
    $ARM_IP/CG092/CG092-BU-50000-r2p0-00rel0/p_flash_cache_f0/logical/models/cells/generic/cdc_capt_sync.v \
    $ARM_IP/CG092/CG092-BU-50000-r2p0-00rel0/p_flash_cache_f0/logical/models/modules/generic/p_flash_cache_f0_static_reg.v \
    $ARM_IP/CG092/CG092-BU-50000-r2p0-00rel0/p_flash_cache_f0/logical/models/modules/generic/static_reg.v \
    $ARM_IP/CG092/CG092-BU-50000-r2p0-00rel0/p_flash_cache_f0/logical/testbench/execution_tb/verilog/p_flash_cache_f0_sp_ram.v \
    $ARM_IP/latest/Corstone-101/logical/cmsdk_apb_slave_mux/verilog/cmsdk_apb_slave_mux.v \
]

read_verilog -sv [list \
    $QSPI_HOME/logical/qspi_controller/logical/qspi_controller.sv \
    $QSPI_HOME/logical/ahb_qspi_interface/logical/ahb_qspi_interface.sv \
]
