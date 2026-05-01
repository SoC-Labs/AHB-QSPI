#-----------------------------------------------------------------------------
# AHB QSPI Subsystem - Pynq-Z2 Pin Constraints
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# PmodSF3 (Diligent QSPI flash) connected to PMODA on Pynq-Z2 v1.0.
#
# PmodSF3 standard QSPI pinout (Type 4A):
#   Pin 1 = CS#       Pin 7 = WP#  / DQ2
#   Pin 2 = MOSI/DQ0  Pin 8 = HOLD#/ DQ3
#   Pin 3 = MISO/DQ1  Pin 9 = unused
#   Pin 4 = SCK       Pin 10 = unused
#
# Pynq-Z2 v1.0 PMODA pin map:
#   JA1=Y18  JA2=Y19  JA3=Y16  JA4=Y17
#   JA7=U18  JA8=U19  JA9=W18  JA10=W19
#-----------------------------------------------------------------------------

set_property -dict { PACKAGE_PIN Y18 IOSTANDARD LVCMOS33 } [get_ports qspi_cs_n]    ;# JA1 -> CS#
set_property -dict { PACKAGE_PIN Y19 IOSTANDARD LVCMOS33 } [get_ports {qspi_io[0]}] ;# JA2 -> DQ0 (MOSI)
set_property -dict { PACKAGE_PIN Y16 IOSTANDARD LVCMOS33 } [get_ports {qspi_io[1]}] ;# JA3 -> DQ1 (MISO)
set_property -dict { PACKAGE_PIN Y17 IOSTANDARD LVCMOS33 } [get_ports qspi_sclk]    ;# JA4 -> SCK
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports {qspi_io[2]}] ;# JA7 -> DQ2 (WP#)
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports {qspi_io[3]}] ;# JA8 -> DQ3 (HOLD#)

# Board LEDs (accent green, accent active-high)
set_property -dict { PACKAGE_PIN R14 IOSTANDARD LVCMOS33 } [get_ports led0] ;# LD0 - SPI CS active
set_property -dict { PACKAGE_PIN P14 IOSTANDARD LVCMOS33 } [get_ports led1] ;# LD1 - SPI clock activity
set_property -dict { PACKAGE_PIN N16 IOSTANDARD LVCMOS33 } [get_ports led2] ;# LD2 - IRQ (transaction done)
set_property -dict { PACKAGE_PIN M14 IOSTANDARD LVCMOS33 } [get_ports led3] ;# LD3 - reserved
