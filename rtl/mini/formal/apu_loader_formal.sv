// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module apu_loader_formal_design (
    input  logic        clk_i,
    output logic        rst_n_i,
    output logic        f_past_valid,
    output logic [ 2:0] scenario,
    output logic [ 6:0] cycle,
    output logic [ 7:0] status,
    output logic        lock,
    output logic        store_write,
    output logic [10:0] store_addr,
    output logic        load_done,
    output logic        abort_done,
    output logic        fault_valid,
    output logic [ 5:0] fault_code,
    output logic [ 3:0] fault_stage,
    output logic [ 1:0] fault_resp,
    output logic [31:0] fault_addr,
    output logic [31:0] fault_detail,
    output logic [31:0] actual_crc,
    output logic        abort_seen,
    output logic        fault_seen,
    output logic        load_seen,
    output logic        store_seen,
    output logic [ 1:0] request_count
);
`ifndef APU_LOADER_FORMAL_SCENARIO
  `define APU_LOADER_FORMAL_SCENARIO 0
`endif
  localparam logic [2:0] FormalScenario = 3'(`APU_LOADER_FORMAL_SCENARIO);
  logic [2:0] f_scenario;
  logic [6:0] s_cycle_q;
  logic       s_request_valid;
  logic [31:0] s_request_addr, s_request_bytes;
  logic s_dma_active_q, s_dma_done_q;
  logic [31:0] s_dma_addr_q, s_dma_bytes_q;
  logic [ 7:0] s_dma_beat_q;
  logic [ 1:0] s_request_count_q;
  logic [31:0] s_dma_data;
  logic        s_dma_last;
  logic        s_dma_ready;
  logic s_store_read, s_store_valid_q;
  logic [63:0] s_store_write_data, s_store_word_q, s_store_read_data_q;
  logic s_abort_seen_q, s_fault_seen_q, s_load_seen_q, s_store_seen_q;

  function automatic logic [31:0] image_word(input logic [7:0] word_i);
    logic [31:0] s_word;
    begin
      s_word = 32'd0;
      unique case (word_i)
        8'd0:                                            s_word = 32'h4150_4d43;
        8'd1:                                            s_word = 32'h0001_0000;
        8'd2:                                            s_word = 32'h0000_00c8;
        8'd3:                                            s_word = 32'h0000_0001;
        8'd4:                                            s_word = 32'h0000_00c0;
        8'd7:                                            s_word = 32'h0000_0040;
        8'd8:                                            s_word = 32'h0000_0003;
        8'd5:                                            s_word = (f_scenario == 3'd1) ? 32'd204 : 32'd0;
        8'd11:                                           s_word = (f_scenario == 3'd3) ? 32'h62e4_edd0 : 32'h62e4_edd1;
        8'd12:                                           s_word = 32'h5566_7788;
        8'd13:                                           s_word = 32'h1122_3344;
        8'd20, 8'd24, 8'd28, 8'd29, 8'd36, 8'd37:        s_word = 32'h0000_0001;
        8'd21:                                           s_word = (f_scenario == 3'd2) ? 32'd0 : 32'h0000_0001;
        8'd32:                                           s_word = 32'h0000_0002;
        8'd49:                                           s_word = (f_scenario == 3'd4) ? 32'h0500_0000 : 32'h0100_0000;
        default:                                         s_word = 32'd0;
      endcase
      return s_word;
    end
  endfunction

  assign f_scenario    = FormalScenario;
  assign scenario      = f_scenario;
  assign cycle         = s_cycle_q;
  assign request_count = s_request_count_q;
  assign abort_seen    = s_abort_seen_q;
  assign fault_seen    = s_fault_seen_q;
  assign load_seen     = s_load_seen_q;
  assign store_seen    = s_store_seen_q;
  assign s_dma_data    = image_word(8'(((s_dma_addr_q - 32'h0000_1000) >> 2) + s_dma_beat_q));
  assign s_dma_last    = s_dma_beat_q == ((s_dma_bytes_q >> 2) - 1'b1);

  apu_microcode_loader #(
      .PathStackDepth(2)
  ) u_dut (
      .clk_i,
      .rst_n_i,
      .start_i            (s_cycle_q == 7'd1),
      .abort_i            ((f_scenario == 3'd5) && (s_cycle_q == 7'd24)),
      .resource_reset_i   ((f_scenario == 3'd6) && (s_cycle_q == 7'd24)),
      .soft_reset_i       (1'b0),
      .counter_clear_i    (1'b0),
      .image_addr_i       (32'h0000_1000),
      .image_size_i       (32'd200),
      .expected_crc_i     (32'h62e4_edd1),
      .dma_request_valid_o(s_request_valid),
      .dma_request_ready_i(1'b1),
      .dma_request_addr_o (s_request_addr),
      .dma_request_bytes_o(s_request_bytes),
      .dma_data_i         (s_dma_data),
      .dma_keep_i         (4'hf),
      .dma_last_i         (s_dma_last),
      .dma_valid_i        (s_dma_active_q),
      .dma_ready_o        (s_dma_ready),
      .dma_done_i         (s_dma_done_q),
      .dma_err_i          (1'b0),
      .dma_err_code_i     (6'd0),
      .dma_err_stage_i    (4'd0),
      .dma_err_resp_i     (2'd0),
      .dma_err_addr_i     (32'd0),
      .store_active_o     (),
      .store_read_o       (s_store_read),
      .store_write_o      (store_write),
      .store_addr_o       (store_addr),
      .store_data_o       (s_store_write_data),
      .store_data_i       (s_store_read_data_q),
      .store_valid_i      (s_store_valid_q),
      .stat_o             (status),
      .abi_o              (),
      .build_id_o         (),
      .lock_o             (lock),
      .actual_crc_o       (actual_crc),
      .load_count_o       (),
      .entry_pc_o         (),
      .entry_first_o      (),
      .entry_last_o       (),
      .entry_max_loop_o   (),
      .entry_max_retired_o(),
      .load_done_o        (load_done),
      .abort_done_o       (abort_done),
      .fault_valid_o      (fault_valid),
      .fault_code_o       (fault_code),
      .fault_stage_o      (fault_stage),
      .fault_resp_o       (fault_resp),
      .fault_addr_o       (fault_addr),
      .fault_detail_o     (fault_detail),
      .idle_o             ()
  );

  initial begin
    rst_n_i      = 1'b0;
    f_past_valid = 1'b0;
  end

  always_ff @(posedge clk_i) begin
    rst_n_i      <= 1'b1;
    f_past_valid <= 1'b1;
    if (!rst_n_i) begin
      s_cycle_q           <= 7'd0;
      s_dma_active_q      <= 1'b0;
      s_dma_done_q        <= 1'b0;
      s_dma_addr_q        <= 32'd0;
      s_dma_bytes_q       <= 32'd0;
      s_dma_beat_q        <= 8'd0;
      s_request_count_q   <= 2'd0;
      s_store_valid_q     <= 1'b0;
      s_store_word_q      <= 64'd0;
      s_store_read_data_q <= 64'd0;
      s_abort_seen_q      <= 1'b0;
      s_fault_seen_q      <= 1'b0;
      s_load_seen_q       <= 1'b0;
      s_store_seen_q      <= 1'b0;
    end else begin
      if (s_cycle_q != 7'h7f) s_cycle_q <= s_cycle_q + 1'b1;
      s_dma_done_q    <= 1'b0;
      s_store_valid_q <= s_store_read;
      if (s_request_valid && !s_dma_active_q) begin
        s_dma_active_q    <= 1'b1;
        s_dma_addr_q      <= s_request_addr;
        s_dma_bytes_q     <= s_request_bytes;
        s_dma_beat_q      <= 8'd0;
        s_request_count_q <= s_request_count_q + 1'b1;
      end
      if (s_dma_active_q &&
          (s_dma_ready || (((f_scenario == 3'd5) || (f_scenario == 3'd6)) &&
                           (s_cycle_q >= 7'd24)))) begin
        if (s_dma_last) begin
          s_dma_active_q <= 1'b0;
          s_dma_done_q   <= 1'b1;
        end else begin
          s_dma_beat_q <= s_dma_beat_q + 1'b1;
        end
      end
      if (store_write && (store_addr == 11'd0)) begin
        s_store_word_q <= s_store_write_data;
        s_store_seen_q <= 1'b1;
      end
      if (s_store_read) begin
        s_store_read_data_q <= (store_addr == 11'd0) ? s_store_word_q : 64'd0;
      end
      if (abort_done) s_abort_seen_q <= 1'b1;
      if (fault_valid && (fault_code == 6'd21)) s_fault_seen_q <= 1'b1;
      if (load_done) s_load_seen_q <= 1'b1;
    end
  end
endmodule

`undef APU_LOADER_FORMAL_SCENARIO
