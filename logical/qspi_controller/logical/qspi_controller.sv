
module qspi_controller (
    input  wire         HCLK,
    input  wire         HRESETn,

    // Soft reset from the AHB watchdog (HCLK domain). Asserted level-high
    // when the AHB interface's WAIT_READ timeout fires. Synchronised into
    // the QSPI_SCLK_i domain below and used as a synchronous reset on the
    // FSM and its counters to recover from a wedged state without
    // requiring a full system reset.
    input  wire         SOFT_RESET,

    input  wire         QSPI_SCLK_i,

    input  wire [1:0]   QSPI_SPI_MODE, // {CPOL, CPHA}

    input  wire [7:0]   QSPI_CMD,
    input  wire         QSPI_ENABLE,
    output reg          QSPI_ENABLE_ACK,
    input  wire         QSPI_READ,
    input  wire         QSPI_WRITE,
    input  wire         QSPI_ADDR_EN,
    input  wire [3:0]   QSPI_DUMMY_CYCLES,
    input  wire [4:0]   QSPI_N_RW_BYTES,
    input  wire [21:0]  QSPI_ADDR,
    input  wire [127:0] QSPI_WDATA,
    output reg  [127:0] QSPI_RDATA,
    input  wire         QSPI_QIO_MODE,
    input  wire         QSPI_CONT_READ,
    input  wire [7:0]   QSPI_MODE_CODE,
    input  wire         QSPI_NO_CMD,

    // QSPI Interface
    output wire         QSPI_SCLK,
    output wire         QSPI_nCS,
    output wire [3:0]   QSPI_IO_o,
    input  wire [3:0]   QSPI_IO_i,
    output wire [3:0]   QSPI_IO_e

);

reg     QSPI_SCLK_e;

