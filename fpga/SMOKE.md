# FPGA harness smoke test

A reproducible walkthrough that exercises every public target in
[harness/fpga.mk](harness/fpga.mk) against a real PYNQ-Z2. Run it after
changes to anything under `fpga/harness/`, after the fpgahub daemon
config rolls over, or whenever you onboard a new host that has the
fpgahub client installed.

Total wall-clock: **~3 min** (lease + scp + 60 s stress).

---

## 0. Prerequisites

Confirm in one go:

```bash
which fpgahub                          # /home/<you>/.local/bin/fpgahub (shim)
fpgahub health                         # daemon reachable
python3 -c 'import json'               # stdlib only; no jq needed
fpgahub status                         # at least one PYNQ-Z2 board listed
```

You also need a built bitstream — for this repo it lives at
[imp/fpga/output/pynq-z2/qspi.bit](../imp/fpga/output/pynq-z2/qspi.bit).
If it's missing, `cd ..; source set_env.sh; make -C fpga build_design`
first (Vivado, ~10 min).

Per-shell setup (the harness reads `SOCLABS_AHB_QSPI_DIR` and
`ARM_IP_LIBRARY_PATH`; `set_env.sh` exports both):

```bash
cd /home/<you>/SoCLabs/ahb_qspi
source set_env.sh
```

> **Short-name DNS.** fpgahub returns `david@mapstone-dev` as the dev
> host. The harness auto-appends `FPGAHUB_DEFAULT_DOMAIN`
> (default `ecs.soton.ac.uk`) when the short name doesn't resolve, so
> no SSH-config alias is required — but adding one cleans up the logs:
> ```
> echo -e '\nHost mapstone-dev\n    HostName mapstone-dev.ecs.soton.ac.uk' \
>     >> ~/.ssh/config
> ```

---

## 1. Pick a board

This walkthrough uses `pynq_z2_01_pl` — unpaired, free, has
`qspi_flash_pmod` for the QSPI overlay. Substitute any other
PYNQ-Z2 with the same capability.

```bash
fpgahub board show pynq_z2_01_pl       # shows capabilities, network, pair status
fpgahub lease show pynq_z2_01_pl       # should say "not leased" before you start
```

If you don't care which board:

```bash
fpgahub board list --capability qspi_flash_pmod
```

…and pick any row whose `lease_state` is `none`.

---

## 2. Resolve coords (no lease taken)

`resolve_board` prints what the harness would use without touching
anything. Use it to sanity-check `host_ssh` / `host_proxy` /
`host_dev_host` before a real run.

```bash
make -C fpga resolve_board BOARD=pynq_z2_01_pl
```

Expected:

```
board=pynq_z2_01_pl
ssh=xilinx@192.168.2.101
proxy=-                                 # blank → harness falls back to dev_host
dev_host=david@mapstone-dev
lease=none
```

---

## 3. Deploy the bitstream

Leases the board, scp's `qspi.{bit,bin,hwh}` + the [../pynq/](../pynq/)
directory to `/home/xilinx/qspi_overlay/`, then hot-loads via
`fpga_manager`. Releases on exit.

```bash
make -C fpga deploy BOARD=pynq_z2_01_pl
```

Expected tail:

```
with_lease.sh: leased pynq_z2_01_pl (ttl=3600s) ssh=xilinx@192.168.2.101 proxy=david@mapstone-dev.ecs.soton.ac.uk
[deploy] target xilinx@192.168.2.101 (via david@mapstone-dev.ecs.soton.ac.uk)
…SCP transfers…
[deploy] hot-loading qspi.bin via fpga_manager
[sudo] password for xilinx: fpga_manager state: operating
[deploy] done
```

The `state: operating` line is the success signal — anything else
(`unknown`, `state: power_off`) means the firmware copy or
`/sys/class/fpga_manager/fpga0/firmware` write failed.

Verify the lease released:

```bash
fpgahub lease show pynq_z2_01_pl       # expect: not leased
```

---

## 4. Stress test (short budget)

Same lease + deploy as before, then runs `python3 -m stress.runner`
over SSH for the given budget. Default `FPGA_STRESS_BUDGET=300` (5 min);
override to 60 s for a smoke:

```bash
make -C fpga stress BOARD=pynq_z2_01_pl FPGA_STRESS_BUDGET=60
```

