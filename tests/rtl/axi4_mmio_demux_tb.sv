`timescale 1ns / 1ps

`include "axi4_define.svh"

module axi4_mmio_demux_tb;
  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) source (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) mem (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) mmio (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  always #5 clk_i = ~clk_i;

  axi4_mmio_demux u_dut (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .clear_i(1'b0),
      .source (source),
      .mem    (mem),
      .mmio   (mmio)
  );

  function automatic logic [63:0] read_data(input logic [2:0] id, input int beat);
    return {32'h5A00_0000 + 32'(id), 32'h0000_0000 + 32'(beat)};
  endfunction

  task automatic init_bus;
    begin
      source.awid     = '0;
      source.awaddr   = '0;
      source.awlen    = '0;
      source.awsize   = `AXI4_BURST_SIZE_8BYTES;
      source.awburst  = `AXI4_BURST_TYPE_INCR;
      source.awlock   = `AXI4_LOCK_NORM;
      source.awcache  = `AXI4_CACHE_NO_BUF;
      source.awprot   = `AXI4_PROT_DATA;
      source.awqos    = `AXI4_QOS_NORMAL;
      source.awregion = `AXI4_REGION_NORMAL;
      source.awuser   = '0;
      source.awvalid  = 1'b0;
      source.wdata    = '0;
      source.wstrb    = '0;
      source.wlast    = 1'b0;
      source.wuser    = '0;
      source.wvalid   = 1'b0;
      source.bready   = 1'b0;
      source.arid     = '0;
      source.araddr   = '0;
      source.arlen    = '0;
      source.arsize   = `AXI4_BURST_SIZE_8BYTES;
      source.arburst  = `AXI4_BURST_TYPE_INCR;
      source.arlock   = `AXI4_LOCK_NORM;
      source.arcache  = `AXI4_CACHE_NO_BUF;
      source.arprot   = `AXI4_PROT_DATA;
      source.arqos    = `AXI4_QOS_NORMAL;
      source.arregion = `AXI4_REGION_NORMAL;
      source.aruser   = '0;
      source.arvalid  = 1'b0;
      source.rready   = 1'b0;
      mem.awready     = 1'b0;
      mem.wready      = 1'b0;
      mem.bid         = '0;
      mem.bresp       = `AXI4_RESP_OKAY;
      mem.buser       = '0;
      mem.bvalid      = 1'b0;
      mem.arready     = 1'b0;
      mem.rid         = '0;
      mem.rdata       = '0;
      mem.rresp       = `AXI4_RESP_OKAY;
      mem.rlast       = 1'b0;
      mem.ruser       = '0;
      mem.rvalid      = 1'b0;
      mmio.awready    = 1'b0;
      mmio.wready     = 1'b0;
      mmio.bid        = '0;
      mmio.bresp      = `AXI4_RESP_OKAY;
      mmio.buser      = '0;
      mmio.bvalid     = 1'b0;
      mmio.arready    = 1'b0;
      mmio.rid        = '0;
      mmio.rdata      = '0;
      mmio.rresp      = `AXI4_RESP_OKAY;
      mmio.rlast      = 1'b0;
      mmio.ruser      = '0;
      mmio.rvalid     = 1'b0;
    end
  endtask

  // Runs one read routed by address window: expect_mmio selects the target.
  // Checks that the address only leaves on the selected port, that a ready on
  // the wrong port cannot complete the source handshake, that wrong-port read
  // data never leaks to the source, and that the selected response is held
  // stable while source.rready is low on beat hold_beat (-1 disables).
  task automatic do_read(input logic [31:0] address, input logic expect_mmio, input logic [2:0] id,
                         input logic [7:0] length, input int hold_beat);
    logic [63:0] expected_data;
    begin
      @(negedge clk_i);
      source.araddr  = address;
      source.arlen   = length;
      source.arsize  = `AXI4_BURST_SIZE_8BYTES;
      source.arburst = `AXI4_BURST_TYPE_INCR;
      source.arid    = id;
      source.arvalid = 1'b1;
      #1;
      if (source.arready) $fatal(1, "read address accepted without target ready");
      if (expect_mmio) begin
        if (!mmio.arvalid || mem.arvalid) $fatal(1, "read address leaked to the wrong port");
      end else begin
        if (!mem.arvalid || mmio.arvalid) $fatal(1, "read address leaked to the wrong port");
      end
      // A ready on the wrong port must not complete the source handshake.
      if (expect_mmio) mem.arready = 1'b1;
      else mmio.arready = 1'b1;
      #1;
      if (source.arready) $fatal(1, "read address used the wrong port ready");
      if (expect_mmio) mmio.arready = 1'b1;
      else mem.arready = 1'b1;
      #1;
      if (!source.arready) $fatal(1, "read address was not forwarded to the selected port");
      if (expect_mmio) begin
        if (mmio.arid != id || mmio.araddr != address || mmio.arlen != length ||
            mmio.arsize != `AXI4_BURST_SIZE_8BYTES) begin
          $fatal(1, "read address fields changed on the mmio port");
        end
      end else begin
        if (mem.arid != id || mem.araddr != address || mem.arlen != length ||
            mem.arsize != `AXI4_BURST_SIZE_8BYTES) begin
          $fatal(1, "read address fields changed on the mem port");
        end
      end
      @(posedge clk_i);
      @(negedge clk_i);
      source.arvalid = 1'b0;
      mem.arready    = 1'b0;
      mmio.arready   = 1'b0;
      // A response on the wrong port must not reach the source.
      if (expect_mmio) mem.rvalid = 1'b1;
      else mmio.rvalid = 1'b1;
      #1;
      if (source.rvalid) $fatal(1, "wrong-port read data leaked to the source");
      if (expect_mmio) begin
        if (mem.rready) $fatal(1, "read ready leaked to the wrong port");
      end else begin
        if (mmio.rready) $fatal(1, "read ready leaked to the wrong port");
      end
      @(posedge clk_i);
      @(negedge clk_i);
      mem.rvalid  = 1'b0;
      mmio.rvalid = 1'b0;
      for (int j = 0; j <= length; j++) begin
        @(negedge clk_i);
        mem.rid    = id;
        mmio.rid   = id;
        mem.rdata  = read_data(id, j);
        mmio.rdata = read_data(id, j);
        mem.rresp  = `AXI4_RESP_OKAY;
        mmio.rresp = `AXI4_RESP_OKAY;
        mem.rlast  = (j == length);
        mmio.rlast = (j == length);
        if (expect_mmio) mmio.rvalid = 1'b1;
        else mem.rvalid = 1'b1;
        source.rready = (j != hold_beat);
        #1;
        expected_data = read_data(id, j);
        if (!source.rvalid || source.rid != id || source.rdata != expected_data ||
            source.rresp != `AXI4_RESP_OKAY || source.rlast != (j == length)) begin
          $fatal(1, "read data return mismatch");
        end
        if (j == hold_beat) begin
          repeat (2) begin
            if (expect_mmio) begin
              if (mmio.rready) $fatal(1, "read beat ignored source backpressure");
            end else begin
              if (mem.rready) $fatal(1, "read beat ignored source backpressure");
            end
            @(posedge clk_i);
            @(negedge clk_i);
            #1;
            if (!source.rvalid || source.rdata != expected_data ||
                source.rlast != (j == length)) begin
              $fatal(1, "read data changed under backpressure");
            end
          end
          source.rready = 1'b1;
          #1;
        end
        if (expect_mmio) begin
          if (!mmio.rready || mem.rready) $fatal(1, "read ready routing mismatch");
        end else begin
          if (!mem.rready || mmio.rready) $fatal(1, "read ready routing mismatch");
        end
        @(posedge clk_i);
      end
      @(negedge clk_i);
      mem.rvalid    = 1'b0;
      mmio.rvalid   = 1'b0;
      mem.rlast     = 1'b0;
      mmio.rlast    = 1'b0;
      source.rready = 1'b0;
    end
  endtask

  // Runs one single-beat write routed by address window: the W channel must
  // follow the registered AW selection and the buffered response must be held
  // stable while source.bready is low.
  task automatic do_write(input logic [31:0] address, input logic expect_mmio,
                          input logic [2:0] id);
    logic [63:0] data;
    begin
      data = {32'hD000_0000 + 32'(id), 32'h5EED_0000};
      @(negedge clk_i);
      source.awaddr  = address;
      source.awlen   = 8'd0;
      source.awsize  = `AXI4_BURST_SIZE_8BYTES;
      source.awburst = `AXI4_BURST_TYPE_INCR;
      source.awid    = id;
      source.awvalid = 1'b1;
      #1;
      if (source.awready) $fatal(1, "write address accepted without target ready");
      if (expect_mmio) begin
        if (!mmio.awvalid || mem.awvalid) $fatal(1, "write address leaked to the wrong port");
        mmio.awready = 1'b1;
      end else begin
        if (!mem.awvalid || mmio.awvalid) $fatal(1, "write address leaked to the wrong port");
        mem.awready = 1'b1;
      end
      #1;
      if (!source.awready) $fatal(1, "write address was not forwarded to the selected port");
      @(posedge clk_i);
      @(negedge clk_i);
      source.awvalid = 1'b0;
      mem.awready    = 1'b0;
      mmio.awready   = 1'b0;
      // The W channel follows the registered AW selection.
      source.wdata   = data;
      source.wstrb   = 8'hA5;
      source.wlast   = 1'b1;
      source.wvalid  = 1'b1;
      #1;
      if (source.wready) $fatal(1, "write data accepted without target ready");
      if (expect_mmio) begin
        if (!mmio.wvalid || mem.wvalid) $fatal(1, "write data leaked to the wrong port");
      end else begin
        if (!mem.wvalid || mmio.wvalid) $fatal(1, "write data leaked to the wrong port");
      end
      if (expect_mmio) mmio.wready = 1'b1;
      else mem.wready = 1'b1;
      #1;
      if (!source.wready) $fatal(1, "write data was not forwarded to the selected port");
      if (expect_mmio) begin
        if (mmio.wdata != data || mmio.wstrb != 8'hA5 || !mmio.wlast) begin
          $fatal(1, "write data fields changed on the mmio port");
        end
      end else begin
        if (mem.wdata != data || mem.wstrb != 8'hA5 || !mem.wlast) begin
          $fatal(1, "write data fields changed on the mem port");
        end
      end
      @(posedge clk_i);
      @(negedge clk_i);
      source.wvalid = 1'b0;
      mem.wready    = 1'b0;
      mmio.wready   = 1'b0;
      // A response on the wrong port must not reach the source.
      if (expect_mmio) mem.bvalid = 1'b1;
      else mmio.bvalid = 1'b1;
      #1;
      if (source.bvalid) $fatal(1, "wrong-port write response leaked to the source");
      @(posedge clk_i);
      @(negedge clk_i);
      mem.bvalid  = 1'b0;
      mmio.bvalid = 1'b0;
      // Selected response is held stable under source.bready backpressure.
      mem.bid     = id;
      mmio.bid    = id;
      mem.bresp   = `AXI4_RESP_OKAY;
      mmio.bresp  = `AXI4_RESP_OKAY;
      if (expect_mmio) mmio.bvalid = 1'b1;
      else mem.bvalid = 1'b1;
      source.bready = 1'b0;
      #1;
      if (!source.bvalid || source.bid != id || source.bresp != `AXI4_RESP_OKAY) begin
        $fatal(1, "write response return mismatch");
      end
      if (expect_mmio) begin
        if (mmio.bready || mem.bready) $fatal(1, "write ready leaked under backpressure");
      end else begin
        if (mem.bready || mmio.bready) $fatal(1, "write ready leaked under backpressure");
      end
      repeat (2) begin
        @(posedge clk_i);
        @(negedge clk_i);
        #1;
        if (!source.bvalid || source.bid != id)
          $fatal(1, "write response changed under backpressure");
      end
      source.bready = 1'b1;
      #1;
      if (expect_mmio) begin
        if (!mmio.bready || mem.bready) $fatal(1, "write ready routing mismatch");
      end else begin
        if (!mem.bready || mmio.bready) $fatal(1, "write ready routing mismatch");
      end
      @(posedge clk_i);
      @(negedge clk_i);
      mem.bvalid    = 1'b0;
      mmio.bvalid   = 1'b0;
      source.bready = 1'b0;
      #1;
      if (source.bvalid) $fatal(1, "duplicate write response");
    end
  endtask

  initial begin
    init_bus();
    repeat (4) @(posedge clk_i);
    rst_n_i = 1'b1;

    // Read routing: above the MMIO window goes to mem, inside goes to mmio.
    do_read(32'h3800_0000, 1'b0, 3'h1, 8'd0, -1);
    do_read(32'h1000_0000, 1'b1, 3'h2, 8'd0, -1);

    // Window boundaries: 0x01FFFFFF mem, 0x02000000 mmio, 0x2FFFFFFF mmio,
    // 0x30000000 mem.
    do_read(32'h01FF_FFFF, 1'b0, 3'h3, 8'd0, -1);
    do_read(32'h0200_0000, 1'b1, 3'h4, 8'd0, -1);
    do_read(32'h2FFF_FFFF, 1'b1, 3'h5, 8'd0, -1);
    do_read(32'h3000_0000, 1'b0, 3'h6, 8'd0, -1);

    // Multi-beat reads with mid-burst source.rready backpressure, alternating
    // targets so each transaction follows a completed one on the other port.
    do_read(32'h1000_0100, 1'b1, 3'h7, 8'd3, 1);
    do_read(32'h4000_0000, 1'b0, 3'h0, 8'd1, 0);

    // Write routing in both directions; the W channel follows AW.
    do_write(32'h0200_0040, 1'b1, 3'h1);
    do_write(32'h4000_0080, 1'b0, 3'h2);
    do_write(32'h2FFF_FFF8, 1'b1, 3'h3);
    do_write(32'h01FF_FFF8, 1'b0, 3'h4);

    $display("AXI4 MMIO demux test passed");
    $finish;
  end
endmodule
