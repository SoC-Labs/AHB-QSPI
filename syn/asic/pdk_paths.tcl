#-----------------------------------------------------------------------------
# Shared PDK / cell-library / memory paths for the top_ahb_qspi flow.
#
# This file is the single source of truth for every external path the
# ASIC flow needs. Source it from any Tcl context that needs the
# values, or read it via the parallel Make variables in
# syn/asic/common.mk.
#
# ## Paths Please Edit for your system
#
# The values below come from the project-wide SoC-Labs convention; not
# every path is reachable from every host. For this partition flow
# (top_ahb_qspi), only a SUBSET of the paths is actually used at the
# moment — see the "PARTITION-FLOW DEPENDENCY" comments. The rest are
# captured here so the chip-top / wider-project context can be brought
# in without re-deriving them.
#-----------------------------------------------------------------------------

# ── A) Process tech (TSMC cln65lp) ────────────────────────────────────────
# PARTITION-FLOW DEPENDENCY: alternative tech file + alternative LEF.
# The partition currently uses the Arm-supplied Milkyway tech file
# (arm_tech/r2p0/milkyway/1p9m_6x2z/sc12_tech.tf) — see common.mk
# TF_FILE. The TSMC-supplied path below is the foundry-original and
# can be substituted when on a host that has TSMCHOME mirrored.
set cln65lp_tech_path           /home/dwn1c21/SoC-Labs/phys_ip/TSMC/65/CMOS/LP/stclib/12-track/tcbn65lpbwp12t-set/tcbn65lpbwp12t_200b_FE/TSMCHOME/digital/Back_End

# Technology files
set cln65lp_tech_file       $cln65lp_tech_path/milkyway/tcbn65lpbwp12t_200a/techfiles/tsmcn65_9lmT2.tf
set cln65lp_lef_file        $cln65lp_tech_path/lef/tcbn65lpbwp12t_140b/lef/tcbn65lpbwp12t_9lmT2.lef

# ── B) Arm sc12 standard cells (TSMC cln65lp, 12-track, RVT) ──────────────
# PARTITION-FLOW DEPENDENCY: YES — this is the std-cell library the
# partition synthesises + places against. common.mk uses the same
# physical location via PHYS_IP_PATH/sc12_base_rvt/r0p0/...
set standard_cell_base_path     /research/AAA/phys_ip_library/arm/tsmc/cln65lp/sc12_base_rvt/r0p0

set standard_cell_lef_file                  $standard_cell_base_path/lef/sc12_cln65lp_base_rvt.lef
set standard_cell_gds_file                  $standard_cell_base_path/gds2/sc12_cln65lp_base_rvt.gds2
set standard_cell_db_file_ss_0p72v_125C     $standard_cell_base_path/db/sc12_cln65lp_base_rvt_ss_typical_max_1p08v_125c.db
set standard_cell_db_file_tt_0p80v_25C      $standard_cell_base_path/db/sc12_cln65lp_base_rvt_tt_typical_max_1p20v_25c.db
set standard_cell_db_file_ff_0p88v_m40C     $standard_cell_base_path/db/sc12_cln65lp_base_rvt_ff_typical_min_1p32v_m40c.db
set standard_cell_antenna_file              $standard_cell_base_path/milkyway/9m_2xa1xd3xe2z_utrdl/sc9mcpp96c_cln16fcll001_base_svt_c24_antenna.clf

# ── C) Arm IO library (chip-top pad ring) ──────────────────────────────────
# PARTITION-FLOW DEPENDENCY: NO. The partition has no pad cells; pins
# are placed at the partition boundary. These IO macros are for the
# chip-top context that wraps the partition in a pad ring.
set io_base_path                /home/dwn1c21/SoC-Labs/phys_ip/TSMC/65/CMOS/LP/IO2.5V/iolib/linear/tpdn65lpnv2od3_200a_FE/TSMCHOME/digital

set io_lef_file                 $io_base_path/Back_End/lef/tpdn65lpnv2od3_140b/mt_2/9lm/lef/tpdn65lpnv2od3_9lm.lef
set io_gds_file                 $io_base_path/gds2/io_gppr_cln16fcll001_t18_mv08_fs18_rvt_dr_9m_2xa1xd3xe2z_fc.gds2
set io_db_file_ss_0p72v_125C    $io_base_path/Front_End/timing_power_noise/NLDM/tpdn65lpnv2od3_200a/tpdn65lpnv2od3wc.db
set io_db_file_tt_0p80v_25C     $io_base_path/Front_End/timing_power_noise/NLDM/tpdn65lpnv2od3_200a/tpdn65lpnv2od3tc.db
set io_db_file_ff_0p88v_m40C    $io_base_path/Front_End/timing_power_noise/NLDM/tpdn65lpnv2od3_200a/tpdn65lpnv2od3bc.db
set io_antenna_file             $io_base_path/milkyway/9m_2xa1xd3xe2z_fc/io_gppr_cln16fcll001_t18_mv08_fs18_rvt_dr_antenna.clf