The stress runner writes a JSON summary to
`./qspi_stress_summary.json` on the board. Expected final log lines:

```
stress.runner INFO STRESS RUN COMPLETE: 0 failure(s) across 6 test(s) in 1.4 min
stress.runner INFO Summary written to ./qspi_stress_summary.json
[stress] done
```

Six phases run in this order: `soak`, `xip_torture`, `mode_flip`,
`concurrent`, `clk_div_sweep`, `irq_storm`. **0 failures** is the
pass criterion. Anything non-zero needs investigation —
[pynq/scripts/stress_bisect.sh](../pynq/scripts/stress_bisect.sh)
isolates which phase regressed.

---

## 5. Serial / network probe (optional)

Verifies the pynq-side scripts pick up `host_dev_host` from fpgahub.

```bash
# Probe the board over its FTDI UART; writes pynq/board.json
BOARD=pynq_z2_01_pl bash pynq/scripts/refresh_board.sh

# Background-capture serial for 5 s, then stop
BOARD=pynq_z2_01_pl bash pynq/scripts/serial_capture.sh
sleep 5
BOARD=pynq_z2_01_pl bash pynq/scripts/serial_capture.sh --stop
ls -lh pynq/logs/serial-*.log | tail -1
```

`refresh_board.sh` should write [../pynq/board.json](../pynq/board.json)
with the live board IP / MAC / hostname. The serial-capture log will be
small (no console activity unless something is printing on UART).

---

## 6. Program via JTAG (admin token only)

```bash
make -C fpga program BOARD=pynq_z2_01_pl
```

This hits an admin endpoint on the fpgahub daemon. Without
`FPGAHUB_TOKEN=<bearer>` exported it fails with `HTTP 401: admin
endpoint: present a Bearer token` — that's expected, **not** a harness
bug. Ask the fpgahub admin to mint you a token
(`fpgahub token create … --role write`). The `deploy` path above
needs only mTLS, so use it for day-to-day bring-up.

---

## What "all good" looks like

After steps 2–5, this snapshot:

```bash
fpgahub lease show pynq_z2_01_pl       # not leased
ls fpga/harness/ fpga/harness/scripts/
# fpga.mk
# scripts:
# bit2bin.py  deploy_and_stress.sh  deploy_overlay.sh  run_stress.sh  with_lease.sh
```

And inside the most recent stress run's output you saw
`STRESS RUN COMPLETE: 0 failure(s) across 6 test(s)`.

---

## Common failures and where to look

| Symptom | Most likely cause | Fix |
|---|---|---|
| `with_lease.sh: lease acquire failed` with HTTP 409 | Another user holds the lease | Pick a different board, or wait for `lease_expires_at` |
| `ssh: connect to host 192.168.X.Y port 22: Connection timed out` | Daemon's `host_proxy` was empty and `host_dev_host` is unreachable | Confirm `make resolve_board` reports a working `dev_host`; otherwise SSH-test it manually |
| `ssh: Could not resolve hostname mapstone-dev` | `FPGAHUB_DEFAULT_DOMAIN` doesn't apply on your host | Export a working `FPGAHUB_DEFAULT_DOMAIN=…` or add an SSH alias |
| `[sudo] password for xilinx:` hangs | Default `FPGA_PASSWORD=xilinx` no longer correct for that board | Set `FPGA_PASSWORD=<actual-password>` on the `make` line |
| `BITSTREAM argument is required` from `fpgahub board program` | Missing admin token | See step 6 |
| `fpga_manager state: unknown` after deploy | Bitstream / part mismatch, or `/lib/firmware/<FPGA_FIRMWARE_NAME>` copy failed | Re-check `FPGA_FIRMWARE_NAME` matches what's actually written to firmware |
| `ERROR: harness inputs unset: …` | Project Makefile didn't set the listed `FPGA_*` variable before including `harness/fpga.mk` | Set it; see the comment block at the top of [harness/fpga.mk](harness/fpga.mk) |

---

## Cleanup

Nothing to do — the harness releases the lease on every exit path
(success, error, Ctrl-C). If a runaway lease ever survives, drop it
by hand:

```bash
fpgahub lease show <board>             # grab the token
fpgahub lease release <board> --token <token>
```
