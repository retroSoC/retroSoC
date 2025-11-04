// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module spisd_cache (
    // verilog_format: off
    input logic         clk_i,
    input logic         rst_n_i,
    input logic         mode_i,
    input logic         init_done_i,
    input logic         wr_sync_i,
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
    nmi_if.slave        nmi
    // verilog_format: on
);

  // verilog_format: off
  localparam FSM_IDLE     = 2'd0;
  localparam FSM_COMP_TAG = 2'd1;
  localparam FSM_ALLOC    = 2'd2;
  localparam FSM_WR_BACK  = 2'd3;
  // verilog_format: on

  logic s_cache_mem_hit, s_cache_byp_hit;
  logic [6:0] s_cache_index;
  logic s_cache_valid_d, s_cache_valid_q;
  logic s_cache_dirty_d, s_cache_dirty_q;
  logic [31:0] s_cache_tag_d, s_cache_tag_q;
  logic [1:0] s_cache_fsm_d, s_cache_fsm_q;
  logic [31:0] s_cache_data_d[0:127];
  logic [31:0] s_cache_data_q[0:127];
  // sd if
  logic [7:0] s_sd_wr_data_d, s_sd_wr_data_q;
  // common
  logic [6:0] s_line_cnt_d, s_line_cnt_q;
  logic [1:0] s_word_cnt_d, s_word_cnt_q;
  logic [31:0] s_word_data_d, s_word_data_q;

  // io
  assign sd_wr_data_o    = s_sd_wr_data_q;
  assign nmi.rdata       = s_cache_data_q[s_cache_index];
  // cache
  assign s_cache_index   = nmi.addr[8:2];
  assign s_cache_mem_hit = ~mode_i && (nmi.addr[27:9] == s_cache_tag_q[18:0]);
  assign s_cache_byp_hit = mode_i && (nmi.addr == s_cache_tag_q);

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
    nmi.ready       = '0;
    unique case (s_cache_fsm_q)
      FSM_IDLE: begin
        if (init_done_i) begin
          if (nmi.valid) s_cache_fsm_d = FSM_COMP_TAG;
          // sw wr sync
          else if (wr_sync_i && s_cache_dirty_q) begin
            s_cache_fsm_d   = FSM_WR_BACK;
            s_cache_dirty_d = 1'b0;
          end
        end
      end
      FSM_COMP_TAG: begin
        // cache hit
        if ((s_cache_mem_hit || s_cache_byp_hit) && s_cache_valid_q) begin
          nmi.ready = 1'b1;
          // write oper, set dirty
          if (|nmi.wstrb) begin
            s_cache_dirty_d = 1'b1;
            if (nmi.wstrb[0]) s_cache_data_d[s_cache_index][7:0] = nmi.wdata[7:0];
            if (nmi.wstrb[1]) s_cache_data_d[s_cache_index][15:8] = nmi.wdata[15:8];
            if (nmi.wstrb[2]) s_cache_data_d[s_cache_index][23:16] = nmi.wdata[23:16];
            if (nmi.wstrb[3]) s_cache_data_d[s_cache_index][31:24] = nmi.wdata[31:24];
          end
          s_cache_fsm_d = FSM_IDLE;
        end else begin
          // need to update tag line info
          s_cache_valid_d = 1'b1;
          s_cache_dirty_d = |nmi.wstrb;
          // tag line is clean
          if (s_cache_valid_q == 1'b0 || s_cache_dirty_q == 1'b0) begin
            s_cache_fsm_d = FSM_ALLOC;
            if (~mode_i) s_cache_tag_d = {13'd0, nmi.addr[27:9]};
            else s_cache_tag_d = nmi.addr;
          end else begin
            // need to flush data into sd card sectors
            s_cache_fsm_d = FSM_WR_BACK;
          end
        end
      end
      FSM_ALLOC: begin
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
            if (s_line_cnt_q == 7'd127) s_cache_fsm_d = FSM_COMP_TAG;
          end else begin
            s_word_cnt_d  = s_word_cnt_q + 1'b1;
            s_word_data_d = {sd_rd_data_i, s_word_data_q[31:8]};
          end
        end
      end
      FSM_WR_BACK: begin
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
                s_cache_fsm_d = FSM_ALLOC;
                if (~mode_i) s_cache_tag_d = {13'd0, nmi.addr[27:9]};
                else s_cache_tag_d = nmi.addr;
              end
            end else begin
              s_word_cnt_d  = s_word_cnt_q + 1'b1;
              s_word_data_d = {8'd0, s_word_data_q[31:8]};
            end
          end
        end
      end
    endcase
  end

  dffr #(2) u_cache_fsm_dffr (
      clk_i,
      rst_n_i,
      s_cache_fsm_d,
      s_cache_fsm_q
  );

  dffr #(1) u_cache_valid_dffr (
      clk_i,
      rst_n_i,
      s_cache_valid_d,
      s_cache_valid_q
  );

  dffr #(1) u_cache_dirty_dffr (
      clk_i,
      rst_n_i,
      s_cache_dirty_d,
      s_cache_dirty_q
  );

  dffr #(32) u_cache_tag_dffr (
      clk_i,
      rst_n_i,
      s_cache_tag_d,
      s_cache_tag_q
  );

  dffr #(7) u_line_cnt_dffr (
      clk_i,
      rst_n_i,
      s_line_cnt_d,
      s_line_cnt_q
  );

  dffr #(2) u_word_cnt_dffr (
      clk_i,
      rst_n_i,
      s_word_cnt_d,
      s_word_cnt_q
  );

  dffr #(8) u_s_sd_wr_data_dffr (
      clk_i,
      rst_n_i,
      s_sd_wr_data_d,
      s_sd_wr_data_q
  );

  dffr #(32) u_word_data_dffr (
      clk_i,
      rst_n_i,
      s_word_data_d,
      s_word_data_q
  );

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (~rst_n_i) begin
      for (int i = 0; i < 128; ++i) s_cache_data_q[i] <= '0;
    end else s_cache_data_q <= s_cache_data_d;
  end

endmodule
