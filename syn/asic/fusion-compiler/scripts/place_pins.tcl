#-----------------------------------------------------------------------------
# Port-to-side assignment for top_ahb_qspi as a chip-top partition.
#
# Convention (per partition integration spec):
#   TOP    — external IO (off-chip QSPI flash interface)
#   BOTTOM — system AHB bus (high-bandwidth data path)
#   LEFT   — system APB bus (register access)
#   RIGHT  — clocks, resets, interrupt, debug
#
# Sourced by 1_init_design.tcl AFTER place_memories.tcl and BEFORE the
# pre-compile sanity check. Constraints are attached to the ports via
# set_individual_pin_constraints; the actual pin placement runs later
# inside compile_fusion (or, for visibility into init.design, an
# explicit place_pins call at the end of this script).
#-----------------------------------------------------------------------------

# ── Helpers ────────────────────────────────────────────────────────────────
# Wrap set_individual_pin_constraints with a port-collection guard so
# the call is silently skipped when none of the listed patterns match.
# Side numbering follows fc_shell's set_individual_pin_constraints
# convention: 1 = left, 2 = top, 3 = right, 4 = bottom (starting from
# the left-most vertical edge and going clockwise).
array set SIDE {left 1  top 2  right 3  bottom 4}

proc constrain_pins_on_side {patterns side_name label} {
    global SIDE
    set ports [get_ports -quiet $patterns]
    if {[sizeof_collection $ports] == 0} {
        puts "WARN: \[place_pins\] no ports matched for $label — skipping"
        return
    }
    set side $SIDE($side_name)
    set_individual_pin_constraints -ports $ports -sides $side
    puts "INFO: \[place_pins\] $label : [sizeof_collection $ports] ports -> $side_name (side $side)"
}

# ── TOP — external QSPI flash interface ───────────────────────────────────
constrain_pins_on_side {
    QSPI_SCLK
    QSPI_nCS
    QSPI_IO_o*
    QSPI_IO_i*
    QSPI_IO_e*
} top "QSPI external"

# ── BOTTOM — AHB bus (system data path) ───────────────────────────────────
constrain_pins_on_side {
    HCLK
    HRESETn
    HADDR*
    HTRANS*
    HWRITE
    HSIZE*
    HBURST*
    HPROT*
    HWDATA*
    HSELx
    HRDATA*
    HREADY
    HREADYOUT
    HRESP
} bottom "AHB bus"

# ── LEFT — APB bus (register interface) ───────────────────────────────────
constrain_pins_on_side {
    PCLK
    PRESETn
    PADDR*
    PPROT*
    PSEL
    PENABLE
    PWRITE
    PWDATA*
    PSTRB*
    PRDATA*
    PREADY
    PSLVERR
} left "APB bus"

# ── RIGHT — interrupt, debug, anything else ───────────────────────────────
constrain_pins_on_side {
    IRQ_QSPI_FINISHED
    DBG_XIP_ACTIVE
    DBG_SOFT_RESET
} right "IRQ + debug"

#-----------------------------------------------------------------------------
# Run the pin placer now so the assignments are baked into init.design
# and visible in the GUI. compile_fusion will respect the placed pins.
#-----------------------------------------------------------------------------
puts "INFO: \[place_pins\] running place_pins"
place_pins -ports [get_ports]
