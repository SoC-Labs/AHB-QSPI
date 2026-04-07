`timescale 1ns/10ps

module ahb_qspi_cocotb(
    input  wire                 HCLK,
    input  wire                 HRESETn,

    // AHB Signals
    input  wire [32-1:0]    config_HADDR,
    input  wire [1:0]       config_HTRANS,
    input  wire             config_HWRITE,
    input  wire [2:0]       config_HSIZE,
    input  wire [2:0]       config_HBURST,
    input  wire [32-1:0]    config_HWDATA,
    input  wire             config_HSEL,
    output wire [32-1:0]    config_HRDATA,
    input  wire             config_HREADY_IN,
    output wire             config_HREADY,
    output wire             config_HRESP,

    input  wire [32-1:0]    data_HADDR,
    input  wire [1:0]       data_HTRANS,
    input  wire             data_HWRITE,
    input  wire [2:0]       data_HSIZE,
    input  wire [2:0]       data_HBURST,
    input  wire [32-1:0]    data_HWDATA,
    input  wire             data_HSEL,
    output wire [32-1:0]    data_HRDATA,
    input  wire             data_HREADY_IN,
    output wire             data_HREADY,
    output wire             data_HRESP
);

initial
begin
   $dumpfile("ahb_qspi.vcd");
   $dumpvars;
end
wire [3:0]       config_HPROT;
wire [3:0]       data_HPROT;
assign config_HPROT = 4'b0010;
assign data_HPROT = 4'b1000;
wire [15:0]          PADDR;
wire [2:0]           PPROT;
wire                 PSEL;
wire                 PENABLE;
wire                 PWRITE;
wire [31:0]          PWDATA;
wire [3:0]           PSTRB;
wire [31:0]          PRDATA;
wire                 PREADY;
wire                 PSLVERR;

wire                IRQ_QSPI_FINISHED;

cmsdk_ahb_to_apb #(
    .ADDRWIDTH(16),
    .REGISTER_RDATA(1),
    .REGISTER_WDATA(0)
) u_cmsdk_ahb_to_apb (
    .HCLK(HCLK),
    .HRESETn(HRESETn),
    .PCLKEN(1'b1),

    .HSEL(config_HSEL),
    .HADDR(config_HADDR[15:0]),
    .HTRANS(config_HTRANS),
    .HSIZE(config_HSIZE),
    .HPROT(config_HPROT),
    .HWRITE(config_HWRITE),
    .HREADY(config_HREADY_IN),
    .HWDATA(config_HWDATA),

    .HREADYOUT(config_HREADY),
    .HRDATA(config_HRDATA),
    .HRESP(config_HRESP),

    .PADDR(PADDR),
    .PENABLE(PENABLE),
    .PWRITE(PWRITE),
    .PSTRB(PSTRB),
    .PPROT(PPROT),
    .PWDATA(PWDATA),
    .PSEL(PSEL),
    .APBACTIVE(),
    .PRDATA(PRDATA),
    .PREADY(PREADY),
    .PSLVERR(PSLVERR)
);


wire QSPI_SCLK;
wire QSPI_nCS;
wire [3:0] QSPI_IO;

ahb_qspi_pads u_ahb_qspi_pads(
    .HCLK(HCLK),
    .HRESETn(HRESETn),
    .PCLK(HCLK),
    .PRESETn(HRESETn),

    .HADDR(data_HADDR),
    .HTRANS(data_HTRANS),
    .HWRITE(data_HWRITE),
    .HSIZE(data_HSIZE),
    .HBURST(data_HBURST),
    .HPROT(data_HPROT),
    .HWDATA(data_HWDATA),
    .HSELx(data_HSEL),
    .HRDATA(data_HRDATA),
    .HREADY(data_HREADY),
    .HREADYOUT(data_HREADY),
    .HRESP(data_HRESP),

    .PADDR(PADDR),
    .PPROT(PPROT),
    .PSEL(PSEL),
    .PENABLE(PENABLE),
    .PWRITE(PWRITE),
    .PWDATA(PWDATA),
    .PSTRB(PSTRB),
    .PRDATA(PRDATA),
    .PREADY(PREADY),
    .PSLVERR(PSLVERR),

    .QSPI_SCLK(QSPI_SCLK),
    .QSPI_nCS(QSPI_nCS),
    .QSPI_IO(QSPI_IO),

    .IRQ_QSPI_FINISHED(IRQ_QSPI_FINISHED)

);

`ifdef GATE_SIMS
initial begin
    $sdf_annotate("../../imp/ASIC/top_ahb_qspi.sdf", u_ahb_qspi_pads);
end
`endif


sst26vf064b u_sst26vf064b(
    .SCK(QSPI_SCLK),
    .SIO(QSPI_IO),
    .CEb(QSPI_nCS)
);
defparam u_sst26vf064b.I0.Tbe = 1_000;
defparam u_sst26vf064b.I0.Tse = 1_000;
defparam u_sst26vf064b.I0.Tsce = 1_000;
defparam u_sst26vf064b.I0.Tpp = 1_000;
defparam u_sst26vf064b.I0.Tws = 1000;

endmodule
