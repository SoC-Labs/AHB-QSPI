#-----------------------------------------------------------------------------
# AHB QSPI — partition-level SDC overlay.
#
# The shared FC.read_design.tcl already creates the AHB system clock
# ($CLK_NAME = HCLK @ $CLK_PERIOD = 4 ns) and applies all_inputs/
# all_outputs I/O delays excluding HCLK / HRESETn / PCLK / PRESETn.
# This file adds the second boundary clock (PCLK), the divided-by-2
# generated QSPI_SCLK that the controller uses to drive the flash, and
# tightens the QSPI-port I/O delays against QSPI_SCLK.
#
# Read into every active scenario by 1_init_design.tcl.
#-----------------------------------------------------------------------------

# ── APB peripheral clock (functionally async to HCLK) ─────────────────────
# Same period as HCLK in the reference baseline; bump independently here
# if the chip-top APB plan diverges.
set PCLK_PERIOD 4.0
create_clock -name PCLK -period $PCLK_PERIOD \
    -waveform "0 [expr {$PCLK_PERIOD / 2.0}]" [get_ports PCLK]

# ── Generated QSPI serial clock — HCLK divided by 2 inside the controller
# (qspi_clock_div). Matches dc_synthesis_core.tcl's create_generated_clock.
create_generated_clock -name QSPI_SCLK \
    -source [get_ports HCLK] -divide_by 2 \
    [get_pins u_qspi_clock_div/QSPI_SCLK_i]

# ── Async clock groups ────────────────────────────────────────────────────
# HCLK + PCLK come from independent dividers/PLL outputs at the chip-top;
# QSPI_SCLK is generated from HCLK but the flash-side timing closure
# treats it as an independent domain (DDR-ish I/O), so group it
# separately. CDC between AHB↔APB is already synchronised in RTL.
set_clock_groups -asynchronous \
    -group {HCLK QSPI_SCLK} \
    -group {PCLK}

# Async resets — already declared as false_path in the shared script;
# nothing to add here.

# ── Boundary I/O delays for the new clock domains ─────────────────────────
set pclk_io_delay [expr {$PCLK_PERIOD * 0.25}]

# APB-side ports — apply input/output delays against PCLK.
set apb_inputs  [list PADDR* PPROT* PSEL PENABLE PWRITE PWDATA* PSTRB*]
set apb_outputs [list PRDATA* PREADY PSLVERR]

foreach pat $apb_inputs {
    set p [get_ports $pat]
    if {[sizeof_collection $p] > 0} {
        set_input_delay -clock PCLK $pclk_io_delay $p
    }
}
foreach pat $apb_outputs {
    set p [get_ports $pat]
    if {[sizeof_collection $p] > 0} {
        set_output_delay -clock PCLK $pclk_io_delay $p
    }
}

# ── QSPI flash interface — clocked by QSPI_SCLK (1 ns I/O delay matches
# the dc_synthesis_core baseline; tighten once the flash device's
# tCO/tSU spec is finalised). -add_delay so the existing HCLK-domain
# defaults from the shared script aren't dropped on the same ports.
set qspi_io_delay 1.0

foreach pat {QSPI_IO_i*} {
    set p [get_ports $pat]
    if {[sizeof_collection $p] > 0} {
        set_input_delay -clock QSPI_SCLK $qspi_io_delay $p -add_delay
    }
}
foreach pat {QSPI_IO_o* QSPI_IO_e* QSPI_SCLK QSPI_nCS} {
    set p [get_ports $pat]
    if {[sizeof_collection $p] > 0} {
        set_output_delay -clock QSPI_SCLK $qspi_io_delay $p -add_delay
    }
}
