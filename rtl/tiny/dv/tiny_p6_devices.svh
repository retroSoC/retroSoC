// Verification-only external devices on the Gen1 GPIO routes. No DUT state is driven.
logic s_p6_io_trace_started = 0;
always @(negedge s_clk) begin
  if ($test$plusargs("p6_debug_io")) begin
    if (u_dut.u_soc.u_i2c0.s_cmd_valid && !s_p6_io_trace_started) begin
      s_p6_io_trace_started = 1;
      $display("P6_IO_DIAGNOSTIC start pads=%b raw=%b%b filtered=%b%b drive=%b%b", s_gpio[11:10],
               u_dut.u_soc.u_i2c0_if.sda_i, u_dut.u_soc.u_i2c0_if.scl_i,
               u_dut.u_soc.u_i2c0.s_sda_filtered, u_dut.u_soc.u_i2c0.s_scl_filtered,
               u_dut.u_soc.u_i2c0.s_sda_pull_low, u_dut.u_soc.u_i2c0.s_scl_pull_low);
      $fflush();
    end
    if (u_dut.u_soc.u_i2c0.s_addr_nack_event || u_dut.u_soc.u_i2c0.s_bus_timeout_event ||
        u_dut.u_soc.u_i2c0.s_cmd_timeout_event || u_dut.u_soc.u_i2c0.s_stretch_timeout_event ||
        u_dut.u_soc.u_i2c0.s_arb_lost_event) begin
      $display(
          "P6_IO_DIAGNOSTIC nack=%b bus_timeout=%b command_timeout=%b stretch=%b arbitration=%b pads=%b drive=%b%b",
          u_dut.u_soc.u_i2c0.s_addr_nack_event, u_dut.u_soc.u_i2c0.s_bus_timeout_event,
          u_dut.u_soc.u_i2c0.s_cmd_timeout_event, u_dut.u_soc.u_i2c0.s_stretch_timeout_event,
          u_dut.u_soc.u_i2c0.s_arb_lost_event, s_gpio[11:10], u_dut.u_soc.u_i2c0.s_sda_pull_low,
          u_dut.u_soc.u_i2c0.s_scl_pull_low);
      $finish;  // Diagnostic only: deliberately no SIM_TEST_PASS verdict.
    end
  end
