// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "apu_define.svh"

module apu_p5_corpus_tb;
  localparam logic [31:0] ApuBase = 32'h1001_3000;
  localparam logic [31:0] ImageBase = 32'h3000_0000;
  localparam logic [31:0] InputBase = 32'h4000_0000;
  localparam logic [31:0] OutputBase = 32'h5000_0000;

  logic        clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        resource_reset_i;
  logic [31:0] image            [0:16383];
  logic        read_active_q;
  logic [31:0] read_addr_q;
  logic [7:0] read_len_q, read_beat_q;
  logic [31:0] read_data_q, s_read_data;
  logic write_active_q, write_response_q;
  logic [31:0] write_addr_q;
  logic [7:0] write_len_q, write_beat_q;
  longint unsigned input_next_offset_q;
  longint unsigned output_next_offset_q;
  logic [31:0] s_value;
  logic [31:0] s_job_status, s_job_input_used, s_job_output_bytes;
  logic [31:0] s_job_frames, s_job_source_info, s_job_cycles, s_job_detail;
  logic [31:0] s_error_status, s_error_address, s_error_detail;
  logic [31:0] s_input_bytes, s_input_config, s_output_config, s_output_capacity;
  longint unsigned s_max_cycles, s_elapsed_cycles;
  integer s_input_file, s_output_file;
  string s_image_path, s_input_path, s_output_path;

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

  always #1 clk_i = ~clk_i;

  assign axi4.arready       = !read_active_q;
  assign axi4.rid           = 1'b0;
  assign axi4.rdata         = read_data_q;
  assign axi4.rresp         = 2'd0;
  assign axi4.rlast         = read_beat_q == read_len_q;
  assign axi4.ruser         = 1'b0;
  assign axi4.rvalid        = read_active_q;
  assign axi4.awready       = !write_active_q && !write_response_q;
  assign axi4.wready        = write_active_q;
  assign axi4.bid           = 1'b0;
  assign axi4.bresp         = 2'd0;
  assign axi4.buser         = 1'b0;
  assign axi4.bvalid        = write_response_q;

  assign dma_tx_axis.tdata  = 32'd0;
  assign dma_tx_axis.tkeep  = 4'hf;
  assign dma_tx_axis.tstrb  = 4'hf;
  assign dma_tx_axis.tlast  = 1'b0;
  assign dma_tx_axis.tid    = '0;
  assign dma_tx_axis.tdest  = '0;
  assign dma_tx_axis.tuser  = '0;
  assign dma_tx_axis.tvalid = 1'b0;
  assign dma_rx_axis.tready = 1'b1;
  assign i2s_tx_axis.tready = 1'b1;
  assign i2s_rx_axis.tdata  = 32'd0;
  assign i2s_rx_axis.tkeep  = 4'hf;
  assign i2s_rx_axis.tstrb  = 4'hf;
  assign i2s_rx_axis.tlast  = 1'b0;
  assign i2s_rx_axis.tid    = '0;
  assign i2s_rx_axis.tdest  = '0;
  assign i2s_rx_axis.tuser  = '0;
  assign i2s_rx_axis.tvalid = 1'b0;

  task automatic load_read_data(input logic [31:0] address_i, output logic [31:0] data_o);
    integer s_byte, s_seek_result;
    begin
      data_o = 32'd0;
      if ((address_i >= ImageBase) && (address_i < ImageBase + image[2])) begin
        data_o = image[(address_i-ImageBase)>>2];
      end else if ((address_i >= InputBase) &&
                   (address_i < InputBase + s_input_bytes + 32'd3)) begin
        if ((address_i - InputBase) != input_next_offset_q) begin
          s_seek_result = $fseek(s_input_file, address_i - InputBase, 0);
          if (s_seek_result != 0) $fatal(1, "P5 corpus input seek failed at %h", address_i);
        end
        for (int lane = 0; lane < 4; lane++) begin
          s_byte            = $fgetc(s_input_file);
          data_o[lane*8+:8] = (s_byte < 0) ? 8'd0 : 8'(s_byte);
        end
        input_next_offset_q = address_i - InputBase + 32'd4;
      end else begin
        $fatal(1, "P5 corpus unexpected AXI read %h", address_i);
      end
    end
  endtask

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    integer s_seek_result;
    if (!rst_n_i) begin
      read_active_q    <= 1'b0;
      read_addr_q      <= 32'd0;
      read_len_q       <= 8'd0;
      read_beat_q      <= 8'd0;
      read_data_q      <= 32'd0;
      write_active_q   <= 1'b0;
      write_response_q <= 1'b0;
      write_addr_q     <= 32'd0;
      write_len_q      <= 8'd0;
      write_beat_q     <= 8'd0;
      input_next_offset_q <= 64'd0;
      output_next_offset_q <= 64'd0;
    end else begin
      if (axi4.arvalid && axi4.arready) begin
        load_read_data(axi4.araddr, s_read_data);
        read_active_q <= 1'b1;
        read_addr_q   <= axi4.araddr;
        read_len_q    <= axi4.arlen;
        read_beat_q   <= 8'd0;
        read_data_q   <= s_read_data;
      end
      if (axi4.rvalid && axi4.rready) begin
        if (axi4.rlast) begin
          read_active_q <= 1'b0;
        end else begin
          load_read_data(read_addr_q + 32'd4, s_read_data);
          read_addr_q <= read_addr_q + 32'd4;
          read_beat_q <= read_beat_q + 1'b1;
          read_data_q <= s_read_data;
        end
      end
      if (axi4.awvalid && axi4.awready) begin
        write_active_q <= 1'b1;
        write_addr_q   <= axi4.awaddr;
        write_len_q    <= axi4.awlen;
        write_beat_q   <= 8'd0;
      end
      if (axi4.wvalid && axi4.wready) begin
        if ((write_addr_q < OutputBase) || (write_addr_q >= OutputBase + s_output_capacity)) begin
          $fatal(1, "P5 corpus unexpected AXI write %h", write_addr_q);
        end
        if ((axi4.wstrb == 4'hf) &&
            ((write_addr_q - OutputBase) == output_next_offset_q)) begin
          $fwrite(s_output_file, "%c%c%c%c", axi4.wdata[7:0], axi4.wdata[15:8],
                  axi4.wdata[23:16], axi4.wdata[31:24]);
          output_next_offset_q <= output_next_offset_q + 64'd4;
        end else begin
          for (int lane = 0; lane < 4; lane++) begin
            if (axi4.wstrb[lane]) begin
              s_seek_result = $fseek(s_output_file, write_addr_q - OutputBase + lane, 0);
              if (s_seek_result != 0) $fatal(1, "P5 corpus output seek failed at %h", write_addr_q);
              $fwrite(s_output_file, "%c", axi4.wdata[lane*8+:8]);
              if ((write_addr_q - OutputBase + lane + 1) > output_next_offset_q) begin
                output_next_offset_q <= write_addr_q - OutputBase + lane + 1;
              end
            end
          end
        end
        if (axi4.wlast != (write_beat_q == write_len_q)) begin
          $fatal(1, "P5 corpus AXI WLAST mismatch");
        end
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
      .i2s_tx_underrun_i(1'b0),
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

  task automatic apb_write(input logic [11:0] offset_i, input logic [31:0] value_i);
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
      if (apb4.pslverr) $fatal(1, "P5 corpus APB write failed %h", offset_i);
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
      if (apb4.pslverr) $fatal(1, "P5 corpus APB read failed %h", offset_i);
      value_o = apb4.prdata;
      @(negedge clk_i);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
    end
  endtask

  initial begin
    s_input_bytes     = 32'd0;
    s_input_config    = 32'd0;
    s_output_config   = 32'd0;
    s_output_capacity = 32'd0;
    s_max_cycles      = 64'd0;
    if (!$value$plusargs("IMAGE=%s", s_image_path)) $fatal(1, "IMAGE plusarg missing");
    if (!$value$plusargs("INPUT=%s", s_input_path)) $fatal(1, "INPUT plusarg missing");
    if (!$value$plusargs("OUTPUT=%s", s_output_path)) $fatal(1, "OUTPUT plusarg missing");
    if (!$value$plusargs("INPUT_BYTES=%d", s_input_bytes)) $fatal(1, "INPUT_BYTES missing");
    if (!$value$plusargs("INPUT_CONFIG=%h", s_input_config)) $fatal(1, "INPUT_CONFIG missing");
    if (!$value$plusargs("OUTPUT_CONFIG=%h", s_output_config)) $fatal(1, "OUTPUT_CONFIG missing");
    if (!$value$plusargs("OUTPUT_CAPACITY=%d", s_output_capacity)) begin
      $fatal(1, "OUTPUT_CAPACITY missing");
    end
    if (!$value$plusargs("MAX_CYCLES=%d", s_max_cycles)) $fatal(1, "MAX_CYCLES missing");
    $readmemh(s_image_path, image);
    s_input_file = $fopen(s_input_path, "rb");
    if (s_input_file == 0) $fatal(1, "cannot open corpus input %s", s_input_path);
    s_output_file = $fopen(s_output_path, "wb");
    if (s_output_file == 0) $fatal(1, "cannot open corpus output %s", s_output_path);

    resource_reset_i = 1'b0;
    apb4.paddr       = 32'd0;
    apb4.pprot       = 3'd1;
    apb4.psel        = 1'b0;
    apb4.penable     = 1'b0;
    apb4.pwrite      = 1'b0;
    apb4.pwdata      = 32'd0;
    apb4.pstrb       = 4'd0;
    repeat (4) @(posedge clk_i);
    rst_n_i = 1'b1;
    repeat (2) @(posedge clk_i);

    apb_write(`APB4_APU__READ_BASE, ImageBase);
    apb_write(`APB4_APU__READ_LIMIT, InputBase + s_input_bytes - 1'b1);
    apb_write(`APB4_APU__WRITE_BASE, OutputBase);
    apb_write(`APB4_APU__WRITE_LIMIT, OutputBase + s_output_capacity - 1'b1);
    apb_write(`APB4_APU__MC_IMAGE_ADDRESS, ImageBase);
    apb_write(`APB4_APU__MC_IMAGE_SIZE, image[2]);
    apb_write(`APB4_APU__MC_EXPECTED_CRC, image[11]);
    apb_write(`APB4_APU__COMMAND, 32'd1 << `APB4_APU__COMMAND_MICROCODE_LOAD);
    for (int poll = 0; poll < 2000000; poll++) begin
      @(posedge clk_i);
      if (u_dut.s_mc_status[`APB4_APU__MC_STATUS_VALID]) break;
      if (!u_dut.s_mc_status[`APB4_APU__MC_STATUS_BUSY]) $fatal(1, "P5 corpus load failed");
    end
    if (!u_dut.s_mc_status[`APB4_APU__MC_STATUS_VALID]) begin
      $fatal(1, "P5 corpus load timeout state=%0d entry=%0d pc=%0d",
             u_dut.u_microcode_loader.s_state_q, u_dut.u_microcode_loader.s_scan_entry_q,
             u_dut.u_microcode_loader.s_scan_pc_q);
    end

    apb4.pprot = 3'd0;
    apb_write(`APB4_APU__JOB_CONTROL, 32'd2 << 4);
    apb_write(`APB4_APU__JOB_INPUT_ADDRESS, InputBase);
    apb_write(`APB4_APU__JOB_INPUT_LENGTH, s_input_bytes);
    apb_write(`APB4_APU__JOB_OUTPUT_ADDRESS, OutputBase);
    apb_write(`APB4_APU__JOB_OUTPUT_CAPACITY, s_output_capacity);
    apb_write(`APB4_APU__JOB_INPUT_CONFIG, s_input_config);
    apb_write(`APB4_APU__JOB_OUTPUT_CONFIG, s_output_config);
    apb_write(`APB4_APU__JOB_FLAGS, 32'd1);
    apb_write(`APB4_APU__COMMAND, 32'd1 << `APB4_APU__COMMAND_START_DIRECT);

    s_elapsed_cycles = 0;
    while (!(u_dut.s_codec_job_status[`APB4_APU__JOB_STATUS_DONE] ||
             u_dut.s_codec_job_status[`APB4_APU__JOB_STATUS_ERROR] ||
             u_dut.s_codec_job_status[`APB4_APU__JOB_STATUS_ABORTED]) &&
           (s_elapsed_cycles < s_max_cycles)) begin
      @(posedge clk_i);
      s_elapsed_cycles++;
    end
    if (s_elapsed_cycles >= s_max_cycles) $fatal(1, "P5 corpus job timeout");

    apb_read(`APB4_APU__JOB_STATUS, s_job_status);
    apb_read(`APB4_APU__JOB_INPUT_USED, s_job_input_used);
    apb_read(`APB4_APU__JOB_OUTPUT_BYTES, s_job_output_bytes);
    apb_read(`APB4_APU__JOB_FRAMES, s_job_frames);
    apb_read(`APB4_APU__JOB_SOURCE_INFO, s_job_source_info);
    apb_read(`APB4_APU__JOB_CYCLES, s_job_cycles);
    apb_read(`APB4_APU__JOB_DETAIL, s_job_detail);
    apb_read(`APB4_APU__ERROR_STATUS, s_error_status);
    apb_read(`APB4_APU__ERROR_ADDRESS, s_error_address);
    apb_read(`APB4_APU__ERROR_DETAIL, s_error_detail);
    $fclose(s_input_file);
    $fclose(s_output_file);
    $display(
        "APU_P5_CORPUS_RESULT status=%08x input_used=%08x output_bytes=%08x frames=%08x source_info=%08x cycles=%08x detail=%08x error_status=%08x error_address=%08x error_detail=%08x elapsed=%0d",
        s_job_status, s_job_input_used, s_job_output_bytes, s_job_frames, s_job_source_info,
        s_job_cycles, s_job_detail, s_error_status, s_error_address, s_error_detail,
        s_elapsed_cycles);
    $finish;
  end

  initial begin : wallclock_timeout
    longint unsigned wallclock_ns;
    wallclock_ns = 64'd4_000_000_000;
    void'($value$plusargs("WALLCLOCK_NS=%d", wallclock_ns));
    if (wallclock_ns != 0) begin
      #(wallclock_ns);
      $fatal(1, "P5 corpus wall clock timeout");
    end
  end
endmodule
