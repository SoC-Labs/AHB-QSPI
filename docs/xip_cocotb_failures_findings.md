# Findings: 5 failing XIP cocotb tests — root-cause diagnosis

**Investigator hand-off response to** `docs/xip_cocotb_failures_brief.md`.
**Date:** 2026-05-18. **Branch:** `feat-nanosoc_int`. **Simulator:** vcs
(T-2022.06-SP2), cocotb + cocotbext-ahb **0.5.1**, py3.10 (miniconda3).

## TL;DR verdicts

| Failure mode | Tests | Root cause | Verdict |
|---|---|---|---|
| **2 — "cache never reaches READY"** | `test_xip_plain_spi_no_flash_write`, `test_xip_plain_spi_fast_read_line_fill`, `test_xip_plain_spi_slow_read_line_fill` | **Test-harness bug.** The CG092 cache *does* reach READY; the open-coded poll loops read **one** register per iteration with a `Timer` between iterations, which trips a cocotbext-ahb 0.5.1 master limitation against the spec-compliant `cmsdk_ahb_to_apb` bridge (HREADYOUT=1 while idle ⇒ master reads **stale registered HRDATA** and never issues a fresh APB read). **NOT an RTL bug.** | Harness / test-pattern gap. RTL is correct. |
| **1 — "X/Z on the QPI line-fill AHB path"** | `test_xip_qpi_no_cont_read_no_nocmd`, `test_xip_qpi_no_cont_read_warmup` | **Verification-integration gap (load-bearing warmup confirmed).** Without the cont_read warmup the qspi_controller never emits the QPI **mode byte** (FSM `MODE` state is gated on `qspi_cont_read_latched`), but the SST26VF064B model's `SQI_HS_READ` *unconditionally* consumes a 2-nibble Mode_Configuration field. Protocol framing desyncs, the flash never drives the IO bus, Z propagates to AHB `HRDATA`. | Not a tape-out RTL bug *for the QPI+cont_read silicon use-case*, **but** a real controller/flash protocol constraint: QPI `0x0B` line-fill is only valid in continuous-read mode. Stage-0 / silicon must always perform the cont_read warmup (or the controller must be taught a non-cont-read QPI framing). |

Both modes are **pre-existing** and **independent of** the uncommitted
QSPI_RDATA read-mux change (confirmed: mode-1 Z originates at the SST26
IO pins, never reaching the read-mux with valid data; mode-2 never does
a flash access at all). Not related to the `test_qspi_partial_byte_read_ordering`
xfail.

---

## Reproduction (all 4 runs done with the brief's command)

```
export SOCLABS_AHB_QSPI_DIR=/home/dam1n19/SoCLabs/ahb_qspi
export SOCLABS_SOCTOOLS_FLOW_DIR=$SOCLABS_AHB_QSPI_DIR/soctools_flow
export ARM_IP_LIBRARY_PATH=/research/AAA/ip_library
make run_cocotb SIMULATOR=vcs TESTCASE=<name>
```

| Test | Result | Sim time | Signature |
|---|---|---|---|
| `test_xip_plain_spi_no_flash_write` | FAIL | 5,009,940 ns | `Cache did not reach READY (STATUS & 0x3 stuck at 0x1)` |
| `test_xip_plain_spi_fast_read` (contrast) | **PASS** | 37,760 ns | — uses `_xip_baseline_minus` |
| `test_xip_qpi_no_cont_read_no_nocmd` | FAIL | 79,370 ns | `Timeout 5000 clk — AHB.SLAVE signals are not resolvable` (line 1328, the **data** master XIP read) |
| `test_xip_qpi_no_nocmd` (contrast) | **PASS** | 34,230 ns | — does the cont_read warmup |

`$dumpvars` in `verif/cocotb/ahb_qspi_cocotb.v` produced a full-hierarchy
VCD per run (`verif/cocotb/ahb_qspi.vcd`, git-ignored). Diagnostic VCDs
were copied to `/tmp/vcd_*.vcd` (scratch; not committed). No source files
were modified.

