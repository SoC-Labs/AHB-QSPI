
module qspi_controller (
    input  wire         HCLK,
    input  wire         HRESETn,

    input  wire [7:0]   QSPI_CLK_DIV,
    input  wire [1:0]   QSPI_SPI_MODE, // {CPOL, CPHA} 
    
    input  wire [7:0]   QSPI_CMD,
    input  wire         QSPI_ENABLE,
    output reg          QSPI_ENABLE_ACK,
    input  wire         QSPI_READ,
    input  wire         QSPI_WRITE,
    input  wire         QSPI_ADDR_EN,
    input  wire [3:0]   QSPI_DUMMY_CYCLES,
    input  wire [3:0]   QSPI_N_RW_BYTES,
    input  wire [23:0]  QSPI_ADDR,
    input  wire [31:0]  QSPI_WDATA,
    output wire [31:0]  QSPI_RDATA,
    input  wire         QSPI_QIO_MODE,

    // QSPI Interface
    output wire         QSPI_SCLK,
    output wire         QSPI_nCS,
    output wire [3:0]   QSPI_IO_o,
    input  wire [3:0]   QSPI_IO_i,
    output wire [3:0]   QSPI_IO_e
);

reg [7:0] QSPI_CLK_DIV_COUNTER;
reg     QSPI_SCLK_reg;
wire    QSPI_SCLK_i;
reg     QSPI_SCLK_e;

