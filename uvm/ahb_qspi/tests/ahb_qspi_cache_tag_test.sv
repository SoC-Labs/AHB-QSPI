///////////////////////////////////////////////////////////////////////////////
// ahb_qspi_cache_tag_test.sv
///////////////////////////////////////////////////////////////////////////////
// Exercises the CG092 cache tag RAM.
//
// Every other test in this suite leaves the cache disabled: the CG092 only
// issues RAM accesses once CCR.EN is set, and nothing writes CCR. So the tag
// and data RAMs are never accessed and no test can see a defect in them. This
// test enables the cache, warms it, then re-reads the same addresses so the
// tag lookups have to match.
//
// Note that AHB read data alone cannot detect a broken tag RAM: if tag reads
// return X the cache simply never reports a hit, every lookup misses and
// refetches from flash, and the returned data is still correct. So the checks
// here are on cache_tag_probe's observations of the tag RAM itself -- X on the
// read path, and whether the cache ever actually hits -- not on read data.
//
// Only meaningful against CACHE_MODEL=asic (real TSMC65 macros). Under the
// generic behavioural model the probe is not compiled in and the cache checks
// are skipped; the traffic still runs.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_QSPI_CACHE_TAG_TEST_SV
`define GUARD_AHB_QSPI_CACHE_TAG_TEST_SV

class ahb_qspi_cache_tag_test extends ahb_qspi_base_test;

  `uvm_component_utils(ahb_qspi_cache_tag_test)

  // CG092 p_flash_cache_f0 APB block: cmsdk_apb_slave_mux DECODE4BIT =
  // PADDR[15:12], cache is PSEL1 -> 0x1000. CCR is at offset 0x000.
  localparam bit [15:0] CACHE_CCR_ADDR = 16'h1000;
  localparam bit [15:0] CACHE_SR_ADDR  = 16'h1004;

  // CCR fields (p_flash_cache_f0_core.v: ccr_en <= ip_wdata[0],
  // ccr_statistic_en <= ip_wdata[6]). STATISTIC_EN resets to 1 and gates the
  // CACHEHIT/CACHEMISS outputs, so it must be written back as 1 -- writing a
  // bare 0x1 would silently turn the hit counters off.
  localparam bit [31:0] CCR_EN           = 32'h1 << 0;
  localparam bit [31:0] CCR_STATISTIC_EN = 32'h1 << 6;

  // Number of distinct word addresses to sweep. 16 words = 64 bytes = 4 cache
  // lines at LINEW=4 (128-bit lines), enough to fill several tag entries.
  localparam int N_WORDS = 16;

  function new(string name = "ahb_qspi_cache_tag_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    qspi_init_sequence init_seq;
    qspi_cmd_sequence  cmd;
    bit [31:0] read_data;
    bit [31:0] ccr_val;

    phase.raise_objection(this);
    wait_for_reset();

    // ---------------------------------------------------------------------
    // Flash init + program a known pattern so XIP reads return real data.
    // ---------------------------------------------------------------------
    init_seq = qspi_init_sequence::type_id::create("init");
    init_seq.clear_protect = 1;
    init_seq.start(env.apb_agt.sequencer);

    cmd = qspi_cmd_sequence::type_id::create("wren");
    cmd.opcode = SPI_OP_WREN;
    cmd.start(env.apb_agt.sequencer);

    cmd = qspi_cmd_sequence::type_id::create("pp");
    cmd.opcode     = SPI_OP_PP;
    cmd.do_write   = 1;
    cmd.addr_en    = 1;
    cmd.flash_addr = 22'h0;
    cmd.n_rw_bytes = 15;
    cmd.wdata[0]   = 32'hAABBCCDD;
    cmd.wdata[1]   = 32'h11223344;
    cmd.wdata[2]   = 32'h55667788;
    cmd.wdata[3]   = 32'h99AABBCC;
    cmd.start(env.apb_agt.sequencer);

    begin
      bit flash_busy = 1;
      int timeout = 1000;
      while (flash_busy && timeout > 0) begin
        cmd = qspi_cmd_sequence::type_id::create("poll_sr");
        cmd.opcode     = SPI_OP_RDSR;
        cmd.do_read    = 1;
        cmd.n_rw_bytes = 1;
        cmd.start(env.apb_agt.sequencer);
        flash_busy = cmd.rdata[0][0];
        timeout--;
      end
      if (flash_busy)
        `uvm_error("CACHE_TAG", "flash still busy after page program timeout")
    end

    // ---------------------------------------------------------------------
    // Bring up XIP, then enable the cache.
    // ---------------------------------------------------------------------
    apb_write(QSPI_AHB_SETUP_ADDR, {16'h0, 4'h8, 4'h0, SPI_OP_FAST_READ});
    apb_write(QSPI_CTRL_ADDR, (1 << CTRL_XIP_ACTIVE_BIT));
    wait_clks(5);

    `uvm_info("CACHE_TAG", "enabling CG092 cache via CCR", UVM_LOW)
    apb_write(CACHE_CCR_ADDR, CCR_EN | CCR_STATISTIC_EN);

    // CCR.EN kicks the enable FSM: auto power-up (SET_MAN_POW=0) then auto
    // invalidate (SET_MAN_INV=0). The invalidate walks all 256 tag entries one
    // per cycle, so it must be polled out rather than waited on -- a fixed
    // wait that expires early lets traffic hit tag entries the invalidate has
    // not written yet, which reads as X in the macro and looks exactly like a
    // broken tag RAM. SR bit 2 is sr_inv_stat (= invalidate_run).
    // SR bit4 = sr_pow_stat (RAM powered), bit2 = sr_inv_stat (invalidate
    // running). Polling for "not invalidating" alone races: immediately after
    // the CCR write the FSM has not powered the RAMs yet, so inv_stat is still
    // 0 and the poll falls straight through. Require powered AND
    // invalidate-finished.
    begin
      bit [31:0] sr_val;
      int timeout = 5000;
      do begin
        apb_read(CACHE_SR_ADDR, sr_val);
        timeout--;
      end while (!((sr_val & 32'h10) && !(sr_val & 32'h4)) && timeout > 0);
      if (timeout <= 0)
        `uvm_error("CACHE_TAG",
                   $sformatf("cache never reached powered+invalidated (SR=0x%08h)", sr_val))
      else
        `uvm_info("CACHE_TAG",
                  $sformatf("cache powered and invalidated (SR=0x%08h)", sr_val), UVM_LOW)
    end

    apb_read(CACHE_CCR_ADDR, ccr_val);
    `uvm_info("CACHE_TAG", $sformatf("CCR readback = 0x%08h", ccr_val), UVM_LOW)
    if (!(ccr_val & CCR_EN))
      `uvm_error("CACHE_TAG",
                 $sformatf("cache did not enable: CCR.EN clear (CCR=0x%08h)", ccr_val))

    apb_read(CACHE_SR_ADDR, read_data);
    `uvm_info("CACHE_TAG", $sformatf("cache SR = 0x%08h", read_data), UVM_LOW)

    // ---------------------------------------------------------------------
    // Warm the cache, then re-read the same addresses so tags must match.
    // ---------------------------------------------------------------------
    // HPROT[3] is the AHB cacheable attribute, and the CG092 gates on it:
    //   non_cache_aphase = ahb_access & (hwrites | ~hprots[3] | hmasters)
    // ahb_data_if defaults hprot to 4'b0000 and ahb_read() never drives it, so
    // without this every access is non-cacheable and the cache passes straight
    // through without a tag lookup -- enabled, but doing nothing. Set it once;
    // ahb_read() leaves hprot alone. 4'b1011 = cacheable, bufferable,
    // privileged, data.
    ahb_vif.drv_cb.hprot <= 4'b1011;
    wait_clks(2);

    for (int i = 0; i < N_WORDS; i++) begin
      ahb_read(i * 4, read_data);
      `uvm_info("CACHE_TAG",
                $sformatf("warm  [0x%06h] = 0x%08h", i*4, read_data), UVM_HIGH)
    end

    for (int pass = 0; pass < 2; pass++) begin
      for (int i = 0; i < N_WORDS; i++) begin
        ahb_read(i * 4, read_data);
        `uvm_info("CACHE_TAG",
                  $sformatf("rehit p%0d [0x%06h] = 0x%08h", pass, i*4, read_data), UVM_HIGH)
      end
    end

    wait_clks(20);
    apb_write(QSPI_CTRL_ADDR, 32'h0);

    // ---------------------------------------------------------------------
    // Checks -- on the tag RAM itself, not on read data.
    // ---------------------------------------------------------------------
`ifdef CACHE_ASIC_MODEL
    begin
      int unsigned tag_reads   = cache_tag_stats::tag_reads;
      int unsigned tag_x_reads = cache_tag_stats::tag_x_reads;
      int unsigned hits        = cache_tag_stats::hit_events;
      int unsigned misses      = cache_tag_stats::miss_events;

      `uvm_info("CACHE_TAG",
                $sformatf("probe: tag_reads=%0d tag_x_reads=%0d hits=%0d misses=%0d",
                          tag_reads, tag_x_reads, hits, misses), UVM_LOW)

      if (tag_reads == 0)
        `uvm_error("CACHE_TAG",
                   "tag RAM was never read -- cache did not engage, test proves nothing")

      if (tag_x_reads != 0)
        `uvm_error("CACHE_TAG",
                   $sformatf("tag RAM returned X on %0d of %0d reads -- tag read path broken",
                             tag_x_reads, tag_reads))

      if (hits == 0)
        `uvm_error("CACHE_TAG",
                   $sformatf("zero cache hits across %0d re-reads -- tag lookup never matched",
                             2*N_WORDS))
    end
`else
    `uvm_info("CACHE_TAG",
              "generic cache model: tag RAM checks skipped (run with CACHE_MODEL=asic)",
              UVM_LOW)
`endif

    `uvm_info("CACHE_TAG", "cache tag test complete", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass

`endif // GUARD_AHB_QSPI_CACHE_TAG_TEST_SV