---

## Failure mode 2 — "cache never reaches READY" (3 tests)

### The cache **does** reach READY — proven by VCD

In `test_xip_plain_spi_no_flash_write` (CCR write at HCLK ~478 µs-tick),
tracing CG092 core internals
(`u_cache_subsystem.u_cache_controller.u_p_flash_cache_f0_core`):

```
   t(ns)   reg_enable_fsm  cache_enabled  mux_status_1_0  sr_cs
   480000   ccr_wr_en_int=1
   482000   001                            01
   487000   010
   743000   011
   744000   100             1
   745000   101                            10            (READY)
   746000   101                                          10  ← SR=READY
   ... stays 10 for the entire remaining 5 ms ...
   500993000 (teardown CCR=0) cache_enabled→0
```

CG092 `p_flash_cache_f0_core.v` decodes `reg_enable_fsm` → status bits:
`3'b101 ⇒ sr_cs = 2'b10` ("Enabled"), surfaced at SR (offset 0x4)
`ip_rdata[1:0]`. **The cache is genuinely READY at ~746 µs-tick and stays
READY.** The assertion ("stuck at 0x1") is therefore false-negative — the
hardware is fine; the test never *observes* the new value.

### Why the test never observes READY — only ONE real APB read happens

Counting `cmsdk_apb_slave_mux` PSEL1 (cache select) rising edges over the
**entire 5 ms** sim: **exactly 3** — the enable CCR write (~479 µs-tick),
**one** SR read (~483 µs-tick, *before* READY), and the teardown CCR write
(~500.99 ms-tick). The 500-iteration poll loop issues ~499 further SR
"reads" that **never reach the cache**.

Config-AHB / `cmsdk_ahb_to_apb` bridge trace:

* First SR read (t≈482–485 µs-tick): bridge FSM `state_reg`
  `000→010→011→100`, real APB cycle, returns `HRDATA=0x1` (correct — cache
  was still "Enabling" at that instant).
* t=486000: cocotb master idles `config_HREADY_IN→0`.
* Every later poll read (t≈1.486 ms, 2.487 ms, 3.488 ms, … ~1 ms apart):
  `config_HSEL`/`config_HTRANS` assert and de-assert **in the same
  timestamp** (zero-width). Bridge `state_reg` **stays `000` (ST_IDLE)**.
  No APB transaction. `config_HRDATA` stays frozen at the stale `0x1`.

### The mechanism — cocotbext-ahb 0.5.1 vs spec-compliant bridge

`cmsdk_ahb_to_apb.v` drives `HREADYOUT = 1'b1` in `ST_IDLE` (line ~288),
and with `REGISTER_RDATA(1)` (set in `ahb_qspi_cocotb.v`) it **holds the
last read data on HRDATA while idle**. This is correct AHB-Lite.

cocotbext-ahb `ahb_master.py` `_send_txn()` builds a single read as a
2-element non-pipelined vector `[addr, default]`:

* index 0: `_addr_phase()` (HSEL/HTRANS/HREADY_IN=1), one `RisingEdge`,
  then `while self.bus.hready.value != 1:` (line 261). `self.bus.hready`
  maps to the slave `HREADYOUT` (= `config_HREADY`).
* Because the bridge is in ST_IDLE with `HREADYOUT==1` **before** it
  samples the new address, the `while` exits **immediately**.
* index 1 (`==len-1`): `_reset_bus()` tears HSEL/HTRANS down in the same
  cycle — the bridge FSM never leaves ST_IDLE, no APB cycle is generated,
  and the returned data is the **stale registered `config_HRDATA`** from
  the previous real read.

So every single-register poll iteration returns the value captured by the
*first* SR read (0x1, taken before the cache was ready) → "stuck at 0x1"
forever, even though the cache reached READY at ~746 µs-tick.

### The decisive contrast — why the passing tests pass