assign QSPI_SCLK_i = (QSPI_CLK_DIV==8'h00) ? HCLK : QSPI_SCLK_reg;
assign QSPI_SCLK = (QSPI_SCLK_e==1'b1) ? QSPI_SCLK_i : QSPI_SPI_MODE[1];

// Clock Divider for SCLK
always @(posedge HCLK or negedge HRESETn) begin
    if(~HRESETn) begin
        QSPI_CLK_DIV_COUNTER<=8'h00;
        QSPI_SCLK_reg <= 1'b0;
    end else begin 
        if(QSPI_CLK_DIV!=8'h00) begin 
            if(QSPI_CLK_DIV_COUNTER==QSPI_CLK_DIV-1'b1) begin 
                QSPI_CLK_DIV_COUNTER <= 8'h00;
            end else begin 
                QSPI_SCLK_reg <= ~QSPI_SCLK_reg;
                QSPI_CLK_DIV_COUNTER <= QSPI_CLK_DIV_COUNTER + 1'b1;
            end
        end else begin 
            QSPI_SCLK_reg <= QSPI_SPI_MODE[1];
        end
    end
end

enum {IDLE, OP, ADDR, DUMMY, DATA_O, DATA_I} current_state, next_state;

reg [2:0] op_counter;
reg [7:0] data_counter;
reg [3:0] dummy_counter;
reg [4:0] byte_counter;
reg [7:0] op_code;
reg [3:0] QSPI_IO_o_reg;
reg [7:0] data_in_reg;
assign QSPI_IO_o = QSPI_IO_o_reg;

always @(posedge QSPI_SCLK_i or negedge HRESETn) begin
    if(~HRESETn) begin 
        current_state <= IDLE;
    end else begin 
        current_state <= next_state;
    end
end 

always @(*) begin 
    case(current_state)
        IDLE: begin
            if(QSPI_ENABLE) begin
                next_state = OP;
            end else begin
                next_state = IDLE;
                QSPI_ENABLE_ACK = 1'b0;
            end 
            //op_counter=3'h0; 
        end
        OP: begin
            QSPI_ENABLE_ACK = 1'b1;
            if(QSPI_QIO_MODE==1'b1 & op_counter==3'h1) begin
                QSPI_ENABLE_ACK = 1'b0;
                if(QSPI_ADDR_EN)
                    next_state = ADDR;
                else if(QSPI_DUMMY_CYCLES>4'h0)
                    next_state = DUMMY;
                else if(QSPI_READ)
                    next_state = DATA_I;
                else if(QSPI_WRITE)
                    next_state = DATA_O;
                else
                    next_state = IDLE;
            end
            else if(QSPI_QIO_MODE==1'b0 & op_counter==3'h7) begin
                QSPI_ENABLE_ACK = 1'b0;
                if(QSPI_ADDR_EN)
                    next_state = ADDR;
                else if(QSPI_DUMMY_CYCLES>4'h0)
                    next_state = DUMMY;
                else if(QSPI_READ)
                    next_state = DATA_I;
                else if(QSPI_WRITE)
                    next_state = DATA_O;
                else
                    next_state = IDLE;
            end
        end     
        ADDR: begin
            
        end 
        DUMMY: begin
            if(dummy_counter >= QSPI_DUMMY_CYCLES - 1'b1) begin
                if(QSPI_WRITE)
                    next_state = DATA_O;
                else if(QSPI_READ)
                    next_state = DATA_I;
                else
                    next_state = IDLE;
            end 
        end 
        DATA_O: begin
            
        end 
        DATA_I: begin 
            if(byte_counter==QSPI_N_RW_BYTES+1'b1) begin
                next_state = IDLE;
            end
        end
    endcase
end

reg QSPI_IO_e_int;

always @(negedge QSPI_SCLK_i) begin
    if(current_state==OP) begin 
        QSPI_IO_e_int <= 1'b1;
        QSPI_SCLK_e <= 1'b1;
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
    end else if(current_state == DUMMY) begin 
        QSPI_IO_e_int <= 1'b1;
        QSPI_SCLK_e <= 1'b1;
    end else begin 
        op_code <= QSPI_CMD;
        QSPI_SCLK_e<=1'b0;
        QSPI_IO_o_reg<=4'hF;
        QSPI_IO_e_int <= 1'b1;
    end
end
always @(posedge QSPI_SCLK_i) begin 
    if(current_state==OP) begin 
        op_counter<=op_counter+1'b1;
    end else begin 
        op_counter <= 3'h0;
    end
    if(current_state==DATA_I || current_state ==DATA_O) begin
        data_counter <= data_counter + 1'b1;
        if(QSPI_QIO_MODE==1'b0 && data_counter == 3'h7) begin 
            byte_counter <= byte_counter+1'b1;
            data_counter <= 3'h0;
        end else if (QSPI_QIO_MODE==1'b1 && data_counter == 3'h1) begin
            byte_counter <= byte_counter+1'b1;
            data_counter <= 3'h0;
        end
    end else begin 
        data_counter <= 3'h0;
        byte_counter <= 4'h0;
    end
    if(current_state == DATA_I) begin
        if(QSPI_QIO_MODE==1'b1) begin 
            data_in_reg <= {data_in_reg[3:0], QSPI_IO_i};
        end else begin 
            data_in_reg <= {data_in_reg[6:0],QSPI_IO_i[1]};
        end
    end

    if(current_state == DUMMY) begin 
        dummy_counter <= dummy_counter + 1'b1;
    end else begin 
        dummy_counter <= 4'h0;
    end

end

assign QSPI_nCS = ((QSPI_ENABLE==1'b1) ||(current_state!=IDLE) || (QSPI_SCLK_e==1'b1))?1'b0:1'b1;
//assign QSPI_SCLK_e = (current_state!=IDLE)?1'b1:1'b0;w

assign QSPI_IO_e[3] = (QSPI_QIO_MODE==1'b1)?QSPI_IO_e_int:1'b1;
assign QSPI_IO_e[2] = (QSPI_QIO_MODE==1'b1)?QSPI_IO_e_int:1'b1;
assign QSPI_IO_e[1] = (QSPI_QIO_MODE==1'b1)?QSPI_IO_e_int:1'b0;
assign QSPI_IO_e[0] = (QSPI_QIO_MODE==1'b1)?QSPI_IO_e_int:1'b1;
endmodule