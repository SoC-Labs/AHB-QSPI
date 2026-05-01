#-----------------------------------------------------------------------------
# AHB QSPI Subsystem - Pynq-Z2 Timing Constraints (implementation-only)
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Timing constraints applied during implementation only. The clk_wiz output
# clock isn't visible during synthesis, so applying these in synth fires
# CRITICAL WARNING 12-4739 ("No valid object(s) found").
#-----------------------------------------------------------------------------

# QSPI_SCLK is divided down from HCLK inside qspi_clock_div. With the cocotb
# default CLK_DIV=5, QSPI_SCLK = HCLK/10 = 5 MHz. Define a generated clock
# on the divider output and on the pad output.
create_generated_clock -name qspi_sclk_int \
    -source [get_pins {qspi_design_i/qspi_design_i/qspi_ip_0/inst/u_top_ahb_qspi/u_qspi_clock_div/HCLK}] \
    -divide_by 2 \
    [get_pins {qspi_design_i/qspi_design_i/qspi_ip_0/inst/u_top_ahb_qspi/u_qspi_clock_div/QSPI_SCLK_i}]

create_generated_clock -name qspi_sclk_pad \
    -source [get_pins {qspi_design_i/qspi_design_i/qspi_ip_0/inst/u_top_ahb_qspi/u_qspi_clock_div/QSPI_SCLK_i}] \
    -divide_by 1 \
    [get_ports qspi_sclk]

# PmodSF3 IO timing budget (conservative; SCK is divided down so plenty of
# margin even with PCB lengths). Tighten later if needed.
set_input_delay  -clock [get_clocks qspi_sclk_pad] -min  0.0 [get_ports {qspi_io[*]}]
set_input_delay  -clock [get_clocks qspi_sclk_pad] -max 20.0 [get_ports {qspi_io[*]}]
set_output_delay -clock [get_clocks qspi_sclk_pad] -min  0.0 [get_ports {qspi_io[*]}]
set_output_delay -clock [get_clocks qspi_sclk_pad] -max 20.0 [get_ports {qspi_io[*]}]

# CS# is asynchronous w.r.t. SCLK at the pad - just a slow control line.
set_false_path -to [get_ports qspi_cs_n]

# LEDs are human-visible, no timing path needed
set_false_path -to [get_ports {led0 led1 led2 led3}]
