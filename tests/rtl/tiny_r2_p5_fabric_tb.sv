`timescale 1ns / 1ps
module tiny_r2_p5_fabric_tb;
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
      .aresetn(rst_n_i)
  );
  logic [5:0] fault_valid, fault_instruction;
  logic [5:0][31:0] fault_addr;
  logic [5:0][ 1:0] fault_resp;
  logic [63:0] cpu_wait, dma_wait;
  integer faults = 0;
  logic [22:0] hold_address = '0, hold_read = '0, hold_write = '0, hold_b = '0;
  integer              error_beat              [23];
  logic   [ 2:0]       error_last_wait = '0;
  logic                release_error = 0;
  integer              simultaneous_faults = 0;
  logic   [31:0]       seed = 32'h12345678;
  integer              completions             [ 3];
  integer              target_requests         [23];
  logic   [ 2:0][31:0] awaddr;
  logic   [ 2:0][ 7:0] awlen;
  logic   [ 2:0][ 2:0] awsize;
  logic   [ 2:0][ 1:0] awburst;
  logic   [ 2:0][ 0:0] awlock;
  logic   [ 2:0][ 0:0] awid;
  logic   [ 2:0][ 0:0] awvalid;
  logic   [ 2:0][31:0] wdata;
  logic   [ 2:0][ 3:0] wstrb;
  logic   [ 2:0][ 0:0] wlast;
  logic   [ 2:0][ 0:0] wvalid;
  logic   [ 2:0][ 0:0] bready;
  logic   [ 2:0][31:0] araddr;
  logic   [ 2:0][ 7:0] arlen;
  logic   [ 2:0][ 2:0] arsize;
  logic   [ 2:0][ 1:0] arburst;
  logic   [ 2:0][ 0:0] arlock;
  logic   [ 2:0][ 0:0] arid;
  logic   [ 2:0][ 0:0] arvalid;
  logic   [ 2:0][ 2:0] arprot;
  logic   [ 2:0][ 0:0] rready;
  logic   [ 2:0][ 0:0] awready;
  logic   [ 2:0][ 0:0] arready;
  logic   [ 2:0][ 0:0] wready;
  logic   [ 2:0][ 0:0] bvalid;
  logic   [ 2:0][ 0:0] bid;
  logic   [ 2:0][ 1:0] bresp;
  logic   [ 2:0][ 0:0] rvalid;
  logic   [ 2:0][ 0:0] rid;
  logic   [ 2:0][ 0:0] rlast;
  logic   [ 2:0][31:0] rdata;
  logic   [ 2:0][ 1:0] rresp;
  tiny_axi4_fabric u_dut (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .target_rst_n_i     (target_rst_n),
      .perf_enable_i      (1'b1),
      .perf_clear_i       (1'b0),
      .masters            (masters),
      .targets            (targets),
      .fault_valid_o      (fault_valid),
      .fault_addr_o       (fault_addr),
      .fault_instruction_o(fault_instruction),
      .owner_idle_o       (),
      .target_idle_o      (),
      .fault_resp_o       (fault_resp),
      .cpu_wait_o         (cpu_wait),
      .dma_wait_o         (dma_wait)
  );
  for (genvar target = 0; target < 23; target++) begin : gen_target_reset
    assign target_rst_n[target] = rst_n_i;
  end
  always @(posedge clk_i) begin
    faults <= faults + $countones(fault_valid);
    if (fault_valid[2] && fault_valid[4]) begin
      simultaneous_faults <= simultaneous_faults + 1;
      if (fault_addr[2] != 32'h30000004 || fault_addr[4] != 32'h30008004 ||
          fault_resp[2] != 2 || fault_resp[4] != 2)
        $fatal(1, "first nonfinal error metadata lost");
    end
  end
  for (genvar m = 0; m < 3; m++) begin : gen_master
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
    assign masters[m].arprot   = arprot[m];
    assign masters[m].arqos    = '0;
    assign masters[m].arregion = '0;
    assign masters[m].aruser   = '0;
    assign masters[m].wuser    = '0;
  end
  for (genvar t = 0; t < 23; t++) begin : gen_target
    tiny_p5_target_model #(
        .ErrorResponse(t == 21 ? 3 : (t == 22 ? 2 : 0))
    ) u_response (
        .clk_i         (clk_i),
        .rst_n_i       (rst_n_i),
        .hold_address_i(hold_address[t]),
        .hold_read_i   (hold_read[t]),
        .hold_write_i  (hold_write[t]),
        .hold_b_i      (hold_b[t]),
        .error_beat_i  (error_beat[t]),
        .axi4          (targets[t])
    );
    initial begin
      target_requests[t] = 0;
      error_beat[t]      = -1;
    end
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
    araddr[m]  = 32'hbad00000;  // The accepted address, not live pins, owns responses.
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
      if (expected == 0 && rdata[m] !== (32'h10000000 ^ (addr + (32'(beat) << size))))
        $fatal(1, "read data routed from wrong target/beat");
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
    wdata[m]   = 32'hb0000000 ^ addr;
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
    awaddr[m]  = 32'hbad08000;
    if (!early_w) repeat (5) @(negedge clk_i);
    for (int beat = 0; beat < beats; beat++) begin
      wvalid[m] = 1;
      wlast[m]  = (beat == beats - 1);
      wdata[m]  = 32'hb0000000 ^ addr ^ 32'(beat);
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

  task automatic mixed_error_read(input int m, input logic [31:0] address);
    @(negedge clk_i);
    araddr[m]  = address;
    arlen[m]   = 3;
    arsize[m]  = 2;
    arburst[m] = 1;
    arvalid[m] = 1;
    arid[m]    = 1'(m);
    do @(posedge clk_i); while (!arready[m]);
    @(negedge clk_i);
    arvalid[m] = 0;
    for (integer beat = 0; beat < 4; beat++) begin
      wait (rvalid[m]);
      if (beat == 3) begin
        error_last_wait[m] = 1;
        wait (release_error);
      end
      @(negedge clk_i);
      if (rresp[m] != (beat == 1 ? 2 : 0) || rlast[m] != (beat == 3))
        $fatal(1, "mixed read response was altered");
      rready[m] = 1;
      @(posedge clk_i);
      @(negedge clk_i);
      rready[m] = 0;
    end
  endtask
  task automatic random_reads(input int m, input logic [31:0] initial_seed);
    logic   [31:0] state;
    logic   [31:0] address;
    integer        beats;
    state = initial_seed;
    for (integer n = 0; n < 32; n++) begin
      state   = state ^ (state << 13);
      state   = state ^ (state >> 17);
      state   = state ^ (state << 5);
      address = 32'h30000000 + (state % 4) * 32768 + ((state >> 4) % 16) * 64;
      beats   = 1 + integer'((state >> 12) % 16);
      read_request(m, address, beats, 2, 1, 0);
    end
  endtask
  initial begin
    awaddr  = '0;
    awlen   = '0;
    awsize  = '0;
    awburst = '0;
    awlock  = '0;
    awid    = '0;
    awvalid = '0;
    wdata   = '0;
    wstrb   = '0;
    wlast   = '0;
    wvalid  = '0;
    bready  = '0;
    araddr  = '0;
    arlen   = '0;
    arsize  = '0;
    arburst = '0;
    arlock  = '0;
    arid    = '0;
    arvalid = '0;
    arprot  = '0;
    rready  = '0;
    for (integer m = 0; m < 3; m++) completions[m] = 0;
    repeat (5) @(negedge clk_i);
    rst_n_i      = 1;
    // XPI can withhold its first response indefinitely without owning APB/SRAM.
    hold_read[4] = 1;
    fork
      read_request(1, 32'h50000000, 16, 2, 1, 0);
      begin
        wait (target_requests[4] == 1);
        read_request(0, 32'h1000b000, 1, 2, 1, 0);
        read_request(0, 32'h30000000, 4, 2, 1, 0);
        if (!u_dut.s_busy_q[2] || u_dut.target_idle_o[4])
          $fatal(1, "XPI test did not retain ownership");
        hold_read[4] = 0;
      end
    join
    // One owner's read and write can own different targets simultaneously.
    hold_read[0]  = 1;
    hold_b[1]     = 1;
    hold_write[1] = 1;
    fork
      read_request(1, 32'h30000000, 16, 2, 1, 0);
      write_request(1, 32'h30008000, 16, 0, 1);
      begin
        wait (u_dut.s_busy_q[2] && u_dut.s_busy_q[3]);
        read_request(2, 32'h30010000, 4, 2, 1, 0);
        if (u_dut.target_idle_o[0] || u_dut.target_idle_o[1])
          $fatal(1, "different targets serialized");
        hold_read[0]  = 0;
        hold_b[1]     = 0;
        hold_write[1] = 0;
      end
    join
    // A waiting APB FIFO branch cannot block independent control admission.
    hold_read[12] = 1;
    fork
      read_request(1, 32'h10009000, 1, 2, 1, 0);
      begin
        wait (!u_dut.target_idle_o[12]);
        read_request(0, 32'h1000a000, 1, 2, 1, 0);
        hold_read[12] = 0;
      end
    join
    fork
      begin
        repeat (8) read_request(0, 32'h30000000, 4, 2, 1, 0);
      end
      begin
        repeat (8) write_request(1, 32'h30000000, 4, 0, 0);
      end
      begin
        repeat (8) read_request(2, 32'h30000000, 4, 2, 1, 0);
      end
    join
    if (cpu_wait == 0 || dma_wait == 0) $fatal(1, "same-target wait counters never advanced");
    // Even when both CPU directions request different targets together,
    // the fabric must retain the CPU's one-combined-operation contract.
    fork
      read_request(0, 32'h30000000, 4, 2, 1, 0);
      write_request(0, 32'h30008000, 4, 0, 0);
    join
    error_beat[0] = 1;
    error_beat[1] = 1;
    fork
      mixed_error_read(1, 32'h30000000);
      mixed_error_read(2, 32'h30008000);
      begin
        wait (error_last_wait[1] && error_last_wait[2]);
        @(negedge clk_i);
        release_error = 1;
      end
    join
    if (simultaneous_faults != 1) $fatal(1, "simultaneous terminal faults lost");
    error_beat[0] = -1;
    error_beat[1] = -1;
    fork
      random_reads(0, 32'h12345678);
      random_reads(1, 32'h87654321);
      random_reads(2, 32'hc0ffee01);
    join
    // An accepted address buffered ahead of a stopped target remains owned.
    @(negedge clk_i);
    hold_address[0] = 1;
    araddr[1]       = 32'h30000000;
    arlen[1]        = 0;
    arsize[1]       = 2;
    arburst[1]      = 1;
    arvalid[1]      = 1;
    do @(posedge clk_i); while (!arready[1]);
    @(negedge clk_i);
    arvalid[1] = 0;
    repeat (8) @(negedge clk_i);
    if (u_dut.owner_idle_o[1] || u_dut.target_idle_o[0]) $fatal(1, "buffered AR not outstanding");
    arvalid = '0;
    awvalid = '0;
    wvalid  = '0;
    rready  = '0;
    bready  = '0;
    rst_n_i = 0;
    repeat (5) @(negedge clk_i);
    hold_address = '0;
    rst_n_i      = 1;
    repeat (4) @(negedge clk_i);
    if (rvalid != 0 || bvalid != 0 || u_dut.owner_idle_o != 7) $fatal(1, "old session replayed");
    read_request(2, 32'h30000000, 1, 2, 1, 0);
    $display("SIM_TEST_PASS Tiny P5 fabric seed=12345678 random_reads=96 concurrent_faults=2");
    $finish;
  end
  initial begin
    repeat (100000) @(posedge clk_i);
    $fatal(1, "SIM_TEST_TIMEOUT Tiny P5 fabric");
  end
endmodule

// Verification endpoint: delays only the creation of VALID, never withdraws a
// presented response. Per-address data and write checks detect crossed routes.
module tiny_p5_target_model #(
    parameter logic [1:0] ErrorResponse = 0
) (
    input logic         clk_i,
    rst_n_i,
    hold_address_i,
    hold_read_i,
    hold_write_i,
    hold_b_i,
    input integer       error_beat_i,
          axi4_if.slave axi4
);
  logic active = 0, writing = 0, write_done = 0, id = 0;
  logic [31:0] address = 0, start_address = 0;
  logic [7:0] length = 0, beat = 0;
  logic [2:0] size = 0;
  logic [1:0] burst = 0;
  assign axi4.arready = !active && !hold_address_i;
  assign axi4.awready = !active && !hold_address_i && !axi4.arvalid;
  assign axi4.wready  = active && writing && !write_done && !hold_write_i;
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
        active        <= 1;
        writing       <= 0;
        address       <= axi4.araddr;
        start_address <= axi4.araddr;
        length        <= axi4.arlen;
        beat          <= 0;
        id            <= axi4.arid;
        size          <= axi4.arsize;
        burst         <= axi4.arburst;
      end
      if (axi4.awvalid && axi4.awready) begin
        active        <= 1;
        writing       <= 1;
        write_done    <= 0;
        address       <= axi4.awaddr;
        start_address <= axi4.awaddr;
        length        <= axi4.awlen;
        beat          <= 0;
        id            <= axi4.awid;
        size          <= axi4.awsize;
        burst         <= axi4.awburst;
      end
      if (active && !writing && !axi4.rvalid && !hold_read_i) begin
        axi4.rvalid <= 1;
        axi4.rid <= id;
        axi4.rdata <= 32'h10000000 ^ address;
        axi4.rresp<=(ErrorResponse != 0) ? ErrorResponse : ((integer'(beat)==error_beat_i) ? 2 : 0);
        axi4.rlast <= beat == length;
      end
      if (axi4.rvalid && axi4.rready) begin
        axi4.rvalid <= 0;
        if (axi4.rlast) active <= 0;
        else begin
          beat <= beat + 1;
          if (burst == 1) address <= address + (32'd1 << size);
        end
      end
      if (axi4.wvalid && axi4.wready) begin
        if (axi4.wdata !== (32'hb0000000 ^ start_address ^ {24'd0, beat}))
          $fatal(1, "write data crossed AW ownership");
        if (axi4.wlast || beat == length) write_done <= 1;
        else beat <= beat + 1;
      end
      if (active && writing && write_done && !hold_b_i) begin
        axi4.bvalid <= 1;
        axi4.bid    <= id;
        axi4.bresp  <= ErrorResponse;
      end
      if (axi4.bvalid && axi4.bready) begin
        axi4.bvalid <= 0;
        active      <= 0;
        write_done  <= 0;
      end
    end
  end
endmodule
