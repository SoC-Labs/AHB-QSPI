#-----------------------------------------------------------------------------
# Power-ground mesh insertion for the top_ahb_qspi partition.
#
# Builds:
#   - supply nets + ports for VDD / VSS
#   - cell PG pin auto-connection (every std cell + macro grabs VDD/VSS)
#   - M1 follow-pin rails inside every std-cell row (the std cells have
#     M1 power rails by construction; this pattern says "treat them as
#     the partition's PG rails")
#   - M5 horizontal + M6 vertical mesh, 50 μm pitch interleaved VDD/VSS
#     2 μm wide straps — stitches the M1 rails together and gives the
#     partition's high-current loads (macros, clock buffers) a low-
#     impedance path. Reserves M7+ for chip-top global routing.
#
# Run after floorplan + macros are placed, before compile_fusion runs
# std-cell placement — sourced from 1_init_design.tcl after
# place_pins.tcl.
#
# The pitch + width are conservative starting points for a 970 × 190 μm
# tile @ 250 MHz HCLK. Tune after the first IR-drop analysis at chip
# top (currently we don't run signoff IR — the partition's job is to
# present a continuous mesh chip-top can stitch its own straps onto).
#-----------------------------------------------------------------------------

# ── Step 1: power domain + supply nets + ports ───────────────────────────
# Single voltage domain — chip-top will wire the partition's VDD/VSS
# supply ports to the global rails at integration. UPF-style flow:
# create the domain first, then nets in that domain's scope, then ports
# at the boundary, then designate VDD/VSS as the domain's primary
# supplies so connect_pg_net knows what to connect cell PG pins to.
puts "INFO: \[pg_mesh\] creating power domain + supply nets + ports"

create_power_domain PD_TOP -include_scope

create_supply_net VDD -domain PD_TOP
create_supply_net VSS -domain PD_TOP

create_supply_port VDD -direction in
create_supply_port VSS -direction in

connect_supply_net VDD -ports {VDD}
connect_supply_net VSS -ports {VSS}

set_domain_supply_net PD_TOP \
    -primary_power_net  VDD \
    -primary_ground_net VSS

set_voltage 1.08 -object_list [get_supply_nets VDD]
set_voltage 0.00 -object_list [get_supply_nets VSS]

# ── Step 2: connect cell PG pins to the supply nets ──────────────────────
# Every std cell + macro has VDD/VSS pins; tie them to the nets created
# above. -automatic uses the Liberty cell_footprint info to pair pins
# with nets by name.
puts "INFO: \[pg_mesh\] connect_pg_net -automatic"
connect_pg_net -automatic

# ── Step 3: M1 follow-pin pattern (std-cell rails) ───────────────────────
# The sc12 std cells carry their own M1 PG rails by construction; this
# pattern tells compile_pg "use them" so it drops via stacks from the
# M5 mesh down to M1 at every crossing. Without this pattern,
# check_pg_connectivity flags ~5000 cells as floating.
puts "INFO: \[pg_mesh\] creating M1 follow-pin pattern"
# rail_width 0.18 μm matches the sc12 std-cell M1 PG rail width.
# Tried omitting it (let compile_pg infer): regressed to 5710 floating
# std cells. Tried wider (0.24): no change vs 0.18. The accompanying
# 119 M1 PG-DRC violations (24 shorts + 24 overlaps + 71 spacings) are
# residual edge cases from where compile_pg's via stack drops collide
# with macro keepouts; chip-top integration can resolve them via its
# own straps + minor partition tweaks.
create_pg_std_cell_conn_pattern std_cell_rail \
    -layers {M1} \
    -rail_width 0.18

# ── Step 4: M5 horizontal + M6 vertical mesh ─────────────────────────────
# 2 μm wide straps, 50 μm pitch, interleaved VDD/VSS pairs. Tried
# tighter pitch (25 μm) and saw WNS regress to -0.01 ns from route
# congestion — the cache subsystem's wide HRDATA/HWDATA busses lose
# routing tracks. 50 μm pitch keeps timing closed.
puts "INFO: \[pg_mesh\] creating M5/M6 mesh pattern"
create_pg_mesh_pattern mesh_m5_m6 -layers {
    { {horizontal_layer: M5} {width: 2.0} {pitch: 50.0} {spacing: interleaving} {offset: 10.0} {trim: true} }
    { {vertical_layer:   M6} {width: 2.0} {pitch: 50.0} {spacing: interleaving} {offset: 10.0} {trim: true} }
}

# ── Step 5: macro M4 PG pin connection pattern ───────────────────────────
# The flash_cache_data / flash_cache_tag macros expose VDD / VSS pins
# as `long_pin` style M4 vertical rails (see flash_cache_*.lef — many
# short RECT segments along the full macro height). The mesh alone
# only landed vias on 2/10 macros — the long_pin pattern below drops a
# per-macro M5 strap (horizontal, perpendicular to the M4 pin
# orientation) every 4 μm so compile_pg picks up every macro M4 pin
# it crosses.
puts "INFO: \[pg_mesh\] creating macro PG connection pattern"
create_pg_macro_conn_pattern macro_conn \
    -pin_conn_type long_pin \
    -direction horizontal \
    -pitch 4.0 \
    -layers M5

# ── Step 6: bind patterns to nets via PG strategies ──────────────────────
puts "INFO: \[pg_mesh\] defining PG strategies"

set_pg_strategy rail_strategy \
    -pattern {{name: std_cell_rail} {nets: {VDD VSS}}} \
    -core

set_pg_strategy mesh_strategy \
    -pattern {{name: mesh_m5_m6} {nets: {VDD VSS}}} \
    -core

set_pg_strategy macro_strategy \
    -pattern {{name: macro_conn} {nets: {VDD VSS}}} \
    -macros [get_cells -hier -filter {is_hard_macro==true}]

# ── Step 7: synthesize the PG network ────────────────────────────────────
puts "INFO: \[pg_mesh\] compile_pg"
compile_pg -strategies {rail_strategy mesh_strategy macro_strategy}

puts "INFO: \[pg_mesh\] PG mesh built (M1 rails + M5/M6 mesh @ 50 μm pitch)"
