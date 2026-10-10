`timescale 1ns / 1ps

`include "axi4_define.svh"

module axi4_downsizer_128to64_tb;
  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(128),
      .ID_WIDTH  (8),
      .USER_WIDTH(1)
  ) wide (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) narrow (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  always #5 clk_i = ~clk_i;

  axi4_downsizer_128to64 #(
      .WideIdWidth(8)
  ) u_dut (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .clear_i(1'b0),
      .wide   (wide),
      .narrow (narrow)
  );

  // Lower-half RRESP of the wide beat currently being recombined.
  logic [1:0] last_lower_resp;

  function automatic logic [127:0] wide_write_data(input int beat);
    return {64'hD00D_0000_0000_0000 + 64'(beat), 64'hB00B_0000_0000_0000 + 64'(beat)};
  endfunction

  function automatic logic [15:0] wide_write_strb(input int beat);
    return (beat % 2 == 0) ? 16'hFFFF : 16'hC33C;
  endfunction

  function automatic logic [63:0] narrow_read_data(input int beat);
    return 64'h3000_0000_0000_0000 + 64'(beat);
  endfunction

  function automatic logic [63:0] size2_read_data(input int beat);
    return 64'hA5A5_0000_0000_0000 + 64'(beat);
  endfunction

  task automatic init_bus;
    begin
      wide.awid       = '0;
      wide.awaddr     = '0;
      wide.awlen      = '0;
      wide.awsize     = `AXI4_BURST_SIZE_16BYTES;
      wide.awburst    = `AXI4_BURST_TYPE_INCR;
      wide.awlock     = `AXI4_LOCK_NORM;
      wide.awcache    = `AXI4_CACHE_NO_BUF;
      wide.awprot     = `AXI4_PROT_DATA;
      wide.awqos      = `AXI4_QOS_NORMAL;
      wide.awregion   = `AXI4_REGION_NORMAL;
      wide.awuser     = '0;
      wide.awvalid    = 1'b0;
      wide.wdata      = '0;
      wide.wstrb      = '0;
      wide.wlast      = 1'b0;
      wide.wuser      = '0;
      wide.wvalid     = 1'b0;
      wide.bready     = 1'b0;
      wide.arid       = '0;
      wide.araddr     = '0;
      wide.arlen      = '0;
      wide.arsize     = `AXI4_BURST_SIZE_16BYTES;
      wide.arburst    = `AXI4_BURST_TYPE_INCR;
      wide.arlock     = `AXI4_LOCK_NORM;
      wide.arcache    = `AXI4_CACHE_NO_BUF;
      wide.arprot     = `AXI4_PROT_DATA;
      wide.arqos      = `AXI4_QOS_NORMAL;
      wide.arregion   = `AXI4_REGION_NORMAL;
      wide.aruser     = '0;
      wide.arvalid    = 1'b0;
      wide.rready     = 1'b0;
      narrow.awready  = 1'b0;
      narrow.wready   = 1'b0;
      narrow.bid      = '0;
      narrow.bresp    = `AXI4_RESP_OKAY;
      narrow.buser    = '0;
      narrow.bvalid   = 1'b0;
      narrow.arready  = 1'b0;
      narrow.rid      = '0;
      narrow.rdata    = '0;
      narrow.rresp    = `AXI4_RESP_OKAY;
      narrow.rlast    = 1'b0;
      narrow.ruser    = '0;
      narrow.rvalid   = 1'b0;
      last_lower_resp = `AXI4_RESP_OKAY;
    end
  endtask

  task automatic accept_read(input logic [31:0] address, input logic [7:0] length,
                             input logic [2:0] size, input logic [1:0] burst, input logic [7:0] id,
                             input logic [7:0] expected_length);
    begin
      @(negedge clk_i);
      wide.araddr  = address;
      wide.arlen   = length;
      wide.arsize  = size;
      wide.arburst = burst;
      wide.arid    = id;
      wide.arvalid = 1'b1;
      #1;
      if (wide.arready) $fatal(1, "read address ignored narrow backpressure");
      narrow.arready = 1'b1;
      #1;
      if (!narrow.arvalid || narrow.arid != 3'd0 || narrow.araddr != address ||
          narrow.arlen != expected_length ||
          narrow.arsize != ((size == 3'd4) ? 3'd3 : size) || narrow.arburst != burst) begin
        $fatal(1, "read address conversion mismatch");
      end
      @(posedge clk_i);
      @(negedge clk_i);
      wide.arvalid   = 1'b0;
      narrow.arready = 1'b0;
    end
  endtask

  task automatic accept_write(input logic [31:0] address, input logic [7:0] length,
                              input logic [2:0] size, input logic [7:0] id,
                              input logic [7:0] expected_length);
    begin
      @(negedge clk_i);
      wide.awaddr  = address;
      wide.awlen   = length;
      wide.awsize  = size;
      wide.awburst = `AXI4_BURST_TYPE_INCR;
      wide.awid    = id;
      wide.awvalid = 1'b1;
      #1;
      if (wide.awready) $fatal(1, "write address ignored narrow backpressure");
      narrow.awready = 1'b1;
      #1;
      if (!narrow.awvalid || narrow.awid != 3'd0 || narrow.awaddr != address ||
          narrow.awlen != expected_length ||
          narrow.awsize != ((size == 3'd4) ? 3'd3 : size) ||
          narrow.awburst != `AXI4_BURST_TYPE_INCR) begin
        $fatal(1, "write address conversion mismatch");
      end
      @(posedge clk_i);
      @(negedge clk_i);
      wide.awvalid   = 1'b0;
      narrow.awready = 1'b0;
    end
  endtask

  // Returns the narrow write response while the wide master is not ready; the
  // response must be buffered privately and presented once with the registered
  // wide ID, held stable until the wide handshake completes.
  task automatic return_write_response(input logic [7:0] expected_id, input logic [1:0] response);
    begin
      @(negedge clk_i);
      narrow.bresp  = response;
      narrow.bvalid = 1'b1;
      wide.bready   = 1'b0;
      #1;
      if (!narrow.bready) $fatal(1, "narrow write response was not accepted into buffer");
      if (wide.bvalid) $fatal(1, "write response bypassed the buffer");
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
      #1;
      if (wide.bvalid) $fatal(1, "duplicate write response");
    end
  endtask

  // Drives one wide size-4 write beat whose two narrow halves stream back to
  // back. The narrow side raises wlast only on the upper half of the final
  // wide beat; the wide master sees wready only on the upper halves.
  task automatic send_wide_write_beat(input logic [127:0] data, input logic [15:0] strb,
                                      input logic wide_last);
    begin
      @(negedge clk_i);
      wide.wdata    = data;
      wide.wstrb    = strb;
      wide.wlast    = wide_last;
      wide.wvalid   = 1'b1;
      narrow.wready = 1'b1;
      #1;
      if (!narrow.wvalid || narrow.wdata != data[63:0] || narrow.wstrb != strb[7:0] ||
          narrow.wlast || wide.wready) begin
        $fatal(1, "lower split write beat mismatch");
      end
      @(posedge clk_i);
      @(negedge clk_i);
      #1;
      if (!narrow.wvalid || narrow.wdata != data[127:64] || narrow.wstrb != strb[15:8] ||
          narrow.wlast != wide_last || !wide.wready) begin
        $fatal(1, "upper split write beat mismatch");
      end
      @(posedge clk_i);
    end
  endtask

  // Drives one narrow read beat of a size-4 burst. Even beats are lower halves
  // that must be buffered invisibly; odd beats complete a wide beat whose
  // response keeps a non-OKAY lower half. hold_cycles > 0 applies wide.rready
  // backpressure on the upper half before accepting it.
  task automatic send_narrow_read_beat(input int beat, input int total_narrow, input logic [7:0] id,
                                       input logic [1:0] response, input int hold_cycles);
    logic [127:0] expected_data;
    logic [  1:0] expected_response;
    logic         expected_last;
    begin
      @(negedge clk_i);
      narrow.rdata  = narrow_read_data(beat);
      narrow.rresp  = response;
      narrow.rlast  = (beat == total_narrow - 1);
      narrow.rvalid = 1'b1;
      wide.rready   = (hold_cycles == 0);
      #1;
      if (beat % 2 == 0) begin
        last_lower_resp = response;
        if (!narrow.rready) $fatal(1, "lower narrow read beat was not accepted");
        if (wide.rvalid) $fatal(1, "lower narrow read beat leaked to the wide side");
        @(posedge clk_i);
      end else begin
        expected_data     = {narrow_read_data(beat), narrow_read_data(beat - 1)};
        expected_response = (last_lower_resp != `AXI4_RESP_OKAY) ? last_lower_resp : response;
        expected_last     = (beat == total_narrow - 1);
        if (!wide.rvalid || wide.rdata != expected_data || wide.rresp != expected_response ||
            wide.rid != id || wide.rlast != expected_last) begin
          $fatal(1, "wide read recombination mismatch");
        end
        for (int h = 0; h < hold_cycles; h++) begin
          if (narrow.rready) $fatal(1, "upper narrow read beat ignored wide backpressure");
          @(posedge clk_i);
          @(negedge clk_i);
          #1;
          if (!wide.rvalid || wide.rdata != expected_data || wide.rresp != expected_response ||
              wide.rid != id || wide.rlast != expected_last) begin
            $fatal(1, "wide read beat changed under backpressure");
          end
        end
        wide.rready = 1'b1;
        #1;
        if (!narrow.rready) $fatal(1, "upper narrow read beat was not accepted");
        @(posedge clk_i);
      end
    end
  endtask

  // Runs one size-4 read burst (INCR or WRAP): the narrow burst doubles in
  // length, every two narrow beats recombine into one wide beat, and the wide
  // side raises rlast only on the final beat. error_beat/error_response inject
  // a lower-half error, hold_wide_beat stalls one wide beat, and
  // gap_after_narrow inserts a narrow.rvalid bubble; -1 disables each.
  task automatic do_size4_read(input logic [31:0] address, input logic [7:0] length,
                               input logic [1:0] burst, input logic [7:0] id, input int error_beat,
                               input logic [1:0] error_response, input int hold_wide_beat,
                               input int gap_after_narrow);
    int         total_narrow;
    logic [1:0] response;
    begin
      total_narrow = 2 * (length + 1);
      accept_read(address, length, 3'd4, burst, id, 8'((length << 1) | 8'd1));
      for (int j = 0; j < total_narrow; j++) begin
        response = (j == error_beat) ? error_response : `AXI4_RESP_OKAY;
        send_narrow_read_beat(j, total_narrow, id, response,
                              (j % 2 == 1 && j / 2 == hold_wide_beat) ? 2 : 0);
        if (j == gap_after_narrow) begin
          @(negedge clk_i);
          narrow.rvalid = 1'b0;
          narrow.rlast  = 1'b0;
          wide.rready   = 1'b0;
          #1;
          if (wide.rvalid) $fatal(1, "wide read beat appeared during a narrow gap");
          @(posedge clk_i);
        end
      end
      @(negedge clk_i);
      narrow.rvalid = 1'b0;
      narrow.rlast  = 1'b0;
      wide.rready   = 1'b0;
    end
  endtask

  // Runs one size-2 read burst: the geometry passes through unchanged and each
  // narrow beat lands on the lane selected by address bit 3.
  task automatic do_size2_read(input logic [31:0] address, input logic [7:0] length,
                               input logic [7:0] id);
    logic [127:0] expected_data;
    begin
      accept_read(address, length, 3'd2, `AXI4_BURST_TYPE_INCR, id, length);
      for (int j = 0; j <= length; j++) begin
        @(negedge clk_i);
        narrow.rdata  = size2_read_data(j);
        narrow.rresp  = `AXI4_RESP_OKAY;
        narrow.rlast  = (j == length);
        narrow.rvalid = 1'b1;
        wide.rready   = 1'b1;
        #1;
        expected_data = address[3] ? {size2_read_data(j), 64'd0} : {64'd0, size2_read_data(j)};
        if (!narrow.rready) $fatal(1, "32-bit read beat was not accepted");
        if (!wide.rvalid || wide.rdata != expected_data || wide.rid != id ||
            wide.rlast != (j == length) || wide.rresp != `AXI4_RESP_OKAY) begin
          $fatal(1, "32-bit read lane mismatch");
        end
        @(posedge clk_i);
      end
      @(negedge clk_i);
      narrow.rvalid = 1'b0;
      narrow.rlast  = 1'b0;
      wide.rready   = 1'b0;
    end
  endtask

  // Runs one size-4 write burst: each wide beat splits into a lower and an
  // upper narrow beat and the narrow burst ends on the upper half of the final
  // wide beat.
  task automatic do_size4_write(input logic [31:0] address, input logic [7:0] length,
                                input logic [7:0] id, input logic [1:0] response);
    begin
      accept_write(address, length, 3'd4, id, 8'((length << 1) | 8'd1));
      for (int i = 0; i <= length; i++) begin
        send_wide_write_beat(wide_write_data(i), wide_write_strb(i), i == length);
      end
      @(negedge clk_i);
      wide.wvalid   = 1'b0;
      narrow.wready = 1'b0;
      return_write_response(id, response);
    end
  endtask

  // Runs one single-beat size-2 write; the narrow beat takes the half selected
  // by address bit 3 and completes immediately.
  task automatic do_size2_write(input logic [31:0] address, input logic [7:0] id);
    logic [127:0] data;
    logic [ 15:0] strb;
    logic [ 63:0] expected_data;
    logic [  7:0] expected_strb;
    begin
      data = 128'hCAFE_0000_0000_0000_DEAD_0000_0000_0000;
      strb = 16'hF00F;
      accept_write(address, 8'd0, 3'd2, id, 8'd0);
      @(negedge clk_i);
      wide.wdata    = data;
      wide.wstrb    = strb;
      wide.wlast    = 1'b1;
      wide.wvalid   = 1'b1;
      narrow.wready = 1'b1;
      #1;
      expected_data = address[3] ? data[127:64] : data[63:0];
      expected_strb = address[3] ? strb[15:8] : strb[7:0];
      if (!narrow.wvalid || narrow.wdata != expected_data || narrow.wstrb != expected_strb ||
          !narrow.wlast || !wide.wready) begin
        $fatal(1, "32-bit write lane mismatch");
      end
      @(posedge clk_i);
      @(negedge clk_i);
      wide.wvalid   = 1'b0;
      narrow.wready = 1'b0;
      return_write_response(id, `AXI4_RESP_OKAY);
    end
  endtask

  initial begin
    init_bus();
    repeat (4) @(posedge clk_i);
    rst_n_i = 1'b1;

    // Single-beat size-4 read: the lower-half SLVERR stays sticky in the
    // recombined wide beat, which is held under wide.rready backpressure.
    do_size4_read(32'h0000_0040, 8'd0, `AXI4_BURST_TYPE_INCR, 8'hA5, 0, `AXI4_RESP_SLAVE_ERROR, 0,
                  -1);

    // Four-beat size-4 INCR read: narrow arlen 7, wide rlast only on the final
    // beat, mid-burst wide backpressure, and a narrow.rvalid bubble.
    do_size4_read(32'h0000_0100, 8'd3, `AXI4_BURST_TYPE_INCR, 8'h10, -1, `AXI4_RESP_OKAY, 1, 4);

    // WRAP4 size-4 read: the narrow burst stays WRAP with doubled length.
    do_size4_read(32'h0000_0300, 8'd3, `AXI4_BURST_TYPE_WRAP, 8'h11, -1, `AXI4_RESP_OKAY, -1, -1);

    // Size-2 reads: geometry passthrough and lane placement for address bit 3
    // clear (lower lane) and set (upper lane).
    do_size2_read(32'h0000_0200, 8'd1, 8'h41);
    do_size2_read(32'h0000_0208, 8'd0, 8'h42);

    // Two-beat size-4 INCR write: beat splitting, wstrb halves, narrow wlast
    // only on the upper half of the final wide beat, and an error response.
    do_size4_write(32'h0000_0400, 8'd1, 8'h20, `AXI4_RESP_SLAVE_ERROR);

    // Size-2 writes: lane placement for both address bit 3 alignments.
    do_size2_write(32'h0000_0500, 8'h43);
    do_size2_write(32'h0000_0508, 8'h44);

    $display("AXI4 128-to-64 downsizer test passed");
    $finish;
  end
endmodule
