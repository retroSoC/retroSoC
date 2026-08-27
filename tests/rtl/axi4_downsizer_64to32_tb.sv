`timescale 1ns / 1ps

`include "axi4_define.svh"

module axi4_downsizer_64to32_tb;
  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) wide (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) narrow (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  always #5 clk_i = ~clk_i;

  axi4_downsizer_64to32 u_dut (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .wide   (wide),
      .narrow (narrow)
  );

  task automatic init_bus;
    begin
      wide.awid      = '0;
      wide.awaddr    = '0;
      wide.awlen     = '0;
      wide.awsize    = `AXI4_BURST_SIZE_8BYTES;
      wide.awburst   = `AXI4_BURST_TYPE_INCR;
      wide.awlock    = `AXI4_LOCK_NORM;
      wide.awcache   = `AXI4_CACHE_NO_BUF;
      wide.awprot    = `AXI4_PROT_DATA;
      wide.awqos     = `AXI4_QOS_NORMAL;
      wide.awregion  = `AXI4_REGION_NORMAL;
      wide.awuser    = '0;
      wide.awvalid   = 1'b0;
      wide.wdata     = '0;
      wide.wstrb     = '0;
      wide.wlast     = 1'b0;
      wide.wuser     = '0;
      wide.wvalid    = 1'b0;
      wide.bready    = 1'b0;
      wide.arid      = '0;
      wide.araddr    = '0;
      wide.arlen     = '0;
      wide.arsize    = `AXI4_BURST_SIZE_8BYTES;
      wide.arburst   = `AXI4_BURST_TYPE_INCR;
      wide.arlock    = `AXI4_LOCK_NORM;
      wide.arcache   = `AXI4_CACHE_NO_BUF;
      wide.arprot    = `AXI4_PROT_DATA;
      wide.arqos     = `AXI4_QOS_NORMAL;
      wide.arregion  = `AXI4_REGION_NORMAL;
      wide.aruser    = '0;
      wide.arvalid   = 1'b0;
      wide.rready    = 1'b0;
      narrow.awready = 1'b0;
      narrow.wready  = 1'b0;
      narrow.bid     = '0;
      narrow.bresp   = `AXI4_RESP_OKAY;
      narrow.buser   = '0;
      narrow.bvalid  = 1'b0;
      narrow.arready = 1'b0;
      narrow.rid     = '0;
      narrow.rdata   = '0;
      narrow.rresp   = `AXI4_RESP_OKAY;
      narrow.rlast   = 1'b0;
      narrow.ruser   = '0;
      narrow.rvalid  = 1'b0;
    end
  endtask

  task automatic accept_read(input logic [31:0] address, input logic [7:0] length,
                             input logic [2:0] size, input logic [2:0] id,
                             input logic [7:0] expected_length);
    begin
      @(negedge clk_i);
      wide.araddr  = address;
      wide.arlen   = length;
      wide.arsize  = size;
      wide.arid    = id;
      wide.arvalid = 1'b1;
      #1;
      if (wide.arready) $fatal(1, "read address ignored narrow backpressure");
      narrow.arready = 1'b1;
      #1;
      if (!narrow.arvalid || narrow.araddr != address || narrow.arlen != expected_length ||
          narrow.arsize != ((size == 3'd3) ? 3'd2 : size)) begin
        $fatal(1, "read address conversion mismatch");
      end
      @(posedge clk_i);
      @(negedge clk_i);
      wide.arvalid   = 1'b0;
      narrow.arready = 1'b0;
    end
  endtask

  task automatic accept_write(input logic [31:0] address, input logic [7:0] length,
                              input logic [2:0] size, input logic [2:0] id,
                              input logic [7:0] expected_length);
    begin
      @(negedge clk_i);
      wide.awaddr  = address;
      wide.awlen   = length;
      wide.awsize  = size;
      wide.awid    = id;
      wide.awvalid = 1'b1;
      #1;
      if (wide.awready) $fatal(1, "write address ignored narrow backpressure");
      narrow.awready = 1'b1;
      #1;
      if (!narrow.awvalid || narrow.awaddr != address || narrow.awlen != expected_length ||
          narrow.awsize != ((size == 3'd3) ? 3'd2 : size)) begin
        $fatal(1, "write address conversion mismatch");
      end
      @(posedge clk_i);
      @(negedge clk_i);
      wide.awvalid   = 1'b0;
      narrow.awready = 1'b0;
    end
  endtask

  task automatic return_write_response(input logic [2:0] expected_id, input logic [1:0] response);
    begin
      @(negedge clk_i);
      narrow.bresp  = response;
      narrow.bvalid = 1'b1;
      wide.bready   = 1'b0;
      #1;
      if (!narrow.bready) $fatal(1, "narrow write response was not accepted into buffer");
      @(posedge clk_i);
      @(negedge clk_i);
      narrow.bvalid = 1'b0;
      #1;
      if (!wide.bvalid || wide.bid != expected_id || wide.bresp != response) begin
        $fatal(1, "buffered write response mismatch");
      end
      repeat (2) @(posedge clk_i);
      if (!wide.bvalid || wide.bid != expected_id || wide.bresp != response) begin
        $fatal(1, "write response changed under backpressure");
      end
      @(negedge clk_i);
      wide.bready = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      wide.bready = 1'b0;
    end
  endtask

  initial begin
    init_bus();
    repeat (4) @(posedge clk_i);
    rst_n_i = 1'b1;

    accept_read(32'h0000_0040, 8'd0, 3'd3, 3'd5, 8'd1);
    @(negedge clk_i);
    narrow.rdata  = 32'h1122_3344;
    narrow.rresp  = `AXI4_RESP_SLAVE_ERROR;
    narrow.rlast  = 1'b0;
    narrow.rvalid = 1'b1;
    wide.rready   = 1'b0;
    #1;
    if (!narrow.rready || wide.rvalid) $fatal(1, "lower read beat was not buffered");
    @(posedge clk_i);
    @(negedge clk_i);
    narrow.rdata = 32'h5566_7788;
    narrow.rresp = `AXI4_RESP_OKAY;
    narrow.rlast = 1'b1;
    #1;
    if (!wide.rvalid || narrow.rready || wide.rid != 3'd5 ||
        wide.rdata != 64'h5566_7788_1122_3344 || wide.rresp != `AXI4_RESP_SLAVE_ERROR ||
        !wide.rlast) begin
      $fatal(1, "64-bit read assembly or backpressure mismatch");
    end
    repeat (2) @(posedge clk_i);
    @(negedge clk_i);
    wide.rready = 1'b1;
    @(posedge clk_i);
    @(negedge clk_i);
    wide.rready   = 1'b0;
    narrow.rvalid = 1'b0;

    accept_read(32'h0000_0000, 8'd1, 3'd2, 3'd3, 8'd1);
    @(negedge clk_i);
    narrow.rdata  = 32'hA5A5_0000;
    narrow.rresp  = `AXI4_RESP_OKAY;
    narrow.rlast  = 1'b0;
    narrow.rvalid = 1'b1;
    wide.rready   = 1'b1;
    #1;
    if (wide.rdata != 64'h0000_0000_A5A5_0000 || wide.rid != 3'd3) begin
      $fatal(1, "lower 32-bit read lane mismatch");
    end
    @(posedge clk_i);
    @(negedge clk_i);
    narrow.rdata = 32'hA5A5_0001;
    narrow.rlast = 1'b1;
    #1;
    if (wide.rdata != 64'hA5A5_0001_0000_0000 || !wide.rlast) begin
      $fatal(1, "upper 32-bit read lane mismatch");
    end
    @(posedge clk_i);
    @(negedge clk_i);
    wide.rready   = 1'b0;
    narrow.rvalid = 1'b0;

    accept_write(32'h0000_0080, 8'd0, 3'd3, 3'd6, 8'd1);
    @(negedge clk_i);
    wide.wdata    = 64'h1122_3344_5566_7788;
    wide.wstrb    = 8'hF3;
    wide.wlast    = 1'b1;
    wide.wvalid   = 1'b1;
    narrow.wready = 1'b1;
    #1;
    if (narrow.wdata != 32'h5566_7788 || narrow.wstrb != 4'h3 || narrow.wlast || wide.wready) begin
      $fatal(1, "lower 64-bit write split mismatch");
    end
    @(posedge clk_i);
    @(negedge clk_i);
    #1;
    if (narrow.wdata != 32'h1122_3344 || narrow.wstrb != 4'hF || !narrow.wlast ||
        !wide.wready) begin
      $fatal(1, "upper 64-bit write split mismatch");
    end
    @(posedge clk_i);
    @(negedge clk_i);
    wide.wvalid   = 1'b0;
    narrow.wready = 1'b0;
    return_write_response(3'd6, `AXI4_RESP_DECODE_ERROR);

    accept_write(32'h0000_0004, 8'd1, 3'd2, 3'd2, 8'd1);
    @(negedge clk_i);
    wide.wdata    = 64'hCAFE_0000_DEAD_0000;
    wide.wstrb    = 8'hF0;
    wide.wlast    = 1'b0;
    wide.wvalid   = 1'b1;
    narrow.wready = 1'b1;
    #1;
    if (narrow.wdata != 32'hCAFE_0000 || narrow.wstrb != 4'hF || !wide.wready) begin
      $fatal(1, "upper 32-bit write lane mismatch");
    end
    @(posedge clk_i);
    @(negedge clk_i);
    wide.wdata = 64'hDEAD_0000_CAFE_0001;
    wide.wstrb = 8'h0F;
    wide.wlast = 1'b1;
    #1;
    if (narrow.wdata != 32'hCAFE_0001 || narrow.wstrb != 4'hF || !wide.wready) begin
      $fatal(1, "lower 32-bit write lane mismatch");
    end
    @(posedge clk_i);
    @(negedge clk_i);
    wide.wvalid   = 1'b0;
    narrow.wready = 1'b0;
    return_write_response(3'd2, `AXI4_RESP_OKAY);

    $display("AXI4 64-to-32 downsizer test passed");
    $finish;
  end
endmodule
