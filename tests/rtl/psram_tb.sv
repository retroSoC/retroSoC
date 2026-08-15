// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

`timescale 1ns / 1ps

`include "axi4_define.svh"
`include "psram_define.svh"

module psram_tb;
  localparam logic [31:0] PsramBase = 32'h4000_0000;

  logic        clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic [31:0] reg_data;
  logic [31:0] read_data;
  logic [31:0] held_data;
  logic [ 1:0] held_resp;
  logic        held_last;

  ribp_if cfg_ribp ();
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) mem_axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  psram_if psram ();

  tri1 [3:0] psram_sio;

  always #5 clk_i = ~clk_i;

  for (genvar io_index = 0; io_index < 4; io_index++) begin : gen_psram_io
    assign psram_sio[io_index] = psram.io_oe_o[io_index] ? psram.io_do_o[io_index] : 1'bz;
  end
  assign psram.io_di_i = psram_sio;

  ribp_psram u_dut (
      .clk_i   (clk_i),
      .rst_n_i (rst_n_i),
      .cfg_ribp(cfg_ribp),
      .mem_axi4(mem_axi4),
      .psram   (psram)
  );

  ESP_PSRAM64H #(
      .ID               (0),
      .MEMORY_BYTES     (4096),
      .INITIALIZE_MEMORY(1),
      .POWER_UP_CHECK   (0),
      .TIMING_CHECK     (0)
  ) u_psram0 (
      .sclk(psram.sck_o),
      .csn (psram.nss_o[0]),
      .sio (psram_sio)
  );

  ESP_PSRAM64H #(
      .ID               (1),
      .MEMORY_BYTES     (4096),
      .INITIALIZE_MEMORY(1),
      .POWER_UP_CHECK   (0),
      .TIMING_CHECK     (0)
  ) u_psram1 (
      .sclk(psram.sck_o),
      .csn (psram.nss_o[1]),
      .sio (psram_sio)
  );

  ESP_PSRAM64H #(
      .ID                   (2),
      .MEMORY_BYTES         (4096),
      .INITIALIZE_MEMORY    (1),
      .POWER_UP_CHECK       (0),
      .TIMING_CHECK         (0),
      .INJECT_MISSING_DEVICE(1)
  ) u_psram2 (
      .sclk(psram.sck_o),
      .csn (psram.nss_o[2]),
      .sio (psram_sio)
  );

  ESP_PSRAM64H #(
      .ID               (3),
      .MEMORY_BYTES     (4096),
      .INITIALIZE_MEMORY(1),
      .POWER_UP_CHECK   (0),
      .TIMING_CHECK     (0)
  ) u_psram3 (
      .sclk(psram.sck_o),
      .csn (psram.nss_o[3]),
      .sio (psram_sio)
  );

  task automatic init_axi4;
    begin
      mem_axi4.awid     = '0;
      mem_axi4.awaddr   = '0;
      mem_axi4.awlen    = '0;
      mem_axi4.awsize   = `AXI4_BURST_SIZE_4BYTES;
      mem_axi4.awburst  = `AXI4_BURST_TYPE_INCR;
      mem_axi4.awlock   = `AXI4_LOCK_NORM;
      mem_axi4.awcache  = `AXI4_CACHE_NO_BUF;
      mem_axi4.awprot   = `AXI4_PROT_DATA;
      mem_axi4.awqos    = `AXI4_QOS_NORMAL;
      mem_axi4.awregion = `AXI4_REGION_NORMAL;
      mem_axi4.awuser   = '0;
      mem_axi4.awvalid  = 1'b0;
      mem_axi4.wdata    = '0;
      mem_axi4.wstrb    = '0;
      mem_axi4.wlast    = 1'b0;
      mem_axi4.wuser    = '0;
      mem_axi4.wvalid   = 1'b0;
      mem_axi4.bready   = 1'b0;
      mem_axi4.arid     = '0;
      mem_axi4.araddr   = '0;
      mem_axi4.arlen    = '0;
      mem_axi4.arsize   = `AXI4_BURST_SIZE_4BYTES;
      mem_axi4.arburst  = `AXI4_BURST_TYPE_INCR;
      mem_axi4.arlock   = `AXI4_LOCK_NORM;
      mem_axi4.arcache  = `AXI4_CACHE_NO_BUF;
      mem_axi4.arprot   = `AXI4_PROT_DATA;
      mem_axi4.arqos    = `AXI4_QOS_NORMAL;
      mem_axi4.arregion = `AXI4_REGION_NORMAL;
      mem_axi4.aruser   = '0;
      mem_axi4.arvalid  = 1'b0;
      mem_axi4.rready   = 1'b0;
    end
  endtask

  task automatic ribp_write(input logic [31:0] offset, input logic [31:0] data,
                            input logic [3:0] strobe, input logic expected_error);
    begin
      @(negedge clk_i);
      cfg_ribp.addr  = offset;
      cfg_ribp.wdata = data;
      cfg_ribp.wstrb = strobe;
      cfg_ribp.valid = 1'b1;
      do @(negedge clk_i); while (!cfg_ribp.ready);
      if (cfg_ribp.resp_err != expected_error) begin
        $fatal(1, "RIBP write response mismatch at %08x", offset);
      end
      cfg_ribp.valid = 1'b0;
      cfg_ribp.wstrb = '0;
      @(negedge clk_i);
    end
  endtask

  task automatic ribp_read(input logic [31:0] offset, input logic expected_error,
                           output logic [31:0] data);
    begin
      @(negedge clk_i);
      cfg_ribp.addr  = offset;
      cfg_ribp.wdata = '0;
      cfg_ribp.wstrb = '0;
      cfg_ribp.valid = 1'b1;
      do @(negedge clk_i); while (!cfg_ribp.ready);
      if (cfg_ribp.resp_err != expected_error) begin
        $fatal(1, "RIBP read response mismatch at %08x", offset);
      end
      data           = cfg_ribp.rdata;
      cfg_ribp.valid = 1'b0;
      @(negedge clk_i);
    end
  endtask

  task automatic wait_for_init;
    begin
      reg_data = '0;
      for (int poll = 0; poll < 200; poll++) begin
        repeat (20) @(posedge clk_i);
        ribp_read(`RIBP_PSRAM_INTR_STATE, 1'b0, reg_data);
        if (reg_data[`PSRAM_INTR_INIT_DONE]) return;
      end
      $fatal(1, "PSRAM initialization timed out");
    end
  endtask

  task automatic wait_for_indirect;
    begin
      reg_data = '0;
      for (int poll = 0; poll < 100; poll++) begin
        repeat (10) @(posedge clk_i);
        ribp_read(`RIBP_PSRAM_INTR_STATE, 1'b0, reg_data);
        if (reg_data[`PSRAM_INTR_INDIRECT_DONE]) return;
      end
      $fatal(1, "PSRAM indirect command timed out");
    end
  endtask

  task automatic axi_write_single(input logic [31:0] address, input logic [2:0] size,
                                  input logic [31:0] data, input logic [3:0] strobe,
                                  input logic [1:0] expected_response);
    begin
      @(negedge clk_i);
      mem_axi4.awaddr  = address;
      mem_axi4.awlen   = 8'd0;
      mem_axi4.awsize  = size;
      mem_axi4.awburst = `AXI4_BURST_TYPE_INCR;
      mem_axi4.awvalid = 1'b1;
      do @(posedge clk_i); while (!mem_axi4.awready);
      @(negedge clk_i);
      mem_axi4.awvalid = 1'b0;
      mem_axi4.wdata   = data;
      mem_axi4.wstrb   = strobe;
      mem_axi4.wlast   = 1'b1;
      mem_axi4.wvalid  = 1'b1;
      do @(posedge clk_i); while (!mem_axi4.wready);
      @(negedge clk_i);
      mem_axi4.wvalid = 1'b0;
      do @(negedge clk_i); while (!mem_axi4.bvalid);
      if (mem_axi4.bresp != expected_response) begin
        $fatal(1, "AXI write response mismatch at %08x", address);
      end
      mem_axi4.bready = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      mem_axi4.bready = 1'b0;
      mem_axi4.wlast  = 1'b0;
      @(negedge clk_i);
    end
  endtask

  task automatic axi_read_single(input logic [31:0] address, input logic [2:0] size,
                                 input logic [1:0] expected_response, output logic [31:0] data);
    begin
      @(negedge clk_i);
      mem_axi4.araddr  = address;
      mem_axi4.arlen   = 8'd0;
      mem_axi4.arsize  = size;
      mem_axi4.arburst = `AXI4_BURST_TYPE_INCR;
      mem_axi4.arvalid = 1'b1;
      do @(posedge clk_i); while (!mem_axi4.arready);
      @(negedge clk_i);
      mem_axi4.arvalid = 1'b0;
      do @(negedge clk_i); while (!mem_axi4.rvalid);
      held_data = mem_axi4.rdata;
      held_resp = mem_axi4.rresp;
      held_last = mem_axi4.rlast;
      repeat (3) begin
        @(negedge clk_i);
        if (!mem_axi4.rvalid || (mem_axi4.rdata != held_data) ||
            (mem_axi4.rresp != held_resp) || (mem_axi4.rlast != held_last)) begin
          $fatal(1, "AXI read response changed under backpressure");
        end
      end
      if ((held_resp != expected_response) || !held_last) begin
        $fatal(1, "AXI read response mismatch at %08x", address);
      end
      data            = held_data;
      mem_axi4.rready = 1'b1;
      @(negedge clk_i);
      mem_axi4.rready = 1'b0;
    end
  endtask

  task automatic axi_write_burst4(input logic [31:0] address);
    begin
      @(negedge clk_i);
      mem_axi4.awaddr  = address;
      mem_axi4.awlen   = 8'd3;
      mem_axi4.awsize  = `AXI4_BURST_SIZE_4BYTES;
      mem_axi4.awburst = `AXI4_BURST_TYPE_INCR;
      mem_axi4.awvalid = 1'b1;
      do @(posedge clk_i); while (!mem_axi4.awready);
      @(negedge clk_i);
      mem_axi4.awvalid = 1'b0;
      for (int beat = 0; beat < 4; beat++) begin
        mem_axi4.wdata  = 32'hA500_1000 + beat;
        mem_axi4.wstrb  = 4'hF;
        mem_axi4.wlast  = beat == 3;
        mem_axi4.wvalid = 1'b1;
        do @(posedge clk_i); while (!mem_axi4.wready);
        @(negedge clk_i);
        mem_axi4.wvalid = 1'b0;
      end
      do @(negedge clk_i); while (!mem_axi4.bvalid);
      if (mem_axi4.bresp != `AXI4_RESP_OKAY) $fatal(1, "AXI burst write failed");
      mem_axi4.bready = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      mem_axi4.bready = 1'b0;
      mem_axi4.wlast  = 1'b0;
      @(negedge clk_i);
    end
  endtask

  task automatic axi_read_burst4(input logic [31:0] address);
    begin
      @(negedge clk_i);
      mem_axi4.araddr  = address;
      mem_axi4.arlen   = 8'd3;
      mem_axi4.arsize  = `AXI4_BURST_SIZE_4BYTES;
      mem_axi4.arburst = `AXI4_BURST_TYPE_INCR;
      mem_axi4.arvalid = 1'b1;
      do @(posedge clk_i); while (!mem_axi4.arready);
      @(negedge clk_i);
      mem_axi4.arvalid = 1'b0;
      for (int beat = 0; beat < 4; beat++) begin
        if (beat == 1) repeat (3) @(negedge clk_i);
        do @(negedge clk_i); while (!mem_axi4.rvalid);
        if ((mem_axi4.rdata != (32'hA500_1000 + beat)) ||
            (mem_axi4.rresp != `AXI4_RESP_OKAY) ||
            (mem_axi4.rlast != (beat == 3))) begin
          $fatal(1, "AXI burst read beat %0d failed", beat);
        end
        mem_axi4.rready = 1'b1;
        @(posedge clk_i);
        @(negedge clk_i);
        mem_axi4.rready = 1'b0;
      end
    end
  endtask

  task automatic axi_illegal_read;
    integer beat;
    begin
      @(negedge clk_i);
      mem_axi4.araddr  = PsramBase + 32'h400;
      mem_axi4.arlen   = 8'd16;
      mem_axi4.arsize  = `AXI4_BURST_SIZE_4BYTES;
      mem_axi4.arburst = `AXI4_BURST_TYPE_INCR;
      mem_axi4.arvalid = 1'b1;
      do @(posedge clk_i); while (!mem_axi4.arready);
      @(negedge clk_i);
      mem_axi4.arvalid = 1'b0;
      beat             = 0;
      while (beat < 17) begin
        do @(negedge clk_i); while (!mem_axi4.rvalid);
        if ((mem_axi4.rresp != `AXI4_RESP_SLAVE_ERROR) || (mem_axi4.rlast != (beat == 16))) begin
          $fatal(1, "illegal AXI burst response mismatch");
        end
        mem_axi4.rready = 1'b1;
        @(posedge clk_i);
        @(negedge clk_i);
        mem_axi4.rready = 1'b0;
        beat            = beat + 1;
      end
    end
  endtask

  initial begin
    cfg_ribp.valid = 1'b0;
    cfg_ribp.addr  = '0;
    cfg_ribp.wdata = '0;
    cfg_ribp.wstrb = '0;
    init_axi4();

    repeat (5) @(posedge clk_i);
    rst_n_i = 1'b1;

    $display("PSRAM_TB_STAGE register_setup");
    ribp_write(`RIBP_PSRAM_POWERUP_CYCLES, 32'd1, 4'hF, 1'b0);
    ribp_write(`RIBP_PSRAM_CS_HIGH_CYCLES, 32'd2, 4'hF, 1'b0);
    ribp_write(`RIBP_PSRAM_CS_HOLD_CYCLES, 32'd3, 4'hF, 1'b0);
    ribp_write(`RIBP_PSRAM_CS_MAX_LOW_CYCLES, 32'd512, 4'hF, 1'b0);
    ribp_write(`RIBP_PSRAM_ACCESS_TIMEOUT_CYCLES, 32'd1024, 4'hF, 1'b0);
    ribp_write(`RIBP_PSRAM_PERF_CTRL, 32'd1, 4'h1, 1'b0);
    ribp_write(`RIBP_PSRAM_STATUS, 32'd1, 4'h1, 1'b1);
    ribp_read(32'h0000_0002, 1'b1, reg_data);
    ribp_read(32'h0000_00B0, 1'b1, reg_data);
    ribp_write(`RIBP_PSRAM_COMMAND, 32'h0000_0003, 4'h1, 1'b1);

    $display("PSRAM_TB_STAGE initialization");
    ribp_write(`RIBP_PSRAM_COMMAND, 32'h0000_0001, 4'h1, 1'b0);
    wait_for_init();
    ribp_read(`RIBP_PSRAM_CHIP_PRESENT, 1'b0, reg_data);
    if (reg_data[3:0] != 4'b1011) $fatal(1, "unexpected present mask");
    ribp_read(`RIBP_PSRAM_CHIP_READY, 1'b0, reg_data);
    if (reg_data[3:0] != 4'b1011) $fatal(1, "unexpected ready mask");
    ribp_read(`RIBP_PSRAM_CHIP_ERROR, 1'b0, reg_data);
    if (reg_data[3:0] != 4'b0100) $fatal(1, "missing-device error not isolated");
    ribp_read(`RIBP_PSRAM_CHIP0_ID_LO, 1'b0, reg_data);
    if (reg_data != 32'h0026_5D0D) $fatal(1, "chip ID mismatch");
    ribp_read(`RIBP_PSRAM_CHIP_MODE, 1'b0, reg_data);
    if (reg_data[3:0] != 4'b1011) $fatal(1, "QPI mode mask mismatch");

    $display("PSRAM_TB_STAGE basic_axi");
    axi_write_single(PsramBase + 32'h100, `AXI4_BURST_SIZE_4BYTES, 32'hDEAD_BEEF, 4'hF,
                     `AXI4_RESP_OKAY);
    axi_read_single(PsramBase + 32'h100, `AXI4_BURST_SIZE_4BYTES, `AXI4_RESP_OKAY, read_data);
    if (read_data != 32'hDEAD_BEEF) $fatal(1, "word readback mismatch");
    axi_write_single(PsramBase + 32'h101, `AXI4_BURST_SIZE_1BYTE, 32'h0000_AA00, 4'h2,
                     `AXI4_RESP_OKAY);
    axi_read_single(PsramBase + 32'h100, `AXI4_BURST_SIZE_4BYTES, `AXI4_RESP_OKAY, read_data);
    if (read_data != 32'hDEAD_AAEF) $fatal(1, "byte write address or lane mismatch");

    axi_write_single(PsramBase + 32'h104, `AXI4_BURST_SIZE_4BYTES, 32'd0, 4'hF, `AXI4_RESP_OKAY);
    axi_write_single(PsramBase + 32'h104, `AXI4_BURST_SIZE_4BYTES, 32'h4433_2211, 4'b0101,
                     `AXI4_RESP_OKAY);
    axi_read_single(PsramBase + 32'h104, `AXI4_BURST_SIZE_4BYTES, `AXI4_RESP_OKAY, read_data);
    if (read_data != 32'h0033_0011) $fatal(1, "masked write mismatch");

    $display("PSRAM_TB_STAGE burst_axi");
    axi_write_burst4(PsramBase + 32'h200);
    axi_read_burst4(PsramBase + 32'h200);
    axi_illegal_read();

    axi_read_single(PsramBase + 32'h0100_0000, `AXI4_BURST_SIZE_4BYTES, `AXI4_RESP_SLAVE_ERROR,
                    read_data);
    axi_write_single(PsramBase + 32'h0180_0300, `AXI4_BURST_SIZE_4BYTES, 32'hC001_CAFE, 4'hF,
                     `AXI4_RESP_OKAY);
    axi_read_single(PsramBase + 32'h0180_0300, `AXI4_BURST_SIZE_4BYTES, `AXI4_RESP_OKAY, read_data);
    if (read_data != 32'hC001_CAFE) $fatal(1, "healthy chip after missing device failed");

    $display("PSRAM_TB_STAGE indirect");
    ribp_write(`RIBP_PSRAM_INTR_STATE, 32'hF, 4'h1, 1'b0);
    ribp_write(`RIBP_PSRAM_INDIRECT_CTRL, 32'h8000_0009, 4'hF, 1'b0);
    wait_for_indirect();
    ribp_read(`RIBP_PSRAM_CHIP_MODE, 1'b0, reg_data);
    if (!reg_data[4]) $fatal(1, "wrap32 mode did not update");

    $display("PSRAM_TB_STAGE timeout");
    ribp_write(`RIBP_PSRAM_CS_MAX_LOW_CYCLES, 32'd20, 4'hF, 1'b0);
    axi_read_single(PsramBase + 32'h0080_0800, `AXI4_BURST_SIZE_4BYTES, `AXI4_RESP_SLAVE_ERROR,
                    read_data);
    ribp_read(`RIBP_PSRAM_CHIP_READY, 1'b0, reg_data);
    if (reg_data[3:0] != 4'b1001) $fatal(1, "timeout fault was not isolated");
    ribp_write(`RIBP_PSRAM_CS_MAX_LOW_CYCLES, 32'd512, 4'hF, 1'b0);
    axi_read_single(PsramBase + 32'h0180_0300, `AXI4_BURST_SIZE_4BYTES, `AXI4_RESP_OKAY, read_data);
    if (read_data != 32'hC001_CAFE) $fatal(1, "healthy chip failed after timeout");

    $display("PSRAM_TB_STAGE counters");
    ribp_read(`RIBP_PSRAM_PERF_READ_BYTES, 1'b0, reg_data);
    if (reg_data == 32'd0) $fatal(1, "read performance counter did not advance");
    ribp_read(`RIBP_PSRAM_PERF_WRITE_BYTES, 1'b0, reg_data);
    if (reg_data == 32'd0) $fatal(1, "write performance counter did not advance");
    ribp_read(`RIBP_PSRAM_PERF_COMMANDS, 1'b0, reg_data);
    if (reg_data == 32'd0) $fatal(1, "command performance counter did not advance");

    $display("PSRAM controller integration test passed");
    $finish;
  end
endmodule
