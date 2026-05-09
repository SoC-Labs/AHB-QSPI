#-----------------------------------------------------------------------------
# Common pre-elaborate setup — sourced at the start of every stage script,
# right after the design library is opened. ONLY global-scoped options go
# here; design-scoped app_options must wait until after elaborate (where a
# current block exists), and live in scripts/setup_design_options.tcl.
#-----------------------------------------------------------------------------

set_host_options -max_cores 8 -num_processes 8

# ── Power-domain nets (single-domain partition; chip-top adds VDDIO/VDDACC)
set PG_NETS    [list VDD VSS]
set CORE_VOLTAGE 1.08

# Block clock-gate cell usage. fc_shell U-2022.12 inserts PREICG/ICGT
# cells aggressively (the cache_subsystem RTL has many enable patterns
# the synth recognises and gates), and the emitted SVF doesn't carry
# the per-CG match guidance Formality needs to absorb the gate's
# enable latch into the downstream DFF cone. Marking these cells
# dont_use here — at global scope, before any compile or check — keeps
# them out of the netlist so LEC verifies cleanly. Done in setup.tcl
# rather than setup_design_options.tcl so the attribute lands at
# library scope, before init/elaborate. Cost: higher dynamic power on
# the cache + interface registers — re-enable (and add proper
# SVF/`set_user_match` guidance) once the partition is being closed
# for real silicon.
set _icg_cells [get_lib_cells -quiet [list */PREICG_* */ICGT_*]]
if {[sizeof_collection $_icg_cells] > 0} {
    set_attribute $_icg_cells dont_use true
    puts "INFO: \[setup\] [sizeof_collection $_icg_cells] ICG lib_cells marked dont_use"
}
