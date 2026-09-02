`timescale 1ns / 1ps

`include "axi4_define.svh"
`include "mmap_define.svh"

module onchip_ram64_tb #(
    parameter int unsigned CapacityKiB = 32
);
  localparam logic [31:0] SramBase = `SOC_ADDR_SRAM_BASE;

  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (6),
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
      .Present    (1'b1),
      .CapacityKiB(CapacityKiB),
      .DataWidth  (64),
      .IdWidth    (6)
  ) u_dut (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .perf_enable_i(1'b1),
      .perf_clear_i (1'b0),
      .mem_axi4     (mem_axi4),
      .cfg_apb4     (cfg_apb4)
  );

  task automatic issue_write(input logic [5:0] id, input logic [31:0] address,
                             input logic [7:0] length, input logic [2:0] size,
                             input logic [63:0] seed, input logic [7:0] strobe);
    begin
      @(negedge clk_i);
      mem_axi4.awid    = id;
      mem_axi4.awaddr  = address;
      mem_axi4.awlen   = length;
      mem_axi4.awsize  = size;
      mem_axi4.awvalid = 1'b1;
      do @(posedge clk_i); while (!mem_axi4.awready);
      @(negedge clk_i);
      mem_axi4.awvalid = 1'b0;
      for (int beat = 0; beat <= int'(length); beat++) begin
        mem_axi4.wdata  = seed + beat;
        mem_axi4.wstrb  = strobe;
        mem_axi4.wlast  = beat == int'(length);
        mem_axi4.wvalid = 1'b1;
        do @(posedge clk_i); while (!mem_axi4.wready);
        @(negedge clk_i);
      end
      mem_axi4.wvalid = 1'b0;
      mem_axi4.wlast  = 1'b0;
      mem_axi4.bready = 1'b1;
      do @(posedge clk_i); while (!mem_axi4.bvalid);
      if ((mem_axi4.bid != id) || (mem_axi4.bresp != `AXI4_RESP_OKAY)) begin
        $fatal(1, "AXI64 SRAM write response mismatch");
      end
      @(negedge clk_i);
      mem_axi4.bready = 1'b0;
    end
  endtask

  task automatic expect_read(input logic [5:0] id, input logic [31:0] address,
                             input logic [7:0] length, input logic [63:0] seed);
    integer previous_cycle;
    integer cycle_count;
    begin
      @(negedge clk_i);
      mem_axi4.arid    = id;
      mem_axi4.araddr  = address;
      mem_axi4.arlen   = length;
      mem_axi4.arsize  = 3'd3;
      mem_axi4.arvalid = 1'b1;
      do @(posedge clk_i); while (!mem_axi4.arready);
      @(negedge clk_i);
      mem_axi4.arvalid = 1'b0;
      mem_axi4.rready  = 1'b1;
      previous_cycle   = -1;
      cycle_count      = 0;
      for (int beat = 0; beat <= int'(length); beat++) begin
        do begin
          @(posedge clk_i);
          cycle_count = cycle_count + 1;
        end while (!mem_axi4.rvalid);
        if ((mem_axi4.rid != id) || (mem_axi4.rresp != `AXI4_RESP_OKAY) ||
            (mem_axi4.rlast != (beat == int'(length))) ||
            (mem_axi4.rdata != (seed + beat))) begin
          $fatal(1, "AXI64 SRAM read response mismatch at beat %0d", beat);
        end
        if ((previous_cycle >= 0) && (cycle_count != previous_cycle + 1)) begin
          $fatal(1, "AXI64 SRAM read burst inserted a bubble at beat %0d", beat);
        end
        previous_cycle = cycle_count;
      end
      @(negedge clk_i);
      mem_axi4.rready = 1'b0;
    end
  endtask

  initial begin
    mem_axi4.awid     = '0;
    mem_axi4.awaddr   = '0;
    mem_axi4.awlen    = '0;
    mem_axi4.awsize   = 3'd3;
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
    mem_axi4.arsize   = 3'd3;
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

    repeat (3) @(posedge clk_i);
    rst_n_i = 1'b1;

    issue_write(6'h2A, SramBase + 32'h100, 8'd3, 3'd3, 64'h1000_2000_3000_4000, 8'hFF);
    expect_read(6'h2B, SramBase + 32'h100, 8'd3, 64'h1000_2000_3000_4000);
    issue_write(6'h2C, SramBase + 32'h10C, 8'd0, 3'd2, 64'hDEAD_BEEF_0000_0000, 8'hF0);
    expect_read(6'h2D, SramBase + 32'h108, 8'd0, 64'hDEAD_BEEF_3000_4001);

    $display("native AXI64 on-chip SRAM test passed");
    $finish;
  end

  initial begin
    repeat (400) @(posedge clk_i);
    $fatal(1, "native AXI64 on-chip SRAM test timed out");
  end
endmodule
