
module qspi_controller (
    input  wire         HCLK,
    input  wire         HRESETn,

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

// 2-FF CDC synchronizer for QSPI_ENABLE (HCLK/PCLK -> QSPI_SCLK_i domain)
reg QSPI_enable_sync_meta;
reg QSPI_enable_sync;

always @(posedge QSPI_SCLK_i or negedge HRESETn) begin
    if(~HRESETn) begin
        QSPI_enable_sync_meta <= 1'b0;
        QSPI_enable_sync      <= 1'b0;
    end else begin
        QSPI_enable_sync_meta <= QSPI_ENABLE;
        QSPI_enable_sync      <= QSPI_enable_sync_meta;
    end
end

reg [127:0]   QSPI_WDATA_reg;

assign QSPI_IO_o = QSPI_IO_o_reg;

always @(posedge QSPI_SCLK_i or negedge HRESETn) begin
    if(~HRESETn) begin
        current_state <= IDLE;
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
            if(QSPI_enable_sync==1'b1 && QSPI_NO_CMD==1'b0) begin
                next_state = OP;
            end else if(QSPI_enable_sync==1'b1 && QSPI_NO_CMD==1'b1) begin
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
            if(QSPI_QIO_MODE==1'b1 & op_counter==3'h1) begin
                QSPI_ENABLE_ACK = 1'b0;
                if(QSPI_ADDR_EN)
                    next_state = ADDR;
                else if(QSPI_DUMMY_CYCLES!=4'h0)
                    next_state = DUMMY;
                else if(QSPI_READ)
                    next_state = DATA_I;
                else if(QSPI_WRITE)
                    next_state = DATA_O;
                else
                    next_state = IDLE;
            end
            // Next state decision from OP if in SPI mode
            else if(QSPI_QIO_MODE==1'b0 & op_counter==3'h7) begin
                QSPI_ENABLE_ACK = 1'b0;
                if(QSPI_ADDR_EN)
                    next_state = ADDR;
                else if(QSPI_DUMMY_CYCLES!=4'h0)
                    next_state = DUMMY;
                else if(QSPI_READ)
                    next_state = DATA_I;
                else if(QSPI_WRITE)
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
            if(QSPI_QIO_MODE==1'b1 & addr_counter==5'h05) begin
                QSPI_ENABLE_ACK = 1'b0;
                if(QSPI_CONT_READ)
                    next_state = MODE;
                else if(QSPI_DUMMY_CYCLES!=4'h0)
                    next_state = DUMMY;
                else if(QSPI_READ)
                    next_state = DATA_I;
                else if(QSPI_WRITE)
                    next_state = DATA_O;
                else
                    next_state = IDLE;
            end
            // Next state decision from ADDR if in SPI mode
            else if(QSPI_QIO_MODE==1'b0 & addr_counter==5'h17) begin
                QSPI_ENABLE_ACK = 1'b0;
                if(QSPI_DUMMY_CYCLES!=4'h0)
                    next_state = DUMMY;
                else if(QSPI_READ)
                    next_state = DATA_I;
                else if(QSPI_WRITE)
                    next_state = DATA_O;
                else
                    next_state = IDLE;
            end else begin
                next_state = ADDR;
            end
        end
        MODE: begin
            // Next state decision from MODE if in QPI mode
            if(QSPI_QIO_MODE==1'b1 & mode_counter == 1'b0) begin
                if(QSPI_DUMMY_CYCLES!=4'h0)
                    next_state = DUMMY;
                else if(QSPI_READ)
                    next_state = DATA_I;
                else if(QSPI_WRITE)
                    next_state = DATA_O;
                else
                    next_state = IDLE;
            end
            // Next state decision from MODE if in SPI mode
            else if(QSPI_QIO_MODE==1'b0) begin
                next_state = IDLE;
            end else begin 
                next_state = MODE;
            end
        end
        DUMMY: begin
            // Next state decision from DUMMY
            if(dummy_counter >= (QSPI_DUMMY_CYCLES - 1)) begin
                if(QSPI_WRITE)
                    next_state = DATA_O;
                else if(QSPI_READ)
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
                if(QSPI_QIO_MODE==1'b0) begin
                    if(byte_counter==QSPI_N_RW_BYTES) begin
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
                    if(byte_counter==QSPI_N_RW_BYTES) begin
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
            if(QSPI_QIO_MODE==1'b0) begin
                if((byte_counter[3:0]==QSPI_N_RW_BYTES)) begin
                    if(data_counter==3'h6)
                        next_state = IDLE;
                    else
                        next_state = DATA_I;
                end
            end 
            // Next state decision from DATA_I if in SPI mode
            else begin
                if((byte_counter==QSPI_N_RW_BYTES)) begin
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
// SpyGlass CDC synthesis (SYNTH_133). QSPI_WDATA_reg load is merged into
// every branch except DATA_O (where it is shifted instead).
always @(negedge QSPI_SCLK_i or negedge HRESETn) begin
    if(~HRESETn) begin
        QSPI_SCLK_e <= 1'b0;
        QSPI_IO_o_reg <= 4'hF;
        QSPI_IO_e_int <= 1'b1;
        op_code <= 8'h00;
        addr_code <= 24'h000000;
        qspi_mode_reg <= 8'h00;
        QSPI_WDATA_reg <= 128'd0;
    end else if(current_state==OP) begin
        QSPI_IO_e_int <= 1'b1;
        QSPI_SCLK_e <= 1'b1;
        QSPI_WDATA_reg <= QSPI_WDATA;
        if(QSPI_QIO_MODE==1'b1) begin
            QSPI_IO_o_reg[3:0]<=op_code[7:4];
            op_code[7:0] <= {op_code[3:0],4'h0};
        end else begin
            QSPI_IO_o_reg[3:0]<={3'h7, op_code[7]};
            op_code[7:0] <= {op_code[6:0], 1'b0};
        end
    end else if(current_state == DATA_I) begin
        QSPI_IO_e_int <= 1'b0;
        QSPI_SCLK_e <= 1'b1;
        QSPI_WDATA_reg <= QSPI_WDATA;
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
        if(QSPI_QIO_MODE==1'b1) begin
            QSPI_IO_o_reg <= QSPI_WDATA_reg[3:0];
            QSPI_WDATA_reg <= {4'h0, QSPI_WDATA_reg[127:4]};
        end else if(byte_counter != 5'h1F) begin
            QSPI_IO_o_reg[0] <= QSPI_WDATA_reg[0];
            QSPI_WDATA_reg <= {1'b0, QSPI_WDATA_reg[127:1]};
        end else begin
            QSPI_SCLK_e <= 1'b0;  // suppress the spurious SPI-mode clock
        end
    end else if(current_state == ADDR) begin
        QSPI_IO_e_int <= 1'b1;
        QSPI_SCLK_e <= 1'b1;
        QSPI_WDATA_reg <= QSPI_WDATA;
        if(QSPI_QIO_MODE==1'b1) begin
            QSPI_IO_o_reg[3:0]<=addr_code[23:20];
            addr_code[23:0] <= {addr_code[19:0],4'h0};
        end else begin
            QSPI_IO_o_reg[3:0]<={3'h7, addr_code[23]};
            addr_code[23:0] <= {addr_code[22:0], 1'b0};
        end
    end else if(current_state == DUMMY) begin
        QSPI_IO_e_int <= 1'b0;
        QSPI_SCLK_e <= 1'b1;
        QSPI_WDATA_reg <= QSPI_WDATA;
    end else if(current_state == MODE) begin
        QSPI_IO_e_int <=1'b1;
        QSPI_SCLK_e <= 1'b1;
        QSPI_WDATA_reg <= QSPI_WDATA;
        if(QSPI_QIO_MODE==1'b1) begin
            QSPI_IO_o_reg <= qspi_mode_reg[7:4];
            qspi_mode_reg <= {qspi_mode_reg[3:0], 4'b0};
        end
    end else begin
        op_code <= QSPI_CMD;
        addr_code <= {2'b00,QSPI_ADDR};
        qspi_mode_reg <= QSPI_MODE_CODE;
        QSPI_WDATA_reg <= QSPI_WDATA;
        QSPI_SCLK_e<=1'b0;
        QSPI_IO_o_reg<=4'hF;
        QSPI_IO_e_int <= 1'b1;
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
    end else begin
        if(current_state==OP) begin
            data_in_reg <= 128'd0;
            op_counter<=op_counter+1;
        end else begin
            op_counter <= 3'h0;
        end

        if(current_state==DATA_I || current_state ==DATA_O) begin
            data_counter <= data_counter + 1;
            if(QSPI_QIO_MODE==1'b0 && data_counter == 3'h7) begin
                byte_counter <= byte_counter+1;
                data_counter <= 3'h0;
            end else if (QSPI_QIO_MODE==1'b1 && data_counter >= 3'h1) begin
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
            if(QSPI_QIO_MODE==1'b1) begin
                if(byte_counter!=QSPI_N_RW_BYTES+1)
                    data_in_reg <= {data_in_reg[123:0], QSPI_IO_i};
            end else begin
                if(byte_counter!=QSPI_N_RW_BYTES+1)
                    data_in_reg <= {data_in_reg[126:0], QSPI_IO_i[1]};
            end
        end

    end
end

// RDATA output — purely combinational, no latch
always_comb begin
    case(QSPI_N_RW_BYTES)
        4'h0:   QSPI_RDATA = {{120{1'b0}}, data_in_reg[7:0 ]};
        4'h1:   QSPI_RDATA = {{112{1'b0}}, data_in_reg[15:0]};
        4'h2:   QSPI_RDATA = {{104{1'b0}}, data_in_reg[23:0]};
        4'h3:   QSPI_RDATA = {{96{1'b0}},  data_in_reg[31:0]};
        4'h4:   QSPI_RDATA = {{88{1'b0}},  data_in_reg[31:0], data_in_reg[39:32]};
        4'h5:   QSPI_RDATA = {{80{1'b0}},  data_in_reg[31:0], data_in_reg[47:32]};
        4'h6:   QSPI_RDATA = {{72{1'b0}},  data_in_reg[31:0], data_in_reg[55:32]};
        4'h7:   QSPI_RDATA = {{64{1'b0}},  data_in_reg[31:0], data_in_reg[63:32]};
        4'h8:   QSPI_RDATA = {{56{1'b0}},  data_in_reg[31:0], data_in_reg[63:32], data_in_reg[71:64]};
        4'h9:   QSPI_RDATA = {{48{1'b0}},  data_in_reg[31:0], data_in_reg[63:32], data_in_reg[79:64]};
        4'hA:   QSPI_RDATA = {{40{1'b0}},  data_in_reg[31:0], data_in_reg[63:32], data_in_reg[87:64]};
        4'hB:   QSPI_RDATA = {{32{1'b0}},  data_in_reg[31:0], data_in_reg[63:32], data_in_reg[95:64]};
        4'hC:   QSPI_RDATA = {{24{1'b0}},  data_in_reg[31:0], data_in_reg[63:32], data_in_reg[95:64], data_in_reg[103:96]};
        4'hD:   QSPI_RDATA = {{16{1'b0}},  data_in_reg[31:0], data_in_reg[63:32], data_in_reg[95:64], data_in_reg[111:96]};
        4'hE:   QSPI_RDATA = {{8{1'b0}},   data_in_reg[31:0], data_in_reg[63:32], data_in_reg[95:64], data_in_reg[119:96]};
        4'hF:   QSPI_RDATA = {data_in_reg[31:0], data_in_reg[63:32], data_in_reg[95:64], data_in_reg[127:96]};
        default: QSPI_RDATA = 128'd0;
    endcase
end

assign QSPI_nCS = ((QSPI_enable_sync==1'b1) ||(current_state!=IDLE) || (QSPI_SCLK_e==1'b1))?1'b0:1'b1;
//assign QSPI_SCLK_e = (current_state!=IDLE)?1'b1:1'b0;w

assign QSPI_IO_e[3] = (QSPI_QIO_MODE==1'b1)?QSPI_IO_e_int:1'b1;
assign QSPI_IO_e[2] = (QSPI_QIO_MODE==1'b1)?QSPI_IO_e_int:1'b1;
assign QSPI_IO_e[1] = (QSPI_QIO_MODE==1'b1)?QSPI_IO_e_int:1'b0;
assign QSPI_IO_e[0] = (QSPI_QIO_MODE==1'b1)?QSPI_IO_e_int:1'b1;
endmodule
