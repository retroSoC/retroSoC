`timescale 1ns / 1ps

`include "apu_define.svh"

module apu_reg_tb;
  localparam logic [31:0] ApuBase = 32'h1001_3000;
  localparam int unsigned RegisterCount = 96;
  localparam logic [1:0] AccessRo = 2'd0;
  localparam logic [1:0] AccessWo = 2'd1;
  localparam logic [1:0] AccessRw = 2'd2;

  logic               clk_i = 1'b0;
  logic               rst_n_i = 1'b0;
  logic        [ 1:0] owner_i = 2'd0;
  logic               owner_lock_i = 1'b0;
  logic               quiesce_i = 1'b0;
  logic               resource_reset_i = 1'b0;
  logic               idle_o;
  logic               irq_o;
  logic        [31:0] s_value;
  logic        [11:0] s_reg_offset            [RegisterCount];
  logic        [ 1:0] s_reg_access            [RegisterCount];
  logic        [31:0] s_reg_reset             [RegisterCount];
  logic               s_reg_full_strobe       [RegisterCount];
  int unsigned        s_reg_count;
  string              s_phase;

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
      clk_i,
      rst_n_i
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) dma_tx_axis (
      clk_i,
      rst_n_i
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) dma_rx_axis (
      clk_i,
      rst_n_i
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) i2s_tx_axis (
      clk_i,
      rst_n_i
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) i2s_rx_axis (
      clk_i,
      rst_n_i
  );

  assign axi4.awready       = 1'b0;
  assign axi4.wready        = 1'b0;
  assign axi4.bid           = '0;
  assign axi4.bresp         = '0;
  assign axi4.buser         = '0;
  assign axi4.bvalid        = 1'b0;
  assign axi4.arready       = 1'b0;
  assign axi4.rid           = '0;
  assign axi4.rdata         = '0;
  assign axi4.rresp         = '0;
  assign axi4.rlast         = 1'b0;
  assign axi4.ruser         = '0;
  assign axi4.rvalid        = 1'b0;
  assign dma_tx_axis.tdata  = '0;
  assign dma_tx_axis.tkeep  = '1;
  assign dma_tx_axis.tstrb  = '1;
  assign dma_tx_axis.tlast  = 1'b0;
  assign dma_tx_axis.tid    = '0;
  assign dma_tx_axis.tdest  = '0;
  assign dma_tx_axis.tuser  = '0;
  assign dma_tx_axis.tvalid = 1'b0;
  assign dma_rx_axis.tready = 1'b1;
  assign i2s_tx_axis.tready = 1'b1;
  assign i2s_rx_axis.tdata  = '0;
  assign i2s_rx_axis.tkeep  = '1;
  assign i2s_rx_axis.tstrb  = '1;
  assign i2s_rx_axis.tlast  = 1'b0;
  assign i2s_rx_axis.tid    = '0;
  assign i2s_rx_axis.tdest  = '0;
  assign i2s_rx_axis.tuser  = '0;
  assign i2s_rx_axis.tvalid = 1'b0;

  always #5 clk_i = ~clk_i;

  apb4_apu u_dut (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      .owner_i          (owner_i),
      .owner_lock_i     (owner_lock_i),
      .quiesce_i        (quiesce_i),
      .resource_reset_i (resource_reset_i),
      .bridge_epoch_i   (8'd0),
      .i2s_tx_underrun_i(1'b0),
      .i2s_rx_overrun_i (1'b0),
      .apb4             (apb4),
      .axi4             (axi4),
      .dma_tx_axis      (dma_tx_axis),
      .dma_rx_axis      (dma_rx_axis),
      .i2s_tx_axis      (i2s_tx_axis),
      .i2s_rx_axis      (i2s_rx_axis),
      .idle_o           (idle_o),
      .irq_o            (irq_o)
  );

  function automatic logic [31:0] legal_write_value(input logic [11:0] offset_i);
    case (offset_i)
      `APB4_APU__IRQ_STATE:              legal_write_value = 32'h0000_07ff;
      `APB4_APU__IRQ_ENABLE:             legal_write_value = 32'h0000_0005;
      `APB4_APU__ERROR_STATUS:           legal_write_value = 32'h0000_0001;
      `APB4_APU__SEQUENCER_TIMEOUT:      legal_write_value = 32'h1234_5678;
      `APB4_APU__STREAM_ROUTE:           legal_write_value = 32'd0;
      `APB4_APU__STREAM_WATERMARK:       legal_write_value = 32'h0000_2020;
      `APB4_APU__READ_BASE:              legal_write_value = 32'h3000_0000;
      `APB4_APU__READ_LIMIT:             legal_write_value = 32'h3000_ffff;
      `APB4_APU__WRITE_BASE:             legal_write_value = 32'h3001_0000;
      `APB4_APU__WRITE_LIMIT:            legal_write_value = 32'h3001_ffff;
      `APB4_APU__DMA_TIMEOUT:            legal_write_value = 32'h8765_4321;
      `APB4_APU__MC_IMAGE_ADDRESS:       legal_write_value = 32'h3002_0000;
      `APB4_APU__MC_IMAGE_SIZE:          legal_write_value = 32'h0000_0040;
      `APB4_APU__MC_EXPECTED_CRC:        legal_write_value = 32'ha5a5_5a5a;
      `APB4_APU__JOB_CONTROL:            legal_write_value = 32'h0000_0121;
      `APB4_APU__JOB_INPUT_ADDRESS:      legal_write_value = 32'h3003_0000;
      `APB4_APU__JOB_INPUT_LENGTH:       legal_write_value = 32'h0000_0100;
      `APB4_APU__JOB_OUTPUT_ADDRESS:     legal_write_value = 32'h3003_1000;
      `APB4_APU__JOB_OUTPUT_CAPACITY:    legal_write_value = 32'h0000_1000;
      `APB4_APU__JOB_INPUT_CONFIG:       legal_write_value = 32'h0012_3456;
      `APB4_APU__JOB_OUTPUT_CONFIG:      legal_write_value = 32'h0001_2345;
      `APB4_APU__JOB_FLAGS:              legal_write_value = 32'h0000_0001;
      `APB4_APU__RING_BASE:              legal_write_value = 32'h3004_0000;
      `APB4_APU__RING_SIZE:              legal_write_value = 32'h0000_0008;
      `APB4_APU__RING_TAIL:              legal_write_value = 32'h0000_0003;
      `APB4_APU__RING_CONTROL:           legal_write_value = 32'h0000_0001;
      `APB4_APU__RING_COALESCE:          legal_write_value = 32'h0004_0002;
      `APB4_APU__KWS_MODEL_ADDRESS:      legal_write_value = 32'h3005_0000;
      `APB4_APU__KWS_MODEL_SIZE:         legal_write_value = 32'h0000_0100;
      `APB4_APU__KWS_MODEL_EXPECTED_CRC: legal_write_value = 32'h5a5a_a5a5;
      `APB4_APU__KWS_CONTROL:            legal_write_value = 32'h0000_0004;
      `APB4_APU__KWS_CONFIG:             legal_write_value = 32'h0000_0590;
      `APB4_APU__PERF_CONTROL:           legal_write_value = 32'h0000_0001;
      default:                           legal_write_value = 32'd0;
    endcase
  endfunction

  function automatic logic [31:0] legal_readback_value(input logic [11:0] offset_i);
    case (offset_i)
      `APB4_APU__IRQ_STATE, `APB4_APU__ERROR_STATUS, `APB4_APU__STREAM_ROUTE,
      `APB4_APU__KWS_CONTROL:
      legal_readback_value = 32'd0;
      default: legal_readback_value = legal_write_value(offset_i);
    endcase
  endfunction

  function automatic logic [31:0] reset_or_preserved_value(input logic [11:0] offset_i,
                                                           input logic [31:0] reset_i);
    case (offset_i)
      `APB4_APU__READ_BASE, `APB4_APU__READ_LIMIT, `APB4_APU__WRITE_BASE, `APB4_APU__WRITE_LIMIT:
      reset_or_preserved_value = legal_write_value(offset_i);
      default: reset_or_preserved_value = reset_i;
    endcase
  endfunction

  task automatic add_register(input logic [11:0] offset_i, input logic [1:0] access_i,
                              input logic [31:0] reset_i, input logic full_strobe_i);
    begin
      if (s_reg_count >= RegisterCount) $fatal(1, "APU register table overflow");
      s_reg_offset[s_reg_count]      = offset_i;
      s_reg_access[s_reg_count]      = access_i;
      s_reg_reset[s_reg_count]       = reset_i;
      s_reg_full_strobe[s_reg_count] = full_strobe_i;
      s_reg_count++;
    end
  endtask

  task automatic initialize_register_table;
    begin
      s_reg_count = 0;
      add_register(`APB4_APU__IP_ID, AccessRo, 32'h4150_5530, 1'b0);
      add_register(`APB4_APU__IP_VERSION, AccessRo, 32'h0001_0000, 1'b0);
      add_register(`APB4_APU__CAPABILITY0, AccessRo, 32'h0000_01bd, 1'b0);
      add_register(`APB4_APU__CAPABILITY1, AccessRo, 32'h0182_7010, 1'b0);
      add_register(`APB4_APU__COMMAND, AccessWo, 32'd0, 1'b1);
      add_register(`APB4_APU__STATUS, AccessRo, 32'h0000_0100, 1'b0);
      add_register(`APB4_APU__IRQ_STATE, AccessRw, 32'd0, 1'b0);
      add_register(`APB4_APU__IRQ_ENABLE, AccessRw, 32'd0, 1'b0);
      add_register(`APB4_APU__IRQ_TEST, AccessWo, 32'd0, 1'b1);
      add_register(`APB4_APU__ERROR_STATUS, AccessRw, 32'd0, 1'b0);
      add_register(`APB4_APU__ERROR_ADDRESS, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__ERROR_DETAIL, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__SEQUENCER_TIMEOUT, AccessRw, 32'h0000_ffff, 1'b0);
      add_register(`APB4_APU__STREAM_ROUTE, AccessRw, 32'd0, 1'b0);
      add_register(`APB4_APU__STREAM_STATUS, AccessRo, 32'h0000_0014, 1'b0);
      add_register(`APB4_APU__OWNER_STATUS, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__READ_BASE, AccessRw, 32'hffff_ffff, 1'b1);
      add_register(`APB4_APU__READ_LIMIT, AccessRw, 32'd0, 1'b1);
      add_register(`APB4_APU__WRITE_BASE, AccessRw, 32'hffff_ffff, 1'b1);
      add_register(`APB4_APU__WRITE_LIMIT, AccessRw, 32'd0, 1'b1);
      add_register(`APB4_APU__DMA_TIMEOUT, AccessRw, 32'h0000_ffff, 1'b0);
      add_register(`APB4_APU__ABI_DIGEST, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__SEQUENCER_STATUS, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__SEQUENCER_RETIRED, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__STREAM_WATERMARK, AccessRw, 32'd0, 1'b0);
      add_register(`APB4_APU__MC_IMAGE_ADDRESS, AccessRw, 32'd0, 1'b1);
      add_register(`APB4_APU__MC_IMAGE_SIZE, AccessRw, 32'd0, 1'b1);
      add_register(`APB4_APU__MC_EXPECTED_CRC, AccessRw, 32'd0, 1'b1);
      add_register(`APB4_APU__MC_STATUS, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__MC_ABI, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__MC_BUILD_ID_LO, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__MC_BUILD_ID_HI, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__MC_LOCK, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__MC_ACTUAL_CRC, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__MC_LOAD_COUNT, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__JOB_CONTROL, AccessRw, 32'd0, 1'b0);
      add_register(`APB4_APU__JOB_INPUT_ADDRESS, AccessRw, 32'd0, 1'b1);
      add_register(`APB4_APU__JOB_INPUT_LENGTH, AccessRw, 32'd0, 1'b1);
      add_register(`APB4_APU__JOB_OUTPUT_ADDRESS, AccessRw, 32'd0, 1'b1);
      add_register(`APB4_APU__JOB_OUTPUT_CAPACITY, AccessRw, 32'd0, 1'b1);
      add_register(`APB4_APU__JOB_INPUT_CONFIG, AccessRw, 32'd0, 1'b0);
      add_register(`APB4_APU__JOB_OUTPUT_CONFIG, AccessRw, 32'd0, 1'b0);
      add_register(`APB4_APU__JOB_FLAGS, AccessRw, 32'd0, 1'b0);
      add_register(`APB4_APU__JOB_STATUS, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__JOB_INPUT_USED, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__JOB_OUTPUT_BYTES, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__JOB_FRAMES, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__JOB_SOURCE_INFO, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__JOB_CYCLES, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__JOB_DETAIL, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__RING_BASE, AccessRw, 32'd0, 1'b1);
      add_register(`APB4_APU__RING_SIZE, AccessRw, 32'd0, 1'b1);
      add_register(`APB4_APU__RING_HEAD, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__RING_TAIL, AccessRw, 32'd0, 1'b1);
      add_register(`APB4_APU__RING_CONTROL, AccessRw, 32'd0, 1'b1);
      add_register(`APB4_APU__RING_STATUS, AccessRo, 32'h0000_0004, 1'b0);
      add_register(`APB4_APU__RING_COMPLETED, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__RING_COALESCE, AccessRw, 32'h0001_0001, 1'b1);
      add_register(`APB4_APU__RING_DOORBELL, AccessWo, 32'd0, 1'b1);
      add_register(`APB4_APU__KWS_MODEL_ADDRESS, AccessRw, 32'd0, 1'b1);
      add_register(`APB4_APU__KWS_MODEL_SIZE, AccessRw, 32'd0, 1'b1);
      add_register(`APB4_APU__KWS_MODEL_EXPECTED_CRC, AccessRw, 32'd0, 1'b1);
      add_register(`APB4_APU__KWS_CONTROL, AccessRw, 32'd0, 1'b1);
      add_register(`APB4_APU__KWS_CONFIG, AccessRw, 32'h0000_0380, 1'b0);
      add_register(`APB4_APU__KWS_STATUS, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__KWS_RESULT, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__KWS_TIMESTAMP_LO, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__KWS_TIMESTAMP_HI, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__KWS_FRAME_COUNT, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__KWS_INFERENCE_COUNT, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__KWS_HIT_COUNT, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__KWS_OVERRUN_COUNT, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__KWS_MODEL_STATUS, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__KWS_MODEL_ACTUAL_CRC, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__PERF_CONTROL, AccessRw, 32'd0, 1'b0);
      add_register(`APB4_APU__PERF_STATUS, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__PERF_ACTIVE_CYCLES_LO, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__PERF_ACTIVE_CYCLES_HI, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__PERF_INPUT_BYTES_LO, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__PERF_INPUT_BYTES_HI, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__PERF_OUTPUT_BYTES_LO, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__PERF_OUTPUT_BYTES_HI, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__PERF_DECODED_FRAMES_LO, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__PERF_DECODED_FRAMES_HI, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__PERF_DMA_READ_STALLS_LO, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__PERF_DMA_READ_STALLS_HI, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__PERF_DMA_WRITE_STALLS_LO, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__PERF_DMA_WRITE_STALLS_HI, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__PERF_STREAM_STALLS_LO, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__PERF_STREAM_STALLS_HI, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__PERF_SEQUENCER_INSTR_LO, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__PERF_SEQUENCER_INSTR_HI, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__PERF_KWS_CYCLES_LO, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__PERF_KWS_CYCLES_HI, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__PERF_FAULTS_LO, AccessRo, 32'd0, 1'b0);
      add_register(`APB4_APU__PERF_FAULTS_HI, AccessRo, 32'd0, 1'b0);
      if (s_reg_count != RegisterCount) begin
        $fatal(1, "APU register table has %0d entries, expected %0d", s_reg_count, RegisterCount);
      end
    end
  endtask

  task automatic drive_apb_idle;
    begin
      apb4.paddr   = 32'd0;
      apb4.pprot   = 3'd0;
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
      apb4.pwrite  = 1'b0;
      apb4.pwdata  = 32'd0;
      apb4.pstrb   = 4'd0;
    end
  endtask

  task automatic hard_reset;
    begin
      @(negedge clk_i);
      drive_apb_idle();
      owner_i          = 2'd0;
      owner_lock_i     = 1'b0;
      quiesce_i        = 1'b0;
      resource_reset_i = 1'b0;
      rst_n_i          = 1'b0;
      repeat (2) @(posedge clk_i);
      @(negedge clk_i);
      rst_n_i = 1'b1;
    end
  endtask

  task automatic apb_write(input logic [11:0] offset_i, input logic [31:0] data_i,
                           input logic [3:0] strobe_i, input logic expected_err_i);
    int unsigned s_wait_cycles;
    logic        s_response_err;
    begin
      @(negedge clk_i);
      apb4.paddr   = ApuBase + offset_i;
      apb4.pwdata  = data_i;
      apb4.pstrb   = strobe_i;
      apb4.pwrite  = 1'b1;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      #1;
      if (apb4.pready) $fatal(1, "APU PREADY asserted during write setup at %h", offset_i);
      @(negedge clk_i);
      apb4.penable  = 1'b1;
      s_wait_cycles = 0;
      #1;
      while (!apb4.pready) begin
        s_wait_cycles++;
        if (s_wait_cycles > 4) $fatal(1, "APU write wait timeout at %h", offset_i);
        @(negedge clk_i);
        #1;
      end
      if (s_wait_cycles != 1) begin
        $fatal(1, "APU write wait count mismatch at %h: %0d", offset_i, s_wait_cycles);
      end
      if (apb4.pslverr != expected_err_i) begin
        $fatal(1, "APU write response mismatch at %h in %s", offset_i, s_phase);
      end
      s_response_err = apb4.pslverr;
      #2;
      if (!apb4.pready || (apb4.pslverr != s_response_err)) begin
        $fatal(1, "APU write response was not retained through completion at %h", offset_i);
      end
      @(negedge clk_i);
      drive_apb_idle();
    end
  endtask

  task automatic apb_read(input logic [11:0] offset_i, output logic [31:0] data_o,
                          input logic expected_err_i);
    int unsigned        s_wait_cycles;
    logic        [31:0] s_response_data;
    logic               s_response_err;
    begin
      @(negedge clk_i);
      apb4.paddr   = ApuBase + offset_i;
      apb4.pstrb   = 4'd0;
      apb4.pwrite  = 1'b0;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      #1;
      if (apb4.pready) $fatal(1, "APU PREADY asserted during read setup at %h", offset_i);
      @(negedge clk_i);
      apb4.penable  = 1'b1;
      s_wait_cycles = 0;
      #1;
      while (!apb4.pready) begin
        s_wait_cycles++;
        if (s_wait_cycles > 4) $fatal(1, "APU read wait timeout at %h", offset_i);
        @(negedge clk_i);
        #1;
      end
      if (s_wait_cycles != 1) begin
        $fatal(1, "APU read wait count mismatch at %h: %0d", offset_i, s_wait_cycles);
      end
      if (apb4.pslverr != expected_err_i) begin
        $fatal(1, "APU read response mismatch at %h during %s", offset_i, s_phase);
      end
      s_response_data = apb4.prdata;
      s_response_err  = apb4.pslverr;
      #2;
      if (!apb4.pready || (apb4.prdata != s_response_data) ||
          (apb4.pslverr != s_response_err)) begin
        $fatal(1, "APU read response was not retained through completion at %h", offset_i);
      end
      data_o = s_response_data;
      @(negedge clk_i);
      drive_apb_idle();
    end
  endtask

  task automatic expect_read(input logic [11:0] offset_i, input logic [31:0] expected_i);
    begin
      apb_read(offset_i, s_value, 1'b0);
      if (s_value != expected_i) begin
        $fatal(1, "APU read mismatch at %h: got %h expected %h", offset_i, s_value, expected_i);
      end
    end
  endtask

  task automatic program_rw_registers;
    begin
      for (int unsigned register_index = 0; register_index < RegisterCount; register_index++) begin
        if (s_reg_access[register_index] == AccessRw) begin
          apb_write(s_reg_offset[register_index], legal_write_value(s_reg_offset[register_index]),
                    4'hf, 1'b0);
        end
      end
    end
  endtask

  task automatic check_reset_state(input logic preserve_acl_i);
    logic [31:0] s_expected;
    begin
      for (int unsigned register_index = 0; register_index < RegisterCount; register_index++) begin
        if (s_reg_access[register_index] != AccessWo) begin
          s_expected = preserve_acl_i ?
              reset_or_preserved_value(s_reg_offset[register_index], s_reg_reset[register_index]) :
              s_reg_reset[register_index];
          expect_read(s_reg_offset[register_index], s_expected);
        end
      end
    end
  endtask

  task automatic check_rejected_write(input logic [11:0] offset_i,
                                      input logic [31:0] rejected_value_i,
                                      input logic [5:0] error_code_i);
    logic [31:0] s_before;
    begin
      hard_reset();
      apb_write(`APB4_APU__SEQUENCER_TIMEOUT, 32'h1234_5678, 4'hf, 1'b0);
      if ((offset_i != `APB4_APU__COMMAND) && (offset_i != `APB4_APU__IRQ_TEST) &&
          (offset_i != `APB4_APU__RING_DOORBELL)) begin
        apb_read(offset_i, s_before, 1'b0);
      end else begin
        s_before = 32'd0;
      end
      apb_write(offset_i, rejected_value_i, 4'hf, 1'b1);
      expect_read(`APB4_APU__SEQUENCER_TIMEOUT, 32'h1234_5678);
      expect_read(`APB4_APU__ERROR_STATUS, 32'd1 | (32'(error_code_i) << 1));
      expect_read(`APB4_APU__ERROR_ADDRESS, ApuBase + offset_i);
      if ((offset_i != `APB4_APU__COMMAND) && (offset_i != `APB4_APU__IRQ_TEST) &&
          (offset_i != `APB4_APU__RING_DOORBELL) && (offset_i != `APB4_APU__IRQ_STATE) &&
          (offset_i != `APB4_APU__ERROR_STATUS) && (offset_i != `APB4_APU__ERROR_ADDRESS) &&
          (offset_i != `APB4_APU__ERROR_DETAIL)) begin
        expect_read(offset_i, s_before);
      end
    end
  endtask

  task automatic seed_performance_state;
    begin
      hard_reset();
      apb_write(`APB4_APU__PERF_CONTROL, 32'h0000_0001, 4'hf, 1'b0);
      force u_dut.s_dma_busy = 1'b1;
      repeat (3) @(posedge clk_i);
      release u_dut.s_dma_busy;
      apb_write(`APB4_APU__PERF_CONTROL, 32'h0000_0005, 4'hf, 1'b0);
      if ((u_dut.s_active_cycles_q == 64'd0) ||
          (u_dut.u_apu_reg.s_perf_snapshot_q[0] == 64'd0)) begin
        $fatal(1, "performance reset-timing state was not seeded");
      end
    end
  endtask

  initial begin
    initialize_register_table();
    s_phase = "initial reset matrix";
    drive_apb_idle();
    hard_reset();
    if (!idle_o || irq_o) $fatal(1, "APU reset lifecycle outputs mismatch");

    s_phase = "access matrix";
    for (int unsigned register_index = 0; register_index < RegisterCount; register_index++) begin
      hard_reset();
      if (s_reg_access[register_index] == AccessWo) begin
        apb_read(s_reg_offset[register_index], s_value, 1'b1);
      end else begin
        expect_read(s_reg_offset[register_index], s_reg_reset[register_index]);
      end
    end

    for (int unsigned register_index = 0; register_index < RegisterCount; register_index++) begin
      hard_reset();
      case (s_reg_access[register_index])
        AccessRo: begin
          apb_write(`APB4_APU__SEQUENCER_TIMEOUT, 32'h1234_5678, 4'hf, 1'b0);
          apb_write(s_reg_offset[register_index], 32'd0, 4'hf, 1'b1);
          expect_read(`APB4_APU__SEQUENCER_TIMEOUT, 32'h1234_5678);
          if ((s_reg_offset[register_index] != `APB4_APU__ERROR_ADDRESS) &&
              (s_reg_offset[register_index] != `APB4_APU__ERROR_DETAIL)) begin
            expect_read(s_reg_offset[register_index], s_reg_reset[register_index]);
          end
        end
        AccessWo: begin
          apb_read(s_reg_offset[register_index], s_value, 1'b1);
          hard_reset();
          if (s_reg_offset[register_index] == `APB4_APU__COMMAND) begin
            apb_write(s_reg_offset[register_index], 32'h0000_0004, 4'hf, 1'b0);
          end else if (s_reg_offset[register_index] == `APB4_APU__IRQ_TEST) begin
            apb_write(s_reg_offset[register_index], 32'd0, 4'hf, 1'b0);
          end else begin
            apb_write(s_reg_offset[register_index], 32'h0000_0001, 4'hf, 1'b1);
          end
        end
        AccessRw: begin
          apb_write(s_reg_offset[register_index], legal_write_value(s_reg_offset[register_index]),
                    4'hf, 1'b0);
          expect_read(s_reg_offset[register_index], legal_readback_value(
                      s_reg_offset[register_index]));
        end
        default: $fatal(1, "APU register table has invalid access class");
      endcase
    end

    s_phase = "valid byte strobes";
    hard_reset();
    apb_write(`APB4_APU__SEQUENCER_TIMEOUT, 32'h0000_00aa, 4'h1, 1'b0);
    expect_read(`APB4_APU__SEQUENCER_TIMEOUT, 32'h0000_ffaa);
    apb_write(`APB4_APU__SEQUENCER_TIMEOUT, 32'h0000_bb00, 4'h2, 1'b0);
    expect_read(`APB4_APU__SEQUENCER_TIMEOUT, 32'h0000_bbaa);
    apb_write(`APB4_APU__SEQUENCER_TIMEOUT, 32'h00cc_0000, 4'h4, 1'b0);
    expect_read(`APB4_APU__SEQUENCER_TIMEOUT, 32'h00cc_bbaa);
    apb_write(`APB4_APU__SEQUENCER_TIMEOUT, 32'hdd00_0000, 4'h8, 1'b0);
    expect_read(`APB4_APU__SEQUENCER_TIMEOUT, 32'hddcc_bbaa);

    s_phase = "invalid full strobes";
    for (int unsigned register_index = 0; register_index < RegisterCount; register_index++) begin
      if (s_reg_full_strobe[register_index]) begin
        hard_reset();
        apb_write(`APB4_APU__SEQUENCER_TIMEOUT, 32'h1234_5678, 4'hf, 1'b0);
        apb_write(s_reg_offset[register_index], legal_write_value(s_reg_offset[register_index]),
                  4'h7, 1'b1);
        expect_read(`APB4_APU__SEQUENCER_TIMEOUT, 32'h1234_5678);
        if (s_reg_access[register_index] == AccessRw) begin
          expect_read(s_reg_offset[register_index], s_reg_reset[register_index]);
        end
      end
    end

    s_phase = "rejected values";
    check_rejected_write(`APB4_APU__COMMAND, 32'h0000_0080, `APB4_APU__ERROR_CODE_INVALID_CONFIG);
    check_rejected_write(`APB4_APU__COMMAND, 32'h0000_0002, `APB4_APU__ERROR_CODE_INVALID_CONFIG);
    check_rejected_write(`APB4_APU__COMMAND, 32'd1 << `APB4_APU__COMMAND_START_DIRECT,
                         `APB4_APU__ERROR_CODE_INVALID_CONFIG);
    check_rejected_write(`APB4_APU__COMMAND, 32'd1 << `APB4_APU__COMMAND_RING_KICK,
                         `APB4_APU__ERROR_CODE_INVALID_CONFIG);
    check_rejected_write(`APB4_APU__COMMAND, 32'd1 << `APB4_APU__COMMAND_MODEL_LOAD,
                         `APB4_APU__ERROR_CODE_UNSUPPORTED);
    check_rejected_write(`APB4_APU__COMMAND, 32'h0000_0010, `APB4_APU__ERROR_CODE_INVALID_CONFIG);
    check_rejected_write(`APB4_APU__IRQ_STATE, 32'h0000_0800, `APB4_APU__ERROR_CODE_INVALID_CONFIG);
    check_rejected_write(`APB4_APU__IRQ_ENABLE, 32'h0000_0800,
                         `APB4_APU__ERROR_CODE_INVALID_CONFIG);
    check_rejected_write(`APB4_APU__IRQ_TEST, 32'h0000_0800, `APB4_APU__ERROR_CODE_INVALID_CONFIG);
    check_rejected_write(`APB4_APU__ERROR_STATUS, 32'h0000_0002,
                         `APB4_APU__ERROR_CODE_INVALID_CONFIG);
    check_rejected_write(`APB4_APU__SEQUENCER_TIMEOUT, 32'd0, `APB4_APU__ERROR_CODE_INVALID_CONFIG);
    hard_reset();
    apb_write(`APB4_APU__STREAM_ROUTE, 32'h0000_0001, 4'hf, 1'b0);
    expect_read(`APB4_APU__STREAM_ROUTE, 32'h0000_0001);
    check_rejected_write(`APB4_APU__STREAM_ROUTE, 32'h0000_0004, `APB4_APU__ERROR_CODE_UNSUPPORTED);
    check_rejected_write(`APB4_APU__STREAM_WATERMARK, 32'h0000_0041,
                         `APB4_APU__ERROR_CODE_INVALID_CONFIG);
    check_rejected_write(`APB4_APU__STREAM_WATERMARK, 32'h0001_0000,
                         `APB4_APU__ERROR_CODE_INVALID_CONFIG);
    check_rejected_write(`APB4_APU__DMA_TIMEOUT, 32'd0, `APB4_APU__ERROR_CODE_INVALID_CONFIG);
    check_rejected_write(`APB4_APU__MC_IMAGE_ADDRESS, 32'h3002_0001,
                         `APB4_APU__ERROR_CODE_INVALID_CONFIG);
    check_rejected_write(`APB4_APU__MC_IMAGE_SIZE, 32'd0, `APB4_APU__ERROR_CODE_INVALID_CONFIG);
    check_rejected_write(`APB4_APU__JOB_CONTROL, 32'h8000_0000,
                         `APB4_APU__ERROR_CODE_INVALID_CONFIG);
    check_rejected_write(`APB4_APU__JOB_INPUT_CONFIG, 32'h8000_0000,
                         `APB4_APU__ERROR_CODE_INVALID_CONFIG);
    check_rejected_write(`APB4_APU__JOB_OUTPUT_CONFIG, 32'h8000_0000,
                         `APB4_APU__ERROR_CODE_INVALID_CONFIG);
    check_rejected_write(`APB4_APU__JOB_FLAGS, 32'h0000_0002, `APB4_APU__ERROR_CODE_INVALID_CONFIG);
    check_rejected_write(`APB4_APU__RING_BASE, 32'h3004_0001, `APB4_APU__ERROR_CODE_INVALID_CONFIG);
    check_rejected_write(`APB4_APU__RING_SIZE, 32'h0000_0003, `APB4_APU__ERROR_CODE_INVALID_CONFIG);
    check_rejected_write(`APB4_APU__RING_TAIL, 32'h0000_0100, `APB4_APU__ERROR_CODE_INVALID_CONFIG);
    check_rejected_write(`APB4_APU__RING_CONTROL, 32'h0000_0004,
                         `APB4_APU__ERROR_CODE_INVALID_CONFIG);
    check_rejected_write(`APB4_APU__RING_COALESCE, 32'd0, `APB4_APU__ERROR_CODE_INVALID_CONFIG);
    check_rejected_write(`APB4_APU__RING_DOORBELL, 32'h0000_0001,
                         `APB4_APU__ERROR_CODE_INVALID_CONFIG);
    check_rejected_write(`APB4_APU__KWS_MODEL_ADDRESS, 32'h3005_0001,
                         `APB4_APU__ERROR_CODE_INVALID_CONFIG);
    check_rejected_write(`APB4_APU__KWS_MODEL_SIZE, 32'd0, `APB4_APU__ERROR_CODE_INVALID_CONFIG);
    check_rejected_write(`APB4_APU__KWS_CONTROL, 32'h0000_0001, `APB4_APU__ERROR_CODE_UNSUPPORTED);
    check_rejected_write(`APB4_APU__KWS_CONTROL, 32'h0000_0002, `APB4_APU__ERROR_CODE_UNSUPPORTED);
    check_rejected_write(`APB4_APU__KWS_CONTROL, 32'h0000_0008,
                         `APB4_APU__ERROR_CODE_INVALID_CONFIG);
    check_rejected_write(`APB4_APU__KWS_CONFIG, 32'h0000_0080,
                         `APB4_APU__ERROR_CODE_INVALID_CONFIG);
    check_rejected_write(`APB4_APU__PERF_CONTROL, 32'h0000_0008,
                         `APB4_APU__ERROR_CODE_INVALID_CONFIG);

    s_phase = "set over clear";
    hard_reset();
    apb_write(`APB4_APU__IRQ_TEST, 32'h0000_0001, 4'hf, 1'b0);
    force u_dut.u_apu_reg.s_irq_set = 11'h001;
    apb_write(`APB4_APU__IRQ_STATE, 32'h0000_0001, 4'h1, 1'b0);
    release u_dut.u_apu_reg.s_irq_set;
    expect_read(`APB4_APU__IRQ_STATE, 32'h0000_0001);
    apb_write(`APB4_APU__IRQ_STATE, 32'h0000_0001, 4'h1, 1'b0);
    expect_read(`APB4_APU__IRQ_STATE, 32'd0);

    s_phase = "soft reset";
    hard_reset();
    program_rw_registers();
    apb_write(`APB4_APU__COMMAND, 32'h0000_0004, 4'hf, 1'b0);
    check_reset_state(1'b1);

    s_phase = "resource reset";
    hard_reset();
    program_rw_registers();
    force u_dut.s_dma_busy = 1'b1;
    @(negedge clk_i);
    resource_reset_i = 1'b1;
    repeat (3) @(posedge clk_i);
    if (u_dut.s_resource_reset_apply_q || (u_dut.u_apu_reg.s_timeout_q[0] != 32'h1234_5678)) begin
      $fatal(1, "resource reset applied before transport drain");
    end
    force u_dut.s_dma_busy = 1'b0;
    wait (u_dut.s_resource_reset_apply_q);
    release u_dut.s_dma_busy;
    @(posedge clk_i);
    @(negedge clk_i);
    resource_reset_i = 1'b0;
    check_reset_state(1'b1);

    s_phase = "reset timing";
    seed_performance_state();
    @(negedge clk_i);
    force u_dut.u_apu_reg.s_soft_reset = 1'b1;
    #1;
    if ((u_dut.s_active_cycles_q == 64'd0) || (u_dut.u_apu_reg.s_perf_snapshot_q[0] == 64'd0)) begin
      $fatal(1, "soft reset acted asynchronously");
    end
    @(posedge clk_i);
    #1;
    if ((u_dut.s_active_cycles_q != 64'd0) || (u_dut.u_apu_reg.s_perf_snapshot_q != '0)) begin
      $fatal(1, "soft reset did not clear performance state on PCLK");
    end
    release u_dut.u_apu_reg.s_soft_reset;

    seed_performance_state();
    @(negedge clk_i);
    force u_dut.s_resource_reset_apply_q = 1'b1;
    #1;
    if ((u_dut.s_active_cycles_q == 64'd0) || (u_dut.u_apu_reg.s_perf_snapshot_q[0] == 64'd0)) begin
      $fatal(1, "resource reset apply acted asynchronously");
    end
    @(posedge clk_i);
    #1;
    if ((u_dut.s_active_cycles_q != 64'd0) || (u_dut.u_apu_reg.s_perf_snapshot_q != '0)) begin
      $fatal(1, "resource reset apply did not clear performance state on PCLK");
    end
    release u_dut.s_resource_reset_apply_q;

    seed_performance_state();
    @(negedge clk_i);
    force u_dut.u_apu_reg.s_cnt_clear = 1'b1;
    #1;
    if ((u_dut.s_active_cycles_q == 64'd0) || (u_dut.u_apu_reg.s_perf_snapshot_q[0] == 64'd0)) begin
      $fatal(1, "counter clear acted asynchronously");
    end
    @(posedge clk_i);
    #1;
    if ((u_dut.s_active_cycles_q != 64'd0) || (u_dut.u_apu_reg.s_perf_snapshot_q != '0)) begin
      $fatal(1, "counter clear did not clear performance state on PCLK");
    end
    release u_dut.u_apu_reg.s_cnt_clear;

    seed_performance_state();
    @(negedge clk_i);
    rst_n_i = 1'b0;
    #1;
    if ((u_dut.s_active_cycles_q != 64'd0) || (u_dut.u_apu_reg.s_perf_snapshot_q != '0)) begin
      $fatal(1, "hard reset did not clear performance state asynchronously");
    end
    repeat (2) @(posedge clk_i);
    @(negedge clk_i);
    rst_n_i = 1'b1;

    s_phase = "performance enable";
    hard_reset();
    force u_dut.s_dma_busy = 1'b1;
    repeat (5) @(posedge clk_i);
    if (u_dut.s_active_cycles_q != 64'd0) begin
      $fatal(1, "disabled performance counter advanced");
    end
    force u_dut.s_dma_busy = 1'b0;
    release u_dut.s_dma_busy;
    hard_reset();
    apb_write(`APB4_APU__PERF_CONTROL, 32'h0000_0001, 4'hf, 1'b0);
    force u_dut.s_dma_busy = 1'b1;
    repeat (5) @(posedge clk_i);
    if (u_dut.s_active_cycles_q == 64'd0) begin
      $fatal(1, "enabled performance counter did not advance");
    end
    force u_dut.s_dma_busy = 1'b0;
    release u_dut.s_dma_busy;

    hard_reset();
    owner_i      = 2'd1;
    owner_lock_i = 1'b1;
    quiesce_i    = 1'b1;
    expect_read(`APB4_APU__OWNER_STATUS, 32'h0000_0301);
    apb_read(12'h064, s_value, 1'b1);
    apb_read(12'h001, s_value, 1'b1);

    s_phase = "command state predicates";
    hard_reset();
    force u_dut.u_apu_reg.core_busy_i = 1'b1;
    force u_dut.u_apu_reg.core_idle_i = 1'b0;
    apb_write(`APB4_APU__COMMAND, 32'h0000_0002, 4'hf, 1'b0);
    apb_write(`APB4_APU__COMMAND, 32'h0000_0040, 4'hf, 1'b1);
    expect_read(`APB4_APU__ERROR_STATUS, 32'd1 | (32'(`APB4_APU__ERROR_CODE_INVALID_CONFIG) << 1));

    $display("APU-P1 complete APB register matrix passed");
    $finish;
  end

  initial begin
    repeat (20000) @(posedge clk_i);
    $fatal(1, "APU-P1 APB register matrix timed out in %s", s_phase);
  end
endmodule
