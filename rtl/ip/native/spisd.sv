// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// spisd is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.
//
// memory-map rd/wr for first 512MB range of TF card
// cache size: 512(width 9) [8:0]
// tag width: 23 [22:0]
module spisd (
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        mem_valid_i,
    output logic        mem_ready_o,
    input  logic [31:0] mem_addr_i,
    input  logic [31:0] mem_wdata_i,
    input  logic [ 3:0] mem_wstrb_i,
    output logic [31:0] mem_rdata_o,
    output logic        spisd_sclk_o,
    output logic        spisd_cs_o,
    output logic        spisd_mosi_o,
    input  logic        spisd_miso_i
);

`ifndef SPISD_UNIT_TEST
  // verilog_format: off
  localparam FSM_IDLE     = 2'd0;
  localparam FSM_COMP_TAG = 2'd1;
  localparam FSM_ALLOC    = 2'd2;
  localparam FSM_WR_BACK  = 2'd3;
  // verilog_format: on
  logic [6:0] s_cache_index;
  logic s_cache_valid_d, s_cache_valid_q;
  logic s_cache_dirty_d, s_cache_dirty_q;
  logic [22:0] s_cache_tag_d, s_cache_tag_q;
  logic [1:0] s_cache_fsm_d, s_cache_fsm_q;
  logic [31:0] s_cache_data_d   [0:128];
  logic [31:0] s_cache_data_q   [0:128];
  // sd if
  logic [22:0] s_sd_addr;
  logic        s_sd_rd_req;
  logic        s_sd_rd_vld;
  logic [ 7:0] s_sd_rd_data;
  logic        s_sd_rd_busy;
  logic        s_sd_wr_req;
  logic        s_sd_wr_data_req;
  logic        s_sd_wr_busy;
  logic s_sd_wr_first_d, s_sd_wr_first_q;
  logic [7:0] s_sd_wr_data_d, s_sd_wr_data_q;
  // common
  logic s_init_done;
  logic s_fir_clk_edge;
  logic [6:0] s_line_cnt_d, s_line_cnt_q;
  logic [1:0] s_word_cnt_d, s_word_cnt_q;
  logic [31:0] s_word_data_d, s_word_data_q;

  assign s_cache_index = mem_addr_i[8:2];

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
    s_sd_rd_req     = '0;
    s_sd_wr_req     = '0;
    s_sd_wr_first_d = s_sd_wr_first_q;
    s_sd_wr_data_d  = s_sd_wr_data_q;
    s_sd_addr       = '0;
    // mem_if
    mem_ready_o     = '0;
    mem_rdata_o     = s_cache_data_q[s_cache_index];

    unique case (s_cache_fsm_q)
      FSM_IDLE: begin
        if (s_init_done && mem_valid_i) s_cache_fsm_d = FSM_COMP_TAG;
      end
      FSM_COMP_TAG: begin
        // cache hit
        if (mem_addr_i[27:9] == s_cache_tag_q && s_cache_valid_q) begin
          mem_ready_o = 1'b1;
          // write oper, set dirty
          if (|mem_wstrb_i) begin
            s_cache_dirty_d = 1'b1;
            if (mem_wstrb_i[0]) s_cache_data_d[s_cache_index][7:0] = mem_wdata_i[7:0];
            if (mem_wstrb_i[1]) s_cache_data_d[s_cache_index][15:8] = mem_wdata_i[15:8];
            if (mem_wstrb_i[2]) s_cache_data_d[s_cache_index][23:16] = mem_wdata_i[23:16];
            if (mem_wstrb_i[3]) s_cache_data_d[s_cache_index][31:24] = mem_wdata_i[31:24];
          end
          s_cache_fsm_d = FSM_IDLE;
        end else begin
          // need to update tag line info
          s_cache_valid_d = 1'b1;
          s_cache_dirty_d = |mem_wstrb_i;
          // tag line is clean
          if (s_cache_valid_q == 1'b0 || s_cache_dirty_q == 1'b0) begin
            s_cache_fsm_d = FSM_ALLOC;
            s_cache_tag_d = mem_addr_i[27:9];
          end else begin
            // need to flush data into sd card sectors
            s_cache_fsm_d = FSM_WR_BACK;
          end
        end
      end
      FSM_ALLOC: begin
        if (~s_sd_rd_busy) begin
          s_sd_rd_req  = 1'b1;
          s_sd_addr    = {s_cache_tag_q, 9'd0};
          s_line_cnt_d = '0;
          s_word_cnt_d = '0;
        end else if (s_fir_clk_edge && s_sd_rd_vld) begin
          if (s_word_cnt_q == 2'd3) begin
            s_word_cnt_d                 = '0;
            s_line_cnt_d                 = s_line_cnt_q + 1'b1;
            s_cache_data_d[s_line_cnt_q] = {s_sd_rd_data, s_word_data_q};
            if (s_line_cnt_q == 7'd127) s_cache_fsm_d = FSM_COMP_TAG;
          end else begin
            s_word_cnt_d  = s_word_cnt_q + 1'b1;
            s_word_data_d = {s_sd_rd_data, s_word_data_q[31:8]};
          end
        end
      end
      FSM_WR_BACK: begin
        if (~s_sd_wr_busy) begin
          s_sd_wr_req     = 1'b1;
          s_sd_addr       = {s_cache_tag_q, 9'd0};
          s_line_cnt_d    = '0;
          s_word_cnt_d    = '0;
          s_word_data_d   = s_cache_data_q[0];
          s_sd_wr_first_d = 1'b1;
        end else begin
          // 0 1 2 3
          if (s_fir_clk_edge && s_sd_wr_data_req) begin
            s_sd_wr_data_d = s_word_data_q[7:0];
            if (s_word_cnt_q == 2'd3) begin
              s_word_cnt_d  = '0;
              s_line_cnt_d  = s_line_cnt_q + 1'b1;
              s_word_data_d = s_cache_data_q[s_line_cnt_d];
              if (s_line_cnt_q == 7'd127) begin
                s_cache_fsm_d = FSM_ALLOC;
                s_cache_tag_d = mem_addr_i[27:9];
              end
            end else begin
              if (s_sd_wr_first_q == 1'b0) begin
                s_word_cnt_d  = s_word_cnt_q + 1'b1;
                s_word_data_d = {8'd0, s_word_data_q[31:8]};
              end else begin
                s_sd_wr_first_d = 1'b0;
                s_word_cnt_d    = 1'b0;
              end
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

  dffr #(23) u_cache_tag_dffr (
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

  dffr #(1) u_s_sd_wr_first_dffr (
      clk_i,
      rst_n_i,
      s_sd_wr_first_d,
      s_sd_wr_first_q
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

  spisd_core u_spisd_core (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .fir_clk_edge_o(s_fir_clk_edge),
      .init_done_o   (s_init_done),
      .sec_addr_i    ({9'd0, s_sd_addr}),
      .rd_req_i      (s_sd_rd_req),
      .rd_data_vld_o (s_sd_rd_vld),
      .rd_data_o     (s_sd_rd_data),
      .rd_busy_o     (s_sd_rd_busy),
      .wr_req_i      (s_sd_wr_req),
      .wr_data_req_o (s_sd_wr_data_req),
      .wr_data_i     (s_sd_wr_data_q),
      .wr_busy_o     (s_sd_wr_busy),
      .spisd_clk_o   (spisd_sclk_o),
      .spisd_cs_o    (spisd_cs_o),
      .spisd_mosi_o  (spisd_mosi_o),
      .spisd_miso_i  (spisd_miso_i)
  );

`else
  // data gen test
  logic        s_init_done;
  logic [31:0] s_sec_addr;
  logic        s_rd_req;
  logic        s_rd_data_vld;
  logic [ 7:0] s_rd_data;
  logic        s_wr_req;
  logic        s_wr_busy;
  logic        s_wr_data_req;
  logic [ 7:0] s_wr_data;
  logic        s_fir_clk_edge;

  assign mem_ready_o = '0;
  assign mem_rdata_o = '0;
  spisd_data u_spisd_data (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .fir_clk_edge_i(s_fir_clk_edge),
      .init_done_i   (s_init_done),
      .sec_addr_o    (s_sec_addr),
      .rd_req_o      (s_rd_req),
      .rd_data_vld_i (s_rd_data_vld),
      .rd_data_i     (s_rd_data),
      .wr_req_o      (s_wr_req),
      .wr_data_req_i (s_wr_data_req),
      .wr_data_o     (s_wr_data),
      .wr_busy_i     (s_wr_busy)
  );


  spisd_core u_spisd_core (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .fir_clk_edge_o(s_fir_clk_edge),
      .init_done_o   (s_init_done),
      .sec_addr_i    (s_sec_addr),
      .rd_req_i      (s_rd_req),
      .rd_data_vld_o (s_rd_data_vld),
      .rd_data_o     (s_rd_data),
      .rd_busy_o     (),
      .wr_req_i      (s_wr_req),
      .wr_data_req_o (s_wr_data_req),
      .wr_data_i     (s_wr_data),
      .wr_busy_o     (s_wr_busy),
      .spisd_clk_o   (spisd_sclk_o),
      .spisd_cs_o    (spisd_cs_o),
      .spisd_mosi_o  (spisd_mosi_o),
      .spisd_miso_i  (spisd_miso_i)
  );
`endif

endmodule
