// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

`include "apu_define.svh"

module apu_reg (
    // verilog_format: off -- preserve the APB and lifecycle boundary columns
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic [1:0]  owner_i,
    input  logic        owner_lock_i,
    input  logic        quiesce_i,
    input  logic        resource_reset_i,
    input  logic        resource_reset_apply_i,
    input  logic        core_idle_i,
    input  logic        core_busy_i,
    input  logic        core_aborting_i,
    input  logic [31:0] stream_status_i,
    input  logic [31:0] job_status_i,
    input  logic [31:0] job_input_used_i,
    input  logic [31:0] job_output_bytes_i,
    input  logic [31:0] job_frames_i,
    input  logic [31:0] job_source_info_i,
    input  logic [31:0] job_cycles_i,
    input  logic [31:0] job_detail_i,
    input  logic [31:0] ring_status_i,
    input  logic [7:0]  ring_head_i,
    input  logic [31:0] ring_completed_i,
    input  logic [7:0]  mc_status_i,
    input  logic [31:0] mc_abi_i,
    input  logic [63:0] mc_build_id_i,
    input  logic        mc_lock_i,
    input  logic [31:0] mc_actual_crc_i,
    input  logic [31:0] mc_load_count_i,
    input  logic [31:0] sequencer_status_i,
    input  logic [31:0] sequencer_retired_i,
    input  logic        sequencer_trapped_i,
    input  logic [10:0] irq_set_i,
    input  logic        fault_valid_i,
    input  logic [5:0]  fault_code_i,
    input  logic [3:0]  fault_stage_i,
    input  logic [1:0]  fault_resp_i,
    input  logic [7:0]  fault_index_i,
    input  logic [31:0] fault_addr_i,
    input  logic [31:0] fault_detail_i,
    input  logic [63:0] perf_active_cycles_i,
    input  logic [63:0] perf_input_bytes_i,
    input  logic [63:0] perf_output_bytes_i,
    input  logic [63:0] perf_dma_read_stalls_i,
    input  logic [63:0] perf_dma_write_stalls_i,
    input  logic [63:0] perf_stream_stalls_i,
    input  logic [63:0] perf_sequencer_instr_i,
    input  logic [63:0] perf_faults_i,
    apb4_if.slave       apb4,
    output logic        soft_reset_o,
    output logic        abort_o,
    output logic        microcode_load_o,
    output logic        counter_clear_o,
    output logic        perf_enable_o,
    output logic        xrun_clear_o,
    output logic [3:0]  stream_route_o,
    output logic [15:0] stream_watermark_o,
    output logic [31:0] read_base_o,
    output logic [31:0] read_limit_o,
    output logic [31:0] write_base_o,
    output logic [31:0] write_limit_o,
    output logic [31:0] dma_timeout_o,
    output logic [31:0] sequencer_timeout_o,
    output logic [31:0] mc_image_addr_o,
    output logic [31:0] mc_image_size_o,
    output logic [31:0] mc_expected_crc_o,
    output logic [31:0] ring_base_o,
    output logic [8:0]  ring_size_o,
    output logic [7:0]  ring_tail_o,
    output logic [1:0]  ring_control_o,
    output logic [31:0] ring_coalesce_o,
    output logic        idle_o,
    output logic        irq_o
    // verilog_format: on
);
  localparam logic [31:0] IpId = 32'h4150_5530;
  localparam logic [31:0] IpVersion = 32'h0001_0000;
  localparam logic [31:0] Capability0 = 32'h0000_0098;
  localparam logic [31:0] Capability1 = 32'h0000_0010;
  localparam logic [31:0] AbiDigest = 32'd0;
  localparam logic [10:0] IrqMask = 11'h7ff;
  localparam logic [31:0] TimeoutReset = 32'h0000_ffff;
  localparam logic [31:0] RingCoalesceReset = 32'h0001_0001;
  localparam logic [31:0] KwsConfigReset = 32'h0000_0380;
  localparam logic [3:0][31:0] AclReset = {32'd0, 32'hffff_ffff, 32'd0, 32'hffff_ffff};
  localparam logic [4:0][31:0] RingReset = {RingCoalesceReset, 32'd0, 32'd0, 32'd0, 32'd0};

  logic s_apb4_ready_d, s_apb4_ready_q;
  logic [31:0] s_apb4_rdata_q;
  logic s_apb4_resp_err_d, s_apb4_resp_err_q;
  logic        s_req_accept;
  logic        s_write;
  logic [11:0] s_offset;
  logic [31:0] s_strobed_write;
  logic [31:0] s_merged_write;
  logic        s_read_err;
  logic        s_write_err;
  logic        s_write_unsupported;
  logic [31:0] s_read_data;
  logic        s_soft_reset;
  logic        s_abort;
  logic        s_microcode_load;
  logic        s_cnt_clear;
  logic [10:0] s_irq_clear;
  logic [10:0] s_irq_set;

  logic [10:0] s_irq_state_d, s_irq_state_q;
  logic [10:0] s_irq_en_d, s_irq_en_q;
  logic [31:0] s_err_stat_d, s_err_stat_q;
  logic [31:0] s_err_addr_d, s_err_addr_q;
  logic [31:0] s_err_detail_d, s_err_detail_q;
  logic [1:0][31:0] s_timeout_d, s_timeout_q;
  logic [3:0] s_stream_route_d, s_stream_route_q;
  logic [3:0][31:0] s_acl_d, s_acl_q;
  logic [2:0][31:0] s_mc_cfg_d, s_mc_cfg_q;
  logic [7:0][31:0] s_job_cfg_d, s_job_cfg_q;
  logic [4:0][31:0] s_ring_cfg_d, s_ring_cfg_q;
  logic [2:0][31:0] s_kws_model_cfg_d, s_kws_model_cfg_q;
  logic [15:0] s_kws_cfg_d, s_kws_cfg_q;
  logic [15:0] s_stream_watermark_d, s_stream_watermark_q;
  logic s_perf_en_d, s_perf_en_q;
  logic s_perf_snapshot_valid_d, s_perf_snapshot_valid_q;
  logic [ 9:0][63:0] s_perf_snapshot_q;
  logic              s_err_clear;
  logic              s_unused_snapshot;
  logic [32:0]       s_mc_image_end;

  function automatic logic [31:0] apply_wstrb(
      input logic [31:0] previous_i, input logic [31:0] value_i, input logic [3:0] strobe_i);
    logic [31:0] s_value;
    begin
      s_value = previous_i;
      for (int unsigned byte_index = 0; byte_index < 4; byte_index++) begin
        if (strobe_i[byte_index]) begin
          s_value[(byte_index*8)+:8] = value_i[(byte_index*8)+:8];
        end
      end
      return s_value;
    end
  endfunction

  function automatic logic is_power_of_two(input logic [31:0] value_i);
    return (value_i != 32'd0) && ((value_i & (value_i - 1'b1)) == 32'd0);
  endfunction

  assign s_req_accept = apb4.psel && apb4.penable && !s_apb4_ready_q;
  assign s_write = s_req_accept && apb4.pwrite;
  assign s_offset = apb4.paddr[11:0];
  assign s_strobed_write = apply_wstrb(32'd0, apb4.pwdata, apb4.pstrb);
  assign s_apb4_ready_d = s_req_accept;
  assign s_apb4_resp_err_d = s_req_accept && (apb4.pwrite ? s_write_err : s_read_err);
  assign apb4.pready = s_apb4_ready_q;
  assign apb4.prdata = s_apb4_rdata_q;
  assign apb4.pslverr = s_apb4_resp_err_q;
  assign idle_o = core_idle_i;
  assign irq_o = (s_irq_state_q & s_irq_en_q) != 11'd0;
  assign soft_reset_o = s_soft_reset;
  assign abort_o = s_abort;
  assign microcode_load_o = s_microcode_load;
  assign counter_clear_o = s_cnt_clear;
  assign perf_enable_o = s_perf_en_q;
  assign xrun_clear_o = s_irq_clear[`APB4_APU__IRQ_STREAM_XRUN];
  assign stream_route_o = s_stream_route_q;
  assign stream_watermark_o = s_stream_watermark_q;
  assign read_base_o = s_acl_q[0];
  assign read_limit_o = s_acl_q[1];
  assign write_base_o = s_acl_q[2];
  assign write_limit_o = s_acl_q[3];
  assign dma_timeout_o = s_timeout_q[1];
  assign sequencer_timeout_o = s_timeout_q[0];
  assign mc_image_addr_o = s_mc_cfg_q[0];
  assign mc_image_size_o = s_mc_cfg_q[1];
  assign mc_expected_crc_o = s_mc_cfg_q[2];
  assign ring_base_o = s_ring_cfg_q[0];
  assign ring_size_o = s_ring_cfg_q[1][8:0];
  assign ring_tail_o = s_ring_cfg_q[2][7:0];
  assign ring_control_o = s_ring_cfg_q[3][1:0];
  assign ring_coalesce_o = s_ring_cfg_q[4];
  assign s_err_clear     = s_write && !s_write_err &&
      (s_offset == `APB4_APU__ERROR_STATUS) && s_strobed_write[0];
  assign s_unused_snapshot = ^s_perf_snapshot_q[3] ^ ^s_perf_snapshot_q[7] ^ ^s_perf_snapshot_q[8];
  assign s_mc_image_end = {1'b0, s_mc_cfg_q[0]} + {1'b0, s_mc_cfg_q[1]} - 1'b1;

  always_comb begin
    s_read_data = 32'd0;
    s_read_err  = s_offset[1:0] != 2'b00;
    if (!s_read_err) begin
      unique case (s_offset)
        `APB4_APU__IP_ID: s_read_data = IpId;
        `APB4_APU__IP_VERSION: s_read_data = IpVersion;
        `APB4_APU__CAPABILITY0: s_read_data = Capability0;
        `APB4_APU__CAPABILITY1: s_read_data = Capability1;
        `APB4_APU__STATUS:
        s_read_data = {
          22'd0,
          sequencer_trapped_i,
          !core_busy_i,
          core_aborting_i,
          quiesce_i,
          2'd0,
          ring_status_i[`APB4_APU__RING_STATUS_ACTIVE],
          core_busy_i,
          1'b0,
          mc_status_i[`APB4_APU__MC_STATUS_VALID]
        };
        `APB4_APU__IRQ_STATE: s_read_data = {21'd0, s_irq_state_q};
        `APB4_APU__IRQ_ENABLE: s_read_data = {21'd0, s_irq_en_q};
        `APB4_APU__ERROR_STATUS: s_read_data = s_err_stat_q;
        `APB4_APU__ERROR_ADDRESS: s_read_data = s_err_addr_q;
        `APB4_APU__ERROR_DETAIL: s_read_data = s_err_detail_q;
        `APB4_APU__SEQUENCER_TIMEOUT: s_read_data = s_timeout_q[0];
        `APB4_APU__STREAM_ROUTE: s_read_data = {28'd0, s_stream_route_q};
        `APB4_APU__STREAM_STATUS: s_read_data = stream_status_i;
        `APB4_APU__OWNER_STATUS:
        s_read_data = {21'd0, resource_reset_i, quiesce_i, owner_lock_i, 6'd0, owner_i};
        `APB4_APU__READ_BASE: s_read_data = s_acl_q[0];
        `APB4_APU__READ_LIMIT: s_read_data = s_acl_q[1];
        `APB4_APU__WRITE_BASE: s_read_data = s_acl_q[2];
        `APB4_APU__WRITE_LIMIT: s_read_data = s_acl_q[3];
        `APB4_APU__DMA_TIMEOUT: s_read_data = s_timeout_q[1];
        `APB4_APU__ABI_DIGEST: s_read_data = AbiDigest;
        `APB4_APU__SEQUENCER_STATUS: s_read_data = sequencer_status_i;
        `APB4_APU__SEQUENCER_RETIRED: s_read_data = sequencer_retired_i;
        `APB4_APU__MC_STATUS: s_read_data = {24'd0, mc_status_i};
        `APB4_APU__MC_ABI: s_read_data = mc_abi_i;
        `APB4_APU__MC_BUILD_ID_LO: s_read_data = mc_build_id_i[31:0];
        `APB4_APU__MC_BUILD_ID_HI: s_read_data = mc_build_id_i[63:32];
        `APB4_APU__MC_LOCK: s_read_data = {31'd0, mc_lock_i};
        `APB4_APU__MC_ACTUAL_CRC: s_read_data = mc_actual_crc_i;
        `APB4_APU__MC_LOAD_COUNT: s_read_data = mc_load_count_i;
        `APB4_APU__KWS_STATUS, `APB4_APU__KWS_RESULT, `APB4_APU__KWS_TIMESTAMP_LO,
        `APB4_APU__KWS_TIMESTAMP_HI, `APB4_APU__KWS_FRAME_COUNT,
        `APB4_APU__KWS_INFERENCE_COUNT, `APB4_APU__KWS_HIT_COUNT,
        `APB4_APU__KWS_OVERRUN_COUNT, `APB4_APU__KWS_MODEL_STATUS,
        `APB4_APU__KWS_MODEL_ACTUAL_CRC:
        s_read_data = 32'd0;
        `APB4_APU__STREAM_WATERMARK: s_read_data = {16'd0, s_stream_watermark_q};
        `APB4_APU__MC_IMAGE_ADDRESS: s_read_data = s_mc_cfg_q[0];
        `APB4_APU__MC_IMAGE_SIZE: s_read_data = s_mc_cfg_q[1];
        `APB4_APU__MC_EXPECTED_CRC: s_read_data = s_mc_cfg_q[2];
        `APB4_APU__JOB_CONTROL: s_read_data = s_job_cfg_q[0];
        `APB4_APU__JOB_INPUT_ADDRESS: s_read_data = s_job_cfg_q[1];
        `APB4_APU__JOB_INPUT_LENGTH: s_read_data = s_job_cfg_q[2];
        `APB4_APU__JOB_OUTPUT_ADDRESS: s_read_data = s_job_cfg_q[3];
        `APB4_APU__JOB_OUTPUT_CAPACITY: s_read_data = s_job_cfg_q[4];
        `APB4_APU__JOB_INPUT_CONFIG: s_read_data = s_job_cfg_q[5];
        `APB4_APU__JOB_OUTPUT_CONFIG: s_read_data = s_job_cfg_q[6];
        `APB4_APU__JOB_FLAGS: s_read_data = s_job_cfg_q[7];
        `APB4_APU__JOB_STATUS: s_read_data = job_status_i;
        `APB4_APU__JOB_INPUT_USED: s_read_data = job_input_used_i;
        `APB4_APU__JOB_OUTPUT_BYTES: s_read_data = job_output_bytes_i;
        `APB4_APU__JOB_FRAMES: s_read_data = job_frames_i;
        `APB4_APU__JOB_SOURCE_INFO: s_read_data = job_source_info_i;
        `APB4_APU__JOB_CYCLES: s_read_data = job_cycles_i;
        `APB4_APU__JOB_DETAIL: s_read_data = job_detail_i;
        `APB4_APU__RING_BASE: s_read_data = s_ring_cfg_q[0];
        `APB4_APU__RING_SIZE: s_read_data = s_ring_cfg_q[1];
        `APB4_APU__RING_TAIL: s_read_data = s_ring_cfg_q[2];
        `APB4_APU__RING_CONTROL: s_read_data = s_ring_cfg_q[3];
        `APB4_APU__RING_COALESCE: s_read_data = s_ring_cfg_q[4];
        `APB4_APU__RING_HEAD: s_read_data = {24'd0, ring_head_i};
        `APB4_APU__RING_STATUS: s_read_data = ring_status_i;
        `APB4_APU__RING_COMPLETED: s_read_data = ring_completed_i;
        `APB4_APU__KWS_MODEL_ADDRESS: s_read_data = s_kws_model_cfg_q[0];
        `APB4_APU__KWS_MODEL_SIZE: s_read_data = s_kws_model_cfg_q[1];
        `APB4_APU__KWS_MODEL_EXPECTED_CRC: s_read_data = s_kws_model_cfg_q[2];
        `APB4_APU__KWS_CONTROL: s_read_data = 32'd0;
        `APB4_APU__KWS_CONFIG: s_read_data = {16'd0, s_kws_cfg_q};
        `APB4_APU__PERF_CONTROL: s_read_data = {31'd0, s_perf_en_q};
        `APB4_APU__PERF_STATUS: s_read_data = {31'd0, s_perf_snapshot_valid_q};
        `APB4_APU__PERF_ACTIVE_CYCLES_LO: s_read_data = s_perf_snapshot_q[0][31:0];
        `APB4_APU__PERF_ACTIVE_CYCLES_HI: s_read_data = s_perf_snapshot_q[0][63:32];
        `APB4_APU__PERF_INPUT_BYTES_LO: s_read_data = s_perf_snapshot_q[1][31:0];
        `APB4_APU__PERF_INPUT_BYTES_HI: s_read_data = s_perf_snapshot_q[1][63:32];
        `APB4_APU__PERF_OUTPUT_BYTES_LO: s_read_data = s_perf_snapshot_q[2][31:0];
        `APB4_APU__PERF_OUTPUT_BYTES_HI: s_read_data = s_perf_snapshot_q[2][63:32];
        `APB4_APU__PERF_DECODED_FRAMES_LO, `APB4_APU__PERF_DECODED_FRAMES_HI: s_read_data = 32'd0;
        `APB4_APU__PERF_DMA_READ_STALLS_LO: s_read_data = s_perf_snapshot_q[4][31:0];
        `APB4_APU__PERF_DMA_READ_STALLS_HI: s_read_data = s_perf_snapshot_q[4][63:32];
        `APB4_APU__PERF_DMA_WRITE_STALLS_LO: s_read_data = s_perf_snapshot_q[5][31:0];
        `APB4_APU__PERF_DMA_WRITE_STALLS_HI: s_read_data = s_perf_snapshot_q[5][63:32];
        `APB4_APU__PERF_STREAM_STALLS_LO: s_read_data = s_perf_snapshot_q[6][31:0];
        `APB4_APU__PERF_STREAM_STALLS_HI: s_read_data = s_perf_snapshot_q[6][63:32];
        `APB4_APU__PERF_SEQUENCER_INSTR_LO: s_read_data = s_perf_snapshot_q[7][31:0];
        `APB4_APU__PERF_SEQUENCER_INSTR_HI: s_read_data = s_perf_snapshot_q[7][63:32];
        `APB4_APU__PERF_KWS_CYCLES_LO, `APB4_APU__PERF_KWS_CYCLES_HI: s_read_data = 32'd0;
        `APB4_APU__PERF_FAULTS_LO: s_read_data = s_perf_snapshot_q[9][31:0];
        `APB4_APU__PERF_FAULTS_HI: s_read_data = s_perf_snapshot_q[9][63:32];
        `APB4_APU__COMMAND, `APB4_APU__IRQ_TEST, `APB4_APU__RING_DOORBELL: begin
          s_read_data = 32'd0;
          s_read_err  = 1'b1;
        end
        default: begin
          s_read_data = 32'd0;
          s_read_err  = 1'b1;
        end
      endcase
    end
  end

  always_comb begin
    s_write_err         = s_offset[1:0] != 2'b00;
    s_write_unsupported = 1'b0;
    s_merged_write      = s_strobed_write;
    if (!s_write_err) begin
      unique case (s_offset)
        `APB4_APU__COMMAND: begin
          s_write_unsupported = (apb4.pwdata & 32'h0000_0029) != 32'd0;
          s_write_err = (apb4.pstrb != 4'hf) ||
                        ((apb4.pwdata & 32'hffff_ff80) != 32'd0) ||
                        (apb4.pwdata[`APB4_APU__COMMAND_ABORT] && !core_busy_i) ||
                        (apb4.pwdata[`APB4_APU__COMMAND_MICROCODE_LOAD] &&
                         (!core_idle_i || !quiesce_i || (owner_i != 2'd0) || mc_lock_i ||
                          (s_mc_cfg_q[0][5:0] != 6'd0) || (s_mc_cfg_q[1] == 32'd0) ||
                          s_mc_image_end[32] || (s_mc_cfg_q[0] < s_acl_q[0]) ||
                          (s_mc_image_end[31:0] > s_acl_q[1]))) ||
                        ((apb4.pwdata[`APB4_APU__COMMAND_SOFT_RESET] ||
                          apb4.pwdata[`APB4_APU__COMMAND_CLEAR_COUNTERS]) && !core_idle_i) ||
                        s_write_unsupported;
        end
        `APB4_APU__IRQ_STATE: s_write_err = (s_strobed_write & ~32'(IrqMask)) != 32'd0;
        `APB4_APU__IRQ_ENABLE: begin
          s_merged_write = apply_wstrb({21'd0, s_irq_en_q}, apb4.pwdata, apb4.pstrb);
          s_write_err    = (s_merged_write & ~32'(IrqMask)) != 32'd0;
        end
        `APB4_APU__IRQ_TEST:
        s_write_err = (apb4.pstrb != 4'hf) || ((apb4.pwdata & ~32'(IrqMask)) != 32'd0);
        `APB4_APU__ERROR_STATUS: s_write_err = (s_strobed_write & 32'hffff_fffe) != 32'd0;
        `APB4_APU__SEQUENCER_TIMEOUT: begin
          s_merged_write = apply_wstrb(s_timeout_q[0], apb4.pwdata, apb4.pstrb);
          s_write_err    = (s_merged_write == 32'd0) || !core_idle_i;
        end
        `APB4_APU__STREAM_ROUTE: begin
          s_merged_write      = apply_wstrb({28'd0, s_stream_route_q}, apb4.pwdata, apb4.pstrb);
          s_write_unsupported = s_merged_write != 32'd0;
          s_write_err         = s_write_unsupported || !core_idle_i;
        end
        `APB4_APU__READ_BASE, `APB4_APU__READ_LIMIT, `APB4_APU__WRITE_BASE,
        `APB4_APU__WRITE_LIMIT, `APB4_APU__MC_EXPECTED_CRC,
        `APB4_APU__KWS_MODEL_EXPECTED_CRC:
        s_write_err = (apb4.pstrb != 4'hf) || !core_idle_i || (owner_i != 2'd0);
        `APB4_APU__DMA_TIMEOUT: begin
          s_merged_write = apply_wstrb(s_timeout_q[1], apb4.pwdata, apb4.pstrb);
          s_write_err    = (s_merged_write == 32'd0) || !core_idle_i;
        end
        `APB4_APU__STREAM_WATERMARK: begin
          s_merged_write = apply_wstrb({16'd0, s_stream_watermark_q}, apb4.pwdata, apb4.pstrb);
          s_write_err = (s_merged_write[31:16] != 16'd0) ||
              (s_merged_write[7:0] > 8'd64) || (s_merged_write[15:8] > 8'd64) ||
              !core_idle_i;
        end
        `APB4_APU__MC_IMAGE_ADDRESS, `APB4_APU__KWS_MODEL_ADDRESS:
        s_write_err = (apb4.pstrb != 4'hf) || (apb4.pwdata[5:0] != 6'd0) ||
                      !core_idle_i || (owner_i != 2'd0);
        `APB4_APU__MC_IMAGE_SIZE, `APB4_APU__KWS_MODEL_SIZE:
        s_write_err = (apb4.pstrb != 4'hf) || (apb4.pwdata == 32'd0) ||
                      !core_idle_i || (owner_i != 2'd0);
        `APB4_APU__JOB_CONTROL: begin
          s_merged_write = apply_wstrb(s_job_cfg_q[0], apb4.pwdata, apb4.pstrb);
          s_write_err = (s_merged_write[31:12] != 20'd0) ||
                        (s_merged_write[3:0] > 4'd1) ||
                        (s_merged_write[7:4] > 4'd2) || (s_merged_write[9:8] > 2'd1) ||
                        !core_idle_i;
        end
        `APB4_APU__JOB_INPUT_ADDRESS, `APB4_APU__JOB_INPUT_LENGTH,
        `APB4_APU__JOB_OUTPUT_ADDRESS, `APB4_APU__JOB_OUTPUT_CAPACITY:
        s_write_err = (apb4.pstrb != 4'hf) || !core_idle_i;
        `APB4_APU__JOB_INPUT_CONFIG: begin
          s_merged_write = apply_wstrb(s_job_cfg_q[5], apb4.pwdata, apb4.pstrb);
          s_write_err    = (s_merged_write[31:26] != 6'd0) || !core_idle_i;
        end
        `APB4_APU__JOB_OUTPUT_CONFIG: begin
          s_merged_write = apply_wstrb(s_job_cfg_q[6], apb4.pwdata, apb4.pstrb);
          s_write_err    = (s_merged_write[31:21] != 11'd0) ||
                           (s_merged_write[20:19] > 2'd1) || !core_idle_i;
        end
        `APB4_APU__JOB_FLAGS: begin
          s_merged_write = apply_wstrb(s_job_cfg_q[7], apb4.pwdata, apb4.pstrb);
          s_write_err    = (s_merged_write[31:1] != 31'd0) || !core_idle_i;
        end
        `APB4_APU__RING_BASE:
        s_write_err = (apb4.pstrb != 4'hf) || (apb4.pwdata[6:0] != 7'd0) || !core_idle_i;
        `APB4_APU__RING_SIZE:
        s_write_err = (apb4.pstrb != 4'hf) || (apb4.pwdata < 32'd2) ||
                      (apb4.pwdata > 32'd256) || !is_power_of_two(apb4.pwdata) || !core_idle_i;
        `APB4_APU__RING_TAIL: s_write_err = (apb4.pstrb != 4'hf) || (apb4.pwdata[31:8] != 24'd0);
        `APB4_APU__RING_CONTROL:
        s_write_err = (apb4.pstrb != 4'hf) || (apb4.pwdata[31:2] != 30'd0) || !core_idle_i;
        `APB4_APU__RING_COALESCE:
        s_write_err = (apb4.pstrb != 4'hf) || (apb4.pwdata[15:8] != 8'd0) ||
                      (apb4.pwdata[7:0] == 8'd0) || (apb4.pwdata[31:16] == 16'd0) ||
                      !core_idle_i;
        `APB4_APU__RING_DOORBELL: begin
          s_write_unsupported = 1'b1;
          s_write_err         = 1'b1;
        end
        `APB4_APU__KWS_CONTROL: begin
          s_write_unsupported = apb4.pwdata[1:0] != 2'd0;
          s_write_err = (apb4.pstrb != 4'hf) || (apb4.pwdata[31:3] != 29'd0) ||
                        s_write_unsupported || !core_idle_i;
        end
        `APB4_APU__KWS_CONFIG: begin
          s_merged_write = apply_wstrb({16'd0, s_kws_cfg_q}, apb4.pwdata, apb4.pstrb);
          s_write_err    = (s_merged_write[31:16] != 16'd0) ||
                           (s_merged_write[15:8] == 8'd0) || !core_idle_i;
        end
        `APB4_APU__PERF_CONTROL: begin
          s_merged_write = apply_wstrb({31'd0, s_perf_en_q}, apb4.pwdata, apb4.pstrb);
          s_write_err    = s_merged_write[31:3] != 29'd0;
        end
        `APB4_APU__IP_ID, `APB4_APU__IP_VERSION, `APB4_APU__CAPABILITY0,
        `APB4_APU__CAPABILITY1, `APB4_APU__STATUS, `APB4_APU__STREAM_STATUS,
        `APB4_APU__OWNER_STATUS, `APB4_APU__ABI_DIGEST,
        `APB4_APU__SEQUENCER_STATUS, `APB4_APU__SEQUENCER_RETIRED,
        `APB4_APU__MC_STATUS, `APB4_APU__MC_ABI, `APB4_APU__MC_BUILD_ID_LO,
        `APB4_APU__MC_BUILD_ID_HI, `APB4_APU__MC_LOCK, `APB4_APU__MC_ACTUAL_CRC,
        `APB4_APU__MC_LOAD_COUNT, `APB4_APU__JOB_STATUS, `APB4_APU__JOB_INPUT_USED,
        `APB4_APU__JOB_OUTPUT_BYTES, `APB4_APU__JOB_FRAMES,
        `APB4_APU__JOB_SOURCE_INFO, `APB4_APU__JOB_CYCLES, `APB4_APU__JOB_DETAIL,
        `APB4_APU__RING_HEAD, `APB4_APU__RING_STATUS, `APB4_APU__RING_COMPLETED,
        `APB4_APU__KWS_STATUS, `APB4_APU__KWS_RESULT, `APB4_APU__KWS_TIMESTAMP_LO,
        `APB4_APU__KWS_TIMESTAMP_HI, `APB4_APU__KWS_FRAME_COUNT,
        `APB4_APU__KWS_INFERENCE_COUNT, `APB4_APU__KWS_HIT_COUNT,
        `APB4_APU__KWS_OVERRUN_COUNT, `APB4_APU__KWS_MODEL_STATUS,
        `APB4_APU__KWS_MODEL_ACTUAL_CRC, `APB4_APU__PERF_STATUS,
        `APB4_APU__PERF_ACTIVE_CYCLES_LO, `APB4_APU__PERF_ACTIVE_CYCLES_HI,
        `APB4_APU__PERF_INPUT_BYTES_LO, `APB4_APU__PERF_INPUT_BYTES_HI,
        `APB4_APU__PERF_OUTPUT_BYTES_LO, `APB4_APU__PERF_OUTPUT_BYTES_HI,
        `APB4_APU__PERF_DECODED_FRAMES_LO, `APB4_APU__PERF_DECODED_FRAMES_HI,
        `APB4_APU__PERF_DMA_READ_STALLS_LO, `APB4_APU__PERF_DMA_READ_STALLS_HI,
        `APB4_APU__PERF_DMA_WRITE_STALLS_LO, `APB4_APU__PERF_DMA_WRITE_STALLS_HI,
        `APB4_APU__PERF_STREAM_STALLS_LO, `APB4_APU__PERF_STREAM_STALLS_HI,
        `APB4_APU__PERF_SEQUENCER_INSTR_LO, `APB4_APU__PERF_SEQUENCER_INSTR_HI,
        `APB4_APU__PERF_KWS_CYCLES_LO, `APB4_APU__PERF_KWS_CYCLES_HI,
        `APB4_APU__PERF_FAULTS_LO, `APB4_APU__PERF_FAULTS_HI:
        s_write_err = 1'b1;
        default: s_write_err = 1'b1;
      endcase
    end
  end

  always_comb begin
    s_irq_state_d           = s_irq_state_q;
    s_irq_en_d              = s_irq_en_q;
    s_err_stat_d            = s_err_stat_q;
    s_err_addr_d            = s_err_addr_q;
    s_err_detail_d          = s_err_detail_q;
    s_timeout_d             = s_timeout_q;
    s_stream_route_d        = s_stream_route_q;
    s_acl_d                 = s_acl_q;
    s_mc_cfg_d              = s_mc_cfg_q;
    s_job_cfg_d             = s_job_cfg_q;
    s_ring_cfg_d            = s_ring_cfg_q;
    s_kws_model_cfg_d       = s_kws_model_cfg_q;
    s_kws_cfg_d             = s_kws_cfg_q;
    s_stream_watermark_d    = s_stream_watermark_q;
    s_perf_en_d             = s_perf_en_q;
    s_perf_snapshot_valid_d = s_perf_snapshot_valid_q;
    s_soft_reset            = 1'b0;
    s_abort                 = 1'b0;
    s_microcode_load        = 1'b0;
    s_cnt_clear             = 1'b0;
    s_irq_clear             = 11'd0;
    s_irq_set               = irq_set_i;

    if (s_write && !s_write_err) begin
      unique case (s_offset)
        `APB4_APU__COMMAND: begin
          s_abort          = apb4.pwdata[`APB4_APU__COMMAND_ABORT];
          s_soft_reset     = apb4.pwdata[`APB4_APU__COMMAND_SOFT_RESET];
          s_cnt_clear      = apb4.pwdata[`APB4_APU__COMMAND_CLEAR_COUNTERS];
          s_microcode_load = apb4.pwdata[`APB4_APU__COMMAND_MICROCODE_LOAD];
        end
        `APB4_APU__IRQ_STATE:              s_irq_clear = s_strobed_write[10:0];
        `APB4_APU__IRQ_ENABLE:             s_irq_en_d = s_merged_write[10:0];
        `APB4_APU__IRQ_TEST:               s_irq_set = s_irq_set | apb4.pwdata[10:0];
        `APB4_APU__ERROR_STATUS: begin
          if (s_strobed_write[0]) begin
            s_err_stat_d   = 32'd0;
            s_err_addr_d   = 32'd0;
            s_err_detail_d = 32'd0;
          end
        end
        `APB4_APU__SEQUENCER_TIMEOUT:      s_timeout_d[0] = s_merged_write;
        `APB4_APU__STREAM_ROUTE:           s_stream_route_d = s_merged_write[3:0];
        `APB4_APU__READ_BASE:              s_acl_d[0] = apb4.pwdata;
        `APB4_APU__READ_LIMIT:             s_acl_d[1] = apb4.pwdata;
        `APB4_APU__WRITE_BASE:             s_acl_d[2] = apb4.pwdata;
        `APB4_APU__WRITE_LIMIT:            s_acl_d[3] = apb4.pwdata;
        `APB4_APU__DMA_TIMEOUT:            s_timeout_d[1] = s_merged_write;
        `APB4_APU__STREAM_WATERMARK:       s_stream_watermark_d = s_merged_write[15:0];
        `APB4_APU__MC_IMAGE_ADDRESS:       s_mc_cfg_d[0] = apb4.pwdata;
        `APB4_APU__MC_IMAGE_SIZE:          s_mc_cfg_d[1] = apb4.pwdata;
        `APB4_APU__MC_EXPECTED_CRC:        s_mc_cfg_d[2] = apb4.pwdata;
        `APB4_APU__JOB_CONTROL:            s_job_cfg_d[0] = s_merged_write;
        `APB4_APU__JOB_INPUT_ADDRESS:      s_job_cfg_d[1] = apb4.pwdata;
        `APB4_APU__JOB_INPUT_LENGTH:       s_job_cfg_d[2] = apb4.pwdata;
        `APB4_APU__JOB_OUTPUT_ADDRESS:     s_job_cfg_d[3] = apb4.pwdata;
        `APB4_APU__JOB_OUTPUT_CAPACITY:    s_job_cfg_d[4] = apb4.pwdata;
        `APB4_APU__JOB_INPUT_CONFIG:       s_job_cfg_d[5] = s_merged_write;
        `APB4_APU__JOB_OUTPUT_CONFIG:      s_job_cfg_d[6] = s_merged_write;
        `APB4_APU__JOB_FLAGS:              s_job_cfg_d[7] = s_merged_write;
        `APB4_APU__RING_BASE:              s_ring_cfg_d[0] = apb4.pwdata;
        `APB4_APU__RING_SIZE:              s_ring_cfg_d[1] = apb4.pwdata;
        `APB4_APU__RING_TAIL:              s_ring_cfg_d[2] = apb4.pwdata;
        `APB4_APU__RING_CONTROL:           s_ring_cfg_d[3] = apb4.pwdata;
        `APB4_APU__RING_COALESCE:          s_ring_cfg_d[4] = apb4.pwdata;
        `APB4_APU__KWS_MODEL_ADDRESS:      s_kws_model_cfg_d[0] = apb4.pwdata;
        `APB4_APU__KWS_MODEL_SIZE:         s_kws_model_cfg_d[1] = apb4.pwdata;
        `APB4_APU__KWS_MODEL_EXPECTED_CRC: s_kws_model_cfg_d[2] = apb4.pwdata;
        `APB4_APU__KWS_CONFIG:             s_kws_cfg_d = s_merged_write[15:0];
        `APB4_APU__PERF_CONTROL: begin
          s_perf_en_d = s_merged_write[`APB4_APU__PERF_CONTROL_ENABLE];
          if (s_merged_write[`APB4_APU__PERF_CONTROL_CLEAR]) begin
            s_cnt_clear = 1'b1;
          end
          if (s_merged_write[`APB4_APU__PERF_CONTROL_SNAPSHOT]) begin
            s_perf_snapshot_valid_d = 1'b1;
          end
        end
        default: begin
        end
      endcase
    end

    if (s_cnt_clear) begin
      s_perf_snapshot_valid_d = 1'b0;
    end
    if (s_req_accept && (apb4.pwrite ? s_write_err : s_read_err)) begin
      s_irq_set[`APB4_APU__IRQ_FIRST_ERROR] = 1'b1;
      if (!s_err_stat_q[`APB4_APU__ERROR_VALID]) begin
        s_err_stat_d = 32'd1 |
            (32'((apb4.pwrite && s_write_unsupported) ?
                     `APB4_APU__ERROR_CODE_UNSUPPORTED :
                     `APB4_APU__ERROR_CODE_INVALID_CONFIG)
             << `APB4_APU__ERROR_CODE) |
            (32'(`APB4_APU__ERROR_STAGE_APB) << `APB4_APU__ERROR_STAGE);
        s_err_addr_d = apb4.paddr;
        s_err_detail_d = apb4.pwrite ? apb4.pwdata : {20'd0, s_offset};
      end
    end
    if (fault_valid_i && (!s_err_stat_q[`APB4_APU__ERROR_VALID] || s_err_clear)) begin
      s_err_stat_d = 32'd1 | (32'(fault_code_i) << `APB4_APU__ERROR_CODE) |
          (32'(fault_stage_i) << `APB4_APU__ERROR_STAGE) |
          (32'(fault_resp_i) << `APB4_APU__ERROR_AXI_RESPONSE) |
          (32'(fault_index_i) << `APB4_APU__ERROR_DESCRIPTOR_INDEX);
      s_err_addr_d = fault_addr_i;
      s_err_detail_d = fault_detail_i;
    end
    s_irq_state_d = (s_irq_state_d & ~s_irq_clear) | s_irq_set;

    if (s_soft_reset || resource_reset_apply_i) begin
      s_irq_state_d           = 11'd0;
      s_irq_en_d              = 11'd0;
      s_err_stat_d            = 32'd0;
      s_err_addr_d            = 32'd0;
      s_err_detail_d          = 32'd0;
      s_timeout_d[0]          = TimeoutReset;
      s_timeout_d[1]          = TimeoutReset;
      s_stream_route_d        = 4'd0;
      s_mc_cfg_d              = '0;
      s_job_cfg_d             = '0;
      s_ring_cfg_d            = RingReset;
      s_kws_model_cfg_d       = '0;
      s_kws_cfg_d             = KwsConfigReset[15:0];
      s_stream_watermark_d    = 16'd0;
      s_perf_en_d             = 1'b0;
      s_perf_snapshot_valid_d = 1'b0;
      if (resource_reset_apply_i && s_err_stat_q[`APB4_APU__ERROR_VALID] &&
          (s_err_stat_q[6:1] == `APB4_APU__ERROR_CODE_RESOURCE_RESET)) begin
        s_err_stat_d                              = s_err_stat_q;
        s_err_addr_d                              = s_err_addr_q;
        s_err_detail_d                            = s_err_detail_q;
        s_irq_state_d[`APB4_APU__IRQ_FIRST_ERROR] = 1'b1;
      end else if (resource_reset_apply_i && fault_valid_i &&
                   (fault_code_i == `APB4_APU__ERROR_CODE_RESOURCE_RESET)) begin
        s_err_stat_d = 32'd1 | (32'(fault_code_i) << `APB4_APU__ERROR_CODE) |
            (32'(fault_stage_i) << `APB4_APU__ERROR_STAGE) |
            (32'(fault_resp_i) << `APB4_APU__ERROR_AXI_RESPONSE) |
            (32'(fault_index_i) << `APB4_APU__ERROR_DESCRIPTOR_INDEX);
        s_err_addr_d = fault_addr_i;
        s_err_detail_d = fault_detail_i;
        s_irq_state_d[`APB4_APU__IRQ_FIRST_ERROR] = 1'b1;
      end
    end
  end

  dffr #(
      .DATA_WIDTH(1)
  ) u_ready_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_apb4_ready_d),
      .dat_o  (s_apb4_ready_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_resp_err_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_apb4_resp_err_d),
      .dat_o  (s_apb4_resp_err_q)
  );
  dffer #(
      .DATA_WIDTH(32)
  ) u_rdata_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_req_accept && !apb4.pwrite),
      .dat_i  (s_read_data),
      .dat_o  (s_apb4_rdata_q)
  );
  dffr #(
      .DATA_WIDTH(11)
  ) u_irq_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_irq_state_d),
      .dat_o  (s_irq_state_q)
  );
  dffr #(
      .DATA_WIDTH(11)
  ) u_irq_enable_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_irq_en_d),
      .dat_o  (s_irq_en_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_error_status_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_stat_d),
      .dat_o  (s_err_stat_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_error_address_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_addr_d),
      .dat_o  (s_err_addr_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_error_detail_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_detail_d),
      .dat_o  (s_err_detail_q)
  );
  dffrc #(
      .DATA_WIDTH(2 * 32),
      .RESET_VAL ({TimeoutReset, TimeoutReset})
  ) u_timeout_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_timeout_d),
      .dat_o  (s_timeout_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_stream_route_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_stream_route_d),
      .dat_o  (s_stream_route_q)
  );
  dffrc #(
      .DATA_WIDTH(4 * 32),
      .RESET_VAL (AclReset)
  ) u_acl_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_acl_d),
      .dat_o  (s_acl_q)
  );
  dffr #(
      .DATA_WIDTH(3 * 32)
  ) u_mc_cfg_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_mc_cfg_d),
      .dat_o  (s_mc_cfg_q)
  );
  dffr #(
      .DATA_WIDTH(8 * 32)
  ) u_job_cfg_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_job_cfg_d),
      .dat_o  (s_job_cfg_q)
  );
  dffrc #(
      .DATA_WIDTH(5 * 32),
      .RESET_VAL (RingReset)
  ) u_ring_cfg_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ring_cfg_d),
      .dat_o  (s_ring_cfg_q)
  );
  dffr #(
      .DATA_WIDTH(3 * 32)
  ) u_kws_model_cfg_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_kws_model_cfg_d),
      .dat_o  (s_kws_model_cfg_q)
  );
  dffrc #(
      .DATA_WIDTH(16),
      .RESET_VAL (KwsConfigReset[15:0])
  ) u_kws_cfg_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_kws_cfg_d),
      .dat_o  (s_kws_cfg_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_stream_watermark_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_stream_watermark_d),
      .dat_o  (s_stream_watermark_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_perf_enable_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_en_d),
      .dat_o  (s_perf_en_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_perf_snapshot_valid_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_snapshot_valid_d),
      .dat_o  (s_perf_snapshot_valid_q)
  );

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_perf_snapshot_q <= '0;
    end else if (s_soft_reset || resource_reset_apply_i || s_cnt_clear) begin
      s_perf_snapshot_q <= '0;
    end else if (s_write && !s_write_err && (s_offset == `APB4_APU__PERF_CONTROL) &&
                 s_merged_write[`APB4_APU__PERF_CONTROL_SNAPSHOT]) begin
      s_perf_snapshot_q[0] <= perf_active_cycles_i;
      s_perf_snapshot_q[1] <= perf_input_bytes_i;
      s_perf_snapshot_q[2] <= perf_output_bytes_i;
      s_perf_snapshot_q[3] <= 64'd0;
      s_perf_snapshot_q[4] <= perf_dma_read_stalls_i;
      s_perf_snapshot_q[5] <= perf_dma_write_stalls_i;
      s_perf_snapshot_q[6] <= perf_stream_stalls_i;
      s_perf_snapshot_q[7] <= perf_sequencer_instr_i;
      s_perf_snapshot_q[8] <= 64'd0;
      s_perf_snapshot_q[9] <= perf_faults_i;
    end
  end
endmodule
