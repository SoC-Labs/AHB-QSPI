module ahb_qspi_fpga_wrapper (
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 CLK.HCLK CLK" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME CLK.HCLK, ASSOCIATED_RESET HRESETn, CLK_DOMAIN ahb_qspi_ip_HCLK, FREQ_HZ 10000000, FREQ_TOLERANCE_HZ 0, INSERT_VIP 0, PHASE 0.0" *) input HCLK,
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 RST.HRESETN RST" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME RST.HRESETN, INSERT_VIP 0, POLARITY ACTIVE_LOW" *) input HRESETn,
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 CLK.PCLK CLK" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME CLK.PCLK, ASSOCIATED_RESET PRESETn, CLK_DOMAIN ahb_qspi_ip_PCLK, FREQ_HZ 10000000, FREQ_TOLERANCE_HZ 0, INSERT_VIP 0, PHASE 0.0" *) input PCLK,
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 RST.PRESETN RST" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME RST.PRESETN, INSERT_VIP 0, POLARITY ACTIVE_LOW" *) input PRESETn,


  (* X_INTERFACE_INFO = "xilinx.com:interface:ahblite:2.0 S_AHB SEL" *)
  input S_AHB_HSEL, // Slave select (required)               S_AHB
  (* X_INTERFACE_INFO = "xilinx.com:interface:ahblite:2.0 S_AHB HADDR" *)
  input [31:0] S_AHB_HADDR, // Address bus (required)       S_AHB
  (* X_INTERFACE_INFO = "xilinx.com:interface:ahblite:2.0 S_AHB HPROT" *)
  input [3:0] S_AHB_HPROT, // Protection type (required)    S_AHB
  (* X_INTERFACE_INFO = "xilinx.com:interface:ahblite:2.0 S_AHB HTRANS" *)
  input [1:0] S_AHB_HTRANS, // Transfer type (required)     S_AHB
  (* X_INTERFACE_INFO = "xilinx.com:interface:ahblite:2.0 S_AHB HSIZE" *)
  input [2:0] S_AHB_HSIZE, // Transfer size (required)      S_AHB
  (* X_INTERFACE_INFO = "xilinx.com:interface:ahblite:2.0 S_AHB HWRITE" *)
  input S_AHB_HWRITE, // Write / Read transfer (required)   S_AHB
  (* X_INTERFACE_INFO = "xilinx.com:interface:ahblite:2.0 S_AHB HBURST" *)
  input [2:0] S_AHB_HBURST, // Burst type (required)        S_AHB
  (* X_INTERFACE_INFO = "xilinx.com:interface:ahblite:2.0 S_AHB HWDATA" *)
  input [31:0] S_AHB_HWDATA, // Write data (required)       S_AHB
  (* X_INTERFACE_INFO = "xilinx.com:interface:ahblite:2.0 S_AHB HRDATA" *)
  output [31:0] S_AHB_HRDATA, // Read data (required)       S_AHB
  (* X_INTERFACE_INFO = "xilinx.com:interface:ahblite:2.0 S_AHB HRESP" *)
  output S_AHB_HRESP, // Status of the transfer (required)  S_AHB
  (* X_INTERFACE_INFO = "xilinx.com:interface:ahblite:2.0 S_AHB HREADY_IN" *)
  input S_AHB_HREADY_IN, // This signal indicates that the previous transfer is complete. (required)
  (* X_INTERFACE_INFO = "xilinx.com:interface:ahblite:2.0 S_AHB HREADY_OUT" *)
  output S_AHB_HREADY_OUT, // This signal indicates that the transfer is complete. (required)
//  additional ports here
  (* X_INTERFACE_INFO = "xilinx.com:interface:apb:1.0 apb_interface PADDR" *)
  input [31:0] apb_interface_PADDR, // Address (required)       apb
  (* X_INTERFACE_INFO = "xilinx.com:interface:apb:1.0 apb_interface PPROT" *)
  input [2:0] apb_interface_PPROT, // Protection (optional)     apb
  (* X_INTERFACE_INFO = "xilinx.com:interface:apb:1.0 apb_interface PSEL" *)
  input apb_interface_PSEL, // Slave Select (required)          apb
  (* X_INTERFACE_INFO = "xilinx.com:interface:apb:1.0 apb_interface PENABLE" *)
  input apb_interface_PENABLE, // Enable (required)             apb
  (* X_INTERFACE_INFO = "xilinx.com:interface:apb:1.0 apb_interface PWRITE" *)
  input apb_interface_PWRITE, // Write Control (required)       apb
  (* X_INTERFACE_INFO = "xilinx.com:interface:apb:1.0 apb_interface PWDATA" *)
  input [31:0] apb_interface_PWDATA, // Write Data (required)   apb
  (* X_INTERFACE_INFO = "xilinx.com:interface:apb:1.0 apb_interface PSTRB" *)
  input [3:0] apb_interface_PSTRB, // Write data strobe (optionaapb_
  (* X_INTERFACE_INFO = "xilinx.com:interface:apb:1.0 apb_interface PREADY" *)
  output apb_interface_PREADY, // Slave Ready (required)        apb
  (* X_INTERFACE_INFO = "xilinx.com:interface:apb:1.0 apb_interface PRDATA" *)
  output [31:0] apb_interface_PRDATA, // Read Data (required)   apb
  (* X_INTERFACE_INFO = "xilinx.com:interface:apb:1.0 apb_interface PSLVERR" *)
  output apb_interface_PSLVERR, // Slave Error Response (required)
  
  output wire [3:0]  QSPI_IO_o,
  input  wire [3:0]  QSPI_IO_i,
  output wire [3:0]  QSPI_IO_e,

  output wire QSPI_SCLK,
  output wire QSPI_nCS
);


top_ahb_qspi u_top_ahb_qspi(
    .HCLK       (HCLK),   
    .HRESETn    (HRESETn),
    .PCLK       (PCLK),   
    .PRESETn    (PRESETn),

    .HADDR      (S_AHB_HADDR),     
    .HTRANS     (S_AHB_HTRANS),    
    .HWRITE     (S_AHB_HWRITE),    
    .HSIZE      (S_AHB_HSIZE),     
    .HBURST     (S_AHB_HBURST),    
    .HPROT      (S_AHB_HPROT),     
    .HWDATA     (S_AHB_HWDATA),    
    .HSELx      (1'b1),     
    .HRDATA     (S_AHB_HRDATA),    
    .HREADY     (1'b1),    
    .HREADYOUT  (S_AHB_HREADY_OUT), 
    .HRESP      (S_AHB_HRESP),

    .PADDR      (apb_interface_PADDR[15:0]),    
    .PPROT      (apb_interface_PPROT),    
    .PSEL       (apb_interface_PSEL),     
    .PENABLE    (apb_interface_PENABLE),  
    .PWRITE     (apb_interface_PWRITE),   
    .PWDATA     (apb_interface_PWDATA),   
    .PSTRB      (apb_interface_PSTRB),    
    .PRDATA     (apb_interface_PRDATA),   
    .PREADY     (apb_interface_PREADY),   
    .PSLVERR    (apb_interface_PSLVERR),  

    .QSPI_SCLK  (QSPI_SCLK),
    .QSPI_nCS   (QSPI_nCS), 
    .QSPI_IO_o  (QSPI_IO_o),
    .QSPI_IO_i  (QSPI_IO_i),
    .QSPI_IO_e  (QSPI_IO_e) 
);


endmodule