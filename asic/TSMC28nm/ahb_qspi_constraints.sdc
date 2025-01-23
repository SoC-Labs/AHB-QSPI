
set HCLK "HCLK"
set PCLK "PCLK"

set HCLK_PERIOD 10
set PCLK_PERIOD 10

create_clock -name "$HCLK" -period $HCLK_PERIOD [get_ports HCLK]
create_clock -name "$PCLK" -period $PCLK_PERIOD [get_ports PCLK]
create_generated_clock -name "QSPI_SCLK" -source [get_ports HCLK] -divide_by 2 [get_pins u_qspi_controller/u_qspi_clock_div/QSPI_SCLK_i]
set_max_fanout 10 [all_inputs]
