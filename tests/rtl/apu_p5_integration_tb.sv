// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "apu_define.svh"

module apu_p5_integration_tb;
  localparam logic [31:0] ApuBase = 32'h1001_3000;
  localparam logic [31:0] ImageBase = 32'h3000_0000;
  localparam logic [31:0] InputBase = 32'h3001_0000;
  localparam logic [31:0] RingBase = 32'h3001_0800;
  localparam logic [31:0] FlacBase = 32'h3001_1000;
  localparam logic [31:0] OutputBase = 32'h3001_2000;
  localparam logic [31:0] Flac24Base = 32'h3002_0000;

  logic        clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        resource_reset_i;
  logic [31:0] image            [0:16383];
  logic [31:0] input_image      [  0:511];
  logic [31:0] flac_image       [   0:63];
  logic [31:0] flac24_image     [   0:63];
  logic [31:0] ring_image       [   0:63];
  logic [31:0] output_image     [   0:63];
  logic        read_active_q;
  logic [31:0] read_addr_q;
  logic [7:0] read_len_q, read_beat_q;
  logic [31:0] s_value;
  logic [31:0] s_before;
  logic [11:0] tx_count_q;
  logic        tx_last_q;
  logic [31:0] tx_data_q       [0:2047];
  logic [ 5:0] tx_last_count_q;
  logic [63:0] cycle_q, playback_first_q, playback_last_q;
  logic measure_q, measure_d_q, playback_seen_q, playback_started_q, playback_done_q;
  logic playback_xrun_q;
  logic [10:0] playback_div_q, playback_period_q;
  logic [7:0] playback_fifo_count_q, playback_fifo_read_q, playback_fifo_write_q;
  logic       playback_fifo_last_q   [0:127];
  logic [4:0] output_command_count_q;
  logic [8:0] output_command_bytes_q [ 0:15];
  logic write_active_q, write_response_q;
  logic [31:0] write_addr_q;
  logic [7:0] write_len_q, write_beat_q;
  string image_path;
  string flac_path;
  string flac24_path;

  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) dma_tx_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) dma_rx_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) i2s_tx_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) i2s_rx_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  always #5 clk_i = ~clk_i;

  assign axi4.arready = !read_active_q;
  assign axi4.rid = 1'b0;
  assign axi4.rdata = (read_addr_q >= Flac24Base) ?
      flac24_image[(read_addr_q-Flac24Base)>>2] :
      ((read_addr_q >= FlacBase) ?
      flac_image[(read_addr_q-FlacBase)>>2] :
      ((read_addr_q >= RingBase) ? ring_image[(read_addr_q-RingBase)>>2] :
       ((read_addr_q >= InputBase) ? input_image[(read_addr_q-InputBase)>>2] :
        image[(read_addr_q-ImageBase)>>2])));
  assign axi4.rresp = 2'd0;
  assign axi4.rlast = read_beat_q == read_len_q;
  assign axi4.ruser = 1'b0;
  assign axi4.rvalid = read_active_q;
  assign axi4.awready = !write_active_q && !write_response_q;
  assign axi4.wready = write_active_q;
  assign axi4.bid = 1'b0;
  assign axi4.bresp = 2'd0;
  assign axi4.buser = 1'b0;
  assign axi4.bvalid = write_response_q;

  assign dma_tx_axis.tdata = 32'd0;
  assign dma_tx_axis.tkeep = 4'hf;
  assign dma_tx_axis.tstrb = 4'hf;
  assign dma_tx_axis.tlast = 1'b0;
  assign dma_tx_axis.tid = '0;
  assign dma_tx_axis.tdest = '0;
  assign dma_tx_axis.tuser = '0;
  assign dma_tx_axis.tvalid = 1'b0;
  assign dma_rx_axis.tready = 1'b1;
  assign i2s_tx_axis.tready = !measure_q || (playback_fifo_count_q < 8'd128);
  assign i2s_rx_axis.tdata = 32'd0;
  assign i2s_rx_axis.tkeep = 4'hf;
  assign i2s_rx_axis.tstrb = 4'hf;
  assign i2s_rx_axis.tlast = 1'b0;
  assign i2s_rx_axis.tid = '0;
  assign i2s_rx_axis.tdest = '0;
  assign i2s_rx_axis.tuser = '0;
  assign i2s_rx_axis.tvalid = 1'b0;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      read_active_q         <= 1'b0;
      read_addr_q           <= 32'd0;
      read_len_q            <= 8'd0;
      read_beat_q           <= 8'd0;
      tx_count_q            <= 10'd0;
      tx_last_q             <= 1'b0;
      tx_last_count_q       <= 6'd0;
      cycle_q               <= 64'd0;
      playback_first_q      <= 64'd0;
      playback_last_q       <= 64'd0;
      playback_seen_q       <= 1'b0;
      playback_started_q    <= 1'b0;
      playback_done_q       <= 1'b0;
      playback_xrun_q       <= 1'b0;
      playback_div_q        <= 11'd0;
      playback_fifo_count_q <= 8'd0;
      playback_fifo_read_q  <= 8'd0;
      playback_fifo_write_q <= 8'd0;
      for (int entry = 0; entry < 128; entry++) playback_fifo_last_q[entry] <= 1'b0;
      output_command_count_q <= 5'd0;
      for (int command = 0; command < 16; command++) output_command_bytes_q[command] <= 9'd0;
      measure_d_q      <= 1'b0;
      write_active_q   <= 1'b0;
      write_response_q <= 1'b0;
      write_addr_q     <= 32'd0;
      write_len_q      <= 8'd0;
      write_beat_q     <= 8'd0;
    end else begin
      cycle_q     <= cycle_q + 1'b1;
      measure_d_q <= measure_q;
      if (measure_q && !measure_d_q) begin
        playback_first_q       <= 64'd0;
        playback_last_q        <= 64'd0;
        playback_seen_q        <= 1'b0;
        playback_started_q     <= 1'b0;
        playback_done_q        <= 1'b0;
        playback_xrun_q        <= 1'b0;
        playback_div_q         <= 11'd0;
        playback_fifo_count_q  <= 8'd0;
        playback_fifo_read_q   <= 8'd0;
        playback_fifo_write_q  <= 8'd0;
        output_command_count_q <= 5'd0;
      end else if (measure_q && !playback_started_q && (playback_fifo_count_q >= 8'd64) &&
                   (output_command_count_q >= 5'd2)) begin
        playback_started_q <= 1'b1;
        playback_div_q     <= playback_period_q - 1'b1;
      end else if (measure_q && playback_started_q && !playback_done_q) begin
        if (playback_div_q + 1'b1 >= playback_period_q) begin
          playback_div_q <= 11'd0;
          if (playback_fifo_count_q == 8'd0) begin
            playback_xrun_q <= 1'b1;
          end else begin
            if (!playback_seen_q) begin
              playback_first_q <= cycle_q;
              playback_seen_q  <= 1'b1;
            end
            if (playback_fifo_last_q[playback_fifo_read_q[6:0]]) begin
              playback_last_q <= cycle_q;
              playback_done_q <= 1'b1;
            end
            playback_fifo_read_q <= playback_fifo_read_q + 1'b1;
          end
        end else begin
          playback_div_q <= playback_div_q + 1'b1;
        end
      end
      if (measure_q && i2s_tx_axis.tvalid && i2s_tx_axis.tready) begin
        playback_fifo_last_q[playback_fifo_write_q[6:0]] <= i2s_tx_axis.tlast;
        playback_fifo_write_q                            <= playback_fifo_write_q + 1'b1;
      end
      unique case ({
        measure_q && i2s_tx_axis.tvalid && i2s_tx_axis.tready,
        measure_q && playback_started_q && !playback_done_q &&
                    (playback_div_q + 1'b1 >= playback_period_q) &&
                    (playback_fifo_count_q != 8'd0)
      })
        2'b10: playback_fifo_count_q <= playback_fifo_count_q + 1'b1;
        2'b01: playback_fifo_count_q <= playback_fifo_count_q - 1'b1;
        default: begin
        end
      endcase
      if (measure_q && u_dut.s_transport_req_valid && u_dut.s_transport_req_ready &&
          (u_dut.s_transport_opcode inside {
            `APB4_APU__MC_TRANSPORT_OUTPUT_COMMIT,
          `APB4_APU__MC_TRANSPORT_OUTPUT_STREAM
          })) begin
        if ((u_dut.s_transport_source1 == 32'd0) || (u_dut.s_transport_source1 > 32'd256)) begin
          $fatal(1, "P5 output command size %0d is outside 1..256", u_dut.s_transport_source1);
        end
        output_command_bytes_q[output_command_count_q] <= 9'(u_dut.s_transport_source1);
        output_command_count_q                         <= output_command_count_q + 1'b1;
      end
      if (axi4.arvalid && axi4.arready) begin
        read_active_q <= 1'b1;
        read_addr_q   <= axi4.araddr;
        read_len_q    <= axi4.arlen;
        read_beat_q   <= 8'd0;
      end
      if (axi4.rvalid && axi4.rready) begin
        if (axi4.rlast) read_active_q <= 1'b0;
        else begin
          read_addr_q <= read_addr_q + 32'd4;
          read_beat_q <= read_beat_q + 1'b1;
        end
      end
      if (i2s_tx_axis.tvalid && i2s_tx_axis.tready) begin
        tx_data_q[tx_count_q] <= i2s_tx_axis.tdata;
        tx_count_q            <= tx_count_q + 1'b1;
        if (i2s_tx_axis.tlast) begin
          tx_last_q       <= 1'b1;
          tx_last_count_q <= tx_last_count_q + 1'b1;
        end
      end
      if (axi4.awvalid && axi4.awready) begin
        write_active_q <= 1'b1;
        write_addr_q   <= axi4.awaddr;
        write_len_q    <= axi4.awlen;
        write_beat_q   <= 8'd0;
      end
      if (axi4.wvalid && axi4.wready) begin
        if (((write_addr_q < RingBase) || (write_addr_q >= RingBase + 32'd256)) &&
            ((write_addr_q < OutputBase) || (write_addr_q >= OutputBase + 32'd256)))
          $fatal(1, "P5 unexpected AXI write %h", write_addr_q);
        for (int lane = 0; lane < 4; lane++) begin
          if (axi4.wstrb[lane]) begin
            if (write_addr_q >= OutputBase)
              output_image[(write_addr_q-OutputBase)>>2][lane*8+:8] <= axi4.wdata[lane*8+:8];
            else ring_image[(write_addr_q-RingBase)>>2][lane*8+:8] <= axi4.wdata[lane*8+:8];
          end
        end
        if (axi4.wlast != (write_beat_q == write_len_q)) $fatal(1, "P5 AXI write last mismatch");
        if (axi4.wlast) begin
          write_active_q   <= 1'b0;
          write_response_q <= 1'b1;
        end else begin
          write_addr_q <= write_addr_q + 32'd4;
          write_beat_q <= write_beat_q + 1'b1;
        end
      end
      if (axi4.bvalid && axi4.bready) write_response_q <= 1'b0;
    end
  end

  apb4_apu u_dut (
      .clk_i,
      .rst_n_i,
      .owner_i          (2'd0),
      .owner_lock_i     (1'b0),
      .quiesce_i        (apb4.pprot[0]),
      .resource_reset_i,
      .bridge_epoch_i   (8'd0),
      .i2s_tx_underrun_i(playback_xrun_q),
      .i2s_rx_overrun_i (1'b0),
      .apb4,
      .axi4,
      .dma_tx_axis,
      .dma_rx_axis,
      .i2s_tx_axis,
      .i2s_rx_axis,
      .idle_o           (),
      .irq_o            ()
  );

  task automatic apb_write(input logic [11:0] offset_i, input logic [31:0] value_i,
                           input logic expected_error_i);
    begin
      @(negedge clk_i);
      apb4.paddr   = ApuBase + offset_i;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      apb4.pwrite  = 1'b1;
      apb4.pwdata  = value_i;
      apb4.pstrb   = 4'hf;
      @(negedge clk_i);
      apb4.penable = 1'b1;
      while (!apb4.pready) @(negedge clk_i);
      if (apb4.pslverr != expected_error_i)
        $fatal(
            1,
            "P5 APB write response mismatch %h allowed=%0d idle=%0d codec=%0d valid=%0d lock=%0d check=%0d/%0d/%h scratch=%0d input=%h/%h output=%h/%h",
            offset_i,
            u_dut.s_codec_direct_allowed,
            u_dut.s_system_idle,
            u_dut.u_codec_controller.s_state_q,
            u_dut.s_mc_status[`APB4_APU__MC_STATUS_VALID],
            u_dut.s_mc_lock,
            u_dut.u_codec_controller.s_direct_valid,
            u_dut.u_codec_controller.s_direct_reject_code,
            u_dut.u_codec_controller.s_direct_reject_detail,
            u_dut.u_codec_controller.s_direct_scratch_bytes,
            u_dut.s_direct_descriptor[(2*32)+:32],
            u_dut.s_direct_descriptor[(3*32)+:32],
            u_dut.s_direct_descriptor[(4*32)+:32],
            u_dut.s_direct_descriptor[(5*32)+:32]
        );
      @(negedge clk_i);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
    end
  endtask

  task automatic apb_read(input logic [11:0] offset_i, output logic [31:0] value_o);
    begin
      @(negedge clk_i);
      apb4.paddr   = ApuBase + offset_i;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      apb4.pwrite  = 1'b0;
      apb4.pstrb   = 4'd0;
      @(negedge clk_i);
      apb4.penable = 1'b1;
      while (!apb4.pready) @(negedge clk_i);
      if (apb4.pslverr) $fatal(1, "P5 APB read failed %h", offset_i);
      value_o = apb4.prdata;
      @(negedge clk_i);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
    end
  endtask

  initial begin
    logic seen_busy;
    if (!$value$plusargs("IMAGE=%s", image_path)) $fatal(1, "IMAGE plusarg missing");
    if (!$value$plusargs("FLAC=%s", flac_path)) $fatal(1, "FLAC plusarg missing");
    if (!$value$plusargs("FLAC24=%s", flac24_path)) $fatal(1, "FLAC24 plusarg missing");
    $readmemh(image_path, image);
    $readmemh(flac_path, flac_image);
    $readmemh(flac24_path, flac24_image);
    measure_q         = 1'b0;
    playback_period_q = 11'd1;
    for (int word = 0; word < 512; word++) input_image[word] = 32'd0;
    input_image[0]  = 32'h4646_4952;
    input_image[1]  = 32'h0000_002c;
    input_image[2]  = 32'h4556_4157;
    input_image[3]  = 32'h2074_6d66;
    input_image[4]  = 32'h0000_0010;
    input_image[5]  = 32'h0002_0001;
    input_image[6]  = 32'h0000_bb80;
    input_image[7]  = 32'h0002_ee00;
    input_image[8]  = 32'h0010_0004;
    input_image[9]  = 32'h6174_6164;
    input_image[10] = 32'h0000_0008;
    input_image[11] = 32'h7fff_8000;
    input_image[12] = 32'h0001_ffff;
    for (int word = 0; word < 64; word++) ring_image[word] = 32'd0;
    for (int word = 0; word < 64; word++) output_image[word] = 32'd0;
    ring_image[0] = (32'd1 << `APB4_APU__DESCRIPTOR_CONTROL_OWN) |
        (32'd1 << `APB4_APU__DESCRIPTOR_CONTROL_IOC) | (32'd1 << 8);
    ring_image[2] = InputBase;
    ring_image[3] = 32'd52;
    ring_image[6] = 32'h0104_bb80;
    ring_image[7] = 32'h0004_bb80;
    ring_image[8] = 32'd1;
    apb4.paddr = 32'd0;
    resource_reset_i = 1'b0;
    apb4.pprot = 3'd1;
    apb4.psel = 1'b0;
    apb4.penable = 1'b0;
    apb4.pwrite = 1'b0;
    apb4.pwdata = 32'd0;
    apb4.pstrb = 4'd0;
    repeat (4) @(posedge clk_i);
    rst_n_i = 1'b1;
    repeat (2) @(posedge clk_i);

    apb_write(`APB4_APU__READ_BASE, ImageBase, 1'b0);
    apb_write(`APB4_APU__READ_LIMIT, Flac24Base + 32'd255, 1'b0);
    apb_write(`APB4_APU__WRITE_BASE, RingBase, 1'b0);
    apb_write(`APB4_APU__WRITE_LIMIT, OutputBase + 32'd255, 1'b0);
    apb_write(`APB4_APU__MC_IMAGE_ADDRESS, ImageBase, 1'b0);
    apb_write(`APB4_APU__MC_IMAGE_SIZE, image[2], 1'b0);
    apb_write(`APB4_APU__MC_EXPECTED_CRC, image[11], 1'b0);
    apb_write(`APB4_APU__COMMAND, 32'd1 << `APB4_APU__COMMAND_MICROCODE_LOAD, 1'b0);
    for (int poll = 0; poll < 500000; poll++) begin
      apb_read(`APB4_APU__MC_STATUS, s_value);
      if (s_value[`APB4_APU__MC_STATUS_VALID]) break;
      if (!s_value[`APB4_APU__MC_STATUS_BUSY]) begin
        $fatal(1, "P5 load failed %h pc=%0d addr=%h detail=%h", s_value,
               u_dut.u_microcode_loader.s_scan_control_pc_q,
               u_dut.u_microcode_loader.s_scan_control_addr_q,
               u_dut.u_microcode_loader.s_scan_control_detail_q);
      end
    end
    if (!s_value[`APB4_APU__MC_STATUS_VALID]) begin
      $fatal(1, "P5 load timeout state=%0d entry=%0d pc=%0d paths=%0d probe=%0d",
             u_dut.u_microcode_loader.s_state_q, u_dut.u_microcode_loader.s_scan_entry_q,
             u_dut.u_microcode_loader.s_scan_pc_q, u_dut.u_microcode_loader.s_path_stack_count_q,
             u_dut.u_microcode_loader.s_path_memo_probe_q);
    end

    apb4.pprot = 3'd0;
    apb_write(`APB4_APU__JOB_CONTROL, 32'd0, 1'b0);
    apb_write(`APB4_APU__JOB_INPUT_ADDRESS, InputBase, 1'b0);
    apb_write(`APB4_APU__JOB_INPUT_LENGTH, 32'd52, 1'b0);
    apb_write(`APB4_APU__JOB_OUTPUT_ADDRESS, OutputBase, 1'b0);
    apb_write(`APB4_APU__JOB_OUTPUT_CAPACITY, 32'd8, 1'b0);
    apb_write(`APB4_APU__JOB_INPUT_CONFIG, 32'h0104_bb80, 1'b0);
    apb_write(`APB4_APU__JOB_OUTPUT_CONFIG, 32'h0004_bb80, 1'b0);
    apb_write(`APB4_APU__JOB_FLAGS, 32'd1, 1'b0);
    apb_write(`APB4_APU__COMMAND, 32'd1 << `APB4_APU__COMMAND_START_DIRECT, 1'b0);
    seen_busy = 1'b0;
    for (int poll = 0; poll < 500000; poll++) begin
      apb_read(`APB4_APU__JOB_STATUS, s_value);
      if (s_value[`APB4_APU__JOB_STATUS_BUSY]) seen_busy = 1'b1;
      if (seen_busy && (s_value[`APB4_APU__JOB_STATUS_DONE] ||
                        s_value[`APB4_APU__JOB_STATUS_ERROR]))
        break;
    end
    if (!s_value[`APB4_APU__JOB_STATUS_DONE] || output_image[0] != 32'h7fff_8000 ||
        output_image[1] != 32'h0001_ffff)
      $fatal(
          1,
          "P5 direct memory WAV mismatch status=%h data=%h/%h",
          s_value,
          output_image[0],
          output_image[1]
      );

    apb_write(`APB4_APU__STREAM_ROUTE, 32'd1, 1'b0);
    apb_read(`APB4_APU__JOB_STATUS, s_before);
    apb_write(`APB4_APU__JOB_CONTROL, 32'h0000_0100, 1'b0);
    apb_write(`APB4_APU__JOB_INPUT_ADDRESS, InputBase, 1'b0);
    apb_write(`APB4_APU__JOB_INPUT_LENGTH, 32'd52, 1'b0);
    apb_write(`APB4_APU__JOB_OUTPUT_ADDRESS, 32'd0, 1'b0);
    apb_write(`APB4_APU__JOB_OUTPUT_CAPACITY, 32'd0, 1'b0);
    apb_write(`APB4_APU__JOB_INPUT_CONFIG, 32'h0104_bb80, 1'b0);
    apb_write(`APB4_APU__JOB_OUTPUT_CONFIG, 32'h0004_0001, 1'b0);
    apb_write(`APB4_APU__JOB_FLAGS, 32'd1, 1'b0);
    apb_write(`APB4_APU__COMMAND, 32'd1 << `APB4_APU__COMMAND_START_DIRECT, 1'b1);
    apb_read(`APB4_APU__JOB_STATUS, s_value);
    if (s_value != s_before) $fatal(1, "rejected P5 direct job mutated result state");

    apb_write(`APB4_APU__JOB_CONTROL, 32'h0000_0100, 1'b0);
    apb_write(`APB4_APU__JOB_INPUT_ADDRESS, InputBase, 1'b0);
    apb_write(`APB4_APU__JOB_INPUT_LENGTH, 32'd52, 1'b0);
    apb_write(`APB4_APU__JOB_OUTPUT_ADDRESS, 32'd0, 1'b0);
    apb_write(`APB4_APU__JOB_OUTPUT_CAPACITY, 32'd0, 1'b0);
    apb_write(`APB4_APU__JOB_INPUT_CONFIG, 32'h0104_bb80, 1'b0);
    apb_write(`APB4_APU__JOB_OUTPUT_CONFIG, 32'h0004_bb80, 1'b0);
    apb_write(`APB4_APU__JOB_FLAGS, 32'd1, 1'b0);
    apb_write(`APB4_APU__COMMAND, 32'd1 << `APB4_APU__COMMAND_START_DIRECT, 1'b0);

    for (int poll = 0; poll < 500000; poll++) begin
      apb_read(`APB4_APU__JOB_STATUS, s_value);
      if (s_value[`APB4_APU__JOB_STATUS_DONE] || s_value[`APB4_APU__JOB_STATUS_ERROR]) break;
    end
    if (!s_value[`APB4_APU__JOB_STATUS_DONE]) begin
      $display("P5 WAV job failed status=%h", s_value);
      $display("P5 sequencer status=%h retired=%h fault=%h", u_dut.s_seq_status,
               u_dut.s_seq_retired, u_dut.s_seq_fault_detail);
      $display("P5 primitive state=%0d kernel state=%0d element=%0d produced=%0d req=%0d valid=%0d",
               u_dut.u_primitive_dispatcher.s_state_q,
               u_dut.u_primitive_dispatcher.u_kernel_engine.s_state_q,
               u_dut.u_primitive_dispatcher.u_kernel_engine.s_element_q,
               u_dut.u_primitive_dispatcher.u_kernel_engine.s_produced_q,
               u_dut.u_primitive_dispatcher.s_kernel_memory_req, u_dut.s_local_primitive_valid);
      $display(
          "P5 pending kernel=%0d transport=%b transport_state=%0d dma_busy=%0d stream_idle=%0d",
          u_dut.u_codec_sequencer.s_kernel_pending_q, u_dut.u_codec_sequencer.s_transport_pending_q,
          u_dut.u_codec_transport.s_state_q, u_dut.s_dma_busy, u_dut.s_stream_idle);
      $display("P5 codec detail=%h logical=%0d/%0d cursor=%0d/%0d frames=%0d final=%b",
               u_dut.s_codec_detail, u_dut.u_codec_transport.s_logical_input_q,
               u_dut.u_codec_transport.s_logical_output_q,
               u_dut.u_codec_transport.s_input_cursor_q, u_dut.u_codec_transport.s_output_cursor_q,
               u_dut.u_codec_transport.s_frames_q, u_dut.u_codec_transport.s_final_seen_q);
`ifndef HAVE_SRAM_MACRO
      $display("P5 frame-bytes=%0d request=%0d/%0d/%0d inflight=%0d/%0d/%0d",
               u_dut.u_codec_transport.s_frame_bytes_q, u_dut.s_transport_opcode,
               u_dut.s_transport_source0, u_dut.s_transport_source1,
               u_dut.u_local_sram.mem[15'h17cc], u_dut.u_local_sram.mem[15'h17cd],
               u_dut.u_local_sram.mem[15'h17ce]);
`endif
      apb_read(`APB4_APU__ERROR_STATUS, s_value);
      $display("P5 error status=%h", s_value);
      apb_read(`APB4_APU__ERROR_ADDRESS, s_value);
      $display("P5 error address=%h", s_value);
      apb_read(`APB4_APU__ERROR_DETAIL, s_value);
      $fatal(1, "P5 error detail=%h", s_value);
    end
    apb_read(`APB4_APU__JOB_INPUT_USED, s_value);
    if (s_value != 32'd52) $fatal(1, "P5 input count mismatch");
    apb_read(`APB4_APU__JOB_OUTPUT_BYTES, s_value);
    if (s_value != 32'd8) $fatal(1, "P5 output count mismatch");
    apb_read(`APB4_APU__JOB_FRAMES, s_value);
    if (s_value != 32'd2) $fatal(1, "P5 frame count mismatch");
    if (tx_count_q != 2'd2 || !tx_last_q) $fatal(1, "P5 TX stream mismatch");

    apb_write(`APB4_APU__JOB_CONTROL, 32'h0000_0120, 1'b0);
    apb_write(`APB4_APU__JOB_INPUT_ADDRESS, FlacBase, 1'b0);
    apb_write(`APB4_APU__JOB_INPUT_LENGTH, 32'd54, 1'b0);
    apb_write(`APB4_APU__JOB_INPUT_CONFIG, 32'd0, 1'b0);
    apb_write(`APB4_APU__JOB_OUTPUT_CONFIG, 32'h0004_bb80, 1'b0);
    apb_write(`APB4_APU__COMMAND, 32'd1 << `APB4_APU__COMMAND_START_DIRECT, 1'b0);
    for (int poll = 0; poll < 500000; poll++) begin
      apb_read(`APB4_APU__JOB_STATUS, s_value);
      if (s_value[`APB4_APU__JOB_STATUS_DONE] || s_value[`APB4_APU__JOB_STATUS_ERROR]) break;
    end
    if (!s_value[`APB4_APU__JOB_STATUS_DONE]) begin
      $display("P5 constant FLAC job failed status=%h", s_value);
      apb_read(`APB4_APU__ERROR_STATUS, s_value);
      $display("P5 FLAC error status=%h", s_value);
      apb_read(`APB4_APU__ERROR_ADDRESS, s_value);
      $display("P5 FLAC error address=%h", s_value);
      apb_read(`APB4_APU__SEQUENCER_STATUS, s_value);
      $display("P5 FLAC sequencer status=%h", s_value);
      $display("P5 FLAC GPR r4=%h r5=%h r6=%h r7=%h r8=%h r9=%h r10=%h r11=%h r13=%h",
               u_dut.s_seq_gpr[4], u_dut.s_seq_gpr[5], u_dut.s_seq_gpr[6], u_dut.s_seq_gpr[7],
               u_dut.s_seq_gpr[8], u_dut.s_seq_gpr[9], u_dut.s_seq_gpr[10], u_dut.s_seq_gpr[11],
               u_dut.s_seq_gpr[13]);
      apb_read(`APB4_APU__ERROR_DETAIL, s_value);
      $fatal(1, "P5 FLAC error detail=%h", s_value);
    end
    apb_read(`APB4_APU__JOB_INPUT_USED, s_value);
    if (s_value != 32'd54) $fatal(1, "P5 FLAC input count mismatch");
    apb_read(`APB4_APU__JOB_OUTPUT_BYTES, s_value);
    if (s_value != 32'd64) $fatal(1, "P5 FLAC output count mismatch");
    apb_read(`APB4_APU__JOB_FRAMES, s_value);
    if (s_value != 32'd16) $fatal(1, "P5 FLAC frame count mismatch");
    apb_read(`APB4_APU__JOB_SOURCE_INFO, s_value);
    if (s_value != 32'h0082_bb80) $fatal(1, "P5 FLAC source info mismatch %h", s_value);
    apb_read(`APB4_APU__JOB_DETAIL, s_value);
    if (s_value != 32'h0201_0000) $fatal(1, "P5 FLAC warning mismatch %h", s_value);
    if (tx_count_q != 6'd18) $fatal(1, "constant FLAC TX output mismatch");
    for (int frame = 2; frame < 18; frame++) begin
      if (tx_data_q[frame] != 32'hfffe_fffe)
        $fatal(1, "P5 constant FLAC PCM mismatch frame=%0d data=%h", frame, tx_data_q[frame]);
    end
    if (tx_last_count_q != 6'd2) $fatal(1, "P5 direct TLAST count mismatch");

    apb_write(`APB4_APU__RING_BASE, RingBase, 1'b0);
    apb_write(`APB4_APU__RING_SIZE, 32'd2, 1'b0);
    apb_write(`APB4_APU__RING_TAIL, 32'd1, 1'b0);
    apb_write(`APB4_APU__RING_COALESCE, 32'h0001_0001, 1'b0);
    apb_write(`APB4_APU__RING_CONTROL, 32'd1, 1'b0);
    apb_write(`APB4_APU__RING_DOORBELL, 32'd1, 1'b0);
    for (int poll = 0; poll < 500000; poll++) begin
      apb_read(`APB4_APU__RING_HEAD, s_value);
      if (s_value == 32'd1) break;
    end
    if (s_value != 32'd1) $fatal(1, "P5 ring job timeout");
    if (ring_image[0][`APB4_APU__DESCRIPTOR_CONTROL_OWN] ||
        !ring_image[1][`APB4_APU__DESCRIPTOR_STATUS_DONE])
      $fatal(1, "P5 ring OWN-last/result status mismatch");
    if (ring_image[10] != 32'd52 || ring_image[11] != 32'd8 || ring_image[12] != 32'd2 ||
        ring_image[13] != 32'h0084_bb80)
      $fatal(1, "P5 ring result accounting mismatch");
    if (tx_count_q != 6'd20) $fatal(1, "P5 ring TX output mismatch");

    for (int word = 32; word < 64; word++) ring_image[word] = 32'd0;
    ring_image[32] = (32'd1 << `APB4_APU__DESCRIPTOR_CONTROL_OWN) |
        (32'd1 << `APB4_APU__DESCRIPTOR_CONTROL_IOC) | (32'd1 << 8) | (32'd1 << 4);
    ring_image[34] = InputBase;
    ring_image[35] = 32'd52;
    ring_image[38] = 32'h0104_bb80;
    ring_image[39] = 32'h0004_bb80;
    ring_image[40] = 32'd1;
    apb_write(`APB4_APU__RING_TAIL, 32'd0, 1'b0);
    apb_write(`APB4_APU__RING_DOORBELL, 32'd1, 1'b0);
    for (int poll = 0; poll < 500000; poll++) begin
      apb_read(`APB4_APU__RING_HEAD, s_value);
      if (s_value == 32'd0) break;
    end
    if (s_value != 32'd0 || ring_image[32][`APB4_APU__DESCRIPTOR_CONTROL_OWN] ||
        !ring_image[33][`APB4_APU__DESCRIPTOR_STATUS_ERROR] ||
        ring_image[47] != 32'h0100_0001)
      $fatal(1, "P5 invalid MP3 ring completion mismatch");

    for (int word = 0; word < 32; word++) ring_image[word] = 32'd0;
    ring_image[0] = (32'd1 << `APB4_APU__DESCRIPTOR_CONTROL_OWN) |
        (32'd1 << `APB4_APU__DESCRIPTOR_CONTROL_IOC) | (32'd1 << 8) | (32'd2 << 4);
    ring_image[2] = FlacBase;
    ring_image[3] = 32'd54;
    ring_image[7] = 32'h0004_bb80;
    apb_write(`APB4_APU__RING_TAIL, 32'd1, 1'b0);
    apb_write(`APB4_APU__RING_DOORBELL, 32'd1, 1'b0);
    for (int poll = 0; poll < 500000; poll++) begin
      apb_read(`APB4_APU__RING_HEAD, s_value);
      if (s_value == 32'd1) break;
    end
    if (s_value != 32'd1 || ring_image[0][`APB4_APU__DESCRIPTOR_CONTROL_OWN] ||
        !ring_image[1][`APB4_APU__DESCRIPTOR_STATUS_DONE] || ring_image[10] != 32'd54 ||
        ring_image[11] != 32'd64 || ring_image[12] != 32'd16)
      $fatal(1, "P5 constant FLAC ring completion mismatch");
    if (tx_count_q != 6'd36) $fatal(1, "P5 constant FLAC ring TX mismatch");
    for (int frame = 20; frame < 36; frame++) begin
      if (tx_data_q[frame] != 32'hfffe_fffe)
        $fatal(1, "P5 ring FLAC PCM mismatch frame=%0d data=%h", frame, tx_data_q[frame]);
    end
    if (tx_last_count_q != 6'd4) $fatal(1, "P5 ring TLAST count mismatch");

    apb_write(`APB4_APU__RING_CONTROL, 32'd0, 1'b0);
    for (int word = 0; word < 158; word++) input_image[word] = 32'd0;
    input_image[0]    = 32'h4646_4952;
    input_image[1]    = 32'h0000_0270;
    input_image[2]    = 32'h4556_4157;
    input_image[3]    = 32'h2074_6d66;
    input_image[4]    = 32'h0000_0010;
    input_image[5]    = 32'h0002_0001;
    input_image[6]    = 32'h0000_ac44;
    input_image[7]    = 32'h0002_b110;
    input_image[8]    = 32'h0010_0004;
    input_image[9]    = 32'h6174_6164;
    input_image[10]   = 32'h0000_024c;
    playback_period_q = 11'd1000;
    measure_q         = 1'b1;
    apb_write(`APB4_APU__JOB_CONTROL, 32'h0000_0900, 1'b0);
    apb_write(`APB4_APU__JOB_INPUT_ADDRESS, InputBase, 1'b0);
    apb_write(`APB4_APU__JOB_INPUT_LENGTH, 32'd632, 1'b0);
    apb_write(`APB4_APU__JOB_OUTPUT_ADDRESS, 32'd0, 1'b0);
    apb_write(`APB4_APU__JOB_OUTPUT_CAPACITY, 32'd0, 1'b0);
    apb_write(`APB4_APU__JOB_INPUT_CONFIG, 32'h0104_ac44, 1'b0);
    apb_write(`APB4_APU__JOB_OUTPUT_CONFIG, 32'h0004_bb80, 1'b0);
    apb_write(`APB4_APU__JOB_FLAGS, 32'd1, 1'b0);
    apb_write(`APB4_APU__COMMAND, 32'd1 << `APB4_APU__COMMAND_START_DIRECT, 1'b0);
    seen_busy = 1'b0;
    for (int poll = 0; poll < 500000; poll++) begin
      apb_read(`APB4_APU__JOB_STATUS, s_value);
      if (s_value[`APB4_APU__JOB_STATUS_BUSY]) seen_busy = 1'b1;
      if (seen_busy && (s_value[`APB4_APU__JOB_STATUS_DONE] ||
                        s_value[`APB4_APU__JOB_STATUS_ERROR]))
        break;
    end
    if (s_value[`APB4_APU__JOB_STATUS_DONE]) wait (playback_done_q);
    measure_q = 1'b0;
    if (!s_value[`APB4_APU__JOB_STATUS_DONE]) begin
      $display("P5 44.1-to-48 seq=%h retired=%h fault=%h primitive=%0d kernel=%0d",
               u_dut.s_seq_status, u_dut.s_seq_retired, u_dut.s_seq_fault_detail,
               u_dut.u_primitive_dispatcher.s_state_q,
               u_dut.u_primitive_dispatcher.u_kernel_engine.s_state_q);
      $display("P5 44.1-to-48 gpr1=%h gpr3=%h gpr5=%h gpr8=%h local=%h/%0d", u_dut.s_seq_gpr[1],
               u_dut.s_seq_gpr[3], u_dut.s_seq_gpr[5], u_dut.s_seq_gpr[8],
               u_dut.u_primitive_dispatcher.s_local_addr_q, u_dut.s_local_codec_err);
`ifndef HAVE_SRAM_MACRO
      $display("P5 44.1-to-48 tile=%0d", u_dut.u_local_sram.mem[15'h1715]);
`endif
    end
    if (!s_value[`APB4_APU__JOB_STATUS_DONE] || tx_count_q != 10'd196 || tx_last_count_q != 6'd5)
      $fatal(1, "P5 44.1-to-48 playback mismatch status=%h count=%0d", s_value, tx_count_q);
    for (int frame = 36; frame < 196; frame++) begin
      if (tx_data_q[frame] != 32'd0)
        $fatal(1, "P5 44.1-to-48 PCM mismatch frame=%0d data=%h", frame, tx_data_q[frame]);
    end
    if (!playback_seen_q || playback_xrun_q || (playback_last_q - playback_first_q > 64'd159000))
      $fatal(1, "P5 44.1-to-48 real-time span failed %0d", playback_last_q - playback_first_q);
    if ((output_command_count_q != 5'd3) || (output_command_bytes_q[0] != 9'd256) ||
        (output_command_bytes_q[1] != 9'd256) || (output_command_bytes_q[2] != 9'd128))
      $fatal(1, "P5 44.1-to-48 output command packing mismatch");
    apb_read(`APB4_APU__JOB_CYCLES, s_value);
    $display("APU-P5 PLAYBACK_44100_48000 cycles=%0d span=%0d frames=160", s_value,
             playback_last_q - playback_first_q);

    for (int word = 0; word < 107; word++) input_image[word] = 32'd0;
    input_image[0]    = 32'h4646_4952;
    input_image[1]    = 32'h0000_01a4;
    input_image[2]    = 32'h4556_4157;
    input_image[3]    = 32'h2074_6d66;
    input_image[4]    = 32'h0000_0010;
    input_image[5]    = 32'h0001_0001;
    input_image[6]    = 32'h0001_7700;
    input_image[7]    = 32'h0004_6500;
    input_image[8]    = 32'h0018_0003;
    input_image[9]    = 32'h6174_6164;
    input_image[10]   = 32'h0000_0180;
    playback_period_q = 11'd250;
    measure_q         = 1'b1;
    apb_write(`APB4_APU__JOB_CONTROL, 32'h0000_0100, 1'b0);
    apb_write(`APB4_APU__JOB_INPUT_ADDRESS, InputBase, 1'b0);
    apb_write(`APB4_APU__JOB_INPUT_LENGTH, 32'd428, 1'b0);
    apb_write(`APB4_APU__JOB_OUTPUT_ADDRESS, 32'd0, 1'b0);
    apb_write(`APB4_APU__JOB_OUTPUT_CAPACITY, 32'd0, 1'b0);
    apb_write(`APB4_APU__JOB_INPUT_CONFIG, 32'h0183_7700, 1'b0);
    apb_write(`APB4_APU__JOB_OUTPUT_CONFIG, 32'h000d_7700, 1'b0);
    apb_write(`APB4_APU__JOB_FLAGS, 32'd1, 1'b0);
    apb_write(`APB4_APU__COMMAND, 32'd1 << `APB4_APU__COMMAND_START_DIRECT, 1'b0);
    seen_busy = 1'b0;
    for (int poll = 0; poll < 500000; poll++) begin
      apb_read(`APB4_APU__JOB_STATUS, s_value);
      if (s_value[`APB4_APU__JOB_STATUS_BUSY]) seen_busy = 1'b1;
      if (seen_busy && (s_value[`APB4_APU__JOB_STATUS_DONE] ||
                        s_value[`APB4_APU__JOB_STATUS_ERROR]))
        break;
    end
    if (s_value[`APB4_APU__JOB_STATUS_DONE]) wait (playback_done_q);
    measure_q = 1'b0;
    if (!s_value[`APB4_APU__JOB_STATUS_DONE]) begin
      $display("P5 24-bit/96-kHz detail=%h input=%0d output=%0d frames=%0d seq=%h",
               u_dut.s_codec_detail, u_dut.s_codec_input_used, u_dut.s_codec_output_bytes,
               u_dut.s_codec_frames, u_dut.s_seq_status);
      $display("P5 24-bit/96-kHz primitive=%0d kernel=%0d transport=%0d fifo=%0d/%0d sink=%0d",
               u_dut.u_primitive_dispatcher.s_state_q,
               u_dut.u_primitive_dispatcher.u_kernel_engine.s_state_q,
               u_dut.u_codec_transport.s_state_q, u_dut.s_primitive_output_count,
               u_dut.u_stream_router.s_tx_count, playback_fifo_count_q);
`ifndef HAVE_SRAM_MACRO
      $display("P5 24-bit/96-kHz align=%0d remaining=%0d pending=%0d tile=%0d",
               u_dut.u_local_sram.mem[15'h1709], u_dut.u_local_sram.mem[15'h170e],
               u_dut.u_local_sram.mem[15'h1711], u_dut.u_local_sram.mem[15'h1715]);
      $display("P5 24-bit/96-kHz inflight=%0d/%0d/%0d final=%0d", u_dut.u_local_sram.mem[15'h17cc],
               u_dut.u_local_sram.mem[15'h17cd], u_dut.u_local_sram.mem[15'h17ce],
               u_dut.u_local_sram.mem[15'h17cf]);
`endif
    end
    if (!s_value[`APB4_APU__JOB_STATUS_DONE] || tx_count_q != 10'd452 || tx_last_count_q != 6'd6)
      $fatal(1, "P5 24-bit/96-kHz playback mismatch status=%h count=%0d", s_value, tx_count_q);
    for (int word = 196; word < 452; word++) begin
      if (tx_data_q[word] != 32'd0)
        $fatal(1, "P5 24-bit/96-kHz PCM mismatch word=%0d data=%h", word, tx_data_q[word]);
    end
    if (!playback_seen_q || playback_xrun_q || (playback_last_q - playback_first_q > 64'd63750))
      $fatal(1, "P5 24-bit/96-kHz real-time span failed %0d", playback_last_q - playback_first_q);
    if (output_command_count_q != 5'd4) $fatal(1, "P5 24-bit/96-kHz output command count mismatch");
    for (int command = 0; command < 4; command++) begin
      if (output_command_bytes_q[command] != 9'd256)
        $fatal(1, "P5 24-bit/96-kHz output command %0d mismatch", command);
    end
    apb_read(`APB4_APU__JOB_CYCLES, s_value);
    $display("APU-P5 PLAYBACK_24B_96000 cycles=%0d span=%0d frames=128", s_value,
             playback_last_q - playback_first_q);

    playback_period_q = 11'd250;
    measure_q         = 1'b1;
    apb_write(`APB4_APU__JOB_CONTROL, 32'h0000_0120, 1'b0);
    apb_write(`APB4_APU__JOB_INPUT_ADDRESS, Flac24Base, 1'b0);
    apb_write(`APB4_APU__JOB_INPUT_LENGTH, 32'd55, 1'b0);
    apb_write(`APB4_APU__JOB_OUTPUT_ADDRESS, 32'd0, 1'b0);
    apb_write(`APB4_APU__JOB_OUTPUT_CAPACITY, 32'd0, 1'b0);
    apb_write(`APB4_APU__JOB_INPUT_CONFIG, 32'd0, 1'b0);
    apb_write(`APB4_APU__JOB_OUTPUT_CONFIG, 32'h000d_7700, 1'b0);
    apb_write(`APB4_APU__JOB_FLAGS, 32'd1, 1'b0);
    apb_write(`APB4_APU__COMMAND, 32'd1 << `APB4_APU__COMMAND_START_DIRECT, 1'b0);
    seen_busy = 1'b0;
    for (int poll = 0; poll < 500000; poll++) begin
      apb_read(`APB4_APU__JOB_STATUS, s_value);
      if (s_value[`APB4_APU__JOB_STATUS_BUSY]) seen_busy = 1'b1;
      if (seen_busy && (s_value[`APB4_APU__JOB_STATUS_DONE] ||
                        s_value[`APB4_APU__JOB_STATUS_ERROR]))
        break;
    end
    if (s_value[`APB4_APU__JOB_STATUS_DONE]) wait (playback_done_q);
    measure_q = 1'b0;
    if (!s_value[`APB4_APU__JOB_STATUS_DONE] || playback_xrun_q ||
        (tx_count_q != 12'd708) || (tx_last_count_q != 6'd7))
      $fatal(1, "P5 24-bit/96-kHz FLAC playback mismatch status=%h count=%0d", s_value, tx_count_q);
    for (int word = 452; word < 708; word++) begin
      if (tx_data_q[word] != 32'hffff_fffe)
        $fatal(1, "P5 24-bit/96-kHz FLAC PCM mismatch word=%0d data=%h", word, tx_data_q[word]);
    end
    if (!playback_seen_q || (playback_last_q - playback_first_q > 64'd63750) ||
        (output_command_count_q != 5'd4))
      $fatal(1, "P5 24-bit/96-kHz FLAC command/prefill mismatch");
    for (int command = 0; command < 4; command++) begin
      if (output_command_bytes_q[command] != 9'd256)
        $fatal(1, "P5 24-bit/96-kHz FLAC output command %0d mismatch", command);
    end
    apb_read(`APB4_APU__JOB_CYCLES, s_value);
    $display("APU-P5 PLAYBACK_FLAC_24B_96000 cycles=%0d span=%0d frames=128", s_value,
             playback_last_q - playback_first_q);

    for (int word = 0; word < 27; word++) input_image[word] = 32'd0;
    input_image[0]    = 32'h4646_4952;
    input_image[1]    = 32'h0000_0064;
    input_image[2]    = 32'h4556_4157;
    input_image[3]    = 32'h2074_6d66;
    input_image[4]    = 32'h0000_0010;
    input_image[5]    = 32'h0001_0001;
    input_image[6]    = 32'h0000_1f40;
    input_image[7]    = 32'h0000_3e80;
    input_image[8]    = 32'h0010_0002;
    input_image[9]    = 32'h6174_6164;
    input_image[10]   = 32'h0000_0040;
    playback_period_q = 11'd250;
    measure_q         = 1'b1;
    apb_write(`APB4_APU__JOB_CONTROL, 32'h0000_0900, 1'b0);
    apb_write(`APB4_APU__JOB_INPUT_ADDRESS, InputBase, 1'b0);
    apb_write(`APB4_APU__JOB_INPUT_LENGTH, 32'd108, 1'b0);
    apb_write(`APB4_APU__JOB_OUTPUT_ADDRESS, 32'd0, 1'b0);
    apb_write(`APB4_APU__JOB_OUTPUT_CAPACITY, 32'd0, 1'b0);
    apb_write(`APB4_APU__JOB_INPUT_CONFIG, 32'd0, 1'b0);
    apb_write(`APB4_APU__JOB_OUTPUT_CONFIG, 32'h000d_7700, 1'b0);
    apb_write(`APB4_APU__JOB_FLAGS, 32'd1, 1'b0);
    apb_write(`APB4_APU__COMMAND, 32'd1 << `APB4_APU__COMMAND_START_DIRECT, 1'b0);
    seen_busy = 1'b0;
    for (int poll = 0; poll < 1000000; poll++) begin
      apb_read(`APB4_APU__JOB_STATUS, s_value);
      if (s_value[`APB4_APU__JOB_STATUS_BUSY]) seen_busy = 1'b1;
      if (seen_busy && (s_value[`APB4_APU__JOB_STATUS_DONE] ||
                        s_value[`APB4_APU__JOB_STATUS_ERROR]))
        break;
    end
    if (s_value[`APB4_APU__JOB_STATUS_DONE]) wait (playback_done_q);
    measure_q = 1'b0;
    if (!s_value[`APB4_APU__JOB_STATUS_DONE] || playback_xrun_q ||
        (tx_count_q != 12'd1476) || (tx_last_count_q != 6'd8))
      $fatal(1, "P5 8-to-96-kHz expansion mismatch status=%h count=%0d", s_value, tx_count_q);
    for (int word = 708; word < 1476; word++) begin
      if (tx_data_q[word] != 32'd0)
        $fatal(1, "P5 8-to-96-kHz PCM mismatch word=%0d data=%h", word, tx_data_q[word]);
    end
    if (!playback_seen_q || (playback_last_q - playback_first_q > 64'd191750) ||
        (output_command_count_q != 5'd12))
      $fatal(1, "P5 8-to-96-kHz command/prefill mismatch");
    for (int command = 0; command < 12; command++) begin
      if (output_command_bytes_q[command] != 9'd256)
        $fatal(1, "P5 8-to-96-kHz output command %0d mismatch", command);
    end
    $display("APU-P5 PLAYBACK_8000_96000 span=%0d frames=384", playback_last_q - playback_first_q);

    apb_write(`APB4_APU__RING_CONTROL, 32'd1, 1'b0);
    for (int word = 32; word < 64; word++) ring_image[word] = 32'd0;
    ring_image[32] = (32'd1 << `APB4_APU__DESCRIPTOR_CONTROL_OWN) |
        (32'd1 << `APB4_APU__DESCRIPTOR_CONTROL_IOC) | (32'd1 << 8) | 32'd1;
    ring_image[34] = InputBase;
    ring_image[35] = 32'd52;
    ring_image[38] = 32'h0104_bb80;
    ring_image[39] = 32'h0004_bb80;
    ring_image[40] = 32'd1;
    apb_write(`APB4_APU__RING_TAIL, 32'd0, 1'b0);
    apb_write(`APB4_APU__RING_DOORBELL, 32'd1, 1'b0);
    for (int poll = 0; poll < 500000; poll++) begin
      apb_read(`APB4_APU__RING_HEAD, s_value);
      if (s_value == 32'd0) break;
    end
    if (s_value != 32'd0 || ring_image[32][`APB4_APU__DESCRIPTOR_CONTROL_OWN] ||
        !ring_image[33][`APB4_APU__DESCRIPTOR_STATUS_ERROR] ||
        ring_image[47] != 32'h0000_0001)
      $fatal(1, "P5 invalid KWS ring completion mismatch");

    apb_write(`APB4_APU__RING_CONTROL, 32'd0, 1'b0);
    apb_write(`APB4_APU__JOB_CONTROL, 32'h0000_0900, 1'b0);
    apb_write(`APB4_APU__JOB_INPUT_ADDRESS, InputBase, 1'b0);
    apb_write(`APB4_APU__JOB_INPUT_LENGTH, 32'd108, 1'b0);
    apb_write(`APB4_APU__JOB_OUTPUT_ADDRESS, 32'd0, 1'b0);
    apb_write(`APB4_APU__JOB_OUTPUT_CAPACITY, 32'd0, 1'b0);
    apb_write(`APB4_APU__JOB_INPUT_CONFIG, 32'd0, 1'b0);
    apb_write(`APB4_APU__JOB_OUTPUT_CONFIG, 32'h000d_7700, 1'b0);
    apb_write(`APB4_APU__JOB_FLAGS, 32'd1, 1'b0);
    apb_write(`APB4_APU__COMMAND, 32'd1 << `APB4_APU__COMMAND_START_DIRECT, 1'b0);
    wait (!u_dut.s_seq_idle);
    @(negedge clk_i);
    apb4.pprot = 3'd1;
    for (int poll = 0; poll < 500000; poll++) begin
      apb_read(`APB4_APU__STATUS, s_value);
      if (s_value[`APB4_APU__STATUS_IDLE]) break;
    end
    if (!s_value[`APB4_APU__STATUS_IDLE] || !u_dut.s_codec_transport_idle || u_dut.s_dma_busy)
      $fatal(1, "P5 quiesce did not drain to idle");
    apb_read(`APB4_APU__JOB_STATUS, s_value);
    if (!s_value[`APB4_APU__JOB_STATUS_ABORTED] ||
        s_value[`APB4_APU__JOB_STATUS_ERROR_CODE+:6] != `APB4_APU__ERROR_CODE_ABORT)
      $fatal(1, "P5 quiesce terminal result mismatch %h", s_value);
    apb4.pprot = 3'd0;

    apb_write(`APB4_APU__JOB_CONTROL, 32'h0000_0900, 1'b0);
    apb_write(`APB4_APU__COMMAND, 32'd1 << `APB4_APU__COMMAND_START_DIRECT, 1'b0);
    wait (!u_dut.s_seq_idle);
    @(negedge clk_i);
    resource_reset_i = 1'b1;
    @(negedge clk_i);
    resource_reset_i = 1'b0;
    wait (u_dut.idle_o);
    apb_read(`APB4_APU__MC_STATUS, s_value);
    if (!s_value[`APB4_APU__MC_STATUS_VALID]) $fatal(1, "P5 resource reset lost microcode");
    apb_read(`APB4_APU__MC_LOCK, s_value);
    if (!s_value[`APB4_APU__MC_LOCK_LOCKED]) $fatal(1, "P5 resource reset lost lock");
    $display("APU-P5 direct WAV product integration passed");
    $finish;
  end

  initial begin
    repeat (5000000) @(posedge clk_i);
    $fatal(1, "P5 integration timeout");
  end

endmodule
