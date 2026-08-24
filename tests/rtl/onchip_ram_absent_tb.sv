`timescale 1ns / 1ps

`include "axi4_define.svh"
`include "onchip_ram_define.svh"

module onchip_ram_absent_tb;
  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) mem_axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  apb4_if cfg_apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );

  always #5 clk_i = ~clk_i;

  onchip_ram #(
      .Present    (1'b0),
      .CapacityKiB(128)
  ) u_dut (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .perf_enable_i(1'b1),
      .perf_clear_i (1'b0),
      .mem_axi4     (mem_axi4),
      .cfg_apb4     (cfg_apb4)
  );

  task automatic init_interfaces;
    begin
      mem_axi4.awid     = '0;
      mem_axi4.awaddr   = '0;
      mem_axi4.awlen    = '0;
      mem_axi4.awsize   = `AXI4_BURST_SIZE_4BYTES;
      mem_axi4.awburst  = `AXI4_BURST_TYPE_INCR;
      mem_axi4.awlock   = `AXI4_LOCK_NORM;
      mem_axi4.awcache  = `AXI4_CACHE_NO_BUF;
      mem_axi4.awprot   = `AXI4_PROT_DATA;
      mem_axi4.awqos    = `AXI4_QOS_NORMAL;
      mem_axi4.awregion = `AXI4_REGION_NORMAL;
      mem_axi4.awuser   = '0;
      mem_axi4.awvalid  = 1'b0;
      mem_axi4.wdata    = '0;
      mem_axi4.wstrb    = '0;
      mem_axi4.wlast    = 1'b0;
      mem_axi4.wuser    = '0;
      mem_axi4.wvalid   = 1'b0;
      mem_axi4.bready   = 1'b0;
      mem_axi4.arid     = '0;
      mem_axi4.araddr   = '0;
      mem_axi4.arlen    = '0;
      mem_axi4.arsize   = `AXI4_BURST_SIZE_4BYTES;
      mem_axi4.arburst  = `AXI4_BURST_TYPE_INCR;
      mem_axi4.arlock   = `AXI4_LOCK_NORM;
      mem_axi4.arcache  = `AXI4_CACHE_NO_BUF;
      mem_axi4.arprot   = `AXI4_PROT_DATA;
      mem_axi4.arqos    = `AXI4_QOS_NORMAL;
      mem_axi4.arregion = `AXI4_REGION_NORMAL;
      mem_axi4.aruser   = '0;
      mem_axi4.arvalid  = 1'b0;
      mem_axi4.rready   = 1'b0;
      cfg_apb4.paddr    = '0;
      cfg_apb4.pprot    = '0;
      cfg_apb4.psel     = 1'b0;
      cfg_apb4.penable  = 1'b0;
      cfg_apb4.pwrite   = 1'b0;
      cfg_apb4.pwdata   = '0;
      cfg_apb4.pstrb    = '0;
    end
  endtask

  task automatic apb_read(input logic [11:0] offset, input logic [31:0] expected);
    begin
      @(negedge clk_i);
      cfg_apb4.paddr   = {20'd0, offset};
      cfg_apb4.psel    = 1'b1;
      cfg_apb4.penable = 1'b0;
      @(negedge clk_i);
      cfg_apb4.penable = 1'b1;
      do @(posedge clk_i); while (!cfg_apb4.pready);
      if (cfg_apb4.pslverr || (cfg_apb4.prdata !== expected)) begin
        $fatal(1, "absent SRAM APB read mismatch offset=%03x", offset);
      end
      @(negedge clk_i);
      cfg_apb4.psel    = 1'b0;
      cfg_apb4.penable = 1'b0;
    end
  endtask

  initial begin
    init_interfaces();
    repeat (3) @(posedge clk_i);
    @(negedge clk_i);
    rst_n_i = 1'b1;

    apb_read(`APB4_ONCHIP_RAM__CAPABILITY, 32'h0004_107E);
    apb_read(`APB4_ONCHIP_RAM__MEMORY_BYTES, 32'd0);
    apb_read(`APB4_ONCHIP_RAM__BANK_COUNT, 32'd0);

    @(negedge clk_i);
    mem_axi4.araddr  = `SOC_ADDR_SRAM_BASE;
    mem_axi4.arvalid = 1'b1;
    do @(posedge clk_i); while (!mem_axi4.arready);
    @(negedge clk_i);
    mem_axi4.arvalid = 1'b0;
    mem_axi4.rready  = 1'b1;
    do @(posedge clk_i); while (!mem_axi4.rvalid);
    if ((mem_axi4.rresp != `AXI4_RESP_DECODE_ERROR) || !mem_axi4.rlast) begin
      $fatal(1, "absent SRAM read did not return DECERR");
    end
    @(negedge clk_i);
    mem_axi4.rready = 1'b0;

    @(negedge clk_i);
    mem_axi4.awaddr  = `SOC_ADDR_SRAM_BASE;
    mem_axi4.awvalid = 1'b1;
    do @(posedge clk_i); while (!mem_axi4.awready);
    @(negedge clk_i);
    mem_axi4.awvalid = 1'b0;
    mem_axi4.wdata   = 32'hDEAD_BEEF;
    mem_axi4.wstrb   = 4'hF;
    mem_axi4.wlast   = 1'b1;
    mem_axi4.wvalid  = 1'b1;
    do @(posedge clk_i); while (!mem_axi4.wready);
    @(negedge clk_i);
    mem_axi4.wvalid = 1'b0;
    mem_axi4.wlast  = 1'b0;
    mem_axi4.bready = 1'b1;
    do @(posedge clk_i); while (!mem_axi4.bvalid);
    if (mem_axi4.bresp != `AXI4_RESP_DECODE_ERROR) begin
      $fatal(1, "absent SRAM write did not return DECERR");
    end

    $display("absent on-chip SRAM test passed");
    $finish;
  end
endmodule
