#-----------------------------------------------------------------------------
# Build NDMs for the FC flow.
#
# Run with: lm_shell -f create_fusion_lib.tcl
#
# Builds, in order:
#   <out>/sc12_lib       — TSMC65 sc12 std cells (LEF + .db, full lib)
#   <out>/mem_frame_lib  — frame-only NDM for flash_cache_data + flash_cache_tag
#                          macros (LEFs only; macro Liberty reaches fc_shell
#                          via link_library .db's set in 1_init_design.tcl)
#
# Why split:
#   - sc12 cells are self-contained, so a normal-flow lm_shell build
#     embeds Liberty next to the frame and gives fc_shell the AND/OR/INV
#     cells it needs for synthesis (DWS-0103 otherwise).
#   - The cache memory macros' .db files reference std-cell sub-modules,
#     so committing a normal-flow workspace that reads both .lef and .db
#     without their parent std-cell library context fails check_workspace.
#     Frame-only is sufficient for placement; macro timing comes through
#     fc_shell's link_library.
#
# Environment variables (set by Makefile via common.mk):
#   PHYS_IP_PATH      - sc12 base path
#   TF_FILE           - .tf
#   DB_SS / DB_FF     - sc12 slow/fast .db
#   MEM_BASE          - precompiled-mems root (TSMC65)
#   FUSION_LIB        - output path for sc12_lib (siblings created next to it)
#-----------------------------------------------------------------------------

set phys_ip_path $::env(PHYS_IP_PATH)
set tf_file      $::env(TF_FILE)
set db_ss        $::env(DB_SS)
set db_ff        $::env(DB_FF)

if {[info exists ::env(MEM_BASE)] && $::env(MEM_BASE) ne ""} {
    set mem_base $::env(MEM_BASE)
} else {
    set mem_base "/research/precompiled_mems/TSMC65"
}

set stdcell_lef "${phys_ip_path}/sc12_base_rvt/r0p0/lef/sc12_cln65lp_base_rvt.lef"

set mem_lefs [list \
    "${mem_base}/flash_cache_data/flash_cache_data.lef" \
    "${mem_base}/flash_cache_tag/flash_cache_tag.lef"]

# Output base dir: $FUSION_LIB points at sc12_lib; siblings live alongside.
if {[info exists ::env(FUSION_LIB)] && $::env(FUSION_LIB) ne ""} {
    set output_lib_sc12 $::env(FUSION_LIB)
} else {
    set output_lib_sc12 "./fusion_lib/sc12_lib"
}
set output_dir         [file dirname $output_lib_sc12]
set output_lib_mem     "${output_dir}/mem_frame_lib"
file mkdir $output_dir

# Demote LEF-vs-Liberty VDD/VSS direction-mismatch errors (NDM-032) to
# warnings. lm_shell auto-corrects each one (LM-054 "Fixed direction
# mismatches…") but the Error severity counts toward the commit_workspace
# fail threshold. Without this, commit_workspace aborts despite every
# mismatch having been fixed in-flight.
set_message_info -id NDM-032 -limit 5

#-----------------------------------------------------------------------------
# 1) sc12_lib — std cells, normal flow (LEF + Liberty bundled into NDM)
#-----------------------------------------------------------------------------
puts "INFO: \[lib\] Building sc12_lib (std cells, normal flow w/ Liberty)"
puts "INFO: \[lib\]   LEF : $stdcell_lef"
puts "INFO: \[lib\]   .db : $db_ss / $db_ff"
puts "INFO: \[lib\]   Out : $output_lib_sc12"

file delete -force $output_lib_sc12
# Explicit `-flow normal` is required for the leading-positional form to
# parse — the implicit/default form rejects the `<name>` positional with
# CMD-012 "extra positional option" in U-2022.12.
create_workspace sc12_ws -technology $tf_file -flow normal
read_lef $stdcell_lef
read_db $db_ss
read_db $db_ff
check_workspace
commit_workspace -output $output_lib_sc12

#-----------------------------------------------------------------------------
# 2) mem_frame_lib — flash_cache_data + flash_cache_tag macros, frame-only.
#    Liberty for flash_cache_* reaches fc_shell via the link_library .db
#    list set in 1_init_design.tcl (the .db's reference std-cell sub-
#    modules so they cannot be cleanly committed into a normal-flow NDM
#    here).
#-----------------------------------------------------------------------------
puts "INFO: \[lib\] Building mem_frame_lib (flash_cache_data + flash_cache_tag frames)"
foreach lef $mem_lefs { puts "INFO: \[lib\]   LEF : $lef" }
puts "INFO: \[lib\]   Out : $output_lib_mem"

file delete -force $output_lib_mem
create_workspace mem_ws -technology $tf_file -flow frame
foreach lef $mem_lefs { read_lef $lef }
check_workspace
commit_workspace -output $output_lib_mem

puts "INFO: \[lib\] All NDMs committed under $output_dir"
exit
