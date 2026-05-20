#-----------------------------------------------------------------------------
# Path D v2 — DRC-driven ECO, NON-DESTRUCTIVE (2026-05-20)
#
# v1 finding: blind candidate-list ECO on the DEF-parser top-10 produced
# "Topology ECO not run, no qualifying violations" on every pair — i.e.
# the top-area candidates are NOT the actual Shorts (they are
# high-bbox-overlap parallel runs, missed by LEF-rule-free heuristic).
#
# v2 tries the right approach: call route_eco WITHOUT -nets so it scans
# the design's own check_routes violations and fixes what it can. Then
# fall back to a bulk top-50 candidate ECO if route_eco didn't clear
# everything. Then a final route_opt + route_detail cleanup pass.
# Saves to throwaway alias only.
#-----------------------------------------------------------------------------

set top_module       $::env(MODULE)
set design_lib_name  "${top_module}.dlib"
set fc_dir           $::env(FC_DIR)
set fc_reports       $::env(FC_REPORTS)
file mkdir $fc_reports

open_lib   $design_lib_name
open_block ${design_lib_name}:${top_module}/signoff.design
source ${fc_dir}/scripts/setup.tcl
source ${fc_dir}/scripts/setup_design_options.tcl

set rpt ${fc_reports}/path_d_eco.rep
set fh  [open $rpt w]
proc emit {fh s} { puts $fh $s; puts $s }

proc drc_counts {} {
    redirect -variable out {catch {check_routes -open_net true -drc true}}
    set total 0; set shorts 0; set eol 0
    if {[regexp {Total number of DRCs\s*=\s*(\d+)} $out -> m]} { set total  $m }
    if {[regexp {Short\s*:\s*(\d+)}                $out -> m]} { set shorts $m }
    if {[regexp {End of line spacing\s*:\s*(\d+)}  $out -> m]} { set eol    $m }
    return [list $total $shorts $eol]
}

proc fmt {label tag} {
    return [format " %-32s : %s" $label $tag]
}

emit $fh "================================================================"
emit $fh " Path D v2 — DRC-driven ECO (non-destructive)"
emit $fh "================================================================"

lassign [drc_counts] b_total b_short b_eol
emit $fh [fmt "Baseline" "$b_total DRCs ($b_short Shorts, $b_eol EOL)"]
if {$b_short == 0 && $b_total == 0} {
    emit $fh "No DRCs in baseline; nothing to do."
    close $fh
    catch {save_block -as ${design_lib_name}:${top_module}/signoff_pathd.design}
    puts "FC_STAGE_OK: path_d_eco"; exit
}

# ── Phase A — route_eco with no -nets ── let it scan its own violations
emit $fh ""
emit $fh "--- Phase A: route_eco (no -nets, DRC-driven) ---"
if {[catch {route_eco} err]} {
    emit $fh [fmt "route_eco" "FAILED: $err"]
} else {
    emit $fh [fmt "route_eco" "OK"]
}
lassign [drc_counts] a_total a_short a_eol
emit $fh [fmt "After Phase A" "$a_total DRCs ($a_short Shorts, $a_eol EOL)\
  delta_total=[expr {$a_total - $b_total}] delta_short=[expr {$a_short - $b_short}]"]

