###-----------------------------------------------------------------------------
### AHB QSPI Subsystem - Vivado IP Packaging Script
### A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
###
### Contributors
###
### David Mapstone (d.a.mapstone@soton.ac.uk)
###
### Copyright (C) 2026, SoC Labs (www.soclabs.org)
###-----------------------------------------------------------------------------
### Packages qspi_vivado_wrapper as a Vivado IP with properly defined bus
### interfaces (AHB-Lite slave, APB slave, clock/reset, interrupt) for use in
### the Vivado IP Integrator.
###
### Required environment variables:
###   FPGA_COMPONENT_FILELIST - Path to TCL filelist for source files
###   FPGA_COMPONENT_LIB      - Output directory for packaged IP
###   FPGA_VENDOR             - IP vendor string (e.g. soclabs.org)
###   FPGA_CORE_REV           - IP core revision number
###-----------------------------------------------------------------------------

set component_lib $env(FPGA_COMPONENT_LIB)

# STEP 0: Read in design sources
source $env(FPGA_COMPONENT_FILELIST)

# Add the wrapper source file
set wrapper_dir [file dirname [info script]]
read_verilog $wrapper_dir/qspi_vivado_wrapper.v

set_property top qspi_vivado_wrapper [current_fileset]
update_compile_order -fileset sources_1

# STEP 1: Package the project as IP
ipx::package_project -root_dir $component_lib \
    -vendor $env(FPGA_VENDOR) \
    -library user \
    -taxonomy /UserIP \
    -import_files \
    -set_current false \
    -force \
    -force_update_compile_order

ipx::unload_core $component_lib/component.xml
ipx::edit_ip_in_project -upgrade true \
    -name tmp_edit_project \
    -directory $component_lib \
    $component_lib/component.xml

update_compile_order -fileset sources_1

# STEP 2: Core metadata
set core [ipx::current_core]

set_property display_name    "AHB QSPI Subsystem (XiP + APB config)" $core
set_property description     "SoC Labs QSPI flash controller with AHB-Lite XiP read path, APB register config, Arm CG092 flash cache, and QPI support. PmodSF3-compatible." $core
set_property vendor_display_name "SoC Labs" $core
set_property company_url     "https://www.soclabs.org" $core
set_property core_revision   $env(FPGA_CORE_REV) $core
set_property supported_families {
    zynq       Production
    zynquplus  Production
    artix7     Production
    kintex7    Production
    spartan7   Production
    virtex7    Production
} $core

set_property ipi_drc {ignore_freq_hz true} $core

# STEP 3: Let IPI auto-infer the AHB, APB, clock, reset and interrupt bus
# interfaces from the X_INTERFACE_INFO attributes on the wrapper — don't
# strip them.
ipx::merge_project_changes -verbose files $core

# STEP 3.5: Define memory maps for the two slave interfaces so IPI can
# assign addresses. Without these, validate_bd_design fails with
# "addressable slave interface without an associated memory map".

# AHB slave - 16 MB XiP window (covers SPI_ADDR[21:0])
ipx::add_memory_map S_AHB $core
set_property slave_memory_map_ref S_AHB \
    [ipx::get_bus_interfaces S_AHB -of_objects $core]
ipx::add_address_block Reg \
    [ipx::get_memory_maps S_AHB -of_objects $core]
set_property range  16777216 \
    [ipx::get_address_blocks Reg \
        -of_objects [ipx::get_memory_maps S_AHB -of_objects $core]]
set_property width  32 \
    [ipx::get_address_blocks Reg \
        -of_objects [ipx::get_memory_maps S_AHB -of_objects $core]]

# APB slave - 64 KB register window (covers PADDR[15:0] + cache regs at 0x1000)
ipx::add_memory_map apb_interface $core
set_property slave_memory_map_ref apb_interface \
    [ipx::get_bus_interfaces apb_interface -of_objects $core]
ipx::add_address_block Reg \
    [ipx::get_memory_maps apb_interface -of_objects $core]
set_property range  65536 \
    [ipx::get_address_blocks Reg \
        -of_objects [ipx::get_memory_maps apb_interface -of_objects $core]]
set_property width  32 \
    [ipx::get_address_blocks Reg \
        -of_objects [ipx::get_memory_maps apb_interface -of_objects $core]]

# STEP 4: Finalize
ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::check_integrity $core

ipx::save_core $core
ipx::check_integrity -quiet -xrt $core
ipx::move_temp_component_back -component $core
close_project

update_ip_catalog
close_project

puts "==========================================="
puts " AHB QSPI IP packaged successfully"
puts " Output: $component_lib"
puts "==========================================="
