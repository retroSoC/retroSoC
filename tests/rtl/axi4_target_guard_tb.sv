`timescale 1ns / 1ps

module axi4_target_guard_tb;
  logic        clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        abort_o;
  logic        timeout_valid_o;
  logic        timeout_write_o;
  logic [ 5:0] timeout_id_o;
  logic [31:0] timeout_addr_o;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (6),
      .USER_WIDTH(1)
  ) source (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (6),
      .USER_WIDTH(1)
  ) sink (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  always #5 clk_i = ~clk_i;

  axi4_target_guard #(
      .ReadDepth (4),
      .WriteDepth(2)
  ) u_dut (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .clear_i        (1'b0),
      .timeout_i      (32'd4),
      .clear_busy_o   (),
      .abort_o        (abort_o),
      .abort_done_i   (abort_o),
      .timeout_valid_o(timeout_valid_o),
      .timeout_write_o(timeout_write_o),
      .timeout_id_o   (timeout_id_o),
      .timeout_addr_o (timeout_addr_o),
      .source         (source),
      .sink           (sink)
  );

  task automatic issue_read(input logic [5:0] id, input logic [7:0] len, input logic [31:0] addr);
    begin
      @(negedge clk_i);
      source.arid    = id;
      source.arlen   = len;
      source.araddr  = addr;
      source.arvalid = 1'b1;
      do @(posedge clk_i); while (!source.arready);
      @(negedge clk_i);
      source.arvalid = 1'b0;
    end
  endtask

  task automatic expect_error_read(input logic [5:0] id, input int unsigned beats);
    begin
      for (int beat = 0; beat < beats; beat++) begin
        do @(posedge clk_i); while (!source.rvalid);
        if ((source.rid != id) || (source.rresp != 2'b10) ||
            (source.rlast != (beat == beats - 1))) begin
          $fatal(1, "target guard synthetic read response mismatch");
        end
      end
    end
  endtask

  task automatic return_read_beat(input logic [5:0] id, input logic last,
                                  input logic expected_last, input logic [1:0] expected_resp);
    begin
      @(negedge clk_i);
      sink.rid    = id;
      sink.rdata  = 64'h0123_4567_89ab_cdef;
      sink.rresp  = 2'b00;
      sink.rlast  = last;
      sink.rvalid = 1'b1;
      wait (source.rvalid);
      #1;
      if ((source.rid != id) || (source.rresp != expected_resp) ||
          (source.rlast != expected_last)) begin
        $fatal(1, "target guard read normalization mismatch");
      end
      do @(posedge clk_i); while (!sink.rready);
      @(negedge clk_i);
      sink.rvalid = 1'b0;
      sink.rlast  = 1'b0;
    end
  endtask

  initial begin
    source.awid     = '0;
    source.awaddr   = '0;
    source.awlen    = '0;
    source.awsize   = 3'd3;
    source.awburst  = 2'b01;
    source.awlock   = 1'b0;
    source.awcache  = '0;
    source.awprot   = '0;
    source.awqos    = '0;
    source.awregion = '0;
    source.awuser   = '0;
    source.awvalid  = 1'b0;
    source.wdata    = '0;
    source.wstrb    = '0;
    source.wlast    = 1'b1;
    source.wuser    = '0;
    source.wvalid   = 1'b0;
    source.bready   = 1'b1;
    source.arid     = '0;
    source.araddr   = '0;
    source.arlen    = '0;
    source.arsize   = 3'd3;
    source.arburst  = 2'b01;
    source.arlock   = 1'b0;
    source.arcache  = '0;
    source.arprot   = '0;
    source.arqos    = '0;
    source.arregion = '0;
    source.aruser   = '0;
    source.arvalid  = 1'b0;
    source.rready   = 1'b1;

    sink.awready    = 1'b1;
    sink.wready     = 1'b1;
    sink.bid        = '0;
    sink.bresp      = '0;
    sink.buser      = '0;
    sink.bvalid     = 1'b0;
    sink.arready    = 1'b1;
    sink.rid        = '0;
    sink.rdata      = '0;
    sink.rresp      = '0;
    sink.rlast      = 1'b0;
    sink.ruser      = '0;
    sink.rvalid     = 1'b0;

    repeat (3) @(posedge clk_i);
    rst_n_i = 1'b1;

    issue_read(6'h07, 8'd1, 32'h3800_0020);
    do @(posedge clk_i); while (!sink.arvalid);
    return_read_beat(6'h07, 1'b0, 1'b0, 2'b00);
    return_read_beat(6'h07, 1'b0, 1'b1, 2'b10);

    issue_read(6'h08, 8'd0, 32'h3800_0030);
    do @(posedge clk_i); while (!sink.arvalid);
    return_read_beat(6'h08, 1'b1, 1'b1, 2'b00);

    issue_read(6'h09, 8'd1, 32'h3800_0040);
    wait (timeout_valid_o);
    if (timeout_write_o || (timeout_id_o != 6'h09) || (timeout_addr_o != 32'h3800_0040)) begin
      $fatal(1, "target guard read timeout attribution mismatch");
    end
    expect_error_read(6'h09, 2);

    fork
      begin
        issue_read(6'h0A, 8'd0, 32'h3800_0080);
        expect_error_read(6'h0A, 1);
      end
      begin
        repeat (12) begin
          @(posedge clk_i);
          if (sink.arvalid) $fatal(1, "isolated target accepted a new read");
        end
      end
    join

    @(negedge clk_i);
    source.awid    = 6'h0B;
    source.awaddr  = 32'h3800_0100;
    source.awvalid = 1'b1;
    do @(posedge clk_i); while (!source.awready);
    @(negedge clk_i);
    source.awvalid = 1'b0;
    source.wdata   = 64'h0123_4567_89AB_CDEF;
    source.wstrb   = 8'hFF;
    source.wvalid  = 1'b1;
    do @(posedge clk_i); while (!source.wready);
    @(negedge clk_i);
    source.wvalid = 1'b0;
    do @(posedge clk_i); while (!source.bvalid);
    if ((source.bid != 6'h0B) || (source.bresp != 2'b10) || sink.awvalid || sink.wvalid) begin
      $fatal(1, "isolated target write termination mismatch");
    end

    $display("AXI4 target guard timeout and isolation test passed");
    $finish;
  end

  initial begin
    repeat (200) @(posedge clk_i);
    $fatal(1, "AXI4 target guard test timed out");
  end
endmodule
