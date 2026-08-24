`timescale 1ns / 1ps

`include "axi4_define.svh"

module onchip_ram_perf_tb;
  logic          clk_i = 1'b0;
  logic          rst_n_i = 1'b0;
  logic   [31:0] s_legacy_memory [0:1023];
  integer        s_native_cycles;
  integer        s_legacy_cycles;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) native_axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) legacy_axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  apb4_if cfg_apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  ram_if legacy_ram ();

  always #5 clk_i = ~clk_i;

  always_ff @(posedge clk_i) begin
    legacy_ram.rdata <= s_legacy_memory[legacy_ram.addr[9:0]];
    for (int lane = 0; lane < 4; lane++) begin
      if (legacy_ram.wstrb[lane]) begin
        s_legacy_memory[legacy_ram.addr[9:0]][lane*8+:8] <= legacy_ram.wdata[lane*8+:8];
      end
    end
  end

  onchip_ram #(
      .Present    (1'b1),
      .CapacityKiB(4)
  ) u_native (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .perf_enable_i(1'b0),
      .perf_clear_i (1'b0),
      .mem_axi4     (native_axi4),
      .cfg_apb4     (cfg_apb4)
  );
  axi42ram u_legacy (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .axi4   (legacy_axi4),
      .ram    (legacy_ram)
  );

  task automatic init_axi4;
    begin
      native_axi4.awid     = '0;
      native_axi4.awaddr   = '0;
      native_axi4.awlen    = '0;
      native_axi4.awsize   = `AXI4_BURST_SIZE_4BYTES;
      native_axi4.awburst  = `AXI4_BURST_TYPE_INCR;
      native_axi4.awlock   = 1'b0;
      native_axi4.awcache  = '0;
      native_axi4.awprot   = '0;
      native_axi4.awqos    = '0;
      native_axi4.awregion = '0;
      native_axi4.awuser   = '0;
      native_axi4.awvalid  = 1'b0;
      native_axi4.wdata    = '0;
      native_axi4.wstrb    = '0;
      native_axi4.wlast    = 1'b0;
      native_axi4.wuser    = '0;
      native_axi4.wvalid   = 1'b0;
      native_axi4.bready   = 1'b0;
      native_axi4.arid     = '0;
      native_axi4.araddr   = '0;
      native_axi4.arlen    = '0;
      native_axi4.arsize   = `AXI4_BURST_SIZE_4BYTES;
      native_axi4.arburst  = `AXI4_BURST_TYPE_INCR;
      native_axi4.arlock   = 1'b0;
      native_axi4.arcache  = '0;
      native_axi4.arprot   = '0;
      native_axi4.arqos    = '0;
      native_axi4.arregion = '0;
      native_axi4.aruser   = '0;
      native_axi4.arvalid  = 1'b0;
      native_axi4.rready   = 1'b1;
      legacy_axi4.awid     = '0;
      legacy_axi4.awaddr   = '0;
      legacy_axi4.awlen    = '0;
      legacy_axi4.awsize   = `AXI4_BURST_SIZE_4BYTES;
      legacy_axi4.awburst  = `AXI4_BURST_TYPE_INCR;
      legacy_axi4.awlock   = 1'b0;
      legacy_axi4.awcache  = '0;
      legacy_axi4.awprot   = '0;
      legacy_axi4.awqos    = '0;
      legacy_axi4.awregion = '0;
      legacy_axi4.awuser   = '0;
      legacy_axi4.awvalid  = 1'b0;
      legacy_axi4.wdata    = '0;
      legacy_axi4.wstrb    = '0;
      legacy_axi4.wlast    = 1'b0;
      legacy_axi4.wuser    = '0;
      legacy_axi4.wvalid   = 1'b0;
      legacy_axi4.bready   = 1'b0;
      legacy_axi4.arid     = '0;
      legacy_axi4.araddr   = '0;
      legacy_axi4.arlen    = '0;
      legacy_axi4.arsize   = `AXI4_BURST_SIZE_4BYTES;
      legacy_axi4.arburst  = `AXI4_BURST_TYPE_INCR;
      legacy_axi4.arlock   = 1'b0;
      legacy_axi4.arcache  = '0;
      legacy_axi4.arprot   = '0;
      legacy_axi4.arqos    = '0;
      legacy_axi4.arregion = '0;
      legacy_axi4.aruser   = '0;
      legacy_axi4.arvalid  = 1'b0;
      legacy_axi4.rready   = 1'b1;
      cfg_apb4.paddr       = '0;
      cfg_apb4.pprot       = '0;
      cfg_apb4.psel        = 1'b0;
      cfg_apb4.penable     = 1'b0;
      cfg_apb4.pwrite      = 1'b0;
      cfg_apb4.pwdata      = '0;
      cfg_apb4.pstrb       = '0;
    end
  endtask

  task automatic measure_native;
    integer beats;
    begin
      @(negedge clk_i);
      native_axi4.araddr  = `SOC_ADDR_SRAM_BASE;
      native_axi4.arlen   = 8'd15;
      native_axi4.arvalid = 1'b1;
      do @(posedge clk_i); while (!native_axi4.arready);
      @(negedge clk_i);
      native_axi4.arvalid = 1'b0;
      s_native_cycles     = 0;
      beats               = 0;
      while (beats < 16) begin
        @(posedge clk_i);
        s_native_cycles = s_native_cycles + 1;
        if (native_axi4.rvalid) beats = beats + 1;
      end
    end
  endtask

  task automatic measure_legacy;
    integer beats;
    begin
      @(negedge clk_i);
      legacy_axi4.araddr  = `SOC_ADDR_SRAM_BASE;
      legacy_axi4.arlen   = 8'd15;
      legacy_axi4.arvalid = 1'b1;
      do @(posedge clk_i); while (!legacy_axi4.arready);
      @(negedge clk_i);
      legacy_axi4.arvalid = 1'b0;
      s_legacy_cycles     = 0;
      beats               = 0;
      while (beats < 16) begin
        @(posedge clk_i);
        s_legacy_cycles = s_legacy_cycles + 1;
        if (legacy_axi4.rvalid) beats = beats + 1;
      end
    end
  endtask

  initial begin
    init_axi4();
    repeat (3) @(posedge clk_i);
    @(negedge clk_i);
    rst_n_i = 1'b1;
    measure_native();
    measure_legacy();
    $display("on-chip SRAM burst cycles native=%0d legacy=%0d", s_native_cycles, s_legacy_cycles);
    if ((s_native_cycles != 16) || (s_legacy_cycles < (s_native_cycles + 2))) begin
      $fatal(1, "native SRAM did not reach one beat per cycle or remove bridge overhead");
    end
    $finish;
  end
endmodule
