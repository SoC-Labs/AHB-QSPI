#-----------------------------------------------------------------------------
# Phase 4c: partition export — write hand-off products for top-level chip
#                              integration.
#
# Run with: fc_shell -f 6_partition_export.tcl   (after 5_signoff.tcl)
#-----------------------------------------------------------------------------

set top_module       $::env(MODULE)
set design_lib_name  "${top_module}.dlib"
set fc_dir           $::env(FC_DIR)
set fc_outputs       $::env(FC_OUTPUTS)
set fc_reports       $::env(FC_REPORTS)

file mkdir $fc_outputs

#-----------------------------------------------------------------------------
# Open the post-signoff checkpoint
#-----------------------------------------------------------------------------
open_lib   $design_lib_name
open_block ${design_lib_name}:${top_module}/signoff.design

source ${fc_dir}/scripts/setup.tcl
source ${fc_dir}/scripts/setup_design_options.tcl

#-----------------------------------------------------------------------------
# Hand-off products for top-level chip flow
#-----------------------------------------------------------------------------

# Gate-level Verilog netlist (logic) + power-aware variant (with PG pins)
puts "INFO: \[fc_abstract\] write_verilog (gate netlist + PG variant)"
write_verilog ${fc_outputs}/${top_module}.v
write_verilog -include {pg_objects} ${fc_outputs}/${top_module}.pg.v

# Boundary SDC for top-level constraint propagation
puts "INFO: \[fc_abstract\] write_sdc"
write_sdc -output ${fc_outputs}/${top_module}.sdc

# Per-scenario SDF + SPEF for back-annotated gate-level sim and
# chip-top hierarchical STA. write_sdf / write_parasitics operate on the
# current scenario, so iterate every ACTIVE scenario rather than
# hardcoding scen_slow — when MEM_DBS_FF is populated and scen_fast
# exists, the integrator automatically gets both the slow/setup and
# fast/hold views with no script change. A bare ${top}.sdf alias
# (slow-biased: slow if present, else the first active scenario) is also
# emitted so existing chip-top sim scripts that expect the un-suffixed
# name keep working.
set active_scenarios [list]
foreach_in_collection s [get_scenarios -quiet -filter active==true] {
    lappend active_scenarios [get_attribute $s name]
}
if {[llength $active_scenarios] == 0} {
    puts "WARNING: \[fc_abstract\] no active scenarios — skipping SDF/SPEF"
} else {
    puts "INFO: \[fc_abstract\] SDF/SPEF for scenarios: $active_scenarios"
    set sdf_alias_scen [expr {[lsearch -exact $active_scenarios scen_slow] >= 0 \
                              ? "scen_slow" : [lindex $active_scenarios 0]}]
    foreach scen $active_scenarios {
        current_scenario $scen
        puts "INFO: \[fc_abstract\] write_sdf ($scen)"
        write_sdf ${fc_outputs}/${top_module}.${scen}.sdf
        if {$scen eq $sdf_alias_scen} {
            write_sdf ${fc_outputs}/${top_module}.sdf
        }
        # SPEF — chip-top STA needs the block's extracted parasitics so
        # it can do real hierarchical timing instead of re-flat-extracting
        # through the partition. Depends on signoff-stage RC extraction
        # having run; guard so a missing-parasitic block downgrades to a
        # warning rather than killing the export stage.
        puts "INFO: \[fc_abstract\] write_parasitics SPEF ($scen)"
        if {[catch {write_parasitics -format SPEF \
                        -output ${fc_outputs}/${top_module}.${scen}.spef} perr]} {
            puts "WARNING: \[fc_abstract\] SPEF write failed for $scen: $perr"
            puts "WARNING: \[fc_abstract\]   (signoff-stage extract_parasitics may not have run —"
            puts "WARNING: \[fc_abstract\]    chip-top must re-extract through the block instead)"
        }
    }
}

# Floorplan DEF (top can place the partition by reading this)
puts "INFO: \[fc_abstract\] write_def"
write_def ${fc_outputs}/${top_module}.def

# LEF abstract (physical interface for top-level placement)
puts "INFO: \[fc_abstract\] write_lef"
write_lef ${fc_outputs}/${top_module}.lef

# Boundary UPF — pg_mesh.tcl built PD_TOP + VDD/VSS supply ports/nets
# with create_power_domain / create_supply_*. A chip-top that wraps this
# partition in its own (possibly multi-rail) power intent needs the
# block's supply-set as UPF, not just the PG pins in the .pg.v netlist:
# it tells the integrator which ports are power, that there is a single
# PD_TOP domain, and (by their absence) that no isolation/level-shift/
# retention strategy is required at the boundary. Guarded — a block
# built without UPF-style PG commands would have nothing to save.
puts "INFO: \[fc_abstract\] save_upf"
if {[catch {save_upf ${fc_outputs}/${top_module}.upf} uerr]} {
    puts "WARNING: \[fc_abstract\] save_upf failed: $uerr"
    puts "WARNING: \[fc_abstract\]   (no UPF power intent in block — chip-top must"
    puts "WARNING: \[fc_abstract\]    treat VDD/VSS as plain supply ports from the .pg.v)"
}

