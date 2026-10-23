`timescale 1ns / 1ps

// Production APB/AXI wrapper and real serial device. No memory backdoor.
module tiny_p8_xpi_tb;
  import xpi_pkg::*;
  logic s_clk = 0, s_rst_n = 0;
  apb4_if apb (
      s_clk,
      s_rst_n
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) axi ();
  xpi_if pins ();
  tri1 [3:0] s_data;
  logic s_idle, s_tx_stall, s_rx_stall, s_irq;
  logic   [31:0] s_value;
  integer        s_commands = 0;

  always #20.833 s_clk = ~s_clk;
  for (genvar i = 0; i < 4; i++) begin : gen_pads
    assign s_data[i] = pins.io_oe_o[i] ? pins.io_do_o[i] : 1'bz;
  end
  assign pins.io_di_i = s_data;
  always @(negedge pins.nss_o[1]) s_commands++;

  apb4_xpi u_dut (
      .clk_i           (s_clk),
      .rst_n_i         (s_rst_n),
      .dma_xfer_done_i (1'b0),
      .lifecycle_idle_o(s_idle),
      .dma_tx_stall_o  (s_tx_stall),
      .dma_rx_stall_o  (s_rx_stall),
      .irq_o           (s_irq),
      .apb4            (apb),
      .mem_axi4        (axi),
      .xpi             (pins)
  );
  ESP_PSRAM64H #(
      .POWER_UP_CHECK        (1),
      .TIMING_VIOLATION_FATAL(1)
  ) u_ram (
      .sclk(pins.sck_o),
      .csn (pins.nss_o[1]),
      .sio (s_data)
  );

  task automatic access (input bit write, input logic [11:0] addr, input logic [31:0] data,
                         output logic [31:0] result);
    @(negedge s_clk);
    apb.psel    = 1;
    apb.penable = 0;
    apb.pwrite  = write;
    apb.paddr   = {20'd0, addr};
    apb.pwdata  = data;
    apb.pstrb   = 4'hf;
    @(negedge s_clk);
    apb.penable = 1;
    do @(posedge s_clk); while (!apb.pready);
    if (apb.pslverr) $fatal(1, "SIM_TEST_FAIL APB addr=%h", addr);
    result = apb.prdata;
    @(negedge s_clk);
    apb.psel    = 0;
    apb.penable = 0;
  endtask
  task automatic wr(input logic [11:0] addr, input logic [31:0] data);
    logic [31:0] unused;
    access (1, addr, data, unused);
  endtask
  task automatic rd(input logic [11:0] addr, output logic [31:0] data);
    access (0, addr, 0, data);
  endtask
  task automatic idle;
    logic [31:0] status;
    do rd(12'h010, status); while ((status & 32'h0e) != 0);
  endtask
  task automatic program_lut(input int seq, input logic [15:0] a, b, c, d);
    wr(12'(12'h200 + seq * 16), {b, a});
    wr(12'(12'h204 + seq * 16), {d, c});
    wr(12'(12'h208 + seq * 16), 0);
    wr(12'(12'h20c + seq * 16), 0);
  endtask
  task automatic command(input logic [7:0] opcode, input logic [1:0] pads);
    idle();
    wr(12'h00c, 0);
    program_lut(3, xpi_instr(XpiInstrCommand, pads, opcode), 0, 0, 0);
    wr(12'h00c, 1);
    wr(12'h024, 255);
    wr(12'h048, 0);
    wr(12'h04c, 0);
    wr(12'h050, 32'h31);
    wr(12'h014, 1);
    idle();
    rd(12'h024, s_value);
    if ((s_value & 32'h61) != 1) $fatal(1, "SIM_TEST_FAIL command %h status=%h", opcode, s_value);
  endtask

  task automatic write_burst(input logic [31:0] addr, input int beats, input logic [2:0] size,
                             input logic [1:0] expected, input logic [31:0] pattern,
                             input logic [3:0] strobes);
    @(negedge s_clk);
    axi.awaddr  = addr;
    axi.awlen   = 8'(beats - 1);
    axi.awsize  = size;
    axi.awvalid = 1;
    do @(posedge s_clk); while (!axi.awready);
    @(negedge s_clk);
    axi.awvalid = 0;
    for (int b = 0; b < beats; b++) begin
      axi.wdata  = pattern + 32'(b);
      axi.wstrb  = size < 2 ? 4'(((1 << (1 << size)) - 1) << ((addr + (b << size)) & 3)) : strobes;
      axi.wlast  = (b == beats - 1);
      axi.wvalid = 1;
      do @(posedge s_clk); while (!axi.wready);
      @(negedge s_clk);
      axi.wvalid = 0;
    end
    do @(posedge s_clk); while (!axi.bvalid);
    if (axi.bresp !== expected)
      $fatal(1, "SIM_TEST_FAIL write addr=%h resp=%h expected=%h", addr, axi.bresp, expected);
    @(negedge s_clk);
  endtask
  task automatic read_burst(input logic [31:0] addr, input int beats, input logic [1:0] expected,
                            input logic [31:0] pattern);
    @(negedge s_clk);
    axi.araddr  = addr;
    axi.arlen   = 8'(beats - 1);
    axi.arvalid = 1;
    do @(posedge s_clk); while (!axi.arready);
    @(negedge s_clk);
    axi.arvalid = 0;
    for (int b = 0; b < beats; b++) begin
      do @(posedge s_clk); while (!axi.rvalid);
      if (axi.rresp !== expected || axi.rlast !== (b == beats - 1))
        $fatal(1, "SIM_TEST_FAIL read response addr=%h beat=%0d resp=%h", addr, b, axi.rresp);
      if (expected == 0 && axi.rdata !== pattern + 32'(b))
        $fatal(
            1,
            "SIM_TEST_FAIL readback addr=%h beat=%0d got=%h expected=%h",
            addr,
            b,
            axi.rdata,
            pattern + 32'(b)
        );
      @(negedge s_clk);
    end
    idle();
  endtask

  task automatic held_read;
    @(negedge s_clk);
    axi.araddr  = 32'h54000000;
    axi.arlen   = 1;
    axi.arvalid = 1;
    axi.rready  = 0;
    do @(posedge s_clk); while (!axi.arready);
    @(negedge s_clk);
    axi.arvalid = 0;
    do @(posedge s_clk); while (!axi.rvalid);
    for (int i = 0; i < 250; i++) begin
      @(negedge s_clk);
      if (!axi.rvalid || axi.rresp !== 0 || axi.rdata !== 32'h12345678 || axi.rlast)
        $fatal(1, "SIM_TEST_FAIL held read changed across core timeout");
    end
    axi.rready = 1;
    @(posedge s_clk);
    @(negedge s_clk);
    do @(posedge s_clk); while (!axi.rvalid);
    if (axi.rresp !== 2 || !axi.rlast) $fatal(1, "SIM_TEST_FAIL timeout tail");
    @(negedge s_clk);
    idle();
  endtask

  initial begin
    #2000000;
    $fatal(1, "SIM_TEST_TIMEOUT Tiny P8 XPI");
  end
  initial begin
    apb.psel     = 0;
    apb.penable  = 0;
    apb.pwrite   = 0;
    apb.paddr    = 0;
    apb.pwdata   = 0;
    apb.pstrb    = 0;
    apb.pprot    = 0;
    axi.awid     = 0;
    axi.awaddr   = 0;
    axi.awlen    = 0;
    axi.awsize   = 2;
    axi.awburst  = 1;
    axi.awlock   = 0;
    axi.awcache  = 0;
    axi.awprot   = 0;
    axi.awqos    = 0;
    axi.awregion = 0;
    axi.awuser   = 0;
    axi.awvalid  = 0;
    axi.wdata    = 0;
    axi.wstrb    = 0;
    axi.wlast    = 0;
    axi.wuser    = 0;
    axi.wvalid   = 0;
    axi.bready   = 1;
    axi.arid     = 0;
    axi.araddr   = 0;
    axi.arlen    = 0;
    axi.arsize   = 2;
    axi.arburst  = 1;
    axi.arlock   = 0;
    axi.arcache  = 0;
    axi.arprot   = 0;
    axi.arqos    = 0;
    axi.arregion = 0;
    axi.aruser   = 0;
    axi.arvalid  = 0;
    axi.rready   = 1;
    repeat (5) @(negedge s_clk);
    s_rst_n = 1;
    #150000;
    wr(12'h00c, 0);
    wr(12'h120, 1);
    wr(12'h124, 32'h800000);
    wr(12'h128, 32'h21);
    wr(12'h12c, 32'h02010100);
    wr(12'h130, 192);
    wr(12'h134, 1024);
    program_lut(1, 16'h18eb, 16'h2818, 16'h4006, 16'h6800);
    program_lut(2, 16'h1838, 16'h2818, 16'h5800, 0);
    // Read ID: SPI 9f, 24 address bits, six bytes, no dummy clocks.
    program_lut(4, 16'h109f, 16'h2018, 16'h6000, 0);
    wr(12'h00c, 1);
    command(8'h66, 0);
    command(8'h99, 0);
    #100;
    wr(12'h024, 255);
    wr(12'h048, 0);
    wr(12'h04c, 6);
    wr(12'h050, 32'h41);
    wr(12'h014, 1);
    idle();
    rd(12'h044, s_value);
    if (s_value[23:0] !== 24'h265d0d) $fatal(1, "SIM_TEST_FAIL PSRAM identity %h", s_value);
    rd(12'h044, s_value);
    command(8'h35, 0);
    idle();
    wr(12'h00c, 0);
    wr(12'h120, 7);
    wr(12'h00c, 1);

    if ($test$plusargs("boundary")) begin
      read_burst(32'h540003fc, 2, 2, 0);
      read_burst(32'h54000ffc, 2, 2, 0);
      read_burst(32'h54800000, 1, 2, 0);
      write_burst(32'h540003fc, 2, 2, 2, 0, 4'hf);
      write_burst(32'h54000ffc, 2, 2, 2, 0, 4'hf);
      write_burst(32'h54800000, 1, 2, 2, 0, 4'hf);
      write_burst(32'h00000000, 1, 2, 2, 0, 4'hf);
    end else if ($test$plusargs("lanes")) begin
      write_burst(32'h54000200, 1, 2, 0, 32'h00000000, 4'hf);
      write_burst(32'h54000200, 4, 0, 0, 32'h44332211, 4'hf);
      read_burst(32'h54000200, 1, 0, 32'h44332211);
      write_burst(32'h54000200, 2, 1, 0, 32'h88776655, 4'hf);
      read_burst(32'h54000200, 1, 0, 32'h88776655);
      write_burst(32'h54000200, 1, 2, 0, 32'h01020304, 4'h5);
      read_burst(32'h54000200, 1, 0, 32'h88026604);
      write_burst(32'h54000200, 1, 2, 0, 32'hffffffff, 4'h0);
      read_burst(32'h54000200, 1, 0, 32'h88026604);
    end else if ($test$plusargs("timeout")) begin
      // A mapped TX must retire with error even if the core times out
      // before accepting its first payload byte.
      idle();
      wr(12'h00c, 0);
      wr(12'h130, 1);
      wr(12'h00c, 1);
      write_burst(32'h54000000, 1, 2, 2, 32'h12345678, 4'h1);
    end else if ($test$plusargs("short_read")) begin
      idle();
      wr(12'h00c, 0);
      program_lut(1, 0, 0, 0, 0);
      wr(12'h00c, 1);
      read_burst(32'h54000000, 1, 2, 0);
    end else if (!$test$plusargs("identity")) begin
      write_burst(32'h54000000, 1, 2, 0, 32'h12345678, 4'hf);
      if ($test$plusargs("held_read")) held_read();
      else if ($test$plusargs("late_error")) begin
        idle();
        wr(12'h00c, 0);
        wr(12'h218, 32'h0000f000);
        wr(12'h00c, 1);
        read_burst(32'h54000000, 1, 2, 0);
      end else begin
        read_burst(32'h54000000, 1, 0, 32'h12345678);
        write_burst(32'h547ffffc, 1, 2, 0, 32'h89abcdef, 4'hf);
        read_burst(32'h547ffffc, 1, 0, 32'h89abcdef);
      end
    end
    $display("SIM_TEST_PASS Tiny P8 XPI pins");
    $finish;
  end
endmodule
