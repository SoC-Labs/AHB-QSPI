# H-PIPE regression tests for `ahb_qspi_interface`

These benches guard the fix for **H-PIPE** and the related AHB-Lite slave
defects in `logical/ahb_qspi_interface/logical/ahb_qspi_interface.sv`:

| Defect | What went wrong before the fix |
|---|---|
| H-PIPE, WAIT_READ leg | A read accepted in the cycle the previous read completed was never fetched. It completed OKAY with the previous line, or with the next transfer's line. |
| H-PIPE, ERR2 leg | A transfer accepted in the second ERROR cycle was dropped. A write got OKAY instead of ERROR. A read got stale or X data. |
| Deadlock | Read, then back-to-back read, then a NONSEQ to another slave: HREADYOUT stayed low forever. |
| IDLE ignored HREADY | On a multi-slave bus, a waited address phase caused a one-cycle ERROR or a phantom fetch. |
| Stale ACK after a watchdog | After a watchdog ERROR, the next read could complete OKAY from the wedged transaction's acknowledge, with no fetch. |
| HRDATA not reset | HRDATA was X after reset. |

All of the harnesses below were written by the independent assessors of AHB-QSPI
PR #1 (13 Oct 2026). They are copied here so the defects stay fixed.

| Dir | Source | Changes from the source |
|---|---|---|
| `cocotb_a1/` | Assessor A1, `~/SoCLabs/qspi-assess-A1`, branch `assess/A1` 0c3ca6c, `verif/cocotb_a1/` | The tb, the AHB master and protocol checker, and the 21 tests are unchanged. The Makefile default paths moved with the directory. `run_a1.sh` simulates a tree in place instead of exporting a commit. |
| `formal/` | Assessor A2, `~/SoCLabs/qspi-assess-A2`, branch `assess/A2` 80e2ee8, `formal/ahb_qspi_interface/` and `formal/tools/vcdtable.py` | A2's checks are unchanged. Additions, all behind defines: `*_wdsr*` checks (watchdog with a short soft-reset pulse, so reads after the soft reset fall inside the BMC depth), the `cover_wdsr` non-vacuity cover, and `hpipe_inv.svh` helper invariants for k-induction. |
| `tb_hpipe/` | Assessor A3, `~/SoCLabs/qspi-assess-A3-ip`, branch `assess/A3` f1961d6, `verif/assess_a3/` | Case T0 was added (HRDATA known after reset). The work dir moved to `simulate/`. |
| `plants.py` | New. Plants H1-H8 are new. P*/A2_* re-create A1's and A2's plants on the fixed RTL. | - |

## How to run

Every job is single-threaded. Run them one at a time under `nice -n 19`.

```bash
cd <this checkout>
export PATH=$HOME/miniconda3/bin:$PATH PYTHONDONTWRITEBYTECODE=1  # cocotb 2.0.1
# 1. A3 standalone bench (VCS, about 10 s). Exit 0 = pass.
nice -n 19 verif/hpipe/tb_hpipe/run.sh
# 2. A1 cocotb tests (VCS, about 17 min). Needs verif/VIP/SST26VF064B.v.
nice -n 19 verif/hpipe/cocotb_a1/run_a1.sh
# 3. A2 formal (SymbiYosys, about 1 h for BMC + covers).
F=$PWD/logical/ahb_qspi_interface/logical/ahb_qspi_interface.sv
verif/hpipe/formal/run_all.sh $F $PWD/simulate/hpipe/formal bmc cover
# 4. k-induction with the helper invariants
INV=1 PROVE_K=<k> verif/hpipe/formal/run_all.sh $F $PWD/simulate/hpipe/formal-prove prove
```

To run against another tree, use `RTL_DIR=<tree>` for `run_a1.sh`, pass
`<tree>` as the argument of `tb_hpipe/run.sh`, or pass that tree's interface file
to the formal scripts.

### Expected results

| Bench | On the fix | On c8af8ee (master with PR #1, before the fix) |
|---|---|---|
| `tb_hpipe` | T0-T5 PASS, 0 errors | T0, T1, T2, T4 FAIL |
| `cocotb_a1` | 20/21. The one FAIL is `a1_q1_apb_frames_and_clocks`, the separate QPI command-only defect (`qspi_controller.sv:271`), which is out of scope here. | 10/21 |
| formal BMC | every check PASS; every cover reached | P1/P2/P6 model, rdonly, wd and multi checks FAIL; P4 multi FAILs |

## Planted defects

```bash
python3 verif/hpipe/plants.py --list
python3 verif/hpipe/plants.py . simulate/hpipe/plants            # all plants
RTL_DIR=$PWD/simulate/hpipe/plants/H1_wr_exit_drop verif/hpipe/cocotb_a1/run_a1.sh /tmp/x a1_q3_read_read
```

Plants are scratch copies. Never commit one.
