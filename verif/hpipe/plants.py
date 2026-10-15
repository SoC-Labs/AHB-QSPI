#!/usr/bin/env python3
"""Planted-defect copies of the H-PIPE-fixed RTL, for test-sensitivity runs.

    plants.py <src tree with logical/> <out dir> [PLANT ...]   (default: all)
    plants.py --list

Each plant is written to <out dir>/<PLANT>/logical/ as a SCRATCH copy. Point a
harness at it (RTL_DIR=... for cocotb_a1, IP_DIR for tb_hpipe, the interface
file for formal). NEVER commit a plant: the out dir must be outside the source
tree or under the git-ignored simulate/ directory.

Plants marked (A1 Pn) / (A2 name) re-create the plants assessors A1 and A2 used
in the PR #1 assessment (13 Oct 2026), re-anchored on the fixed RTL. H* plants
are new: each undoes one part of the H-PIPE fix.
"""
import os
import shutil
import sys

IF = "logical/ahb_qspi_interface/logical/ahb_qspi_interface.sv"
MUX = "logical/qspi_controller/logical/qspi_controller_mux.v"
CTL = "logical/qspi_controller/logical/qspi_controller.sv"

# name -> (description, [(file, old, new), ...])
PLANTS = {
    # ---- H-PIPE fix undone, one part at a time ----------------------------
    "H1_wr_exit_drop": ("WAIT_READ completion ignores a same-edge accepted phase", [
        (IF, """                            if(accept)
                                next_state = accept_err ? ERR1 : WAIT_READ;
                            else
                                next_state = IDLE;
                        end""",
             """                            next_state = IDLE; // PLANT H1
                        end""")]),
    "H2_err2_exit_drop": ("ERR2 ignores a same-edge accepted phase", [
        (IF, """        ERR2:           if(accept)
                            next_state = accept_err ? ERR1 : WAIT_READ;
                        else
                            next_state = IDLE;""",
             """        ERR2:           next_state = IDLE; // PLANT H2""")]),
    "H3_idle_no_hready": ("IDLE decodes an address phase without HREADY", [
        (IF, """        IDLE:           if(accept)""",
             """        IDLE:           if(HSELx & HTRANS[1]) // PLANT H3""")]),
    "H4_stale_ack": ("started set by any ack_sync; ENABLE raised with ack_sync high", [
        (IF, """            if(ahb_qspi_busy_sync!=1'b1 && !ahb_qspi_enable_ack_sync &&
               !SOFT_RESET) begin""",
             """            if(ahb_qspi_busy_sync!=1'b1 &&
               !SOFT_RESET) begin // PLANT H4"""),
        (IF, """            if(ahb_qspi_enable_ack_sync && AHB_QSPI_ENABLE) begin""",
             """            if(ahb_qspi_enable_ack_sync) begin // PLANT H4""")]),
    "H5_no_capture_on_done": ("completion cycle keeps the handshake (no clear/capture)", [
        (IF, """        if(current_state == WAIT_READ && !qspi_ready) begin""",
             """        if(current_state == WAIT_READ) begin // PLANT H5""")]),
    "H6_hrdata_no_reset": ("HRDATA not reset", [
        (IF, """        HRDATA <= {DATA_W{1'b0}};\n""", "")]),
    "H7_soft_reset_no_guard": ("next fetch not held off while SOFT_RESET is high", [
        (IF, """            if(ahb_qspi_busy_sync!=1'b1 && !ahb_qspi_enable_ack_sync &&
               !SOFT_RESET) begin""",
             """            if(ahb_qspi_busy_sync!=1'b1 && !ahb_qspi_enable_ack_sync) begin // PLANT H7""")]),
    "H8_watchdog_not_per_transfer": ("watchdog keeps counting across a back-to-back read", [
        (IF, """        if(current_state == WAIT_READ && !qspi_ready && !SOFT_RESET &&""",
             """        if(current_state == WAIT_READ && !SOFT_RESET && // PLANT H8""")]),
    # ---- A1 plants (re-anchored) -------------------------------------------
    "P1_err_one_cycle": ("(A1 P1 / A2 err_1cycle) ERR1 drives HREADYOUT=1", [
        (IF, "1'b0; // ERR1", "1'b1; // ERR1 (PLANT P1)")]),
    "P2_busy_waited": ("(A1 P2 / A2 busy_wait) a BUSY transfer gets a wait state", [
        (IF, """                   (current_state==IDLE)      ? 1'b1                      :""",
             """                   (current_state==IDLE)      ? (last_HTRANS!=2'b01)      : // PLANT P2""")]),
    "P3_rdata_byteswap": ("(A1 P3) byte swap in HRDATA word 0", [
        (IF, "wire [31:0] AHB_QSPI_RDATA_W2 = {AHB_QSPI_RDATA[7:0], AHB_QSPI_RDATA[15:8],",
             "wire [31:0] AHB_QSPI_RDATA_W2 = {AHB_QSPI_RDATA[15:8], AHB_QSPI_RDATA[7:0],")]),
    "P4_ahb_busy_late": ("(A1 P4) AHB BUSY rises after ACK", [
        (MUX, "AHB_QSPI_BUSY_q       <= AHB_QSPI_BUSY_in | AHB_QSPI_BUSY_del | AHB_QSPI_BUSY_del1 | AHB_QSPI_BUSY_del2;",
              "AHB_QSPI_BUSY_q       <= AHB_QSPI_BUSY_del2 & AHB_QSPI_BUSY_del1; // PLANT P4")]),
    "P5_apb_busy_zero": ("(A1 P5) APB BUSY stuck 0", [
        (MUX, "APB_QSPI_BUSY_q       <= APB_QSPI_BUSY_in;", "APB_QSPI_BUSY_q       <= 1'b0; // PLANT P5")]),
    "P6_apb_ack_late": ("(A1 P6) APB ACK 6 SCLK late", [
        (MUX, "assign APB_QSPI_ENABLE_ACK = (XIP_ACTIVE==1'b0) ? QSPI_ENABLE_ACK : 1'b0;",
              "reg [5:0] ack_dly; always @(posedge QSPI_SCLK or negedge HRESETn) if(~HRESETn) ack_dly<=0; else ack_dly<={ack_dly[4:0],QSPI_ENABLE_ACK};\n"
              "assign APB_QSPI_ENABLE_ACK = (XIP_ACTIVE==1'b0) ? ack_dly[5] : 1'b0; // PLANT P6")]),
    "P7_ctl_no_hreset": ("(A1 P7) controller FSM ignores HRESETn", [
        (CTL, "    if(~HRESETn) begin\n        current_state <= IDLE;\n    end else if (soft_reset_sync) begin\n        current_state <= IDLE;   // watchdog-driven soft reset",
              "    if(~HRESETn) begin\n        current_state <= current_state; // PLANT P7\n    end else if (soft_reset_sync) begin\n        current_state <= IDLE;   // watchdog-driven soft reset"),
        (CTL, "fsm_state_e current_state, next_state;", "fsm_state_e current_state = IDLE, next_state;")]),
    "P7d_if_state_no_reset": ("(A1 P7d) interface FSM ignores HRESETn", [
        (IF, "        current_state <= IDLE;\n    end else begin\n        last_HSEL   <= HSELx;",
             "        current_state <= current_state; // PLANT P7d\n    end else begin\n        last_HSEL   <= HSELx;"),
        (IF, "enum {IDLE, WAIT_READ, ERR1, ERR2} current_state, next_state;",
             "enum {IDLE, WAIT_READ, ERR1, ERR2} current_state = IDLE, next_state;")]),
    "P8_no_watchdog": ("(A1 P8) watchdog never expires", [
        (IF, "(watchdog_cnt == {WATCHDOG_WIDTH{1'b1}});", "1'b0; // PLANT P8")]),
    "P9_apb_rdata_mux": ("(A1 P9) APB RDATA mux select inverted", [
        (MUX, "assign APB_QSPI_RDATA = (XIP_ACTIVE==1'b0) ?  QSPI_RDATA : 128'd0;",
              "assign APB_QSPI_RDATA = (XIP_ACTIVE==1'b1) ?  QSPI_RDATA : 128'd0; // PLANT P9")]),
    "P10_ahb_busy_zero": ("(A1 P10) AHB BUSY stuck 0", [
        (MUX, "assign AHB_QSPI_BUSY = AHB_QSPI_BUSY_q;", "assign AHB_QSPI_BUSY = 1'b0; // PLANT P10")]),
    "P11_cdc_glitch": ("(A1 P11) zero-time pulse on APB BUSY", [
        (MUX, "assign APB_QSPI_BUSY = APB_QSPI_BUSY_q;",
              "reg sclk_buf; always @(QSPI_SCLK) sclk_buf = QSPI_SCLK;\n"
              "assign APB_QSPI_BUSY = APB_QSPI_BUSY_q | (QSPI_SCLK & ~sclk_buf); // PLANT P11")]),
    "P12b_addr_from_last": ("(A1 P12b / A2 addr_stale) fetch address from last cycle's HADDR", [
        (IF, "            AHB_QSPI_ADDR <= {HADDR[ADDR_W-1:4],4'b0000};",
             "            AHB_QSPI_ADDR <= {last_HADDR[ADDR_W-1:4],4'b0000}; // PLANT P12b")]),
    # ---- A2 plants not covered above (re-anchored) -------------------------
    "A2_err_skip2": ("(A2 err_skip2) ERR1 -> IDLE, no 2nd ERROR cycle", [
        (IF, "        ERR1:           next_state = ERR2;", "        ERR1:           next_state = IDLE; // PLANT")]),
    "A2_resp_glitch": ("(A2 resp_glitch) HRESP drops in ERR2", [
        (IF, "assign HRESP = (current_state == ERR1 || current_state == ERR2) ? 1'b1 : 1'b0;",
             "assign HRESP = (current_state == ERR1) ? 1'b1 : 1'b0; // PLANT")]),
    "A2_no_fetch_wait": ("(A2 no_fetch_wait) complete without waiting for the fetch", [
        (IF, "            if(qspi_started==1'b1) begin\n                if(ahb_qspi_busy_sync==1'b0) begin",
             "            if(1'b1) begin // PLANT\n                if(ahb_qspi_busy_sync==1'b0) begin")]),
    "A2_lane_swap": ("(A2 lane_swap) HRDATA words W0/W1 swapped", [
        (IF, "wire [127:0] AHB_QSPI_RDATA_i = {AHB_QSPI_RDATA_W3,AHB_QSPI_RDATA_W0, AHB_QSPI_RDATA_W1, AHB_QSPI_RDATA_W2};",
             "wire [127:0] AHB_QSPI_RDATA_i = {AHB_QSPI_RDATA_W3,AHB_QSPI_RDATA_W1, AHB_QSPI_RDATA_W0, AHB_QSPI_RDATA_W2}; // PLANT")]),
    "A2_write_ok": ("(A2 write_ok) writes are fetched as reads (no ERROR)", [
        (IF, "wire accept_err = ~XIP_ACTIVE | HWRITE;", "wire accept_err = ~XIP_ACTIVE; // PLANT")]),
}


def make(src, out, name):
    desc, edits = PLANTS[name]
    dst = os.path.join(out, name)
    if os.path.exists(dst):
        shutil.rmtree(dst)
    shutil.copytree(os.path.join(src, "logical"), os.path.join(dst, "logical"))
    for f, old, new in edits:
        p = os.path.join(dst, f)
        s = open(p).read()
        if s.count(old) != 1:
            sys.exit(f"plants: anchor for {name} found {s.count(old)} times in {f}")
        open(p, "w").write(s.replace(old, new))
    return dst


def main():
    if sys.argv[1:2] == ["--list"]:
        for n, (d, _) in PLANTS.items():
            print(f"{n:30s} {d}")
        return
    src, out = sys.argv[1:3]
    src_real, out_real = os.path.realpath(src), os.path.realpath(out)
    if out_real.startswith(os.path.join(src_real, "logical")):
        sys.exit("plants: out dir must not be inside the RTL tree")
    for n in sys.argv[3:] or list(PLANTS):
        print("made", make(src, out, n))


if __name__ == "__main__":
    main()
