`timescale 1ns / 1ps
module tiny_r2_p4_cpu_tb;
  logic clk_i = 0, rst_n_i = 0;
  always #5 clk_i = ~clk_i;
  wire s_rst_n = rst_n_i;
  logic s_jtag_tck_driver = 0, s_jtag_tms_driver = 1, s_jtag_tdi_driver = 0;
  wire s_jtag_tdo;
  logic core_rst_n, quiesce, idle, halted;
  ahbl_if cpu[2] (
      .hclk   (clk_i),
      .hresetn(core_rst_n)
  );
  tiny_sram_port_if local_ports[2] ();
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) slow (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) ext[4] (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  apb4_if cfg (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  logic  [7:0] rom      [0:4095];
  string       firmware;
  logic read_pending = 0, aw_pending = 0, write_pending = 0, hold_read = 0;
  logic [31:0] read_data = 0, write_addr = 0;
  logic   [ 1:0] read_resp = 0;
  integer        starts = 0;
  logic          completed = 0;
  logic   [31:0] status;
  bit            ignored;
  `include "tiny_jtag_smoke.svh"

tiny_cpu_wrapper #(
      .EnableAtomics  (0),
      .ResetSyncStages(5)
  ) u_cpu (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .irq_i         (32'd0),
      .jtag_tck_i    (s_jtag_tck_driver),
      .jtag_tms_i    (s_jtag_tms_driver),
      .jtag_tdi_i    (s_jtag_tdi_driver),
      .jtag_trst_n_i (rst_n_i),
      .jtag_tdo_o    (s_jtag_tdo),
      .debug_halted_o(halted),
      .bus_idle_i    (idle),
      .core_rst_n_o  (core_rst_n),
      .quiesce_o     (quiesce),
      .cpu           (cpu)
  );
  tiny_cpu_mem u_cpu_mem (
      .clk_i      (clk_i),
      .rst_n_i    (core_rst_n),
      .quiesce_i  (quiesce),
      .idle_o     (idle),
      .cpu        (cpu),
      .local_ports(local_ports),
      .slow_axi4  (slow)
  );
  tiny_sram u_sram (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .perf_enable_i (1'b0),
      .perf_clear_i  (1'b0),
      .local_ports   (local_ports),
      .external_ports(ext),
      .cfg_apb4      (cfg)
  );
  // Verification-only slow memory, not a product Boot ROM. It also supplies
  // the terminal mailbox and instruction fault used by this CPU fixture.
  assign slow.arready = !read_pending;
  assign slow.rvalid  = read_pending && !hold_read;
  assign slow.rdata   = read_data;
  assign slow.rresp   = read_resp;
  assign slow.rid     = 0;
  assign slow.rlast   = 1;
  assign slow.ruser   = 0;
  assign slow.awready = !aw_pending && !write_pending;
  assign slow.wready  = aw_pending;
  assign slow.bvalid  = write_pending;
  assign slow.bresp   = 0;
  assign slow.bid     = 0;
  assign slow.buser   = 0;
  always @(posedge clk_i) begin
    if (!rst_n_i) begin
      read_pending  <= 0;
      aw_pending    <= 0;
      write_pending <= 0;
    end else begin
      if (slow.rvalid && slow.rready) read_pending <= 0;
      if (slow.arvalid && slow.arready) begin
        read_pending <= 1;
        if (slow.araddr < 4096) begin
          read_resp <= 0;
          read_data <= {
            rom[slow.araddr+3], rom[slow.araddr+2], rom[slow.araddr+1], rom[slow.araddr]
          };
        end else begin
          read_resp <= 3;
          read_data <= 0;
          if (!slow.arprot[2]) $fatal(1, "unexpected slow data read %h", slow.araddr);
        end
      end
      if (slow.awvalid && slow.awready) begin
        aw_pending <= 1;
        write_addr <= slow.awaddr;
      end
      if (slow.wvalid && slow.wready) begin
        aw_pending    <= 0;
        write_pending <= 1;
        if (write_addr != 32'h1000b084) $fatal(1, "unexpected slow write %h", write_addr);
        if (slow.wdata == 1) starts <= starts + 1;
        else if (slow.wdata == 32'h80000001) completed <= 1;
        else $fatal(1, "SIM_TEST_FAIL CPU fixture code=%h", slow.wdata);
      end
      if (slow.bvalid && slow.bready) write_pending <= 0;
    end
  end
  for (genvar g = 0; g < 4; g++) begin : gen_init
    initial begin
      ext[g].awid     = 0;
      ext[g].awaddr   = 0;
      ext[g].awlen    = 0;
      ext[g].awsize   = 2;
      ext[g].awburst  = 1;
      ext[g].awlock   = 0;
      ext[g].awcache  = 0;
      ext[g].awprot   = 0;
      ext[g].awqos    = 0;
      ext[g].awregion = 0;
      ext[g].awuser   = 0;
      ext[g].awvalid  = 0;
      ext[g].wdata    = 0;
      ext[g].wstrb    = 15;
      ext[g].wlast    = 1;
      ext[g].wuser    = 0;
      ext[g].wvalid   = 0;
      ext[g].bready   = 0;
      ext[g].arid     = 0;
      ext[g].araddr   = 0;
      ext[g].arlen    = 0;
      ext[g].arsize   = 2;
      ext[g].arburst  = 1;
      ext[g].arlock   = 0;
      ext[g].arcache  = 0;
      ext[g].arprot   = 0;
      ext[g].arqos    = 0;
      ext[g].arregion = 0;
      ext[g].aruser   = 0;
      ext[g].arvalid  = 0;
      ext[g].rready   = 0;
    end
  end
  task automatic abstract_wait;
    integer        polls;
    logic   [31:0] value;
    polls = 0;
    do begin
      jtag_dmi(0, 7'h16, 0, value);
      polls++;
    end while (value[12] && polls < 128);
    if (value[12] || value[10:8] != 0) $fatal(1, "abstract command status %h", value);
  endtask
  task automatic set_gpr(input logic [4:0] regnum, input logic [31:0] value);
    logic [31:0] unused;
    jtag_dmi(1, 7'h04, value, unused);
    jtag_dmi(1, 7'h17, 32'h00231000 | {27'd0, regnum}, unused);
    abstract_wait();
  endtask
  task automatic execute_debug(input logic [31:0] instruction);
    logic [31:0] unused;
    jtag_dmi(1, 7'h20, instruction, unused);
    jtag_dmi(1, 7'h21, 32'h00100073, unused);
    jtag_dmi(1, 7'h17, 32'h00240000, unused);
    abstract_wait();
  endtask
  task automatic debug_store(input logic [31:0] address, input logic [31:0] value);
    set_gpr(28, address);
    set_gpr(29, value);
    execute_debug(32'h01de2023);  // sw t4,0(t3)
  endtask
  initial begin
    #10000000;
    $display(
        "CPU_DIAG starts=%0d completed=%b core_reset=%b halted=%b pending=%b idle=%b quiesce=%b hold=%b read=%b",
        starts, completed, core_rst_n, halted, u_cpu.s_reset_pending, idle, quiesce, hold_read,
        read_pending);
    $display("CPU_DIAG I addr=%h trans=%b ready=%b D addr=%h trans=%b ready=%b slowstate=%0d",
             cpu[0].haddr, cpu[0].htrans, cpu[0].hready, cpu[1].haddr, cpu[1].htrans,
             cpu[1].hready, u_cpu_mem.s_slow_q.state);
    $fatal(1, "SIM_TEST_TIMEOUT Tiny P4 CPU");
  end
  initial begin
    if (!$value$plusargs("firmware=%s", firmware)) $fatal(1, "missing CPU fixture image");
    $readmemh(firmware, rom);
    cfg.paddr   = 0;
    cfg.pprot   = 0;
    cfg.psel    = 0;
    cfg.penable = 0;
    cfg.pwrite  = 0;
    cfg.pwdata  = 0;
    cfg.pstrb   = 15;
    repeat (6) jtag_tick(1, 0, ignored);
    @(negedge clk_i);
    rst_n_i = 1;
    repeat (12) jtag_tick(1, 0, ignored);
    jtag_idle(1);
    jtag_ir(5'h11);
    wait (starts == 1);
    $display("P4_CPU_STAGE boot-and-boundaries");
    jtag_dmi(1, 7'h10, 1, status);
    jtag_dmi(1, 7'h10, 32'h80000001, status);
    wait (halted);
    $display("P4_CPU_STAGE halted");
    debug_store(32'h30000080, 32'h00200513);
    debug_store(32'h3001ffe0, 1);
    execute_debug(32'h0000100f);  // FENCE.I before debugger resume
    jtag_dmi(1, 7'h10, 32'h40000001, status);
    jtag_dmi(1, 7'h10, 1, status);
    wait (completed);
    $display("P4_CPU_STAGE patched-code-executed");
    // A different external owner retains a B response across hart reset.
    @(negedge clk_i);
    ext[2].awaddr  = 32'h30010100;
    ext[2].awvalid = 1;
    do @(posedge clk_i); while (!ext[2].awready);
    @(negedge clk_i);
    ext[2].awvalid = 0;
    ext[2].wdata   = 32'hdecafbad;
    ext[2].wvalid  = 1;
    do @(posedge clk_i); while (!ext[2].wready);
    @(negedge clk_i);
    ext[2].wvalid = 0;
    wait (ext[2].bvalid);
    @(negedge clk_i);
    hold_read = 1;
    wait (read_pending);
    jtag_dmi(1, 7'h10, 3, status);
    repeat (32) begin
      @(posedge clk_i);
      if (!core_rst_n || !ext[2].bvalid) $fatal(1, "hart reset discarded accepted work");
    end
    @(negedge clk_i);
    hold_read = 0;
    wait (!core_rst_n);
    $display("P4_CPU_STAGE hart-reset-drained");
    if (!ext[2].bvalid) $fatal(1, "hart reset reset external SRAM frontend");
    jtag_dmi(1, 7'h10, 1, status);
    wait (core_rst_n);
    wait (starts == 2);
    @(negedge clk_i);
    ext[2].bready = 1;
    @(posedge clk_i);
    @(negedge clk_i);
    ext[2].bready  = 0;
    ext[2].araddr  = 32'h30010100;
    ext[2].arvalid = 1;
    do @(posedge clk_i); while (!ext[2].arready);
    @(negedge clk_i);
    ext[2].arvalid = 0;
    ext[2].rready  = 1;
    do @(posedge clk_i); while (!ext[2].rvalid);
    if (ext[2].rdata !== 32'hdecafbad || ext[2].rresp != 0)
      $fatal(1, "SRAM payload lost on hart reset");
    $display("SIM_TEST_PASS Tiny P4 CPU compressed-boundaries fence-i debug-patch hart-drain");
    $finish;
  end
endmodule
