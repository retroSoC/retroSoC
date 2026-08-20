// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of the Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`timescale 1ns / 1ps

module sdio_standalone_tb #(
    parameter bit CardHighCapacity = 1'b1,
    parameter bit RunFourBit       = 1'b1
);
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
  localparam logic [31:0] DataStatus = 32'h08C;
  localparam logic [31:0] IrqStatus = 32'h100;
  localparam logic [31:0] IrqEnable = 32'h104;
  localparam logic [31:0] TimeoutData = 32'h020;
  localparam logic [31:0] TimeoutBusy = 32'h024;
  localparam logic [31:0] TimeoutCount = 32'h118;
  localparam logic [31:0] CrcCount = 32'h114;
  localparam logic [31:0] AxiCount = 32'h11C;
  localparam logic [31:0] PioData = 32'h090;
  localparam logic [31:0] DescBase = 32'h0C0;
  localparam logic [31:0] DescCount = 32'h0C4;
  localparam logic [31:0] Status = 32'h028;
  localparam logic [31:0] ClockActual = 32'h014;

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
  integer        timeout_count_before;
  integer        crc_count_before;

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

  sdio_sd_memory_model #(
      .HighCapacity(CardHighCapacity),
      .BlockBytes  (512),
      .BlockCount  (128),
      .BusyCycles  (8)
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

  sdio_axi_memory_responder #(
      .DepthWords(16384)
  ) u_axi_memory (
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
      for (integer wait_count = 0; wait_count < 100000; wait_count++) begin
        @(posedge clk_i);
        #1;
        if (apb4.pready) begin
          break;
        end
      end
      if (!apb4.pready || apb4.pslverr) begin
        $fatal(1, "SDIO APB write failed addr=%h data=%h err=%b", address_i, data_i, apb4.pslverr);
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
        $fatal(1, "SDIO APB read failed addr=%h err=%b", address_i, apb4.pslverr);
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
        $fatal(1, "command did not drain");
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
        $fatal(1, "data path did not drain");
      end
    end
  endtask

  task automatic issue_command(input logic [5:0] index_i, input logic [31:0] argument_i,
                               input logic [3:0] response_i, input logic crc_check_i,
                               input logic index_check_i);
    logic [31:0] status_value;
    begin
      apb_write(CmdArg, argument_i, 4'hF);
      apb_write(CmdCfg, {18'd0, index_check_i, crc_check_i, response_i, 2'd0, index_i}, 4'hF);
      apb_write(CmdStart, 32'd1, 4'h1);
      wait_command();
      apb_read(CmdStatus, status_value);
      if ((status_value & 32'h0000_001E) != 0) begin
        $fatal(1, "command %0d failed status=%h", index_i, status_value);
      end
    end
  endtask

  task automatic configure_data(input logic width4_i, input logic direction_i,
                                input logic [15:0] bytes_i, input logic [15:0] count_i);
    begin
      apb_write(BusCtrl, width4_i ? 32'd1 : 32'd0, 4'h1);
      apb_write(BlockSize, {16'd0, bytes_i}, 4'hF);
      apb_write(BlockCount, {16'd0, count_i}, 4'hF);
      apb_write(DataCfg, {25'd0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, width4_i, direction_i}, 4'h1);
    end
  endtask

  task automatic configure_dma_data(input logic width4_i, input logic direction_i,
                                    input logic [15:0] bytes_i);
    begin
      apb_write(BusCtrl, width4_i ? 32'd1 : 32'd0, 4'h1);
      apb_write(BlockSize, {16'd0, bytes_i}, 4'hF);
      apb_write(BlockCount, 32'd1, 4'hF);
      apb_write(DataCfg, {25'd0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, width4_i, direction_i}, 4'h1);
      apb_write(DescBase, 32'd0, 4'hF);
      apb_write(DescCount, 32'd1, 4'hF);
    end
  endtask

  task automatic read_pio(input integer address_i, input logic width4_i,
                          output logic [31:0] data_o);
    begin
      u_card.arm_read(address_i, 4, width4_i, 1'b0);
      apb_write(DataStart, 32'd1, 4'h1);
      wait_data();
      apb_read(PioData, data_o);
    end
  endtask

  task automatic wait_pio_valid;
    begin
      timeout_guard = 0;
      while (!u_apb4_sdio.u_sdio_core.s_pio_valid_q && (timeout_guard < 200000)) begin
        @(posedge clk_i);
        timeout_guard = timeout_guard + 1;
      end
      if (timeout_guard >= 200000) begin
        $fatal(1, "PIO read word did not become valid");
      end
    end
  endtask

  task automatic write_pio(input integer address_i, input logic width4_i,
                           input logic [31:0] data_i);
    begin
      u_card.arm_write(address_i, 4, width4_i, 1'b0);
      apb_write(DataStart, 32'd1, 4'h1);
      apb_write(PioData, data_i, 4'hF);
      wait_data();
      if (u_card.read_backing(
              address_i
          ) != data_i[7:0] || u_card.read_backing(
              address_i + 1
          ) != data_i[15:8] || u_card.read_backing(
              address_i + 2
          ) != data_i[23:16] || u_card.read_backing(
              address_i + 3
          ) != data_i[31:24]) begin
        $fatal(1, "PIO write mismatch at %0d", address_i);
      end
    end
  endtask

  task automatic tail_read_test(input integer address_i, input logic width4_i,
                                input integer byte_count_i);
    logic   [31:0] word0;
    logic   [31:0] word1;
    integer        word_count;
    integer        expected_words;
    begin
      configure_data(width4_i, 1'b0, byte_count_i, 16'd1);
      u_card.arm_read(address_i, byte_count_i, width4_i, 1'b0);
      apb_write(DataStart, 32'd1, 4'h1);
      expected_words = (byte_count_i + 3) / 4;
      word_count     = 0;
      while (word_count < expected_words) begin
        wait_pio_valid();
        if (word_count == 0) begin
          apb_read(PioData, word0);
        end else begin
          apb_read(PioData, word1);
        end
        word_count = word_count + 1;
      end
      wait_data();
      for (integer byte_index = 0; byte_index < byte_count_i; byte_index++) begin
        if ((byte_index < 4 ? word0[(byte_index % 4)*8+:8] :
                              word1[(byte_index % 4)*8+:8]) !=
            u_card.read_backing(
                address_i + byte_index
            )) begin
          $fatal(1, "tail read mismatch width4=%b bytes=%0d byte=%0d", width4_i, byte_count_i,
                 byte_index);
        end
      end
    end
  endtask

  task automatic tail_write_test(input integer address_i, input logic width4_i,
                                 input integer byte_count_i);
    integer        expected_words;
    logic   [31:0] word;
    logic   [ 3:0] strb;
    integer        remaining;
    begin
      configure_data(width4_i, 1'b1, byte_count_i, 16'd1);
      u_card.arm_write(address_i, byte_count_i, width4_i, 1'b0);
      apb_write(DataStart, 32'd1, 4'h1);
      expected_words = (byte_count_i + 3) / 4;
      for (integer word_index = 0; word_index < expected_words; word_index++) begin
        word      = '0;
        remaining = byte_count_i - (word_index * 4);
        for (integer byte_index = 0; byte_index < 4; byte_index++) begin
          if (byte_index < remaining) begin
            word[byte_index*8+:8] = 8'hA0 + (word_index * 4) + byte_index;
          end
        end
        strb = (remaining >= 4) ? 4'hF : ((4'b0001 << remaining) - 1'b1);
        apb_write(PioData, word, strb);
      end
      wait_data();
      for (integer byte_index = 0; byte_index < byte_count_i; byte_index++) begin
        if (u_card.read_backing(address_i + byte_index) != (8'hA0 + byte_index)) begin
          $fatal(1, "tail write mismatch width4=%b bytes=%0d byte=%0d data=%h", width4_i,
                 byte_count_i, byte_index, u_card.read_backing(address_i + byte_index));
        end
      end
    end
  endtask

  initial begin
    apb_idle();
    repeat (4) @(posedge clk_i);
    rst_n_i = 1'b1;
    u_card.fill_memory(8'h20);
    u_card.set_response_delay(1);
    u_card.set_data_delay(1);

    // 400 kHz command flow at the documented 72 MHz integration clock.
    apb_write(ClockCtrl, 32'h0000_5A01, 4'hF);
    apb_write(HostCtrl, 32'h0000_0005, 4'h1);
    apb_read(ClockActual, apb_value);
    if (apb_value != 32'd400000) begin
      $fatal(1, "400 kHz clock calculation mismatch: %0d", apb_value);
    end
    issue_command(6'd8, 32'h0000_01AA, 4'd8, 1'b1, 1'b1);
    apb_read(Resp0, apb_value);
    if (apb_value[31:8] != 24'h0001AA) begin
      $fatal(1, "CMD8 response echo mismatch: %h", apb_value);
    end

    apb_write(TimeoutBusy, 32'd4, 4'hF);
    apb_write(CmdArg, 32'd0, 4'hF);
    apb_write(CmdCfg, {18'd0, 1'b1, 1'b1, 4'd2, 2'd0, 6'd12}, 4'hF);
    apb_write(CmdStart, 32'd1, 4'h1);
    wait_command();
    apb_read(CmdStatus, apb_value);
    if ((apb_value & 32'h0000_0004) == 0) begin
      $fatal(1, "R1b command did not use TIMEOUT_BUSY");
    end
    apb_write(TimeoutBusy, 32'd1000000, 4'hF);

    apb_write(IrqEnable, 32'h0000_0080, 4'h1);
    u_card.set_response_delay(1000);
    apb_write(CmdArg, 32'd0, 4'hF);
    apb_write(CmdCfg, {18'd0, 1'b1, 1'b1, 4'd1, 2'd0, 6'd17}, 4'hF);
    apb_write(CmdStart, 32'd1, 4'h1);
    repeat (8) @(posedge clk_i);
    apb_write(HostCtrl, 32'h0000_0007, 4'h1);
    wait_command();
    apb_read(IrqStatus, apb_value);
    if ((apb_value & 32'h0000_0080) == 0) $fatal(1, "command abort IRQ missing");
    apb_write(IrqStatus, 32'h0000_0080, 4'h1);
    u_card.set_response_delay(1);

    configure_data(1'b0, 1'b0, 16'd4, 16'd1);
    u_card.set_data_delay(1000);
    u_card.arm_read(3000, 4, 1'b0, 1'b0);
    apb_write(DataStart, 32'd1, 4'h1);
    repeat (8) @(posedge clk_i);
    apb_write(HostCtrl, 32'h0000_0007, 4'h1);
    wait_data();
    apb_read(IrqStatus, apb_value);
    if ((apb_value & 32'h0000_0080) == 0) $fatal(1, "data abort IRQ missing");
    apb_write(IrqStatus, 32'h0000_0080, 4'h1);
    u_card.set_data_delay(1);

    u_axi_memory.clear_memory();
    u_axi_memory.write_word(32'h0000_0000, 32'h0000_0200);
    u_axi_memory.write_word(32'h0000_0004, 32'd4);
    u_axi_memory.write_word(32'h0000_0008, 32'd0);
    u_axi_memory.write_word(32'h0000_000C, 32'h0000_0005);
    u_axi_memory.set_backpressure(0, 3, 0, 0);
    configure_dma_data(1'b0, 1'b0, 16'd4);
    u_card.arm_read(3004, 4, 1'b0, 1'b0);
    apb_write(DataStart, 32'd1, 4'h1);
    wait (u_apb4_sdio.u_sdio_core.u_sdio_dma.s_state_q == 4'd2);
    apb_write(HostCtrl, 32'h0000_0007, 4'h1);
    wait_data();
    apb_read(IrqStatus, apb_value);
    if ((apb_value & 32'h0000_0080) == 0 || u_axi_memory.read_word(
            32'h0000_000C
        ) != 32'h0002_0004) begin
      $fatal(1, "descriptor-fetch host abort did not drain/write back");
    end
    apb_write(IrqStatus, 32'h0000_0080, 4'h1);
    u_axi_memory.set_backpressure(0, 0, 0, 0);

    apb_write(TimeoutData, 32'd4, 4'hF);
    apb_read(TimeoutCount, apb_value);
    timeout_count_before = apb_value;
    u_card.set_data_delay(1000);
    u_card.arm_read(3200, 4, 1'b0, 1'b0);
    configure_data(1'b0, 1'b0, 16'd4, 16'd1);
    apb_write(DataStart, 32'd1, 4'h1);
    wait_data();
    apb_read(DataStatus, apb_value);
    if ((apb_value & 32'h0000_0004) == 0) $fatal(1, "data timeout phase not reported");
    apb_read(TimeoutCount, apb_value);
    if (apb_value != timeout_count_before + 1) begin
      $fatal(1, "timeout counter incremented incorrectly: before=%0d after=%0d",
             timeout_count_before, apb_value);
    end
    apb_write(TimeoutData, 32'd1000000, 4'hF);
    u_card.set_data_delay(1);

    // SDSC and SDHC use the same native command path but different address
    // interpretation.  The parameterized wrapper is run once for each card
    // geometry by the pytest entry points.
    issue_command(
        6'd17, CardHighCapacity ? (RunFourBit ? 32'd4 : 32'd2) : (RunFourBit ? 32'd2048 : 32'd1024),
        4'd1, 1'b1, 1'b1);
    issue_command(6'd12, 32'd0, 4'd2, 1'b1, 1'b1);
    configure_data(RunFourBit, 1'b0, 16'd4, 16'd1);
    read_pio(RunFourBit ? 2048 : 1024, RunFourBit, apb_value);
    if (apb_value != 32'h2322_2120) begin
      $fatal(1, "4-bit read mismatch: %h", apb_value);
    end

    // Each APB PIO read consumes one held word.  The second word must not
    // repeat the first word or require a reset between reads.
    configure_data(RunFourBit, 1'b0, 16'd8, 16'd1);
    u_card.arm_read(RunFourBit ? 2052 : 1028, 8, RunFourBit, 1'b0);
    apb_write(DataStart, 32'd1, 4'h1);
    wait_pio_valid();
    apb_read(PioData, apb_value);
    if (apb_value != 32'h2726_2524) begin
      $fatal(1, "first back-to-back PIO word mismatch: %h", apb_value);
    end
    wait_pio_valid();
    apb_read(PioData, apb_value);
    if (apb_value != 32'h2B2A_2928) begin
      $fatal(1, "second back-to-back PIO word mismatch: %h", apb_value);
    end
    wait_data();

    configure_data(1'b0, 1'b1, 16'd4, 16'd1);
    write_pio(3072, 1'b0, 32'hA1B2_C3D4);
    configure_data(1'b1, 1'b1, 16'd4, 16'd1);
    write_pio(4096, 1'b1, 32'h1020_3040);

    // A complete PIO block uses a real ready/consume FIFO.  The APB writes
    // below are intentionally consecutive; PREADY supplies the required
    // wait-states while the serializer drains the queue.
    apb_write(ClockCtrl, 32'h0000_0101, 4'hF);

    // End-to-end DMA direction checks use the same card model and AXI
    // responder as the PIO path.
    u_axi_memory.clear_memory();
    u_axi_memory.write_word(32'h0000_0000, 32'h0000_0200);
    u_axi_memory.write_word(32'h0000_0004, 32'd5);
    u_axi_memory.write_word(32'h0000_0008, 32'd0);
    u_axi_memory.write_word(32'h0000_000C, 32'h0000_000D);
    configure_dma_data(1'b1, 1'b0, 16'd5);
    u_card.arm_read(20000, 5, 1'b1, 1'b0);
    for (integer byte_index = 0; byte_index < 5; byte_index++) begin
      u_card.write_backing(20000 + byte_index, 8'h60 + byte_index);
    end
    apb_write(DataStart, 32'd1, 4'h1);
    wait_data();
    apb_write(IrqEnable, 32'h0000_0084, 4'h1);
    repeat (2) @(posedge clk_i);
    apb_read(IrqStatus, apb_value);
    if ((apb_value & 32'h0000_0004) == 0) begin
      $fatal(1, "descriptor IRQ was not visible through the core");
    end
    apb_write(IrqStatus, 32'h0000_0004, 4'h1);
    if (u_axi_memory.read_word(
            32'h0000_0200
        ) != 32'h6362_6160 || (u_axi_memory.read_word(
            32'h0000_0204
        ) & 32'hFF) != 32'h64 || u_axi_memory.read_word(
            32'h0000_000C
        ) != 32'h0001_000C) begin
      $fatal(1, "card-to-memory DMA end-to-end direction failed");
    end

    u_axi_memory.clear_memory();
    u_axi_memory.write_word(32'h0000_0000, 32'h0000_0300);
    u_axi_memory.write_word(32'h0000_0004, 32'd5);
    u_axi_memory.write_word(32'h0000_0008, 32'd0);
    u_axi_memory.write_word(32'h0000_000C, 32'h0000_0005);
    u_axi_memory.write_word(32'h0000_0300, 32'hD4C3_B2A1);
    u_axi_memory.write_word(32'h0000_0304, 32'h0000_00E5);
    configure_dma_data(1'b0, 1'b1, 16'd5);
    u_card.arm_write(21000, 5, 1'b0, 1'b0);
    apb_write(DataStart, 32'd1, 4'h1);
    wait_data();
    if (u_card.read_backing(
            21000
        ) != 8'hA1 || u_card.read_backing(
            21001
        ) != 8'hB2 || u_card.read_backing(
            21002
        ) != 8'hC3 || u_card.read_backing(
            21003
        ) != 8'hD4 || u_card.read_backing(
            21004
        ) != 8'hE5 || u_axi_memory.read_word(
            32'h0000_000C
        ) != 32'h0001_0004) begin
      $fatal(1, "memory-to-card DMA end-to-end direction failed");
    end

    apb_read(AxiCount, apb_value);
    timeout_count_before = apb_value;
    u_axi_memory.clear_memory();
    u_axi_memory.write_word(32'h0000_0000, 32'h0000_0400);
    u_axi_memory.write_word(32'h0000_0004, 32'd4);
    u_axi_memory.write_word(32'h0000_0008, 32'd0);
    u_axi_memory.write_word(32'h0000_000C, 32'h0000_0005);
    u_axi_memory.write_word(32'h0000_0400, 32'h1122_3344);
    u_axi_memory.inject_read_error(32'h0000_0400);
    configure_dma_data(1'b0, 1'b1, 16'd4);
    u_card.arm_write(22000, 4, 1'b0, 1'b0);
    apb_write(DataStart, 32'd1, 4'h1);
    wait_data();
    apb_read(AxiCount, apb_value);
    if (apb_value != timeout_count_before + 1 || u_axi_memory.read_word(
            32'h0000_000C
        ) != 32'h0002_0004) begin
      $fatal(1, "AXI error counter/writeback contract failed: before=%0d after=%0d",
             timeout_count_before, apb_value);
    end
    u_axi_memory.clear_errors();

    apb_write(ClockCtrl, 32'h0000_0100, 4'hF);
    repeat (4) @(posedge clk_i);
    apb_write(ClockCtrl, 32'h0000_0101, 4'hF);
    configure_data(1'b0, 1'b1, 16'd512, 16'd1);
    u_card.arm_write(8192, 512, 1'b0, 1'b0);
    apb_write(DataStart, 32'd1, 4'h1);
    for (integer word_index = 0; word_index < 128; word_index++) begin
      logic [31:0] word;
      word = '0;
      for (integer byte_index = 0; byte_index < 4; byte_index++) begin
        word[byte_index*8+:8] = (word_index * 4) + byte_index;
      end
      apb_write(PioData, word, 4'hF);
    end
    wait_data();
    for (integer byte_index = 0; byte_index < 512; byte_index++) begin
      if (u_card.read_backing(8192 + byte_index) != byte_index[7:0]) begin
        $fatal(1, "512-byte PIO write mismatch at %0d: %h", byte_index, u_card.read_backing(
               8192 + byte_index));
      end
    end

    configure_data(1'b0, 1'b0, 16'd512, 16'd1);
    u_card.arm_read(8192, 512, 1'b0, 1'b0);
    apb_write(DataStart, 32'd1, 4'h1);
    for (integer word_index = 0; word_index < 128; word_index++) begin
      wait_pio_valid();
      apb_read(PioData, apb_value);
      for (integer byte_index = 0; byte_index < 4; byte_index++) begin
        if (apb_value[byte_index*8+:8] != ((word_index * 4) + byte_index) % 256) begin
          $fatal(1, "512-byte PIO read mismatch word=%0d byte=%0d: %h", word_index, byte_index,
                 apb_value);
        end
      end
    end
    wait_data();

    for (integer tail_bytes = 1; tail_bytes <= 5; tail_bytes++) begin
      if (tail_bytes != 4) begin
        tail_read_test(12000 + (tail_bytes * 16), 1'b0, tail_bytes);
        tail_write_test(13000 + (tail_bytes * 16), 1'b0, tail_bytes);
        tail_read_test(14000 + (tail_bytes * 16), 1'b1, tail_bytes);
        tail_write_test(15000 + (tail_bytes * 16), 1'b1, tail_bytes);
      end
    end

    apb_write(TimeoutBusy, 32'd4, 4'hF);
    configure_data(1'b0, 1'b1, 16'd4, 16'd1);
    u_card.arm_write(15996, 4, 1'b0, 1'b0);
    apb_write(DataStart, 32'd1, 4'h1);
    apb_write(PioData, 32'h4433_2211, 4'hF);
    wait_data();
    apb_read(DataStatus, apb_value);
    if ((apb_value & 32'h0000_0010) == 0) begin
      $fatal(1, "DAT0 busy timeout did not use TIMEOUT_BUSY");
    end
    apb_write(TimeoutBusy, 32'd1000000, 4'hF);

    configure_data(1'b0, 1'b1, 16'd4, 16'd1);
    u_card.inject_next_crc_error();
    u_card.arm_write(16000, 4, 1'b0, 1'b0);
    apb_read(CrcCount, apb_value);
    crc_count_before = apb_value;
    apb_write(DataStart, 32'd1, 4'h1);
    apb_write(PioData, 32'h4433_2211, 4'hF);
    wait_data();
    apb_read(DataStatus, apb_value);
    if ((apb_value & 32'h0000_0008) == 0) begin
      $fatal(1, "CRC-error write response token was not reported: status=%h dataerr=%b crc=%b",
             apb_value, u_apb4_sdio.u_sdio_core.s_data_err, u_apb4_sdio.u_sdio_core.s_data_crc_err);
    end
    apb_read(CrcCount, apb_value);
    if (apb_value != crc_count_before + 1) begin
      $fatal(1, "CRC counter incremented incorrectly: before=%0d after=%0d", crc_count_before,
             apb_value);
    end

    configure_data(1'b0, 1'b1, 16'd4, 16'd1);
    u_card.inject_next_write_error();
    u_card.arm_write(16004, 4, 1'b0, 1'b0);
    apb_write(DataStart, 32'd1, 4'h1);
    apb_write(PioData, 32'h8877_6655, 4'hF);
    wait_data();
    apb_read(DataStatus, apb_value);
    if (((apb_value & 32'h0000_0002) == 0) || ((apb_value & 32'h0000_0008) != 0)) begin
      $fatal(1, "write-error response token was not distinguished: %h", apb_value);
    end

    $display("SDIO standalone native SD model test passed (%s)",
             CardHighCapacity ? "SDHC" : "SDSC");
    $finish;
  end
endmodule

module sdio_sdsc_tb;
  sdio_standalone_tb #(.CardHighCapacity(1'b0)) u_tb ();
endmodule

module sdio_onebit_tb;
  sdio_standalone_tb #(.RunFourBit(1'b0)) u_tb ();
endmodule