# ── D) Arm power-management kit (cln16fcll001) ─────────────────────────────
# PARTITION-FLOW DEPENDENCY: NO. These cross-process cells (PMK + RKLO
# retention flops) are intended for chip-top power-domain crossings.
# Paths reference cln16fcll001 (16nm) despite the 65nm base flow —
# kept as configured for the wider project.
set pmk_base_path               /research/AAA/phys_ip_library/arm/tsmc/cln16fcll001/sc9mcpp96c_pmk_svt_c24/r2p0
set ret_base_path               /research/AAA/phys_ip_library/arm/tsmc/cln16fcll001/sc9mcpp96c_rklo_lvt_svt_c20_c24/r1p0

# ── E) Project memories (chip-top SRAM + bootrom) ──────────────────────────
# PARTITION-FLOW DEPENDENCY: NO. The top_ahb_qspi partition uses the
# precompiled flash_cache_data + flash_cache_tag macros (see
# common.mk MEM_BASE = /research/precompiled_mems/TSMC65) — those are
# the cache RAMs visible from the cache_subsystem. SRAM_32K + ROM_VIA
# are wider-project memories; SOCLABS_PROJECT_DIR is expected to
# point at a chip-top repo that has these under memories/.
if {[info exists ::env(SOCLABS_PROJECT_DIR)]} {
    set _proj_root $::env(SOCLABS_PROJECT_DIR)
} elseif {[info exists ::env(SOCLABS_AHB_QSPI_DIR)]} {
    # Fallback: this partition's project root (so syntax checks succeed
    # even though the memories/ tree only exists in the wider project).
    set _proj_root $::env(SOCLABS_AHB_QSPI_DIR)
} else {
    set _proj_root "."
}

set SRAM_32K_PATH            $_proj_root/memories/sram_32k
set SRAM_32K_lef_file        $SRAM_32K_PATH/sram_32k.lef
set SRAM_32K_gds_file        $SRAM_32K_PATH/sram_32k.gds2
set SRAM_32K_lib_file_ss     $SRAM_32K_PATH/sram_32k_ssgnp_0p72v_0p72v_125c.lib
set SRAM_32K_lib_file_tt     $SRAM_32K_PATH/sram_32k_tt_0p80v_0p80v_25c.lib
set SRAM_32K_lib_file_ff     $SRAM_32K_PATH/sram_32k_ffgnp_0p88v_0p88v_m40c.lib
set SRAM_32K_db_file_ss      $SRAM_32K_PATH/sram_32k_ssgnp_0p72v_0p72v_125c.db
set SRAM_32K_db_file_tt      $SRAM_32K_PATH/sram_32k_tt_0p80v_0p80v_25c.db
set SRAM_32K_db_file_ff      $SRAM_32K_PATH/sram_32k_ffgnp_0p88v_0p88v_m40c.db

set ROM_VIA_PATH            $_proj_root/memories/bootrom
set ROM_VIA_lef_file        $ROM_VIA_PATH/rom_via.lef
set ROM_VIA_gds_file        $ROM_VIA_PATH/rom_via.gds2
set ROM_VIA_lib_file_ss     $ROM_VIA_PATH/rom_via_ssgnp_0p72v_0p72v_125c.lib
set ROM_VIA_lib_file_tt     $ROM_VIA_PATH/rom_via_tt_0p80v_0p80v_25c.lib
set ROM_VIA_lib_file_ff     $ROM_VIA_PATH/rom_via_ffgnp_0p88v_0p88v_m40c.lib
set ROM_VIA_db_file_ss      $ROM_VIA_PATH/rom_via_ssgnp_0p72v_0p72v_125c.db
set ROM_VIA_db_file_tt      $ROM_VIA_PATH/rom_via_tt_0p80v_0p80v_25c.db
set ROM_VIA_db_file_ff      $ROM_VIA_PATH/rom_via_ffgnp_0p88v_0p88v_m40c.db

# ── F) TSMC Calibre PDK (signoff DRC + LVS) ────────────────────────────────
# PARTITION-FLOW DEPENDENCY: YES (signoff). The partition exports a
# routed GDS (outputs/top_ahb_qspi.gds.gz). Running Calibre DRC
# against it gives EXACT short coordinates + foundry rule numbers —
# Path C from docs/route_drc_shorts_analysis.md, now actually
# runnable (Calibre v2023.1 is installed at /eda/mentor/calibre/).
#
# The deck below is the per-stack variant; our partition uses the
# 1p9m_6X2Z0U metal stack (per common.mk TF_FILE = 1p9m_6x2z).
set tsmc65_calibre_pdk          /home/dwn1c21/SoC-Labs/phys_ip/TSMC/65/CMOS/LP/pdk/Calibre

set tsmc65_drc_deck             $tsmc65_calibre_pdk/online/drc_online/1p9m_6X2Z0U/calibre.drc
set tsmc65_drc_top_deck         $tsmc65_calibre_pdk/drc/calibre.drc
set tsmc65_lvs_deck             $tsmc65_calibre_pdk/lvs/calibre.lvs
set tsmc65_rcx_deck             $tsmc65_calibre_pdk/rcx/calibre.rcx
set tsmc65_antenna_deck         $tsmc65_calibre_pdk/drc/ANTENNA_DRC

# Calibre binary (only the signoff-DRC make target reads this).
set tsmc65_calibre_bin          /eda/mentor/calibre/bin/calibre
