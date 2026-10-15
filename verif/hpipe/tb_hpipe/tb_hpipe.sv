//-----------------------------------------------------------------------------
// Source: assessor A3, ~/SoCLabs/qspi-assess-A3-ip assess/A3 f1961d6,
// verif/assess_a3/tb_hpipe.sv. Copied for the H-PIPE regression; the only
// change is case T0 (HRDATA reset) below.
//
// tb_hpipe.sv -- assessor A3: ahb_qspi_interface ALONE under directed AHB-Lite
// stimulus (AHB-QSPI PR #1 assessment, 13 Oct 2026; not product).
//
// The slave's controller side is a behavioural stub that answers the
// ENABLE/ACK/BUSY handshake (as qspi_controller_mux does, through the slave's
// own 2-FF synchronisers) and returns the 16-byte line of the address it was
// given: line(a) word k = {a[21:4], k[1:0], 10'h2A5} ^ 32'h5A000000 (distinct per line and word).
// Every completed OKAY read is checked against line(own address phase).
//
// Cases (each a back-to-back address phase accepted in the cycle the previous
// transfer completes, which is legal AHB-Lite master behaviour):
//   T1  A (line 0x000) then B (line 0x010) back to back, then IDLE
//   T2  A, B (line 0x010), C (line 0x020) all back to back
//   T3  A, B in the SAME line, then IDLE (the case that hides the defect)
//   T4  XIP off: A gets ERROR; B presented in the ERR2 cycle, XIP turned on
//       in between, then IDLE (ERR2 -> IDLE leg)
//   T5  A then IDLE then B (a gap: the control case, must pass)
// Rules also checked: R1 zero-wait OKAY for an IDLE data phase; R2 two-cycle
// ERROR. Output: per-case PASS/FAIL lines and "TB_HPIPE: n errors".
//-----------------------------------------------------------------------------
`timescale 1ns/1ps
module tb_hpipe;
  reg HCLK = 0, HRESETn = 0;
  always #5 HCLK = ~HCLK;
  reg  [21:0]  HADDR = 0;
  reg  [1:0]   HTRANS = 0;
  reg          HWRITE = 0, HSELx = 0, XIP = 1;
  wire [127:0] HRDATA;
  wire         HREADYOUT, HRESP;
  wire         EN, SOFT;
  wire [21:0]  QADDR;
  reg          ACK = 0, BUSY = 0;
  reg  [127:0] RDATA = 0;

  ahb_qspi_interface #(.ADDR_W(22), .DATA_W(128), .WATCHDOG_WIDTH(16)) dut (
    .HCLK(HCLK), .HRESETn(HRESETn), .HADDR(HADDR), .HTRANS(HTRANS), .HWRITE(HWRITE),
    .HSIZE(3'b100), .HBURST(3'b000), .HPROT(4'b1110), .HWDATA(128'd0), .HSELx(HSELx),
    .HRDATA(HRDATA), .HREADY(HREADYOUT), .HREADYOUT(HREADYOUT), .HRESP(HRESP),
    .XIP_ACTIVE(XIP), .AHB_QSPI_ENABLE(EN), .AHB_QSPI_READ(), .AHB_QSPI_WRITE(),
    .AHB_QSPI_ADDR_EN(), .AHB_QSPI_N_RW_BYTES(), .AHB_QSPI_ADDR(QADDR), .AHB_QSPI_WDATA(),
    .AHB_QSPI_ENABLE_ACK(ACK), .AHB_QSPI_BUSY(BUSY), .AHB_QSPI_RDATA(RDATA), .SOFT_RESET(SOFT));

  // the slave byte-swaps RDATA into HRDATA (AHB_QSPI_RDATA_i): model the line in
  // HRDATA terms and pre-apply the inverse mapping on the stub side
  function automatic [127:0] line_hr(input [21:0] a);
    for (int k = 0; k < 4; k++) line_hr[32*k +: 32] = {a[21:4], k[1:0], 12'h2A5} ^ 32'h5A000000;
  endfunction
  function automatic [127:0] to_rdata(input [127:0] h);
    // inverse of: W3=bswap(R[127:96]) -> H[127:96]; W0=bswap(R[95:64]) -> H[95:64];
    //             W1=bswap(R[63:32]) -> H[63:32]; W2=bswap(R[31:0]) -> H[31:0]
    for (int k = 0; k < 4; k++) begin
      logic [31:0] w; w = h[32*k +: 32];
      to_rdata[32*k +: 32] = {w[7:0], w[15:8], w[23:16], w[31:24]};
    end
  endfunction

  // controller stub: ENABLE seen -> BUSY, then ACK, then ACK low, data, BUSY low
  initial forever begin
    @(posedge HCLK);
    if (EN && !BUSY) begin
      logic [21:0] a; a = QADDR;
      repeat (3) @(posedge HCLK); BUSY <= 1;
      repeat (4) @(posedge HCLK); ACK <= 1;
      wait (!EN); repeat (3) @(posedge HCLK); ACK <= 0;
      repeat (10) @(posedge HCLK); RDATA <= to_rdata(line_hr(a));
      repeat (4) @(posedge HCLK); BUSY <= 0;
    end
  end

  int errors = 0, case_err;
  // checker: pipeline tracker
  bit dv = 0; logic [21:0] da; bit dsel = 0; bit err1 = 0;
  always @(posedge HCLK) if (HRESETn) begin
    if (err1 && !(HRESP && HREADYOUT)) begin errors++; case_err++; $display("%0t R2: ERROR cycle 1 not followed by cycle 2", $time); end
    if (!err1 && HRESP && HREADYOUT) begin errors++; case_err++; $display("%0t R2: one-cycle ERROR", $time); end
    err1 = HRESP && !HREADYOUT;
    if (dsel && !dv && !(HREADYOUT && !HRESP)) begin errors++; case_err++; $display("%0t R1: IDLE data phase answered HREADYOUT=%b HRESP=%b", $time, HREADYOUT, HRESP); end
    if (HREADYOUT && dv && !HRESP) begin
      if (HRDATA !== line_hr(da)) begin
        errors++; case_err++;
        $display("%0t DATA: transfer @%06h completed OKAY with %032h, its own line is %032h", $time, da, HRDATA, line_hr(da));
      end else $display("%0t ok: @%06h", $time, da);
    end
    if (HREADYOUT) begin dv = HSELx && HTRANS[1]; da = HADDR; dsel = HSELx; end
  end

  // master: issue a list of NONSEQ reads; gap=1 inserts an IDLE before the next
  // one clock; returns the HREADYOUT the slave showed during that cycle
  task automatic tick(output bit r);
    @(negedge HCLK); r = HREADYOUT; @(posedge HCLK);
  endtask
  task automatic until_ready();
    bit r; do tick(r); while (!r);
  endtask
  task automatic xfer(input [21:0] a, input bit gap_before);
    if (gap_before) begin HTRANS <= 2'b00; HSELx <= 1; until_ready(); end
    HADDR <= a; HTRANS <= 2'b10; HSELx <= 1; HWRITE <= 0;
    until_ready();                                          // address phase accepted
  endtask
  task automatic finish_idle(input int maxcyc);
    int n; bit r;
    HTRANS <= 2'b00; HADDR <= 22'h3FFFF0;
    n = 0;
    do begin tick(r); n++; end while (!r && n < maxcyc);
    if (n >= maxcyc) begin errors++; case_err++; $display("%0t HANG: data phase never completed", $time); end
    repeat (5) @(posedge HCLK);
  endtask
  task automatic report(string name);
    $display("TB_HPIPE %s: %s", name, case_err ? "FAIL" : "PASS");
    case_err = 0;
  endtask

  initial begin
    case_err = 0;
    repeat (5) @(posedge HCLK); HRESETn <= 1; repeat (5) @(posedge HCLK);
    // T0 (added for the H-PIPE fix, not in A3's original): HRDATA is reset,
    // so the slave never drives X on HRDATA after reset (ADJUDICATION item 6).
    if (^HRDATA === 1'bx) begin errors++; case_err++; $display("%0t R3: HRDATA is X after reset", $time); end
    report("T0 HRDATA known after reset");
    // T1
    xfer(22'h000004, 0); xfer(22'h000010, 0); finish_idle(2000); report("T1 A,B(next line),IDLE");
    // T2
    xfer(22'h000100, 0); xfer(22'h000110, 0); xfer(22'h000120, 0); finish_idle(2000); report("T2 A,B,C back to back");
    // T3
    xfer(22'h000200, 0); xfer(22'h000204, 0); finish_idle(2000); report("T3 A,B same line");
    // T4: ERROR then B in the ERR2 cycle
    XIP <= 0;
    HADDR <= 22'h000300; HTRANS <= 2'b10; HSELx <= 1;
    until_ready();                                // A accepted (slave IDLE, ready)
    HTRANS <= 2'b00;
    begin bit r; do begin @(negedge HCLK); r = HRESP && !HREADYOUT; @(posedge HCLK); end while (!r); end // ERR1 cycle done
    XIP <= 1;
    HADDR <= 22'h000310; HTRANS <= 2'b10;          // B driven in the ERR2 cycle
    until_ready();
    finish_idle(2000); report("T4 ERROR, B in ERR2");
    // T5 control: a gap between the transfers
    xfer(22'h000400, 0); xfer(22'h000410, 1); finish_idle(2000); report("T5 control (gap)");
    $display("TB_HPIPE: %0d errors", errors);
    $finish;
  end
  initial begin #2000000; $display("TB_HPIPE: global timeout"); $finish; end
endmodule
