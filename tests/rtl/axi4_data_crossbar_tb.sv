`timescale 1ns / 1ps

module axi4_data_crossbar_tb;
  localparam int NumMasters = 8;
  localparam int NumTargets = 6;

  logic        clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        idle_o;
  logic [ 7:0] outstanding_read_o;
  logic [ 7:0] outstanding_write_o;
  logic        fault_valid_o;
  logic [ 2:0] fault_master_o;
  logic [ 2:0] fault_target_o;
  logic [31:0] fault_addr_o;
  logic        fault_write_o;
  logic [ 3:0] fault_reason_o;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (6),
      .USER_WIDTH(1)
  ) masters[NumMasters] (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (6),
      .USER_WIDTH(1)
  ) targets[NumTargets] (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  always #5 clk_i = ~clk_i;

  initial begin
    repeat (500) @(posedge clk_i);
    $fatal(1, "AXI4 data crossbar test timed out");
  end

  axi4_data_crossbar u_dut (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .block_new_i        (1'b0),
      .recovery_i         (1'b0),
      .mem_pad_mode_i     (2'd1),
      .ext_h_read_base_i  (32'h3000_0000),
      .ext_h_read_limit_i (32'h4FFF_FFFF),
      .ext_h_write_base_i (32'h3000_0000),
      .ext_h_write_limit_i(32'h4FFF_FFFF),
      .masters            (masters),
      .targets            (targets),
      .idle_o             (idle_o),
      .outstanding_read_o (outstanding_read_o),
      .outstanding_write_o(outstanding_write_o),
      .fault_valid_o      (fault_valid_o),
      .fault_master_o     (fault_master_o),
      .fault_target_o     (fault_target_o),
      .fault_addr_o       (fault_addr_o),
      .fault_write_o      (fault_write_o),
      .fault_reason_o     (fault_reason_o)
  );

  task automatic issue_master1_read(input logic [5:0] id, input logic [31:0] addr);
    begin
      @(negedge clk_i);
      masters[1].arid    = id;
      masters[1].araddr  = addr;
      masters[1].arvalid = 1'b1;
      do @(posedge clk_i); while (!masters[1].arready);
      @(negedge clk_i);
      masters[1].arvalid = 1'b0;
    end
  endtask

  task automatic return_target0_read(input logic [5:0] id, input logic [63:0] data);
    begin
      @(negedge clk_i);
      targets[0].rid    = id;
      targets[0].rdata  = data;
      targets[0].rresp  = 2'b00;
      targets[0].rlast  = 1'b1;
      targets[0].rvalid = 1'b1;
      do @(posedge clk_i); while (!targets[0].rready);
      @(negedge clk_i);
      targets[0].rvalid = 1'b0;
    end
  endtask

  task automatic return_target1_read(input logic [5:0] id, input logic [63:0] data);
    begin
      @(negedge clk_i);
      targets[1].rid    = id;
      targets[1].rdata  = data;
      targets[1].rresp  = 2'b00;
      targets[1].rlast  = 1'b1;
      targets[1].rvalid = 1'b1;
      do @(posedge clk_i); while (!targets[1].rready);
      @(negedge clk_i);
      targets[1].rvalid = 1'b0;
    end
  endtask

  `define INIT_MASTER(index)                       \
    masters[index].awid = '0;                      \
    masters[index].awaddr = '0;                    \
    masters[index].awlen = '0;                     \
    masters[index].awsize = 3'd3;                  \
    masters[index].awburst = 2'b01;                \
    masters[index].awlock = 1'b0;                  \
    masters[index].awcache = '0;                   \
    masters[index].awprot = '0;                    \
    masters[index].awqos = '0;                     \
    masters[index].awregion = '0;                  \
    masters[index].awuser = '0;                    \
    masters[index].awvalid = 1'b0;                 \
    masters[index].wdata = '0;                     \
    masters[index].wstrb = '0;                     \
    masters[index].wlast = 1'b1;                   \
    masters[index].wuser = '0;                     \
    masters[index].wvalid = 1'b0;                  \
    masters[index].bready = 1'b1;                  \
    masters[index].arid = '0;                      \
    masters[index].araddr = '0;                    \
    masters[index].arlen = '0;                     \
    masters[index].arsize = 3'd3;                  \
    masters[index].arburst = 2'b01;                \
    masters[index].arlock = 1'b0;                  \
    masters[index].arcache = '0;                   \
    masters[index].arprot = '0;                    \
    masters[index].arqos = '0;                     \
    masters[index].arregion = '0;                  \
    masters[index].aruser = '0;                    \
    masters[index].arvalid = 1'b0;                 \
    masters[index].rready = 1'b1;

  `define INIT_TARGET(index)                       \
    targets[index].awready = 1'b1;                 \
    targets[index].wready = 1'b1;                  \
    targets[index].bid = '0;                       \
    targets[index].bresp = '0;                     \
    targets[index].buser = '0;                     \
    targets[index].bvalid = 1'b0;                  \
    targets[index].arready = 1'b1;                 \
    targets[index].rid = '0;                       \
    targets[index].rdata = '0;                     \
    targets[index].rresp = '0;                     \
    targets[index].rlast = 1'b1;                   \
    targets[index].ruser = '0;                     \
    targets[index].rvalid = 1'b0;

  initial begin
    `INIT_MASTER(0)
    `INIT_MASTER(1)
    `INIT_MASTER(2)
    `INIT_MASTER(3)
    `INIT_MASTER(4)
    `INIT_MASTER(5)
    `INIT_MASTER(6)
    `INIT_MASTER(7)
    `INIT_TARGET(0)
    `INIT_TARGET(1)
    `INIT_TARGET(2)
    `INIT_TARGET(3)
    `INIT_TARGET(4)
    `INIT_TARGET(5)

    repeat (3) @(posedge clk_i);
    rst_n_i = 1'b1;

    issue_master1_read(6'b001_000, 32'h3000_0000);
    issue_master1_read(6'b001_001, 32'h3800_0000);
    if (outstanding_read_o != 8'd2 || idle_o) begin
      $fatal(1, "different-target reads were not tracked concurrently");
    end

    @(negedge clk_i);
    masters[1].arid    = 6'b001_000;
    masters[1].araddr  = 32'h4000_0000;
    masters[1].arvalid = 1'b1;
    #1;
    if (masters[1].arready) $fatal(1, "same source ID was accepted before completion");
    masters[1].arvalid = 1'b0;

    fork
      return_target1_read(6'b001_001, 64'h2222_2222_2222_2222);
      begin
        wait (masters[1].rvalid);
        if ((masters[1].rid != 6'b001_001) || (masters[1].rdata != 64'h2222_2222_2222_2222)) begin
          $fatal(1, "out-of-order different-ID response was misrouted");
        end
      end
    join
    return_target0_read(6'b001_000, 64'h1111_1111_1111_1111);
    @(negedge clk_i);
    if (!idle_o || (outstanding_read_o != 8'd0)) begin
      $fatal(1, "read completion did not drain the crossbar");
    end

    @(negedge clk_i);
    masters[6].arid    = 6'b110_000;
    masters[6].araddr  = 32'h3000_0000;
    masters[6].arvalid = 1'b1;
    do @(posedge clk_i); while (!masters[6].arready);
    #1;
    if (!fault_valid_o || (fault_master_o != 3'd6) ||
        (fault_reason_o != 4'd3) || fault_write_o) begin
      $fatal(1, "reserved-master ACL fault attribution mismatch");
    end
    @(negedge clk_i);
    masters[6].arvalid = 1'b0;
    targets[5].rid     = 6'b110_000;
    targets[5].rresp   = 2'b10;
    targets[5].rlast   = 1'b1;
    targets[5].rvalid  = 1'b1;
    do @(posedge clk_i); while (!targets[5].rready);
    @(negedge clk_i);
    targets[5].rvalid = 1'b0;

    $display("AXI4 data crossbar concurrency and ACL test passed");
    $finish;
  end

  `undef INIT_MASTER
  `undef INIT_TARGET
endmodule
