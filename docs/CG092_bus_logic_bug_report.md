# Bug report: CG092 `p_flash_cache_f0_bus_logic` silently drops non-privileged APB writes

> **NOTE (2026-06-18):** This is a **real, separate** CG092 bug (PPROT[0] gate
> on register writes) and stands on its own. It is **related to** the silicon
> **XiP branch-fetch hang** only in that, in this SoC, the CG092 cache is left
> **disabled / in bypass** (`CCR.EN` resets to 0 and nothing enables it), so the
> wrapper sees the raw M0+ fetch stream and the back-to-back-NONSEQ handshake
> bug surfaces. Reconciled branch-hang root cause + fix:
> [`xip_branch_fetch_hang_rootcause.md`](xip_branch_fetch_hang_rootcause.md)
> (one fix direction there is to actually enable + configure the cache, which
> this PPROT gate can silently block — re-verify the enable path on HW).


## Summary

The ARM CG092 flash cache IP (`p_flash_cache_f0`, release `r2p0-00rel0`)
contains an APB-slave bus-logic block that gates **all register writes**
on `PPROT[0]` (privileged/user bit), while leaving register reads
unrestricted. When the cache is driven from an APB master whose
`PPROT[0]` defaults to `0` (user mode) — which includes the standard
Xilinx `axi_apb_bridge` IP when the AXI master issues `AxPROT[0]=0`,
*and* the Linux `/dev/mem` userspace MMIO path on Zynq-7000 — **every
write to the Cache Config Register (CCR) is silently discarded**. Reads
return the reset value, so nothing about the access looks wrong.

The downstream consequence in our system was that the cache stayed
disabled, the AHB XIP data path never responded to the first flash
read, the Xilinx `axi_ahblite_bridge` held the AXI read beat open
waiting for `HREADYOUT`, and the Zynq PS CPU deadlocked on the MMIO
load. Because the stall occurs inside the AXI fabric, the Cortex-A9
interrupt path, the Linux soft-lockup detector, and even the kernel's
panic handlers are all unreachable — the board appears "fully hung" to
an outside observer (ssh drops, serial console goes silent, watchdog
cannot fire unless explicitly enabled). Recovery requires a physical
power-cycle.

It took roughly a full day of bring-up debugging — swapping RTL, adding
LED heartbeats, tying off IRQ_F2P, adding progress instrumentation, and
a granular single-MMIO-read reproducer — to localise the problem to the
cache. Because reads read back cleanly, there was no signal that writes
weren't landing until we compared the reset value (`0x40`, from
`STATISTIC_EN=1`) against the value we had written (`0x01`).

## Affected file and line

[`p_flash_cache_f0/logical/p_flash_cache_f0/verilog/p_flash_cache_f0_bus_logic.v`](../../../research/AAA/ip_library/CG092/CG092-BU-50000-r2p0-00rel0/p_flash_cache_f0/logical/p_flash_cache_f0/verilog/p_flash_cache_f0_bus_logic.v),
in the release `r2p0-00rel0`.

Relevant RTL:

```verilog
// Line 89
assign apb_valid = (psel & ~penable & (~pwrite | pprot[0]));
```

When `pwrite==1` (this is an APB write) and `pprot[0]==0` (non-privileged),
`apb_valid` is held low for the whole SETUP phase, and no downstream
`ccr_reg_wr_en_int`, `irqmask_reg_wr_en_int`, `cshr_reg_wr_en_int` or
`csmr_reg_wr_en_int` ever asserts. The write completes on the APB side
(`PREADY` is still driven according to the normal `ack_in` path), so the
master sees a successful transaction. The register contents do not
change.

No such gate exists on the read path; reads complete normally regardless
of `PPROT[0]`.

The behaviour appears to be deliberate — treating CCR and related
control registers as privileged-only — but there is no documented
indication of it in any version of the TRM we have access to, the
signature of "clean write + stale readback + slow downstream wedge" is
indistinguishable from a hardware fault, and there is no `PSLVERR`
returned to flag the dropped write.

## Reproduction

Minimal reproduction with PYNQ-Z2 + Zynq-7000 PS driving an `axi_apb_bridge`
which routes through a `cmsdk_apb_slave_mux` into `cache_subsystem.v`
(which instantiates `p_flash_cache_f0`):

1. Boot Linux. Open `/dev/mem` and `mmap` the APB window.
2. From userspace (any UID, root included):
   ```python
   ol.apb.write(CACHE_CFG_OFFSET, 0x1)        # write CCR.EN=1
   ol.apb.read(CACHE_CFG_OFFSET)              # reads back 0x40 (reset value)
   ol.apb.read(CACHE_CFG_OFFSET + 0x4)        # SR stays 0x00000000 (not ready)
   ```
