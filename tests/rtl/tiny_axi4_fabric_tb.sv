`timescale 1ns / 1ps
module tiny_axi4_fabric_tb;
  logic clk_i = 0;
  logic rst_n_i = 0;
  always #5 clk_i = !clk_i;
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) masters[2] (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) targets[5] (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  logic fault_valid, fault_master, fault_write;
  logic [31:0] fault_addr;
  logic [ 1:0] fault_resp;
  logic [63:0] cpu_wait, dma_wait;
  integer             faults = 0;
  integer             completions    [2];
  integer             target_requests[5];
  logic   [1:0][31:0] awaddr;
  logic   [1:0][ 7:0] awlen;
  logic   [1:0][ 2:0] awsize;
  logic   [1:0][ 1:0] awburst;
  logic   [1:0][ 0:0] awlock;
  logic   [1:0][ 0:0] awid;
  logic   [1:0][ 0:0] awvalid;
  logic   [1:0][31:0] wdata;
  logic   [1:0][ 3:0] wstrb;
  logic   [1:0][ 0:0] wlast;
  logic   [1:0][ 0:0] wvalid;
  logic   [1:0][ 0:0] bready;
  logic   [1:0][31:0] araddr;
  logic   [1:0][ 7:0] arlen;
  logic   [1:0][ 2:0] arsize;
  logic   [1:0][ 1:0] arburst;
  logic   [1:0][ 0:0] arlock;
  logic   [1:0][ 0:0] arid;
  logic   [1:0][ 0:0] arvalid;
  logic   [1:0][ 0:0] rready;
  logic   [1:0][ 0:0] awready;
  logic   [1:0][ 0:0] arready;
  logic   [1:0][ 0:0] wready;
  logic   [1:0][ 0:0] bvalid;
  logic   [1:0][ 0:0] bid;
  logic   [1:0][ 1:0] bresp;
  logic   [1:0][ 0:0] rvalid;
  logic   [1:0][ 0:0] rid;
  logic   [1:0][ 0:0] rlast;
  logic   [1:0][31:0] rdata;
  logic   [1:0][ 1:0] rresp;
  tiny_axi4_fabric u_dut (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .perf_enable_i (1'b1),
      .perf_clear_i  (1'b0),
      .masters       (masters),
      .targets       (targets),
      .fault_valid_o (fault_valid),
      .fault_addr_o  (fault_addr),
      .fault_master_o(fault_master),
      .fault_write_o (fault_write),
      .fault_resp_o  (fault_resp),
      .cpu_wait_o    (cpu_wait),
      .dma_wait_o    (dma_wait)
  );
  always @(posedge clk_i) if (fault_valid) faults <= faults + 1;
  for (genvar m = 0; m < 2; m++) begin : gen_master
    assign masters[m].awaddr   = awaddr[m];
    assign masters[m].awlen    = awlen[m];
    assign masters[m].awsize   = awsize[m];
    assign masters[m].awburst  = awburst[m];
    assign masters[m].awlock   = awlock[m];
    assign masters[m].awid     = awid[m];
    assign masters[m].awvalid  = awvalid[m];
    assign masters[m].wdata    = wdata[m];
    assign masters[m].wstrb    = wstrb[m];
    assign masters[m].wlast    = wlast[m];
    assign masters[m].wvalid   = wvalid[m];
    assign masters[m].bready   = bready[m];
    assign masters[m].araddr   = araddr[m];
    assign masters[m].arlen    = arlen[m];
    assign masters[m].arsize   = arsize[m];
    assign masters[m].arburst  = arburst[m];
    assign masters[m].arlock   = arlock[m];
    assign masters[m].arid     = arid[m];
    assign masters[m].arvalid  = arvalid[m];
    assign masters[m].rready   = rready[m];
    assign awready[m]          = masters[m].awready;
    assign arready[m]          = masters[m].arready;
    assign wready[m]           = masters[m].wready;
    assign bvalid[m]           = masters[m].bvalid;
    assign bid[m]              = masters[m].bid;
    assign bresp[m]            = masters[m].bresp;
    assign rvalid[m]           = masters[m].rvalid;
    assign rid[m]              = masters[m].rid;
    assign rlast[m]            = masters[m].rlast;
    assign rdata[m]            = masters[m].rdata;
    assign rresp[m]            = masters[m].rresp;
    assign masters[m].awcache  = '0;
    assign masters[m].awprot   = '0;
    assign masters[m].awqos    = '0;
    assign masters[m].awregion = '0;
    assign masters[m].awuser   = '0;
    assign masters[m].arcache  = '0;
    assign masters[m].arprot   = '0;
    assign masters[m].arqos    = '0;
    assign masters[m].arregion = '0;
    assign masters[m].aruser   = '0;
    assign masters[m].wuser    = '0;
  end
  for (genvar t = 0; t < 5; t++) begin : gen_target
    // Deterministic terminal responder allows independent checks of routing,
    // burst length and ID preservation without sharing the fabric decoder.
    axi4_error_slave #(
        .Response(t == 3 ? 2'b11 : (t == 4 ? 2'b10 : 2'b00))
    ) u_response (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .axi4   (targets[t])
    );
    initial target_requests[t] = 0;
    always @(posedge clk_i) begin
      if ((targets[t].arvalid && targets[t].arready) || (targets[t].awvalid && targets[t].awready))
        target_requests[t] <= target_requests[t] + 1;
    end
  end
  task automatic read_request(input int m, input logic [31:0] addr, input int beats,
                              input logic [2:0] size, input logic [1:0] burst,
                              input logic [1:0] expected);
    logic [35:0] held;
    @(negedge clk_i);
    araddr[m]  = addr;
    arlen[m]   = 8'(beats - 1);
    arsize[m]  = size;
    arburst[m] = burst;
    arid[m]    = 1'(m);
    arvalid[m] = 1;
    do @(posedge clk_i); while (!arready[m]);
    @(negedge clk_i);
    arvalid[m] = 0;
    for (int beat = 0; beat < beats; beat++) begin
      do @(posedge clk_i); while (!rvalid[m]);
      held = {rid[m], rlast[m], rresp[m], rdata[m]};
      repeat (3) begin
        @(negedge clk_i);
        if (!rvalid[m] || held != {rid[m], rlast[m], rresp[m], rdata[m]})
          $fatal(1, "read changed under backpressure");
      end
      if (rresp[m] != expected || rid[m] != 1'(m) || rlast[m] != (beat == beats - 1))
        $fatal(
            1,
            "read response/ID/length mismatch m=%0d addr=%x beat=%0d resp=%0d",
            m,
            addr,
            beat,
            rresp[m]
        );
      rready[m] = 1;
      @(posedge clk_i);
      @(negedge clk_i);
      rready[m] = 0;
    end
    completions[m]++;
  endtask
  task automatic write_request(input int m, input logic [31:0] addr, input int beats,
                               input logic [1:0] expected, input bit early_w);
    @(negedge clk_i);
    awaddr[m]  = addr;
    awlen[m]   = 8'(beats - 1);
    awsize[m]  = 2;
    awburst[m] = 1;
    awid[m]    = 1'(m);
    wdata[m]   = 32'h12345678;
    wstrb[m]   = 4'b0101;
    wlast[m]   = (beats == 1);
    if (early_w) begin
      wvalid[m] = 1;
      repeat (4) begin
        @(posedge clk_i);
        if (wready[m]) $fatal(1, "W accepted before AW");
      end
      @(negedge clk_i);
    end
    awvalid[m] = 1;
    do @(posedge clk_i); while (!awready[m]);
    @(negedge clk_i);
    awvalid[m] = 0;
    if (!early_w) repeat (5) @(negedge clk_i);
    for (int beat = 0; beat < beats; beat++) begin
      wvalid[m] = 1;
      wlast[m]  = (beat == beats - 1);
      wdata[m]  = 32'(beat);
      do @(posedge clk_i); while (!wready[m]);
      @(negedge clk_i);
      wvalid[m] = 0;
      repeat (2) @(negedge clk_i);
    end
    do @(posedge clk_i); while (!bvalid[m]);
    repeat (3) begin
      @(negedge clk_i);
      if (!bvalid[m] || bresp[m] != expected || bid[m] != 1'(m))
        $fatal(1, "write response mismatch");
    end
    bready[m] = 1;
    @(posedge clk_i);
    @(negedge clk_i);
    bready[m] = 0;
    completions[m]++;
  endtask
  initial begin
    awaddr         = '0;
    awlen          = '0;
    awsize         = '0;
    awburst        = '0;
    awlock         = '0;
    awid           = '0;
    awvalid        = '0;
    wdata          = '0;
    wstrb          = '0;
    wlast          = '0;
    wvalid         = '0;
    bready         = '0;
    araddr         = '0;
    arlen          = '0;
    arsize         = '0;
    arburst        = '0;
    arlock         = '0;
    arid           = '0;
    arvalid        = '0;
    rready         = '0;
    completions[0] = 0;
    completions[1] = 0;
    repeat (5) @(negedge clk_i);
    rst_n_i = 1;
    fork
      begin
        write_request(0, 32'h30000000, 16, 0, 1);
        read_request(0, 32'h30000000, 16, 2, 1, 0);
        read_request(0, 32'h38000000, 4, 2, 1, 3);
        read_request(0, 32'h30000ffc, 2, 2, 1, 2);
        read_request(0, 32'h30000001, 1, 2, 1, 2);
        read_request(0, 32'h10001000, 2, 2, 1, 2);
        read_request(0, 32'h30000000, 4, 2, 2, 2);
      end
      begin
        read_request(1, 32'h50000000, 4, 2, 1, 0);
        write_request(1, 32'h10001000, 1, 0, 0);
        write_request(1, 32'h38000000, 3, 3, 1);
        read_request(1, 32'h10001000, 1, 2, 0, 0);
        read_request(1, 32'h3001ffff, 1, 0, 1, 0);
        read_request(1, 32'h30020000, 1, 2, 1, 3);
      end
    join
    if (completions[0]!=7 || completions[1]!=6 || faults!=7 ||
        target_requests[0]!=3 || target_requests[1]!=1 || target_requests[2]!=2 ||
        target_requests[3]!=3 || target_requests[4]!=4 || cpu_wait==0 || dma_wait==0)
      $fatal(1, "accounting/fairness mismatch faults=%0d", faults);
    read_request(0, 32'h30000000, 1, 2, 1, 0);
    $display("SIM_TEST_PASS Tiny fabric");
    $finish;
  end
  initial begin
    repeat (20000) @(posedge clk_i);
    $fatal(1, "SIM_TEST_TIMEOUT Tiny fabric");
  end
endmodule
