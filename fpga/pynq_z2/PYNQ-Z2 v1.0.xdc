set_property -dict { PACKAGE_PIN W14 IOSTANDARD LVCMOS33 } [get_ports QSPI_nCS_0]; 
set_property -dict { PACKAGE_PIN Y14 IOSTANDARD LVCMOS33 } [get_ports {QSPI_IO_0[0]}]; 
set_property -dict { PACKAGE_PIN T11 IOSTANDARD LVCMOS33 } [get_ports {QSPI_IO_0[1]}]; 
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports QSPI_SCLK_0];
set_property -dict { PACKAGE_PIN W16 IOSTANDARD LVCMOS33 } [get_ports RESET]; 
set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports {QSPI_IO_0[2]}]; 
set_property -dict { PACKAGE_PIN W13 IOSTANDARD LVCMOS33 } [get_ports {QSPI_IO_0[3]}]; 


create_generated_clock -name QSPI_SCLK -source [get_pins {ahb_qspi_i/processing_system7_0/inst/PS7_i/FCLKCLK[0]}] -divide_by 2 [get_pins ahb_qspi_i/AXI_QSPI_0/inst/ahb_qspi_fpga_wrapper_0/inst/u_top_ahb_qspi/u_qspi_clock_div/QSPI_SCLK_i]
create_generated_clock -name QSPI_CLK_o -source [get_pins ahb_qspi_i/AXI_QSPI_0/inst/ahb_qspi_fpga_wrapper_0/inst/u_top_ahb_qspi/u_qspi_clock_div/QSPI_SCLK_i] -divide_by 1 [get_ports QSPI_SCLK_0]

set_input_delay -clock [get_clocks QSPI_SCLK] -min 0  [get_ports {QSPI_IO_0[*]}]
set_input_delay -clock [get_clocks QSPI_SCLK] -max 20 [get_ports {QSPI_IO_0[*]}]

set_output_delay -clock [get_clocks QSPI_CLK_o] -min 0 [get_ports {QSPI_IO_0[*]}]
set_output_delay -clock [get_clocks QSPI_CLK_o] -max 20 [get_ports {QSPI_IO_0[*]}]


