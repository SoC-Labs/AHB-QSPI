# Common ASIC synthesis definitions
# Included by all flow Makefiles under syn/asic/

export SOCLABS_AHB_QSPI_DIR := $(realpath $(dir $(lastword $(MAKEFILE_LIST)))/../..)

# ARM IP root (CG092 cache + Corstone-101 APB slave mux live here).
# Override via the environment for non-default install paths.
export ARM_IP_LIBRARY_PATH ?= /research/AAA/ip_library

# ── Target module ──────────────────────────────────────────────────────────
export MODULE ?= top_ahb_qspi
export TOP    ?= $(MODULE)

# ── File lists ─────────────────────────────────────────────────────────────
# The ASIC flist pulls real SRAM macros from /research/precompiled_mems/TSMC65
# (flash_cache_data + flash_cache_tag), via ahb_QSPI_ASIC.flist + its sv-only
# nested flist. Use the SIM flist for behavioural cache_ram models instead.
export FLIST := $(SOCLABS_AHB_QSPI_DIR)/flist/Top/ahb_QSPI_ASIC.flist

# ── Cell libraries (TSMC 65nm LP, sc12 RVT) ────────────────────────────────
# 1.08 V slow corner — paired with the 1.08 V SRAM macro corners below so
# every link library sits at the same operating point.
export TARGET_LIB     ?= /research/AAA/phys_ip_library/arm/tsmc/cln65lp/sc12_base_rvt/r0p0/db/sc12_cln65lp_base_rvt_ss_typical_max_1p08v_125c.db

# ── Memory macro libraries ─────────────────────────────────────────────────
# top_ahb_qspi instantiates two cache ways (cache_subsystem.v): each way's
# cache_ram has 4× flash_cache_data (256×32) and 1× flash_cache_tag (256×11)
# = 10 SRAM macros at the partition top. Both come precompiled with .lef +
# slow/fast .db under /research/precompiled_mems/TSMC65/.
export MEM_BASE       ?= /research/precompiled_mems/TSMC65

export FCD_DB_SS      ?= $(MEM_BASE)/flash_cache_data/flash_cache_data_ss_1p08v_1p08v_125c.db
export FCT_DB_SS      ?= $(MEM_BASE)/flash_cache_tag/flash_cache_tag_ss_1p08v_1p08v_125c.db

# Aggregate slow/fast macro library lists for link_library.
# NOTE: only the ss_1p08v_125c corner is precompiled to .db under
# /research/precompiled_mems/TSMC65/flash_cache_*/. The matching .lib
# for ff_1p32v_m40c exists alongside but no .db has been built yet, so
# MEM_DBS_FF is left empty here and the FC.read_design.tcl skips
# scen_fast when this list is empty. To enable hold-corner analysis,
# convert the .lib's to .db with lc_shell and point FCD_DB_FF / FCT_DB_FF
# at the resulting files.
export MEM_DBS_SS     := $(FCD_DB_SS) $(FCT_DB_SS)
export MEM_DBS_FF     :=

# Link libraries — target + every macro corner present
export LINK_LIBS      ?= $(TARGET_LIB) $(MEM_DBS_SS)

# ── Physical references (TSMC 65nm LP, 1p9m_6x2z stack) ───────────────────
export PHYS_IP_PATH   ?= /research/AAA/phys_ip_library/arm/tsmc/cln65lp
export STDCELL_VERILOG ?= $(PHYS_IP_PATH)/sc12_base_rvt/r0p0
export TF_FILE        ?= $(PHYS_IP_PATH)/arm_tech/r2p0/milkyway/1p9m_6x2z/sc12_tech.tf
export MW_REF_LIB     ?= $(PHYS_IP_PATH)/sc12_base_rvt/r0p0/milkyway/1p9m_6x2z/sc12_cln65lp_base_rvt

# ── Multi-corner .db libraries (sc12 std cells) ────────────────────────────
export DB_PATH        ?= $(PHYS_IP_PATH)/sc12_base_rvt/r0p0/db
export DB_SS          ?= $(DB_PATH)/sc12_cln65lp_base_rvt_ss_typical_max_1p08v_125c.db
export DB_FF          ?= $(DB_PATH)/sc12_cln65lp_base_rvt_ff_typical_min_1p32v_m40c.db

# ── TLU+ parasitic extraction models ─────────────────────────────────────
export TLUPLUS_PATH   ?= $(PHYS_IP_PATH)/arm_tech/r2p0/synopsys_tluplus/1p9m_6x2z
export TLUPLUS_MAP    ?= $(TLUPLUS_PATH)/tluplus.map

# ── Design constraints ─────────────────────────────────────────────────────
# top_ahb_qspi has two boundary clocks (HCLK + PCLK, both 4 ns in the
# existing dc_synthesis_core.tcl baseline) plus a divided-by-2 generated
# QSPI_SCLK. The shared FC.read_design.tcl creates HCLK; the Fusion
# inputs/constraints.sdc overlay adds PCLK + the generated clock.
export CLK_NAME        ?= HCLK
export CLK_PERIOD      ?= 4.0
export CLK_UNCERTAINTY ?= 0.35

# Two reset ports: HRESETn (AHB) and PRESETn (APB). The shared script
# accepts a single RST_NAME; the second is treated as async via the SDC
# overlay's set_false_path -from list.
export RST_NAME        ?= HRESETn