# NOTE: ETM (Extracted Timing Model) generation is not provided directly
# in fc_shell U-2022.12 — the relevant `write_lib_model -format etm`
# command is unavailable here. Top-level STA can either read the
# committed signoff.design block from the .dlib (NDM-based hierarchical
# STA) or generate ETM via PrimeTime as a follow-on. The .dlib block
# IS the partition abstract for FC's hierarchical PnR flow.

# GDSII for chip-finish / DRC / LVS — partition geometry plus the
# referenced std-cell + macro GDS streams merged in so the output is
# self-contained.
puts "INFO: \[fc_abstract\] write_gds (merging std-cell + cache-RAM streams)"
set gds_layer_map [expr {[info exists ::env(GDS_LAYER_MAP)] ? $::env(GDS_LAYER_MAP) : ""}]
set gds_merge_files [list]
foreach v {GDS_STDCELL GDS_MEM_FCD GDS_MEM_FCT} {
    if {[info exists ::env($v)] && [file exists $::env($v)]} {
        lappend gds_merge_files $::env($v)
    } else {
        puts "WARNING: \[fc_abstract\] $v missing or path not found — skipping merge"
    }
}
if {$gds_layer_map ne "" && [file exists $gds_layer_map]} {
    write_gds \
        -hierarchy all \
        -layer_map $gds_layer_map \
        -layer_map_format icc2 \
        -merge_files $gds_merge_files \
        -compress \
        ${fc_outputs}/${top_module}.gds
    puts "INFO: \[fc_abstract\] GDS at ${fc_outputs}/${top_module}.gds"
} else {
    puts "WARNING: \[fc_abstract\] GDS_LAYER_MAP not found at '$gds_layer_map' — skipping GDS write"
}

#-----------------------------------------------------------------------------
# Manifest of delivered products.
#
# The integrator consumes this to know (a) WHAT was delivered, (b) WHICH
# signoff block + scenarios it came from (provenance — so a stale netlist
# paired with a fresh SDF is caught), and (c) a SHA256 per file so the
# chip-top side can verify the bytes it received are the bytes we wrote.
# Role strings document what each artefact is *for* — an integrator
# picking up the drop shouldn't have to guess why a .upf is in the set.
#-----------------------------------------------------------------------------
array set deliverable_role {
    .v     "gate netlist (logic) — chip-top HDL integration / LEC impl"
    .pg.v  "gate netlist with PG pins — LVS source / power-aware sim"
    .sdc   "boundary timing constraints — propagate at chip-top"
    .sdf   "back-annotated delays (alias = slow/first scenario)"
    .spef  "extracted parasitics — chip-top hierarchical STA"
    .def   "floorplan geometry — chip-top placement/stitch"
    .lef   "physical abstract — chip-top placement footprint"
    .upf   "boundary power intent — chip-top supply-set wiring"
    .gds   "merged stream-out — chip-finish / signoff DRC / LVS"
}
proc deliverable_role_for {fname} {
    global deliverable_role
    foreach suf {.pg.v .spef .sdf .gds .lef .def .sdc .upf .v} {
        if {[string match "*${suf}" $fname]} {
            if {[info exists deliverable_role($suf)]} {
                return $deliverable_role($suf)
            }
        }
    }
    return ""
}
redirect -tee -file ${fc_reports}/06_abstract_manifest.txt {
    puts "================================================================="
    puts " Partition deliverables — $top_module"
    puts "================================================================="
    puts "  Source block : ${design_lib_name}:${top_module}/signoff.design"
    puts "  Generated    : [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S %Z}]"
    if {[info exists active_scenarios] && [llength $active_scenarios] > 0} {
        puts "  Scenarios    : $active_scenarios"
        puts "                 (SDF/SPEF emitted per scenario; chip-top must"
        puts "                  close timing on every corner listed here)"
        if {[lsearch -exact $active_scenarios scen_fast] < 0} {
            puts "  NOTE         : no scen_fast — hold/min corner NOT covered."
            puts "                 Populate MEM_DBS_FF (make mem_ff_db) to add it."
        }
    } else {
        puts "  Scenarios    : (none active — SDF/SPEF not emitted)"
    }
    puts "-----------------------------------------------------------------"
    puts [format "  %-12s  %-64s  %s" "SIZE(B)" "SHA256" "FILE  —  ROLE"]
    puts "-----------------------------------------------------------------"
    foreach f [lsort [glob -nocomplain ${fc_outputs}/*]] {
        if {![file isfile $f]} { continue }
        set sha "n/a"
        catch {set sha [lindex [exec sha256sum $f] 0]}
        set role [deliverable_role_for [file tail $f]]
        puts [format "  %-12s  %-64s  %s" \
                  [file size $f] $sha "[file tail $f]  —  $role"]
    }
    puts "================================================================="
}

puts "FC_STAGE_OK: abstract"
exit
