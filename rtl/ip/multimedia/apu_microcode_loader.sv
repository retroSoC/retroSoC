// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "apu_define.svh"

module apu_microcode_loader #(
    parameter int unsigned PathStackDepth = 2048,
    parameter bit          EnableP4       = 1'b0,
    parameter bit          EnableP5       = 1'b0
) (
    // verilog_format: off -- preserve command, DMA, store, and result columns
    input  logic                  clk_i,
    input  logic                  rst_n_i,
    input  logic                  start_i,
    input  logic                  abort_i,
    input  logic                  resource_reset_i,
    input  logic                  soft_reset_i,
    input  logic                  counter_clear_i,
    input  logic [31:0]           image_addr_i,
    input  logic [31:0]           image_size_i,
    input  logic [31:0]           expected_crc_i,
    output logic                  dma_request_valid_o,
    input  logic                  dma_request_ready_i,
    output logic [31:0]           dma_request_addr_o,
    output logic [31:0]           dma_request_bytes_o,
    input  logic [31:0]           dma_data_i,
    input  logic [3:0]            dma_keep_i,
    input  logic                  dma_last_i,
    input  logic                  dma_valid_i,
    output logic                  dma_ready_o,
    input  logic                  dma_done_i,
    input  logic                  dma_err_i,
    input  logic [5:0]            dma_err_code_i,
    input  logic [3:0]            dma_err_stage_i,
    input  logic [1:0]            dma_err_resp_i,
    input  logic [31:0]           dma_err_addr_i,
    output logic                  store_active_o,
    output logic                  store_read_o,
    output logic                  store_write_o,
    output logic [10:0]           store_addr_o,
    output logic [63:0]           store_data_o,
    input  logic [63:0]           store_data_i,
    input  logic                  store_valid_i,
    output logic                  local_write_o,
    output logic [16:0]           local_addr_o,
    output logic [31:0]           local_data_o,
    output logic [3:0]            local_strb_o,
    output logic [15:0]           table_bytes_o,
    output logic [7:0]            stat_o,
    output logic [31:0]           abi_o,
    output logic [63:0]           build_id_o,
    output logic                  lock_o,
    output logic [31:0]           actual_crc_o,
    output logic [31:0]           load_count_o,
    output logic [2:0][10:0]      entry_pc_o,
    output logic [2:0][10:0]      entry_first_o,
    output logic [2:0][10:0]      entry_last_o,
    output logic [2:0][15:0]      entry_max_loop_o,
    output logic [2:0][23:0]      entry_max_retired_o,
    output logic [2:0][16:0]      entry_scratch_base_o,
    output logic [2:0][16:0]      entry_scratch_bytes_o,
    output logic [2:0][31:0]      entry_primitive_mask_o,
    output logic [2:0][15:0]      entry_table_offset_o,
    output logic [2:0][15:0]      entry_table_bytes_o,
    output logic                  load_done_o,
    output logic                  abort_done_o,
    output logic                  fault_valid_o,
    output logic [5:0]            fault_code_o,
    output logic [3:0]            fault_stage_o,
    output logic [1:0]            fault_resp_o,
    output logic [31:0]           fault_addr_o,
    output logic [31:0]           fault_detail_o,
    output logic                  idle_o
    // verilog_format: on
);
  import apu_microcode_pkg::*;

  localparam logic [11:0] PathStackLimit = 12'(PathStackDepth);