end
`define _P6_WS u_dut.u_soc.u_ws2812
logic       s_p6_uart_rx = 1;
logic [7:0] s_p6_uart_byte;
logic [7:0] s_p6_uart_packet [4];
integer s_p6_uart_index = 0, s_p6_uart_routes = 0;
assign s_gpio_9 = s_p6_uart_rx;
initial begin
  forever begin
    @(negedge s_gpio_8);
    #1627.604;
    for (integer bit_index = 0; bit_index < 8; bit_index++) begin
      s_p6_uart_byte[bit_index] = s_gpio_8;
      #1085.069;
    end
    if (s_p6_uart_index != 0 || s_p6_uart_byte == 8'ha5) begin
      s_p6_uart_packet[s_p6_uart_index] = s_p6_uart_byte;
      s_p6_uart_index++;
      if (s_p6_uart_index == 4) begin
        if (s_p6_uart_packet[0] != 8'ha5 || s_p6_uart_packet[1] != 8'h5a ||
            s_p6_uart_packet[2] != 8'h96 || s_p6_uart_packet[3] != 8'h69)
          $fatal(1, "SIM_TEST_FAIL P6 UART GPIO8 framing/data");
        for (integer byte_index = 0; byte_index < 4; byte_index++) begin
          s_p6_uart_rx = 0;
          #1085.069;
          for (integer bit_index = 0; bit_index < 8; bit_index++) begin
            s_p6_uart_rx = s_p6_uart_packet[byte_index][bit_index];
            #1085.069;
          end
          s_p6_uart_rx = 1;
          #1085.069;
        end
        s_p6_uart_index = 0;
        s_p6_uart_routes++;
      end
    end
  end
end
integer s_p6_frames = 0, s_p6_completed = 0, s_p6_underflows = 0, s_p6_aborts = 0;
longint unsigned s_p6_sdio_overlap = 0, s_p6_overlap_fetches = 0;
always @(posedge s_clk) begin
  if (u_dut.u_soc.u_dma.s_busy[2] && u_dut.u_soc.u_sdio.s_dma_status[0]) begin
    s_p6_sdio_overlap++;
    if (u_dut.u_soc.u_cpu_ahbl_if[0].hready && u_dut.u_soc.u_cpu_ahbl_if[0].htrans[1])
      s_p6_overlap_fetches++;
  end
end
integer s_p6_word = 0, s_p6_bit = 0, s_p6_bit_cycle = 0, s_p6_reset_cycles = 0;
integer s_p6_ws_wait = 0, s_p6_ws_wait_max = 0, s_p6_fifo_max = 0;
integer s_p6_clock_stops = 0;
integer s_p6_wire_cases = 0, s_p6_wire_matched = 0, s_p6_wire_examined = 0;
integer s_p6_wire_edges = 0;
logic s_p6_wire_found = 0, s_p6_wire_boundary = 0, s_p6_wire_lrck = 0;
logic [23:0] s_p6_wire_shift = 0;
logic [31:0] s_p6_wire_word;
wire         s_p6_audio_enabled = u_dut.u_soc.u_i2s.u_i2s_core.enable_i;
wire         s_p6_audio_wide = u_dut.u_soc.u_i2s.u_i2s_core.s_bitmode;
// Decode actual BCLK/LRCLK/DOUT pads, independently of the receive engine.
always @(posedge s_gpio[12] or negedge s_p6_audio_enabled) begin
  if (!s_p6_audio_enabled) begin
    if (s_p6_wire_found) begin
      if (s_p6_wire_matched != 512) $fatal(1, "SIM_TEST_FAIL P6 truncated I2S wire payload");
      s_p6_wire_cases++;
      $display("R2_P6_I2S_WIRE bits=%0d samples=%0d", s_p6_audio_wide ? 24 : 16, s_p6_wire_matched);
    end
    s_p6_wire_matched  = 0;
    s_p6_wire_examined = 0;
    s_p6_wire_edges    = 0;
    s_p6_wire_found    = 0;
    s_p6_wire_boundary = 0;
    s_p6_wire_lrck     = 0;
    s_p6_wire_shift    = 0;
  end else begin
    if (s_gpio[14] !== 1'b0 && s_gpio[14] !== 1'b1) $fatal(1, "SIM_TEST_FAIL P6 unknown I2S DOUT");
    s_p6_wire_shift = {s_p6_wire_shift[22:0], s_gpio[14]};
    s_p6_wire_edges++;
    if (s_gpio[13] != s_p6_wire_lrck) begin
      if (s_p6_wire_boundary && s_p6_wire_edges != (s_p6_audio_wide ? 24 : 16))
        $fatal(1, "SIM_TEST_FAIL P6 I2S slot length");
      s_p6_wire_boundary = 1;
      s_p6_wire_edges = 0;
      s_p6_wire_word = s_p6_audio_wide ? {8'd0, s_p6_wire_shift} : {16'd0, s_p6_wire_shift[15:0]};
      if (!s_p6_wire_found && s_p6_wire_word == (s_p6_audio_wide ? 32'h120020 : 32'h2020))
        s_p6_wire_found = 1;
      if (s_p6_wire_found && s_p6_wire_matched < 512) begin
        if (s_p6_wire_word != (s_p6_audio_wide ? 32'h120020 : 32'h2020) + 32'(s_p6_wire_matched))
          $fatal(1, "SIM_TEST_FAIL P6 I2S wire ordering/data index=%0d", s_p6_wire_matched);
        s_p6_wire_matched++;
      end
      s_p6_wire_examined++;
      if (!s_p6_wire_found && s_p6_wire_examined > 40)
        $fatal(1, "SIM_TEST_FAIL P6 missing I2S wire payload");
      s_p6_wire_lrck = s_gpio[13];
    end
  end
end
logic        s_p6_busy_previous = 0;
logic [23:0] s_p6_pixel;
logic        s_p6_expected_high;
logic        s_p6_audio_reference = 1'b0;
logic        s_p6_audio_running = 1'b0;
initial begin
  repeat (200) @(negedge s_clk);
  if (!u_dut.u_soc.s_cpu_ready_rst_n)
    $fatal(1, "SIM_TEST_FAIL CPU boot waited for absent AUDIO clock");
  s_p6_audio_running = 1'b1;
end
// GPIO27 is a verification-board control only after the four normal WS frames.
// Stop low and high in separate cases, then restore the source without DUT forcing.
always @(posedge s_gpio[27]) begin
  if (s_p6_frames == 4 && s_p6_clock_stops < 2) begin
    wait (s_p6_audio_reference == (s_p6_clock_stops != 0));
    s_p6_audio_running = 0;
    repeat (4800) @(negedge s_clk);
    s_p6_clock_stops++;
    s_p6_audio_running = 1;
  end
end
always @(negedge s_clk) begin
  if (`_P6_WS.s_busy && !s_p6_busy_previous) begin
    s_p6_frames++;
    s_p6_word         = 0;
    s_p6_bit          = 0;
    s_p6_bit_cycle    = 0;
    s_p6_reset_cycles = 0;
  end
  if (`_P6_WS.s_underflow) s_p6_underflows++;
  if (`_P6_WS.s_aborted) s_p6_aborts++;
  if (`_P6_WS.s_busy && !`_P6_WS.s_reset_active && s_p6_frames <= 4) begin
    s_p6_pixel         = 24'(s_p6_word * 32'h010203);
    s_p6_expected_high = s_p6_bit_cycle < (s_p6_pixel[23-s_p6_bit] ? 17 : 8);
    if (s_gpio[26] !== s_p6_expected_high)
      $fatal(
          1,
          "SIM_TEST_FAIL Tiny P6 WS pad waveform frame=%0d word=%0d bit=%0d cycle=%0d",
          s_p6_frames,
          s_p6_word,
          s_p6_bit,
          s_p6_bit_cycle
      );
    s_p6_bit_cycle++;
    if (s_p6_bit_cycle == 30) begin
      s_p6_bit_cycle = 0;
      s_p6_bit++;
      if (s_p6_bit == 24) begin
        s_p6_bit = 0;
        s_p6_word++;
      end
    end
    if (`_P6_WS.u_ws2812_reg.s_fifo_level > s_p6_fifo_max)
      s_p6_fifo_max = integer'(`_P6_WS.u_ws2812_reg.s_fifo_level);
    if (`_P6_WS.u_ws2812_reg.s_fifo_low && !`_P6_WS.u_ws2812_reg.s_tx_push) s_p6_ws_wait++;
    else s_p6_ws_wait = 0;
    if (s_p6_ws_wait > s_p6_ws_wait_max) s_p6_ws_wait_max = s_p6_ws_wait;
    if (s_p6_ws_wait > 4800 || s_p6_fifo_max > 16)
      $fatal(1, "SIM_TEST_FAIL Tiny P6 WS service budget/occupancy");
  end else s_p6_ws_wait = 0;
  if (`_P6_WS.s_reset_active) begin
    if (s_gpio[26] !== 1'b0) $fatal(1, "SIM_TEST_FAIL Tiny P6 WS reset-low");
    s_p6_reset_cycles++;
  end
  if (!`_P6_WS.s_busy && s_p6_busy_previous) begin
    if (s_p6_reset_cycles < 7200) $fatal(1, "SIM_TEST_FAIL Tiny P6 WS reset interval");
    if (s_p6_frames <= 4) begin
      if (s_p6_word != ((s_p6_frames % 2) ? 33 : 65) || s_p6_bit != 0 || s_p6_bit_cycle != 0)
        $fatal(1, "SIM_TEST_FAIL Tiny P6 WS exact frame length");
      s_p6_completed++;
    end
  end
  s_p6_busy_previous = `_P6_WS.s_busy;
end
final begin
  if (u_dut.s_test_done && u_dut.s_test_pass && s_p6_frames != 0) begin
    if (s_p6_sdio_overlap == 0 || s_p6_overlap_fetches == 0)
      $fatal(1, "SIM_TEST_FAIL P6 missing actual SDIO/DMA/CPU contention");
    $display("R2_P6_CONTENTION sdio_dma_cycles=%0d cpu_fetches=%0d", s_p6_sdio_overlap,
             s_p6_overlap_fetches);
    if (s_p6_completed != 4 || s_p6_underflows != 1 || s_p6_aborts != 1 ||
        s_p6_clock_stops != 2 || s_p6_wire_cases != 2 || s_p6_uart_routes != 1)
      $fatal(1, "SIM_TEST_FAIL Tiny P6 incomplete device coverage");
    $display(
        "R2_P6_DEVICES ws_frames=%0d ws_wait_max=%0d fifo_max=%0d underflows=%0d aborts=%0d clock_stops=%0d",
        s_p6_completed, s_p6_ws_wait_max, s_p6_fifo_max, s_p6_underflows, s_p6_aborts,
        s_p6_clock_stops);
  end
end
`undef _P6_WS
// Counts describe observed bus handshakes over the complete acceptance run.
// Read bytes require OKAY; write bytes are accepted W strobes, not rollback claims.
for (genvar owner = 0; owner < 3; owner++) begin : gen_p6_axi_observer
  longint unsigned read_bytes = 0, write_bytes = 0, descriptor_bytes = 0;
  longint unsigned ar_wait = 0, aw_wait = 0, w_wait = 0, r_wait = 0, b_wait = 0;
  longint unsigned ar_max = 0, aw_max = 0, w_max = 0, r_max = 0, b_max = 0;
  logic pending_read = 0, pending_write = 0, descriptor = 0;
  logic [2:0] read_size = 0;
  `define _P6_AXI u_dut.u_soc.u_masters_axi4_if[owner]
  always @(posedge s_clk) begin
    if (s_rst_n) begin
      if (`_P6_AXI.arvalid && `_P6_AXI.arready) begin
        if (pending_read) $fatal(1, "SIM_TEST_FAIL P6 duplicate read admission");
        pending_read = 1;
        read_size = `_P6_AXI.arsize;
        descriptor = owner == 1 && u_dut.u_soc.u_dma.s_tcd_count[64+:32] != 0 &&
            `_P6_AXI.araddr >= u_dut.u_soc.u_dma.s_tcd_head[64+:32] &&
            `_P6_AXI.araddr < u_dut.u_soc.u_dma.s_tcd_head[64+:32] + 32'd256;
      end
      if (`_P6_AXI.rvalid && `_P6_AXI.rready) begin
        if (!pending_read) $fatal(1, "SIM_TEST_FAIL P6 unsolicited read response");
        if (`_P6_AXI.rresp == 0) begin
          read_bytes += 64'd1 << read_size;
          if (descriptor) descriptor_bytes += 64'd1 << read_size;
        end
        if (`_P6_AXI.rlast) pending_read = 0;
      end
      if (`_P6_AXI.awvalid && `_P6_AXI.awready) begin
        if (pending_write) $fatal(1, "SIM_TEST_FAIL P6 duplicate write admission");
        pending_write = 1;
      end
      if (`_P6_AXI.wvalid && `_P6_AXI.wready) begin
        if (!pending_write) $fatal(1, "SIM_TEST_FAIL P6 W without saved AW");
        for (integer lane = 0; lane < 4; lane++) if (`_P6_AXI.wstrb[lane]) write_bytes++;
      end
      if (`_P6_AXI.bvalid && `_P6_AXI.bready) begin
        if (!pending_write) $fatal(1, "SIM_TEST_FAIL P6 unsolicited write response");
        pending_write = 0;
      end
      ar_wait = `_P6_AXI.arvalid && !`_P6_AXI.arready ? ar_wait + 1 : 0;
      aw_wait = `_P6_AXI.awvalid && !`_P6_AXI.awready ? aw_wait + 1 : 0;
      w_wait  = `_P6_AXI.wvalid && !`_P6_AXI.wready ? w_wait + 1 : 0;
      r_wait  = `_P6_AXI.rvalid && !`_P6_AXI.rready ? r_wait + 1 : 0;
      b_wait  = `_P6_AXI.bvalid && !`_P6_AXI.bready ? b_wait + 1 : 0;
      if (ar_wait > ar_max) ar_max = ar_wait;
      if (aw_wait > aw_max) aw_max = aw_wait;
      if (w_wait > w_max) w_max = w_wait;
      if (r_wait > r_max) r_max = r_wait;
      if (b_wait > b_max) b_max = b_wait;
    end
  end
  final begin
    if (u_dut.s_test_done && u_dut.s_test_pass && s_p6_frames != 0) begin
      if (pending_read || pending_write) $fatal(1, "SIM_TEST_FAIL P6 unretired accepted work");
      $display(
          "R2_P6_AXI owner=%0d read_bytes=%0d write_bytes=%0d descriptor_bytes=%0d ar_stall_max=%0d aw_stall_max=%0d w_stall_max=%0d r_stall_max=%0d b_stall_max=%0d",
          owner, read_bytes, write_bytes, descriptor_bytes, ar_max, aw_max, w_max, r_max, b_max);
    end
  end
  `undef _P6_AXI
end
always #27.126736111 if (s_p6_audio_running) s_p6_audio_reference = !s_p6_audio_reference;
assign s_gpio_17 = s_p6_audio_reference;
// The first integration case is an external codec loopback, across actual pads.
// Independent wire decoding and error injection supplement firmware readback.
assign s_gpio_15 = s_gpio_14;
wire       s_p6_card_cmd;
wire [3:0] s_p6_card_data;
wire       s_p6_card_irq;
sdio_native_card_model #(
    .MemoryInitialization(1'b1),
    .BlockCount          (1024)
) u_p6_card (
    .rst_n_i (s_rst_n),
    .sck_i   (s_gpio[0]),
    .cmd_oe_i(u_dut.u_soc.u_sdio_if.cmd_oe_o),
    .cmd_do_i(s_gpio[1]),
    .cmd_do_o(s_p6_card_cmd),
    .dat_oe_i(u_dut.u_soc.u_sdio_if.dat_oe_o),
    .dat_do_i(s_gpio[5:2]),
    .dat_do_o(s_p6_card_data),
    .irq_o   (s_p6_card_irq)
);
assign s_gpio_1 = u_dut.u_soc.u_sdio_if.cmd_oe_o ? 1'bz : s_p6_card_cmd;
assign s_gpio_2 = u_dut.u_soc.u_sdio_if.dat_oe_o[0] ? 1'bz : s_p6_card_data[0];
assign s_gpio_3 = u_dut.u_soc.u_sdio_if.dat_oe_o[1] ? 1'bz : s_p6_card_data[1];
assign s_gpio_4 = u_dut.u_soc.u_sdio_if.dat_oe_o[2] ? 1'bz : s_p6_card_data[2];
assign s_gpio_5 = u_dut.u_soc.u_sdio_if.dat_oe_o[3] ? 1'bz : s_p6_card_data[3];
always @(negedge s_clk) begin
  // Reuse the standalone card's explicit data-stimulus API. The wire command
  // fixes direction/address/length; host DATA_START only schedules admission.
  // This is repository controller integration evidence, not card compliance.
  if (u_dut.u_soc.u_sdio.s_data_start) begin
    if (u_p6_card.s_last_cmd != 17 && u_p6_card.s_last_cmd != 18 && u_p6_card.s_last_cmd != 25)
      $fatal(1, "SIM_TEST_FAIL P6 unexpected SDIO data command");
    if (u_dut.u_soc.u_sdio.s_block_size != 512 ||
        u_dut.u_soc.u_sdio.s_block_count != (u_p6_card.s_last_cmd == 17 ? 1 : 2) ||
        u_dut.u_soc.u_sdio.s_data_direction != (u_p6_card.s_last_cmd == 25) ||
        u_dut.u_soc.u_sdio.s_bus_width != (u_p6_card.s_memory_width4 ? 1 : 0))
      $fatal(1, "SIM_TEST_FAIL P6 SDIO command/data configuration disagreement");
    u_p6_card.set_data_delay(1);
    if (u_p6_card.s_last_cmd == 25)
      u_p6_card.arm_write(integer'(u_p6_card.s_last_arg * 512), 1024, u_p6_card.s_memory_width4,
                          1'b0);
    else
      u_p6_card.arm_read(integer'(u_p6_card.s_last_arg * 512),
                         u_p6_card.s_last_cmd == 17 ? 512 : 1024, u_p6_card.s_memory_width4, 1'b0);
  end
  if ($test$plusargs("p6_debug_sdio") && u_dut.u_soc.u_sdio.s_cmd_start) begin
    $display("P6_SDIO_DIAGNOSTIC cmd=%0d argument=%h status=%h", u_dut.u_soc.u_sdio.s_cmd_index,
             u_dut.u_soc.u_sdio.s_cmd_arg, u_dut.u_soc.u_sdio.s_status);
    $fflush();
  end
  if (u_dut.u_soc.u_sdio.s_cmd_start && u_dut.u_soc.u_sdio.s_cmd_index == 13) begin
    if (u_dut.u_soc.u_sdio.s_cmd_arg == 32'hbadc0de0) u_p6_card.inject_next_crc_error();
    if (u_dut.u_soc.u_sdio.s_cmd_arg == 32'hbadc0de1) u_p6_card.inject_next_timeout();
  end
end
