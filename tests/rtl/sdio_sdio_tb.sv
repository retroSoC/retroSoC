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

module sdio_sdio_tb;
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
  localparam logic [31:0] IrqStatus = 32'h100;
  localparam logic [31:0] IrqEnable = 32'h104;

  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;
  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) dma_axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  sdio_if sdio ();
  logic          card_cmd_do;
  logic   [ 3:0] card_dat_do;
  logic          card_irq;
  logic   [31:0] apb_value;
  integer        timeout_guard;

  assign sdio.cmd_di_i = sdio.cmd_oe_o ? sdio.cmd_do_o : card_cmd_do;
  assign sdio.dat_di_i = (sdio.dat_oe_o & sdio.dat_do_o) | (~sdio.dat_oe_o & card_dat_do);

  always #5 clk_i = ~clk_i;

  apb4_sdio #(
      .InputClockHz(72_000_000),
      .AddrWidth   (32),
      .DataWidth   (32),
      .DescCount   (16)
  ) u_apb4_sdio (
      .clk_i   (clk_i),
      .rst_n_i (rst_n_i),
      .apb4    (apb4),
      .dma_axi4(dma_axi4),
      .sdio    (sdio)
  );

  sdio_sdio_model #(
      .FunctionCount(2),
      .FunctionBytes(4096),
      .BusyCycles   (8)
  ) u_card (
      .rst_n_i (rst_n_i),
      .sck_i   (sdio.sck_o),
      .cmd_oe_i(sdio.cmd_oe_o),
      .cmd_do_i(sdio.cmd_do_o),
      .cmd_do_o(card_cmd_do),
      .dat_oe_i(sdio.dat_oe_o),
      .dat_do_i(sdio.dat_do_o),
      .dat_do_o(card_dat_do),
      .irq_o   (card_irq)
  );

  sdio_axi_memory_responder u_axi_memory (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .axi4   (dma_axi4)
  );

  task automatic apb_idle;
    begin
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
      apb4.pwrite  = 1'b0;
      apb4.paddr   = '0;
      apb4.pwdata  = '0;
      apb4.pstrb   = '0;
    end
  endtask

  task automatic issue_command_unchecked(input logic [5:0] index_i, input logic [31:0] argument_i,
                                         input logic [3:0] response_i);
    begin
      apb_write(CmdArg, argument_i, 4'hF);
      apb_write(CmdCfg, {18'd0, 1'b0, 1'b0, response_i, 2'd0, index_i}, 4'hF);
      apb_write(CmdStart, 32'd1, 4'h1);
      wait_command();
    end
  endtask

  task automatic apb_write(input logic [31:0] address_i, input logic [31:0] data_i,
                           input logic [3:0] strobe_i);
    begin
      @(negedge clk_i);
      apb4.paddr   = address_i;
      apb4.pwdata  = data_i;
      apb4.pstrb   = strobe_i;
      apb4.pwrite  = 1'b1;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      @(negedge clk_i);
      apb4.penable = 1'b1;
      @(posedge clk_i);
      #1;
      if (!apb4.pready || apb4.pslverr) begin
        $fatal(1, "SDIO APB write failed addr=%h data=%h", address_i, data_i);
      end
      apb_idle();
    end
  endtask

  task automatic apb_read(input logic [31:0] address_i, output logic [31:0] data_o);
    begin
      @(negedge clk_i);
      apb4.paddr   = address_i;
      apb4.pwdata  = '0;
      apb4.pstrb   = '0;
      apb4.pwrite  = 1'b0;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      @(negedge clk_i);
      apb4.penable = 1'b1;
      @(posedge clk_i);
      #1;
      if (!apb4.pready || apb4.pslverr) begin
        $fatal(1, "SDIO APB read failed addr=%h", address_i);
      end
      data_o = apb4.prdata;
      apb_idle();
    end
  endtask

  task automatic wait_command;
    logic seen_busy;
    begin
      timeout_guard = 0;
      seen_busy     = 1'b0;
      while (timeout_guard < 20000) begin
        @(posedge clk_i);
        timeout_guard = timeout_guard + 1;
        if (u_apb4_sdio.u_sdio_core.s_cmd_busy) begin
          seen_busy = 1'b1;
        end
        if (seen_busy && (u_apb4_sdio.u_sdio_core.u_sdio_command.s_state_q == 3'd0)) begin
          break;
        end
      end
      if (timeout_guard >= 20000) begin
        $fatal(1, "SDIO command did not drain");
      end
    end
  endtask

  task automatic wait_data;
    logic seen_busy;
    begin
      timeout_guard = 0;
      seen_busy     = 1'b0;
      while (timeout_guard < 200000) begin
        @(posedge clk_i);
        timeout_guard = timeout_guard + 1;
        if (u_apb4_sdio.u_sdio_core.s_data_busy || u_apb4_sdio.u_sdio_core.s_dma_busy) begin
          seen_busy = 1'b1;
        end
        if (seen_busy && !u_apb4_sdio.u_sdio_core.s_data_busy &&
            !u_apb4_sdio.u_sdio_core.s_dma_busy) begin
          break;
        end
      end
      if (timeout_guard >= 200000) begin
        $fatal(1, "SDIO data path did not drain");
      end
    end
  endtask

  task automatic wait_write_ready;
    begin
      timeout_guard = 0;
      while ((u_apb4_sdio.u_sdio_core.u_sdio_data.s_state_q != 4'd1) &&
             (timeout_guard < 1000)) begin
        @(posedge clk_i);
        timeout_guard = timeout_guard + 1;
      end
      if (timeout_guard >= 1000) begin
        $fatal(1, "SDIO write engine did not become ready");
      end
    end
  endtask

  task automatic issue_command(input logic [5:0] index_i, input logic [31:0] argument_i,
                               input logic [3:0] response_i);
    logic [31:0] status_value;
    begin
      apb_write(CmdArg, argument_i, 4'hF);
      apb_write(CmdCfg, {18'd0, 1'b1, 1'b1, response_i, 2'd0, index_i}, 4'hF);
      apb_write(CmdStart, 32'd1, 4'h1);
      wait_command();
      apb_read(CmdStatus, status_value);
      if ((status_value & 32'h0000_001E) != 0) begin
        $fatal(1, "SDIO command %0d failed status=%h", index_i, status_value);
      end
    end
  endtask

  task automatic configure_data(input logic width4_i, input logic direction_i,
                                input logic block_mode_i, input logic fixed_address_i,
                                input logic [15:0] bytes_i, input logic [15:0] count_i);
    begin
      apb_write(BusCtrl, width4_i ? 32'd1 : 32'd0, 4'h1);
      apb_write(BlockSize, {16'd0, bytes_i}, 4'hF);
      apb_write(BlockCount, {16'd0, count_i}, 4'hF);
      apb_write(DataCfg, {
                25'd0, fixed_address_i, block_mode_i, 1'b0, 1'b0, 1'b0, width4_i, direction_i},
                4'h1);
    end
  endtask

  initial begin
    apb_idle();
    repeat (4) @(posedge clk_i);
    rst_n_i = 1'b1;
    apb_write(ClockCtrl, 32'h0000_0101, 4'hF);
    apb_write(HostCtrl, 32'h0000_0005, 4'h1);

    // SDIO enumeration and CCCR/FBR/CIS-backed direct accesses.
    issue_command(6'd5, 32'h0000_0000, 4'd5);
    repeat (8) @(posedge clk_i);
    issue_command(6'd52, 32'h0000_0000, 4'd6);
    apb_read(Resp0, apb_value);
    if (apb_value[15:8] != 8'h03) begin
      $fatal(1, "CCCR version mismatch: %h", apb_value);
    end
    issue_command(6'd52, {1'b0, 3'd0, 1'b0, 1'b0, 17'h00013, 1'b0, 8'h00}, 4'd6);
    apb_read(Resp0, apb_value);
    if (apb_value[15:8] != 8'h01) $fatal(1, "CCCR high-speed capability missing");
    issue_command(6'd52, {1'b1, 3'd0, 1'b0, 1'b0, 17'h00013, 1'b0, 8'h03}, 4'd6);
    issue_command(6'd52, {1'b0, 3'd0, 1'b0, 1'b0, 17'h00013, 1'b0, 8'h00}, 4'd6);
    apb_read(Resp0, apb_value);
    if (apb_value[15:8] != 8'h03) $fatal(1, "CCCR high-speed enable did not stick");
    issue_command(6'd52, {1'b1, 3'd0, 1'b0, 1'b0, 17'h00004, 1'b0, 8'h5A}, 4'd6);
    apb_read(Resp0, apb_value);
    if (apb_value[15:8] != 8'h5A) begin
      $fatal(1, "CCCR write response mismatch: %h", apb_value);
    end

    // CMD53 byte mode, incrementing address, 4-bit SDR.
    issue_command_unchecked(6'd53, {1'b0, 3'd1, 1'b0, 1'b1, 17'h00020, 9'd4}, 4'd0);
    configure_data(1'b1, 1'b0, 1'b0, 1'b0, 16'd4, 16'd1);
    u_card.arm_read(4096 + 32, 4, 1'b1, 1'b0);
    apb_write(DataStart, 32'd1, 4'h1);
    wait_data();
    apb_read(PioData, apb_value);
    if (apb_value != 32'h0000_0000) begin
      $fatal(1, "unexpected initial function memory: %h", apb_value);
    end

    // CMD53 block mode, fixed address, 1-bit SDR write.
    issue_command_unchecked(6'd53, {1'b1, 3'd1, 1'b1, 1'b0, 17'h00030, 9'd1}, 4'd0);
    configure_data(1'b0, 1'b1, 1'b1, 1'b1, 16'd4, 16'd1);
    u_card.arm_write(4096 + 48, 4, 1'b0, 1'b1);
    apb_write(DataStart, 32'd1, 4'h1);
    wait_write_ready();
    apb_write(PioData, 32'h1122_3344, 4'hF);
    wait_data();
    if (u_card.read_backing(4096 + 48) != 8'h11) begin
      $fatal(1, "fixed-address CMD53 write did not land: %h", u_card.read_backing(4096 + 48));
    end

    apb_write(IrqEnable, 32'h0000_0040, 4'h1);
    apb_write(IrqStatus, 32'h0000_00FF, 4'h1);
    u_card.clear_irq();
    repeat (4) @(posedge clk_i);
    apb_read(IrqStatus, apb_value);
    if ((apb_value & 32'h0000_0040) != 0 || sdio.irq_o) begin
      $fatal(1, "DAT1 high level caused a false host IRQ");
    end

    // DAT1 is an active-low function interrupt.  It is synchronized in clk_i,
    // qualified only while the host releases the data path, and remains sticky
    // while SDCLK is stopped.
    u_card.set_irq();
    repeat (4) @(posedge clk_i);
    if (sdio.dat_di_i[1] != 1'b0 || !card_irq) begin
      $fatal(1, "SDIO DAT1 interrupt was not asserted low");
    end
    apb_read(IrqStatus, apb_value);
    if ((apb_value & 32'h0000_0040) == 0 || !sdio.irq_o) begin
      $fatal(1, "active-low DAT1 did not latch host IRQ");
    end
    apb_write(IrqStatus, 32'h0000_0040, 4'h1);
    repeat (8) @(posedge clk_i);
    apb_read(IrqStatus, apb_value);
    if ((apb_value & 32'h0000_0040) != 0 || sdio.irq_o) begin
      $fatal(1, "DAT1 W1C did not clear sticky host IRQ");
    end
    if (sdio.sck_o != 1'b0) begin
      $fatal(1, "SDCLK was not stopped for DAT1 persistence check");
    end
    repeat (8) @(posedge clk_i);
    apb_read(IrqStatus, apb_value);
    if ((apb_value & 32'h0000_0040) != 0) begin
      $fatal(1, "cleared DAT1 IRQ reasserted while line remained low");
    end

    u_card.clear_irq();
    repeat (4) @(posedge clk_i);
    if (sdio.dat_di_i[1] != 1'b1) begin
      $fatal(1, "DAT1 interrupt did not release");
    end
    u_card.set_irq();
    repeat (4) @(posedge clk_i);
    apb_read(IrqStatus, apb_value);
    if ((apb_value & 32'h0000_0040) == 0) begin
      $fatal(1, "DAT1 did not re-arm after returning high");
    end

    $display("SDIO-only CMD5/CMD52/CMD53/DAT1 test passed");
    $finish;
  end
endmodule
