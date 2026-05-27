# `ahb_qspi` — engineer hand-off guide

This guide is the entry point for picking up the `ahb_qspi` project
cold. It covers: what the IP is, the current state of every flow, how
to replicate the repo, and how to run each flow.

For deep dives into specific topics, jump to the
[Documentation map](#documentation-map) at the bottom.

---

## 1. What this IP is

QSPI controller with AHB and APB interfaces, plus an XiP cache built
around the Arm CG092 Flash Cache. The AHB and APB sides are mux'd
into the QSPI engine so external flash can be reached via either
interface. Verified against a model of the Microchip SST26VF064B
64 Mb SPI flash.

Top-level ports (see [README.md](README.md) for the register map):

- **AHB** — read-only XiP path via Arm CG092 cache
- **APB** — programmable register + data path to the QSPI engine,
  plus CG092 configuration registers
- **QSPI** — 4-bit serial interface to external flash + clock + CS

External IP dependencies:

- **Arm Corstone-101** (BP210) — provides the AHB → APB bridge used
  in verification
- **Arm CG092 Flash Cache** (`p_flash_cache_f0`) — 2-way, default 4 KB
- **SST26VF064B** flash model — downloaded by `make get_flash_model`

---

## 2. Current state (as of 2026-05-27)

| area | branch | state |
|---|---|---|
| RTL verification (cocotb) | `master`, `feat-nanosoc_int` | 97.5 % code coverage; all gold-path + corner tests passing |
| UVM regression | `master` | green |
| Lint (Verilator + HAL) | `master` | green |
| CDC (SpyGlass, structural goal) | `master` | clean; full formal goal hangs — see [docs/cdc_signoff_status.md](docs/cdc_signoff_status.md) |
| FPGA on PYNQ-Z2 | `master` | APB path works end-to-end; AHB XiP on FPGA has known issues |
| DC synthesis (legacy, sc12) | `master` | runs to completion in CI; superseded by FC flow |
| **Fusion Compiler partition flow** (TSMC tcbn65lp 9-track) | `master` | **`CLEAN (2 WAIVERS)`**, `FM_LEC_OK`, `scen_slow` WNS −0.01 ns |
| Formality LEC | `master` | clean (`FM_LEC_OK`) |
| PrimeTime ETM | `master` | scaffold; not silicon-validated |
| Calibre signoff DRC | `master` | wired but coord extraction blocked by absent foundry stdcell GDS |
| GDS_STDCELL auto-wire + Path-D Calibre scaffold | `feat-nanosoc_int` only | staged; activates the moment the `tcbn65lp_220a_BE` pack lands |

**Branch policy:** `master` carries verified state. `feat-nanosoc_int`
carries work-in-progress (currently 1 commit ahead — the
GDS auto-wire scaffold). All earlier development branches (the
`agent/*` and `worktree-agent-*` set) have been retired; their tips
are recoverable from `git reflog` for 90 days.

Tip commit on `master`: `b420b5c`. Tip commit on `feat-nanosoc_int`:
`0d0dba8`.

### Chip-top punchlist (open items)

| item | bounded by | action |
|---|---|---|
| 2 routing Shorts in the central std-cell+cache-bus channel | `FC_ROUTES_DRC_MAX=5` | chip-top detailed-route ECO with M7+ tracks; recipe in [docs/chip_top_handoff.md](docs/chip_top_handoff.md) |
| ~1020 floating PG wire-stubs (1008–1024 run-to-run) | `FC_PG_CONN_FLOAT_MAX=1300` | create proper PG terminals when wiring partition VDD/VSS to chip-top global rails |
| ETM extracted timing model | scaffold only | validate `syn/asic/primetime/scripts/extract_etm.tcl` against silicon, or use the `.dlib` NDM block for hierarchical STA |
| IR-drop / EM signoff | not run | commission a separate IR/EM pass at chip-top (`pg_mesh.tcl` is the supply-network reference) |
| Antenna rules | not loaded in this flow | source cln65lp antenna deck (already at `pdk_paths.tcl`) and run at chip-top DRC |
| Calibre signoff DRC coord extraction | wired but blocked | source the foundry tcbn65lp stdcell `.gds`; `common.mk` auto-detects it (on `feat-nanosoc_int`) |
| AHB XiP on FPGA | known issue | rework FPGA build / debug (PYNQ APB path is the working baseline) |

---

## 3. Replicating the repo

### 3.1 Tooling prerequisites

All flows assume the SoC Labs RHEL 8 build host with these EDA tools
already installed and licensed:

| tool | path on host | flows that use it |
|---|---|---|
| Synopsys VCS 2022.06-SP2 | `/eda/synopsys/2022-23/RHELx86/VCS_2022.06-SP2` | cocotb, UVM, gate-sim |
| Synopsys Verdi 2022.06-SP2 | `/eda/synopsys/2022-23/RHELx86/VERDI_2022.06-SP2` | wave/coverage GUI |
| Synopsys SpyGlass 2022.06-SP2 | `/eda/synopsys/2022-23/RHELx86/SPYGLASS_2022.06-SP2` | CDC |
| Synopsys Design Compiler 2022.12 | `/eda/synopsys/2022-23/RHELx86/SYN_2022.12` | legacy DC synthesis |
| Synopsys Fusion Compiler 2022.12 | `/eda/synopsys/2022-23/RHELx86/FS-COMPILER_2022.12` | partition PnR |
| Synopsys IC Compiler II 2022.12 | `/eda/synopsys/2022-23/RHELx86/ICC2_2022.12` | NDM library mgmt |
| Synopsys Library Compiler 2022.12 | `/eda/synopsys/2022-23/RHELx86/LC_2022.12` | LEF/`.db` import |
| Synopsys Formality 2022.12 | `/eda/synopsys/2022-23/RHELx86/FM_2022.12` | LEC |
| Synopsys PrimeTime 2022.12 | `/eda/synopsys/2022-23/RHELx86/PT_2022.12` | ETM extraction |
| Mentor Calibre nmDRC 2023.1 | `/eda/mentor/calibre` | signoff DRC |
| Verilator | system | lint |
| Cadence HAL | system | lint |
| AMD/Xilinx Vivado | system | FPGA build |
| Python ≥ 3.8 + `cocotb` | system | cocotb harness |

PDK / IP roots:

| input | path on host |
|---|---|
| Arm IP library (CG092, BP210) | `/research/AAA/ip_library` (export as `ARM_IP_LIBRARY_PATH`) |
| TSMC cln65lp Arm-supplied PDK mirror | `/research/AAA/phys_ip_library/arm/tsmc/cln65lp/arm_tech/r2p0/` |
| TSMC tcbn65lp 9-track stdcell FE pack | `/home/dwn1c21/SoC-Labs/phys_ip/TSMC/65/CMOS/LP/stclib/9-track/tcbn65lp-set/tcbn65lp_220a_FE/` |
| TSMC cln65lp Calibre deck | `/home/dwn1c21/SoC-Labs/phys_ip/TSMC/65/CMOS/LP/pdk/Calibre/` |
| Precompiled cache memories | `/research/precompiled_mems/TSMC65/{flash_cache_data,flash_cache_tag}/` |
| TSMC tcbn65lp **BE** pack (NOT on host) | — needed to unblock Calibre coord extraction and zero-Short headless fix |

### 3.2 Clone + first-time setup

```bash
git clone git@git.soton.ac.uk:soclabs/ahb_qspi.git
cd ahb_qspi
git checkout master                  # or feat-nanosoc_int for the GDS scaffold
git submodule update --init          # picks up soctools_flow

source set_env.sh                    # exports SOCLABS_AHB_QSPI_DIR + SOCLABS_SOCTOOLS_FLOW_DIR
                                     # downloads SST26VF064B flash model on first run
                                     # defines fpga_use / fpga_release shell helpers
export ARM_IP_LIBRARY_PATH=/research/AAA/ip_library
```

The flash-model fetch in `set_env.sh` runs `make get_flash_model` (the
top-level `makefile` target) which wgets the Microchip ZIP into
`verif/VIP/`. If you're offline, drop a copy of `SST26VF064B.v` into
`verif/VIP/` manually.

### 3.3 cocotb-silicon (optional, for hardware regression)

The PYNQ hardware regression replays the cocotb suite on real silicon
through the [cocotb-silicon](https://git.soton.ac.uk/soclabs/cocotb-silicon)
package — checkout it out as a sibling of `ahb_qspi`:

```bash
cd ..
git clone git@git.soton.ac.uk:soclabs/cocotb-silicon.git
cd ahb_qspi && source set_env.sh     # auto-detects sibling; sets PYTHONPATH
```

### 3.4 fpgahub (optional, for FPGA workflows)

The FPGA harness leases boards via `fpgahub`. Install the client and
confirm:

```bash
which fpgahub                        # /home/<you>/.local/bin/fpgahub (shim)
fpgahub health                       # daemon reachable
fpgahub status                       # boards visible
```

See [fpga/SMOKE.md](fpga/SMOKE.md) for the 3-minute end-to-end smoke
test of the harness.

---

## 4. Flow reference

Every command below assumes you've sourced `set_env.sh` at least once.

### 4.1 Verilator lint

```bash
make lint_verilator                  # top-level: lints top_ahb_qspi against ahb_QSPI.flist
```

Source: [flows/makefile.lint](flows/makefile.lint). Output at
`lint/ahb_qspi/`. Used by the GitLab `verilator-lint` stage.

### 4.2 HAL lint (Cadence)

```bash
make -C lint lint                    # default: MODULE=top_ahb_qspi
make -C lint lint MODULE=qspi_controller   # standalone module
make -C lint lint-all                # every module (standalone + IP-deps)
make -C lint report                  # produce *_hal_report.txt
make -C lint gui                     # HAL GUI
```

Source: [lint/Makefile](lint/Makefile). Lintable modules:
`qspi_controller`, `qspi_clock_div`, `apb_qspi_regs`,
`ahb_qspi_interface`, `top_ahb_qspi`.

### 4.3 SpyGlass CDC

```bash
make -C cdc cdc                      # default: structural goal (cdc_verify_struct)
make -C cdc cdc SG_GOAL=cdc/cdc_verify   # full formal — HANGS at rule 429/533
make -C cdc cdc-report               # summarise the run
```

Source: [cdc/Makefile](cdc/Makefile). The structural goal completes in
minutes; the full formal `Ac_cdc` rule set does **not** terminate on
this design (documented at [docs/cdc_signoff_status.md](docs/cdc_signoff_status.md))
— so the structural verdict is the sign-off artefact. Reports under
`cdc/top_ahb_qspi/consolidated_reports/`.

### 4.4 Cocotb regression

```bash
make run_cocotb                      # top-level: VCS by default
make run_cocotb SIMULATOR=mti        # Questa
make run_cocotb SIMULATOR=icarus     # Icarus
make sim_cocotb                      # GUI variant (Verdi)
make run_cocotb TESTCASE=test_xip_basic   # single testcase
GATE_SIMS=yes make run_cocotb        # gate-level netlist replay
```

Source: [flows/makefile.simulate](flows/makefile.simulate) →
[verif/cocotb/makefile](verif/cocotb/makefile). Test plan at
[verif/cocotb/VPLAN.md](verif/cocotb/VPLAN.md). Outputs land under
`simulate/sim/cocotb/`.

### 4.5 UVM regression

```bash
make -C uvm/ahb_qspi compile         # build the testbench
make -C uvm/ahb_qspi run TEST=ahb_qspi_register_test
make -C uvm/ahb_qspi run_all         # full regression
make -C uvm/ahb_qspi coverage        # merged coverage report
make -C uvm/ahb_qspi waves           # run + VCD
```

Source: [uvm/ahb_qspi/Makefile](uvm/ahb_qspi/Makefile). Plan at
[uvm/ahb_qspi/VPLAN.md](uvm/ahb_qspi/VPLAN.md). Tests live in
`uvm/ahb_qspi/tests/`; sequences in `uvm/ahb_qspi/sequences/`.

### 4.6 Design Compiler synthesis (legacy)

```bash
cd asic/TSMC65nm
dc_shell -f dc_synthesis_core.tcl    # synthesises top_ahb_qspi (no pads)
dc_shell -f dc_synthesis.tcl         # synthesises with pad ring (ahb_qspi_pads)
```

Source: [asic/TSMC65nm/](asic/TSMC65nm/). Uses the **sc12 12-track**
Arm wrapper library — kept for CI parity but superseded by the
Fusion Compiler flow below. Outputs at `imp/ASIC/`.

### 4.7 Fusion Compiler partition flow (the primary ASIC flow)

This is the flow that produces the hardened `top_ahb_qspi` partition
hand-off package (LEF / DEF / GDS / SDF / SPEF / UPF / SVF).

```bash
make -C syn/asic/fusion-compiler help     # full target list
make -C syn/asic/fusion-compiler fc_all   # init → synth → cts → route → pg →
                                          # signoff → drc → abstract → LEC
                                          # (~35–45 min)
make -C syn/asic/fusion-compiler fc       # everything except LEC
make -C syn/asic/fusion-compiler fc_init  # stage 1 only
make -C syn/asic/fusion-compiler fc_synth # stage 2 only … etc.
make -C syn/asic/fusion-compiler gui      # fc_shell -gui on the live work dir
make -C syn/asic/fusion-compiler clean    # nuke work/libs/logs/reports/outputs
```

Source: [syn/asic/fusion-compiler/Makefile](syn/asic/fusion-compiler/Makefile).
Stage scripts in `syn/asic/fusion-compiler/scripts/`
(`1_init_design.tcl` through `7_drc.tcl`, plus
`6_partition_export.tcl` for the hand-off package). Shared PDK paths
in [syn/asic/common.mk](syn/asic/common.mk).

**Stage gates / sentinels.** Each stage saves an FC `save_block` alias
and touches a sentinel file (`.init.done`, `.synth.done`, …). `make
-j` is safe across stages because of the explicit sentinel dependency
chain. Resuming after a stage failure is just `make fc_<stage>` —
prior stages skip if their sentinel is current.

**Bounded waivers.** Two checks run as bounded waivers:

- `check_pg_connectivity` ≤ `FC_PG_CONN_FLOAT_MAX` (default 1300, 0
  macros) — set `FC_PG_CONN_WAIVER=0` to restore strict `==0`.
- `check_routes` ≤ `FC_ROUTES_DRC_MAX` (default 5, 0 opens) — set
  `FC_ROUTES_WAIVER=0` to restore strict `==0`.

The waiver implementation is at
[syn/asic/fusion-compiler/scripts/7_drc.tcl](syn/asic/fusion-compiler/scripts/7_drc.tcl);
methodology and rationale at
[docs/route_drc_shorts_analysis.md](docs/route_drc_shorts_analysis.md).

**Opt-in inputs.**

| variable / file | effect |
|---|---|
| `inputs/routing_rules.tcl` (copy from `.template`) | per-net NDR / antenna at `fc_route` |
| `ICV_DRC_RUNSET=<path>` | enable Synopsys ICV signoff DRC at `fc_drc` |
| `GDS_LAYER_MAP=<path>` | GDS stream-out (default in common.mk) |
| `TCBN65LP_BE=<path>` (on `feat-nanosoc_int`) | auto-wires stdcell GDS into the merged stream when the BE pack is present |

**Hand-off artefacts** (after `fc_abstract`): under
`syn/asic/fusion-compiler/outputs/` — see
[docs/chip_top_handoff.md §"What's in the deliverable"](docs/chip_top_handoff.md#whats-in-the-deliverable)
for the full manifest.

### 4.8 Formality LEC

```bash
make -C syn/asic/formality lec       # RTL ↔ FC gate netlist equivalence
make -C syn/asic/formality gui       # debug failing points (if any)
```

Source: [syn/asic/formality/Makefile](syn/asic/formality/Makefile).
Depends on the FC gate netlist from `fc_abstract`. The
`fc_all` target already runs this implicitly.

### 4.9 PrimeTime ETM extraction (scaffold)

```bash
make -C syn/asic/primetime etm
```

Source: [syn/asic/primetime/Makefile](syn/asic/primetime/Makefile).
**Scaffold only — not silicon-validated.** For hierarchical STA today,
prefer opening the partition's `.dlib` NDM block at
`syn/asic/fusion-compiler/work/top_ahb_qspi.dlib/top_ahb_qspi/design_label.signoff/`.

### 4.10 Calibre signoff DRC

```bash
make -C syn/asic/calibre calibre_drc                       # default stack 1p9m_6X2Z0U
make -C syn/asic/calibre calibre_drc STACK=1p9m_6X1Z1U     # alternate stack
```

Source: [syn/asic/calibre/Makefile](syn/asic/calibre/Makefile),
helper [syn/asic/calibre/run_drc.sh](syn/asic/calibre/run_drc.sh).
**Currently coord-blocked on this host:** the partition GDS lacks
tcbn65lp stdcell internals (no BE pack), so Calibre aborts on
"Cell <name> referenced but not defined" before reaching spacing
checks. On `feat-nanosoc_int`, [syn/asic/common.mk](syn/asic/common.mk)
has the auto-wiring — drop the BE pack into
`/home/dwn1c21/SoC-Labs/phys_ip/TSMC/65/CMOS/LP/stclib/9-track/tcbn65lp-set/tcbn65lp_220a_BE/`
and `GDS_STDCELL` populates automatically. Then re-run `fc_all`
followed by `calibre_drc` to surface Short coordinates.

### 4.11 FPGA build + deploy + stress

```bash
make -C fpga help                    # full target list
make -C fpga build_design            # Vivado: package IP + BD + .bit + .hwh  (~10 min)
make -C fpga package_ip              # just the IP packaging step

# Board-touching targets (require fpgahub):
make -C fpga program BOARD=pynq_z2_03_pl   # JTAG-program a leased board
make -C fpga deploy  BOARD=pynq_z2_03_pl   # scp + hot-load on PYNQ Linux
make -C fpga stress  BOARD=pynq_z2_03_pl   # deploy + pynq.stress.runner
make -C fpga ci_full BOARD=pynq_z2_03_pl   # deploy + stress in one lease
make -C fpga resolve_board                 # print resolved SSH coords
```

Source: [fpga/Makefile](fpga/Makefile), harness
[fpga/harness/fpga.mk](fpga/harness/fpga.mk). End-to-end walkthrough
at [fpga/SMOKE.md](fpga/SMOKE.md).

**Board selection.** Use `BOARD=<name>` for a specific board or
`BOARD_TAG=<capability>` (e.g. `qspi_flash_pmod`) to lease by tag.
Without either, the harness picks the first available board.

**Bitstream artefacts** land at `imp/fpga/output/pynq-z2/qspi.bit` +
`qspi.hwh`. The harness needs both.

### 4.12 PYNQ hardware regression + cocotb-on-silicon

```bash
make -C fpga cocotb_hw BOARD=pynq_z2_03_pl   # replay cocotb suite on real silicon
                                              # via cocotb-silicon package
```

The cocotb-silicon adapter at [pynq/cocotb_silicon_adapter.py](pynq/cocotb_silicon_adapter.py)
re-binds DUT signals to PYNQ memory-mapped registers. Design notes:
[docs/cocotb-silicon-design.md](docs/cocotb-silicon-design.md);
on-hardware findings: [docs/cocotb-silicon-findings.md](docs/cocotb-silicon-findings.md).

Pure-PYNQ stress-suite (independent of cocotb):

```bash
# On the board, after fpga/deploy:
python3 -m pynq.stress.runner --budget 60   # 60-second stress run
```

---

## 5. CI pipeline

[.gitlab-ci.yml](.gitlab-ci.yml) — 8 stages, top-to-bottom:

| stage | job(s) | gate |
|---|---|---|
| 1. setup | `clone`, `preflight`, `fetch-deps` | always |
| 2. lint | `verilator-lint`, `hal-lint` | always |
| 3. cdc | `spyglass-cdc` | always (structural goal only) |
| 4. regression | `cocotb-regression` (8 tests, VCS+coverage) | always |
| 5. coverage | `coverage-report` | always |
| 6. synthesis | DC synth + opt-in Fusion Compiler partition PnR + LEC | manual (set `RUN_FC_PNR=1`) |
| 7. fpga-deploy | `fpga-deploy`, `fpga-hw-regression` | manual (set `FPGAHUB_BOARD` / `FPGAHUB_BOARD_TAG`) |
| 8. cleanup | `cleanup` | always |

Tool paths and the `ARM_IP_LIBRARY_PATH` are baked into the `variables:`
block at the top of the file. When porting to a different runner,
update those paths first; everything else follows.

---

## 6. Documentation map

- [README.md](README.md) — IP overview, register map, FPGA + ASIC top-line state
- [docs/chip_top_handoff.md](docs/chip_top_handoff.md) — **short-form package for the chip-top integrator**
- [docs/route_drc_shorts_analysis.md](docs/route_drc_shorts_analysis.md) — engineering reference for the 2 routing Shorts + all 11 PnR levers tried
- [docs/backend_shorts_resolution_guide.md](docs/backend_shorts_resolution_guide.md) — beginner walkthrough on what the Shorts are and how to fix them
- [docs/mr_description.md](docs/mr_description.md) — paste-ready MR description for the partition hand-off branch
- [docs/cdc_signoff_status.md](docs/cdc_signoff_status.md) — CDC verification state + why the formal goal hangs
- [docs/cocotb-silicon-design.md](docs/cocotb-silicon-design.md) + [findings](docs/cocotb-silicon-findings.md) — replaying cocotb on PYNQ
- [docs/xip_cocotb_failures_brief.md](docs/xip_cocotb_failures_brief.md) + [findings](docs/xip_cocotb_failures_findings.md) — XiP debug
- [docs/qspi-flash-recovery-c-driver-spec.md](docs/qspi-flash-recovery-c-driver-spec.md) — C-driver recovery for nanoSoC boot
- [docs/qspi_controller_optimisation_plan.md](docs/qspi_controller_optimisation_plan.md) — RTL optimisation log
- [docs/CG092_bus_logic_bug_report.md](docs/CG092_bus_logic_bug_report.md) — upstream Arm IP bug findings
- [docs/dma_master_port_bug_plan.md](docs/dma_master_port_bug_plan.md) — DMA master port debugging plan
- [syn/asic/fusion-compiler/INTEGRATION_CHANGES.md](syn/asic/fusion-compiler/INTEGRATION_CHANGES.md) — **the running narrative of every PnR experiment** (1100+ lines, every committed disposition)
- [syn/asic/fusion-compiler/FLOW_COMPARISON.md](syn/asic/fusion-compiler/FLOW_COMPARISON.md) — DC synth vs FC partition flow side-by-side
- [verif/cocotb/VPLAN.md](verif/cocotb/VPLAN.md) — cocotb verification plan
- [uvm/ahb_qspi/VPLAN.md](uvm/ahb_qspi/VPLAN.md) — UVM verification plan
- [fpga/SMOKE.md](fpga/SMOKE.md) — FPGA harness smoke test
- [pynq/README.md](pynq/README.md) — PYNQ-side overlay + stress runner

---

## 7. First-day playbook

A reasonable order to verify your replica is working end-to-end:

1. **Source the environment.** `source set_env.sh` (then `export
   ARM_IP_LIBRARY_PATH=/research/AAA/ip_library`).
2. **Cocotb smoke test.** `make run_cocotb` — should finish in
   ~5 min and report all tests passing.
3. **Lint smoke.** `make lint_verilator` + `make -C lint lint`.
4. **CDC smoke.** `make -C cdc cdc` — structural goal, ~5 min.
5. **Fusion Compiler from-clean.** `make -C syn/asic/fusion-compiler
   clean && make -C syn/asic/fusion-compiler fc_all` — ~35–45 min,
   should print `RESULT: CLEAN (2 WAIVERS)` and `FM_LEC_OK`.
6. **FPGA smoke** (if you have fpgahub access): follow
   [fpga/SMOKE.md](fpga/SMOKE.md) — 3 min.

If all six pass, the replica is faithful. Anything failing here is
either a host/PDK path mismatch (start at §3.1) or a stale checkout.

---

## 8. Contacts

Original development (RTL + verification + FPGA + DC synth):
**David Mapstone** (d.a.mapstone@soton.ac.uk).

Partition flow (Fusion Compiler), backend Shorts characterisation,
Calibre wiring, and this hand-off bundle: see the `INTEGRATION_CHANGES.md`
log for the commit-by-commit trail.
