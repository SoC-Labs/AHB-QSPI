// HAL rule configuration for AHB QSPI lint flow
//
// Waive rules that conflict with AHB/AMBA/APB naming conventions or are
// style-only and not relevant to design correctness.

// ── Naming convention waivers ─────────────────────────────────────
// AHB/APB signal names (HCLK, HRESETn, HADDR, PSEL, etc.) are
// defined by the AMBA spec and cannot follow HAL's default suffixes.
-nocheck INPTNM
-nocheck OUTPNM
-nocheck CLKSNM
-nocheck RSTNAM
-nocheck MODLNM
-nocheck RGOPNM
-nocheck IDLENG
// Uppercase variable names — AMBA uses ALL-CAPS ports (HCLK, HADDR, etc.)
-nocheck LCVARN

// ── Style waivers ─────────────────────────────────────────────────
// Numeric literals in port widths (e.g. [31:0]) are standard practice
-nocheck STYVAL
// Line length — 120 chars is acceptable for modern editors
-nocheck MAXLEN
// Per-port and per-signal comments are overkill for clear code
-nocheck COMIOP
-nocheck COMDEC
-nocheck COMEND
// Always-block comments — not required for well-structured code
-nocheck COMBLK
// Parameter base/width — defaults are fine for simple integer params
-nocheck PRMVAL
-nocheck PRMBSE
// Compiler directives (`ifdef/`endif) — used in IP, acceptable
-nocheck CDWARN
-nocheck COMDIR
// Block labels — meaningful code structure over mandatory labelling
-nocheck NOBLKN
// Missing begin/end in single-statement if/always — acceptable style
-nocheck NBGEND
// Empty default case statements — intentional no-op for completeness
-nocheck EMPSTM
// Numeric suffix in identifiers — by design
-nocheck NUMSUF
// Separate line for each signal declaration — acceptable grouping
-nocheck SEPLIN

// ── Structural waivers ───────────────────────────────────────────
// Tied outputs are by design:
//   - PREADY=1, PSLVERR=0 (zero-wait-state APB slave)
//   - HRESP tied low in normal operation
-nocheck TIELOG
// Feedthrough paths are intentional:
//   - QSPI_IO_i → QSPI_RDATA (flash data path)
//   - PWDATA → register file → QSPI_CMD/ADDR/WDATA
-nocheck FDTHRU
// Mixed sync/async is expected with async active-low reset (HRESETn)
-nocheck SYNASN
// Combinational paths crossing hierarchy — expected in hierarchical design
-nocheck CBPAHI
// Combinational outputs at top level — AHB/APB protocols are comb by design
-nocheck TPOUNR
// Combinational (async) output ports — same reason
-nocheck SYNPRT
// Large operand arithmetic — inherent to parameterised widths
-nocheck LRGOPR
// Multiple non-blocking assigns — set/clear pattern for busy/irq regs
-nocheck MULNBA
// Parameters in port expressions
-nocheck PRMEXP
-nocheck IPRTEX
// FSM modelling style — HAL expects specific patterns, ours is valid
-nocheck BADFSM
-nocheck EXTFSM
-nocheck TRNMBT
-nocheck STMCNM
// Typedef not in package — module-local typedefs are acceptable
-nocheck TDOPKG
// Lowercase type names — SV convention for types
-nocheck UCCONN
// Clock/reset renamed across hierarchy (different port names)
-nocheck DIFCLK
-nocheck DIFRST
// Aliased wires — shared expressions by design
-nocheck DALIAS
// FF with constant data — synchroniser reset stages
-nocheck FFCSTD
// FF without synchronous reset — async reset is sufficient
-nocheck FFWNSR
// Mixed driver types — init vs runtime, harmless
-nocheck DFDRVS
// Unused port bits — AHB htrans[0] not decoded, QSPI_IO upper bits in SPI mode
-nocheck USEPRT
// Unconnected output naming
-nocheck UCOPNM
// Unconnected output ports — cache debug signals
-nocheck UNCONO
// Unread local registers
-nocheck URDREG
// Glue logic at top level — address derivation wires
-nocheck ATLGLC
// CMSDK/CG092-specific warnings
-nocheck OLDALW
-nocheck LOGNEG
-nocheck LOGAND
-nocheck BOUINC
-nocheck MEMRNM
-nocheck MICAWS
-nocheck BBXSIG
// Potential overflow — intentional for counter wrapping
-nocheck POIASG

// ── RTL-specific waivers ────────────────────────────────────────
// Missing default in APB write case — writes to unmatched addresses are
// intentionally ignored (no register update). Adding a default would be
// a no-op and add unnecessary logic.
-nocheck CDEFNC

// ── External IP waivers ─────────────────────────────────────────
// Unconnected input ports on CG092 cache controller — the cache_subsystem
// wrapper connects SRAM interfaces via separate RAM instances, not through
// the cache controller's ports directly. This is the intended integration.
-nocheck UNCONI

// Clock domain crossings — the design intentionally crosses between
// HCLK/PCLK and the generated QSPI_SCLK_i domain. CDC synchronisers
// are present in the RTL (2-FF synchronisers in apb_qspi_regs and
// ahb_qspi_interface). These are analysed by SpyGlass CDC separately.
-nocheck CLKDMN
