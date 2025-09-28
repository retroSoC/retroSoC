// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.
//
// memory-map rd/wr for first 256MB range of TF card
// cache size: 512(width 9) [8:0]
// tag width: 23 [22:0]

module nmi_spisd (
    // verilog_format: off
    input  logic clk_i,
    input  logic rst_n_i,
    nmi_if.slave nmi,
    spi_if.dut   spi
    // verilog_format: on
);

`ifndef SPISD_UNIT_TEST
  // verilog_format: off
  localparam FSM_IDLE     = 2'd0;
  localparam FSM_COMP_TAG = 2'd1;
  localparam FSM_ALLOC    = 2'd2;
  localparam FSM_WR_BACK  = 2'd3;
  // verilog_format: on

  logic [1:0] s_clkdiv_d, s_clkdiv_q;
  logic       s_cfg_reg_sel;
  logic       s_mem_ready;

  logic [6:0] s_cache_index;
  logic s_cache_valid_d, s_cache_valid_q;
  logic s_cache_dirty_d, s_cache_dirty_q;
  logic [22:0] s_cache_tag_d, s_cache_tag_q;
  logic [1:0] s_cache_fsm_d, s_cache_fsm_q;
  logic [31:0] s_cache_data_d   [0:127];
  logic [31:0] s_cache_data_q   [0:127];
  // sd if
  logic [31:0] s_sd_addr;
  logic        s_sd_rd_req;
  logic        s_sd_rd_vld;
  logic [ 7:0] s_sd_rd_data;
  logic        s_sd_rd_busy;
  logic        s_sd_wr_req;
  logic        s_sd_wr_data_req;
  logic        s_sd_wr_busy;
  logic [7:0] s_sd_wr_data_d, s_sd_wr_data_q;
  // common
  logic s_init_done;
  logic s_fir_clk_edge;
  logic [6:0] s_line_cnt_d, s_line_cnt_q;
  logic [1:0] s_word_cnt_d, s_word_cnt_q;
  logic [31:0] s_word_data_d, s_word_data_q;


  assign s_cfg_reg_sel = nmi.addr[31:24] == 8'h10 && nmi.addr[15:8] == 8'h50;
  assign nmi.ready     = nmi.addr[31:24] == 8'h50 ? s_mem_ready : 1'b1;
  assign nmi.rdata     = nmi.addr[31:24] == 8'h50 ? s_cache_data_q[s_cache_index] : s_clkdiv_q;

  always_comb begin
    s_clkdiv_d = s_clkdiv_q;
    if (nmi.valid && nmi.wstrb[0] && s_cfg_reg_sel && nmi.addr[7:0] == 8'h00) begin
      s_clkdiv_d = nmi.wdata[1:0];
    end
  end
  dffr #(2) u_clkdiv_dffr (
      clk_i,
      rst_n_i,
      s_clkdiv_d,
      s_clkdiv_q
  );


  assign s_cache_index = nmi.addr[8:2];
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
    s_sd_wr_data_d  = s_sd_wr_data_q;
    s_sd_addr       = '0;
    // mem_if
    s_mem_ready     = '0;
    if (nmi.addr[31:24] == 8'h50) begin
      unique case (s_cache_fsm_q)
        FSM_IDLE: begin
          if (s_init_done && nmi.valid) s_cache_fsm_d = FSM_COMP_TAG;
        end
        FSM_COMP_TAG: begin
          // cache hit
          if (nmi.addr[27:9] == s_cache_tag_q[18:0] && s_cache_valid_q) begin
            s_mem_ready = 1'b1;
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
              s_cache_tag_d = {4'd0, nmi.addr[27:9]};
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
              s_cache_data_d[s_line_cnt_q] = {s_sd_rd_data, s_word_data_q[31:8]};
              if (s_line_cnt_q == 7'd127) s_cache_fsm_d = FSM_COMP_TAG;
            end else begin
              s_word_cnt_d  = s_word_cnt_q + 1'b1;
              s_word_data_d = {s_sd_rd_data, s_word_data_q[31:8]};
            end
          end
        end
        FSM_WR_BACK: begin
          if (~s_sd_wr_busy) begin
            s_sd_wr_req   = 1'b1;
            s_sd_addr     = {s_cache_tag_q, 9'd0};
            s_line_cnt_d  = '0;
            s_word_cnt_d  = '0;
            s_word_data_d = s_cache_data_q[0];
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
                  s_cache_tag_d = {4'd0, nmi.addr[27:9]};
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
      .cfg_clkdiv_i  (s_clkdiv_q),
      .fir_clk_edge_o(s_fir_clk_edge),
      .init_done_o   (s_init_done),
      .sec_addr_i    (s_sd_addr),
      .rd_req_i      (s_sd_rd_req),
      .rd_data_vld_o (s_sd_rd_vld),
      .rd_data_o     (s_sd_rd_data),
      .rd_busy_o     (s_sd_rd_busy),
      .wr_req_i      (s_sd_wr_req),
      .wr_data_req_o (s_sd_wr_data_req),
      .wr_data_i     (s_sd_wr_data_q),
      .wr_busy_o     (s_sd_wr_busy),
      .spisd_clk_o   (spi.spi_sck_o),
      .spisd_cs_o    (spi.spi_nss_o),
      .spisd_mosi_o  (spi.spi_mosi_o),
      .spisd_miso_i  (spi.spi_miso_i)
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

  assign s_mem_ready = '0;
  assign nmi.rdata   = '0;
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
      .cfg_clkdiv_i  (cfg_clkdiv_i),
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
      .spisd_clk_o   (spi.spi_sck_o),
      .spisd_cs_o    (spi.spi_nss_o),
      .spisd_mosi_o  (spi.spi_mosi_o),
      .spisd_miso_i  (spi.spi_miso_i)
  );
`endif

endmodule