`ifndef SYNTHESIS
  initial begin
    if (EnableP5 && !EnableP4) $fatal(1, "apu_microcode_loader: P5 requires the P4 profile");
  end
`endif

  typedef enum logic [4:0] {
    Idle,
    HeaderDmaRequest,
    HeaderReceive,
    HeaderValidate,
    PayloadDmaRequest,
    PayloadReceive,
    Validate,
    ScanRequest,
    ScanWait,
    ScanCheck,
    PathRequest,
    PathWait,
    PathCheck,
    PathPop,
    PathPopLoad,
    Finish,
    CancelWait,
    DescriptorDmaRequest,
    DescriptorReceive,
    DescriptorValidate
  } loader_state_e;

  loader_state_e              s_state_q;
  logic          [15:0][31:0] s_header_q;
  logic          [23:0][31:0] s_entry_word_q;
  logic [31:0] s_source_addr_q, s_source_size_q, s_expected_crc_q;
  logic [31:0] s_byte_offset_q;
  logic [31:0] s_crc_q;
  logic [31:0] s_instruction_low_q;
  logic        s_transfer_err_q;
  logic        s_padding_err_q;
  logic [31:0] s_padding_addr_q, s_padding_detail_q;
  logic s_valid_q, s_lock_q;
  logic [5:0] s_err_bits_q;
  logic [31:0] s_abi_q, s_actual_crc_q, s_load_count_q;
  logic [63:0]       s_build_id_q;
  logic [ 1:0]       s_scan_entry_q;
  logic [10:0]       s_scan_pc_q;
  logic [ 2:0]       s_call_depth_q;
  logic [ 3:0][10:0] s_return_pc_q;
  logic [ 3:0]       s_loop_active_q;
  logic [ 3:0][10:0] s_loop_start_q;
  logic [ 2:0]       s_loop_nesting_depth_q;
  logic [ 3:0][ 1:0] s_loop_nesting_slot_q;
  logic [ 1:0]       s_loop_top_slot;
  logic [11:0]       s_path_stack_count_q;
  logic s_path_stack_cs, s_path_stack_write, s_path_stack_push;
  logic [10:0] s_path_stack_addr;
  logic [63:0] s_path_stack_write_data, s_path_stack_read_data;
  logic        s_path_stop_valid_q;
  logic [10:0] s_path_stop_pc_q;
  logic s_scan_control_err_q, s_scan_capability_err_q;
  logic [31:0] s_scan_control_addr_q, s_scan_control_detail_q;
  logic [31:0] s_scan_capability_addr_q, s_scan_capability_detail_q;
  logic s_cancel_resource_q, s_cancel_abort_q;

  logic s_header_err, s_header_range_err, s_range_err, s_table_err, s_capability_err;
  logic s_table_header_err;
  logic [31:0] s_header_addr, s_header_detail;
  logic [31:0] s_header_range_addr, s_header_range_detail;
  logic [31:0] s_range_addr, s_range_detail;
  logic [31:0] s_table_addr, s_table_detail;
  logic [31:0] s_capability_addr, s_capability_detail;
  logic [32:0] s_instruction_end, s_entry_end, s_table_end;
  logic [31:0] s_header_transfer_bytes, s_descriptor_transfer_bytes;
  logic s_data_accept, s_data_in_instruction, s_data_in_entry, s_data_in_table;
  logic        s_data_in_region;
  logic [11:0] s_instruction_word_relative;
  logic [ 4:0] s_entry_word_relative;
  logic [63:0] s_scan_instruction;
  logic [3:0] s_scan_class, s_scan_opcode, s_scan_predicate;
  logic [ 7:0] s_scan_aux;
  logic [10:0] s_scan_immediate;
  logic        s_scan_last;
  logic s_scan_instruction_err, s_scan_target_err, s_scan_call_err, s_scan_loop_err;
  logic        s_scan_unclosed_loop_err;
  logic        s_path_err;
  logic [ 7:0] s_path_err_reason;
  logic [10:0] s_path_err_pc;
  logic        s_path_fallthrough;
  logic        s_scan_capability_instruction;
  logic [11:0] s_scan_target;

  assign dma_request_valid_o = s_state_q inside {
    HeaderDmaRequest, DescriptorDmaRequest, PayloadDmaRequest
  };
  assign dma_request_addr_o = (s_state_q == HeaderDmaRequest) ? s_source_addr_q :
      ((s_state_q == DescriptorDmaRequest) ? (s_source_addr_q + s_header_q[7]) :
       (s_source_addr_q + 32'd64));
  assign dma_request_bytes_o = (s_state_q == HeaderDmaRequest) ? s_header_transfer_bytes :
      ((s_state_q == DescriptorDmaRequest) ? s_descriptor_transfer_bytes :
       (s_source_size_q - 32'd64));
  assign dma_ready_o = s_state_q inside {HeaderReceive, DescriptorReceive, PayloadReceive};
  assign s_data_accept = dma_valid_i && dma_ready_o;
  assign s_header_transfer_bytes = (s_source_size_q < 32'd64) ? s_source_size_q : 32'd64;
  assign s_descriptor_transfer_bytes = 32'd96;
  assign store_active_o = s_state_q inside {
    PayloadReceive, ScanRequest, ScanWait, ScanCheck, PathRequest, PathWait, PathCheck
  };
  assign store_read_o = s_state_q inside {ScanRequest, PathRequest};
  assign store_write_o = (s_state_q == PayloadReceive) && s_data_accept &&
      s_data_in_instruction && s_instruction_word_relative[0];
  assign store_addr_o = (s_state_q inside {
    ScanRequest, ScanWait, ScanCheck, PathRequest, PathWait, PathCheck
  }) ?
      s_scan_pc_q : s_instruction_word_relative[11:1];
  assign store_data_o = {dma_data_i, s_instruction_low_q};
  assign local_write_o = EnableP4 && (s_state_q == PayloadReceive) && s_data_accept &&
      s_data_in_table;
  assign local_addr_o = 17'(s_byte_offset_q - s_header_q[5]);
  assign local_data_o = dma_data_i;
  assign local_strb_o = dma_keep_i;
  assign table_bytes_o = s_header_q[6][15:0];
  assign idle_o = s_state_q == Idle;
  assign stat_o = {
    s_err_bits_q[5],
    s_err_bits_q[4],
    s_err_bits_q[3],
    s_err_bits_q[2],
    s_err_bits_q[1],
    s_err_bits_q[0],
    s_valid_q,
    !idle_o
  };
  assign abi_o = s_abi_q;
  assign build_id_o = s_build_id_q;
  assign lock_o = s_lock_q;
  assign actual_crc_o = s_actual_crc_q;
  assign load_count_o = s_load_count_q;

  for (genvar entry = 0; entry < 3; entry++) begin : gen_entry_outputs
    assign entry_pc_o[entry]             = s_entry_word_q[entry*8][14:4];
    assign entry_first_o[entry]          = s_entry_word_q[(entry*8)+1][10:0];
    assign entry_last_o[entry]           = s_entry_word_q[(entry*8)+1][26:16];
    assign entry_max_loop_o[entry]       = s_entry_word_q[(entry*8)+4][15:0];
    assign entry_max_retired_o[entry]    = s_entry_word_q[(entry*8)+5][23:0];
    assign entry_scratch_base_o[entry]   = s_entry_word_q[(entry*8)+2][16:0];
    assign entry_scratch_bytes_o[entry]  = s_entry_word_q[(entry*8)+3][16:0];
    assign entry_primitive_mask_o[entry] = s_entry_word_q[(entry*8)+6];
    assign entry_table_offset_o[entry]   = s_entry_word_q[(entry*8)+7][15:0];
    assign entry_table_bytes_o[entry]    = s_entry_word_q[(entry*8)+7][31:16];
  end

  assign s_instruction_end = {1'b0, s_header_q[4]} + ({1'b0, s_header_q[3]} << 3);
  assign s_entry_end = {1'b0, s_header_q[7]} + 33'd96;
  assign s_table_end = {1'b0, s_header_q[5]} + {1'b0, s_header_q[6]};
  assign s_instruction_word_relative = 12'((s_byte_offset_q - s_header_q[4]) >> 2);
  assign s_entry_word_relative = 5'((s_byte_offset_q - s_header_q[7]) >> 2);
  assign s_data_in_instruction = (s_byte_offset_q >= s_header_q[4]) &&
      ({1'b0, s_byte_offset_q} < s_instruction_end);
  assign s_data_in_entry = (s_byte_offset_q >= s_header_q[7]) &&
      ({1'b0, s_byte_offset_q} < s_entry_end);
  assign s_data_in_table = (s_header_q[6] != 32'd0) &&
      (s_byte_offset_q >= s_header_q[5]) && ({1'b0, s_byte_offset_q} < s_table_end);
  assign s_data_in_region = s_data_in_instruction || s_data_in_entry || s_data_in_table;

  always_comb begin
    s_header_err    = 1'b0;
    s_header_addr   = s_source_addr_q;
    s_header_detail = s_header_q[0];
    if (s_header_q[0] != `APB4_APU__APUMC_MAGIC) begin
      s_header_err = 1'b1;
    end else if (s_header_q[1] != `APB4_APU__APUMC_ABI) begin
      s_header_err    = 1'b1;
      s_header_addr   = s_source_addr_q + 32'd4;
      s_header_detail = s_header_q[1];
    end else if ((s_header_q[2] != s_source_size_q) || (s_header_q[2] < 32'd160)) begin
      s_header_err    = 1'b1;
      s_header_addr   = s_source_addr_q + 32'd8;
      s_header_detail = s_header_q[2];
    end else if (s_header_q[8] != 32'd3) begin
      s_header_err    = 1'b1;
      s_header_addr   = s_source_addr_q + 32'd32;
      s_header_detail = s_header_q[8];
    end else if (s_header_q[14] != 32'd0) begin
      s_header_err    = 1'b1;
      s_header_addr   = s_source_addr_q + 32'd56;
      s_header_detail = s_header_q[14];
    end else if (s_header_q[15] != 32'd0) begin
      s_header_err    = 1'b1;
      s_header_addr   = s_source_addr_q + 32'd60;
      s_header_detail = s_header_q[15];
    end else if (s_padding_err_q) begin
      s_header_err    = 1'b1;
      s_header_addr   = s_padding_addr_q;
      s_header_detail = s_padding_detail_q;
    end
  end

  always_comb begin
    s_header_range_err    = 1'b0;
    s_header_range_addr   = s_source_addr_q + 32'd12;
    s_header_range_detail = s_header_q[3];
    if ((s_header_q[3] == 32'd0) || (s_header_q[3] > 32'd2048)) begin
      s_header_range_err = 1'b1;
    end else if ((s_header_q[4][5:0] != 6'd0) || (s_header_q[4] < 32'd64) ||
                 s_instruction_end[32] ||
                 (s_instruction_end > {1'b0, s_source_size_q})) begin
      s_header_range_err    = 1'b1;
      s_header_range_addr   = s_source_addr_q + 32'd16;
      s_header_range_detail = s_header_q[4];
    end else if ((s_header_q[5][1:0] != 2'd0) ||
                 ({1'b0, s_header_q[5]} > {1'b0, s_source_size_q})) begin
      s_header_range_err    = 1'b1;
      s_header_range_addr   = s_source_addr_q + 32'd20;
      s_header_range_detail = s_header_q[5];
    end else if ((s_header_q[6] != 32'd0) &&
                 ((s_header_q[5] < 32'd64) || s_table_end[32] ||
                  (s_table_end > {1'b0, s_source_size_q}))) begin
      s_header_range_err    = 1'b1;
      s_header_range_addr   = s_source_addr_q + 32'd20;
      s_header_range_detail = s_header_q[5];
    end else if ((s_header_q[7][4:0] != 5'd0) || (s_header_q[7] < 32'd64) ||
                 s_entry_end[32] || (s_entry_end > {1'b0, s_source_size_q})) begin
      s_header_range_err    = 1'b1;
      s_header_range_addr   = s_source_addr_q + 32'd28;
      s_header_range_detail = s_header_q[7];
    end else if (!((s_instruction_end <= {1'b0, s_header_q[7]}) ||
                   (s_entry_end <= {1'b0, s_header_q[4]}))) begin
      s_header_range_err    = 1'b1;
      s_header_range_addr   = s_source_addr_q + 32'd16;
      s_header_range_detail = s_header_q[4];
    end else if ((s_header_q[6] != 32'd0) &&
                 (!((s_table_end <= {1'b0, s_header_q[4]}) ||
                    ({1'b0, s_header_q[5]} >= s_instruction_end)) ||
                  !((s_table_end <= {1'b0, s_header_q[7]}) ||
                    ({1'b0, s_header_q[5]} >= s_entry_end)))) begin
      s_header_range_err    = 1'b1;
      s_header_range_addr   = s_source_addr_q + 32'd20;
      s_header_range_detail = s_header_q[5];
    end else if ((!EnableP4 && (s_header_q[10] != 32'd0)) ||
                 (EnableP4 && (s_header_q[10] > 32'h0000_6000))) begin
      s_header_range_err    = 1'b1;
      s_header_range_addr   = s_source_addr_q + 32'd40;
      s_header_range_detail = s_header_q[10];
    end
  end

  always_comb begin
    logic [31:0] s_scratch_end;
    logic [31:0] s_max_scratch_end;
    s_range_err       = s_header_range_err;
    s_range_addr      = s_header_range_addr;
    s_range_detail    = s_header_range_detail;
    s_max_scratch_end = 32'd0;
    for (int unsigned entry = 0; entry < 3; entry++) begin
      s_scratch_end = s_entry_word_q[(entry*8)+2] + s_entry_word_q[(entry*8)+3];
      if (s_scratch_end > s_max_scratch_end) s_max_scratch_end = s_scratch_end;
      if (!s_range_err && ((s_entry_word_q[entry*8][31:15] != 17'd0) ||
                           (s_entry_word_q[entry*8][3:0] != 4'(entry)))) begin
        s_range_err    = 1'b1;
        s_range_addr   = s_source_addr_q + s_header_q[7] + 32'(entry * 32);
        s_range_detail = s_entry_word_q[entry*8];
      end else if (!s_range_err &&
                   ((s_entry_word_q[(entry*8)+1][31:27] != 5'd0) ||
                    (s_entry_word_q[(entry*8)+1][15:11] != 5'd0) ||
                    (s_entry_word_q[(entry*8)+1][10:0] >
                     s_entry_word_q[entry*8][14:4]) ||
                    (s_entry_word_q[entry*8][14:4] >
                     s_entry_word_q[(entry*8)+1][26:16]) ||
                    ({21'd0, s_entry_word_q[(entry*8)+1][26:16]} >= s_header_q[3]))) begin
        s_range_err    = 1'b1;
        s_range_addr   = s_source_addr_q + s_header_q[7] + 32'(entry * 32) + 32'd4;
        s_range_detail = s_entry_word_q[(entry*8)+1];
      end else if (!s_range_err &&
                   ((!EnableP4 && (s_entry_word_q[(entry*8)+2] != 32'd0)) ||
                    (EnableP4 && ((s_entry_word_q[(entry*8)+2][31:17] != 15'd0) ||
                                  (s_entry_word_q[(entry*8)+2][1:0] != 2'd0) ||
                                  (s_entry_word_q[(entry*8)+3][31:17] != 15'd0) ||
                                  (s_entry_word_q[(entry*8)+3][1:0] != 2'd0) ||
                                  (s_scratch_end > 32'h0000_6000) ||
                                  ((s_entry_word_q[(entry*8)+3] != 32'd0) &&
                                   (s_entry_word_q[(entry*8)+2] < s_header_q[6])))))) begin
        s_range_err    = 1'b1;
        s_range_addr   = s_source_addr_q + s_header_q[7] + 32'(entry * 32) + 32'd8;
        s_range_detail = s_entry_word_q[(entry*8)+2];
      end else if (!s_range_err && !EnableP4 && (s_entry_word_q[(entry*8)+3] != 32'd0)) begin
        s_range_err    = 1'b1;
        s_range_addr   = s_source_addr_q + s_header_q[7] + 32'(entry * 32) + 32'd12;
        s_range_detail = s_entry_word_q[(entry*8)+3];
      end else if (!s_range_err &&
                   ((s_entry_word_q[(entry*8)+4][31:16] != 16'd0) ||
                    (s_entry_word_q[(entry*8)+4][15:0] == 16'd0))) begin
        s_range_err    = 1'b1;
        s_range_addr   = s_source_addr_q + s_header_q[7] + 32'(entry * 32) + 32'd16;
        s_range_detail = s_entry_word_q[(entry*8)+4];
      end else if (!s_range_err &&
                   ((s_entry_word_q[(entry*8)+5][31:24] != 8'd0) ||
                    (s_entry_word_q[(entry*8)+5][23:0] == 24'd0))) begin
        s_range_err    = 1'b1;
        s_range_addr   = s_source_addr_q + s_header_q[7] + 32'(entry * 32) + 32'd20;
        s_range_detail = s_entry_word_q[(entry*8)+5];
      end
    end
    if (!s_range_err && EnableP4 && (s_header_q[10] != s_max_scratch_end)) begin
      s_range_err    = 1'b1;
      s_range_addr   = s_source_addr_q + 32'd40;
      s_range_detail = s_header_q[10];
    end
  end

  always_comb begin
    logic [16:0] s_entry_table_end;
    s_table_err = 1'b0;
    s_table_addr = s_source_addr_q + 32'd20;
    s_table_detail = s_header_q[5];
    s_table_header_err = EnableP4 &&
        ((s_header_q[6] > 32'h0000_6000) || (s_header_q[6][1:0] != 2'd0));
    if (!EnableP4 && (s_header_q[5] != 32'd0)) begin
      s_table_err = 1'b1;
    end else if (!EnableP4 && (s_header_q[6] != 32'd0)) begin
      s_table_err    = 1'b1;
      s_table_addr   = s_source_addr_q + 32'd24;
      s_table_detail = s_header_q[6];
    end else begin
      for (int unsigned entry = 0; entry < 3; entry++) begin
        s_entry_table_end = {1'b0, s_entry_word_q[(entry*8)+7][15:0]} +
            {1'b0, s_entry_word_q[(entry*8)+7][31:16]};
        if (!s_table_err &&
            ((!EnableP4 && (s_entry_word_q[(entry*8)+7] != 32'd0)) ||
             (EnableP4 && ((s_entry_word_q[(entry*8)+7][1:0] != 2'd0) ||
                           (s_entry_word_q[(entry*8)+7][17:16] != 2'd0) ||
                           (s_entry_table_end > {1'b0, s_header_q[6][15:0]}))))) begin
          s_table_err    = 1'b1;
          s_table_addr   = s_source_addr_q + s_header_q[7] + 32'(entry * 32) + 32'd28;
          s_table_detail = s_entry_word_q[(entry*8)+7];
        end
      end
    end
  end

  always_comb begin
    logic [31:0] s_entry_mask;
    s_entry_mask        = s_entry_word_q[6] | s_entry_word_q[14] | s_entry_word_q[22];
    s_capability_err    = 1'b0;
    s_capability_addr   = s_source_addr_q + 32'd36;
    s_capability_detail = s_header_q[9] ^ s_entry_mask;
    if (s_header_q[9] != s_entry_mask) begin
      s_capability_err = 1'b1;
    end else if ((!EnableP4 && (s_header_q[9] != 32'd0)) ||
                 (EnableP4 && !EnableP5 &&
                  ((s_header_q[9] & ~`APB4_APU__APUMC_P4_PRIMITIVE_MASK) != 32'd0)) ||
                 (EnableP5 &&
                  ((s_header_q[9] & ~`APB4_APU__APUMC_P5_PRIMITIVE_MASK) != 32'd0))) begin
      s_capability_err    = 1'b1;
      s_capability_detail = s_header_q[9];
    end else begin
      for (int unsigned entry = 0; entry < 3; entry++) begin
        if (!s_capability_err &&
            ((!EnableP4 && (s_entry_word_q[(entry*8)+6] != 32'd0)) ||
             (EnableP4 && !EnableP5 && ((s_entry_word_q[(entry*8)+6] &
                                         ~`APB4_APU__APUMC_P4_PRIMITIVE_MASK) != 32'd0)) ||
             (EnableP5 && ((s_entry_word_q[(entry*8)+6] &
                            ~`APB4_APU__APUMC_P5_PRIMITIVE_MASK) != 32'd0)))) begin
          s_capability_err    = 1'b1;
          s_capability_addr   = s_source_addr_q + s_header_q[7] + 32'(entry * 32) + 32'd24;
          s_capability_detail = s_entry_word_q[(entry*8)+6];
        end
      end
    end
  end

  assign s_scan_instruction = store_data_i;
  assign s_scan_class = s_scan_instruction[63:60];
  assign s_scan_opcode = s_scan_instruction[59:56];
  assign s_scan_predicate = s_scan_instruction[55:52];
  assign s_scan_aux = s_scan_instruction[39:32];
  assign s_scan_immediate = s_scan_instruction[10:0];
  assign s_scan_last = s_scan_pc_q == entry_last_o[s_scan_entry_q];
  assign s_scan_target = {1'b0, s_scan_pc_q} + 1'b1 + {1'b0, s_scan_immediate};
  assign s_path_stack_push = (s_state_q == PathCheck) && !s_path_err &&
      (s_scan_predicate != 4'd0) && (s_scan_class == 4'd0) &&
      (s_scan_opcode inside {4'd3, 4'd4}) && (s_path_stack_count_q < PathStackLimit);
  assign s_path_stack_cs = s_path_stack_push ||
      ((s_state_q == PathPop) && (s_path_stack_count_q != 12'd0));
  assign s_path_stack_write = s_path_stack_push;
  assign s_path_stack_addr = s_path_stack_push ?
      s_path_stack_count_q[10:0] : s_path_stack_count_q[10:0] - 1'b1;
  assign s_path_stack_write_data = {
    2'b10, s_loop_active_q, s_return_pc_q, s_call_depth_q, s_scan_pc_q + 1'b1
  };

`ifdef HAVE_SRAM_MACRO
  logic s_path_stack_read_bank_q;
  logic [1:0][31:0] s_path_stack_low_data, s_path_stack_high_data;

  tc_sram_1024x32 u_path_stack_low_bank0 (
      .clk_i (clk_i),
      .cs_i  (s_path_stack_cs && !s_path_stack_addr[10]),
      .addr_i(s_path_stack_addr[9:0]),
      .data_i(s_path_stack_write_data[31:0]),
      .mask_i(4'hf),
      .wren_i(s_path_stack_write),
      .data_o(s_path_stack_low_data[0])
  );
  tc_sram_1024x32 u_path_stack_high_bank0 (
      .clk_i (clk_i),
      .cs_i  (s_path_stack_cs && !s_path_stack_addr[10]),
      .addr_i(s_path_stack_addr[9:0]),
      .data_i(s_path_stack_write_data[63:32]),
      .mask_i(4'hf),
      .wren_i(s_path_stack_write),
      .data_o(s_path_stack_high_data[0])
  );
  tc_sram_1024x32 u_path_stack_low_bank1 (
      .clk_i (clk_i),
      .cs_i  (s_path_stack_cs && s_path_stack_addr[10]),
      .addr_i(s_path_stack_addr[9:0]),
      .data_i(s_path_stack_write_data[31:0]),
      .mask_i(4'hf),
      .wren_i(s_path_stack_write),
      .data_o(s_path_stack_low_data[1])
  );
  tc_sram_1024x32 u_path_stack_high_bank1 (
      .clk_i (clk_i),
      .cs_i  (s_path_stack_cs && s_path_stack_addr[10]),
      .addr_i(s_path_stack_addr[9:0]),
      .data_i(s_path_stack_write_data[63:32]),
      .mask_i(4'hf),
      .wren_i(s_path_stack_write),
      .data_o(s_path_stack_high_data[1])
  );

  assign s_path_stack_read_data = {
    s_path_stack_high_data[s_path_stack_read_bank_q],
    s_path_stack_low_data[s_path_stack_read_bank_q]
  };
  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_path_stack_read_bank_q <= 1'b0;
    end else if (s_path_stack_cs && !s_path_stack_write) begin
      s_path_stack_read_bank_q <= s_path_stack_addr[10];
    end
  end
`else
  logic [63:0] s_path_stack_mem         [0:PathStackDepth-1];
  logic [63:0] s_path_stack_read_data_q;

  assign s_path_stack_read_data = s_path_stack_read_data_q;
  always_ff @(posedge clk_i) begin
    if (s_path_stack_cs) begin
      if (s_path_stack_write) begin
        s_path_stack_mem[s_path_stack_addr] <= s_path_stack_write_data;
      end else begin
        s_path_stack_read_data_q <= s_path_stack_mem[s_path_stack_addr];
      end
    end
  end
`endif
  always_comb begin
    s_loop_top_slot = 2'd0;
    if (s_loop_nesting_depth_q != 3'd0) begin
      s_loop_top_slot = s_loop_nesting_slot_q[s_loop_nesting_depth_q-1'b1];
    end
  end
  assign s_scan_instruction_err = !instruction_encoding_valid(
      s_scan_instruction
  ) || (s_scan_class >= 4'd7);
  assign s_scan_target_err = (s_scan_class == 4'd0) &&
      (s_scan_opcode inside {4'd3, 4'd4}) &&
      (s_scan_target[11] || (s_scan_target[10:0] < entry_first_o[s_scan_entry_q]) ||
       (s_scan_target[10:0] > entry_last_o[s_scan_entry_q]));
  assign s_scan_call_err = (s_state_q == PathCheck) && (s_scan_class == 4'd0) &&
      (((s_scan_opcode == 4'd4) && (s_call_depth_q == 3'd4)) ||
       ((s_scan_opcode == 4'd5) && (s_call_depth_q == 3'd0)));
  assign s_scan_loop_err = (s_state_q == ScanCheck) && (s_scan_class == 4'd0) &&
      (((s_scan_opcode == 4'd6) && s_loop_active_q[s_scan_aux[1:0]]) ||
       ((s_scan_opcode == 4'd7) &&
        (!s_loop_active_q[s_scan_aux[1:0]] ||
         (s_loop_nesting_depth_q == 3'd0) || (s_loop_top_slot != s_scan_aux[1:0]) ||
         ({1'b0, s_scan_pc_q} + 1'b1 < {1'b0, s_scan_immediate}) ||
         ((s_scan_pc_q + 1'b1 - s_scan_immediate) !=
          s_loop_start_q[s_scan_aux[1:0]]))));
  assign s_scan_unclosed_loop_err = (s_state_q == ScanCheck) && s_scan_last &&
      (((s_scan_class == 4'd0) && (s_scan_opcode == 4'd7) && !s_scan_loop_err) ?
       ((s_loop_active_q & ~(4'b0001 << s_scan_aux[1:0])) != 4'd0) :
       ((s_loop_active_q != 4'd0) ||
        ((s_scan_class == 4'd0) && (s_scan_opcode == 4'd6))));
  // verilog_format: off -- preserve the P3/P4/P5 capability decision tree
  always_comb begin
    s_scan_capability_instruction = 1'b0;
    if (!EnableP4) begin
      s_scan_capability_instruction = ((s_scan_class >= 4'd2) && (s_scan_class <= 4'd6)) ||
          ((s_scan_class == 4'd0) && (s_scan_opcode == 4'd8));
    end else if (!EnableP5) begin
      s_scan_capability_instruction = (s_scan_class == 4'd6) ||
          ((s_scan_class == 4'd0) && (s_scan_opcode == 4'd8) &&
           !(s_scan_aux inside {8'd1, 8'd2, 8'd3})) ||
          (!((s_scan_class == 4'd0) && (s_scan_opcode == 4'd8) &&
             (s_scan_aux == 8'd1)) &&
           ((instruction_primitive_mask(s_scan_instruction) &
             ~entry_primitive_mask_o[s_scan_entry_q]) != 32'd0)) ||
          (((s_scan_class == 4'd0) && (s_scan_opcode == 4'd8) && (s_scan_aux == 8'd1)) &&
           ((entry_primitive_mask_o[s_scan_entry_q] & 32'h0000_ffc0) == 32'd0));
    end else begin
      s_scan_capability_instruction =
          (!((s_scan_class == 4'd0) && (s_scan_opcode == 4'd8) &&
             (s_scan_aux inside {8'd0, 8'd1})) &&
           !((s_scan_class == 4'd6) && (s_scan_opcode == 4'd3)) &&
           ((instruction_primitive_mask(s_scan_instruction) &
             ~entry_primitive_mask_o[s_scan_entry_q]) != 32'd0)) ||
          (((s_scan_class == 4'd0) && (s_scan_opcode == 4'd8) && (s_scan_aux == 8'd1)) &&
           ((entry_primitive_mask_o[s_scan_entry_q] & 32'h0000_ffc0) == 32'd0)) ||
          ((((s_scan_class == 4'd0) && (s_scan_opcode == 4'd8) && (s_scan_aux == 8'd0)) ||
            ((s_scan_class == 4'd6) && (s_scan_opcode == 4'd3))) &&
           ((entry_primitive_mask_o[s_scan_entry_q] & 32'h0007_0000) == 32'd0));
    end
  end
  // verilog_format: on

  always_comb begin
    s_path_fallthrough = s_scan_predicate != 4'd0;
    if ((s_scan_class >= 4'd1) &&
        (s_scan_class <= (EnableP5 ? 4'd6 : (EnableP4 ? 4'd5 : 4'd1)))) begin
      s_path_fallthrough = 1'b1;
    end else if ((s_scan_class == 4'd0) && (s_scan_opcode inside {4'd0, 4'd6, 4'd7})) begin
      s_path_fallthrough = 1'b1;
    end
    s_path_err        = 1'b0;
    s_path_err_reason = 8'd2;
    s_path_err_pc     = s_scan_pc_q;
    if ((s_scan_pc_q < entry_first_o[s_scan_entry_q]) ||
        (s_scan_pc_q > entry_last_o[s_scan_entry_q])) begin
      s_path_err    = 1'b1;
      s_path_err_pc = entry_pc_o[s_scan_entry_q];
    end else if (s_scan_call_err) begin
      s_path_err        = 1'b1;
      s_path_err_reason = 8'd3;
    end else if ((s_scan_class == 4'd0) && (s_scan_opcode == 4'd6) &&
                 s_loop_active_q[s_scan_aux[1:0]]) begin
      s_path_err        = 1'b1;
      s_path_err_reason = 8'd4;
    end else if ((s_scan_class == 4'd0) && (s_scan_opcode == 4'd7) &&
                 !s_loop_active_q[s_scan_aux[1:0]]) begin
      s_path_err        = 1'b1;
      s_path_err_reason = 8'd4;
    end else if (s_scan_last && s_path_fallthrough) begin
      s_path_err = 1'b1;
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_state_q                  <= Idle;
      s_header_q                 <= '0;
      s_entry_word_q             <= '0;
      s_source_addr_q            <= 32'd0;
      s_source_size_q            <= 32'd0;
      s_expected_crc_q           <= 32'd0;
      s_byte_offset_q            <= 32'd0;
      s_crc_q                    <= 32'hffff_ffff;
      s_instruction_low_q        <= 32'd0;
      s_transfer_err_q           <= 1'b0;
      s_padding_err_q            <= 1'b0;
      s_padding_addr_q           <= 32'd0;
      s_padding_detail_q         <= 32'd0;
      s_valid_q                  <= 1'b0;
      s_lock_q                   <= 1'b0;
      s_err_bits_q               <= 6'd0;
      s_abi_q                    <= 32'd0;
      s_actual_crc_q             <= 32'd0;
      s_load_count_q             <= 32'd0;
      s_build_id_q               <= 64'd0;
      s_scan_entry_q             <= 2'd0;
      s_scan_pc_q                <= 11'd0;
      s_call_depth_q             <= 3'd0;
      s_return_pc_q              <= '0;
      s_loop_active_q            <= 4'd0;
      s_loop_start_q             <= '0;
      s_loop_nesting_depth_q     <= 3'd0;
      s_loop_nesting_slot_q      <= '0;
      s_path_stack_count_q       <= '0;
      s_path_stop_valid_q        <= 1'b0;
      s_path_stop_pc_q           <= 11'd0;
      s_scan_control_err_q       <= 1'b0;
      s_scan_capability_err_q    <= 1'b0;
      s_scan_control_addr_q      <= 32'd0;
      s_scan_control_detail_q    <= 32'd0;
      s_scan_capability_addr_q   <= 32'd0;
      s_scan_capability_detail_q <= 32'd0;
      s_cancel_resource_q        <= 1'b0;
      s_cancel_abort_q           <= 1'b0;
      load_done_o                <= 1'b0;
      abort_done_o               <= 1'b0;
      fault_valid_o              <= 1'b0;
      fault_code_o               <= 6'd0;
      fault_stage_o              <= 4'd0;
      fault_resp_o               <= 2'd0;
      fault_addr_o               <= 32'd0;
      fault_detail_o             <= 32'd0;
    end else begin
      load_done_o   <= 1'b0;
      abort_done_o  <= 1'b0;
      fault_valid_o <= 1'b0;
      if (counter_clear_i && (s_state_q == Idle)) begin
        s_load_count_q <= 32'd0;
      end
      if (soft_reset_i && (s_state_q == Idle)) begin
        s_err_bits_q <= 6'd0;
      end
      if (resource_reset_i && (s_state_q == Idle)) begin
        s_err_bits_q <= 6'd0;
      end

      if ((s_state_q inside {
            HeaderValidate, DescriptorValidate, Validate, ScanRequest, ScanWait, ScanCheck,
            PathRequest, PathWait, PathCheck, PathPop, PathPopLoad, Finish
          }) &&
          (resource_reset_i || abort_i)) begin
        s_state_q      <= Idle;
        s_valid_q      <= 1'b0;
        s_lock_q       <= 1'b0;
        s_err_bits_q   <= 6'd0;
        s_abi_q        <= 32'd0;
        s_build_id_q   <= 64'd0;
        s_actual_crc_q <= 32'd0;
        if (resource_reset_i) begin
          fault_valid_o <= 1'b1;
          fault_code_o  <= `APB4_APU__ERROR_CODE_RESOURCE_RESET;
          fault_stage_o <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
        end else begin
          abort_done_o <= 1'b1;
        end
      end else
        unique case (s_state_q)
          Idle: begin
            if (start_i) begin
              s_state_q               <= HeaderDmaRequest;
              s_header_q              <= '0;
              s_entry_word_q          <= '0;
              s_source_addr_q         <= image_addr_i;
              s_source_size_q         <= image_size_i;
              s_expected_crc_q        <= expected_crc_i;
              s_byte_offset_q         <= 32'd0;
              s_crc_q                 <= 32'hffff_ffff;
              s_transfer_err_q        <= 1'b0;
              s_padding_err_q         <= 1'b0;
              s_valid_q               <= 1'b0;
              s_err_bits_q            <= 6'd0;
              s_abi_q                 <= 32'd0;
              s_build_id_q            <= 64'd0;
              s_actual_crc_q          <= 32'd0;
              s_scan_control_err_q    <= 1'b0;
              s_scan_capability_err_q <= 1'b0;
              s_path_stop_valid_q     <= 1'b0;
              s_path_stop_pc_q        <= 11'd0;
              s_cancel_resource_q     <= 1'b0;
              s_cancel_abort_q        <= 1'b0;
            end
          end
          HeaderDmaRequest, DescriptorDmaRequest, PayloadDmaRequest: begin
            if (resource_reset_i || abort_i) begin
              s_cancel_resource_q <= resource_reset_i;
              s_cancel_abort_q    <= abort_i && !resource_reset_i;
              s_state_q           <= Idle;
              s_valid_q           <= 1'b0;
              s_lock_q            <= 1'b0;
              s_err_bits_q        <= 6'd0;
              s_abi_q             <= 32'd0;
              s_build_id_q        <= 64'd0;
              s_actual_crc_q      <= 32'd0;
              if (resource_reset_i) begin
                fault_valid_o <= 1'b1;
                fault_code_o  <= `APB4_APU__ERROR_CODE_RESOURCE_RESET;
                fault_stage_o <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
              end else begin
                abort_done_o <= 1'b1;
              end
            end else if (dma_request_ready_i) begin
              if (s_state_q == HeaderDmaRequest) begin
                s_state_q <= HeaderReceive;
              end else if (s_state_q == DescriptorDmaRequest) begin
                s_state_q <= DescriptorReceive;
              end else begin
                s_state_q <= PayloadReceive;
              end
            end
          end
          HeaderReceive: begin
            if (resource_reset_i || abort_i) begin
              s_cancel_resource_q <= resource_reset_i;
              s_cancel_abort_q    <= abort_i && !resource_reset_i;
              s_state_q           <= CancelWait;
            end else begin
              if (s_data_accept) begin
                if (dma_last_i != ((s_byte_offset_q + 32'($countones(
                        dma_keep_i
                    ))) == s_header_transfer_bytes)) begin
                  s_transfer_err_q <= 1'b1;
                end
                if (s_byte_offset_q >= s_header_transfer_bytes) begin
                  s_transfer_err_q <= 1'b1;
                end else begin
                  s_header_q[s_byte_offset_q[5:2]] <= dma_data_i;
                end
                s_byte_offset_q <= s_byte_offset_q + 32'($countones(dma_keep_i));
              end
              if (dma_err_i) begin
                s_state_q     <= Idle;
                s_valid_q     <= 1'b0;
                s_lock_q      <= 1'b0;
                s_err_bits_q  <= 6'd0;
                fault_valid_o <= 1'b1;
                fault_code_o  <= dma_err_code_i;
                fault_stage_o <= dma_err_stage_i;
                fault_resp_o  <= dma_err_resp_i;
                fault_addr_o  <= dma_err_addr_i;
              end else if (dma_done_i) begin
                if (s_transfer_err_q || (s_byte_offset_q != s_header_transfer_bytes)) begin
                  s_state_q     <= Idle;
                  s_valid_q     <= 1'b0;
                  s_lock_q      <= 1'b0;
                  s_err_bits_q  <= 6'd0;
                  fault_valid_o <= 1'b1;
                  fault_code_o  <= `APB4_APU__ERROR_CODE_AXI_READ;
                  fault_stage_o <= `APB4_APU__ERROR_STAGE_DMA_READ;
                  fault_addr_o  <= s_source_addr_q + s_byte_offset_q;
                end else begin
                  s_state_q <= HeaderValidate;
                end
              end
            end
          end
          HeaderValidate: begin
            if (s_header_err) begin
              s_state_q       <= Idle;
              s_err_bits_q[0] <= 1'b1;
              fault_valid_o   <= 1'b1;
              fault_code_o    <= `APB4_APU__ERROR_CODE_MICROCODE;
              fault_stage_o   <= `APB4_APU__ERROR_STAGE_LOADER;
              fault_addr_o    <= s_header_addr;
              fault_detail_o  <= s_header_detail;
            end else if (s_header_range_err) begin
              s_state_q       <= Idle;
              s_err_bits_q[1] <= 1'b1;
              fault_valid_o   <= 1'b1;
              fault_code_o    <= `APB4_APU__ERROR_CODE_MICROCODE;
              fault_stage_o   <= `APB4_APU__ERROR_STAGE_LOADER;
              fault_addr_o    <= s_header_range_addr;
              fault_detail_o  <= s_header_range_detail;
            end else if (s_table_header_err) begin
              s_state_q       <= Idle;
              s_err_bits_q[3] <= 1'b1;
              fault_valid_o   <= 1'b1;
              fault_code_o    <= `APB4_APU__ERROR_CODE_MICROCODE;
              fault_stage_o   <= `APB4_APU__ERROR_STAGE_LOADER;
              fault_addr_o    <= s_source_addr_q + 32'd24;
              fault_detail_o  <= s_header_q[6];
            end else begin
              s_transfer_err_q <= 1'b0;
              s_byte_offset_q  <= s_header_q[7];
              s_state_q        <= DescriptorDmaRequest;
            end
          end
          DescriptorReceive: begin
            if (resource_reset_i || abort_i) begin
              s_cancel_resource_q <= resource_reset_i;
              s_cancel_abort_q    <= abort_i && !resource_reset_i;
              s_state_q           <= CancelWait;
            end else begin
              if (s_data_accept) begin
                if (dma_last_i != ((s_byte_offset_q + 32'($countones(
                        dma_keep_i
                    ))) == (s_header_q[7] + s_descriptor_transfer_bytes))) begin
                  s_transfer_err_q <= 1'b1;
                end
                if ((s_byte_offset_q < s_header_q[7]) ||
                    (s_byte_offset_q >= (s_header_q[7] + s_descriptor_transfer_bytes))) begin
                  s_transfer_err_q <= 1'b1;
                end else begin
                  s_entry_word_q[s_entry_word_relative] <= dma_data_i;
                end
                s_byte_offset_q <= s_byte_offset_q + 32'($countones(dma_keep_i));
              end
              if (dma_err_i) begin
                s_state_q     <= Idle;
                s_valid_q     <= 1'b0;
                s_lock_q      <= 1'b0;
                s_err_bits_q  <= 6'd0;
                fault_valid_o <= 1'b1;
                fault_code_o  <= dma_err_code_i;
                fault_stage_o <= dma_err_stage_i;
                fault_resp_o  <= dma_err_resp_i;
                fault_addr_o  <= dma_err_addr_i;
              end else if (dma_done_i) begin
                if (s_transfer_err_q ||
                    (s_byte_offset_q != (s_header_q[7] + s_descriptor_transfer_bytes))) begin
                  s_state_q     <= Idle;
                  s_valid_q     <= 1'b0;
                  s_lock_q      <= 1'b0;
                  s_err_bits_q  <= 6'd0;
                  fault_valid_o <= 1'b1;
                  fault_code_o  <= `APB4_APU__ERROR_CODE_AXI_READ;
                  fault_stage_o <= `APB4_APU__ERROR_STAGE_DMA_READ;
                  fault_addr_o  <= s_source_addr_q + s_byte_offset_q;
                end else begin
                  s_state_q <= DescriptorValidate;
                end
              end
            end
          end
          DescriptorValidate: begin
            if (s_range_err) begin
              s_state_q       <= Idle;
              s_err_bits_q[1] <= 1'b1;
              fault_valid_o   <= 1'b1;
              fault_code_o    <= `APB4_APU__ERROR_CODE_MICROCODE;
              fault_stage_o   <= `APB4_APU__ERROR_STAGE_LOADER;
              fault_addr_o    <= s_range_addr;
              fault_detail_o  <= s_range_detail;
            end else if (EnableP4 && s_table_err) begin
              s_state_q       <= Idle;
              s_err_bits_q[3] <= 1'b1;
              fault_valid_o   <= 1'b1;
              fault_code_o    <= `APB4_APU__ERROR_CODE_MICROCODE;
              fault_stage_o   <= `APB4_APU__ERROR_STAGE_LOADER;
              fault_addr_o    <= s_table_addr;
              fault_detail_o  <= s_table_detail;
            end else begin
              s_byte_offset_q  <= 32'd64;
              s_crc_q          <= 32'hffff_ffff;
              s_transfer_err_q <= 1'b0;
              s_state_q        <= PayloadDmaRequest;
            end
          end
          PayloadReceive: begin
            if (resource_reset_i || abort_i) begin
              s_cancel_resource_q <= resource_reset_i;
              s_cancel_abort_q    <= abort_i && !resource_reset_i;
              s_state_q           <= CancelWait;
            end else begin
              if (s_data_accept) begin
                if (dma_last_i != ((s_byte_offset_q + 32'($countones(
                        dma_keep_i
                    ))) == s_source_size_q)) begin
                  s_transfer_err_q <= 1'b1;
                end
                s_crc_q <= crc32_word(s_crc_q, dma_data_i, dma_keep_i);
                if (s_data_in_instruction && !s_instruction_word_relative[0]) begin
                  s_instruction_low_q <= dma_data_i;
                end
                if (!s_data_in_region && !s_padding_err_q &&
                  ((dma_data_i & {{8{dma_keep_i[3]}}, {8{dma_keep_i[2]}},
                                  {8{dma_keep_i[1]}}, {8{dma_keep_i[0]}}}) != 32'd0)) begin
                  s_padding_err_q    <= 1'b1;
                  s_padding_addr_q   <= s_source_addr_q + s_byte_offset_q;
                  s_padding_detail_q <= dma_data_i;
                end
                s_byte_offset_q <= s_byte_offset_q + 32'($countones(dma_keep_i));
              end
              if (dma_err_i) begin
                s_state_q     <= Idle;
                s_valid_q     <= 1'b0;
                s_lock_q      <= 1'b0;
                s_err_bits_q  <= 6'd0;
                fault_valid_o <= 1'b1;
                fault_code_o  <= dma_err_code_i;
                fault_stage_o <= dma_err_stage_i;
                fault_resp_o  <= dma_err_resp_i;
                fault_addr_o  <= dma_err_addr_i;
              end else if (dma_done_i) begin
                if (s_transfer_err_q || (s_byte_offset_q != s_source_size_q)) begin
                  s_state_q     <= Idle;
                  s_valid_q     <= 1'b0;
                  s_lock_q      <= 1'b0;
                  s_err_bits_q  <= 6'd0;
                  fault_valid_o <= 1'b1;
                  fault_code_o  <= `APB4_APU__ERROR_CODE_AXI_READ;
                  fault_stage_o <= `APB4_APU__ERROR_STAGE_DMA_READ;
                  fault_addr_o  <= s_source_addr_q + s_byte_offset_q;
                end else begin
                  s_state_q <= Validate;
                end
              end
            end
          end
          Validate: begin
            if (s_header_err) begin
              s_state_q       <= Idle;
              s_err_bits_q[0] <= 1'b1;
              fault_valid_o   <= 1'b1;
              fault_code_o    <= `APB4_APU__ERROR_CODE_MICROCODE;
              fault_stage_o   <= `APB4_APU__ERROR_STAGE_LOADER;
              fault_addr_o    <= s_header_addr;
              fault_detail_o  <= s_header_detail;
            end else if (s_range_err) begin
              s_state_q       <= Idle;
              s_err_bits_q[1] <= 1'b1;
              fault_valid_o   <= 1'b1;
              fault_code_o    <= `APB4_APU__ERROR_CODE_MICROCODE;
              fault_stage_o   <= `APB4_APU__ERROR_STAGE_LOADER;
              fault_addr_o    <= s_range_addr;
              fault_detail_o  <= s_range_detail;
            end else begin
              s_actual_crc_q         <= ~s_crc_q;
              s_scan_entry_q         <= 2'd0;
              s_scan_pc_q            <= entry_first_o[0];
              s_call_depth_q         <= 3'd0;
              s_return_pc_q          <= '0;
              s_loop_active_q        <= 4'd0;
              s_loop_start_q         <= '0;
              s_loop_nesting_depth_q <= 3'd0;
              s_loop_nesting_slot_q  <= '0;
              s_path_stack_count_q   <= '0;
              s_path_stop_valid_q    <= 1'b0;
              s_state_q              <= ScanRequest;
            end
          end
          ScanRequest: s_state_q <= ScanWait;
          ScanWait: begin
            if (store_valid_i) s_state_q <= ScanCheck;
          end
          ScanCheck: begin
            if (s_scan_instruction_err || s_scan_target_err || s_scan_loop_err ||
                s_scan_unclosed_loop_err) begin
              s_scan_control_err_q <= 1'b1;
              s_scan_control_addr_q <= s_source_addr_q + s_header_q[4] + {18'd0, s_scan_pc_q, 3'd0};
              s_scan_control_detail_q <= trap_detail(
                  (s_scan_loop_err || s_scan_unclosed_loop_err) ? 8'd4 :
                  (s_scan_instruction_err ? 8'd1 : 8'd2),
                  s_scan_pc_q,
                  s_scan_instruction
              );
              s_scan_pc_q <= entry_pc_o[s_scan_entry_q];
              s_call_depth_q <= 3'd0;
              s_return_pc_q <= '0;
              s_loop_active_q <= 4'd0;
              s_loop_start_q <= '0;
              s_path_stack_count_q <= '0;
              s_path_stop_valid_q <= 1'b1;
              s_path_stop_pc_q <= s_scan_pc_q;
              s_state_q <= PathRequest;
            end else begin
              if (!s_scan_capability_err_q && s_scan_capability_instruction &&
                  instruction_encoding_valid(
                      s_scan_instruction
                  )) begin
                s_scan_capability_err_q <= 1'b1;
                s_scan_capability_addr_q <= s_source_addr_q + s_header_q[4] +
                    {18'd0, s_scan_pc_q, 3'd0};
                s_scan_capability_detail_q <= trap_detail(8'd6, s_scan_pc_q, s_scan_instruction);
              end
              if ((s_scan_class == 4'd0) && (s_scan_opcode == 4'd6)) begin
                s_loop_active_q[s_scan_aux[1:0]]              <= 1'b1;
                s_loop_start_q[s_scan_aux[1:0]]               <= s_scan_pc_q + 1'b1;
                s_loop_nesting_slot_q[s_loop_nesting_depth_q] <= s_scan_aux[1:0];
                s_loop_nesting_depth_q                        <= s_loop_nesting_depth_q + 1'b1;
              end else if ((s_scan_class == 4'd0) && (s_scan_opcode == 4'd7)) begin
                s_loop_active_q[s_scan_aux[1:0]] <= 1'b0;
                s_loop_nesting_depth_q           <= s_loop_nesting_depth_q - 1'b1;
              end
              if (s_scan_last) begin
                s_scan_pc_q          <= entry_pc_o[s_scan_entry_q];
                s_call_depth_q       <= 3'd0;
                s_return_pc_q        <= '0;
                s_loop_active_q      <= 4'd0;
                s_loop_start_q       <= '0;
                s_path_stack_count_q <= '0;
                s_path_stop_valid_q  <= 1'b0;
                s_state_q            <= PathRequest;
              end else begin
                s_scan_pc_q <= s_scan_pc_q + 1'b1;
                s_state_q   <= ScanRequest;
              end
            end
          end
          PathRequest: s_state_q <= PathWait;
          PathWait: begin
            if (store_valid_i) s_state_q <= PathCheck;
          end
          PathCheck: begin
            if (s_path_stop_valid_q && (s_scan_pc_q == s_path_stop_pc_q)) begin
              s_state_q <= PathPop;
            end else if (s_path_err) begin
              if (!s_scan_control_err_q || (s_path_err_pc < s_scan_control_detail_q[18:8])) begin
                s_scan_control_err_q <= 1'b1;
                s_scan_control_addr_q <= s_source_addr_q + s_header_q[4] +
                    {18'd0, s_path_err_pc, 3'd0};
                s_scan_control_detail_q <= trap_detail(
                    s_path_err_reason, s_path_err_pc, s_scan_instruction
                );
              end
              s_state_q <= PathPop;
            end else if ((s_scan_predicate != 4'd0) &&
                         (s_scan_class == 4'd0) &&
                         (s_scan_opcode inside {4'd1, 4'd2})) begin
              s_scan_pc_q <= s_scan_pc_q + 1'b1;
              s_state_q   <= PathRequest;
            end else if ((s_scan_class == 4'd0) && (s_scan_opcode inside {4'd1, 4'd2})) begin
              s_state_q <= PathPop;
            end else if ((s_scan_class == 4'd0) && (s_scan_opcode inside {4'd3, 4'd4})) begin
              if ((s_scan_predicate != 4'd0) && (s_path_stack_count_q == PathStackLimit)) begin
                s_scan_control_err_q <= 1'b1;
                s_scan_control_addr_q <= s_source_addr_q + s_header_q[4] +
                    {18'd0, entry_pc_o[s_scan_entry_q], 3'd0};
                s_scan_control_detail_q <= trap_detail(
                    8'd2, entry_pc_o[s_scan_entry_q], s_scan_instruction
                );
                s_state_q <= PathPop;
              end else begin
                if (s_scan_predicate != 4'd0) begin
                  s_path_stack_count_q <= s_path_stack_count_q + 1'b1;
                end
                if (s_scan_opcode == 4'd4) begin
                  s_return_pc_q[s_call_depth_q] <= s_scan_pc_q + 1'b1;
                  s_call_depth_q                <= s_call_depth_q + 1'b1;
                end
                s_scan_pc_q <= s_scan_target[10:0];
                s_state_q   <= PathRequest;
              end
            end else if ((s_scan_class == 4'd0) && (s_scan_opcode == 4'd5)) begin
              s_call_depth_q <= s_call_depth_q - 1'b1;
              s_scan_pc_q    <= s_return_pc_q[s_call_depth_q-1'b1];
              s_state_q      <= PathRequest;
            end else if ((s_scan_class == 4'd0) && (s_scan_opcode == 4'd6)) begin
              s_loop_active_q[s_scan_aux[1:0]] <= 1'b1;
              s_loop_start_q[s_scan_aux[1:0]]  <= s_scan_pc_q + 1'b1;
              s_scan_pc_q                      <= s_scan_pc_q + 1'b1;
              s_state_q                        <= PathRequest;
            end else if ((s_scan_class == 4'd0) && (s_scan_opcode == 4'd7)) begin
              s_loop_active_q[s_scan_aux[1:0]] <= 1'b0;
              s_scan_pc_q                      <= s_scan_pc_q + 1'b1;
              s_state_q                        <= PathRequest;
            end else begin
              s_scan_pc_q <= s_scan_pc_q + 1'b1;
              s_state_q   <= PathRequest;
            end
          end
          PathPop: begin
            if (s_path_stack_count_q != 12'd0) begin
              s_path_stack_count_q <= s_path_stack_count_q - 1'b1;
              s_state_q            <= PathPopLoad;
            end else if (s_scan_control_err_q || (s_scan_entry_q == 2'd2)) begin
              s_state_q <= Finish;
            end else begin
              s_scan_entry_q         <= s_scan_entry_q + 1'b1;
              s_scan_pc_q            <= entry_first_o[s_scan_entry_q+1'b1];
              s_call_depth_q         <= 3'd0;
              s_return_pc_q          <= '0;
              s_loop_active_q        <= 4'd0;
              s_loop_start_q         <= '0;
              s_loop_nesting_depth_q <= 3'd0;
              s_loop_nesting_slot_q  <= '0;
              s_state_q              <= ScanRequest;
            end
          end
          PathPopLoad: begin
            if (s_path_stack_read_data[63:62] != 2'b10) begin
              s_scan_control_err_q <= 1'b1;
              s_scan_control_addr_q <= s_source_addr_q + s_header_q[4] +
                  {18'd0, entry_pc_o[s_scan_entry_q], 3'd0};
              s_scan_control_detail_q <= trap_detail(
                  8'd2, entry_pc_o[s_scan_entry_q], s_scan_instruction
              );
              s_state_q <= Finish;
            end else begin
              s_scan_pc_q     <= s_path_stack_read_data[10:0];
              s_call_depth_q  <= s_path_stack_read_data[13:11];
              s_return_pc_q   <= s_path_stack_read_data[57:14];
              s_loop_active_q <= s_path_stack_read_data[61:58];
              s_state_q       <= PathRequest;
            end
          end
          Finish: begin
            s_state_q <= Idle;
            if (s_scan_control_err_q) begin
              s_err_bits_q[2] <= 1'b1;
              fault_valid_o   <= 1'b1;
              fault_code_o    <= `APB4_APU__ERROR_CODE_MICROCODE;
              fault_stage_o   <= `APB4_APU__ERROR_STAGE_LOADER;
              fault_addr_o    <= s_scan_control_addr_q;
              fault_detail_o  <= s_scan_control_detail_q;
            end else if (s_table_err) begin
              s_err_bits_q[3] <= 1'b1;
              fault_valid_o   <= 1'b1;
              fault_code_o    <= `APB4_APU__ERROR_CODE_MICROCODE;
              fault_stage_o   <= `APB4_APU__ERROR_STAGE_LOADER;
              fault_addr_o    <= s_table_addr;
              fault_detail_o  <= s_table_detail;
            end else if (s_capability_err || s_scan_capability_err_q) begin
              s_err_bits_q[5] <= 1'b1;
              fault_valid_o <= 1'b1;
              fault_code_o <= `APB4_APU__ERROR_CODE_MICROCODE_CRC;
              fault_stage_o <= `APB4_APU__ERROR_STAGE_LOADER;
              fault_addr_o <= s_capability_err ? s_capability_addr : s_scan_capability_addr_q;
              fault_detail_o <= s_capability_err ? s_capability_detail : s_scan_capability_detail_q;
            end else if ((~s_crc_q != s_header_q[11]) || (~s_crc_q != s_expected_crc_q)) begin
              s_err_bits_q[4] <= 1'b1;
              fault_valid_o   <= 1'b1;
              fault_code_o    <= `APB4_APU__ERROR_CODE_MICROCODE_CRC;
              fault_stage_o   <= `APB4_APU__ERROR_STAGE_LOADER;
              fault_addr_o    <= s_source_addr_q + 32'h2c;
              fault_detail_o  <= ~s_crc_q;
            end else begin
              s_valid_q      <= 1'b1;
              s_lock_q       <= 1'b1;
              s_abi_q        <= s_header_q[1];
              s_build_id_q   <= {s_header_q[13], s_header_q[12]};
              s_load_count_q <= (&s_load_count_q) ? s_load_count_q : s_load_count_q + 1'b1;
              load_done_o    <= 1'b1;
            end
          end
          CancelWait: begin
            if (resource_reset_i) s_cancel_resource_q <= 1'b1;
            if (dma_err_i || dma_done_i) begin
              s_state_q      <= Idle;
              s_valid_q      <= 1'b0;
              s_lock_q       <= 1'b0;
              s_err_bits_q   <= 6'd0;
              s_abi_q        <= 32'd0;
              s_build_id_q   <= 64'd0;
              s_actual_crc_q <= 32'd0;
              if (s_cancel_resource_q || resource_reset_i) begin
                fault_valid_o <= 1'b1;
                fault_code_o  <= `APB4_APU__ERROR_CODE_RESOURCE_RESET;
                fault_stage_o <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
              end else begin
                abort_done_o <= s_cancel_abort_q;
                if (dma_err_i) begin
                  fault_valid_o <= 1'b1;
                  fault_code_o  <= dma_err_code_i;
                  fault_stage_o <= dma_err_stage_i;
                  fault_resp_o  <= dma_err_resp_i;
                  fault_addr_o  <= dma_err_addr_i;
                end
              end
            end
          end
          default:     s_state_q <= Idle;
        endcase
    end
  end

endmodule
