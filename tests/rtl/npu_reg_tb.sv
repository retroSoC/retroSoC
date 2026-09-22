`timescale 1ns / 1ps

// NPU-P2 APB register matrix test: every documented offset, access classes,
// alignment/strobe enforcement, CONTROL exact-one-bit semantics with START
// always rejected, IRQ test/W1C/enable gating with set-wins-clear, live
// OWNER_STATUS, snapshot round trip with zero bank and no tear, recovery
// generation counting, and the P2 truthfulness invariants (READY=0,
// RESULT_VALID never set).
`include "npu_define.svh"

module npu_reg_tb;
  localparam logic [31:0] NpuBase = 32'h1001_b000;
  localparam int unsigned RegisterCount = 52;
  localparam logic [1:0] AccessRo = 2'd0;
  localparam logic [1:0] AccessWo = 2'd1;
  localparam logic [1:0] AccessRw = 2'd2;

  logic               clk_i = 1'b0;
  logic               clk_hp_i = 1'b0;
  logic               rst_n_i = 1'b0;
  logic               rst_hp_n_i = 1'b0;
  logic        [ 1:0] resource_owner_i = 2'd0;
  logic               resource_owner_lock_i = 1'b0;
  logic               resource_quiesce_i = 1'b0;
  logic               resource_reset_i = 1'b0;
  logic               idle_o;
  logic               block_ack_o;
  logic               irq_o;
  logic               hp_block_new_i = 1'b0;
  logic               hp_pause_ack_o;
  logic               hp_flush_i = 1'b0;
  logic               hp_flush_busy_o;
  logic               hp_idle_o;
  logic        [31:0] s_value;
  logic        [11:0] s_reg_offset                 [RegisterCount];
  logic        [ 1:0] s_reg_access                 [RegisterCount];
  logic        [31:0] s_reg_reset                  [RegisterCount];
  logic               s_reg_full_strobe            [RegisterCount];
  int unsigned        s_reg_count;
  int unsigned        s_ack_wait_cycles;
  logic        [11:0] s_bad_offset;
  logic        [11:0] s_unknown_offsets            [            6];
  logic        [31:0] s_bad_values                 [           20];
  string              s_phase;

  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) npu_axi4 (
      clk_hp_i,
      rst_hp_n_i
  );

  assign npu_axi4.awready = 1'b0;
  assign npu_axi4.wready  = 1'b0;
  assign npu_axi4.bid     = '0;
  assign npu_axi4.bresp   = '0;
  assign npu_axi4.buser   = '0;
  assign npu_axi4.bvalid  = 1'b0;
  assign npu_axi4.arready = 1'b0;
  assign npu_axi4.rid     = '0;
  assign npu_axi4.rdata   = '0;
  assign npu_axi4.rresp   = '0;
  assign npu_axi4.rlast   = 1'b0;
  assign npu_axi4.ruser   = '0;
  assign npu_axi4.rvalid  = 1'b0;

  always #5 clk_i = ~clk_i;
  always #7 clk_hp_i = ~clk_hp_i;

  apb4_npu u_dut (
      .clk_i                (clk_i),
      .rst_n_i              (rst_n_i),
      .clk_hp_i             (clk_hp_i),
      .rst_hp_n_i           (rst_hp_n_i),
      .resource_owner_i     (resource_owner_i),
      .resource_owner_lock_i(resource_owner_lock_i),
      .resource_quiesce_i   (resource_quiesce_i),
      .resource_reset_i     (resource_reset_i),
      .apb4                 (apb4),
      .idle_o               (idle_o),
      .block_ack_o          (block_ack_o),
      .irq_o                (irq_o),
      .hp_block_new_i       (hp_block_new_i),
      .hp_pause_ack_o       (hp_pause_ack_o),
      .hp_flush_i           (hp_flush_i),
      .hp_flush_busy_o      (hp_flush_busy_o),
      .hp_idle_o            (hp_idle_o),
      .npu_axi4             (npu_axi4)
  );

  function automatic logic [31:0] legal_write_value(input logic [11:0] offset_i);
    case (offset_i)
      `APB4_NPU__IRQ_STATE:      legal_write_value = 32'h0000_0007;
      `APB4_NPU__IRQ_ENABLE:     legal_write_value = 32'h0000_0005;
      `APB4_NPU__JOB_BASE:       legal_write_value = 32'h3000_0000;
      `APB4_NPU__JOB_COUNT:      legal_write_value = 32'h0000_0040;
      `APB4_NPU__JOB_ID:         legal_write_value = 32'ha5a5_5a5a;
      `APB4_NPU__TIMEOUT_CYCLES: legal_write_value = 32'h044a_a200;
      `APB4_NPU__PERF_CONTROL:   legal_write_value = 32'h0000_0001;
      default:                   legal_write_value = 32'd0;
    endcase
  endfunction

  function automatic logic [31:0] legal_readback_value(input logic [11:0] offset_i);
    case (offset_i)
      `APB4_NPU__IRQ_STATE: legal_readback_value = 32'd0;
      default:              legal_readback_value = legal_write_value(offset_i);
    endcase
  endfunction

  task automatic add_register(input logic [11:0] offset_i, input logic [1:0] access_i,
                              input logic [31:0] reset_i, input logic full_strobe_i);
    begin
      if (s_reg_count >= RegisterCount) $fatal(1, "NPU register table overflow");
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
      add_register(`APB4_NPU__IP_ID, AccessRo, `APB4_NPU__IP_ID_VALUE, 1'b1);
      add_register(`APB4_NPU__IP_VERSION, AccessRo, `APB4_NPU__IP_VERSION_VALUE, 1'b1);
      add_register(`APB4_NPU__CAPABILITY, AccessRo, `APB4_NPU__CAPABILITY_P4, 1'b1);
      add_register(`APB4_NPU__STATUS, AccessRo, 32'd1, 1'b1);
      add_register(`APB4_NPU__CONTROL, AccessWo, 32'd0, 1'b1);
      add_register(`APB4_NPU__IRQ_STATE, AccessRw, 32'd0, 1'b1);
      add_register(`APB4_NPU__IRQ_ENABLE, AccessRw, 32'd0, 1'b1);
      add_register(`APB4_NPU__IRQ_TEST, AccessWo, 32'd0, 1'b1);
      add_register(`APB4_NPU__JOB_BASE, AccessRw, 32'd0, 1'b1);
      add_register(`APB4_NPU__JOB_COUNT, AccessRw, 32'd0, 1'b1);
      add_register(`APB4_NPU__JOB_ID, AccessRw, 32'd0, 1'b1);
      add_register(`APB4_NPU__TIMEOUT_CYCLES, AccessRw, 32'd0, 1'b1);
      add_register(`APB4_NPU__RESULT_JOB_ID, AccessRo, 32'd0, 1'b1);
      add_register(`APB4_NPU__RESULT_CODE, AccessRo, 32'd0, 1'b1);
      add_register(`APB4_NPU__COMPLETED_DESCRIPTORS, AccessRo, 32'd0, 1'b1);
      add_register(`APB4_NPU__FAULT_DESCRIPTOR, AccessRo, `APB4_NPU__FAULT_DESCRIPTOR_RESET, 1'b1);
      add_register(`APB4_NPU__FAULT_CODE, AccessRo, 32'd0, 1'b1);
      add_register(`APB4_NPU__FAULT_ADDRESS, AccessRo, 32'd0, 1'b1);
      add_register(`APB4_NPU__FAULT_INFO, AccessRo, 32'd0, 1'b1);
      add_register(`APB4_NPU__NUMERIC_PROFILE, AccessRo, `APB4_NPU__NUMERIC_PROFILE_VALUE, 1'b1);
      add_register(`APB4_NPU__LOCAL_BYTES, AccessRo, `APB4_NPU__LOCAL_BYTES_VALUE, 1'b1);
      add_register(`APB4_NPU__MAC_CONFIG, AccessRo, `APB4_NPU__MAC_CONFIG_VALUE, 1'b1);
      add_register(`APB4_NPU__MAX_K_SLICE, AccessRo, `APB4_NPU__MAX_K_SLICE_VALUE, 1'b1);
      add_register(`APB4_NPU__MAX_DIMENSION, AccessRo, `APB4_NPU__MAX_DIMENSION_VALUE, 1'b1);
      add_register(`APB4_NPU__OP_CAPABILITY, AccessRo, `APB4_NPU__OP_CAPABILITY_VALUE, 1'b1);
      add_register(`APB4_NPU__OWNER_STATUS, AccessRo, 32'd0, 1'b1);
      add_register(`APB4_NPU__RECOVERY_GENERATION, AccessRo, 32'd0, 1'b1);
      add_register(`APB4_NPU__PERF_CONTROL, AccessWo, 32'd0, 1'b1);
      add_register(`APB4_NPU__PERF_STATUS, AccessRo, 32'd0, 1'b1);
      add_register(`APB4_NPU__PERF_JOB_ID, AccessRo, 32'd0, 1'b1);
      add_register(`APB4_NPU__PERF_GENERATION, AccessRo, 32'd0, 1'b1);
      add_register(`APB4_NPU__DESCRIPTOR_BYTES, AccessRo, `APB4_NPU__DESCRIPTOR_BYTES_VALUE, 1'b1);
      add_register(`APB4_NPU__PERF_ACTIVE_CYCLES_LO, AccessRo, 32'd0, 1'b1);
      add_register(`APB4_NPU__PERF_ACTIVE_CYCLES_HI, AccessRo, 32'd0, 1'b1);
      add_register(`APB4_NPU__PERF_CLOCK_PAUSE_CYCLES_LO, AccessRo, 32'd0, 1'b1);
      add_register(`APB4_NPU__PERF_CLOCK_PAUSE_CYCLES_HI, AccessRo, 32'd0, 1'b1);
      add_register(`APB4_NPU__PERF_USEFUL_MACS_LO, AccessRo, 32'd0, 1'b1);
      add_register(`APB4_NPU__PERF_USEFUL_MACS_HI, AccessRo, 32'd0, 1'b1);
      add_register(`APB4_NPU__PERF_PACK_CYCLES_LO, AccessRo, 32'd0, 1'b1);
      add_register(`APB4_NPU__PERF_PACK_CYCLES_HI, AccessRo, 32'd0, 1'b1);
      add_register(`APB4_NPU__PERF_LOCAL_BANK_STALL_LO, AccessRo, 32'd0, 1'b1);
      add_register(`APB4_NPU__PERF_LOCAL_BANK_STALL_HI, AccessRo, 32'd0, 1'b1);
      add_register(`APB4_NPU__PERF_DMA_READ_BYTES_LO, AccessRo, 32'd0, 1'b1);
      add_register(`APB4_NPU__PERF_DMA_READ_BYTES_HI, AccessRo, 32'd0, 1'b1);
      add_register(`APB4_NPU__PERF_DMA_WRITE_BYTES_LO, AccessRo, 32'd0, 1'b1);
      add_register(`APB4_NPU__PERF_DMA_WRITE_BYTES_HI, AccessRo, 32'd0, 1'b1);
      add_register(`APB4_NPU__PERF_DMA_STALL_CYCLES_LO, AccessRo, 32'd0, 1'b1);
      add_register(`APB4_NPU__PERF_DMA_STALL_CYCLES_HI, AccessRo, 32'd0, 1'b1);
      add_register(`APB4_NPU__PERF_REQUANT_STALL_LO, AccessRo, 32'd0, 1'b1);
      add_register(`APB4_NPU__PERF_REQUANT_STALL_HI, AccessRo, 32'd0, 1'b1);
      add_register(`APB4_NPU__PERF_RETIRED_DESCRIPTORS_LO, AccessRo, 32'd0, 1'b1);
      add_register(`APB4_NPU__PERF_RETIRED_DESCRIPTORS_HI, AccessRo, 32'd0, 1'b1);
      if (s_reg_count != RegisterCount) begin
        $fatal(1, "NPU register table has %0d entries, expected %0d", s_reg_count, RegisterCount);
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

  task automatic wait_link_up;
    int unsigned s_polls;
    begin
      s_polls = 0;
      apb_read(`APB4_NPU__STATUS, s_value, 1'b0);
      while (s_value[`APB4_NPU__STATUS_RECOVERING] != 1'b0) begin
        s_polls++;
        if (s_polls > 200) $fatal(1, "NPU link did not reconcile after reset");
        apb_read(`APB4_NPU__STATUS, s_value, 1'b0);
      end
    end
  endtask

  task automatic wait_snapshot_valid;
    int unsigned s_polls;
    begin
      s_polls = 0;
      apb_read(`APB4_NPU__PERF_STATUS, s_value, 1'b0);
      while (s_value[`APB4_NPU__PERF_STATUS_SNAP_VALID] != 1'b1) begin
        s_polls++;
        if (s_polls > 500) $fatal(1, "NPU snapshot did not complete");
        apb_read(`APB4_NPU__PERF_STATUS, s_value, 1'b0);
      end
    end
  endtask

  task automatic hard_reset;
    begin
      @(negedge clk_i);
      drive_apb_idle();
      resource_owner_i      = 2'd0;
      resource_owner_lock_i = 1'b0;
      resource_quiesce_i    = 1'b0;
      resource_reset_i      = 1'b0;
      hp_block_new_i        = 1'b0;
      hp_flush_i            = 1'b0;
      rst_n_i               = 1'b0;
      repeat (3) @(posedge clk_i);
      @(negedge clk_i);
      rst_n_i = 1'b1;
      wait_link_up();
    end
  endtask

  task automatic pulse_hp_reset;
    begin
      @(negedge clk_hp_i);
      rst_hp_n_i = 1'b0;
      repeat (4) @(posedge clk_hp_i);
      @(negedge clk_hp_i);
      rst_hp_n_i = 1'b1;
      wait_link_up();
    end
  endtask

  task automatic apb_write(input logic [11:0] offset_i, input logic [31:0] data_i,
                           input logic [3:0] strobe_i, input logic expected_err_i);
    int unsigned s_wait_cycles;
    logic        s_response_err;
    begin
      @(negedge clk_i);
      apb4.paddr   = NpuBase + offset_i;
      apb4.pwdata  = data_i;
      apb4.pstrb   = strobe_i;
      apb4.pwrite  = 1'b1;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      #1;
      if (apb4.pready) $fatal(1, "NPU PREADY asserted during write setup at %h", offset_i);
      @(negedge clk_i);
      apb4.penable  = 1'b1;
      s_wait_cycles = 0;
      #1;
      while (!apb4.pready) begin
        s_wait_cycles++;
        if (s_wait_cycles > 4) $fatal(1, "NPU write wait timeout at %h", offset_i);
        @(negedge clk_i);
        #1;
      end
      if (s_wait_cycles != 1) begin
        $fatal(1, "NPU write wait count mismatch at %h: %0d", offset_i, s_wait_cycles);
      end
      if (apb4.pslverr != expected_err_i) begin
        $fatal(1, "NPU write response mismatch at %h in %s", offset_i, s_phase);
      end
      s_response_err = apb4.pslverr;
      #2;
      if (!apb4.pready || (apb4.pslverr != s_response_err)) begin
        $fatal(1, "NPU write response was not retained through completion at %h", offset_i);
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
      apb4.paddr   = NpuBase + offset_i;
      apb4.pstrb   = 4'd0;
      apb4.pwrite  = 1'b0;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      #1;
      if (apb4.pready) $fatal(1, "NPU PREADY asserted during read setup at %h", offset_i);
      @(negedge clk_i);
      apb4.penable  = 1'b1;
      s_wait_cycles = 0;
      #1;
      while (!apb4.pready) begin
        s_wait_cycles++;
        if (s_wait_cycles > 4) $fatal(1, "NPU read wait timeout at %h", offset_i);
        @(negedge clk_i);
        #1;
      end
      if (s_wait_cycles != 1) begin
        $fatal(1, "NPU read wait count mismatch at %h: %0d", offset_i, s_wait_cycles);
      end
      if (apb4.pslverr != expected_err_i) begin
        $fatal(1, "NPU read response mismatch at %h during %s", offset_i, s_phase);
      end
      s_response_data = apb4.prdata;
      s_response_err  = apb4.pslverr;
      #2;
      if (!apb4.pready || (apb4.prdata != s_response_data) ||
          (apb4.pslverr != s_response_err)) begin
        $fatal(1, "NPU read response was not retained through completion at %h", offset_i);
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
        $fatal(1, "NPU read mismatch at %h: got %h expected %h", offset_i, s_value, expected_i);
      end
    end
  endtask

  task automatic check_reset_state;
    begin
      for (int unsigned register_index = 0; register_index < RegisterCount; register_index++) begin
        if (s_reg_access[register_index] != AccessWo) begin
          expect_read(s_reg_offset[register_index], s_reg_reset[register_index]);
        end
      end
    end
  endtask

  task automatic expect_perf_bank_zero;
    begin
      for (int unsigned counter_index = 0; counter_index < 10; counter_index++) begin
        expect_read(12'(`APB4_NPU__PERF_ACTIVE_CYCLES_LO + 8 * counter_index), 32'd0);
        expect_read(12'(`APB4_NPU__PERF_ACTIVE_CYCLES_LO + 8 * counter_index + 4), 32'd0);
      end
    end
  endtask

  initial begin
    initialize_register_table();
    s_phase = "initial reset";
    drive_apb_idle();
    @(negedge clk_i);
    rst_n_i    = 1'b0;
    rst_hp_n_i = 1'b0;
    repeat (4) @(posedge clk_i);
    @(negedge clk_i);
    rst_hp_n_i = 1'b1;
    @(negedge clk_i);
    rst_n_i = 1'b1;
    wait_link_up();
    if (!idle_o || irq_o) $fatal(1, "NPU reset lifecycle outputs mismatch");
    check_reset_state();

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
          apb_write(`APB4_NPU__TIMEOUT_CYCLES, 32'h044a_a200, 4'hf, 1'b0);
          apb_write(s_reg_offset[register_index], 32'hffff_ffff, 4'hf, 1'b1);
          expect_read(`APB4_NPU__TIMEOUT_CYCLES, 32'h044a_a200);
          expect_read(s_reg_offset[register_index], s_reg_reset[register_index]);
        end
        AccessWo: begin
          apb_read(s_reg_offset[register_index], s_value, 1'b1);
          hard_reset();
          if (s_reg_offset[register_index] == `APB4_NPU__CONTROL) begin
            apb_write(s_reg_offset[register_index], 32'h0000_0004, 4'hf, 1'b0);
            wait_link_up();
          end else if (s_reg_offset[register_index] == `APB4_NPU__IRQ_TEST) begin
            apb_write(s_reg_offset[register_index], 32'd0, 4'hf, 1'b0);
          end else begin
            apb_write(s_reg_offset[register_index], 32'h0000_0001, 4'hf, 1'b0);
            wait_snapshot_valid();
          end
        end
        AccessRw: begin
          apb_write(s_reg_offset[register_index], legal_write_value(s_reg_offset[register_index]),
                    4'hf, 1'b0);
          expect_read(s_reg_offset[register_index], legal_readback_value(
                      s_reg_offset[register_index]));
        end
        default: $fatal(1, "NPU register table has invalid access class");
      endcase
    end

    s_phase = "full strobe enforcement";
    for (int unsigned register_index = 0; register_index < RegisterCount; register_index++) begin
      if (s_reg_full_strobe[register_index] && (s_reg_access[register_index] != AccessRo)) begin
        hard_reset();
        if (s_reg_offset[register_index] == `APB4_NPU__TIMEOUT_CYCLES) begin
          apb_write(`APB4_NPU__JOB_ID, 32'ha5a5_5a5a, 4'hf, 1'b0);
          apb_write(s_reg_offset[register_index], legal_write_value(s_reg_offset[register_index]),
                    4'h7, 1'b1);
          apb_write(s_reg_offset[register_index], legal_write_value(s_reg_offset[register_index]),
                    4'h0, 1'b1);
          expect_read(`APB4_NPU__JOB_ID, 32'ha5a5_5a5a);
          expect_read(s_reg_offset[register_index], s_reg_reset[register_index]);
        end else begin
          apb_write(`APB4_NPU__TIMEOUT_CYCLES, 32'h044a_a200, 4'hf, 1'b0);
          apb_write(s_reg_offset[register_index], legal_write_value(s_reg_offset[register_index]),
                    4'h7, 1'b1);
          apb_write(s_reg_offset[register_index], legal_write_value(s_reg_offset[register_index]),
                    4'h0, 1'b1);
          expect_read(`APB4_NPU__TIMEOUT_CYCLES, 32'h044a_a200);
          if (s_reg_access[register_index] == AccessRw) begin
            expect_read(s_reg_offset[register_index], s_reg_reset[register_index]);
          end
        end
      end
    end

    s_phase = "misaligned accesses";
    for (int unsigned register_index = 0; register_index < RegisterCount; register_index++) begin
      hard_reset();
      apb_write(`APB4_NPU__TIMEOUT_CYCLES, 32'h044a_a200, 4'hf, 1'b0);
      apb_read(s_reg_offset[register_index] | 12'h002, s_value, 1'b1);
      if (s_value != 32'd0) $fatal(1, "NPU misaligned read returned nonzero data");
      apb_write(s_reg_offset[register_index] | 12'h001, legal_write_value(
                s_reg_offset[register_index]), 4'hf, 1'b1);
      expect_read(`APB4_NPU__TIMEOUT_CYCLES, 32'h044a_a200);
    end

    s_phase = "unknown offsets";
    hard_reset();
    apb_write(`APB4_NPU__TIMEOUT_CYCLES, 32'h044a_a200, 4'hf, 1'b0);
    s_unknown_offsets[0] = 12'h0d0;
    s_unknown_offsets[1] = 12'h0d4;
    s_unknown_offsets[2] = 12'h0f8;
    s_unknown_offsets[3] = 12'h100;
    s_unknown_offsets[4] = 12'h800;
    s_unknown_offsets[5] = 12'hffc;
    for (int unsigned unknown_index = 0; unknown_index < 6; unknown_index++) begin
      apb_read(s_unknown_offsets[unknown_index], s_value, 1'b1);
      if (s_value != 32'd0) $fatal(1, "NPU invalid read returned nonzero data");
      apb_write(s_unknown_offsets[unknown_index], 32'd0, 4'hf, 1'b1);
    end
    expect_read(`APB4_NPU__TIMEOUT_CYCLES, 32'h044a_a200);

    s_phase          = "rejected values";
    s_bad_values[0]  = 32'h0000_0000;
    s_bad_values[1]  = 32'h0000_0003;
    s_bad_values[2]  = 32'h0000_0005;
    s_bad_values[3]  = 32'h0000_0007;
    s_bad_values[4]  = 32'h0000_0008;
    s_bad_values[5]  = 32'h8000_0001;
    s_bad_values[6]  = 32'h0000_0001;
    s_bad_values[7]  = 32'h0000_0008;
    s_bad_values[8]  = 32'hffff_ffff;
    s_bad_values[9]  = 32'h0000_0008;
    s_bad_values[10] = 32'h0000_0008;
    s_bad_values[11] = 32'h0001_0000;
    s_bad_values[12] = 32'h0000_0000;
    s_bad_values[13] = 32'h0000_0000;
    s_bad_values[14] = 32'h0000_0002;
    s_bad_values[15] = 32'h0000_0003;
    s_bad_values[16] = 32'h8000_0001;
    s_bad_values[17] = 32'hffff_ffff;
    s_bad_values[18] = 32'h0000_0001;
    s_bad_values[19] = 32'hffff_ffff;
    for (int unsigned bad_index = 0; bad_index < 20; bad_index++) begin
      case (bad_index)
        0, 1, 2, 3, 4, 5, 6: s_bad_offset = `APB4_NPU__CONTROL;
        7, 8:                s_bad_offset = `APB4_NPU__IRQ_STATE;
        9:                   s_bad_offset = `APB4_NPU__IRQ_ENABLE;
        10:                  s_bad_offset = `APB4_NPU__IRQ_TEST;
        11:                  s_bad_offset = `APB4_NPU__JOB_COUNT;
        12:                  s_bad_offset = `APB4_NPU__TIMEOUT_CYCLES;
        13, 14, 15, 16:      s_bad_offset = `APB4_NPU__PERF_CONTROL;
        17:                  s_bad_offset = `APB4_NPU__IP_ID;
        18:                  s_bad_offset = `APB4_NPU__STATUS;
        default:             s_bad_offset = `APB4_NPU__FAULT_DESCRIPTOR;
      endcase
      hard_reset();
      apb_write(`APB4_NPU__TIMEOUT_CYCLES, 32'h044a_a200, 4'hf, 1'b0);
      if (bad_index == 6) begin
        apb_write(`APB4_NPU__IRQ_TEST, 32'h0000_0001, 4'hf, 1'b0);
      end
      apb_write(s_bad_offset, s_bad_values[bad_index], 4'hf, 1'b1);
      if (bad_index == 6) begin
        apb_write(`APB4_NPU__IRQ_STATE, 32'h0000_0001, 4'hf, 1'b0);
        if (u_dut.u_npu_reg.s_launch_busy_q !== 1'b0) begin
          $fatal(1, "NPU rejected START had a launch side effect");
        end
      end
      expect_read(`APB4_NPU__TIMEOUT_CYCLES, 32'h044a_a200);
      expect_read(`APB4_NPU__IRQ_STATE, 32'd0);
      expect_read(`APB4_NPU__PERF_STATUS, 32'd0);
    end

    s_phase = "control semantics";
    hard_reset();
    apb_write(`APB4_NPU__IRQ_TEST, 32'h0000_0001, 4'hf, 1'b0);
    apb_write(`APB4_NPU__CONTROL, 32'h0000_0001, 4'hf, 1'b1);
    // A pending terminal IRQ holds READY low even with the P4 pipeline enabled.
    expect_read(`APB4_NPU__STATUS, 32'd0);
    expect_read(`APB4_NPU__RECOVERY_GENERATION, 32'd0);
    if (u_dut.u_npu_reg.s_launch_busy_q !== 1'b0) begin
      $fatal(1, "NPU rejected START had a launch side effect");
    end
    apb_write(`APB4_NPU__IRQ_STATE, 32'h0000_0001, 4'hf, 1'b0);
    expect_read(`APB4_NPU__IRQ_STATE, 32'd0);
    apb_write(`APB4_NPU__CONTROL, 32'h0000_0002, 4'hf, 1'b0);
    expect_read(`APB4_NPU__IRQ_STATE, 32'd0);
    expect_read(`APB4_NPU__RESULT_CODE, 32'd0);
    apb_write(`APB4_NPU__JOB_BASE, 32'h3000_0000, 4'hf, 1'b0);
    apb_write(`APB4_NPU__JOB_COUNT, 32'h0000_0040, 4'hf, 1'b0);
    apb_write(`APB4_NPU__JOB_ID, 32'ha5a5_5a5a, 4'hf, 1'b0);
    apb_write(`APB4_NPU__TIMEOUT_CYCLES, 32'h044a_a200, 4'hf, 1'b0);
    apb_write(`APB4_NPU__IRQ_ENABLE, 32'h0000_0007, 4'hf, 1'b0);
    apb_write(`APB4_NPU__IRQ_TEST, 32'h0000_0007, 4'hf, 1'b0);
    apb_write(`APB4_NPU__CONTROL, 32'h0000_0004, 4'hf, 1'b0);
    wait_link_up();
    check_reset_state();
    expect_read(`APB4_NPU__RECOVERY_GENERATION, 32'd0);
    if (irq_o) $fatal(1, "NPU SOFT_RESET retained interrupt state");

    s_phase = "irq events";
    hard_reset();
    apb_write(`APB4_NPU__IRQ_ENABLE, 32'h0000_0007, 4'hf, 1'b0);
    if (irq_o) $fatal(1, "NPU interrupt asserted without events");
    apb_write(`APB4_NPU__IRQ_TEST, 32'h0000_0007, 4'hf, 1'b0);
    expect_read(`APB4_NPU__IRQ_STATE, 32'h0000_0007);
    if (!irq_o) $fatal(1, "NPU enabled interrupt did not assert");
    apb_write(`APB4_NPU__IRQ_ENABLE, 32'd0, 4'hf, 1'b0);
    if (irq_o) $fatal(1, "NPU interrupt enable modified collection");
    expect_read(`APB4_NPU__IRQ_STATE, 32'h0000_0007);
    apb_write(`APB4_NPU__IRQ_STATE, 32'h0000_0005, 4'hf, 1'b0);
    expect_read(`APB4_NPU__IRQ_STATE, 32'h0000_0002);
    apb_write(`APB4_NPU__IRQ_STATE, 32'h0000_0002, 4'hf, 1'b0);
    expect_read(`APB4_NPU__IRQ_STATE, 32'd0);
    apb_write(`APB4_NPU__IRQ_TEST, 32'h0000_0001, 4'hf, 1'b0);
    force u_dut.u_npu_reg.s_irq_test = 3'h1;
    apb_write(`APB4_NPU__IRQ_STATE, 32'h0000_0001, 4'hf, 1'b0);
    release u_dut.u_npu_reg.s_irq_test;
    expect_read(`APB4_NPU__IRQ_STATE, 32'h0000_0001);
    apb_write(`APB4_NPU__IRQ_STATE, 32'h0000_0001, 4'hf, 1'b0);
    expect_read(`APB4_NPU__IRQ_STATE, 32'd0);
    apb_write(`APB4_NPU__IRQ_ENABLE, 32'h0000_0003, 4'hf, 1'b0);
    apb_write(`APB4_NPU__IRQ_TEST, 32'h0000_0001, 4'hf, 1'b0);
    if (!irq_o) $fatal(1, "NPU masked interrupt event did not assert");
    apb_write(`APB4_NPU__IRQ_ENABLE, 32'h0000_0002, 4'hf, 1'b0);
    if (irq_o) $fatal(1, "NPU irq_o is not exactly IRQ_STATE & IRQ_ENABLE");
    // The injected terminal event stays pending, which holds READY low at P4.
    expect_read(`APB4_NPU__STATUS, 32'd0);
    expect_read(`APB4_NPU__RESULT_CODE, 32'd0);
    expect_read(`APB4_NPU__RESULT_JOB_ID, 32'd0);

    s_phase = "owner status";
    hard_reset();
    resource_owner_i      = 2'd1;
    resource_owner_lock_i = 1'b1;
    expect_read(`APB4_NPU__OWNER_STATUS, 32'h0000_0101);
    resource_quiesce_i = 1'b1;
    expect_read(`APB4_NPU__OWNER_STATUS, 32'h0000_0301);
    s_ack_wait_cycles = 0;
    while (!block_ack_o) begin
      @(posedge clk_i);
      s_ack_wait_cycles++;
      if (s_ack_wait_cycles > 200) $fatal(1, "NPU quiesce acknowledgement timed out");
    end
    resource_quiesce_i    = 1'b0;
    resource_owner_i      = 2'd2;
    resource_owner_lock_i = 1'b0;
    expect_read(`APB4_NPU__OWNER_STATUS, 32'h0000_0002);
    @(negedge clk_i);
    resource_reset_i = 1'b1;
    expect_read(`APB4_NPU__OWNER_STATUS, 32'h0000_0402);
    s_ack_wait_cycles = 0;
    while (!block_ack_o) begin
      @(posedge clk_i);
      s_ack_wait_cycles++;
      if (s_ack_wait_cycles > 200) $fatal(1, "NPU reset acknowledgement timed out");
    end
    @(negedge clk_i);
    resource_reset_i = 1'b0;
    resource_owner_i = 2'd0;
    wait_link_up();
    expect_read(`APB4_NPU__RECOVERY_GENERATION, 32'd1);

    s_phase = "snapshot flow";
    hard_reset();
    expect_read(`APB4_NPU__PERF_STATUS, 32'd0);
    apb_write(`APB4_NPU__PERF_CONTROL, 32'h0000_0001, 4'hf, 1'b0);
    if (idle_o) $fatal(1, "NPU reported idle with a snapshot in flight");
    expect_read(`APB4_NPU__PERF_STATUS, 32'h0000_0001);
    apb_write(`APB4_NPU__PERF_CONTROL, 32'h0000_0001, 4'hf, 1'b1);
    expect_read(`APB4_NPU__PERF_ACTIVE_CYCLES_LO, 32'd0);
    expect_read(`APB4_NPU__PERF_RETIRED_DESCRIPTORS_HI, 32'd0);
    wait_snapshot_valid();
    expect_read(`APB4_NPU__PERF_STATUS, 32'h0000_0002);
    expect_perf_bank_zero();
    expect_read(`APB4_NPU__PERF_JOB_ID, 32'd0);
    expect_read(`APB4_NPU__PERF_GENERATION, 32'd0);
    expect_read(`APB4_NPU__STATUS, 32'd1);
    if (!idle_o) $fatal(1, "NPU stayed busy after snapshot completion");
    apb_write(`APB4_NPU__PERF_CONTROL, 32'h0000_0001, 4'hf, 1'b0);
    wait_snapshot_valid();
    expect_perf_bank_zero();
    apb_write(`APB4_NPU__PERF_CONTROL, 32'h0000_0001, 4'hf, 1'b0);
    apb_write(`APB4_NPU__CONTROL, 32'h0000_0004, 4'hf, 1'b1);
    wait_snapshot_valid();
    expect_perf_bank_zero();
    apb_write(`APB4_NPU__PERF_CONTROL, 32'h0000_0001, 4'hf, 1'b0);
    @(negedge clk_i);
    rst_n_i = 1'b0;
    repeat (3) @(posedge clk_i);
    @(negedge clk_i);
    rst_n_i = 1'b1;
    wait_link_up();
    expect_read(`APB4_NPU__PERF_STATUS, 32'd0);
    expect_perf_bank_zero();
    expect_read(`APB4_NPU__STATUS, 32'd1);

    s_phase = "recovery generation";
    hard_reset();
    expect_read(`APB4_NPU__RECOVERY_GENERATION, 32'd0);
    pulse_hp_reset();
    expect_read(`APB4_NPU__RECOVERY_GENERATION, 32'd1);
    pulse_hp_reset();
    expect_read(`APB4_NPU__RECOVERY_GENERATION, 32'd2);
    @(negedge clk_i);
    resource_reset_i  = 1'b1;
    s_ack_wait_cycles = 0;
    while (!block_ack_o) begin
      @(posedge clk_i);
      s_ack_wait_cycles++;
      if (s_ack_wait_cycles > 200) $fatal(1, "NPU resource-reset acknowledgement timed out");
    end
    @(negedge clk_i);
    resource_reset_i = 1'b0;
    wait_link_up();
    expect_read(`APB4_NPU__RECOVERY_GENERATION, 32'd3);
    apb_write(`APB4_NPU__CONTROL, 32'h0000_0004, 4'hf, 1'b0);
    wait_link_up();
    expect_read(`APB4_NPU__RECOVERY_GENERATION, 32'd0);

    s_phase = "forced busy lifecycle";
    hard_reset();
    // Force the next-state input: the launch slot holds the forced value
    // through its own d->q feedback until a fresh clear is forced.
    force u_dut.u_npu_reg.s_launch_busy_d = 1'b1;
    @(posedge clk_i);
    #1;
    apb_read(`APB4_NPU__STATUS, s_value, 1'b0);
    if (s_value[`APB4_NPU__STATUS_BUSY] != 1'b1) $fatal(1, "NPU BUSY not visible");
    if (idle_o) $fatal(1, "NPU reported idle with a pending launch");
    apb_write(`APB4_NPU__JOB_BASE, 32'h3000_0000, 4'hf, 1'b1);
    apb_write(`APB4_NPU__JOB_COUNT, 32'h0000_0040, 4'hf, 1'b1);
    apb_write(`APB4_NPU__JOB_ID, 32'ha5a5_5a5a, 4'hf, 1'b1);
    apb_write(`APB4_NPU__TIMEOUT_CYCLES, 32'h0000_1000, 4'hf, 1'b1);
    apb_write(`APB4_NPU__CONTROL, 32'h0000_0004, 4'hf, 1'b1);
    apb_write(`APB4_NPU__CONTROL, 32'h0000_0001, 4'hf, 1'b1);
    apb_write(`APB4_NPU__CONTROL, 32'h0000_0002, 4'hf, 1'b0);
    apb_write(`APB4_NPU__PERF_CONTROL, 32'h0000_0001, 4'hf, 1'b0);
    wait_snapshot_valid();
    expect_perf_bank_zero();
    @(negedge clk_i);
    resource_quiesce_i = 1'b1;
    repeat (20) @(posedge clk_i);
    if (block_ack_o) begin
      $fatal(1, "NPU quiesce acknowledged with a pending shell launch");
    end
    force u_dut.u_npu_reg.s_launch_busy_d = 1'b0;
    @(posedge clk_i);
    #1;
    release u_dut.u_npu_reg.s_launch_busy_d;
    if (u_dut.u_npu_reg.s_launch_busy_q !== 1'b0) begin
      $fatal(1, "NPU forced launch slot did not clear");
    end
    s_ack_wait_cycles = 0;
    while (!block_ack_o) begin
      @(posedge clk_i);
      s_ack_wait_cycles++;
      if (s_ack_wait_cycles > 200) $fatal(1, "NPU quiesce acknowledgement timed out");
    end
    @(negedge clk_i);
    resource_quiesce_i = 1'b0;
    s_ack_wait_cycles  = 0;
    while (block_ack_o) begin
      @(posedge clk_i);
      s_ack_wait_cycles++;
      if (s_ack_wait_cycles > 200) $fatal(1, "NPU quiesce acknowledgement did not release");
    end

    s_phase = "p2 truthfulness";
    hard_reset();
    expect_read(`APB4_NPU__STATUS, 32'd1);
    expect_read(`APB4_NPU__RESULT_CODE, 32'd0);
    expect_read(`APB4_NPU__RESULT_JOB_ID, 32'd0);
    expect_read(`APB4_NPU__COMPLETED_DESCRIPTORS, 32'd0);
    expect_read(`APB4_NPU__FAULT_DESCRIPTOR, `APB4_NPU__FAULT_DESCRIPTOR_RESET);
    expect_read(`APB4_NPU__FAULT_CODE, 32'd0);
    expect_read(`APB4_NPU__FAULT_ADDRESS, 32'd0);
    expect_read(`APB4_NPU__FAULT_INFO, 32'd0);
    if (!idle_o || irq_o) $fatal(1, "NPU final lifecycle outputs mismatch");

    $display("NPU reg test passed");
    $finish;
  end

  // With START still rejected at Phase 3, no software-visible job can launch,
  // so the master must never issue a request in this shell context. The R/B
  // receivers are engine-driven at Phase 3 (live while obligations exist).
  always @(posedge clk_hp_i) begin
    if (rst_hp_n_i) begin
      if (npu_axi4.awvalid || npu_axi4.wvalid || npu_axi4.arvalid) begin
        $fatal(1, "NPU shell master issued a request without an accepted job");
      end
    end
  end

  initial begin
    repeat (300000) @(posedge clk_i);
    $fatal(1, "NPU register matrix timed out in %s", s_phase);
  end
endmodule
