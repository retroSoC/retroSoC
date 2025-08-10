`include "mmap_define.svh"

module core_wrapper (
    (* keep *) input  logic        clk_i,
    (* keep *) input  logic        rst_n_i,
`ifdef CORE_MDD
    (* keep *) input  logic [ 4:0] core_mdd_sel_i,
`endif
    (* keep *) output logic        core_valid_o,
    (* keep *) output logic [31:0] core_addr_o,
    (* keep *) output logic [31:0] core_wdata_o,
    (* keep *) output logic [ 3:0] core_wstrb_o,
    (* keep *) input  logic [31:0] core_rdata_i,
    (* keep *) input  logic        core_ready_i,
    (* keep *) input  logic [31:0] irq_i
);

`ifdef CORE_PICORV32
  picorv32 #(
      .BARREL_SHIFTER (1),
      .COMPRESSED_ISA (1),
      .ENABLE_MUL     (1),
      .ENABLE_FAST_MUL(1),
      .ENABLE_DIV     (1),
      .ENABLE_IRQ     (0),
      .PROGADDR_RESET (`FLASH_START_ADDR)
  ) u_picorv32 (
      .clk      (clk_i),
      .resetn   (rst_n_i),
      .mem_valid(core_valid_o),
      .mem_instr(),
      .mem_addr (core_addr_o),
      .mem_wdata(core_wdata_o),
      .mem_wstrb(core_wstrb_o),
      .mem_rdata(core_rdata_i),
      .mem_ready(core_ready_i),
      .irq      (irq_i),
      .trap     ()
  );
`elsif CORE_KIANV
  kianv_harris_mc_edition #(
      .RESET_ADDR(`FLASH_START_ADDR),
      .RV32E     (0)
  ) u_kianv_harris_mc_edition (
      .clk      (clk_i),
      .resetn   (rst_n_i),
      .mem_valid(core_valid_o),
      .mem_ready(core_ready_i),
      .mem_wstrb(core_wstrb_o),
      .mem_addr (core_addr_o),
      .mem_wdata(core_wdata_o),
      .mem_rdata(core_rdata_i)
  );

`elsif CORE_MINIRV
  logic [31:0] s_awaddr;
  logic        s_awvalid;
  logic        s_awready;
  logic [31:0] s_wdata;
  logic [ 3:0] s_wstrb;
  logic        s_wvalid;
  logic        s_wready;
  logic [ 1:0] s_bresp;
  logic        s_bvalid;
  logic        s_bready;
  logic [31:0] s_araddr;
  logic        s_arvalid;
  logic        s_arready;
  logic [31:0] s_rdata;
  logic [ 1:0] s_rresp;
  logic        s_rvalid;
  logic        s_rready;

  logic [31:0] s_remap_awaddr;
  logic [31:0] s_remap_araddr;

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
      .AWADDR   (s_remap_awaddr),
      .AWVALID  (s_awvalid),
      .AWREADY  (s_awready),
      .WDATA    (s_wdata),
      .WSTRB    (s_wstrb),
      .WVALID   (s_wvalid),
      .WREADY   (s_wready),
      .BRESP    (s_bresp),
      .BVALID   (s_bvalid),
      .BREADY   (s_bready),
      .ARADDR   (s_remap_araddr),
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

  always_comb begin
    s_remap_awaddr = s_awaddr;
    if (s_awaddr[31:24] == 8'h30) begin
      s_remap_awaddr = {8'h00, s_awaddr[23:0]};
    end
  end

  always_comb begin
    s_remap_araddr = s_araddr;
    if (s_araddr[31:24] == 8'h30) begin
      s_remap_araddr = {8'h00, s_araddr[23:0]};
    end
  end
`elsif CORE_MDD
  core_mdd_wrapper u_core_mdd_wrapper (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .sel_i       (core_mdd_sel_i),
      .core_valid_o(core_valid_o),
      .core_addr_o (core_addr_o),
      .core_wdata_o(core_wdata_o),
      .core_wstrb_o(core_wstrb_o),
      .core_rdata_i(core_rdata_i),
      .core_ready_i(core_ready_i),
      .irq_i       (irq_i)
  );

`endif

endmodule
