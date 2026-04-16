# AHB QSPI Stress Test Suite

Six time-bounded stress tests that exercise the controller for ~20 minutes
end-to-end. Independent of the cocotb test runner — these are written
natively against the [QspiOverlay](../qspi_overlay.py) and don't need the
cocotb stub layer.

## Layout

| File | Purpose |
|---|---|
| [runner.py](runner.py) | CLI entry point, time budgeting, JSON failure log, summary output |
| [tests.py](tests.py) | The six test functions and the `ALL_TESTS` registry |
| [qspi_hw.py](qspi_hw.py) | Synchronous `QspiHw` wrapper around the APB register bank — opcode helpers, page program, FAST_READ, sector erase, XiP setup |
| [prbs.py](prbs.py) | Address-keyed xorshift32 PRBS so any byte can be regenerated from its address |
| [sector_state.py](sector_state.py) | Persistent next-sector-to-erase cursor (default `~/.qspi_stress_state`) so wear spreads across runs |

## The six tests

| Name | Default budget | What it stresses |
|---|---:|---|
| `soak` | 8 min | Per-page write/verify on rotating sectors. Catches data integrity, page-program timing, sustained CDC margin. |
| `xip_torture` | 4 min | Random AHB MMIO reads against a pre-programmed PRBS window. Catches XiP path bugs, cache coherence, byte-swap correctness. |
| `mode_flip` | 3 min | Rapid SPI ↔ QPI mode transitions. Catches FSM stuck states, ENABLE_ACK latch regressions. |
| `concurrent` | 3 min | Background AHB XiP reads + foreground APB CLK_DIV reconfigs. Catches bus-arbitration and mid-flight register-write bugs. |
| `clk_div_sweep` | 1.5 min | Read-verify cycles at every CLK_DIV in [2..31]. Maps reliability vs SPI clock frequency. |
| `irq_storm` | 1 min | Back-to-back single-byte reads at minimum CLK_DIV. Catches IRQ_CLR/BUSY/ENABLE handshake regressions. |

## Wear management

The PmodSF3 (N25Q256A) is rated for **~100k erase cycles per sector**. The
runner spreads erases across all 256 sectors of the lower 16 MB via the
`SectorRotator`, persisted to `~/.qspi_stress_state`. A single full 20-min
run touches ~30–40 sectors at most; you can run the suite hundreds of times
before approaching the wear limit. Reset the rotator with
`--reset-rotator` if you want to start the cursor over.

## Running

After `make deploy` has copied the overlay to `/home/xilinx/qspi_overlay/`:

```bash
ssh xilinx@pynq.local
cd /home/xilinx/qspi_overlay
sudo python3 -m stress.runner                       # all tests, ~20 min
sudo python3 -m stress.runner --tests soak xip_torture
sudo python3 -m stress.runner --budget 1800         # rescale to 30 min total
sudo python3 -m stress.runner --tests irq_storm -v  # one test, debug log
sudo python3 -m stress.runner --reset-rotator       # restart sector cursor at 0
```

Outputs:

* `qspi_stress_failures.jsonl` — append-only, one JSON record per failure
  (test name, wall time, elapsed, expected/actual, address). Survives across runs.
* `qspi_stress_summary.json` — overwritten each run; per-test stats
  (sectors erased, pages verified, miscompares, per-CLK_DIV failure counts, etc.)

Exit code is 0 if zero failures, 1 if any test recorded a failure, 2 if the
ID-readback sanity check failed (AXI/APB path is broken — no point running
anything else).

## Adapting to a different flash

Defaults assume a Micron PmodSF3 (manufacturer ID 0x20). For an SST
SST26VF064B set the manufacturer ID expected by `mode_flip`:

```python
# In tests.py, wire through to the runner CLI if you do this often:
test_mode_flip(hw, ctx, expected_id_mfg=0xBF)
```

The other tests are device-agnostic - they only use the standard SPI
opcodes (FAST_READ 0x0B, PAGE_PROGRAM 0x02, SECTOR_ERASE 0xD8, WREN 0x06,
RDSR 0x05) which are universal across SPI flash vendors.

## Extending

Adding a 7th test:

1. Write a `def test_<name>(hw, ctx, **kwargs):` function in [tests.py](tests.py)
   that respects `ctx.deadline` and reports failures via `ctx.fail(...)`.
2. Add it to `ALL_TESTS` and `DEFAULT_BUDGETS`.
3. The runner will pick it up automatically.

`ctx.summary[name]` is the right place to stash per-test counters so they
end up in the summary JSON.