3. Issue any AHB XIP read into the cache's downstream slave:
   - CPU load at `0x40000000` (our AHB XIP window).
   - `axi_ahblite_bridge` passes AHB read to cache.
   - Cache is not enabled (CCR.EN==0), never asserts `HREADYOUTS`.
   - Bridge holds AXI `ARREADY`/`RVALID` open.
   - CPU stalls on the load instruction.
4. Within a few hundred milliseconds the Linux system becomes
   unresponsive to ssh/serial. A hardware reset is required.

The same flow in a cocotb testbench passes, because our AHB-lite master
in simulation issues `HPROT[1]=1` (privileged) by default and the
Xilinx `axi_ahblite_bridge` passes the privilege bit through onto the
APB `PPROT` side. That difference is what masked this bug from
simulation and from ASIC bring-up that drives the APB slave from a
privileged master.

## Why the gate is problematic in practice

1. **Most bus infrastructure does not carry privilege from userspace.**
   Linux `/dev/mem` `mmap` on ARM issues AWPROT with `PROT[0]=0`, as does
   the Xilinx AXI-APB bridge in its default configuration with no
   explicit PROT override. Production designs with a Linux-facing APB
   slave will need to treat CG092 writes specially or add a shim that
   re-writes `PPROT[0]=1`.

2. **The failure mode is catastrophic and opaque.**
   Silent-drop of the enable register bit means the cache never responds
   on the AHB side, and the bridge upstream has no timeout. The CPU
   locks up on an MMIO load before the OS has any chance to record a
   diagnostic. Every debugging signal in the system — kernel log,
   `/proc`, SSH, UART console — goes silent simultaneously because the
   core is deadlocked in-kernel with interrupts off. This makes the bug
   look like a full hardware fault rather than an APB protocol
   mismatch.

3. **No `PSLVERR`, no alarm, no side-signal.** `PREADY` still asserts;
   the returned data on reads is still valid (reset value); there is no
   IRQ, no status bit, no error response. The only way to discover the
   problem is to diff written-vs-readback values *and* match the read
   data against the reset default, which is a very unusual debug step.

4. **Even when the write is gated, it still consumes an APB cycle and
   drives `ack_in`→`PREADY`**, so the master receives a positive
   write-ack. The system protocol says "the write completed
   successfully" while the effect is nil.

## Suggested fix

In priority order:

1. **Remove the gate for the CCR.**
   At minimum, the primary enable register (CCR) should be
   unconditionally writable. A cache that cannot be enabled because the
   system happens to be using a non-privileged APB master is not
   useful, and the silent-drop behaviour is harmful.

2. **If access control is intentional, return `PSLVERR` on dropped
   writes.** That at least lets the master detect the failure instead
   of silently eating it.

3. **Make the privilege check configurable** via a top-level parameter,
   e.g. `REQUIRE_PRIVILEGED_WRITES=0` by default, and document it in
   the TRM.

4. **Document the existing behaviour prominently**, including the
   failure mode (all writes silently dropped, cache stays in reset,
   downstream AHB wedges with no timeout) and the minimum requirement
   on the APB master. The current lack of any TRM mention of `PPROT[0]`
   interaction is what made this take a day to find.

## Workaround

Local RTL edit at the cache's APB input, forcing `PPROT[0] = 1'b1`:

```verilog
// In top wrapper, driving cache_subsystem's APB inputs:
cache_subsystem u_cache_subsystem(
    ...
    // Force PPROT[0]=1 because p_flash_cache_f0_bus_logic.v:89 drops
    // writes when this bit is 0, and PS-side userspace MMIO cannot set
    // it. Remove once the CG092 fix is in.
    .PPROT({PPROT[2:1], 1'b1}),
    ...
);
```

This restores the expected behaviour — writes to CCR from user-mode AXI
masters land correctly and the cache enables. It is a pure RTL
workaround, no software support required.

## Environment

- CG092 release: `CG092-BU-50000-r2p0-00rel0`
- IP file: `p_flash_cache_f0/logical/p_flash_cache_f0/verilog/p_flash_cache_f0_bus_logic.v`
- Target: AMD/Xilinx Zynq-7020 (PYNQ-Z2 board), Vivado 2024.1
- Upstream bridge: `xilinx.com:ip:axi_apb_bridge:3.0`
- Software: PYNQ Linux v2.7, Python `mmap` on `/dev/mem`
- Observed: APB writes to CCR register (`P_CCR_REG_OFFSET=12'h000`)
  silently dropped; `PSLVERR` never asserted; `PREADY` asserted normally.
  Cache stays at reset value (`0x40` — `STATISTIC_EN=1` default).
  Subsequent AHB read hangs the PS.
