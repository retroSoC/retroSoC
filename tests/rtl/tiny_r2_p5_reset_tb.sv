`timescale 1ns / 1ps

module tiny_r2_p5_reset_tb;
  logic clk_i = 0;
  logic rst_n_i = 0;
  logic target_rst_n[23];
  always #5 clk_i = !clk_i;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) masters[3] (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) targets[23] (
      .aclk   (clk_i),
      .aresetn(target_rst_n)
  );
  logic [5:0] fault_valid, fault_instruction;
  logic [ 5:0][31:0] fault_addr;
  logic [ 5:0][ 1:0] fault_resp;
  logic [ 2:0]       owner_idle;
  logic [22:0]       target_idle;
  logic [63:0] cpu_wait, dma_wait;
  logic hold_address[23];
  logic hold_read   [23];
  logic hold_write  [23];
  logic hold_b      [23];
  logic [2:0] arvalid = '0, rready = '0, awvalid = '0, wvalid = '0, bready = '0;
  logic [2:0][31:0] araddr = '0, awaddr = '0, wdata = '0;
  logic [2:0][7:0] arlen = '0, awlen = '0;
  logic [2:0][2:0] arsize = '0, awsize = '0;
  logic [2:0][1:0] arburst = '0, awburst = '0;
  logic [2:0] arlock = '0, awlock = '0;
  logic [2:0] arid = '0, awid = '0;
  logic [2:0][3:0] wstrb = '0;
  logic [2:0]      wlast = '0;
  logic [2:0][2:0] arprot = '0;
  logic [2:0] arready, awready, rvalid, bvalid;
  logic [2:0][1:0] rresp, bresp;
  logic [2:0] rlast;

  tiny_axi4_fabric u_dut (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .target_rst_n_i     (target_rst_n),
      .perf_enable_i      (1'b0),
      .perf_clear_i       (1'b0),
      .masters            (masters),
      .targets            (targets),
      .fault_valid_o      (fault_valid),
      .fault_addr_o       (fault_addr),
      .fault_resp_o       (fault_resp),
      .fault_instruction_o(fault_instruction),
      .owner_idle_o       (owner_idle),
      .target_idle_o      (target_idle),
      .cpu_wait_o         (cpu_wait),
      .dma_wait_o         (dma_wait)
  );

  for (genvar owner = 0; owner < 3; owner++) begin : gen_master
    assign masters[owner].araddr   = araddr[owner];
    assign masters[owner].arlen    = arlen[owner];
    assign masters[owner].arsize   = arsize[owner];
    assign masters[owner].arburst  = arburst[owner];
    assign masters[owner].arlock   = arlock[owner];
    assign masters[owner].arid     = arid[owner];
    assign masters[owner].arvalid  = arvalid[owner];
    assign masters[owner].arprot   = arprot[owner];
    assign masters[owner].awaddr   = awaddr[owner];
    assign masters[owner].awlen    = awlen[owner];
    assign masters[owner].awsize   = awsize[owner];
    assign masters[owner].awburst  = awburst[owner];
    assign masters[owner].awlock   = awlock[owner];
    assign masters[owner].awid     = awid[owner];
    assign masters[owner].awvalid  = awvalid[owner];
    assign masters[owner].wdata    = wdata[owner];
    assign masters[owner].wstrb    = wstrb[owner];
    assign masters[owner].wlast    = wlast[owner];
    assign masters[owner].wvalid   = wvalid[owner];
    assign masters[owner].rready   = rready[owner];
    assign masters[owner].bready   = bready[owner];
    assign masters[owner].arcache  = '0;
    assign masters[owner].arqos    = '0;
    assign masters[owner].arregion = '0;
    assign masters[owner].aruser   = '0;
    assign masters[owner].awcache  = '0;
    assign masters[owner].awprot   = '0;
    assign masters[owner].awqos    = '0;
    assign masters[owner].awregion = '0;
    assign masters[owner].awuser   = '0;
    assign masters[owner].wuser    = '0;
    assign arready[owner]          = masters[owner].arready;
    assign awready[owner]          = masters[owner].awready;
    assign rvalid[owner]           = masters[owner].rvalid;
    assign rresp[owner]            = masters[owner].rresp;
    assign rlast[owner]            = masters[owner].rlast;
    assign bvalid[owner]           = masters[owner].bvalid;
    assign bresp[owner]            = masters[owner].bresp;
  end

  for (genvar target = 0; target < 23; target++) begin : gen_target
    tiny_r2_p5_reset_target_model u_model (
        .clk_i         (clk_i),
        .rst_n_i       (target_rst_n[target]),
        .hold_address_i(hold_address[target]),
        .hold_read_i   (hold_read[target]),
        .hold_write_i  (hold_write[target]),
        .hold_b_i      (hold_b[target]),
        .axi4          (targets[target])
    );
  end

  task automatic reset_read(input logic [31:0] address, input int target);
    @(negedge clk_i);
    araddr[0]  = address;
    arlen[0]   = 0;
    arsize[0]  = 2;
    arburst[0] = 1;
    arid[0]    = 0;
    arvalid[0] = 1;
    do @(posedge clk_i); while (!arready[0]);
    @(negedge clk_i);
    arvalid[0] = 0;
    repeat (2) @(posedge clk_i);
    if (owner_idle[0] || target_idle[target]) $fatal(1, "read was not retained");
    target_rst_n[target] = 0;
    do @(posedge clk_i); while (!rvalid[0]);
    if (rresp[0] != 2'b11 || !rlast[0]) $fatal(1, "reset read did not terminate with DECERR");
    rready[0] = 1;
    @(posedge clk_i);
    @(negedge clk_i);
    rready[0]            = 0;
    target_rst_n[target] = 1;
    repeat (2) @(posedge clk_i);
    if (!owner_idle[0]) $fatal(1, "read credit was not released after reset");
  endtask

  task automatic reset_write(input logic [31:0] address, input int target);
    @(negedge clk_i);
    awaddr[1]  = address;
    awlen[1]   = 0;
    awsize[1]  = 2;
    awburst[1] = 1;
    awid[1]    = 1;
    awvalid[1] = 1;
    do @(posedge clk_i); while (!awready[1]);
    @(negedge clk_i);
    awvalid[1] = 0;
    repeat (2) @(posedge clk_i);
    if (owner_idle[1] || target_idle[target]) $fatal(1, "write was not retained");
    target_rst_n[target] = 0;
    do @(posedge clk_i); while (!bvalid[1]);
    if (bresp[1] != 2'b11) $fatal(1, "reset write did not terminate with DECERR");
    bready[1] = 1;
    @(posedge clk_i);
    @(negedge clk_i);
    bready[1]            = 0;
    target_rst_n[target] = 1;
    repeat (2) @(posedge clk_i);
    if (!owner_idle[1]) $fatal(1, "write credit was not released after reset");
  endtask

  task automatic reset_buffered_read;
    @(negedge clk_i);
    araddr[0]  = 32'h30000000;
    arlen[0]   = 0;
    arsize[0]  = 2;
    arburst[0] = 1;
    arid[0]    = 0;
    arvalid[0] = 1;
    do @(posedge clk_i); while (!arready[0]);
    @(negedge clk_i);
    arvalid[0] = 0;
    do @(posedge clk_i); while (!rvalid[0]);
    if (rresp[0] != 2'b00) $fatal(1, "buffered read did not reach response spill");
    target_rst_n[0] = 0;
    do @(posedge clk_i); while (!rvalid[0]);
    if (rresp[0] != 2'b11 || !rlast[0]) $fatal(1, "buffered response was replayed after reset");
    rready[0] = 1;
    @(posedge clk_i);
    @(negedge clk_i);
    rready[0]       = 0;
    target_rst_n[0] = 1;
    repeat (2) @(posedge clk_i);
    if (!owner_idle[0]) $fatal(1, "buffered read credit was not released after reset");
  endtask

  initial begin
    for (integer target = 0; target < 23; target++) begin
      target_rst_n[target] = 0;
      hold_address[target] = 0;
      hold_read[target]    = 0;
      hold_write[target]   = 0;
      hold_b[target]       = 0;
    end
    hold_read[0]   = 1;
    hold_write[12] = 1;
    repeat (4) @(negedge clk_i);
    rst_n_i = 1;
    for (integer target = 0; target < 23; target++) target_rst_n[target] = 1;
    reset_read(32'h30000000, 0);
    hold_read[0] = 0;
    reset_buffered_read();
    reset_write(32'h10009000, 12);
    if (fault_valid != 0) $fatal(1, "fault pulse was not consumed");
    $display("SIM_TEST_PASS Tiny P5 target reset isolation");
    $finish;
  end
  initial begin
    repeat (2000) @(posedge clk_i);
    $fatal(1, "SIM_TEST_TIMEOUT Tiny P5 target reset isolation");
  end
endmodule

module tiny_r2_p5_reset_target_model (
    input logic         clk_i,
    input logic         rst_n_i,
    input logic         hold_address_i,
    input logic         hold_read_i,
    input logic         hold_write_i,
    input logic         hold_b_i,
          axi4_if.slave axi4
);
  logic        active = 0;
  logic        writing = 0;
  logic        write_done = 0;
  logic        id = 0;
  logic [31:0] address = 0;
  logic [ 7:0] length = 0;
  logic [ 7:0] beat = 0;

  assign axi4.arready = !active && !hold_address_i && rst_n_i;
  assign axi4.awready = !active && !hold_address_i && !axi4.arvalid && rst_n_i;
  assign axi4.wready  = active && writing && !write_done && !hold_write_i && rst_n_i;
  assign axi4.ruser   = 0;
  assign axi4.buser   = 0;

  always @(posedge clk_i) begin
    if (!rst_n_i) begin
      active      <= 0;
      writing     <= 0;
      write_done  <= 0;
      axi4.rvalid <= 0;
      axi4.bvalid <= 0;
      axi4.rdata  <= 0;
      axi4.rresp  <= 0;
      axi4.rlast  <= 0;
      axi4.rid    <= 0;
      axi4.bid    <= 0;
      axi4.bresp  <= 0;
    end else begin
      if (axi4.arvalid && axi4.arready) begin
        active  <= 1;
        writing <= 0;
        address <= axi4.araddr;
        length  <= axi4.arlen;
        beat    <= 0;
        id      <= axi4.arid;
      end
      if (axi4.awvalid && axi4.awready) begin
        active     <= 1;
        writing    <= 1;
        write_done <= 0;
        address    <= axi4.awaddr;
        length     <= axi4.awlen;
        beat       <= 0;
        id         <= axi4.awid;
      end
      if (active && !writing && !axi4.rvalid && !hold_read_i) begin
        axi4.rvalid <= 1;
        axi4.rid    <= id;
        axi4.rdata  <= 32'h10000000 ^ address;
        axi4.rresp  <= 0;
        axi4.rlast  <= beat == length;
      end
      if (axi4.rvalid && axi4.rready) begin
        axi4.rvalid <= 0;
        active      <= 0;
      end
      if (axi4.wvalid && axi4.wready) begin
        write_done <= 1;
      end
      if (active && writing && write_done && !hold_b_i) begin
        axi4.bvalid <= 1;
        axi4.bid    <= id;
        axi4.bresp  <= 0;
      end
      if (axi4.bvalid && axi4.bready) begin
        axi4.bvalid <= 0;
        active      <= 0;
      end
    end
  end
endmodule
