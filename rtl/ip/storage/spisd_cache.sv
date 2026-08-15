// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module spisd_cache (
    // verilog_format: off -- preserve reviewed column alignment
    input logic         clk_i,
    input logic         rst_n_i,
    input logic         mode_i,
    input logic         init_done_i,
    input logic         wr_sync_i,
    output logic        wr_sync_done_o,
    input logic         fir_clk_edge_i,
    output logic [31:0] sd_addr_o,
    output logic        sd_rd_req_o,
    input logic         sd_rd_vld_i,
    input logic [ 7:0]  sd_rd_data_i,
    input logic         sd_rd_busy_i,
    output logic        sd_wr_req_o,
    input logic         sd_wr_data_req_i,
    output logic [7:0]  sd_wr_data_o,
    input logic         sd_wr_busy_i,
    ribp_if.slave       ribp
    // verilog_format: on
);

  // This single-clock cache accepts one RIBP request through its state machine;
  // cache misses backpressure until media fill/writeback completes. It reports
  // no response errors.
  typedef enum logic [1:0] {
    Idle       = 2'd0,
    CompareTag = 2'd1,
    Allocate   = 2'd2,
    WriteBack  = 2'd3
  } cache_state_e;

  logic s_cache_mem_hit, s_cache_byp_hit;
  logic [6:0] s_cache_index;
  logic s_cache_valid_d, s_cache_valid_q;
  logic s_cache_dirty_d, s_cache_dirty_q;
  logic [31:0] s_cache_tag_d, s_cache_tag_q;
  cache_state_e s_cache_fsm_d, s_cache_fsm_q;
  logic [ 1:0] s_cache_fsm_bits_q;
  logic [31:0] s_cache_data_d     [0:127];
  logic [31:0] s_cache_data_q     [0:127];
  // sd if
  logic [7:0] s_sd_wr_data_d, s_sd_wr_data_q;
  // common
  logic [6:0] s_line_cnt_d, s_line_cnt_q;
  logic [1:0] s_word_cnt_d, s_word_cnt_q;
  logic [31:0] s_word_data_d, s_word_data_q;
  // wr sync
  logic s_wr_sync_d, s_wr_sync_q;

  // io
  assign sd_wr_data_o    = s_sd_wr_data_q;
  assign ribp.rdata      = s_cache_data_q[s_cache_index];
  // cache
  assign s_cache_index   = ribp.addr[8:2];
  assign s_cache_mem_hit = ~mode_i && (ribp.addr[27:9] == s_cache_tag_q[18:0]);
  assign s_cache_byp_hit = mode_i && (ribp.addr == s_cache_tag_q);
  assign s_cache_fsm_q   = cache_state_e'(s_cache_fsm_bits_q);

  always_comb begin
    // cache
    s_cache_valid_d = s_cache_valid_q;
    s_cache_dirty_d = s_cache_dirty_q;
    s_cache_tag_d   = s_cache_tag_q;
    s_cache_fsm_d   = s_cache_fsm_q;
    s_cache_data_d  = s_cache_data_q;
    // intern
    s_line_cnt_d    = s_line_cnt_q;
    s_word_cnt_d    = s_word_cnt_q;
    s_word_data_d   = s_word_data_q;
    // sd_if
    sd_rd_req_o     = '0;
    sd_wr_req_o     = '0;
    s_sd_wr_data_d  = s_sd_wr_data_q;
    sd_addr_o       = '0;
    // mem_if
    ribp.ready      = '0;
    ribp.resp_err   = 1'b0;
    // wr sync
    wr_sync_done_o  = '0;
    unique case (s_cache_fsm_q)
      Idle: begin
        if (init_done_i) begin
          if (ribp.valid) s_cache_fsm_d = CompareTag;
          // sw wr sync
          else if (wr_sync_i && s_cache_dirty_q) begin
            s_cache_fsm_d   = WriteBack;
            s_cache_dirty_d = 1'b0;
          end
        end
      end
      CompareTag: begin
        // cache hit
        if ((s_cache_mem_hit || s_cache_byp_hit) && s_cache_valid_q) begin
          if (s_wr_sync_q) wr_sync_done_o = 1'b1;  // wr sync oper
          else begin
            ribp.ready = 1'b1;  // nomral oper
            // write oper, set dirty
            if (|ribp.wstrb) begin
              s_cache_dirty_d = 1'b1;
              if (ribp.wstrb[0]) s_cache_data_d[s_cache_index][7:0] = ribp.wdata[7:0];
              if (ribp.wstrb[1]) s_cache_data_d[s_cache_index][15:8] = ribp.wdata[15:8];
              if (ribp.wstrb[2]) s_cache_data_d[s_cache_index][23:16] = ribp.wdata[23:16];
              if (ribp.wstrb[3]) s_cache_data_d[s_cache_index][31:24] = ribp.wdata[31:24];
            end
          end
          s_cache_fsm_d = Idle;
        end else begin
          // need to update tag line info
          s_cache_valid_d = 1'b1;
          s_cache_dirty_d = |ribp.wstrb;
          // tag line is clean
          if (s_cache_valid_q == 1'b0 || s_cache_dirty_q == 1'b0) begin
            s_cache_fsm_d = Allocate;
            if (~mode_i) s_cache_tag_d = {13'd0, ribp.addr[27:9]};
            else s_cache_tag_d = ribp.addr;
          end else begin
            // need to flush data into sd card sectors
            s_cache_fsm_d = WriteBack;
          end
        end
      end
      Allocate: begin
        if (~sd_rd_busy_i) begin
          sd_rd_req_o  = 1'b1;
          sd_addr_o    = s_cache_tag_q;
          s_line_cnt_d = '0;
          s_word_cnt_d = '0;
        end else if (fir_clk_edge_i && sd_rd_vld_i) begin
          if (s_word_cnt_q == 2'd3) begin
            s_word_cnt_d                 = '0;
            s_line_cnt_d                 = s_line_cnt_q + 1'b1;
            s_cache_data_d[s_line_cnt_q] = {sd_rd_data_i, s_word_data_q[31:8]};
            if (s_line_cnt_q == 7'd127) s_cache_fsm_d = CompareTag;
          end else begin
            s_word_cnt_d  = s_word_cnt_q + 1'b1;
            s_word_data_d = {sd_rd_data_i, s_word_data_q[31:8]};
          end
        end
      end
      WriteBack: begin
        if (~sd_wr_busy_i) begin
          sd_wr_req_o   = 1'b1;
          sd_addr_o     = s_cache_tag_q;
          s_line_cnt_d  = '0;
          s_word_cnt_d  = '0;
          s_word_data_d = s_cache_data_q[0];
        end else begin
          // 0 1 2 3
          if (fir_clk_edge_i && sd_wr_data_req_i) begin
            s_sd_wr_data_d = s_word_data_q[7:0];
            if (s_word_cnt_q == 2'd3) begin
              s_word_cnt_d  = '0;
              s_line_cnt_d  = s_line_cnt_q + 1'b1;
              s_word_data_d = s_cache_data_q[s_line_cnt_d];
              if (s_line_cnt_q == 7'd127) begin
                s_cache_fsm_d = Allocate;
                if (~mode_i) s_cache_tag_d = {13'd0, ribp.addr[27:9]};
                else s_cache_tag_d = ribp.addr;
              end
            end else begin
              s_word_cnt_d  = s_word_cnt_q + 1'b1;
              s_word_data_d = {8'd0, s_word_data_q[31:8]};
            end
          end
        end
      end
      default: begin
        // Preserve the legacy illegal-state hold through the default assignments.
      end
    endcase
  end

  dffr #(
      .DATA_WIDTH(2)
  ) u_cache_fsm_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_cache_fsm_d),
      .dat_o  (s_cache_fsm_bits_q)
  );

  dffr #(
      .DATA_WIDTH(1)
  ) u_cache_valid_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_cache_valid_d),
      .dat_o  (s_cache_valid_q)
  );

  dffr #(
      .DATA_WIDTH(1)
  ) u_cache_dirty_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_cache_dirty_d),
      .dat_o  (s_cache_dirty_q)
  );

  dffr #(
      .DATA_WIDTH(32)
  ) u_cache_tag_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_cache_tag_d),
      .dat_o  (s_cache_tag_q)
  );

  dffr #(
      .DATA_WIDTH(7)
  ) u_line_cnt_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_line_cnt_d),
      .dat_o  (s_line_cnt_q)
  );

  dffr #(
      .DATA_WIDTH(2)
  ) u_word_cnt_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_word_cnt_d),
      .dat_o  (s_word_cnt_q)
  );

  dffr #(
      .DATA_WIDTH(8)
  ) u_s_sd_wr_data_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_sd_wr_data_d),
      .dat_o  (s_sd_wr_data_q)
  );

  dffr #(
      .DATA_WIDTH(32)
  ) u_word_data_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_word_data_d),
      .dat_o  (s_word_data_q)
  );

  // This is inferred cache-array storage; a Common DFF bank would not preserve
  // array write semantics or the intended memory inference.
  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (~rst_n_i) begin
      for (int i = 0; i < 128; ++i) s_cache_data_q[i] <= '0;
    end else s_cache_data_q <= s_cache_data_d;
  end

  // wr sync oper
  always_comb begin
    s_wr_sync_d = s_wr_sync_q;
    if (wr_sync_i) s_wr_sync_d = 1'b1;
    else if (wr_sync_done_o) s_wr_sync_d = 1'b0;
  end
  dffr #(
      .DATA_WIDTH(1)
  ) u_wr_sync_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_wr_sync_d),
      .dat_o  (s_wr_sync_q)
  );

endmodule
