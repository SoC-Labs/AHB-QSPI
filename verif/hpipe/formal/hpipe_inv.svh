// Helper invariants for k-induction of P1/P2/P6 on the H-PIPE-fixed
// ahb_qspi_interface (included into ahb_if_formal.sv under HPIPE_INV).
//
// They are asserted, not assumed: each one is itself proved by the same
// induction, so they only strengthen the induction hypothesis. Hierarchical
// references into the DUT need yosys-slang (FRONTEND=slang, set by INV=1).
//
// Names: st = DUT FSM state (0 IDLE, 1 WAIT_READ, 2 ERR1, 3 ERR2).

    wire [1:0]   i_st      = dut.current_state;
    wire         i_wr      = (i_st == 2'd1);
    wire         i_idle    = (i_st == 2'd0);
    wire         i_err1    = (i_st == 2'd2);
    wire         i_err2    = (i_st == 2'd3);
    wire [21:0]  i_line    = {dp_addr[21:4], 4'h0};
    wire         i_mine    = dp_sel && dp_trans[1];   // our NONSEQ/SEQ data phase

    always @(*) begin
        if (HRESETn && p_valid) begin
            // ---- FSM state <-> data phase ownership ----------------------
            // IDLE never owns a pending transfer of ours (H-PIPE: nothing
            // accepted is ever dropped); every other state does.
            assert(i_idle == !i_mine);
            // WAIT_READ serves an XIP read, and fetches its own line.
            if (i_wr) assert(!dp_write && dp_xip && dut.AHB_QSPI_ADDR == i_line);
            // ---- handshake bookkeeping ------------------------------------
            if (dut.qspi_ready)   assert((i_wr || i_err1) && dut.qspi_started);
            if (dut.qspi_started) assert(i_wr || i_err1);
            if (AHB_QSPI_ENABLE)  assert(i_wr || i_err1);
            if (AHB_QSPI_ENABLE)  assert(!dut.qspi_started);
            if (dut.watchdog_cnt != 0) assert(i_wr);
            if (dut.soft_reset_cnt != 0) assert(SOFT_RESET);
        end
        // The rest relate the DUT to the controller handshake model.
        if (HRESETn && p_valid && CTRL_MODEL) begin
            // ---- controller model is self-consistent -------------------
            assert(m_busy == (m_st != M_IDLE));
            assert(m_ack  == (m_st == M_ACK));
            // A started (acknowledged) fetch was a capture of this data
            // phase's own line, and no soft reset can be under way.
            if (i_wr && dut.qspi_started) assert(dp_fetched && !SOFT_RESET);
            // While ENABLE is high in WAIT_READ, the controller is either
            // still idle (no capture yet; it cannot be acknowledging an older
            // request) or has captured this line.
            if (i_wr && AHB_QSPI_ENABLE)
                assert((m_st == M_IDLE && !dut.ahb_qspi_enable_ack_meta &&
                        !dut.ahb_qspi_enable_ack_sync && !SOFT_RESET) ||
                       (m_addr == i_line && (dp_fetched || m_cap)));
            // A capture of this line in this data phase stays the model's
            // current capture until the data phase ends.
            if (i_wr && (dp_fetched || dut.qspi_started)) assert(m_addr == i_line);
            // ---- soft reset ------------------------------------------------
            // A read that is in WAIT_READ while the soft-reset pulse is on has
            // not started its fetch: ENABLE is held off until the pulse ends.
            if (i_wr && SOFT_RESET)
                assert(!AHB_QSPI_ENABLE && !dut.qspi_started && !dut.qspi_ready && !dp_fetched);
            // ---- data ------------------------------------------------------
            // Once the model has finished a fetch of this line, RDATA is the
            // line's data while BUSY is low.
            if (i_wr && dut.qspi_started && m_st == M_IDLE && i_line == sym_addr)
                assert(m_rdata == sym_data);
            if (i_wr && dut.qspi_ready && i_line == sym_addr)
                assert(HRDATA == exp_hrdata);
        end
    end
