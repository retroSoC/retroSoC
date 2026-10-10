`timescale 1ns / 1ps
module tiny_r2_p4_memory_tb;
  logic clk_i = 0, rst_n_i = 0, quiesce = 0, idle;
  logic perf_enable = 1, perf_clear = 0;
  always #5 clk_i = ~clk_i;
  ahbl_if cpu[2] (
      .hclk   (clk_i),
      .hresetn(rst_n_i)
  );
  tiny_sram_port_if local_ports[2] ();
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) ext[4] (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) slow (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  apb4_if cfg (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  logic [31:0] addr[2], data[2], rdata[2];
  logic [2:0] size [2];
  logic [1:0] trans[2];
  logic [1:0] wr, ready, resp;
  logic [31:0] awaddr[4], wdata[4], araddr[4], erdata[4];
  logic [3:0] wstrb[4];
  logic [7:0] awlen[4], arlen[4];
  logic [2:0] awsize[4], arsize[4];
  logic [1:0] awburst[4], arburst[4], bresp[4], rresp[4];
  logic [3:0] awvalid, wvalid, wlast, bready, arvalid, rready;
  logic [3:0] awready, wready, bvalid, arready, rvalid, rlast;
  integer        parallel_issues = 0;
  integer        local_latency_max = 0;
  logic   [31:0] observed;
  logic   [31:0] seed = 32'h12345678;

  tiny_cpu_mem u_cpu_mem (
      .clk_i      (clk_i),
      .rst_n_i    (rst_n_i),
      .quiesce_i  (quiesce),
      .idle_o     (idle),
      .cpu        (cpu),
      .local_ports(local_ports),
      .slow_axi4  (slow)
  );
  tiny_sram u_sram (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .perf_enable_i (perf_enable),
      .perf_clear_i  (perf_clear),
      .local_ports   (local_ports),
      .external_ports(ext),
      .cfg_apb4      (cfg)
  );
  axi4_error_slave #(
      .Response(2'b11)
  ) u_slow_error (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .axi4   (slow)
  );
  for (genvar p = 0; p < 2; p++) begin : gen_cpu
    assign cpu[p].haddr     = addr[p];
    assign cpu[p].hwdata    = data[p];
    assign cpu[p].hsize     = size[p];
    assign cpu[p].htrans    = trans[p];
    assign cpu[p].hwrite    = wr[p];
    assign cpu[p].hburst    = 0;
    assign cpu[p].hprot     = 4'(p);
    assign cpu[p].hmastlock = 0;
    assign ready[p]         = cpu[p].hready;
    assign resp[p]          = cpu[p].hresp;
    assign rdata[p]         = cpu[p].hrdata;
  end
  for (genvar g = 0; g < 4; g++) begin : gen_ext
    assign ext[g].awaddr   = awaddr[g];
    assign ext[g].awlen    = awlen[g];
    assign ext[g].awsize   = awsize[g];
    assign ext[g].awburst  = awburst[g];
    assign ext[g].awvalid  = awvalid[g];
    assign ext[g].wdata    = wdata[g];
    assign ext[g].wstrb    = wstrb[g];
    assign ext[g].wlast    = wlast[g];
    assign ext[g].wvalid   = wvalid[g];
    assign ext[g].bready   = bready[g];
    assign ext[g].araddr   = araddr[g];
    assign ext[g].arlen    = arlen[g];
    assign ext[g].arsize   = arsize[g];
    assign ext[g].arburst  = arburst[g];
    assign ext[g].arvalid  = arvalid[g];
    assign ext[g].rready   = rready[g];
    assign ext[g].awid     = '0;
    assign ext[g].awlock   = '0;
    assign ext[g].awcache  = '0;
    assign ext[g].awprot   = '0;
    assign ext[g].awqos    = '0;
    assign ext[g].awregion = '0;
    assign ext[g].awuser   = '0;
    assign ext[g].wuser    = '0;
    assign ext[g].arid     = '0;
    assign ext[g].arlock   = '0;
    assign ext[g].arcache  = '0;
    assign ext[g].arprot   = '0;
    assign ext[g].arqos    = '0;
    assign ext[g].arregion = '0;
    assign ext[g].aruser   = '0;
    assign awready[g]      = ext[g].awready;
    assign wready[g]       = ext[g].wready;
    assign bvalid[g]       = ext[g].bvalid;
    assign bresp[g]        = ext[g].bresp;
    assign arready[g]      = ext[g].arready;
    assign rvalid[g]       = ext[g].rvalid;
    assign rresp[g]        = ext[g].rresp;
    assign rlast[g]        = ext[g].rlast;
    assign erdata[g]       = ext[g].rdata;
  end
  always @(posedge clk_i) begin
    if ((int'(u_sram.gen_group[0].u_group.s_issue) +
         int'(u_sram.gen_group[1].u_group.s_issue) +
         int'(u_sram.gen_group[2].u_group.s_issue) +
         int'(u_sram.gen_group[3].u_group.s_issue)) > 1)
      parallel_issues++;
  end
  task automatic ahb(input integer p, input bit write_access, input logic [31:0] address,
                     input logic [2:0] width, input logic [31:0] value, input bit error_expected,
                     input integer max_latency, output logic [31:0] result);
    time    accepted;
    integer error_cycles;
    @(negedge clk_i);
    addr[p]  = address;
    size[p]  = width;
    wr[p]    = write_access;
    trans[p] = 2;
    do @(posedge clk_i); while (!ready[p]);
    accepted = $time;
    @(negedge clk_i);
    trans[p]     = 0;
    data[p]      = value;
    error_cycles = 0;
    do begin
      @(posedge clk_i);
      if (resp[p]) error_cycles++;
    end while (!ready[p]);
    result = rdata[p];
    if (resp[p] != error_expected || (error_expected && error_cycles != 2))
      $fatal(1, "AHB error protocol p=%0d addr=%h errors=%0d", p, address, error_cycles);
    if (max_latency != 0 && (($time - accepted) / 10) > max_latency)
      $fatal(1, "local latency p=%0d addr=%h cycles=%0d", p, address, ($time - accepted) / 10);
    if (max_latency != 0 && (($time - accepted) / 10) > local_latency_max)
      local_latency_max = integer'(($time - accepted) / 10);
    @(negedge clk_i);
  endtask
  task automatic store(input logic [31:0] address, input logic [31:0] value,
                       input logic [2:0] width);
    logic [31:0] unused;
    ahb(1, 1, address, width, value, 0, 3, unused);
  endtask
  task automatic load(input integer p, input logic [31:0] address, input logic [31:0] value,
                      input integer max_latency);
    logic [31:0] got;
    ahb(p, 0, address, 2, 0, 0, max_latency, got);
    if (got !== value)
      $fatal(1, "local data p=%0d addr=%h got=%h expected=%h", p, address, got, value);
  endtask
  task automatic read_external(input integer g, input logic [31:0] address,
                               input logic [31:0] value, input integer hold_cycles,
                               input logic [1:0] expected_resp);
    @(negedge clk_i);
    araddr[g]  = address;
    arvalid[g] = 1;
    do @(posedge clk_i); while (!arready[g]);
    @(negedge clk_i);
    arvalid[g] = 0;
    while (!rvalid[g]) @(negedge clk_i);
    repeat (hold_cycles) begin
      @(posedge clk_i);
      if (!rvalid[g] || erdata[g] !== value || rresp[g] != expected_resp || !rlast[g])
        $fatal(1, "external response changed under backpressure");
      @(negedge clk_i);
    end
    if (erdata[g] !== value || rresp[g] != expected_resp || !rlast[g])
      $fatal(1, "external read g=%0d got=%h expected=%h resp=%b", g, erdata[g], value, rresp[g]);
    rready[g] = 1;
    @(posedge clk_i);
    @(negedge clk_i);
    rready[g] = 0;
  endtask
  task automatic write_external(input integer g, input logic [31:0] address,
                                input logic [31:0] value, input logic [3:0] mask,
                                input integer delay_data);
    @(negedge clk_i);
    awaddr[g]  = address;
    awvalid[g] = 1;
    do @(posedge clk_i); while (!awready[g]);
    @(negedge clk_i);
    awvalid[g] = 0;
    repeat (delay_data) @(negedge clk_i);
    wdata[g]  = value;
    wstrb[g]  = mask;
    wvalid[g] = 1;
    wlast[g]  = 1;
    do @(posedge clk_i); while (!wready[g]);
    @(negedge clk_i);
    wvalid[g] = 0;
    bready[g] = 1;
    do @(posedge clk_i); while (!bvalid[g]);
    if (bresp[g] != 0) $fatal(1, "external write");
    @(negedge clk_i);
    bready[g] = 0;
  endtask
  task automatic config_read(input logic [11:0] offset, input logic [31:0] expected);
    @(negedge clk_i);
    cfg.paddr   = {20'h10017, offset};
    cfg.psel    = 1;
    cfg.penable = 0;
    @(negedge clk_i);
    cfg.penable = 1;
    do @(posedge clk_i); while (!cfg.pready);
    if (cfg.pslverr || cfg.prdata !== expected)
      $fatal(1, "SRAM ABI/perf offset=%h got=%h expected=%h", offset, cfg.prdata, expected);
    @(negedge clk_i);
    cfg.psel    = 0;
    cfg.penable = 0;
  endtask
  task automatic burst_and_errors;
    // Sixteen captured write beats, with W asserted before AW.
    @(negedge clk_i);
    wdata[0]  = 32'hcafe0000;
    wstrb[0]  = 15;
    wvalid[0] = 1;
    wlast[0]  = 0;
    repeat (3) begin
      @(posedge clk_i);
      if (wready[0]) $fatal(1, "W accepted without AW ownership");
    end
    @(negedge clk_i);
    awaddr[0]  = 32'h30000fc0;
    awlen[0]   = 15;
    awvalid[0] = 1;
    do @(posedge clk_i); while (!awready[0]);
    @(negedge clk_i);
    awvalid[0] = 0;
    for (integer beat = 0; beat < 16; beat++) begin
      wdata[0] = 32'hcafe0000 + beat;
      wlast[0] = (beat == 15);
      do @(posedge clk_i); while (!wready[0]);
      @(negedge clk_i);
    end
    wvalid[0] = 0;
    wait (bvalid[0]);
    load(0, 32'h30000ffc, 32'hcafe000f, 3);  // B held while local read completes.
    if (!bvalid[0] || bresp[0] != 0) $fatal(1, "B not retained");
    @(negedge clk_i);
    bready[0] = 1;
    @(posedge clk_i);
    @(negedge clk_i);
    bready[0]  = 0;
    awlen[0]   = 0;
    araddr[0]  = 32'h30000fc0;
    arlen[0]   = 15;
    arvalid[0] = 1;
    do @(posedge clk_i); while (!arready[0]);
    @(negedge clk_i);
    arvalid[0] = 0;
    for (integer beat = 0; beat < 16; beat++) begin
      wait (rvalid[0]);
      repeat (beat % 4) @(negedge clk_i);
      if (erdata[0] !== (32'hcafe0000 + beat) || rresp[0] != 0 || rlast[0] != (beat == 15))
        $fatal(1, "burst read ordering/last at beat %0d", beat);
      rready[0] = 1;
      @(posedge clk_i);
      @(negedge clk_i);
      rready[0] = 0;
    end
    arlen[0] = 0;
    // A malformed write cannot commit bytes. Test strobes and early/missing LAST.
    for (integer bad = 0; bad < 3; bad++) begin
      @(negedge clk_i);
      awaddr[0]  = 32'h30000fc0;
      awvalid[0] = 1;
      awsize[0]  = (bad == 0) ? 1 : 2;
      awlen[0]   = (bad == 1) ? 3 : 0;
      do @(posedge clk_i); while (!awready[0]);
      @(negedge clk_i);
      awvalid[0] = 0;
      wvalid[0]  = 1;
      wdata[0]   = 0;
      wstrb[0]   = (bad == 0) ? 4'h8 : 4'hf;
      wlast[0]   = (bad != 2);
      do @(posedge clk_i); while (!wready[0]);
      @(negedge clk_i);
      wvalid[0] = 0;
      bready[0] = 1;
      do @(posedge clk_i); while (!bvalid[0]);
      if (bresp[0] != 2) $fatal(1, "malformed write accepted");
      @(negedge clk_i);
      bready[0] = 0;
      load(0, 32'h30000fc0, 32'hcafe0000, 3);
    end
    awsize[0] = 2;
    awlen[0]  = 0;
    wlast[0]  = 1;
    wstrb[0]  = 15;
  endtask
  task automatic back_to_back;
    // The next address is already present when the preceding write completes.
    @(negedge clk_i);
    addr[1]  = 32'h30000100;
    size[1]  = 2;
    wr[1]    = 1;
    trans[1] = 2;
    do @(posedge clk_i); while (!ready[1]);
    for (integer word_index = 0; word_index < 8; word_index++) begin
      @(negedge clk_i);
      data[1]  = 32'hf00d0000 + word_index;
      addr[1]  = 32'h30000104 + word_index * 4;
      trans[1] = (word_index == 7) ? 0 : 2;
      do @(posedge clk_i); while (!ready[1]);
      if (resp[1]) $fatal(1, "pipelined write error");
    end
    @(negedge clk_i);
    for (integer word_index = 0; word_index < 8; word_index++)
      load(0, 32'h30000100 + word_index * 4, 32'hf00d0000 + word_index, 3);
  endtask
  task automatic streaming_burst;
    time started, first_beat, previous_beat, final_write;
    integer read_gap_max, write_gap_max;
    read_gap_max  = 0;
    write_gap_max = 0;
    @(negedge clk_i);
    awaddr[0]  = 32'h30000400;
    awlen[0]   = 15;
    awvalid[0] = 1;
    do @(posedge clk_i); while (!awready[0]);
    started = $time;
    @(negedge clk_i);
    awvalid[0] = 0;
    wvalid[0]  = 1;
    for (integer beat = 0; beat < 16; beat++) begin
      wdata[0] = 32'hface0000 + beat;
      wlast[0] = (beat == 15);
      do @(posedge clk_i); while (!wready[0]);
      if (beat == 0) first_beat = $time;
      else begin
        if (($time - previous_beat) != 10) $fatal(1, "write streaming bubble beat=%0d", beat);
        write_gap_max = 1;
      end
      previous_beat = $time;
      @(negedge clk_i);
    end
    final_write = previous_beat;
    wvalid[0]   = 0;
    bready[0]   = 1;
    do @(posedge clk_i); while (!bvalid[0]);
    if (bresp[0] != 0) $fatal(1, "streaming write response");
    $display("P4_STREAM_WRITE first=%0d total=%0d b_after_last=%0d", (first_beat - started) / 10,
             ($time - started) / 10, ($time - final_write) / 10);
    @(negedge clk_i);
    bready[0]  = 0;
    awlen[0]   = 0;
    araddr[0]  = 32'h30000400;
    arlen[0]   = 15;
    arvalid[0] = 1;
    rready[0]  = 1;
    do @(posedge clk_i); while (!arready[0]);
    started = $time;
    @(negedge clk_i);
    arvalid[0] = 0;
    for (integer beat = 0; beat < 16; beat++) begin
      do @(posedge clk_i); while (!rvalid[0]);
      if (erdata[0] !== (32'hface0000 + beat) || rresp[0] != 0 || rlast[0] != (beat == 15))
        $fatal(1, "streaming read ordering beat=%0d", beat);
      if (beat == 0) first_beat = $time;
      else begin
        if (($time - previous_beat) != 10) $fatal(1, "read streaming bubble beat=%0d", beat);
        read_gap_max = 1;
      end
      previous_beat = $time;
      @(negedge clk_i);
    end
    rready[0] = 0;
    arlen[0]  = 0;
    $display("P4_STREAM_READ first=%0d total=%0d", (first_beat - started) / 10,
             (previous_beat - started) / 10);
    $display("P4_STREAM read_gap_max=%0d write_gap_max=%0d beats=16", read_gap_max, write_gap_max);
  endtask

  task automatic buffered_read;
    // Two reserved words must survive a full queue, local writes to their
    // addresses, and READY dropping again immediately after the first pop.
    @(negedge clk_i);
    araddr[0]  = 32'h30000400;
    arlen[0]   = 15;
    arvalid[0] = 1;
    do @(posedge clk_i); while (!arready[0]);
    @(negedge clk_i);
    arvalid[0] = 0;
    repeat (8) @(negedge clk_i);
    store(32'h30000400, 32'habcd0000, 2);
    store(32'h30000404, 32'habcd0001, 2);
    store(32'h30000408, 32'habcd0002, 2);
    for (integer beat = 0; beat < 16; beat++) begin
      rready[0] = 1;
      do @(posedge clk_i); while (!rvalid[0]);
      if (erdata[0] !== ((beat == 2) ? 32'habcd0002 : (32'hface0000 + beat)) ||
          rresp[0] != 0 || rlast[0] != (beat == 15))
        $fatal(1, "reserved response lost/reordered beat=%0d", beat);
      @(negedge clk_i);
      rready[0] = 0;
      repeat (beat % 5 + 1) @(negedge clk_i);
    end
    arlen[0] = 0;
  endtask

  task automatic buffered_write_errors;
    integer beats, stalls;
    // Earlier queued beats must commit before an error B. Later legal beats
    // after a bad strobe keep the existing target policy; early LAST ends W.
    for (integer bad = 0; bad < 3; bad++) begin
      for (integer n = 0; n < 8; n++) store(32'h30000600 + n * 4, 32'h12340000 + n, 2);
      beats  = (bad == 1) ? 4 : 8;
      stalls = 0;
      @(negedge clk_i);
      awaddr[0]  = 32'h30000600;
      awlen[0]   = 7;
      awsize[0]  = (bad == 0) ? 1 : 2;
      awvalid[0] = 1;
      do @(posedge clk_i); while (!awready[0]);
      @(negedge clk_i);
      awvalid[0] = 0;
      fork
        begin
          for (integer beat = 0; beat < beats; beat++) begin
            wvalid[0] = 1;
            wdata[0]  = 32'hbeefbeef;
            wstrb[0]  = (bad == 0) ? ((beat == 3) ? 4'hf : ((beat % 2) == 0 ? 4'h3 : 4'hc)) : 4'hf;
            wlast[0]  = (bad == 1) ? (beat == 3) : ((bad == 0) && (beat == 7));
            do begin
              @(posedge clk_i);
              if (!wready[0]) stalls++;
            end while (!wready[0]);
            @(negedge clk_i);
            wvalid[0] = 0;
            if (beat == 4) repeat (3) @(negedge clk_i);
          end
        end
        begin
          repeat (6) load(0, 32'h30000020, 32'h98765432, 0);
        end
        begin
          repeat (6) load(1, 32'h30000020, 32'h98765432, 0);
        end
      join
      wait (bvalid[0]);
      if (bresp[0] != 2) $fatal(1, "buffered malformed write response");
      if (bad != 0 && stalls == 0) $fatal(1, "write buffer full path not exercised");
      for (integer n = 0; n < 8; n++) begin
        if (bad == 0) begin
          load(0, 32'h30000600 + n * 4,
               (n == 1) ? 32'h1234beef : ((n < 4) ? 32'hbeefbeef : (32'h12340000 + n)), 3);
        end else begin
          load(0, 32'h30000600 + n * 4, (n < (beats - 1)) ? 32'hbeefbeef : (32'h12340000 + n), 3);
        end
      end
      @(negedge clk_i);
      bready[0] = 1;
      @(posedge clk_i);
      @(negedge clk_i);
      bready[0] = 0;
    end
    awlen[0]  = 0;
    awsize[0] = 2;
    wlast[0]  = 1;
    wstrb[0]  = 15;
  endtask
  initial begin
    #20000000;
    $fatal(1, "SIM_TEST_TIMEOUT Tiny P4 memory");
  end
  initial begin
    wr       = 0;
    trans[0] = 0;
    trans[1] = 0;
    addr[0]  = 0;
    addr[1]  = 0;
    data[0]  = 0;
    data[1]  = 0;
    size[0]  = 2;
    size[1]  = 2;
    awvalid  = 0;
    wvalid   = 0;
    wlast    = 0;
    bready   = 0;
    arvalid  = 0;
    rready   = 0;
    for (integer g = 0; g < 4; g++) begin
      awaddr[g]  = 0;
      awlen[g]   = 0;
      awsize[g]  = 2;
      awburst[g] = 1;
      araddr[g]  = 0;
      arlen[g]   = 0;
      arsize[g]  = 2;
      arburst[g] = 1;
      wdata[g]   = 0;
      wstrb[g]   = 15;
    end
    cfg.paddr   = 0;
    cfg.pprot   = 0;
    cfg.psel    = 0;
    cfg.penable = 0;
    cfg.pwrite  = 0;
    cfg.pwdata  = 0;
    cfg.pstrb   = 15;
    repeat (5) @(negedge clk_i);
    rst_n_i = 1;
    config_read(12'h00c, 131072);
    config_read(12'h010, 32);
    config_read(12'h014, 4096);
    // First/last words of all 32 physical macros and every 32 KiB boundary.
    for (integer bank = 0; bank < 32; bank++) begin
      store(32'h30000000 + bank * 4096, 32'ha5000000 + bank, 2);
      store(32'h30000ffc + bank * 4096, 32'h5a000000 + bank, 2);
      load(0, 32'h30000000 + bank * 4096, 32'ha5000000 + bank, 3);
      load(1, 32'h30000ffc + bank * 4096, 32'h5a000000 + bank, 3);
    end
    store(32'h30000020, 32'h11223344, 2);
    store(32'h30000021, 32'haa, 0);
    store(32'h30000022, 32'hbbcc, 1);
    load(0, 32'h30000020, 32'hbbccaa44, 3);
    for (integer lane = 0; lane < 4; lane++) begin
      store(32'h30000028, 32'h11223344, 2);
      store(32'h30000028 + lane, 32'haa, 0);
      load(0, 32'h30000028, (32'h11223344 & ~(32'hff << (lane * 8))) | (32'haa << (lane * 8)), 3);
    end
    store(32'h30000028, 32'h11223344, 2);
    store(32'h30000028, 32'haabb, 1);
    load(0, 32'h30000028, 32'h1122aabb, 3);
    back_to_back();
    fork
      load(0, 32'h30000000, 32'ha5000000, 3);
      load(1, 32'h30008000, 32'ha5000008, 3);
    join
    if (parallel_issues == 0) $fatal(1, "different groups serialized");
    fork
      load(0, 32'h30000000, 32'ha5000000, 0);
      load(1, 32'h30000000, 32'ha5000000, 0);
      read_external(0, 32'h30000000, 32'ha5000000, 0, 0);
    join
    // A held R must retain old data while local writes use that same macro.
    fork
      read_external(0, 32'h30000020, 32'hbbccaa44, 31, 0);
      begin
        wait (rvalid[0]);
        store(32'h30000020, 32'h98765432, 2);
        load(0, 32'h30000020, 32'h98765432, 3);
      end
    join
    // Waiting for external W does not lock the macro against CPU accesses.
    fork
      write_external(0, 32'h30000024, 32'hdeadbeef, 15, 31);
      begin
        wait (wready[0]);
        load(0, 32'h30000020, 32'h98765432, 3);
      end
    join
    load(1, 32'h30000024, 32'hdeadbeef, 3);
    @(negedge clk_i);
    perf_clear = 1;
    @(negedge clk_i);
    perf_clear = 0;
    fork
      read_external(0, 32'h30000000, 32'ha5000000, 7, 0);
      read_external(1, 32'h30008000, 32'ha5000008, 7, 0);
      read_external(2, 32'h30010000, 32'ha5000010, 7, 0);
      read_external(3, 32'h30018000, 32'ha5000018, 7, 0);
    join
    config_read(12'h020, 4);
    config_read(12'h024, 0);
    config_read(12'h028, 4);
    config_read(12'h030, 7);  // Four parallel stalls count once per clock.
    burst_and_errors();
    streaming_burst();
    buffered_read();
    buffered_write_errors();
    read_external(0, 32'h30008000, 0, 0, 3);
    ahb(1, 0, 32'h70000000, 2, 0, 1, 0, observed);
    ahb(1, 0, 32'h30000001, 2, 0, 1, 0, observed);
    // Deterministic word/byte readback across all groups without touching a
    // simulator memory array: every operation travels through the real ports.
    for (integer g = 0; g < 4; g++) begin
      for (integer n = 0; n < 4096; n++) begin
        seed = seed ^ (seed << 13);
        seed = seed ^ (seed >> 17);
        seed = seed ^ (seed << 5);
        store(32'h30000000 + g * 32768 + (n % 8192) * 4, seed, 2);
        load(0, 32'h30000000 + g * 32768 + (n % 8192) * 4, seed, 3);
      end
    end
    store(32'h3001fff0, 32'h76543210, 2);
    @(negedge clk_i);
    araddr[3]  = 32'h3001fff0;
    arlen[3]   = 3;
    arvalid[3] = 1;
    do @(posedge clk_i); while (!arready[3]);
    @(negedge clk_i);
    arvalid[3] = 0;
    wait (rvalid[3]);
    repeat (4) @(negedge clk_i);
    @(negedge clk_i);
    rst_n_i = 0;
    repeat (3) @(negedge clk_i);
    if (rvalid != 0 || bvalid != 0) $fatal(1, "system reset retained a stale response");
    rst_n_i  = 1;
    arlen[3] = 0;
    load(0, 32'h3001fff0, 32'h76543210, 3);
    read_external(3, 32'h3001fff0, 32'h76543210, 0, 0);
    // Reset after W acceptance, before the captured word reaches a macro.
    // The cancelled word and its completion must not replay into a new session.
    @(negedge clk_i);
    awaddr[3]  = 32'h3001fff0;
    awlen[3]   = 3;
    awvalid[3] = 1;
    do @(posedge clk_i); while (!awready[3]);
    @(negedge clk_i);
    awvalid[3] = 0;
    wdata[3]   = 32'hbad0bad0;
    wlast[3]   = 0;
    wvalid[3]  = 1;
    do @(posedge clk_i); while (!wready[3]);
    @(negedge clk_i);
    wvalid[3] = 0;
    rst_n_i   = 0;
    repeat (3) @(negedge clk_i);
    rst_n_i  = 1;
    awlen[3] = 0;
    wlast[3] = 1;
    repeat (5) @(negedge clk_i);
    if (bvalid != 0 || rvalid != 0) $fatal(1, "cancelled W response replayed");
    read_external(3, 32'h3001fff0, 32'h76543210, 0, 0);
    $display("P4_BUFFER backpressure errors reset conservation PASS");
    $display("P4_MEMORY local_latency_max=%0d parallel_issue_cycles=%0d", local_latency_max,
             parallel_issues);
    $display("SIM_TEST_PASS Tiny P4 memory seed=12345678 random_per_group=4096");
    $finish;
  end
endmodule