`test_xip_plain_spi_fast_read` / `_minimum` / `_line_fill_clkdiv_sweep`
all go through **`_xip_baseline_minus`**, whose poll loop issues **two
back-to-back reads per iteration** (CONFIG @0x1000 *then* SR @0x1004,
**no Timer between them**). VCD of the passing `test_xip_plain_spi_fast_read`,
one poll iteration:

```
 t=3046000  read 0x1000 (CONFIG)  ← zero-width glitch, stale HRDATA
 t=3047000  read 0x1004 (SR)      ← held a full cycle, REAL APB cycle
 t=3050000  HRDATA = 0x12         ← FRESH:  0x12 & 0x3 == 2  ⇒ READY ⇒ break ⇒ PASS
```

The *second* read of the pair lands while the bus is still in its
post-first-read non-idle window, so it generates a real APB transaction
and returns fresh SR data. The 3 failing tests open-code a **single**
SR read per iteration with a `Timer(10 µs)` between iterations — every
read finds the bridge idle ⇒ stale data ⇒ never sees READY.

This is exactly the "load-bearing pre-read / per-iter read" behaviour the
test-file comment at `ahb_qspi_tests.py:1237–1245` describes
("Omitting any of steps 1/3/4 leaves STATUS stuck at 0x1 … feels like a
read-side ACK handshake in the CG092 reg block") and the
"HRDATA-from-previous-beat vs HRDATA-for-current-HADDR" note in
`docs/dma_master_port_bug_plan.md`. It is **not** a CG092 reg-block
handshake bug — it is a cocotbext-ahb master limitation against an idle
slave that legitimately keeps `HREADYOUT=1`.

### Verdict — mode 2: test-harness bug, RTL is correct

The CG092 cache, the `cmsdk_ahb_to_apb` bridge, and the QSPI datapath are
all behaving correctly and spec-compliantly. The 3 failures are an
artefact of cocotbext-ahb 0.5.1 mis-handling a single read to a slave
that holds `HREADYOUT=1` while idle. **No RTL change required for these.**

Real silicon is unaffected: a CPU/PL230 load to the SR register issues a
proper AHB transfer (address held until `HREADYOUT` is sampled in the
*data* phase), so it always gets fresh data. The
`nanosoc-ethernet-flash-system` stage-0 spin-on-SR loop is fine on
hardware (consistent with `dma_master_port_bug_plan.md`: "Cache reaches
READY normally … 1→2 at +267 cycles").

### Recommended fix (test-only — reported, not applied)

Make the 3 open-coded poll loops mirror `_xip_baseline_minus`: per
iteration do **two reads** (a throwaway CONFIG read at `CACHE_CONFIG_ADDR`
immediately followed by the SR read at `CACHE_CONFIG_ADDR + 0x04`, with
**no `await Timer` between the two**). Equivalent minimal alternative:
issue a dummy `read(CACHE_CONFIG_ADDR)` right before each SR read. Either
defeats the stale-registered-HRDATA artefact and lets the tests observe
the READY the cache genuinely reaches at ~746 µs-tick. (A cleaner
long-term fix is upgrading/patching cocotbext-ahb so a single read holds
the address phase until it samples a fresh data-phase `HREADYOUT`, but
that is outside this repo.)

Locations: `verif/cocotb/ahb_qspi_tests.py`
`test_xip_plain_spi_no_flash_write` poll at lines 1431–1443; shared
`_xip_plain_spi_fill_body` poll at lines 1528–1536.

---

## Failure mode 1 — "X/Z on the QPI line-fill AHB path" (2 tests)

### Where the X/Z originates — at the SST26 IO pins

`test_xip_qpi_no_cont_read_no_nocmd` (`_xip_baseline_minus`,
`qio_mode=True, no_cmd=False, cont_read_warmup=False`). The cache reaches
READY normally (`sr_cs=10` at ~2.184 ms-tick — mode 2 doesn't bite here
because `_xip_baseline_minus` does the two-read poll). The failure is the
**data-master XIP read** (`ahb_qspi_tests.py:1328`). VCD chain at the
failing read (`addr=0xA000`, starts ~2.937 ms-tick):

```
 qspi_controller FSM: IDLE→OP→ADDR→DUMMY→DATA_I
 t=2986000  qspi_controller QSPI_IO_e = 0   (turnaround: controller tristates IO)
 t=2986000  SST26 SIO = zzzz
 t=2986000..3128000  SCK keeps toggling, SST26 SIO STAYS zzzz  ← flash never drives
 t=3004000  qspi_controller.QSPI_RDATA  = ...zzzz...   (shifting in Z)
 t=3143000  ahb_qspi_interface.HRDATA   = ...0000zzzzzzzz, qspi_ready=1
            → Z propagates to cache flash_HRDATAM → cache line fill →
              data-AHB HRDATA → cocotbext-ahb resolvability check trips
```

The X/Z is **not** generated anywhere in the RTL datapath — it is the
**flash failing to drive its IO bus**, then high-Z faithfully propagated
through controller → `ahb_qspi_interface` → CG092 → AHB. (`AHB_QSPI_RDATA_i`
byte-swizzle and the uncommitted QSPI_RDATA read-mux are downstream of
already-Z data — they are *not* the cause.)

### Why the flash doesn't drive — protocol-framing mismatch

`verif/VIP/SST26VF064B.v` `SQI_HS_READ` (opcode `0x0B` in QPI/SQI mode),
lines 1713–1744:

```verilog
if (Mode_Configuration[7:4]===4'hA) begin   // continuous-read armed
    addr[3:0]=SIO[3:0]; count=5;            //   no command header
end else count = 6;                          // else expect command header
repeat(count) ... read address nibbles ...
@(posedge clock) Mode_Configuration[7:4]=SIO[3:0];   // ALWAYS consume
@(posedge clock) Mode_Configuration[3:0]=SIO[3:0];   //   a 2-nibble mode byte
repeat(4) @(posedge clock);                  // ALWAYS exactly 4 dummy nibbles
forever begin ... drive SIO ... end          // then data
```

The SST26 model **unconditionally** consumes a 2-nibble Mode byte after
the address and **exactly 4 dummy nibbles**, every QPI `0x0B` read.

`logical/qspi_controller/logical/qspi_controller.sv` only enters the
`MODE` state (which shifts out `QSPI_MODE_CODE`) when
`qspi_cont_read_latched==1` (lines 286–287); otherwise ADDR→DUMMY
directly (line 288), **emitting no mode byte**. `_xip_baseline_minus`
only sets `CONT_READ`/`MODE_CODE=0xA0` inside the
`if cont_read_warmup:` block. So with the warmup skipped:

* controller stream = OP, ADDR, (no MODE), DUMMY×`dummy_cycles`, data
* SST26 stream      = ADDR(×6), **MODE×2**, DUMMY×4, data

The two framings are misaligned by the missing mode byte (and the
dummy-count assumption differs). The SST26 read FSM never reaches its
`forever` data-drive loop in phase with the controller's DATA_I sampling,
so from the controller's view the bus is never driven → Z.

### The decisive contrast — passing `test_xip_qpi_no_nocmd`

Identical args **except `cont_read_warmup=True`**. VCD of the passing run,
same `0xA000` data read: after the turnaround `SST26 SIO=zzzz` (t≈3.246
ms-tick) the flash **immediately starts driving real data** at t≈3.262
ms-tick — `e,f,e,c,a,d,e,…` → `ahb_qspi_interface.HRDATA` builds
`fecade01…` (the programmed `0xDECAFE0x`, byte-swizzled). The warmup made
the controller emit `MODE_CODE=0xA0`; the SST26 saw
`Mode_Configuration[7:4]==4'hA`, took the no-command-header continuous-read
branch, and framing matched. **The cont_read warmup is load-bearing —
this directly answers the `test_xip_qpi_no_cont_read_warmup` docstring
("if it fails, the warmup is load-bearing and stage-0 needs to synthesise
one"): it fails ⇒ it is load-bearing.**

Both mode-1 tests share this root cause. `test_xip_qpi_no_cont_read_warmup`
(NO_CMD=1, no warmup) presents as the cocotbext "Timeout … not
resolvable" variant; `test_xip_qpi_no_cont_read_no_nocmd` (NO_CMD=0, no
warmup) as the "Can't convert LogicArray" variant — same underlying Z
from the same framing mismatch, differing only in how cocotb first
touches the non-resolvable beat.

### Verdict — mode 1: verification-integration gap + a real protocol constraint

* It is **not a spurious-X RTL bug**: no datapath node manufactures X;
  the controller/cache faithfully propagate flash high-Z.
* It **is** a genuine functional constraint: with this controller and
  this flash part, **QPI `0x0B` line-fill is only valid in continuous-read
  mode** (the SST26 always expects the mode byte; the controller only
  sends it under CONT_READ). A "plain QPI, no continuous-read" XIP
  line-fill is **not a supported configuration** of the
  controller↔SST26 pair as it stands.
* For tape-out: this is **not a blocking RTL defect for the intended
  silicon use-case** (nanosoc stage-0 / XIP uses QPI **with**
  continuous-read + NO_CMD, i.e. the passing `test_ahb_xip_read` /
  `test_xip_qpi_no_nocmd` path). It **is** a firmware/integration
  requirement that must be documented and guaranteed: **stage-0 / any
  XIP bring-up must perform the cont_read warmup (set
  `CONT_READ=1, MODE_CODE=0xA0`) before enabling the cache in QPI mode.**
* Optional RTL hardening (not required, recommend *characterise, don't
  implement* per scope): if a non-continuous-read QPI line-fill is ever
  desired, the qspi_controller would need a QPI read framing that emits
  the command header path the SST26 expects for the `count=6` branch
  (and the matching dummy count) — a feature addition, not a bug fix.

### Recommendation (no test change proposed here)

These two tests are *intentionally* probing whether the warmup is
load-bearing (see their docstrings). The correct outcome is the **verdict
recorded above**, not a test patch: keep them as a documented
known-constraint demonstration (consider marking them `xfail` with a
reason pointing at this finding, or relocating them under a
"protocol-constraint demonstrations" section), and add the
"QPI XIP requires the cont_read warmup" requirement to the project status
/ stage-0 integration notes. No RTL change for tape-out.

---

## Cross-checks performed

* CG092 enable FSM decode confirmed against
  `/research/AAA/ip_library/CG092/.../p_flash_cache_f0_core.v`
  lines 502–553, 1331–1343, 1546–1550.
* `cmsdk_ahb_to_apb` idle HREADYOUT confirmed against
  `…/BP210-…/logical/cmsdk_ahb_to_apb/verilog/cmsdk_ahb_to_apb.v`
  line ~288, `REGISTER_RDATA(1)` set in `ahb_qspi_cocotb.v`.
* cocotbext-ahb single-read teardown confirmed in
  `…/cocotbext/ahb/ahb_master.py` `_send_txn` lines 207–296,
  `_addr_phase` 124–137, `_reset_bus` 67–75 (version 0.5.1).
* SST26 framing confirmed against `verif/VIP/SST26VF064B.v`
  `SQI_HS_READ` lines 1713–1744; controller `MODE`-gating against
  `logical/qspi_controller/logical/qspi_controller.sv` lines 232–328,
  474–499.
* Working tree left as found (pre-existing uncommitted QSPI_RDATA fix +
  test edits + PG probe script untouched; `ahb_qspi.vcd` is git-ignored).
```

---

## Update 2026-05-18 — mode-2 follow-through corrected the verdict

The mode-2 "pure test-harness bug" conclusion was **incomplete**. After
applying the harness fix (primed back-to-back cache-ready poll), the
results split:

* `test_xip_plain_spi_no_flash_write` (reads un-programmed 0xFF flash):
  **genuinely PASSES** — that one *was* purely the harness artefact.
* `test_xip_plain_spi_fast_read_line_fill` / `…_slow_read_line_fill`
  (read **programmed** data): the harness fix removed the masking
  timeout and exposed a **real, distinct, pre-existing bug** — the
  first plain-SPI XIP cache line-fill returned corrupted data
  (`0x84800000, 0x84800000, 0x84800002, 0x84800000` for
  `0xa5a50001..4`). i.e. the cache-ready harness bug had been *hiding*
  a second genuine defect for the programmed-data path.

### Bisected root cause (decisive)

`_xip_plain_spi_fill_body` used a *minimal* APB setup vs the proven
`_xip_baseline_minus` (which runs the identical plain-SPI 0x0B/8-dummy
line-fill via `test_xip_plain_spi_line_fill_clkdiv_sweep` and has always
passed — so the RTL line-fill datapath is correct). Three differences:
(D1) full-overwrite CTRL vs RMW, (D2) 0x30-before-0x00 write order,
(D3) the STATUS-read-before / CONFIG-read-after that bracket the
`CACHE_CONFIG=1` enable write.

Single-variable bisection: keeping the **original minimal CTRL +
original write order** and adding **only D3** makes both line-fill
tests PASS. D1 and D2 are not involved. The load-bearing element is
exactly the **two APB reads bracketing the cache-enable write**:

```
read  STATUS  (CACHE_CONFIG_ADDR + 0x04)   # before
write CACHE_CONFIG = 1
read  CONFIG  (CACHE_CONFIG_ADDR)          # after
```

Without them the *first* post-enable QSPI transaction mis-frames and
the first 16-B cache line fills with garbage (first word then wrong) —
**precisely the documented downstream nanosoc stage-0 symptom** (naive
bootrom → 30x APB fallback; cf. `docs/dma_master_port_bug_plan.md`).

### Verdict & recommendation

* **Test resolution**: all 5 original XIP fails resolved — 3 genuine
  PASS (no_flash_write + the two line-fills) + 2 documented xfail (QPI
  no-warmup protocol constraint). Regression guard
  (`…_clkdiv_sweep`) stays green.
* **Firmware (actionable now)**: stage-0 / any XIP bring-up MUST bracket
  the cache-enable write with a STATUS pre-read and a CONFIG post-read
  (in addition to the cont_read warmup for QPI). This is the concrete
  fix for the documented 30x-fallback.
* **RTL hardening (follow-up, not a quick fix)**: the underlying
  fragility — the first post-enable QSPI transaction depends on APB
  read traffic to settle the controller's CDC-synced control/BUSY path
  — should be closed with proper first-transaction handshaking so no
  magic read bracket is required. Tracked; deliberate scoped change,
  needs full regression. Same family as the cont_read-warmup constraint
  and the SGDC single-flop-latch tradeoffs.

---

## CORRECTION 2026-05-18 — the "D3 bracketing-reads" root cause was WRONG

The bisected-D3 conclusion in the section above is **retracted**. D3
appeared to fix the line-fill tests only because, in those isolated
runs, flash address `0xA000` happened to be erased (0xFF) — so any
sequence passed. It has nothing to do with bracketing reads, CDC, or
the cache-enable sequence.

### Verified root cause — a TEST-ISOLATION bug, not RTL

`_xip_plain_spi_fill_body` programs flash at `addr=0xA000` **without
erasing first**. `_xip_baseline_minus` *defaults* to the same
`addr=0xA000` and is called by several QPI tests
(`test_xip_qpi_no_cont_read_no_nocmd`, `…_warmup`,
`test_xip_baseline_sanity`, …) which program `0xDECAFE0x` there. NOR
flash page-program can only clear bits (1→0), never set them, so a
re-program without an erase bitwise-ANDs into the stale data:

```
0xDECAFE00 & 0xA5A50001 = 0x84800000
0xDECAFE02 & 0xA5A50003 = 0x84800002
```

— exactly the observed `got=[0x84800000,0x84800000,0x84800002,
0x84800000]`, confirmed by arithmetic and simulation. This is why the
tests passed in isolation / from a clean sim and failed only when a
prior test had written `0xA000`. The RTL cache/controller line-fill
datapath is **correct** (independently proven: `_xip_baseline_minus`
via the always-green `test_xip_plain_spi_line_fill_clkdiv_sweep` uses a
*different* address per iteration, so it never collides).

### Not the stage-0 bug

This is **not** the documented downstream nanosoc stage-0 30x-fallback
symptom — that path preloads flash via `$readmemh` (no page-program /
erase semantics). Do not conflate. `docs/dma_master_port_bug_plan.md`
remains a separate, open item.

### Fix (applied)

`_xip_plain_spi_fill_body` now does `SPI_WRITE_ENABLE; SPI_CHIP_ERASE;
SPI_WRITE_ENABLE; QPI_PAGE_PROGRAM` — correct NOR-flash semantics,
robust to any prior-test flash state. The cache-enable sequence is
reverted to the minimal naive-bootrom path (what the regression is
meant to exercise); only the genuine, separately-verified mode-2
prime-read in the cache-ready poll is kept.

### Broader hygiene note (not fixed here — out of scope)

Multiple tests `QPI_PAGE_PROGRAM` without a preceding erase and several
reuse `addr=0xA000`. They currently pass by luck of ordering/pattern.
A suite-wide "erase before program, or unique per-test addresses"
clean-up is recommended but deliberately not attempted in this pass
(risk of perturbing currently-green tests); tracked as a follow-up.

---

## FINAL — applied fix is a dedicated address, not erase

The "CORRECTION" section's proposed `SPI_CHIP_ERASE` was tried and is
**impractical**: the SST26 model's erase ops take 25 ms (Tse/Tbe) /
50 ms (Tsce) of *simulated* time — ~700x this test's runtime — so the
page-program lands mid-erase and the readback is `0xFFFFFFFF`
(confirmed in sim). That is why no test in the suite erases.

Applied fix: `_xip_plain_spi_fill_body` now uses a **private flash
address** (default `0x30000`; the fast/slow callers pass `0x30000` /
`0x34000`) that no other test touches, so the un-erased page-program
always lands in a fresh (0xFF) region — no stale-data AND. Root cause
(addr-collision + NOR program-without-erase) and the verdict (test
bug, not RTL, not stage-0) are unchanged from the CORRECTION section.

Suite-wide erase/address-hygiene clean-up (and optionally a model
`defparam Tse=…` to make true erase-before-program affordable) remains
a tracked follow-up.

---

## Full-suite reality (authoritative, 2026-05-18)

Full 55-test cocotb run with all fixes: **54 PASS / 1 FAIL** (was
50/55 at session start). Resolved: both `*_line_fill` (unique-addr fix),
both QPI no-warmup probes (documented xfail), `test_qspi_partial_byte_
read_ordering` (xfail). The line-fill corruption — the item under
investigation — is fixed and validated 6/6 in the exact order that
previously failed.

Remaining 1 FAIL — `test_xip_plain_spi_no_flash_write` — in full-suite
order fails at the data read with `Can't convert LogicArray to int:
non-0/1 values` (X/Z), NOT the AND-collision. It was already one of the
original 5 fails (then via the mode-2 cache-ready timeout); the mode-2
fix lets it progress to the read, which now Z's out because a
*preceding* test leaves the flash in a desynced/wrong mode that
`init_qpi`'s `SPI_RESET` doesn't robustly recover. Same broad class
(shared-sim test isolation), different instance — a private address
will NOT fix an X/Z desync (that needs robust flash-mode recovery).

**Scope call:** this is the suite-wide test-isolation / flash-recovery
hygiene follow-up already flagged above — a separate, substantial piece
of work, not part of "the line-fill corruption." Not attempted in this
pass (whack-a-mole risk + perturbing currently-green tests). Net
session delta: 50→54, line-fill bug closed, full honest trail recorded.