assign QSPI_SCLK = (QSPI_SCLK_e==1'b1) ? QSPI_SCLK_i : QSPI_SPI_MODE[1];

typedef enum {IDLE, NO_FETCH, OP, ADDR, MODE, DUMMY, DATA_O, DATA_I} fsm_state_e;
fsm_state_e current_state, next_state;

reg [2:0]   op_counter;
reg [4:0]   addr_counter;
reg         mode_counter;
reg [2:0]   data_counter;
reg [3:0]   dummy_counter;
reg [4:0]   byte_counter;
reg [7:0]   op_code;
reg [23:0]  addr_code;
reg [7:0]   qspi_mode_reg;
reg [3:0]   QSPI_IO_o_reg;
reg [127:0] data_in_reg;
reg [21:0]  last_QSPI_ADDR;

// 3-FF CDC synchronizer for QSPI_ENABLE (HCLK/PCLK -> QSPI_SCLK_i domain).
//
// Why 3-FF for ENABLE when the control bus (QSPI_READ, QSPI_WRITE,
// QSPI_N_RW_BYTES, etc.) is only 2-FF:
//
// Software writes control regs at PCLK cycle T and enable at cycle T+1 —
// separate APB transactions. Both sets of signals then cross into
// QSPI_SCLK_i via independent 2-FF synchronisers whose metastability
// resolution is independent. If the enable chain resolves one SCLK cycle
// earlier than the control chain (legal under the CDC contract), the
// latch at QSPI_enable_sync_rise fires while qspi_xxx_sync still holds
// the previous value — silent miscapture of N_RW_BYTES / READ / WRITE /
// QIO mode, and a wrong-shaped operation on the bus.
//
// Giving ENABLE one extra pipeline stage forces its observed rising edge
// to appear >=1 SCLK cycle after the control-bus 2-FF chain has had time
// to settle, removing the race without any software protocol changes.
reg QSPI_enable_sync_meta;
reg QSPI_enable_sync_s2;
reg QSPI_enable_sync;
reg QSPI_enable_sync_prev;

always @(posedge QSPI_SCLK_i or negedge HRESETn) begin
    if(~HRESETn) begin
        QSPI_enable_sync_meta <= 1'b0;
        QSPI_enable_sync_s2   <= 1'b0;
        QSPI_enable_sync      <= 1'b0;
        QSPI_enable_sync_prev <= 1'b0;
    end else begin
        QSPI_enable_sync_meta <= QSPI_ENABLE;
        QSPI_enable_sync_s2   <= QSPI_enable_sync_meta;
        QSPI_enable_sync      <= QSPI_enable_sync_s2;
        QSPI_enable_sync_prev <= QSPI_enable_sync;
    end
end
wire QSPI_enable_sync_rise = QSPI_enable_sync & ~QSPI_enable_sync_prev;

// 2-FF CDC synchroniser for SOFT_RESET (HCLK -> QSPI_SCLK_i).
// SOFT_RESET is held high for multiple HCLK cycles by the AHB watchdog,
// so a 2-FF sync is adequate and we don't need async-assert handling
// (SOFT_RESET is a synchronous reset, not an async one).
reg soft_reset_sync_meta;
reg soft_reset_sync;
always @(posedge QSPI_SCLK_i or negedge HRESETn) begin
    if(~HRESETn) begin
        soft_reset_sync_meta <= 1'b0;
        soft_reset_sync      <= 1'b0;
    end else begin
        soft_reset_sync_meta <= SOFT_RESET;
        soft_reset_sync      <= soft_reset_sync_meta;
    end
end

// ============================================================
// Control-bus CDC sync + edge-triggered latch (Bug A fix)
// ============================================================
// Every HCLK-domain control signal is passed through its own 2-FF
// synchroniser and then latched on the rising edge of QSPI_enable_sync.
// The previous "track while current_state==IDLE" scheme had a race: a
// second APB write arriving before QSPI_enable_sync rose could slip the
// corrupted value into the latch on the cycle the FSM transitioned out
// of IDLE. Gating capture on the enable-sync rising edge instead
// guarantees the latched control bus is whatever was valid at the
// moment the (synchronised) enable was first seen, regardless of
// subsequent software activity.
reg [4:0]   qspi_n_rw_bytes_meta,   qspi_n_rw_bytes_sync;
reg [3:0]   qspi_dummy_cycles_meta, qspi_dummy_cycles_sync;
reg         qspi_read_meta,         qspi_read_sync;
reg         qspi_write_meta,        qspi_write_sync;
reg         qspi_addr_en_meta,      qspi_addr_en_sync;
reg         qspi_qio_mode_meta,     qspi_qio_mode_sync;
reg         qspi_cont_read_meta,    qspi_cont_read_sync;
reg [7:0]   qspi_mode_code_meta,    qspi_mode_code_sync;
reg         qspi_no_cmd_meta,       qspi_no_cmd_sync;

always @(posedge QSPI_SCLK_i or negedge HRESETn) begin
    if(~HRESETn) begin
        qspi_n_rw_bytes_meta   <= 5'h0; qspi_n_rw_bytes_sync   <= 5'h0;
        qspi_dummy_cycles_meta <= 4'h0; qspi_dummy_cycles_sync <= 4'h0;
        qspi_read_meta         <= 1'b0; qspi_read_sync         <= 1'b0;
        qspi_write_meta        <= 1'b0; qspi_write_sync        <= 1'b0;
        qspi_addr_en_meta      <= 1'b0; qspi_addr_en_sync      <= 1'b0;
        qspi_qio_mode_meta     <= 1'b0; qspi_qio_mode_sync     <= 1'b0;
        qspi_cont_read_meta    <= 1'b0; qspi_cont_read_sync    <= 1'b0;
        qspi_mode_code_meta    <= 8'h0; qspi_mode_code_sync    <= 8'h0;
        qspi_no_cmd_meta       <= 1'b0; qspi_no_cmd_sync       <= 1'b0;
    end else begin
        qspi_n_rw_bytes_meta   <= QSPI_N_RW_BYTES;   qspi_n_rw_bytes_sync   <= qspi_n_rw_bytes_meta;
        qspi_dummy_cycles_meta <= QSPI_DUMMY_CYCLES; qspi_dummy_cycles_sync <= qspi_dummy_cycles_meta;
        qspi_read_meta         <= QSPI_READ;         qspi_read_sync         <= qspi_read_meta;
        qspi_write_meta        <= QSPI_WRITE;        qspi_write_sync        <= qspi_write_meta;
        qspi_addr_en_meta      <= QSPI_ADDR_EN;      qspi_addr_en_sync      <= qspi_addr_en_meta;
        qspi_qio_mode_meta     <= QSPI_QIO_MODE;     qspi_qio_mode_sync     <= qspi_qio_mode_meta;
        qspi_cont_read_meta    <= QSPI_CONT_READ;    qspi_cont_read_sync    <= qspi_cont_read_meta;
        qspi_mode_code_meta    <= QSPI_MODE_CODE;    qspi_mode_code_sync    <= qspi_mode_code_meta;
        qspi_no_cmd_meta       <= QSPI_NO_CMD;       qspi_no_cmd_sync       <= qspi_no_cmd_meta;
    end
end

reg [4:0]   qspi_n_rw_bytes_latched;
reg [3:0]   qspi_dummy_cycles_latched;
reg         qspi_read_latched;
reg         qspi_write_latched;
reg         qspi_addr_en_latched;
reg         qspi_qio_mode_latched;
reg         qspi_cont_read_latched;
reg [7:0]   qspi_mode_code_latched;
reg         qspi_no_cmd_latched;

always @(posedge QSPI_SCLK_i or negedge HRESETn) begin
    if(~HRESETn) begin
        qspi_n_rw_bytes_latched   <= 5'h0;
        qspi_dummy_cycles_latched <= 4'h0;
        qspi_read_latched         <= 1'b0;
        qspi_write_latched        <= 1'b0;
        qspi_addr_en_latched      <= 1'b0;
        qspi_qio_mode_latched     <= 1'b0;
        qspi_cont_read_latched    <= 1'b0;
        qspi_mode_code_latched    <= 8'h0;
        qspi_no_cmd_latched       <= 1'b0;
    end else if (soft_reset_sync) begin
        // synchronous soft-reset via watchdog
        qspi_n_rw_bytes_latched   <= 5'h0;
        qspi_dummy_cycles_latched <= 4'h0;
        qspi_read_latched         <= 1'b0;
        qspi_write_latched        <= 1'b0;
        qspi_addr_en_latched      <= 1'b0;
        qspi_qio_mode_latched     <= 1'b0;
        qspi_cont_read_latched    <= 1'b0;
        qspi_mode_code_latched    <= 8'h0;
        qspi_no_cmd_latched       <= 1'b0;
    end else if (QSPI_enable_sync_rise) begin
        // Capture the synced control bus on the cycle enable_sync rises.
        // The 3-FF enable chain (vs 2-FF on the control bus) guarantees
        // the rising edge seen here is at least one SCLK cycle after the
        // control-bus sync chain has had time to settle, so the sampled
        // qspi_xxx_sync values are the ones software intended.
        qspi_n_rw_bytes_latched   <= qspi_n_rw_bytes_sync;
        qspi_dummy_cycles_latched <= qspi_dummy_cycles_sync;
        qspi_read_latched         <= qspi_read_sync;
        qspi_write_latched        <= qspi_write_sync;
        qspi_addr_en_latched      <= qspi_addr_en_sync;
        qspi_qio_mode_latched     <= qspi_qio_mode_sync;
        qspi_cont_read_latched    <= qspi_cont_read_sync;
        qspi_mode_code_latched    <= qspi_mode_code_sync;
        qspi_no_cmd_latched       <= qspi_no_cmd_sync;
    end
    // Enable not rising -> hold latched values
end

reg [127:0]   QSPI_WDATA_reg;

assign QSPI_IO_o = QSPI_IO_o_reg;

always @(posedge QSPI_SCLK_i or negedge HRESETn) begin
    if(~HRESETn) begin
        current_state <= IDLE;
    end else if (soft_reset_sync) begin
        current_state <= IDLE;   // watchdog-driven soft reset
    end else begin
        current_state <= next_state;
    end
end

// FSM:Next state decision tree
always_comb begin
    next_state = IDLE;
    QSPI_ENABLE_ACK = 1'b0;
    case(current_state)
        IDLE: begin
            if(QSPI_enable_sync==1'b1 && qspi_no_cmd_latched==1'b0) begin
                next_state = OP;
            end else if(QSPI_enable_sync==1'b1 && qspi_no_cmd_latched==1'b1) begin
                if(last_QSPI_ADDR==QSPI_ADDR)
                    next_state = NO_FETCH;
                else
                    next_state = ADDR;
            end
            //op_counter=3'h0;
        end
        NO_FETCH: begin
            QSPI_ENABLE_ACK = 1'b1;
            if(QSPI_enable_sync==1'b0)
                next_state = IDLE;
        end
        OP: begin
            QSPI_ENABLE_ACK = 1'b1;
            next_state = OP;
            // Next state decision from OP if in QPI mode
            if(qspi_qio_mode_latched==1'b1 & op_counter==3'h1) begin
                QSPI_ENABLE_ACK = 1'b0;
                if(qspi_addr_en_latched)
                    next_state = ADDR;
                else if(qspi_dummy_cycles_latched!=4'h0)
                    next_state = DUMMY;
                else if(qspi_read_latched)
                    next_state = DATA_I;
                else if(qspi_write_latched)
                    next_state = DATA_O;
                else
                    next_state = IDLE;
            end
            // Next state decision from OP if in SPI mode
            else if(qspi_qio_mode_latched==1'b0 & op_counter==3'h7) begin
                QSPI_ENABLE_ACK = 1'b0;
                if(qspi_addr_en_latched)
                    next_state = ADDR;
                else if(qspi_dummy_cycles_latched!=4'h0)
                    next_state = DUMMY;
                else if(qspi_read_latched)
                    next_state = DATA_I;
                else if(qspi_write_latched)
                    next_state = DATA_O;
                else
                    next_state = IDLE;
            end else begin
                next_state = OP;
            end
        end
        ADDR: begin
            QSPI_ENABLE_ACK = 1'b1;
            // Next state decision from ADDR if in QPI mode
            if(qspi_qio_mode_latched==1'b1 & addr_counter==5'h05) begin
                QSPI_ENABLE_ACK = 1'b0;
                if(qspi_cont_read_latched)
                    next_state = MODE;
                else if(qspi_dummy_cycles_latched!=4'h0)
                    next_state = DUMMY;
                else if(qspi_read_latched)
                    next_state = DATA_I;
                else if(qspi_write_latched)
                    next_state = DATA_O;
                else
                    next_state = IDLE;
            end
            // Next state decision from ADDR if in SPI mode
            else if(qspi_qio_mode_latched==1'b0 & addr_counter==5'h17) begin
                QSPI_ENABLE_ACK = 1'b0;
                if(qspi_dummy_cycles_latched!=4'h0)
                    next_state = DUMMY;
                else if(qspi_read_latched)
                    next_state = DATA_I;
                else if(qspi_write_latched)
                    next_state = DATA_O;
                else
                    next_state = IDLE;
            end else begin
                next_state = ADDR;
            end
        end
        MODE: begin
            // Next state decision from MODE if in QPI mode
            if(qspi_qio_mode_latched==1'b1 & mode_counter == 1'b0) begin
                if(qspi_dummy_cycles_latched!=4'h0)
                    next_state = DUMMY;
                else if(qspi_read_latched)
                    next_state = DATA_I;
                else if(qspi_write_latched)
                    next_state = DATA_O;
                else
                    next_state = IDLE;
            end
            // Next state decision from MODE if in SPI mode
            else if(qspi_qio_mode_latched==1'b0) begin
                next_state = IDLE;
            end else begin 
                next_state = MODE;
            end
        end
        DUMMY: begin
            // Next state decision from DUMMY
            if(dummy_counter >= (qspi_dummy_cycles_latched - 1)) begin
                if(qspi_write_latched)
                    next_state = DATA_O;
                else if(qspi_read_latched)
                    next_state = DATA_I;
                else
                    next_state = IDLE;
            end else begin
                next_state = DUMMY;
            end
        end
        DATA_O: begin
            if(byte_counter==5'h1F) begin
                next_state = DATA_O;
            end else begin
                // Next state decision from DATA_O if in QPI mode
                if(qspi_qio_mode_latched==1'b0) begin
                    if(byte_counter==qspi_n_rw_bytes_latched) begin
                        if(data_counter == 3'h7)
                            next_state = IDLE;
                        else
                            next_state = DATA_O;
                    end else begin
                        next_state = DATA_O;
                    end
                end 
                // Next state decision from DATA_O if in SPI mode
                else begin
                    if(byte_counter==qspi_n_rw_bytes_latched) begin
                        if(data_counter==3'h0)
                            next_state = IDLE;
                        else
                            next_state = DATA_O;
                    end else begin
                        next_state = DATA_O;
                    end
                end
            end
        end
        DATA_I: begin
            next_state = DATA_I;
            // Next state decision from DATA_I if in QPI mode
            if(qspi_qio_mode_latched==1'b0) begin
                if((byte_counter[3:0]==qspi_n_rw_bytes_latched)) begin
                    if(data_counter==3'h6)
                        next_state = IDLE;
                    else
                        next_state = DATA_I;
                end
            end 
            // Next state decision from DATA_I if in SPI mode
            else begin
                if((byte_counter==qspi_n_rw_bytes_latched)) begin
                    if(data_counter==3'h0)
                        next_state = IDLE;
                    else
                        next_state = DATA_I;
                end
            end
        end
        default: next_state = IDLE;
    endcase
end

reg QSPI_IO_e_int;

// Negedge shift-out block — single top-level if-else chain required for
// SpyGlass CDC synthesis (SYNTH_133).
//
// This block holds only the QSPI pin-drive state that genuinely needs a
// defined value out of reset: QSPI_SCLK_e (clock-enable, idle low),
// QSPI_IO_o_reg (data out, idle 4'hF) and QSPI_IO_e_int (output-enable,
// idle driving). The shift-register *storage* (op_code, addr_code,
// qspi_mode_reg, QSPI_WDATA_reg) was moved to the no-reset block below
// (Task 2). The if-else-on-current_state chain structure is preserved in
// both blocks so the SYNTH_133 CDC contract still holds.
always @(negedge QSPI_SCLK_i or negedge HRESETn) begin
    if(~HRESETn) begin
        QSPI_SCLK_e <= 1'b0;
        QSPI_IO_o_reg <= 4'hF;
        QSPI_IO_e_int <= 1'b1;
        op_code <= 8'h00;
        addr_code <= 24'h000000;
        qspi_mode_reg <= 8'h00;
        QSPI_WDATA_reg <= 128'd0;
    end else if (soft_reset_sync) begin
        // synchronous soft-reset via watchdog (matches the pattern at L182)
        QSPI_SCLK_e <= 1'b0;
        QSPI_IO_o_reg <= 4'hF;
        QSPI_IO_e_int <= 1'b1;
    end else if(current_state==OP) begin
        QSPI_IO_e_int <= 1'b1;
        QSPI_SCLK_e <= 1'b1;
        if(qspi_qio_mode_latched==1'b1) begin
            QSPI_IO_o_reg[3:0]<=op_code[7:4];
        end else begin
            QSPI_IO_o_reg[3:0]<={3'h7, op_code[7]};
        end
    end else if(current_state == DATA_I) begin
        QSPI_IO_e_int <= 1'b0;
        QSPI_SCLK_e <= 1'b1;
    end else if(current_state == DATA_O) begin
        QSPI_IO_e_int <= 1'b1;
        QSPI_SCLK_e <= 1'b1;
        // DATA_O: WDATA_reg is shifted out, NOT reloaded.
        //
        // SPI-mode bug workaround: during the counter-overflow guard cycle
        // (byte_counter==0x1F on the first DATA_O cycle), the shift-out
        // logic previously ran unconditionally, producing one spurious
        // extra bit on MOSI before the real payload. The flash rejected
        // the resulting Page Program as malformed. Gating the shift (and
        // clock) on byte_counter != 0x1F suppresses that spurious bit.
        //
        // QPI mode behaves differently: its counter rolls over every
        // cycle (data_counter >= 1), so what looks like a guard cycle is
        // actually the first legitimate nibble shift — do NOT suppress.
        if(qspi_qio_mode_latched==1'b1) begin
            QSPI_IO_o_reg <= QSPI_WDATA_reg[3:0];
        end else if(byte_counter != 5'h1F) begin
            QSPI_IO_o_reg[0] <= QSPI_WDATA_reg[0];
        end else begin
            QSPI_SCLK_e <= 1'b0;  // suppress the spurious SPI-mode clock
        end
    end else if(current_state == ADDR) begin
        QSPI_IO_e_int <= 1'b1;
        QSPI_SCLK_e <= 1'b1;
        if(qspi_qio_mode_latched==1'b1) begin
            QSPI_IO_o_reg[3:0]<=addr_code[23:20];
        end else begin
            QSPI_IO_o_reg[3:0]<={3'h7, addr_code[23]};
        end
    end else if(current_state == DUMMY) begin
        QSPI_IO_e_int <= 1'b0;
        QSPI_SCLK_e <= 1'b1;
    end else if(current_state == MODE) begin
        QSPI_IO_e_int <=1'b1;
        QSPI_SCLK_e <= 1'b1;
        if(qspi_qio_mode_latched==1'b1) begin
            QSPI_IO_o_reg <= qspi_mode_reg[7:4];
        end
    end else begin
        QSPI_SCLK_e<=1'b0;
        QSPI_IO_o_reg<=4'hF;
        QSPI_IO_e_int <= 1'b1;
    end
end

// Shift-register storage bank — NO reset branch (Task 2).
//
// op_code, addr_code, qspi_mode_reg and QSPI_WDATA_reg are every one
// loaded from a primary input (QSPI_CMD / QSPI_ADDR / mode-code /
// QSPI_WDATA) in the idle/default branch before the FSM can leave IDLE,
// so they are always written before any state that reads them. The
// async-reset clear was therefore functionally redundant and only forced
// DC onto DFFNRPQ_X1M (~12 um2) instead of plain DFFNQ (~10 um2) on 168
// flops. Dropping the reset branch lets DC pick the smaller flop.
//
// The single if-else-on-current_state chain is mirrored from the block
// above so the SYNTH_133 CDC structure is unchanged. The RHS reads here
// (e.g. op_code[7:4]) and the pin-drive reads in the block above all
// sample the pre-update value on the same negedge (non-blocking), so the
// split is bit-exact with the original merged block.
always @(negedge QSPI_SCLK_i) begin
    if(soft_reset_sync) begin
        // synchronous soft-reset via watchdog (kept: matches the
        // pin-drive block's soft_reset behaviour; no async reset).
        op_code <= 8'h00;
        addr_code <= 24'h000000;
        qspi_mode_reg <= 8'h00;
        QSPI_WDATA_reg <= 128'd0;
    end else if(current_state==OP) begin
        if(qspi_qio_mode_latched==1'b1) begin
            op_code[7:0] <= {op_code[3:0],4'h0};
        end else begin
            op_code[7:0] <= {op_code[6:0], 1'b0};
        end
    end else if(current_state == DATA_O) begin
        if(qspi_qio_mode_latched==1'b1) begin
            QSPI_WDATA_reg <= {4'h0, QSPI_WDATA_reg[127:4]};
        end else if(byte_counter != 5'h1F) begin
            QSPI_WDATA_reg <= {1'b0, QSPI_WDATA_reg[127:1]};
        end
    end else if(current_state == ADDR) begin
        if(qspi_qio_mode_latched==1'b1) begin
            addr_code[23:0] <= {addr_code[19:0],4'h0};
        end else begin
            addr_code[23:0] <= {addr_code[22:0], 1'b0};
        end
    end else if(current_state == MODE) begin
        if(qspi_qio_mode_latched==1'b1) begin
            qspi_mode_reg <= {qspi_mode_reg[3:0], 4'b0};
        end
    end else if(current_state == DATA_I || current_state == DUMMY) begin
        // hold — DATA_I/DUMMY do not touch the shift-register bank
    end else begin
        op_code <= QSPI_CMD;
        addr_code <= {2'b00,QSPI_ADDR};
        qspi_mode_reg <= qspi_mode_code_latched;
        QSPI_WDATA_reg <= QSPI_WDATA;
    end
end
always @(posedge QSPI_SCLK_i or negedge HRESETn) begin
    if(~HRESETn) begin
        op_counter <= 3'h0;
        data_counter <= 3'h7;
        byte_counter <= 5'h1F;
        dummy_counter <= 4'h0;
        addr_counter <= 5'h00;
        mode_counter <= 1'b1;
        data_in_reg <= 128'd0;
        last_QSPI_ADDR <= 22'd0;
    end else if (soft_reset_sync) begin
        // synchronous soft-reset via watchdog
        op_counter <= 3'h0;
        data_counter <= 3'h7;
        byte_counter <= 5'h1F;
        dummy_counter <= 4'h0;
        addr_counter <= 5'h00;
        mode_counter <= 1'b1;
        data_in_reg <= 128'd0;
        last_QSPI_ADDR <= 22'd0;
    end else begin
        if(current_state==OP) begin
            data_in_reg <= 128'd0;
            op_counter<=op_counter+1;
        end else begin
            op_counter <= 3'h0;
        end

        if(current_state==DATA_I || current_state ==DATA_O) begin
            data_counter <= data_counter + 1;
            if(qspi_qio_mode_latched==1'b0 && data_counter == 3'h7) begin
                byte_counter <= byte_counter+1;
                data_counter <= 3'h0;
            end else if (qspi_qio_mode_latched==1'b1 && data_counter >= 3'h1) begin
                byte_counter <= byte_counter+1;
                data_counter <= 3'h0;
            end
        end else begin
            data_counter <= 3'h7;
            byte_counter <= 5'h1F;
        end

        if(current_state == DUMMY) begin
            dummy_counter <= dummy_counter + 1;
        end else begin
            dummy_counter <= 4'h0;
        end

        if(current_state == ADDR) begin
            addr_counter <= addr_counter + 1;
            if(next_state != ADDR)
                last_QSPI_ADDR <= QSPI_ADDR;
        end else begin
            addr_counter <= 5'h00;
        end

        if(current_state == MODE) begin
            mode_counter <= mode_counter + 1;
        end else begin
            mode_counter <= 1'b1;
        end

        if(current_state == DATA_I) begin
            if(qspi_qio_mode_latched==1'b1) begin
                if(byte_counter!=qspi_n_rw_bytes_latched+1)
                    data_in_reg <= {data_in_reg[123:0], QSPI_IO_i};
            end else begin
                if(byte_counter!=qspi_n_rw_bytes_latched+1)
                    data_in_reg <= {data_in_reg[126:0], QSPI_IO_i[1]};
            end
        end

    end
end

// RDATA output — purely combinational, no latch.
//
// qspi_n_rw_bytes_latched is 5 bits; the case tags below are width-
// matched 5-bit literals (was 4-bit, which raised 16 UELCIT lint
// warnings — selector 5b vs tag 4b). N_RW_BYTES is a 4-bit register
// field (apb_qspi_regs.rdl: N_RW_BYTES[4], range 0x0..0xF = 1..16
// bytes) zero-extended into this 5-bit port at the single instantiation
// site (top_ahb_qspi.v: `{1'b0, QSPI_N_RW_BYTES}`), so values 0x10..0x1F
// are not reachable in the current design. The default arm therefore
// returns the full 16-byte view rather than 128'd0: if a future change
// ever widens the field or drives bit[4], a read degrades gracefully to
// "all captured bytes" instead of silently returning zero (the prior
// behaviour gave no error indication — see qspi_controller_optimisation
// _plan.md Task 3/7).
always_comb begin
    case(qspi_n_rw_bytes_latched)
        5'h00:  QSPI_RDATA = {{120{1'b0}}, data_in_reg[7:0 ]};
        5'h01:  QSPI_RDATA = {{112{1'b0}}, data_in_reg[15:0]};
        5'h02:  QSPI_RDATA = {{104{1'b0}}, data_in_reg[23:0]};
        5'h03:  QSPI_RDATA = {{96{1'b0}},  data_in_reg[31:0]};
        5'h04:  QSPI_RDATA = {{88{1'b0}},  data_in_reg[31:0], data_in_reg[39:32]};
        5'h05:  QSPI_RDATA = {{80{1'b0}},  data_in_reg[31:0], data_in_reg[47:32]};
        5'h06:  QSPI_RDATA = {{72{1'b0}},  data_in_reg[31:0], data_in_reg[55:32]};
        5'h07:  QSPI_RDATA = {{64{1'b0}},  data_in_reg[31:0], data_in_reg[63:32]};
        5'h08:  QSPI_RDATA = {{56{1'b0}},  data_in_reg[31:0], data_in_reg[63:32], data_in_reg[71:64]};
        5'h09:  QSPI_RDATA = {{48{1'b0}},  data_in_reg[31:0], data_in_reg[63:32], data_in_reg[79:64]};
        5'h0A:  QSPI_RDATA = {{40{1'b0}},  data_in_reg[31:0], data_in_reg[63:32], data_in_reg[87:64]};
        5'h0B:  QSPI_RDATA = {{32{1'b0}},  data_in_reg[31:0], data_in_reg[63:32], data_in_reg[95:64]};
        5'h0C:  QSPI_RDATA = {{24{1'b0}},  data_in_reg[31:0], data_in_reg[63:32], data_in_reg[95:64], data_in_reg[103:96]};
        5'h0D:  QSPI_RDATA = {{16{1'b0}},  data_in_reg[31:0], data_in_reg[63:32], data_in_reg[95:64], data_in_reg[111:96]};
        5'h0E:  QSPI_RDATA = {{8{1'b0}},   data_in_reg[31:0], data_in_reg[63:32], data_in_reg[95:64], data_in_reg[119:96]};
        5'h0F:  QSPI_RDATA = {data_in_reg[31:0], data_in_reg[63:32], data_in_reg[95:64], data_in_reg[127:96]};
        default: QSPI_RDATA = {data_in_reg[31:0], data_in_reg[63:32], data_in_reg[95:64], data_in_reg[127:96]};
    endcase
end

assign QSPI_nCS = ((QSPI_enable_sync==1'b1) ||(current_state!=IDLE) || (QSPI_SCLK_e==1'b1))?1'b0:1'b1;
//assign QSPI_SCLK_e = (current_state!=IDLE)?1'b1:1'b0;w

assign QSPI_IO_e[3] = (qspi_qio_mode_latched==1'b1)?QSPI_IO_e_int:1'b1;
assign QSPI_IO_e[2] = (qspi_qio_mode_latched==1'b1)?QSPI_IO_e_int:1'b1;
assign QSPI_IO_e[1] = (qspi_qio_mode_latched==1'b1)?QSPI_IO_e_int:1'b0;
assign QSPI_IO_e[0] = (qspi_qio_mode_latched==1'b1)?QSPI_IO_e_int:1'b1;
endmodule
