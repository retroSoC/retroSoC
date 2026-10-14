`include "tiny_topology.svh"
`timescale 1ns / 1ps
module tiny_r2_p5_system_tb;
  logic clk_i = 0, rst_n_i = 0;
  always #20.833 clk_i = ~clk_i;
  wire s_rst_n = rst_n_i;
  logic s_jtag_tck_driver = 0, s_jtag_tms_driver = 1, s_jtag_tdi_driver = 0;
  wire s_jtag_tdo;
  logic done, pass;
  logic [7:0] code;
  gpio_if gpio ();
  xpi_if xpi ();
  integer overlap_cycles = 0, progress = 0, controls = 0, controls_before = 0;
  logic        hart_reset_observed = 0;
  logic [31:0] status;
  bit          ignored;
  `include "tiny_jtag_smoke.svh"
retrosoc_tiny u_dut (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .jtag_tck_i   (s_jtag_tck_driver),
      .jtag_tms_i   (s_jtag_tms_driver),
      .jtag_tdi_i   (s_jtag_tdi_driver),
      .jtag_trst_n_i(rst_n_i),
      .jtag_tdo_o   (s_jtag_tdo),
      .uart0_rx_i   (1'b1),
      .uart1_rx_i   (1'b1),
      .gpio         (gpio),
      .xpi          (xpi),
      .test_done_o  (done),
      .test_pass_o  (pass),
      .test_code_o  (code)
  );
  assign gpio.di_i   = 0;
  assign xpi.io_di_i = 0;
  always @(posedge clk_i) begin
    if (rst_n_i) begin
      if(u_dut.u_masters_axi4_if[1].rvalid && u_dut.u_masters_axi4_if[1].rready &&
         u_dut.u_masters_axi4_if[1].wvalid && u_dut.u_masters_axi4_if[1].wready)
        overlap_cycles++;
      if((u_dut.u_fabric.s_busy_q[2] || u_dut.u_fabric.s_busy_q[3]) &&
         (!u_dut.u_fabric.target_idle_o[4] || !u_dut.u_fabric.target_idle_o[`RETROSOC_TINY__TARGET_XPI]) &&
         u_dut.u_sysctrl_apb4_if.psel && u_dut.u_sysctrl_apb4_if.penable && u_dut.u_sysctrl_apb4_if.pready)
        controls++;
      if(u_dut.u_cpu_local_if[1].req_valid && u_dut.u_cpu_local_if[1].req_ready &&
         u_dut.u_cpu_local_if[1].write && u_dut.u_cpu_local_if[1].addr==32'h3001ffe0) begin
        progress = integer'(u_dut.u_cpu_local_if[1].wdata);
        if (progress == 2) u_dut.u_xpi.hold_mapped = 1;
        if (progress == 3) begin
          if (!u_dut.u_fabric.s_busy_q[2]) $fatal(1, "abort discarded accepted read");
          u_dut.u_xpi.hold_mapped = 0;
        end
      end
    end
  end
  initial begin
    repeat (6) jtag_tick(1, 0, ignored);
    @(negedge clk_i);
    rst_n_i = 1;
    repeat (12) jtag_tick(1, 0, ignored);
    jtag_idle(1);
    jtag_ir(5'h11);
    wait (progress == 1);
    $display("P5_SYSTEM_STAGE independent-progress");
    if (controls == 0 || overlap_cycles == 0 || !u_dut.u_fabric.s_busy_q[2])
      $fatal(1, "CPU/control progress or real DMA overlap absent");
    // Move the held DMA work to an independent APB branch before resetting
    // the hart. CPU debug entry may fetch the reset/exception ROM aperture;
    // accepted CPU work must be allowed to drain rather than discarded.
    @(negedge clk_i);
    u_dut.u_xpi.hold_mapped = 0;
    wait (u_dut.u_xpi_apb4_if.psel && u_dut.u_xpi_apb4_if.penable && !u_dut.u_xpi_apb4_if.pready);
    controls_before = controls;
    repeat (64) @(posedge clk_i);
    if (controls == controls_before) $fatal(1, "APB FIFO wait blocked independent control");
    jtag_dmi(1, 7'h10, 1, status);
    jtag_dmi(1, 7'h10, 3, status);
    $display("P5_SYSTEM_STAGE reset-request pending=%b", u_dut.u_cpu.s_reset_pending);
    wait (!u_dut.s_core_rst_n);
    if (!u_dut.u_fabric.s_busy_q[3] || u_dut.u_fabric.target_idle_o[`RETROSOC_TINY__TARGET_XPI])
      $fatal(1, "hart reset cancelled unrelated DMA");
    hart_reset_observed = 1;
    $display("P5_SYSTEM_STAGE hart-reset");
    jtag_dmi(1, 7'h10, 1, status);
    wait (u_dut.s_core_rst_n);
    @(negedge clk_i);
    u_dut.u_xpi.hold_apb = 0;
    $display("P5_SYSTEM_STAGE released");
    wait (done);
    if (!pass || !hart_reset_observed || progress != 3)
      $fatal(1, "SIM_TEST_FAIL P5 CPU/DMA code=%0d", code);
    repeat (20) @(posedge clk_i);
    $display(
        "P5_SYSTEM dma_overlap_cycles=%0d independent_controls=%0d hart_reset=1 abort_drained=1",
        overlap_cycles, controls);
    $display("SIM_TEST_PASS Tiny P5 system");
    $finish;
  end
  initial begin
    repeat (500000) @(posedge clk_i);
    $display(
        "P5_DIAG core_rst=%b pending=%b halted=%b idle=%b quiesce=%b hold=%b busy=%b I=%h D=%h",
        u_dut.s_core_rst_n, u_dut.u_cpu.s_reset_pending, u_dut.s_debug_halted,
        u_dut.s_cpu_bus_idle, u_dut.s_cpu_quiesce, u_dut.u_xpi.hold_mapped,
        u_dut.u_fabric.s_busy_q, u_dut.u_cpu_ahbl_if[0].haddr, u_dut.u_cpu_ahbl_if[1].haddr);
    $fatal(1, "SIM_TEST_TIMEOUT Tiny P5 system progress=%0d", progress);
  end
endmodule

// Verification-only XPI boundary substitute. The production Tiny integration,
// CPU, DMA, SRAM, APB branches and SYSCTRL remain real. This does not qualify an
// XPI device or replace the pin-level NOR regression. The small reset ROM is
// only a fixture boot source, never a product Boot ROM.
module apb4_xpi (
    output logic         lifecycle_idle_o,
    input  logic         clk_i,
    rst_n_i,
    dma_xfer_done_i,
    output logic         dma_tx_stall_o,
    dma_rx_stall_o,
    irq_o,
           apb4_if.slave apb4,
           axi4_if.slave mem_axi4,
           xpi_if.dut    xpi
);
  logic  [7:0] rom      [0:4095];
  string       firmware;
  logic active = 0, id = 0, hold_mapped = 1, hold_apb = 1;
  logic [31:0] captured_write = 0;
  logic [31:0] address = 0;
  logic [7:0] beat = 0, length = 0;
  assign lifecycle_idle_o = !active && !(apb4.psel && apb4.penable);
  initial begin
    if (!$value$plusargs("firmware=%s", firmware)) $fatal(1, "firmware required");
    $readmemh(firmware, rom);
  end
  assign dma_tx_stall_o = 0;
  assign dma_rx_stall_o = 0;
  assign irq_o = 0;
  assign xpi.sck_o = 0;
  assign xpi.nss_o = '1;
  assign xpi.io_oe_o = 0;
  assign xpi.io_do_o = 0;
  assign apb4.pready=apb4.psel && apb4.penable &&
      !(apb4.pwrite && apb4.paddr[11:0]==12'h040 && hold_apb);
  assign apb4.pslverr = 0;
  assign apb4.prdata = (apb4.paddr[11:0] == 12'h044) ? captured_write : 32'd0;
  assign mem_axi4.arready = !active;
  assign mem_axi4.awready = 0;
  assign mem_axi4.wready = 0;
  assign mem_axi4.bvalid = 0;
  assign mem_axi4.bid = 0;
  assign mem_axi4.bresp = 0;
  assign mem_axi4.buser = 0;
  assign mem_axi4.rresp = 0;
  assign mem_axi4.ruser = 0;
  always @(posedge clk_i) begin
    if (rst_n_i && apb4.psel && apb4.penable && apb4.pready && apb4.pwrite)
      captured_write <= apb4.pwdata;
    if (!rst_n_i) begin
      active          <= 0;
      mem_axi4.rvalid <= 0;
      mem_axi4.rdata  <= 0;
      mem_axi4.rid    <= 0;
      mem_axi4.rlast  <= 0;
    end else begin
      if (mem_axi4.arvalid && mem_axi4.arready) begin
        active  <= 1;
        address <= mem_axi4.araddr;
        id      <= mem_axi4.arid;
        beat    <= 0;
        length  <= mem_axi4.arlen;
      end
      if (active && !mem_axi4.rvalid && !(hold_mapped && address >= 32'h50000000)) begin
        mem_axi4.rvalid <= 1;
        mem_axi4.rid    <= id;
        mem_axi4.rlast  <= beat == length;
        if (address < 4096)
          mem_axi4.rdata <= {rom[address+3], rom[address+2], rom[address+1], rom[address]};
        else mem_axi4.rdata <= 32'h10000000 ^ address;
      end
      if (mem_axi4.rvalid && mem_axi4.rready) begin
        mem_axi4.rvalid <= 0;
        if (mem_axi4.rlast) active <= 0;
        else begin
          address <= address + 4;
          beat    <= beat + 1;
        end
      end
    end
  end
endmodule
