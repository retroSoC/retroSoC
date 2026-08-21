// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of the Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// INCLUDING, BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY OR FITNESS FOR A
// PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`timescale 1ns / 1ps

module sdio_dual_tb;
  localparam logic [31:0] HostCtrl = 32'h00C;
  localparam logic [31:0] ClockCtrl = 32'h010;
  localparam logic [31:0] BusCtrl = 32'h018;
  localparam logic [31:0] CmdArg = 32'h040;
  localparam logic [31:0] CmdCfg = 32'h044;
  localparam logic [31:0] CmdStart = 32'h048;
  localparam logic [31:0] CmdStatus = 32'h04C;
  localparam logic [31:0] Resp0 = 32'h050;
  localparam logic [31:0] BlockSize = 32'h080;
  localparam logic [31:0] BlockCount = 32'h084;
  localparam logic [31:0] DataCfg = 32'h088;
  localparam logic [31:0] DataStart = 32'h08C;
  localparam logic [31:0] PioData = 32'h090;
  localparam logic [31:0] Status = 32'h028;
  localparam logic [31:0] ErrorStatus = 32'h10C;

  logic clk_i = 1'b0;
  logic rst0_n_i = 1'b0;
  logic rst1_n_i = 1'b0;
  apb4_if apb0 (
      .pclk   (clk_i),
      .presetn(rst0_n_i)
  );
  apb4_if apb1 (
      .pclk   (clk_i),
      .presetn(rst1_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) axi0 (
      .aclk   (clk_i),
      .aresetn(rst0_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) axi1 (
      .aclk   (clk_i),
      .aresetn(rst1_n_i)
  );
  sdio_if sdio0 ();
  sdio_if sdio1 ();
  logic          card0_cmd_do;
  logic   [ 3:0] card0_dat_do;
  logic          card0_irq;
  logic          card1_cmd_do;
  logic   [ 3:0] card1_dat_do;
  logic          card1_irq;
  logic   [31:0] value0;
  logic   [31:0] value1;
  integer        guard0;
  integer        guard1;

  assign sdio0.cmd_di_i = sdio0.cmd_oe_o ? sdio0.cmd_do_o : card0_cmd_do;
  assign sdio0.dat_di_i = (sdio0.dat_oe_o & sdio0.dat_do_o) | (~sdio0.dat_oe_o & card0_dat_do);
  assign sdio1.cmd_di_i = sdio1.cmd_oe_o ? sdio1.cmd_do_o : card1_cmd_do;
  assign sdio1.dat_di_i = (sdio1.dat_oe_o & sdio1.dat_do_o) | (~sdio1.dat_oe_o & card1_dat_do);

  always #5 clk_i = ~clk_i;

  apb4_sdio u_sdio0 (
      .clk_i   (clk_i),
      .rst_n_i (rst0_n_i),
      .apb4    (apb0),
      .dma_axi4(axi0),
      .sdio    (sdio0)
  );
  apb4_sdio u_sdio1 (
      .clk_i   (clk_i),
      .rst_n_i (rst1_n_i),
      .apb4    (apb1),
      .dma_axi4(axi1),
      .sdio    (sdio1)
  );

  sdio_sd_memory_model #(
      .HighCapacity(1'b1),
      .BusyCycles  (8)
  ) u_card0 (
      .rst_n_i (rst0_n_i),
      .sck_i   (sdio0.sck_o),
      .cmd_oe_i(sdio0.cmd_oe_o),
      .cmd_do_i(sdio0.cmd_do_o),
      .cmd_do_o(card0_cmd_do),
      .dat_oe_i(sdio0.dat_oe_o),
      .dat_do_i(sdio0.dat_do_o),
      .dat_do_o(card0_dat_do),
      .irq_o   (card0_irq)
  );
  sdio_sdio_model #(
      .FunctionCount(2),
      .FunctionBytes(4096),
      .BusyCycles   (8)
  ) u_card1 (
      .rst_n_i (rst1_n_i),
      .sck_i   (sdio1.sck_o),
      .cmd_oe_i(sdio1.cmd_oe_o),
      .cmd_do_i(sdio1.cmd_do_o),
      .cmd_do_o(card1_cmd_do),
      .dat_oe_i(sdio1.dat_oe_o),
      .dat_do_i(sdio1.dat_do_o),
      .dat_do_o(card1_dat_do),
      .irq_o   (card1_irq)
  );
  sdio_axi_memory_responder u_mem0 (
      .clk_i  (clk_i),
      .rst_n_i(rst0_n_i),
      .axi4   (axi0)
  );
  sdio_axi_memory_responder u_mem1 (
      .clk_i  (clk_i),
      .rst_n_i(rst1_n_i),
      .axi4   (axi1)
  );

  task automatic apb0_idle;
    begin
      apb0.psel    = 1'b0;
      apb0.penable = 1'b0;
      apb0.pwrite  = 1'b0;
      apb0.paddr   = '0;
      apb0.pwdata  = '0;
      apb0.pstrb   = '0;
    end
  endtask
  task automatic apb1_idle;
    begin
      apb1.psel    = 1'b0;
      apb1.penable = 1'b0;
      apb1.pwrite  = 1'b0;
      apb1.paddr   = '0;
      apb1.pwdata  = '0;
      apb1.pstrb   = '0;
    end
  endtask

  task automatic apb0_write(input logic [31:0] address_i, input logic [31:0] data_i);
    begin
      @(negedge clk_i);
      apb0.paddr   = address_i;
      apb0.pwdata  = data_i;
      apb0.pstrb   = 4'hF;
      apb0.pwrite  = 1'b1;
      apb0.psel    = 1'b1;
      apb0.penable = 1'b0;
      @(negedge clk_i);
      apb0.penable = 1'b1;
      @(posedge clk_i);
      #1;
      if (!apb0.pready || apb0.pslverr) $fatal(1, "dual APB0 write failed %h", address_i);
      apb0_idle();
    end
  endtask
  task automatic apb1_write(input logic [31:0] address_i, input logic [31:0] data_i);
    begin
      @(negedge clk_i);
      apb1.paddr   = address_i;
      apb1.pwdata  = data_i;
      apb1.pstrb   = 4'hF;
      apb1.pwrite  = 1'b1;
      apb1.psel    = 1'b1;
      apb1.penable = 1'b0;
      @(negedge clk_i);
      apb1.penable = 1'b1;
      @(posedge clk_i);
      #1;
      if (!apb1.pready || apb1.pslverr) $fatal(1, "dual APB1 write failed %h", address_i);
      apb1_idle();
    end
  endtask
  task automatic apb0_read(input logic [31:0] address_i, output logic [31:0] data_o);
    begin
      @(negedge clk_i);
      apb0.paddr   = address_i;
      apb0.pwrite  = 1'b0;
      apb0.psel    = 1'b1;
      apb0.penable = 1'b0;
      apb0.pstrb   = '0;
      @(negedge clk_i);
      apb0.penable = 1'b1;
      @(posedge clk_i);
      #1;
      if (!apb0.pready || apb0.pslverr) $fatal(1, "dual APB0 read failed %h", address_i);
      data_o = apb0.prdata;
      apb0_idle();
    end
  endtask
  task automatic apb1_read(input logic [31:0] address_i, output logic [31:0] data_o);
    begin
      @(negedge clk_i);
      apb1.paddr   = address_i;
      apb1.pwrite  = 1'b0;
      apb1.psel    = 1'b1;
      apb1.penable = 1'b0;
      apb1.pstrb   = '0;
      @(negedge clk_i);
      apb1.penable = 1'b1;
      @(posedge clk_i);
      #1;
      if (!apb1.pready || apb1.pslverr) $fatal(1, "dual APB1 read failed %h", address_i);
      data_o = apb1.prdata;
      apb1_idle();
    end
  endtask

  task automatic wait0_command;
    logic seen_busy;
    begin
      guard0    = 0;
      seen_busy = 1'b0;
      while (guard0 < 20000) begin
        @(posedge clk_i);
        guard0 = guard0 + 1;
        if (u_sdio0.u_sdio_core.s_cmd_busy) seen_busy = 1'b1;
        if (seen_busy && (u_sdio0.u_sdio_core.u_sdio_command.s_state_q == 3'd0)) begin
          break;
        end
      end
      if (guard0 >= 20000) $fatal(1, "dual SDIO0 command did not drain");
    end
  endtask
  task automatic wait1_command;
    logic seen_busy;
    begin
      guard1    = 0;
      seen_busy = 1'b0;
      while (guard1 < 20000) begin
        @(posedge clk_i);
        guard1 = guard1 + 1;
        if (u_sdio1.u_sdio_core.s_cmd_busy) seen_busy = 1'b1;
        if (seen_busy && (u_sdio1.u_sdio_core.u_sdio_command.s_state_q == 3'd0)) begin
          break;
        end
      end
      if (guard1 >= 20000) $fatal(1, "dual SDIO1 command did not drain");
    end
  endtask
  task automatic wait0_data;
    logic seen_busy;
    begin
      guard0    = 0;
      seen_busy = 1'b0;
      while (guard0 < 200000) begin
        @(posedge clk_i);
        guard0 = guard0 + 1;
        if (u_sdio0.u_sdio_core.s_data_busy || u_sdio0.u_sdio_core.s_dma_busy) begin
          seen_busy = 1'b1;
        end
        if (seen_busy && !u_sdio0.u_sdio_core.s_data_busy && !u_sdio0.u_sdio_core.s_dma_busy) begin
          break;
        end
      end
      if (guard0 >= 200000) $fatal(1, "dual SDIO0 data did not drain");
    end
  endtask
  task automatic wait1_data;
    logic seen_busy;
    begin
      guard1    = 0;
      seen_busy = 1'b0;
      while (guard1 < 200000) begin
        @(posedge clk_i);
        guard1 = guard1 + 1;
        if (u_sdio1.u_sdio_core.s_data_busy || u_sdio1.u_sdio_core.s_dma_busy) begin
          seen_busy = 1'b1;
        end
        if (seen_busy && !u_sdio1.u_sdio_core.s_data_busy && !u_sdio1.u_sdio_core.s_dma_busy) begin
          break;
        end
      end
      if (guard1 >= 200000) $fatal(1, "dual SDIO1 data did not drain");
    end
  endtask

  task automatic run_memory_context;
    begin
      apb0_write(ClockCtrl, 32'h0000_0101);
      apb0_write(HostCtrl, 32'h0000_0005);
      apb0_write(CmdArg, 32'd2);
      apb0_write(CmdCfg, {18'd0, 1'b1, 1'b1, 4'd1, 2'd0, 6'd17});
      apb0_write(CmdStart, 32'd1);
      wait0_command();
      apb0_read(CmdStatus, value0);
      if ((value0 & 32'h1E) != 0) $fatal(1, "dual SDIO0 CMD17 failed");
      apb0_write(BusCtrl, 32'd0);
      apb0_write(BlockSize, 32'd4);
      apb0_write(BlockCount, 32'd1);
      apb0_write(DataCfg, 32'd0);
      u_card0.arm_read(1024, 4, 1'b0, 1'b0);
      apb0_write(DataStart, 32'd1);
      wait0_data();
      apb0_read(PioData, value0);
      if (value0 != 32'h0000_0000) $fatal(1, "dual SDIO0 data mismatch");
    end
  endtask

  task automatic run_sdio_context;
    begin
      apb1_write(ClockCtrl, 32'h0000_0101);
      apb1_write(HostCtrl, 32'h0000_0005);
      apb1_write(CmdArg, 32'd0);
      apb1_write(CmdCfg, {18'd0, 1'b1, 1'b1, 4'd5, 2'd0, 6'd5});
      apb1_write(CmdStart, 32'd1);
      wait1_command();
      apb1_write(CmdArg, {1'b0, 3'd0, 1'b0, 1'b0, 17'h00000, 1'b0, 8'h00});
      apb1_write(CmdCfg, {18'd0, 1'b1, 1'b1, 4'd6, 2'd0, 6'd52});
      apb1_write(CmdStart, 32'd1);
      wait1_command();
      apb1_write(CmdArg, {1'b0, 3'd1, 1'b0, 1'b1, 17'h00020, 9'd4});
      apb1_write(CmdCfg, {18'd0, 1'b0, 1'b0, 4'd0, 2'd0, 6'd53});
      apb1_write(CmdStart, 32'd1);
      wait1_command();
      apb1_write(BusCtrl, 32'd1);
      apb1_write(BlockSize, 32'd4);
      apb1_write(BlockCount, 32'd1);
      apb1_write(DataCfg, 32'h0000_0002);
      u_card1.arm_read(4096 + 32, 4, 1'b1, 1'b0);
      apb1_write(DataStart, 32'd1);
      wait1_data();
      apb1_read(PioData, value1);
      if (value1 != 32'd0) $fatal(1, "dual SDIO1 data mismatch");
      u_card1.set_irq();
    end
  endtask

  initial begin
    apb0_idle();
    apb1_idle();
    repeat (4) @(posedge clk_i);
    rst0_n_i = 1'b1;
    rst1_n_i = 1'b1;
    fork
      run_memory_context();
      run_sdio_context();
    join
    apb0_read(Status, value0);
    apb1_read(Status, value1);
    if (value0 == value1) $fatal(1, "dual status contexts were aliased");
    if (sdio1.dat_di_i[1] != 1'b0) begin
      $fatal(1, "dual SDIO1 DAT1 context is not isolated");
    end
    apb0_read(ErrorStatus, value0);
    if (value0 != 0) $fatal(1, "SDIO0 inherited SDIO1 error state: %h", value0);
    $display("SDIO dual-instance isolation and concurrent traffic test passed");
    $finish;
  end
endmodule
