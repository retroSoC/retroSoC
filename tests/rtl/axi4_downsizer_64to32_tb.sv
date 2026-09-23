`timescale 1ns / 1ps

`include "axi4_define.svh"

module axi4_downsizer_64to32_tb;
  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (7),
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

  axi4_downsizer_64to32 #(
      .WideIdWidth(7)
  ) u_dut (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .clear_i(1'b0),
      .wide   (wide),
      .narrow (narrow)
  );

  // Lower-half RRESP of the wide beat currently being recombined.
  logic [1:0] last_lower_resp;

  function automatic logic [63:0] wide_write_data(input int beat);
    return {32'hD00D_0000 + 32'(beat), 32'hB00B_0000 + 32'(beat)};
  endfunction

  function automatic logic [7:0] wide_write_strb(input int beat);
    return (beat % 2 == 0) ? 8'hFF : 8'hC3;
  endfunction

  function automatic logic [31:0] narrow_read_data(input int beat);
    return 32'h3000_0000 + 32'(beat);
  endfunction

  task automatic init_bus;
    begin
      wide.awid       = '0;
      wide.awaddr     = '0;
      wide.awlen      = '0;
      wide.awsize     = `AXI4_BURST_SIZE_8BYTES;
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
      wide.arsize     = `AXI4_BURST_SIZE_8BYTES;
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
                             input logic [2:0] size, input logic [6:0] id,
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
                              input logic [2:0] size, input logic [6:0] id,
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

  task automatic return_write_response(input logic [6:0] expected_id, input logic [1:0] response);
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

  // Drives one wide write beat whose two narrow halves must stream back to back.
  // expect_narrow_last marks the narrow-burst final beat (a fragment end or the
  // wide burst end); the wide master only raises wide.wlast at the true end.
  task automatic send_wide_write_beat(input logic [63:0] data, input logic [7:0] strb,
                                      input logic wide_last, input logic expect_narrow_last);
    begin
      @(negedge clk_i);
      wide.wdata    = data;
      wide.wstrb    = strb;
      wide.wlast    = wide_last;
      wide.wvalid   = 1'b1;
      narrow.wready = 1'b1;
      #1;
      if (!narrow.wvalid || narrow.wdata != data[31:0] || narrow.wstrb != strb[3:0] ||
          narrow.wlast || wide.wready) begin
        $fatal(1, "lower split write beat mismatch");
      end
      @(posedge clk_i);
      @(negedge clk_i);
      #1;
      if (!narrow.wvalid || narrow.wdata != data[63:32] || narrow.wstrb != strb[7:4] ||
          narrow.wlast != expect_narrow_last || !wide.wready) begin
        $fatal(1, "upper split write beat mismatch");
      end
      @(posedge clk_i);
    end
  endtask

  // Drives one narrow read beat. Fragment boundaries fall on even beat counts,
  // so the narrow slave raises rlast on beat 15 of every fragment; the wide
  // side may only raise rlast on the final beat of the whole wide burst.
  task automatic send_narrow_read_beat(input int beat, input int total_narrow, input logic [6:0] id,
                                       input logic [1:0] response);
    logic [63:0] expected_data;
    logic [ 1:0] expected_response;
    logic        expected_last;
    begin
      @(negedge clk_i);
      narrow.rdata  = narrow_read_data(beat);
      narrow.rresp  = response;
      narrow.rlast  = (beat == 15) || (beat == total_narrow - 1);
      narrow.rvalid = 1'b1;
      wide.rready   = 1'b1;
      #1;
      if (!narrow.rready) $fatal(1, "narrow read beat was not accepted");
      if (beat % 2 == 0) begin
        last_lower_resp = response;
        if (wide.rvalid) $fatal(1, "lower narrow read beat leaked to the wide side");
      end else begin
        expected_data     = {narrow_read_data(beat), narrow_read_data(beat - 1)};
        expected_response = (last_lower_resp != `AXI4_RESP_OKAY) ? last_lower_resp : response;
        expected_last     = (beat == total_narrow - 1);
        if (!wide.rvalid || wide.rdata != expected_data || wide.rresp != expected_response ||
            wide.rid != id || wide.rlast != expected_last) begin
          $fatal(1, "wide read recombination mismatch");
        end
      end
      @(posedge clk_i);
    end
  endtask

  // Accepts the address of a follow-up write fragment; the sideband fields must
  // replay the values registered when the wide address was accepted.
  task automatic accept_fragment_write(
      input logic [31:0] address, input logic [7:0] expected_length,
      input logic [3:0] expected_cache, input logic [2:0] expected_prot,
      input logic [3:0] expected_qos, input logic [3:0] expected_region);
    begin
      @(negedge clk_i);
      narrow.awready = 1'b1;
      #1;
      if (!narrow.awvalid || narrow.awaddr != address || narrow.awlen != expected_length ||
          narrow.awsize != 3'd2 || narrow.awburst != `AXI4_BURST_TYPE_INCR ||
          narrow.awcache != expected_cache || narrow.awprot != expected_prot ||
          narrow.awqos != expected_qos || narrow.awregion != expected_region ||
          narrow.awlock != `AXI4_LOCK_NORM || wide.awready) begin
        $fatal(1, "write fragment address mismatch");
      end
      if (narrow.wvalid || wide.wready) begin
        $fatal(1, "write data accepted before the fragment address");
      end
      @(posedge clk_i);
      @(negedge clk_i);
      narrow.awready = 1'b0;
    end
  endtask

  // Accepts the address of a follow-up read fragment issued while the wide read
  // channel is still busy returning the previous fragment.
  task automatic accept_fragment_read(
      input logic [31:0] address, input logic [7:0] expected_length,
      input logic [3:0] expected_cache, input logic [2:0] expected_prot,
      input logic [3:0] expected_qos, input logic [3:0] expected_region);
    begin
      @(negedge clk_i);
      narrow.rvalid  = 1'b0;
      narrow.rlast   = 1'b0;
      narrow.arready = 1'b1;
      #1;
      if (!narrow.arvalid || narrow.araddr != address || narrow.arlen != expected_length ||
          narrow.arsize != 3'd2 || narrow.arburst != `AXI4_BURST_TYPE_INCR ||
          narrow.arcache != expected_cache || narrow.arprot != expected_prot ||
          narrow.arqos != expected_qos || narrow.arregion != expected_region ||
          narrow.arlock != `AXI4_LOCK_NORM || wide.arready) begin
        $fatal(1, "read fragment address mismatch");
      end
      @(posedge clk_i);
      @(negedge clk_i);
      narrow.arready = 1'b0;
    end
  endtask

  // Returns the final fragment response and checks the single aggregated wide
  // response, including that no further response or fragment is issued.
  task automatic finish_split_write(input logic [6:0] expected_id,
                                    input logic [1:0] driven_response,
                                    input logic [1:0] expected_response);
    begin
      @(negedge clk_i);
      narrow.bresp  = driven_response;
      narrow.bvalid = 1'b1;
      wide.bready   = 1'b0;
      #1;
      if (!narrow.bready) $fatal(1, "final narrow write response was not accepted");
      @(posedge clk_i);
      @(negedge clk_i);
      narrow.bvalid = 1'b0;
      #1;
      if (!wide.bvalid || wide.bid != expected_id || wide.bresp != expected_response) begin
        $fatal(1, "aggregated write response mismatch");
      end
      repeat (2) @(posedge clk_i);
      if (!wide.bvalid || wide.bid != expected_id || wide.bresp != expected_response) begin
        $fatal(1, "aggregated write response changed under backpressure");
      end
      @(negedge clk_i);
      wide.bready = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      wide.bready = 1'b0;
      repeat (2) begin
        #1;
        if (wide.bvalid || narrow.awvalid) $fatal(1, "duplicate write response or fragment");
        @(posedge clk_i);
        @(negedge clk_i);
      end
    end
  endtask

  task automatic expect_no_fragment_issue;
    begin
      repeat (2) begin
        #1;
        if (narrow.arvalid || narrow.awvalid) $fatal(1, "unexpected extra fragment issue");
        @(posedge clk_i);
        @(negedge clk_i);
      end
    end
  endtask

  // Runs one split long-burst write: fragment zero covers eight wide beats and
  // the final fragment the remaining beats - 8 wide beats.
  task automatic do_split_write(input logic [31:0] address, input logic [7:0] length,
                                input logic [6:0] id, input logic [1:0] fragment_response,
                                input logic [1:0] final_response,
                                input logic [1:0] expected_response);
    int          beats;
    logic [ 7:0] fragment_len;
    logic [63:0] gap_data;
    logic [ 7:0] gap_strb;
    begin
      beats         = length + 1;
      fragment_len  = 8'(((length - 8'd7) << 1) - 8'd1);
      wide.awcache  = 4'h6;
      wide.awprot   = 3'h5;
      wide.awqos    = 4'h9;
      wide.awregion = 4'h3;
      accept_write(address, length, 3'd3, id, 8'd15);
      // Mutate the wide sidebands; the fragment address must replay the
      // values registered at the wide address accept, not the live inputs.
      wide.awcache  = 4'hF;
      wide.awprot   = 3'h0;
      wide.awqos    = 4'h0;
      wide.awregion = 4'hF;
      for (int i = 0; i < 8; i++) begin
        send_wide_write_beat(wide_write_data(i), wide_write_strb(i), 1'b0, i == 7);
      end
      gap_data = wide_write_data(8);
      gap_strb = wide_write_strb(8);
      @(negedge clk_i);
      wide.wdata    = gap_data;
      wide.wstrb    = gap_strb;
      wide.wlast    = (beats == 9);
      wide.wvalid   = 1'b1;
      narrow.wready = 1'b1;
      #1;
      if (narrow.wvalid || wide.wready || narrow.awvalid) begin
        $fatal(1, "write data or fragment address crossed the fragment boundary early");
      end
      narrow.bresp  = fragment_response;
      narrow.bvalid = 1'b1;
      #1;
      if (!narrow.bready || wide.bvalid) begin
        $fatal(1, "fragment write response was not buffered privately");
      end
      @(posedge clk_i);
      @(negedge clk_i);
      narrow.bvalid = 1'b0;
      #1;
      if (wide.bvalid) $fatal(1, "fragment write response reached the wide side");
      @(posedge clk_i);
      @(negedge clk_i);
      #1;
      if (wide.bvalid) $fatal(1, "fragment write response reached the wide side");
      accept_fragment_write(address + 32'd64, fragment_len, 4'h6, 3'h5, 4'h9, 4'h3);
      #1;
      if (!narrow.wvalid || narrow.wdata != gap_data[31:0] || narrow.wstrb != gap_strb[3:0] ||
          narrow.wlast || wide.wready) begin
        $fatal(1, "stalled lower split write beat mismatch");
      end
      @(posedge clk_i);
      @(negedge clk_i);
      #1;
      if (!narrow.wvalid || narrow.wdata != gap_data[63:32] || narrow.wstrb != gap_strb[7:4] ||
          narrow.wlast != (beats == 9) || !wide.wready) begin
        $fatal(1, "stalled upper split write beat mismatch");
      end
      @(posedge clk_i);
      for (int i = 9; i < beats; i++) begin
        send_wide_write_beat(wide_write_data(i), wide_write_strb(i), i == beats - 1,
                             i == beats - 1);
      end
      @(negedge clk_i);
      wide.wvalid   = 1'b0;
      narrow.wready = 1'b0;
      finish_split_write(id, final_response, expected_response);
    end
  endtask

  // Runs one split long-burst read, optionally injecting a lower-half and an
  // upper-half RRESP error inside the first fragment (-1 disables either).
  task automatic do_split_read(input logic [31:0] address, input logic [7:0] length,
                               input logic [6:0] id, input int error_lower,
                               input logic [1:0] error_lower_response, input int error_upper,
                               input logic [1:0] error_upper_response);
    int         beats;
    int         total_narrow;
    logic [7:0] fragment_len;
    logic [1:0] response;
    begin
      beats         = length + 1;
      total_narrow  = 2 * beats;
      fragment_len  = 8'(((length - 8'd7) << 1) - 8'd1);
      wide.arcache  = 4'hA;
      wide.arprot   = 3'h6;
      wide.arqos    = 4'h3;
      wide.arregion = 4'hC;
      accept_read(address, length, 3'd3, id, 8'd15);
      wide.arcache  = 4'h0;
      wide.arprot   = 3'h1;
      wide.arqos    = 4'hF;
      wide.arregion = 4'h0;
      for (int j = 0; j < 16; j++) begin
        response = `AXI4_RESP_OKAY;
        if (j == error_lower) response = error_lower_response;
        if (j == error_upper) response = error_upper_response;
        send_narrow_read_beat(j, total_narrow, id, response);
      end
      accept_fragment_read(address + 32'd64, fragment_len, 4'hA, 3'h6, 4'h3, 4'hC);
      for (int j = 16; j < total_narrow; j++) begin
        response = `AXI4_RESP_OKAY;
        if (j == error_lower) response = error_lower_response;
        if (j == error_upper) response = error_upper_response;
        send_narrow_read_beat(j, total_narrow, id, response);
      end
      @(negedge clk_i);
      narrow.rvalid = 1'b0;
      narrow.rlast  = 1'b0;
      wide.rready   = 1'b0;
      expect_no_fragment_issue();
    end
  endtask

  initial begin
    init_bus();
    repeat (4) @(posedge clk_i);
    rst_n_i = 1'b1;

    accept_read(32'h0000_0040, 8'd0, 3'd3, 7'h40, 8'd1);
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
    if (!wide.rvalid || narrow.rready || wide.rid != 7'h40 ||
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

    accept_read(32'h0000_0000, 8'd1, 3'd2, 7'h41, 8'd1);
    @(negedge clk_i);
    narrow.rdata  = 32'hA5A5_0000;
    narrow.rresp  = `AXI4_RESP_OKAY;
    narrow.rlast  = 1'b0;
    narrow.rvalid = 1'b1;
    wide.rready   = 1'b1;
    #1;
    if (wide.rdata != 64'h0000_0000_A5A5_0000 || wide.rid != 7'h41) begin
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

    accept_write(32'h0000_0080, 8'd0, 3'd3, 7'h42, 8'd1);
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
    return_write_response(7'h42, `AXI4_RESP_DECODE_ERROR);

    accept_write(32'h0000_0004, 8'd1, 3'd2, 7'h43, 8'd1);
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
    return_write_response(7'h43, `AXI4_RESP_OKAY);

    // Boundary: an eight-beat size-3 burst keeps the 1:1 single-burst mapping.
    accept_write(32'h0000_0100, 8'd7, 3'd3, 7'h50, 8'd15);
    for (int i = 0; i < 8; i++) begin
      send_wide_write_beat(wide_write_data(i), wide_write_strb(i), i == 7, i == 7);
    end
    @(negedge clk_i);
    wide.wvalid   = 1'b0;
    narrow.wready = 1'b0;
    return_write_response(7'h50, `AXI4_RESP_OKAY);
    expect_no_fragment_issue();

    accept_read(32'h0000_0180, 8'd7, 3'd3, 7'h51, 8'd15);
    for (int j = 0; j < 16; j++) begin
      send_narrow_read_beat(j, 16, 7'h51, `AXI4_RESP_OKAY);
    end
    @(negedge clk_i);
    narrow.rvalid = 1'b0;
    narrow.rlast  = 1'b0;
    wide.rready   = 1'b0;
    expect_no_fragment_issue();

    // Long-burst writes: 9, 15, and 16 beats each split into two fragments.
    do_split_write(32'h0000_0200, 8'd8, 7'h52, `AXI4_RESP_OKAY, `AXI4_RESP_OKAY, `AXI4_RESP_OKAY);
    do_split_write(32'h0000_0280, 8'd14, 7'h53, `AXI4_RESP_OKAY, `AXI4_RESP_OKAY, `AXI4_RESP_OKAY);
    do_split_write(32'h0000_0300, 8'd15, 7'h54, `AXI4_RESP_OKAY, `AXI4_RESP_OKAY, `AXI4_RESP_OKAY);

    // Write response aggregation: an early fragment error and a final fragment
    // error each produce exactly one wide response with the first error code.
    do_split_write(32'h0000_0380, 8'd8, 7'h55, `AXI4_RESP_SLAVE_ERROR, `AXI4_RESP_OKAY,
                   `AXI4_RESP_SLAVE_ERROR);
    do_split_write(32'h0000_0400, 8'd15, 7'h56, `AXI4_RESP_OKAY, `AXI4_RESP_DECODE_ERROR,
                   `AXI4_RESP_DECODE_ERROR);

    // Long-burst reads: 9, 15, and 16 beats recombine across the fragment
    // boundary with rlast only on the final narrow beat of the wide burst.
    do_split_read(32'h0000_0480, 8'd8, 7'h57, -1, `AXI4_RESP_OKAY, -1, `AXI4_RESP_OKAY);
    do_split_read(32'h0000_0500, 8'd14, 7'h58, -1, `AXI4_RESP_OKAY, -1, `AXI4_RESP_OKAY);
    do_split_read(32'h0000_0580, 8'd15, 7'h59, -1, `AXI4_RESP_OKAY, -1, `AXI4_RESP_OKAY);

    // Read errors inside the first fragment: a non-OKAY lower half wins its
    // wide beat, otherwise the upper half response is reported; neither leaks
    // into the following wide beat or across the fragment boundary.
    do_split_read(32'h0000_0600, 8'd15, 7'h5A, 4, `AXI4_RESP_SLAVE_ERROR, 9,
                  `AXI4_RESP_DECODE_ERROR);

    $display("AXI4 64-to-32 downsizer test passed");
    $finish;
  end
endmodule
