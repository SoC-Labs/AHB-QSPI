#-----------------------------------------------------------------------------
# Post-elaborate, design-scoped app_options. Sourced after a current block
# exists (i.e. after elaborate or open_block). Mirrors the safe-defaults
# pattern from the 28nm reference flow.
#-----------------------------------------------------------------------------

set_app_options -name place.coarse.congestion_driven_max_util -value 0.7
set_app_options -name compile.final_place.placement_congestion_effort -value medium
set_app_options -name compile.initial_opto.placement_congestion_effort -value medium

# NOTE: ICG cells (PREICG_*/ICGT_*) are marked dont_use globally in
# setup.tcl, so they don't reach the netlist — see the comment block
# there for the LEC-driven rationale.
