`timescale 1ns / 1ps

`include "axi4_define.svh"

module axi42ribp_burst_tb;
  logic          clk_i = 1'b0;
  logic          rst_n_i = 1'b0;
  logic   [31:0] memory              [0:63];
  logic   [31:0] expected;
  integer        target_accesses = 0;
  integer        error_beats;
  integer        cycle_count = 0;
  integer        burst_cycles;
  integer        single_cycles;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  ribp_if ribp ();

  always #5 clk_i = ~clk_i;

  always @(posedge clk_i) cycle_count <= cycle_count + 1;

  axi42ribp_burst u_dut (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .axi4   (axi4),
      .ribp   (ribp)
  );

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      ribp.ready      <= 1'b0;
      ribp.rdata      <= '0;
      target_accesses <= 0;
    end else begin
      ribp.ready <= ribp.valid && !ribp.ready;
      if (ribp.valid && !ribp.ready) begin
        target_accesses <= target_accesses + 1;
        ribp.rdata      <= memory[ribp.addr[7:2]];
        for (int lane = 0; lane < 4; lane++) begin
          if (ribp.wstrb[lane]) begin
            memory[ribp.addr[7:2]][lane*8+:8] <= ribp.wdata[lane*8+:8];
          end
        end
      end
    end
  end

  assign ribp.resp_err = 1'b0;

  task automatic init_axi4;
    begin
      axi4.awid     = '0;
      axi4.awaddr   = '0;
      axi4.awlen    = '0;
      axi4.awsize   = `AXI4_BURST_SIZE_4BYTES;
      axi4.awburst  = `AXI4_BURST_TYPE_INCR;
      axi4.awlock   = `AXI4_LOCK_NORM;
      axi4.awcache  = `AXI4_CACHE_NO_BUF;
      axi4.awprot   = `AXI4_PROT_DATA;
      axi4.awqos    = `AXI4_QOS_NORMAL;
      axi4.awregion = `AXI4_REGION_NORMAL;
      axi4.awuser   = '0;
      axi4.awvalid  = 1'b0;
      axi4.wdata    = '0;
      axi4.wstrb    = '0;
      axi4.wlast    = 1'b0;
      axi4.wuser    = '0;
      axi4.wvalid   = 1'b0;
      axi4.bready   = 1'b0;
      axi4.arid     = '0;
      axi4.araddr   = '0;
      axi4.arlen    = '0;
      axi4.arsize   = `AXI4_BURST_SIZE_4BYTES;
      axi4.arburst  = `AXI4_BURST_TYPE_INCR;
      axi4.arlock   = `AXI4_LOCK_NORM;
      axi4.arcache  = `AXI4_CACHE_NO_BUF;
      axi4.arprot   = `AXI4_PROT_DATA;
      axi4.arqos    = `AXI4_QOS_NORMAL;
      axi4.arregion = `AXI4_REGION_NORMAL;
      axi4.aruser   = '0;
      axi4.arvalid  = 1'b0;
      axi4.rready   = 1'b0;
    end
  endtask

  task automatic issue_write4(input logic [31:0] address);
    begin
      @(negedge clk_i);
      axi4.awaddr  = address;
      axi4.awlen   = 8'd3;
      axi4.awvalid = 1'b1;
      do @(posedge clk_i); while (!axi4.awready);
      @(negedge clk_i);
      axi4.awvalid = 1'b0;
      for (int beat = 0; beat < 4; beat++) begin
        axi4.wdata  = 32'hA500_0000 + beat;
        axi4.wstrb  = 4'hF;
        axi4.wlast  = beat == 3;
        axi4.wvalid = 1'b1;
        do @(posedge clk_i); while (!axi4.wready);
        @(negedge clk_i);
        axi4.wvalid = 1'b0;
      end
      repeat (2) @(posedge clk_i);
      axi4.bready = 1'b1;
      do @(posedge clk_i); while (!axi4.bvalid);
      if (axi4.bresp != `AXI4_RESP_OKAY) $fatal(1, "write burst returned an error");
      @(negedge clk_i);
      axi4.bready = 1'b0;
    end
  endtask

  task automatic issue_read4(input logic [31:0] address);
    begin
      @(negedge clk_i);
      axi4.araddr  = address;
      axi4.arlen   = 8'd3;
      axi4.arvalid = 1'b1;
      do @(posedge clk_i); while (!axi4.arready);
      @(negedge clk_i);
      axi4.arvalid = 1'b0;
      for (int beat = 0; beat < 4; beat++) begin
        if (beat == 1) begin
          repeat (3) @(posedge clk_i);
          @(negedge clk_i);
        end
        axi4.rready = 1'b1;
        do @(posedge clk_i); while (!axi4.rvalid);
        expected = 32'hA500_0000 + beat;
        if (axi4.rdata != expected || axi4.rresp != `AXI4_RESP_OKAY ||
            axi4.rlast != (beat == 3)) begin
          $fatal(1, "read beat %0d mismatch: data=%08x expected=%08x resp=%0d last=%0d", beat,
                 axi4.rdata, expected, axi4.rresp, axi4.rlast);
        end
        @(negedge clk_i);
        axi4.rready = 1'b0;
      end
    end
  endtask

  task automatic issue_illegal_read(input logic [31:0] address);
    integer accesses_before;
    begin
      accesses_before = target_accesses;
      @(negedge clk_i);
      axi4.araddr  = address;
      axi4.arlen   = 8'd16;
      axi4.arvalid = 1'b1;
      do @(posedge clk_i); while (!axi4.arready);
      @(negedge clk_i);
      axi4.arvalid = 1'b0;
      axi4.rready  = 1'b1;
      error_beats  = 0;
      while (error_beats < 17) begin
        @(posedge clk_i);
        if (axi4.rvalid) begin
          if (axi4.rresp != `AXI4_RESP_SLAVE_ERROR || axi4.rlast != (error_beats == 16)) begin
            $fatal(1, "illegal burst response mismatch");
          end
          error_beats = error_beats + 1;
        end
      end
      @(negedge clk_i);
      axi4.rready = 1'b0;
      if (target_accesses != accesses_before) begin
        $fatal(1, "illegal burst reached the RIBP target");
      end
    end
  endtask

  task automatic issue_early_last_write(input logic [31:0] address);
    integer accesses_before;
    begin
      accesses_before = target_accesses;
      @(negedge clk_i);
      axi4.awaddr  = address;
      axi4.awlen   = 8'd3;
      axi4.awvalid = 1'b1;
      do @(posedge clk_i); while (!axi4.awready);
      @(negedge clk_i);
      axi4.awvalid = 1'b0;
      axi4.wdata   = 32'hDEAD_BEEF;
      axi4.wstrb   = 4'hF;
      axi4.wlast   = 1'b1;
      axi4.wvalid  = 1'b1;
      do @(posedge clk_i); while (!axi4.wready);
      @(negedge clk_i);
      axi4.wvalid = 1'b0;
      axi4.bready = 1'b1;
      do @(posedge clk_i); while (!axi4.bvalid);
      if (axi4.bresp != `AXI4_RESP_SLAVE_ERROR) begin
        $fatal(1, "early WLAST did not return SLVERR");
      end
      @(negedge clk_i);
      axi4.bready = 1'b0;
      axi4.wlast  = 1'b0;
      if (target_accesses != accesses_before + 1) begin
        $fatal(1, "early WLAST must commit exactly one RIBP beat");
      end
    end
  endtask

  task automatic issue_read(input logic [31:0] address, input logic [7:0] length);
    integer beat;
    begin
      @(negedge clk_i);
      axi4.araddr  = address;
      axi4.arlen   = length;
      axi4.arvalid = 1'b1;
      do @(posedge clk_i); while (!axi4.arready);
      @(negedge clk_i);
      axi4.arvalid = 1'b0;
      axi4.rready  = 1'b1;
      beat         = 0;
      while (beat <= length) begin
        @(posedge clk_i);
        if (axi4.rvalid) begin
          if (axi4.rresp != `AXI4_RESP_OKAY || axi4.rlast != (beat == length)) begin
            $fatal(1, "performance read response mismatch");
          end
          beat = beat + 1;
        end
      end
      @(negedge clk_i);
      axi4.rready = 1'b0;
    end
  endtask

  task automatic issue_address_pattern_read(input logic [31:0] address, input logic [7:0] length,
                                            input logic [1:0] burst);
    integer        beat;
    logic   [31:0] expected_address;
    logic   [31:0] burst_bytes;
    begin
      burst_bytes = (length + 1) * 4;
      @(negedge clk_i);
      axi4.araddr  = address;
      axi4.arlen   = length;
      axi4.arburst = burst;
      axi4.arvalid = 1'b1;
      do @(posedge clk_i); while (!axi4.arready);
      @(negedge clk_i);
      axi4.arvalid = 1'b0;
      axi4.rready  = 1'b1;
      beat         = 0;
      while (beat <= length) begin
        @(posedge clk_i);
        if (axi4.rvalid) begin
          if (burst == `AXI4_BURST_TYPE_FIXED) begin
            expected_address = address;
          end else begin
            expected_address = (address & ~(burst_bytes - 1)) |
                               ((address + (beat * 4)) & (burst_bytes - 1));
          end
          if (axi4.rdata != memory[expected_address[7:2]] ||
              axi4.rresp != `AXI4_RESP_OKAY || axi4.rlast != (beat == length)) begin
            $fatal(1, "address pattern mismatch beat=%0d addr=%08x data=%08x", beat,
                   expected_address, axi4.rdata);
          end
          beat = beat + 1;
        end
      end
      @(negedge clk_i);
      axi4.rready  = 1'b0;
      axi4.arburst = `AXI4_BURST_TYPE_INCR;
    end
  endtask

  initial begin
    init_axi4();
    for (int index = 0; index < 64; index++) memory[index] = '0;
    repeat (4) @(posedge clk_i);
    rst_n_i = 1'b1;
    issue_write4(32'h0000_0040);
    issue_read4(32'h0000_0040);
    for (int index = 0; index < 64; index++) memory[index] = 32'h5000_0000 + index;
    issue_address_pattern_read(32'h0000_0020, 8'd3, `AXI4_BURST_TYPE_FIXED);
    issue_address_pattern_read(32'h0000_002C, 8'd3, `AXI4_BURST_TYPE_WRAP);
    issue_illegal_read(32'h0000_0080);
    issue_early_last_write(32'h0000_00C0);
    burst_cycles = cycle_count;
    issue_read(32'h0000_0000, 8'd15);
    burst_cycles  = cycle_count - burst_cycles;
    single_cycles = cycle_count;
    for (int index = 0; index < 16; index++) begin
      issue_read(32'(index * 4), 8'd0);
    end
    single_cycles = cycle_count - single_cycles;
    if ((burst_cycles * 5) > (single_cycles * 4)) begin
      $fatal(1, "16-beat burst improvement is below 20%%: burst=%0d single=%0d", burst_cycles,
             single_cycles);
    end
    if (target_accesses != 49) $fatal(1, "unexpected RIBP access count");
    $display("AXI4 to RIBP burst bridge test passed");
    $finish;
  end
endmodule
