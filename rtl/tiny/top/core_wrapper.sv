`include "mmap_define.svh"

module core_wrapper (
    (* keep *) input  logic        clk_i,
    (* keep *) input  logic        rst_n_i,
    (* keep *) output logic        core_valid_o,
    (* keep *) output logic [31:0] core_addr_o,
    (* keep *) output logic [31:0] core_wdata_o,
    (* keep *) output logic [ 3:0] core_wstrb_o,
    (* keep *) input  logic [31:0] core_rdata_i,
    (* keep *) input  logic        core_ready_i,
    (* keep *) input  logic [31:0] irq_i
);

`ifdef CORE_MINIRV
  wire [31:0] s_awaddr;
  wire        s_awvalid;
  wire        s_awready;
  wire [31:0] s_wdata;
  wire [ 3:0] s_wstrb;
  wire        s_wvalid;
  wire        s_wready;
  wire [ 1:0] s_bresp;
  wire        s_bvalid;
  wire        s_bready;
  wire [31:0] s_araddr;
  wire        s_arvalid;
  wire        s_arready;
  wire [31:0] s_rdata;
  wire [ 1:0] s_rresp;
  wire        s_rvalid;
  wire        s_rready;

  minirv u_minirv (
      .clock            (clk_i),
      .reset            (~rst_n_i),
      .io_master_awready(s_awready),
      .io_master_awvalid(s_awvalid),
      .io_master_awaddr (s_awaddr),
      .io_master_awsize (),
      .io_master_awid   (),
      .io_master_awlen  (),
      .io_master_awburst(),
      .io_master_wready (s_wready),
      .io_master_wvalid (s_wvalid),
      .io_master_wdata  (s_wdata),
      .io_master_wstrb  (s_wstrb),
      .io_master_wlast  (),
      .io_master_bready (s_bready),
      .io_master_bvalid (s_bvalid),
      .io_master_bresp  (s_bresp),
      .io_master_bid    (),
      .io_master_arready(s_arready),
      .io_master_arvalid(s_arvalid),
      .io_master_araddr (s_araddr),
      .io_master_arsize (),
      .io_master_arid   (),
      .io_master_arlen  (),
      .io_master_arburst(),
      .io_master_rready (s_rready),
      .io_master_rvalid (s_rvalid),
      .io_master_rresp  (s_rresp),
      .io_master_rdata  (s_rdata),
      .io_master_rlast  (),
      .io_master_rid    (),
      .io_interrupt     (|irq_i)
  );


  axi4l2mem u_axi4l2mem (
      .ACLK     (clk_i),
      .ARESETn  (rst_n_i),
      .AWADDR   (s_awaddr),
      .AWVALID  (s_awvalid),
      .AWREADY  (s_awready),
      .WDATA    (s_wdata),
      .WSTRB    (s_wstrb),
      .WVALID   (s_wvalid),
      .WREADY   (s_wready),
      .BRESP    (s_bresp),
      .BVALID   (s_bvalid),
      .BREADY   (s_bready),
      .ARADDR   (s_araddr),
      .ARVALID  (s_arvalid),
      .ARREADY  (s_arready),
      .RDATA    (s_rdata),
      .RRESP    (s_rresp),
      .RVALID   (s_rvalid),
      .RREADY   (s_rready),
      .mem_valid(core_valid_o),
      .mem_instr(),
      .mem_addr (core_addr_o),
      .mem_wdata(core_wdata_o),
      .mem_wstrb(core_wstrb_o),
      .mem_ready(core_ready_i),
      .mem_rdata(core_rdata_i)
  );
`endif
endmodule
