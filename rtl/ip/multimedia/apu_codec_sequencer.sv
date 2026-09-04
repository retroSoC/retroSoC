// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "apu_define.svh"

module apu_codec_sequencer #(
    parameter bit EnableP4 = 1'b0
) (
    // verilog_format: off -- preserve launch, predicate, store, and result columns
    input  logic                  clk_i,
    input  logic                  rst_n_i,
    input  logic                  soft_reset_i,
    input  logic                  resource_reset_i,
    input  logic                  counter_clear_i,
    input  logic                  abort_i,
    input  logic                  launch_i,
    input  logic [1:0]            launch_entry_i,
    input  logic                  image_valid_i,
    input  logic [31:0]           timeout_i,
    input  logic [2:0][10:0]      entry_pc_i,
    input  logic [2:0][10:0]      entry_first_i,
    input  logic [2:0][10:0]      entry_last_i,
    input  logic [2:0][15:0]      entry_max_loop_i,
    input  logic [2:0][23:0]      entry_max_retired_i,
    input  logic [2:0][16:0]      entry_scratch_base_i,
    input  logic [2:0][16:0]      entry_scratch_bytes_i,
    input  logic [2:0][31:0]      entry_primitive_mask_i,
    input  logic [2:0][15:0]      entry_table_offset_i,
    input  logic [2:0][15:0]      entry_table_bytes_i,
    input  logic                  input_exhausted_i,
    input  logic                  input_ready_i,
    input  logic                  output_ready_i,
    input  logic                  kernel_done_i,
    input  logic                  transport_idle_success_i,
    input  logic                  stall_i,
    input  logic                  cause_valid_i,
    input  logic [5:0]            cause_code_i,
    input  logic [3:0]            cause_stage_i,
    input  logic [1:0]            cause_resp_i,
    input  logic [7:0]            cause_index_i,
    input  logic [31:0]           cause_addr_i,
    input  logic [31:0]           cause_detail_i,
    output logic                  primitive_req_valid_o,
    input  logic                  primitive_req_ready_i,
    output logic [63:0]           primitive_instruction_o,
    output logic [31:0]           primitive_source0_o,
    output logic [31:0]           primitive_source1_o,
    output logic [31:0]           primitive_destination_o,
    input  logic                  primitive_result_valid_i,
    input  logic [ 3:0]           primitive_result_dst_i,
    input  logic [ 3:0][31:0]     primitive_result_data_i,
    input  logic [ 2:0]           primitive_result_words_i,
    input  logic                  primitive_result_kernel_i,
    input  logic                  primitive_error_i,
    input  logic [ 5:0]           primitive_error_code_i,
    input  logic [ 3:0]           primitive_error_stage_i,
    input  logic [ 7:0]           primitive_error_reason_i,
    output logic                  fetch_o,
    output logic [10:0]           fetch_addr_o,
    input  logic [63:0]           fetch_data_i,
    input  logic                  fetch_valid_i,
    output logic [31:0]           stat_o,
    output logic [31:0]           retired_o,
    output logic [15:0][31:0]     gpr_o,
    output logic                  trapped_o,
    output logic                  trap_event_o,
    output logic                  abort_done_o,
    output logic                  fault_valid_o,
    output logic [5:0]            fault_code_o,
    output logic [3:0]            fault_stage_o,
    output logic [1:0]            fault_resp_o,
    output logic [7:0]            fault_index_o,
    output logic [31:0]           fault_addr_o,
    output logic [31:0]           fault_detail_o,
    output logic [63:0]           perf_retired_o,
    output logic [16:0]           active_scratch_base_o,
    output logic [16:0]           active_scratch_bytes_o,
    output logic [31:0]           active_primitive_mask_o,
    output logic [15:0]           active_table_offset_o,
    output logic [15:0]           active_table_bytes_o,
    output logic                  launch_epoch_o,
    output logic                  idle_o
    // verilog_format: on
);
  import apu_microcode_pkg::*;

  typedef enum logic [2:0] {
    Idle,
    FetchRequest,
    FetchWait,
    Execute,
    PrimitiveWait
  } sequencer_state_e;

  sequencer_state_e              s_state_q;
  logic             [15:0][31:0] s_gpr_q;
  logic s_eq_q, s_signed_lt_q, s_unsigned_lt_q;
  logic [3:0][10:0] s_return_pc_q;
  logic [2:0]       s_return_depth_q;
  logic [3:0]       s_loop_active_q;
  logic [3:0][15:0] s_loop_count_q;
  logic [3:0][10:0] s_loop_start_q;
  logic [10:0] s_pc_q, s_first_pc_q, s_last_pc_q;
  logic [15:0] s_max_loop_q;
  logic [23:0] s_max_retired_q, s_frame_retired_q;
  logic [31:0] s_watchdog_q;
  logic [63:0] s_instruction_q;
  logic [16:0] s_scratch_base_q, s_scratch_bytes_q;
  logic [31:0] s_primitive_mask_q;
  logic [15:0] s_table_offset_q, s_table_bytes_q;
  logic s_kernel_pending_q, s_kernel_done_q;
  logic [ 3:0] s_kernel_dst_q;
  logic        s_kernel_err_q;
  logic [ 5:0] s_kernel_err_code_q;
  logic [ 3:0] s_kernel_err_stage_q;
  logic [ 7:0] s_kernel_err_reason_q;
  logic [31:0] s_stat_q;
  logic        s_trapped_q;
  logic [63:0] s_perf_retired_q;

  logic [3:0] s_class, s_opcode, s_predicate, s_dst, s_src0, s_src1;
  logic [7:0] s_aux;
  logic [31:0] s_immediate, s_source0, s_source1;
  logic s_predicate_true;
  logic [11:0] s_forward_target, s_loop_target;
  logic [31:0] s_sat_result;
  logic        s_trap_now;
  logic [ 7:0] s_trap_reason;
  logic [31:0] s_trap_detail;
  logic s_pending_dependency, s_wait_stall, s_primitive_stall, s_execute_stall;
  logic s_primitive_class;

  assign s_class = s_instruction_q[63:60];
  assign s_opcode = s_instruction_q[59:56];
  assign s_predicate = s_instruction_q[55:52];
  assign s_dst = s_instruction_q[51:48];
  assign s_src0 = s_instruction_q[47:44];
  assign s_src1 = s_instruction_q[43:40];
  assign s_aux = s_instruction_q[39:32];
  assign s_immediate = s_instruction_q[31:0];
  assign s_source0 = s_gpr_q[s_src0];
  assign s_source1 = s_gpr_q[s_src1];
  assign s_forward_target = {1'b0, s_pc_q} + 1'b1 + {1'b0, s_immediate[10:0]};
  assign s_loop_target = {1'b0, s_pc_q} + 1'b1 - {1'b0, s_immediate[10:0]};
  assign fetch_o = s_state_q == FetchRequest;
  assign fetch_addr_o = s_pc_q;
  assign stat_o = s_stat_q;
  assign retired_o = {8'd0, s_frame_retired_q};
  assign gpr_o = s_gpr_q;
  assign trapped_o = s_trapped_q;
  assign perf_retired_o = s_perf_retired_q;
  assign idle_o = s_state_q == Idle;
  assign active_scratch_base_o = s_scratch_base_q;
  assign active_scratch_bytes_o = s_scratch_bytes_q;
  assign active_primitive_mask_o = s_primitive_mask_q;
  assign active_table_offset_o = s_table_offset_q;
  assign active_table_bytes_o = s_table_bytes_q;
  assign launch_epoch_o = (s_state_q == Idle) && launch_i && image_valid_i &&
      (launch_entry_i < 2'd3);
  assign primitive_instruction_o = s_instruction_q;
  assign primitive_source0_o = s_source0;
  assign primitive_source1_o = s_source1;
  assign primitive_destination_o = s_gpr_q[s_dst];
  assign s_primitive_class = EnableP4 && (s_class >= 4'd2) && (s_class <= 4'd5);
  assign primitive_req_valid_o = (s_state_q == Execute) && s_predicate_true &&
      s_primitive_class && !s_pending_dependency && !s_kernel_pending_q;

  always_comb begin
    unique case (s_predicate)
      4'd0:    s_predicate_true = 1'b1;
      4'd1:    s_predicate_true = s_eq_q;
      4'd2:    s_predicate_true = !s_eq_q;
      4'd3:    s_predicate_true = s_signed_lt_q;
      4'd4:    s_predicate_true = !s_signed_lt_q;
      4'd5:    s_predicate_true = s_unsigned_lt_q;
      4'd6:    s_predicate_true = !s_unsigned_lt_q;
      4'd7:    s_predicate_true = input_exhausted_i;
      4'd8:    s_predicate_true = input_ready_i;
      4'd9:    s_predicate_true = output_ready_i;
      4'd10:   s_predicate_true = s_kernel_done_q;
      4'd11:   s_predicate_true = transport_idle_success_i;
      default: s_predicate_true = 1'b0;
    endcase
  end

  always_comb begin
    s_pending_dependency = 1'b0;
    if (s_kernel_pending_q && s_predicate_true) begin
      unique case (s_class)
        `APB4_APU__MC_CLASS_CONTROL: begin
          s_pending_dependency = (s_opcode == `APB4_APU__MC_CONTROL_LOOP_SETUP) &&
              (s_src0 == s_kernel_dst_q);
        end
        `APB4_APU__MC_CLASS_SCALAR: begin
          unique case (s_opcode)
            `APB4_APU__MC_SCALAR_MOV:
            s_pending_dependency = (s_src0 == s_kernel_dst_q) || (s_dst == s_kernel_dst_q);
            `APB4_APU__MC_SCALAR_MOVI: s_pending_dependency = s_dst == s_kernel_dst_q;
            `APB4_APU__MC_SCALAR_CMP:
            s_pending_dependency = (s_src0 == s_kernel_dst_q) || (s_src1 == s_kernel_dst_q);
            `APB4_APU__MC_SCALAR_SAT:
            s_pending_dependency = (s_src0 == s_kernel_dst_q) || (s_dst == s_kernel_dst_q);
            default:
            s_pending_dependency = (s_src0 == s_kernel_dst_q) ||
                (s_src1 == s_kernel_dst_q) || (s_dst == s_kernel_dst_q);
          endcase
        end
        `APB4_APU__MC_CLASS_BITSTREAM: begin
          s_pending_dependency = (s_dst == s_kernel_dst_q) ||
              ((s_opcode >= `APB4_APU__MC_BITSTREAM_FRAME_SYNC) &&
               ((s_src0 == s_kernel_dst_q) || (s_src1 == s_kernel_dst_q)));
        end
        `APB4_APU__MC_CLASS_ENTROPY, `APB4_APU__MC_CLASS_LOCAL: begin
          s_pending_dependency = (s_src0 == s_kernel_dst_q) ||
              (s_src1 == s_kernel_dst_q) || (s_dst == s_kernel_dst_q) ||
              ((s_class == `APB4_APU__MC_CLASS_ENTROPY) &&
               (s_opcode inside {`APB4_APU__MC_ENTROPY_HUFF_PAIR,
                                  `APB4_APU__MC_ENTROPY_HUFF_QUAD}) &&
               ((s_dst + 1'b1) == s_kernel_dst_q)) ||
              ((s_class == `APB4_APU__MC_CLASS_ENTROPY) &&
               (s_opcode == `APB4_APU__MC_ENTROPY_HUFF_QUAD) &&
               (((s_dst + 4'd2) == s_kernel_dst_q) ||
                ((s_dst + 4'd3) == s_kernel_dst_q))) ||
              ((s_class == `APB4_APU__MC_CLASS_LOCAL) &&
               (s_opcode == `APB4_APU__MC_LOCAL_FIFO_POP) &&
               ((s_dst + 1'b1) == s_kernel_dst_q));
        end
        `APB4_APU__MC_CLASS_KERNEL: s_pending_dependency = 1'b1;
        default:                    s_pending_dependency = 1'b0;
      endcase
    end
    s_wait_stall = EnableP4 && s_predicate_true &&
        (s_class == `APB4_APU__MC_CLASS_CONTROL) &&
        (s_opcode == `APB4_APU__MC_CONTROL_WAIT) &&
        (((s_aux == `APB4_APU__MC_WAIT_KERNEL) && !s_kernel_done_q) ||
         ((s_aux == `APB4_APU__MC_WAIT_INPUT_FIFO) && !input_ready_i) ||
         ((s_aux == `APB4_APU__MC_WAIT_OUTPUT_FIFO) && !output_ready_i));
    s_primitive_stall = s_primitive_class &&
        (s_kernel_pending_q || s_pending_dependency || !primitive_req_ready_i);
    s_execute_stall = stall_i || s_wait_stall || s_primitive_stall ||
        (s_kernel_pending_q && s_predicate_true &&
         (s_class == `APB4_APU__MC_CLASS_CONTROL) &&
         (s_opcode == `APB4_APU__MC_CONTROL_END));
  end

  always_comb begin
    s_trap_now    = 1'b0;
    s_trap_reason = 8'd0;
    s_trap_detail = 32'd0;
    if (s_execute_stall && (s_watchdog_q + 1'b1 >= timeout_i)) begin
      s_trap_now    = 1'b1;
      s_trap_reason = 8'd7;
    end else if (!instruction_encoding_valid(s_instruction_q)) begin
      s_trap_now    = 1'b1;
      s_trap_reason = 8'd1;
    end else if ((!EnableP4 && ((s_class >= 4'd2) ||
                               ((s_class == 4'd0) && (s_opcode == 4'd8)))) ||
                 (EnableP4 && ((s_class == 4'd6) ||
                               ((s_class == 4'd0) && (s_opcode == 4'd8) &&
                                !(s_aux inside {8'd1, 8'd2, 8'd3}))))) begin
      s_trap_now    = 1'b1;
      s_trap_reason = 8'd6;
    end else if (s_frame_retired_q >= s_max_retired_q) begin
      s_trap_now    = 1'b1;
      s_trap_reason = 8'd8;
    end else if (!s_predicate_true && ((s_pc_q == s_last_pc_q) || (s_pc_q == 11'd2047))) begin
      s_trap_now    = 1'b1;
      s_trap_reason = 8'd2;
    end else if (s_predicate_true && (s_class == 4'd0)) begin
      unique case (s_opcode)
        4'd0: begin
          s_trap_now    = (s_pc_q == s_last_pc_q) || (s_pc_q == 11'd2047);
          s_trap_reason = 8'd2;
        end
        4'd1: begin
        end
        4'd2: begin
          s_trap_now    = 1'b1;
          s_trap_reason = 8'd10;
          s_trap_detail = s_immediate;
        end
        4'd3, 4'd4: begin
          if (s_forward_target[11] || (s_forward_target[10:0] < s_first_pc_q) ||
              (s_forward_target[10:0] > s_last_pc_q)) begin
            s_trap_now    = 1'b1;
            s_trap_reason = 8'd2;
          end else if ((s_opcode == 4'd4) && (s_return_depth_q == 3'd4)) begin
            s_trap_now    = 1'b1;
            s_trap_reason = 8'd3;
          end
        end
        4'd5: begin
          s_trap_now    = s_return_depth_q == 3'd0;
          s_trap_reason = 8'd3;
        end
        4'd6: begin
          s_trap_now = s_loop_active_q[s_aux[1:0]] || (s_source0[15:0] == 16'd0) ||
              (s_source0[15:0] > s_max_loop_q);
          s_trap_reason = 8'd4;
        end
        4'd7: begin
          s_trap_now = s_loop_target[11] || !s_loop_active_q[s_aux[1:0]] ||
              (s_loop_target[10:0] != s_loop_start_q[s_aux[1:0]]) ||
              (s_loop_target[10:0] < s_first_pc_q);
          s_trap_reason = 8'd4;
        end
        4'd8: begin
        end
        default: begin
          s_trap_now    = 1'b1;
          s_trap_reason = 8'd1;
        end
      endcase
    end else if (s_predicate_true && (s_class == 4'd1) &&
                     ((s_pc_q == s_last_pc_q) || (s_pc_q == 11'd2047))) begin
      s_trap_now    = 1'b1;
      s_trap_reason = 8'd2;
    end
    if (s_trap_now && (s_trap_reason != 8'd10)) begin
      s_trap_detail = trap_detail(s_trap_reason, s_pc_q, s_instruction_q);
    end
  end

  always_comb begin
    logic signed [32:0] s_signed_value;
    logic signed [32:0] s_signed_min;
    logic signed [32:0] s_signed_max;
    logic        [ 4:0] s_width;
    s_width        = s_aux[4:0] == 5'd0 ? 5'd31 : s_aux[4:0];
    s_signed_value = {s_source0[31], s_source0};
    s_signed_min   = -33'sh08000_0000;
    s_signed_max   = 33'sh07fff_ffff;
    s_sat_result   = s_source0;
    if ((s_aux[4:0] != 5'd0) && s_aux[5]) begin
      s_signed_value = {s_source0[31], s_source0};
      s_signed_min   = -(33'sd1 <<< (s_width - 1'b1));
      s_signed_max   = (33'sd1 <<< (s_width - 1'b1)) - 1'b1;
      if (s_signed_value < s_signed_min) begin
        s_sat_result = s_signed_min[31:0];
      end else if (s_signed_value > s_signed_max) begin
        s_sat_result = s_signed_max[31:0];
      end
    end else if ((s_aux[4:0] != 5'd0) && (s_source0 > ((32'd1 << s_aux[4:0]) - 1'b1))) begin
      s_sat_result = (32'd1 << s_aux[4:0]) - 1'b1;
    end
  end

  `define RETROSOC_APU__SET_TRAP(DETAIL)                                               \
  begin                                                                              \
    s_state_q      <= Idle;                                                          \
    s_trapped_q    <= 1'b1;                                                          \
    trap_event_o   <= 1'b1;                                                          \
    fault_valid_o  <= 1'b1;                                                          \
    fault_code_o   <= `APB4_APU__ERROR_CODE_SEQUENCER;                               \
    fault_stage_o  <= `APB4_APU__ERROR_STAGE_LIFECYCLE;                              \
    fault_resp_o   <= 2'd0;                                                          \
    fault_index_o  <= 8'd0;                                                          \
    fault_addr_o   <= {18'd0, s_pc_q, 3'd0};                                         \
    fault_detail_o <= DETAIL;                                                        \
    s_stat_q       <= {11'd0, |s_loop_active_q, s_execute_stall, s_opcode, s_class, s_pc_q}; \
  end

  `define RETROSOC_APU__SET_FETCH_WATCHDOG_TRAP                                      \
  begin                                                                              \
    s_state_q      <= Idle;                                                          \
    s_trapped_q    <= 1'b1;                                                          \
    trap_event_o   <= 1'b1;                                                          \
    fault_valid_o  <= 1'b1;                                                          \
    fault_code_o   <= `APB4_APU__ERROR_CODE_SEQUENCER;                               \
    fault_stage_o  <= `APB4_APU__ERROR_STAGE_LIFECYCLE;                              \
    fault_resp_o   <= 2'd0;                                                          \
    fault_index_o  <= 8'd0;                                                          \
    fault_addr_o   <= {18'd0, s_pc_q, 3'd0};                                         \
    fault_detail_o <= trap_detail(8'd7, s_pc_q, 64'd0);                              \
    s_stat_q       <= {11'd0, |s_loop_active_q, 1'b0, 8'd0, s_pc_q};                 \
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_state_q             <= Idle;
      s_gpr_q               <= '0;
      s_eq_q                <= 1'b0;
      s_signed_lt_q         <= 1'b0;
      s_unsigned_lt_q       <= 1'b0;
      s_return_pc_q         <= '0;
      s_return_depth_q      <= 3'd0;
      s_loop_active_q       <= 4'd0;
      s_loop_count_q        <= '0;
      s_loop_start_q        <= '0;
      s_pc_q                <= 11'd0;
      s_first_pc_q          <= 11'd0;
      s_last_pc_q           <= 11'd0;
      s_max_loop_q          <= 16'd0;
      s_max_retired_q       <= 24'd0;
      s_frame_retired_q     <= 24'd0;
      s_watchdog_q          <= 32'd0;
      s_instruction_q       <= 64'd0;
      s_scratch_base_q      <= 17'd0;
      s_scratch_bytes_q     <= 17'd0;
      s_primitive_mask_q    <= 32'd0;
      s_table_offset_q      <= 16'd0;
      s_table_bytes_q       <= 16'd0;
      s_kernel_pending_q    <= 1'b0;
      s_kernel_done_q       <= 1'b0;
      s_kernel_dst_q        <= 4'd0;
      s_kernel_err_q        <= 1'b0;
      s_kernel_err_code_q   <= 6'd0;
      s_kernel_err_stage_q  <= 4'd0;
      s_kernel_err_reason_q <= 8'd0;
      s_stat_q              <= 32'd0;
      s_trapped_q           <= 1'b0;
      s_perf_retired_q      <= 64'd0;
      trap_event_o          <= 1'b0;
      abort_done_o          <= 1'b0;
      fault_valid_o         <= 1'b0;
      fault_code_o          <= 6'd0;
      fault_stage_o         <= 4'd0;
      fault_resp_o          <= 2'd0;
      fault_index_o         <= 8'd0;
      fault_addr_o          <= 32'd0;
      fault_detail_o        <= 32'd0;
    end else begin
      trap_event_o  <= 1'b0;
      abort_done_o  <= 1'b0;
      fault_valid_o <= 1'b0;
      if (primitive_result_valid_i && primitive_result_kernel_i) begin
        s_kernel_pending_q <= 1'b0;
        s_kernel_done_q    <= !primitive_error_i;
        if (primitive_error_i) begin
          s_kernel_err_q        <= 1'b1;
          s_kernel_err_code_q   <= primitive_error_code_i;
          s_kernel_err_stage_q  <= primitive_error_stage_i;
          s_kernel_err_reason_q <= primitive_error_reason_i;
        end else begin
          s_gpr_q[primitive_result_dst_i] <= primitive_result_data_i[0];
        end
      end else if (kernel_done_i) begin
        s_kernel_done_q <= 1'b1;
      end
      if (counter_clear_i) s_perf_retired_q <= 64'd0;
      if (soft_reset_i || resource_reset_i) begin
        s_state_q          <= Idle;
        s_gpr_q            <= '0;
        s_eq_q             <= 1'b0;
        s_signed_lt_q      <= 1'b0;
        s_unsigned_lt_q    <= 1'b0;
        s_return_depth_q   <= 3'd0;
        s_loop_active_q    <= 4'd0;
        s_pc_q             <= 11'd0;
        s_frame_retired_q  <= 24'd0;
        s_watchdog_q       <= 32'd0;
        s_stat_q           <= 32'd0;
        s_trapped_q        <= 1'b0;
        s_perf_retired_q   <= 64'd0;
        s_kernel_pending_q <= 1'b0;
        s_kernel_done_q    <= 1'b0;
        s_kernel_err_q     <= 1'b0;
      end else begin
        unique case (s_state_q)
          Idle: begin
            if (launch_i && image_valid_i && (launch_entry_i < 2'd3)) begin
              s_state_q          <= FetchRequest;
              s_gpr_q            <= '0;
              s_eq_q             <= 1'b0;
              s_signed_lt_q      <= 1'b0;
              s_unsigned_lt_q    <= 1'b0;
              s_return_depth_q   <= 3'd0;
              s_loop_active_q    <= 4'd0;
              s_pc_q             <= entry_pc_i[launch_entry_i];
              s_first_pc_q       <= entry_first_i[launch_entry_i];
              s_last_pc_q        <= entry_last_i[launch_entry_i];
              s_max_loop_q       <= entry_max_loop_i[launch_entry_i];
              s_max_retired_q    <= entry_max_retired_i[launch_entry_i];
              s_scratch_base_q   <= entry_scratch_base_i[launch_entry_i];
              s_scratch_bytes_q  <= entry_scratch_bytes_i[launch_entry_i];
              s_primitive_mask_q <= entry_primitive_mask_i[launch_entry_i];
              s_table_offset_q   <= entry_table_offset_i[launch_entry_i];
              s_table_bytes_q    <= entry_table_bytes_i[launch_entry_i];
              s_frame_retired_q  <= 24'd0;
              s_watchdog_q       <= 32'd0;
              s_stat_q           <= {21'd0, entry_pc_i[launch_entry_i]};
              s_trapped_q        <= 1'b0;
              s_kernel_pending_q <= 1'b0;
              s_kernel_done_q    <= 1'b0;
              s_kernel_err_q     <= 1'b0;
            end
          end
          FetchRequest: begin
            s_stat_q <= {21'd0, s_pc_q};
            if (s_watchdog_q + 1'b1 >= timeout_i) begin
              `RETROSOC_APU__SET_FETCH_WATCHDOG_TRAP;
            end else if (abort_i) begin
              s_state_q          <= Idle;
              s_kernel_pending_q <= 1'b0;
              s_kernel_done_q    <= 1'b0;
              s_kernel_err_q     <= 1'b0;
              abort_done_o       <= 1'b1;
            end else begin
              s_watchdog_q <= s_watchdog_q + 1'b1;
              s_state_q    <= FetchWait;
            end
          end
          FetchWait: begin
            if (s_watchdog_q + 1'b1 >= timeout_i) begin
              `RETROSOC_APU__SET_FETCH_WATCHDOG_TRAP;
            end else if (abort_i) begin
              s_state_q          <= Idle;
              s_kernel_pending_q <= 1'b0;
              s_kernel_done_q    <= 1'b0;
              s_kernel_err_q     <= 1'b0;
              abort_done_o       <= 1'b1;
            end else begin
              s_watchdog_q <= s_watchdog_q + 1'b1;
              if (fetch_valid_i) begin
                s_instruction_q <= fetch_data_i;
                s_stat_q <= {
                  11'd0, |s_loop_active_q, 1'b0, fetch_data_i[59:56], fetch_data_i[63:60], s_pc_q
                };
                s_state_q <= Execute;
              end
            end
          end
          Execute: begin
            if (cause_valid_i) begin
              s_state_q <= Idle;
              s_trapped_q <= 1'b1;
              trap_event_o <= 1'b1;
              fault_valid_o <= 1'b1;
              fault_code_o <= cause_code_i;
              fault_stage_o <= cause_stage_i;
              fault_resp_o <= cause_resp_i;
              fault_index_o <= cause_index_i;
              fault_addr_o <= cause_addr_i;
              fault_detail_o <= cause_detail_i;
              s_stat_q <= {11'd0, |s_loop_active_q, s_execute_stall, s_opcode, s_class, s_pc_q};
            end else if (primitive_result_valid_i && primitive_error_i) begin
              s_state_q <= Idle;
              s_trapped_q <= 1'b1;
              trap_event_o <= 1'b1;
              fault_valid_o <= 1'b1;
              fault_code_o <= primitive_error_code_i;
              fault_stage_o <= primitive_error_stage_i;
              fault_resp_o <= 2'd0;
              fault_index_o <= 8'd0;
              fault_addr_o <= {18'd0, s_pc_q, 3'd0};
              fault_detail_o <= trap_detail(primitive_error_reason_i, s_pc_q, s_instruction_q);
              s_stat_q <= {11'd0, |s_loop_active_q, s_execute_stall, s_opcode, s_class, s_pc_q};
            end else if (s_kernel_err_q) begin
              s_state_q      <= Idle;
              s_trapped_q    <= 1'b1;
              trap_event_o   <= 1'b1;
              fault_valid_o  <= 1'b1;
              fault_code_o   <= s_kernel_err_code_q;
              fault_stage_o  <= s_kernel_err_stage_q;
              fault_resp_o   <= 2'd0;
              fault_index_o  <= 8'd0;
              fault_addr_o   <= {18'd0, s_pc_q, 3'd0};
              fault_detail_o <= trap_detail(s_kernel_err_reason_q, s_pc_q, s_instruction_q);
              s_kernel_err_q <= 1'b0;
            end else if (s_trap_now) begin
              `RETROSOC_APU__SET_TRAP(s_trap_detail);
            end else if (abort_i) begin
              s_state_q          <= Idle;
              s_kernel_pending_q <= 1'b0;
              s_kernel_done_q    <= 1'b0;
              s_kernel_err_q     <= 1'b0;
              abort_done_o       <= 1'b1;
            end else if (s_execute_stall) begin
              s_stat_q[19] <= 1'b1;
              if (s_watchdog_q + 1'b1 >= timeout_i) begin
                `RETROSOC_APU__SET_TRAP(trap_detail(8'd7, s_pc_q, s_instruction_q));
              end else begin
                s_watchdog_q <= s_watchdog_q + 1'b1;
              end
            end else if (!instruction_encoding_valid(s_instruction_q)) begin
              `RETROSOC_APU__SET_TRAP(trap_detail(8'd1, s_pc_q, s_instruction_q));
            end else if ((!EnableP4 && ((s_class >= 4'd2) ||
                                       ((s_class == 4'd0) && (s_opcode == 4'd8)))) ||
                         (EnableP4 && ((s_class == 4'd6) ||
                                      ((s_class == 4'd0) && (s_opcode == 4'd8) &&
                                       !(s_aux inside {8'd1, 8'd2, 8'd3}))))) begin
              `RETROSOC_APU__SET_TRAP(trap_detail(8'd6, s_pc_q, s_instruction_q));
            end else if (s_frame_retired_q >= s_max_retired_q) begin
              `RETROSOC_APU__SET_TRAP(trap_detail(8'd8, s_pc_q, s_instruction_q));
            end else if (s_predicate_true && s_primitive_class &&
                         (s_class != `APB4_APU__MC_CLASS_KERNEL)) begin
              s_watchdog_q <= s_watchdog_q + 1'b1;
              s_stat_q[19] <= 1'b1;
              s_state_q    <= PrimitiveWait;
            end else begin
              s_watchdog_q      <= 32'd0;
              s_stat_q[19]      <= 1'b0;
              s_frame_retired_q <= s_frame_retired_q + 1'b1;
              if (!counter_clear_i && !(&s_perf_retired_q)) begin
                s_perf_retired_q <= s_perf_retired_q + 1'b1;
              end
              if (!s_predicate_true) begin
                if ((s_pc_q == s_last_pc_q) || (s_pc_q == 11'd2047)) begin
                  `RETROSOC_APU__SET_TRAP(trap_detail(8'd2, s_pc_q, s_instruction_q));
                  s_frame_retired_q <= s_frame_retired_q;
                  s_perf_retired_q  <= s_perf_retired_q;
                end else begin
                  s_pc_q    <= s_pc_q + 1'b1;
                  s_state_q <= FetchRequest;
                end
              end else if (s_class == 4'd0) begin
                unique case (s_opcode)
                  4'd0: begin
                    if ((s_pc_q == s_last_pc_q) || (s_pc_q == 11'd2047)) begin
                      `RETROSOC_APU__SET_TRAP(trap_detail(8'd2, s_pc_q, s_instruction_q));
                      s_frame_retired_q <= s_frame_retired_q;
                      s_perf_retired_q  <= s_perf_retired_q;
                    end else begin
                      s_pc_q    <= s_pc_q + 1'b1;
                      s_state_q <= FetchRequest;
                    end
                  end
                  4'd1: s_state_q <= Idle;
                  4'd2: begin
                    `RETROSOC_APU__SET_TRAP(s_immediate);
                    s_frame_retired_q <= s_frame_retired_q;
                    s_perf_retired_q  <= s_perf_retired_q;
                  end
                  4'd3: begin
                    if (s_forward_target[11] || (s_forward_target[10:0] < s_first_pc_q) ||
                        (s_forward_target[10:0] > s_last_pc_q)) begin
                      `RETROSOC_APU__SET_TRAP(trap_detail(8'd2, s_pc_q, s_instruction_q));
                      s_frame_retired_q <= s_frame_retired_q;
                      s_perf_retired_q  <= s_perf_retired_q;
                    end else begin
                      s_pc_q    <= s_forward_target[10:0];
                      s_state_q <= FetchRequest;
                    end
                  end
                  4'd4: begin
                    if (s_return_depth_q == 3'd4) begin
                      `RETROSOC_APU__SET_TRAP(trap_detail(8'd3, s_pc_q, s_instruction_q));
                      s_frame_retired_q <= s_frame_retired_q;
                      s_perf_retired_q  <= s_perf_retired_q;
                    end else begin
                      s_return_pc_q[s_return_depth_q] <= s_pc_q + 1'b1;
                      s_return_depth_q                <= s_return_depth_q + 1'b1;
                      s_pc_q                          <= s_forward_target[10:0];
                      s_state_q                       <= FetchRequest;
                    end
                  end
                  4'd5: begin
                    if (s_return_depth_q == 3'd0) begin
                      `RETROSOC_APU__SET_TRAP(trap_detail(8'd3, s_pc_q, s_instruction_q));
                      s_frame_retired_q <= s_frame_retired_q;
                      s_perf_retired_q  <= s_perf_retired_q;
                    end else begin
                      s_return_depth_q <= s_return_depth_q - 1'b1;
                      s_pc_q           <= s_return_pc_q[s_return_depth_q-1'b1];
                      s_state_q        <= FetchRequest;
                    end
                  end
                  4'd6: begin
                    if (s_loop_active_q[s_aux[1:0]] || (s_source0[15:0] == 16'd0) ||
                        (s_source0[15:0] > s_max_loop_q)) begin
                      `RETROSOC_APU__SET_TRAP(trap_detail(8'd4, s_pc_q, s_instruction_q));
                      s_frame_retired_q <= s_frame_retired_q;
                      s_perf_retired_q  <= s_perf_retired_q;
                    end else begin
                      s_loop_active_q[s_aux[1:0]] <= 1'b1;
                      s_loop_count_q[s_aux[1:0]]  <= s_source0[15:0];
                      s_loop_start_q[s_aux[1:0]]  <= s_pc_q + 1'b1;
                      s_pc_q                      <= s_pc_q + 1'b1;
                      s_state_q                   <= FetchRequest;
                    end
                  end
                  4'd7: begin
                    if (s_loop_target[11] || !s_loop_active_q[s_aux[1:0]] ||
                        (s_loop_target[10:0] != s_loop_start_q[s_aux[1:0]]) ||
                        (s_loop_target[10:0] < s_first_pc_q)) begin
                      `RETROSOC_APU__SET_TRAP(trap_detail(8'd4, s_pc_q, s_instruction_q));
                      s_frame_retired_q <= s_frame_retired_q;
                      s_perf_retired_q  <= s_perf_retired_q;
                    end else if (s_loop_count_q[s_aux[1:0]] > 16'd1) begin
                      s_loop_count_q[s_aux[1:0]] <= s_loop_count_q[s_aux[1:0]] - 1'b1;
                      s_pc_q                     <= s_loop_target[10:0];
                      s_state_q                  <= FetchRequest;
                    end else begin
                      s_loop_active_q[s_aux[1:0]] <= 1'b0;
                      s_pc_q                      <= s_pc_q + 1'b1;
                      s_state_q                   <= FetchRequest;
                    end
                  end
                  4'd8: begin
                    if ((s_pc_q == s_last_pc_q) || (s_pc_q == 11'd2047)) begin
                      `RETROSOC_APU__SET_TRAP(trap_detail(8'd2, s_pc_q, s_instruction_q));
                      s_frame_retired_q <= s_frame_retired_q;
                      s_perf_retired_q  <= s_perf_retired_q;
                    end else begin
                      s_pc_q    <= s_pc_q + 1'b1;
                      s_state_q <= FetchRequest;
                    end
                  end
                  default: begin
                    `RETROSOC_APU__SET_TRAP(trap_detail(8'd1, s_pc_q, s_instruction_q));
                    s_frame_retired_q <= s_frame_retired_q;
                    s_perf_retired_q  <= s_perf_retired_q;
                  end
                endcase
              end else if (s_class == `APB4_APU__MC_CLASS_KERNEL) begin
                s_kernel_pending_q <= 1'b1;
                s_kernel_done_q    <= 1'b0;
                s_kernel_dst_q     <= s_dst;
                if ((s_pc_q == s_last_pc_q) || (s_pc_q == 11'd2047)) begin
                  `RETROSOC_APU__SET_TRAP(trap_detail(8'd2, s_pc_q, s_instruction_q));
                  s_frame_retired_q  <= s_frame_retired_q;
                  s_perf_retired_q   <= s_perf_retired_q;
                  s_kernel_pending_q <= 1'b0;
                end else begin
                  s_pc_q    <= s_pc_q + 1'b1;
                  s_state_q <= FetchRequest;
                end
              end else begin
                unique case (s_opcode)
                  4'd0: s_gpr_q[s_dst] <= s_source0;
                  4'd1: s_gpr_q[s_dst] <= s_immediate;
                  4'd2: s_gpr_q[s_dst] <= s_source0 + s_source1;
                  4'd3: s_gpr_q[s_dst] <= s_source0 - s_source1;
                  4'd4: s_gpr_q[s_dst] <= s_source0 & s_source1;
                  4'd5: s_gpr_q[s_dst] <= s_source0 | s_source1;
                  4'd6: s_gpr_q[s_dst] <= s_source0 ^ s_source1;
                  4'd7: s_gpr_q[s_dst] <= s_source0 << s_source1[4:0];
                  4'd8: s_gpr_q[s_dst] <= s_source0 >> s_source1[4:0];
                  4'd9: s_gpr_q[s_dst] <= $unsigned($signed(s_source0) >>> s_source1[4:0]);
                  4'd10: begin
                    s_eq_q          <= s_source0 == s_source1;
                    s_signed_lt_q   <= $signed(s_source0) < $signed(s_source1);
                    s_unsigned_lt_q <= s_source0 < s_source1;
                  end
                  4'd11:
                  s_gpr_q[s_dst] <= s_aux[0] ? (($signed(
                      s_source0
                  ) < $signed(
                      s_source1
                  )) ? s_source0 : s_source1) : ((s_source0 < s_source1) ? s_source0 : s_source1);
                  4'd12:
                  s_gpr_q[s_dst] <= s_aux[0] ? (($signed(
                      s_source0
                  ) > $signed(
                      s_source1
                  )) ? s_source0 : s_source1) : ((s_source0 > s_source1) ? s_source0 : s_source1);
                  4'd13: s_gpr_q[s_dst] <= s_sat_result;
                  default: begin
                  end
                endcase
                if ((s_pc_q == s_last_pc_q) || (s_pc_q == 11'd2047)) begin
                  `RETROSOC_APU__SET_TRAP(trap_detail(8'd2, s_pc_q, s_instruction_q));
                  s_frame_retired_q <= s_frame_retired_q;
                  s_perf_retired_q  <= s_perf_retired_q;
                end else begin
                  s_pc_q    <= s_pc_q + 1'b1;
                  s_state_q <= FetchRequest;
                end
              end
            end
          end
          PrimitiveWait: begin
            s_stat_q[19] <= 1'b1;
            if (primitive_result_valid_i) begin
              if (primitive_error_i) begin
                s_state_q      <= Idle;
                s_trapped_q    <= 1'b1;
                trap_event_o   <= 1'b1;
                fault_valid_o  <= 1'b1;
                fault_code_o   <= primitive_error_code_i;
                fault_stage_o  <= primitive_error_stage_i;
                fault_resp_o   <= 2'd0;
                fault_index_o  <= 8'd0;
                fault_addr_o   <= {18'd0, s_pc_q, 3'd0};
                fault_detail_o <= trap_detail(primitive_error_reason_i, s_pc_q, s_instruction_q);
                s_stat_q       <= {11'd0, |s_loop_active_q, 1'b1, s_opcode, s_class, s_pc_q};
              end else begin
                for (int index = 0; index < 4; index++) begin
                  if (index < primitive_result_words_i) begin
                    s_gpr_q[primitive_result_dst_i+4'(index)] <= primitive_result_data_i[index];
                  end
                end
                s_watchdog_q      <= 32'd0;
                s_stat_q[19]      <= 1'b0;
                s_frame_retired_q <= s_frame_retired_q + 1'b1;
                if (!counter_clear_i && !(&s_perf_retired_q)) begin
                  s_perf_retired_q <= s_perf_retired_q + 1'b1;
                end
                if ((s_pc_q == s_last_pc_q) || (s_pc_q == 11'd2047)) begin
                  `RETROSOC_APU__SET_TRAP(trap_detail(8'd2, s_pc_q, s_instruction_q));
                  s_frame_retired_q <= s_frame_retired_q;
                  s_perf_retired_q  <= s_perf_retired_q;
                end else begin
                  s_pc_q    <= s_pc_q + 1'b1;
                  s_state_q <= FetchRequest;
                end
              end
            end else if (abort_i) begin
              s_state_q          <= Idle;
              s_kernel_pending_q <= 1'b0;
              s_kernel_done_q    <= 1'b0;
              s_kernel_err_q     <= 1'b0;
              abort_done_o       <= 1'b1;
            end else if (s_watchdog_q + 1'b1 >= timeout_i) begin
              `RETROSOC_APU__SET_TRAP(trap_detail(8'd7, s_pc_q, s_instruction_q));
            end else begin
              s_watchdog_q <= s_watchdog_q + 1'b1;
            end
          end
          default: s_state_q <= Idle;
        endcase
      end
    end
  end
endmodule

`undef RETROSOC_APU__SET_TRAP
`undef RETROSOC_APU__SET_FETCH_WATCHDOG_TRAP
