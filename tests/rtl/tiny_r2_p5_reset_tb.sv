`timescale 1ns / 1ps
module tiny_r2_p5_reset_tb;
  logic clk_i = 0, rst_n_i = 0;
  always #5 clk_i = !clk_i;
  logic target_rst_n[23];
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
  apb4_if apb (
      .pclk   (clk_i),
      .presetn(target_rst_n[12])
  );
  logic [22:0] hold_address = '0, hold_read = '0, hold_write = '0, hold_b = '0;
  integer error_beat[23];
  integer captures[23], addresses[23], writes[23];
  logic [5:0] fault_valid, fault_instruction;
  logic [ 5:0][31:0] fault_addr;
  logic [ 5:0][ 1:0] fault_resp;
  logic [ 2:0]       owner_idle;
  logic [22:0]       target_idle;
  logic [63:0] cpu_wait, dma_wait;
  logic [2:0] arvalid = 0, awvalid = 0, wvalid = 0, rready = 0, bready = 0;
  logic [2:0][31:0] araddr = 0, awaddr = 0, wdata = 0;
  logic [2:0][7:0] arlen = 0, awlen = 0;
  logic [2:0] wlast = 0;
  wire [2:0] arready, awready, wready, rvalid, bvalid, rlast, rid, bid;
  wire [2:0][1:0] rresp, bresp;
  wire    [2:0][31:0] rdata;
  integer             faults          [6];
  logic   [5:0][31:0] last_fault_addr;
  logic   [5:0][ 1:0] last_fault_resp;
  integer             cases = 0;
  logic dma_start = 0, dma_valid = 0, dma_start_ready, dma_ready, dma_busy, dma_done;
  logic [31:0] dma_addr = 0, dma_data = 0;
  logic [4:0] dma_beats = 1;
  logic [1:0] dma_resp;
  logic       dma_id_error;

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

  // Production master: BREADY cannot rise until its last W handshake.
  dma_axi4_master u_dma (
      .clk_i               (clk_i),
      .rst_n_i             (rst_n_i),
      .clear_i             (1'b0),
      .read_start_valid_i  (1'b0),
      .read_start_ready_o  (),
      .read_addr_i         (32'd0),
      .read_beats_i        (5'd1),
      .read_fixed_i        (1'b0),
      .read_busy_o         (),
      .read_beat_valid_o   (),
      .read_beat_ready_i   (1'b0),
      .read_data_o         (),
      .read_resp_o         (),
      .read_last_o         (),
      .read_expected_last_o(),
      .read_id_error_o     (),
      .read_done_o         (),
      .write_start_valid_i (dma_start),
      .write_start_ready_o (dma_start_ready),
      .write_addr_i        (dma_addr),
      .write_beats_i       (dma_beats),
      .write_fixed_i       (1'b0),
      .write_busy_o        (dma_busy),
      .write_data_valid_i  (dma_valid),
      .write_data_ready_o  (dma_ready),
      .write_data_i        (dma_data),
      .write_strb_i        (4'hf),
      .write_done_o        (dma_done),
      .write_resp_o        (dma_resp),
      .write_id_error_o    (dma_id_error),
      .axi4                (masters[1])
  );

  for (genvar m = 0; m < 3; m++) begin : gen_master
    if (m != 1) begin : gen_manual
      assign masters[m].araddr   = araddr[m];
      assign masters[m].arlen    = arlen[m];
      assign masters[m].arsize   = 2;
      assign masters[m].arburst  = 1;
      assign masters[m].arid     = 1;
      assign masters[m].arvalid  = arvalid[m];
      assign masters[m].arlock   = 0;
      assign masters[m].arprot   = 0;
      assign masters[m].arcache  = 0;
      assign masters[m].arqos    = 0;
      assign masters[m].arregion = 0;
      assign masters[m].aruser   = 0;
      assign masters[m].awaddr   = awaddr[m];
      assign masters[m].awlen    = awlen[m];
      assign masters[m].awsize   = 2;
      assign masters[m].awburst  = 1;
      assign masters[m].awid     = 1;
      assign masters[m].awvalid  = awvalid[m];
      assign masters[m].awlock   = 0;
      assign masters[m].awprot   = 0;
      assign masters[m].awcache  = 0;
      assign masters[m].awqos    = 0;
      assign masters[m].awregion = 0;
      assign masters[m].awuser   = 0;
      assign masters[m].wdata    = wdata[m];
      assign masters[m].wstrb    = 15;
      assign masters[m].wvalid   = wvalid[m];
      assign masters[m].wlast    = wlast[m];
      assign masters[m].wuser    = 0;
      assign masters[m].rready   = rready[m];
      assign masters[m].bready   = bready[m];
    end
    assign arready[m] = masters[m].arready;
    assign awready[m] = masters[m].awready;
    assign wready[m]  = masters[m].wready;
    assign rvalid[m]  = masters[m].rvalid;
    assign bvalid[m]  = masters[m].bvalid;
    assign rlast[m]   = masters[m].rlast;
    assign rid[m]     = masters[m].rid;
    assign bid[m]     = masters[m].bid;
    assign rresp[m]   = masters[m].rresp;
    assign bresp[m]   = masters[m].bresp;
    assign rdata[m]   = masters[m].rdata;

    // Independent upstream scoreboards also run in Icarus without SVA.
    integer rleft = 0, wleft = 0, bleft = 0;
    logic rheld = 0, bheld = 0;
    logic [36:0] saved_r;
    logic [ 3:0] saved_b;
    always @(posedge clk_i) begin
      if (!rst_n_i) begin
        rleft = 0;
        wleft = 0;
        bleft = 0;
        rheld = 0;
        bheld = 0;
      end else begin
        if (rheld && (!masters[m].rvalid ||
            {masters[m].rid, masters[m].rdata, masters[m].rresp,
             masters[m].rlast, masters[m].ruser} !== saved_r))
          $fatal(1, "held R response changed");
        if (bheld && (!masters[m].bvalid ||
            {masters[m].bid, masters[m].bresp, masters[m].buser} !== saved_b))
          $fatal(1, "held B response changed");
        if (masters[m].arvalid && masters[m].arready) begin
          if (rleft != 0) $fatal(1, "duplicate read admission");
          rleft = integer'(masters[m].arlen) + 1;
        end
        if (masters[m].awvalid && masters[m].awready) begin
          if (bleft != 0) $fatal(1, "duplicate write admission");
          wleft = integer'(masters[m].awlen) + 1;
          bleft = 1;
        end
        if (masters[m].bvalid && (bleft != 1 || wleft != 0))
          $fatal(1, "B before complete W drain or duplicate B");
        if (masters[m].wvalid && masters[m].wready) begin
          if (wleft <= 0 || masters[m].wlast != (wleft == 1)) $fatal(1, "W count/last mismatch");
          wleft--;
        end
        if (masters[m].rvalid) begin
          if (rleft <= 0 || masters[m].rlast != (rleft == 1)) $fatal(1, "R count/last mismatch");
          if (masters[m].rready) rleft--;
        end
        if (masters[m].bvalid && masters[m].bready) bleft--;
        rheld = masters[m].rvalid && !masters[m].rready;
        bheld = masters[m].bvalid && !masters[m].bready;
        saved_r = {
          masters[m].rid, masters[m].rdata, masters[m].rresp, masters[m].rlast, masters[m].ruser
        };
        saved_b = {masters[m].bid, masters[m].bresp, masters[m].buser};
      end
    end
  end

  for (genvar t = 0; t < 23; t++) begin : gen_target
    if (t == 12) begin : gen_apb
      tiny_axi42apb4 u_bridge (
          .clk_i  (clk_i),
          .rst_n_i(target_rst_n[t]),
          .axi4   (targets[t]),
          .apb4   (apb)
      );
    end else begin : gen_memory
      tiny_r2_p5_reset_target_model u_model (
          .clk_i         (clk_i),
          .rst_n_i       (target_rst_n[t]),
          .hold_address_i(hold_address[t]),
          .hold_read_i   (hold_read[t]),
          .hold_write_i  (hold_write[t]),
          .hold_b_i      (hold_b[t]),
          .error_beat_i  (error_beat[t]),
          .axi4          (targets[t])
      );
    end
    always @(posedge clk_i) begin
      if (rst_n_i) begin
        if (targets[t].arvalid && targets[t].arready || targets[t].awvalid && targets[t].awready)
          addresses[t]++;
        if (targets[t].wvalid && targets[t].wready) writes[t]++;
        if (targets[t].rvalid && targets[t].rready) captures[t]++;
        if (!target_rst_n[t] && (targets[t].arvalid || targets[t].awvalid ||
            targets[t].wvalid || targets[t].rready || targets[t].bready))
          $fatal(1, "downstream handshake during target reset");
      end
    end
  end
  assign apb.pready  = apb.psel && apb.penable && !hold_read[12] && !hold_b[12];
  assign apb.prdata  = 32'hcafe_f00d;
  assign apb.pslverr = 0;
  always @(posedge clk_i) begin
    if (rst_n_i) begin
      for (integer e = 0; e < 6; e++) begin
        if (fault_valid[e]) begin
          faults[e]++;
          last_fault_addr[e] = fault_addr[e];
          last_fault_resp[e] = fault_resp[e];
        end
      end
    end
  end

  task automatic quiet;
    repeat (4) @(negedge clk_i);
    if (owner_idle != 7 || target_idle != 23'h7fffff || rvalid != 0 || bvalid != 0)
      $fatal(1, "credit/response not retired");
  endtask
  task automatic receive_read(input int index, input int beats, input logic [1:0] expected,
                              input logic [31:0] data);
    do @(posedge clk_i); while (!rvalid[0]);
    @(negedge clk_i);
    repeat (3) @(negedge clk_i);
    if (rid[0] !== 1'b1 || rresp[0] !== expected || rdata[0] !== data ||
        rlast[0] !== (index == beats - 1))
      $fatal(
          1,
          "read data/ID/response mismatch index=%0d expected=%0d got=%0d",
          index,
          expected,
          rresp[0]
      );
    rready[0] = 1;
    @(posedge clk_i);
    @(negedge clk_i);
    rready[0] = 0;
  endtask
  task automatic read_case(input logic [31:0] address, input int t, input int beats,
                           input bit buffered, input bit before_address, input bit inject_reset);
    integer first_capture, prefix, before_faults, before_addresses;
    logic [ 1:0] expected;
    logic [31:0] data;
    @(negedge clk_i);
    first_capture    = captures[t];
    before_faults    = faults[0];
    before_addresses = addresses[t];
    hold_address[t]  = before_address;
    hold_read[t]     = !buffered && inject_reset;
    araddr[0]        = address;
    arlen[0]         = 8'(beats - 1);
    arvalid[0]       = 1;
    do @(posedge clk_i); while (!arready[0]);
    @(negedge clk_i);
    arvalid[0] = 0;
    if (buffered) begin
      wait (rvalid[0]);
      repeat (5) @(negedge clk_i);
    end else if (!before_address) begin
      wait (addresses[t] > before_addresses);
      @(negedge clk_i);
    end
    prefix = captures[t] - first_capture;
    if (inject_reset) begin
      target_rst_n[t]  = 0;
      before_addresses = addresses[t];
      repeat (3) @(negedge clk_i);
      // Release the downstream reset while the upstream is still stalled.
      // The cancelled session must never be issued again after release.
      if (t != 0) target_rst_n[t] = 1;
      hold_address[t] = 0;
      hold_read[t]    = 0;
      repeat (4) @(negedge clk_i);
      if (addresses[t] != before_addresses) $fatal(1, "cancelled AR replayed");
    end
    for (integer n = 0; n < beats; n++) begin
      expected = inject_reset && n >= prefix ? 3 : (n == error_beat[t] ? 2 : 0);
      data = expected == 3 ? 0 : (t == 12 ? 32'hcafe_f00d : (address + 32'(4 * n)) ^ 32'h10000000);
      receive_read(n, beats, expected, data);
    end
    target_rst_n[t] = 1;
    quiet();
    if (inject_reset && (prefix < beats || (error_beat[t] >= 0 && error_beat[t] < prefix))) begin
      expected = (error_beat[t] >= 0 && error_beat[t] < prefix) ? 2 : 3;
      if (faults[0] != before_faults + 1 || last_fault_resp[0] != expected ||
          last_fault_addr[0] != address + 32'(4 * (expected == 2 ? error_beat[t] : prefix)))
        $fatal(1, "first failing read beat metadata/count lost");
    end else if (faults[0] != before_faults) $fatal(1, "spurious read fault");
    cases++;
  endtask
  task automatic send_word(input int n, input int beats);
    @(negedge clk_i);
    wdata[2]  = 32'ha5000000 + 32'(n);
    wlast[2]  = n == beats - 1;
    wvalid[2] = 1;
    do @(posedge clk_i); while (!wready[2]);
    @(negedge clk_i);
    wvalid[2] = 0;
  endtask
  task automatic write_case(input logic [31:0] address, input int t, input int beats,
                            input int prefix, input bit buffered, input bit before_address);
    integer before_faults, after_writes;
    @(negedge clk_i);
    before_faults   = faults[5];
    hold_address[t] = before_address;
    hold_b[t]       = !buffered;
    awaddr[2]       = address;
    awlen[2]        = 8'(beats - 1);
    awvalid[2]      = 1;
    do @(posedge clk_i); while (!awready[2]);
    @(negedge clk_i);
    awvalid[2] = 0;
    for (integer n = 0; n < prefix; n++) send_word(n, beats);
    if (buffered) begin
      wait (bvalid[2]);
      repeat (3) @(negedge clk_i);
    end
    target_rst_n[t] = 0;
    after_writes    = writes[t];
    repeat (3) @(negedge clk_i);
    if (t != 0) target_rst_n[t] = 1;
    hold_address[t] = 0;
    hold_b[t]       = 0;
    for (integer n = prefix; n < beats; n++) begin
      if (bvalid[2]) $fatal(1, "write response before remaining data");
      send_word(n, beats);
    end
    do @(posedge clk_i); while (!bvalid[2]);
    @(negedge clk_i);
    repeat (5) @(negedge clk_i);
    if (bresp[2] != (buffered ? 0 : 3) || bid[2] !== 1'b1 || writes[t] != after_writes)
      $fatal(1, "write response/ID or downstream session replay");
    bready[2] = 1;
    @(posedge clk_i);
    @(negedge clk_i);
    bready[2]       = 0;
    target_rst_n[t] = 1;
    quiet();
    if (faults[5] != before_faults + (buffered ? 0 : 1)) $fatal(1, "write fault count mismatch");
    cases++;
  endtask
  task automatic dma_case(input logic [31:0] address, input int t, input int beats,
                          input int prefix);
    integer before_faults, after_writes;
    @(negedge clk_i);
    before_faults = faults[3];
    hold_b[t]     = 1;
    dma_addr      = address;
    dma_beats     = 5'(beats);
    dma_start     = 1;
    do @(posedge clk_i); while (!dma_start_ready);
    @(negedge clk_i);
    dma_start = 0;
    wait (!owner_idle[1]);
    @(negedge clk_i);
    for (integer n = 0; n < beats; n++) begin
      if (n == prefix) begin
        target_rst_n[t] = 0;
        after_writes    = writes[t];
        repeat (3) @(negedge clk_i);
        target_rst_n[t] = 1;
        hold_b[t]       = 0;
      end
      dma_data  = 32'h5a000000 + 32'(n);
      dma_valid = 1;
      do @(posedge clk_i); while (!dma_ready);
      @(negedge clk_i);
      dma_valid = 0;
    end
    do @(posedge clk_i); while (!dma_done);
    if (dma_resp != 3 || dma_id_error) $fatal(1, "production DMA did not terminate with error");
    @(negedge clk_i);
    quiet();
    if (dma_busy || writes[t] != after_writes || faults[3] != before_faults + 1)
      $fatal(1, "production DMA write drain/credit/count failure");
    cases++;
  endtask

  initial begin
    for (integer t = 0; t < 23; t++) begin
      target_rst_n[t] = 0;
      captures[t]     = 0;
      addresses[t]    = 0;
      writes[t]       = 0;
      error_beat[t]   = -1;
    end
    for (integer e = 0; e < 6; e++) faults[e] = 0;
    repeat (4) @(negedge clk_i);
    rst_n_i = 1;
    for (integer t = 0; t < 23; t++) target_rst_n[t] = 1;
    // SRAM and XPI: address cancellation, missing 16 beats, two captured
    // beats under backpressure, and already captured successful completion.
    for (integer t = 0; t < 5; t += 4) begin
      read_case(t == 0 ? 32'h30000000 : 32'h50000000, t, 16, 0, 1, 1);
      read_case(t == 0 ? 32'h30000000 : 32'h50000000, t, 16, 0, 0, 1);
      read_case(t == 0 ? 32'h30000000 : 32'h50000000, t, 16, 1, 0, 1);
      read_case(t == 0 ? 32'h30000000 : 32'h50000000, t, 1, 1, 0, 1);
      read_case(t == 0 ? 32'h30000000 : 32'h50000000, t, 1, 1, 0, 0);
      write_case(t == 0 ? 32'h30000000 : 32'h50000000, t, 16, 0, 0, 1);
      write_case(t == 0 ? 32'h30000000 : 32'h50000000, t, 16, 2, 0, 0);
      write_case(t == 0 ? 32'h30000000 : 32'h50000000, t, 16, 16, 0, 0);
      write_case(t == 0 ? 32'h30000000 : 32'h50000000, t, 1, 1, 1, 0);
      dma_case(t == 0 ? 32'h30000000 : 32'h50000000, t, 16, 2);
    end
    error_beat[0] = 1;
    read_case(32'h30000000, 0, 16, 1, 0, 1);
    error_beat[0] = -1;
    // Actual APB bridge, with a withheld peripheral completion.
    read_case(32'h10009000, 12, 1, 0, 1, 1);
    read_case(32'h10009000, 12, 1, 0, 0, 1);
    read_case(32'h10009000, 12, 1, 1, 0, 1);
    write_case(32'h10009000, 12, 1, 0, 0, 1);
    write_case(32'h10009000, 12, 1, 1, 0, 0);
    write_case(32'h10009000, 12, 1, 1, 1, 0);
    dma_case(32'h10009000, 12, 1, 0);
    $display("P5_RESET cases=%0d production_dma=3 burst_beats=16 held_RB=1 first_fault=1", cases);
    $display("SIM_TEST_PASS Tiny P5 target reset isolation");
    $finish;
  end
  initial begin
    repeat (20000) @(posedge clk_i);
    $fatal(1, "SIM_TEST_TIMEOUT Tiny P5 target reset isolation cases=%0d", cases);
  end
endmodule

module tiny_r2_p5_reset_target_model (
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
  logic [31:0] address = 0;
  logic [7:0] length = 0, beat = 0;
  assign axi4.arready = !active && !hold_address_i && rst_n_i;
  assign axi4.awready = !active && !hold_address_i && !axi4.arvalid && rst_n_i;
  assign axi4.wready  = active && writing && !write_done && !hold_write_i && rst_n_i;
  assign axi4.ruser   = 0;
  assign axi4.buser   = 0;
  always @(posedge clk_i or negedge rst_n_i) begin
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
        length     <= axi4.awlen;
        beat       <= 0;
        id         <= axi4.awid;
      end
      if (active && !writing && !axi4.rvalid && !hold_read_i) begin
        axi4.rvalid <= 1;
        axi4.rid    <= id;
        axi4.rdata  <= 32'h10000000 ^ address;
        axi4.rresp  <= integer'(beat) == error_beat_i ? 2 : 0;
        axi4.rlast  <= beat == length;
      end
      if (axi4.rvalid && axi4.rready) begin
        axi4.rvalid <= 0;
        if (axi4.rlast) active <= 0;
        else begin
          beat    <= beat + 1;
          address <= address + 4;
        end
      end
      if (axi4.wvalid && axi4.wready) begin
        if (beat == length) write_done <= 1;
        else beat <= beat + 1;
      end
      if (active && writing && write_done && !axi4.bvalid && !hold_b_i) begin
        axi4.bvalid <= 1;
        axi4.bid    <= id;
        axi4.bresp  <= 0;
      end
      if (axi4.bvalid && axi4.bready) begin
        axi4.bvalid <= 0;
        active      <= 0;
        write_done  <= 0;
      end
    end
  end
endmodule