# ── Phase B — bulk route_eco on top-50 candidate net pairs ──
# (Only if Phase A didn't already clear all Shorts.)
if {$a_short > 0} {
    emit $fh ""
    emit $fh "--- Phase B: bulk route_eco on top-50 candidate net pairs ---"
    set candidates {
        "PRDATA[12]" "PRDATA[24]"
        "HADDR[20]" "HRESP"
        "HWDATA[17]" "HWDATA[8]"
        "HRESETn" "u_cache_subsystem/RAMCLD0ADDR[5]"
        "HADDR[11]" "HWDATA[5]"
        "HADDR[19]" "HRDATA[31]"
        "HWDATA[10]" "HWDATA[2]"
        "HADDR[2]" "HRDATA[7]"
        "HADDR[2]" "HADDR[4]"
        "HADDR[9]" "HWDATA[6]"
        "PADDR[8]" "PRDATA[13]"
        "PWDATA[20]" "u_apb_qspi_regs/reg11[18]"
        "HADDR[11]" "HADDR[9]"
        "PENABLE" "PWDATA[5]"
        "PADDR[8]" "PWDATA[24]"
        "u_cache_subsystem/RAMTAG0RDATA[8]" "u_cache_subsystem/u_cache_controller/u_p_flash_cache_f0_core/reg_inv_addr[0]"
        "HADDR[6]" "SEQMAP_NET_4684"
        "u_qspi_controller/data_in_reg[10]" "u_qspi_controller/data_in_reg[88]"
        "PRDATA[12]" "PWDATA[27]"
        "u_apb_qspi_regs/reg9[7]" "u_cache_subsystem/u_cache_controller/u_p_flash_cache_f0_core/ccr_set_prefetch"
        "PCLK" "PRDATA[26]"
        "HRDATA[27]" "SEQMAP_NET_3988"
        "PWDATA[12]" "u_apb_qspi_regs/reg9[9]"
        "HRDATA[22]" "SEQMAP_NET_3984"
        "HRDATA[27]" "HRESETn"
        "HADDR[19]" "u_qspi_controller/QSPI_WDATA_reg[43]"
        "QSPI_CONT_READ" "SEQMAP_NET_2064"
        "PADDR[10]" "PADDR[11]"
        "PWDATA[18]" "SEQMAP_NET_4992"
        "PRDATA[11]" "SEQMAP_NET_4212"
        "PRDATA[23]" "PRDATA[2]"
        "HRDATA[22]" "HREADY"
        "AHB_QSPI_ADDR[4]" "HADDR[9]"
        "u_apb_qspi_regs/reg10[5]" "u_apb_qspi_regs/reg9[0]"
        "HADDR[7]" "SEQMAP_NET_3344"
        "HRDATA[27]" "HRDATA[31]"
        "PWDATA[12]" "u_apb_qspi_regs/reg9[11]"
        "PWDATA[27]" "SEQMAP_NET_2688"
        "PADDR[10]" "PADDR[9]"
        "PADDR[4]" "SEQMAP_NET_4360"
        "HRDATA[3]" "u_cache_subsystem/RAMCLD0WDATA[5]"
        "HADDR[10]" "HWDATA[8]"
        "HRDATA[7]" "u_ahb_qspi_interface/N68"
        "HADDR[2]" "HRDATA[7]"
    }
    # De-dup nets + filter to existing nets
    set net_set {}
    foreach n $candidates {
        set c [get_nets -quiet $n]
        if {[sizeof_collection $c] > 0} {
            lappend net_set [get_object_name [index_collection $c 0]]
        }
    }
    set net_set [lsort -unique $net_set]
    emit $fh [fmt "candidate nets resolved" "[llength $net_set] unique nets"]
    if {[llength $net_set] > 0} {
        set nc [get_nets $net_set]
        if {[catch {route_eco -nets $nc} err]} {
            emit $fh [fmt "bulk route_eco" "FAILED: $err"]
        } else {
            emit $fh [fmt "bulk route_eco" "OK"]
        }
    }
    lassign [drc_counts] c_total c_short c_eol
    emit $fh [fmt "After Phase B" "$c_total DRCs ($c_short Shorts, $c_eol EOL)\
  delta_total=[expr {$c_total - $a_total}] delta_short=[expr {$c_short - $a_short}]"]
} else {
    set c_total $a_total ; set c_short $a_short ; set c_eol $a_eol
    emit $fh "(Phase A cleared all Shorts; skipping Phase B)"
}

# ── Phase C — final route_opt + incremental route_detail cleanup ──
if {$c_short > 0} {
    emit $fh ""
    emit $fh "--- Phase C: route_opt + route_detail (final DRC cleanup) ---"
    if {[catch {route_opt -from final_route -to final_route} err]} {
        emit $fh [fmt "route_opt" "WARN: $err"]
    } else {
        emit $fh [fmt "route_opt" "OK"]
    }
    if {[catch {route_detail -incremental true -initial_drc_from_input true \
                              -max_number_iterations 30} err]} {
        emit $fh [fmt "route_detail" "WARN: $err"]
    } else {
        emit $fh [fmt "route_detail" "OK"]
    }
    lassign [drc_counts] d_total d_short d_eol
    emit $fh [fmt "After Phase C" "$d_total DRCs ($d_short Shorts, $d_eol EOL)\
  delta_total=[expr {$d_total - $c_total}] delta_short=[expr {$d_short - $c_short}]"]
} else {
    set d_total $c_total ; set d_short $c_short ; set d_eol $c_eol
}

# ── Summary ──
emit $fh ""
emit $fh "================================================================"
emit $fh [fmt "Baseline" "$b_total DRCs, $b_short Shorts"]
emit $fh [fmt "After Phase A (route_eco)" "$a_total DRCs, $a_short Shorts"]
emit $fh [fmt "After Phase B (bulk -nets)" "$c_total DRCs, $c_short Shorts"]
emit $fh [fmt "After Phase C (opt+detail)" "$d_total DRCs, $d_short Shorts"]
emit $fh [fmt "Net shorts delta" "[expr {$d_short - $b_short}]"]
emit $fh "================================================================"
close $fh

catch {save_block -as ${design_lib_name}:${top_module}/signoff_pathd.design}
puts "FC_STAGE_OK: path_d_eco"
exit
