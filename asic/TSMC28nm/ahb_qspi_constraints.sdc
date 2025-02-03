
set HCLK "HCLK"
set PCLK "PCLK"

set HCLK_PERIOD 10
set PCLK_PERIOD 10

create_clock -name "$HCLK" -period $HCLK_PERIOD [get_ports HCLK]
create_clock -name "$PCLK" -period $PCLK_PERIOD [get_ports PCLK]
create_generated_clock -name "QSPI_SCLK" -source [get_ports HCLK] -divide_by 2 [get_pins u_qspi_controller/u_qspi_clock_div/QSPI_SCLK_i]
create_generated_clock -name "QSPI_SCLK_o" -source [get_pins u_qspi_controller/u_qspi_clock_div/QSPI_SCLK_i] -divide_by 1 [get_ports QSPI_SCLK]


set_max_fanout 10 [all_inputs]

set_input_delay  1 -clock "QSPI_SCLK_o" [get_ports QSPI_IO_i[*]]
set_output_delay 1 -clock "QSPI_SCLK_o" [get_ports QSPI_IO_e[*]]
set_output_delay 1 -clock "QSPI_SCLK_o" [get_ports QSPI_IO_o[*]]
set_output_delay 1 -clock "QSPI_SCLK_o" [get_ports QSPI_nCS]