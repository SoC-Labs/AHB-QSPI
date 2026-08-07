//-----------------------------------------------------------------------------
// cache_tag_probe -- passive observer on the cache tag RAM read path.
//
// Compiled only into the CACHE_MODEL=asic build.
//
// The data-correctness tests cannot see a broken tag RAM on their own: if tag
// reads return X the cache simply never reports a hit, every lookup misses and
// refetches from flash, and the AHB read data is still correct. The bug is
// invisible at the bus. This probe watches the two things that do change --
// X on the tag read data, and whether the cache ever actually hits.
//-----------------------------------------------------------------------------
`ifndef CACHE_TAG_PROBE_SV
`define CACHE_TAG_PROBE_SV

module cache_tag_probe;

  // test_top -> ahb_qspi_pads -> top_ahb_qspi -> cache_subsystem
  `define CSS test_top.u_dut.u_top_ahb_qspi.u_cache_subsystem

  // NOTE: 4-state, deliberately. Under -xprop=tmerge an X condition makes VCS
  // merge both branches; assigning that to a 2-state `int` silently collapses
  // the X to 0, so a corrupted counter reads as a plausible number instead of
  // announcing itself. Every condition below is also forced 2-state with ===
  // so there is nothing for xprop to merge in the first place. Both halves
  // matter: the guards prevent corruption, the 4-state type makes any that
  // slips through visible.
  logic [31:0] tag_reads   = 0;
  logic [31:0] tag_x_reads = 0;
  logic [31:0] hit_events  = 0;
  logic [31:0] miss_events = 0;

  wire clk    = `CSS.HCLK;
  wire resetn = `CSS.HRESETn;

  wire        w0_rd   = `CSS.RAMTAG0RD & `CSS.RAMTAG0CS;
  wire        w1_rd   = `CSS.RAMTAG1RD & `CSS.RAMTAG1CS;
  wire [10:0] w0_data = `CSS.RAMTAG0RDATA;
  wire [10:0] w1_data = `CSS.RAMTAG1RDATA;

  // Tag read data lands the cycle after the read strobe.
  reg w0_rd_d, w1_rd_d;
  always @(posedge clk) begin
    if (!resetn) begin w0_rd_d <= 1'b0; w1_rd_d <= 1'b0; end
    else         begin w0_rd_d <= w0_rd; w1_rd_d <= w1_rd; end
  end

  always @(posedge clk) if (resetn === 1'b1) begin
    if (w0_rd_d === 1'b1) begin
      tag_reads++;
      if (^w0_data === 1'bx) tag_x_reads++;
    end
    if (w1_rd_d === 1'b1) begin
      tag_reads++;
      if (^w1_data === 1'bx) tag_x_reads++;
    end
    if (`CSS.CACHEHIT  === 1'b1) hit_events++;
    if (`CSS.CACHEMISS === 1'b1) miss_events++;

    // Publish to the package statics so ahb_qspi_cache_tag_test can read them.
    // SystemVerilog forbids hierarchical references from inside a package, so
    // the data has to be pushed out rather than pulled in.
    ahb_qspi_pkg::cache_tag_stats::tag_reads   = tag_reads;
    ahb_qspi_pkg::cache_tag_stats::tag_x_reads = tag_x_reads;
    ahb_qspi_pkg::cache_tag_stats::hit_events  = hit_events;
    ahb_qspi_pkg::cache_tag_stats::miss_events = miss_events;
  end

  // --- diagnostics ---
  `define CORE `CSS.u_cache_controller.u_p_flash_cache_f0_core
  logic [31:0] clks = 0, rst_high = 0, tagcs = 0, tagrd = 0, tagwe = 0, cldcs = 0;
  logic [31:0] tag1cs = 0, tag1rd = 0, tag1we = 0;
  logic [31:0] cacheable_acc = 0, noncache_acc = 0, resp_err = 0;
  logic [31:0] sels = 0, trans_nz = 0, sel_and_trans = 0;
  logic [31:0] fsm_seen = 0;
  always @(posedge clk) begin
    clks++;
    if (resetn === 1'b1)  rst_high++;
    if (`CSS.RAMTAG0CS === 1'b1)   tagcs++;
    if (`CSS.RAMTAG0RD === 1'b1)   tagrd++;
    if (`CSS.RAMTAG0WE === 1'b1)   tagwe++;
    if ((|`CSS.RAMCLD0CS) === 1'b1) cldcs++;
    if (`CSS.RAMTAG1CS === 1'b1)   tag1cs++;
    if (`CSS.RAMTAG1RD === 1'b1)   tag1rd++;
    if (`CSS.RAMTAG1WE === 1'b1)   tag1we++;
    if (`CSS.HSELS === 1'b1)       sels++;
    if (`CSS.HTRANSS[1] === 1'b1) trans_nz++;
    if ((`CSS.HSELS & `CSS.HTRANSS[1]) === 1'b1) sel_and_trans++;
    if ((`CSS.HSELS & `CSS.HTRANSS[1] &  `CSS.HPROTS[3]) === 1'b1) cacheable_acc++;
    if ((`CSS.HSELS & `CSS.HTRANSS[1] & ~`CSS.HPROTS[3]) === 1'b1) noncache_acc++;
    if (`CSS.HRESPS === 1'b1)      resp_err++;
    fsm_seen = fsm_seen | (32'h1 << `CORE.reg_enable_fsm);
  end

  final begin
    $display("[cache_tag_probe] tag_reads=%0d tag_x_reads=%0d hits=%0d misses=%0d",
             tag_reads, tag_x_reads, hit_events, miss_events);
    $display("[cache_tag_probe] DIAG clks=%0d rst_high=%0d TAG0CS=%0d TAG0RD=%0d TAG0WE=%0d CLD0CS=%0d",
             clks, rst_high, tagcs, tagrd, tagwe, cldcs);
    $display("[cache_tag_probe] DIAG TAG1CS=%0d TAG1RD=%0d TAG1WE=%0d",
             tag1cs, tag1rd, tag1we);
    $display("[cache_tag_probe] DIAG cacheable_acc=%0d noncache_acc=%0d hresps_err=%0d",
             cacheable_acc, noncache_acc, resp_err);
    $display("[cache_tag_probe] DIAG HSELS=%0d HTRANSS[1]=%0d both=%0d enable_fsm_states_seen=%b",
             sels, trans_nz, sel_and_trans, fsm_seen[7:0]);

    if (tag_reads == 0) begin
      // Not a pass. The CG092 cache only issues RAM accesses once its CCR
      // (APB 0x1000, offset 0) enables it, and no test in this suite writes
      // it -- so the tag RAM is never touched and a green run means nothing
      // about the cache. Say so, loudly, rather than let the ASIC-model
      // regression look like coverage it does not have.
      $display("[cache_tag_probe] NO-COVERAGE: the cache RAMs were never accessed.");
      $display("[cache_tag_probe] NO-COVERAGE: this run does NOT exercise the tag RAM.");
      $display("[cache_tag_probe] NO-COVERAGE: a test must enable the cache via CCR first.");
    end else if (tag_x_reads != 0) begin
      $display("[cache_tag_probe] FAIL: tag RAM returned X on %0d of %0d reads",
               tag_x_reads, tag_reads);
    end else begin
      $display("[cache_tag_probe] PASS: %0d tag reads, none X, %0d hits",
               tag_reads, hit_events);
    end
  end

  `undef CSS

endmodule

`endif
