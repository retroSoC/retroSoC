// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

`include "dvp_define.svh"

module dvp_reg (
    // verilog_format: off
    input  logic         clk_i,
    input  logic         rst_n_i,
    ribp_if.slave        ribp,
    input  logic         active_i,
    input  logic         fifo_empty_i,
    input  logic         fifo_full_i,
    input  logic [31:0]  rx_data_i,
    input  logic         frame_start_i,
    input  logic         line_done_i,
    input  logic         frame_done_i,
    input  logic         error_event_i,
    input  logic [ 5:0]  error_flags_i,
    input  logic [127:0] frame_stats_i,
    input  logic         frame_stats_valid_i,
    output logic [127:0] config_o,
    output logic         config_valid_o,
    output logic         command_abort_o,
    output logic         command_flush_o,
    output logic         command_valid_o,
    input  logic         command_ready_i,
    output logic         rx_pop_o,
    input  logic         config_ready_i,
    output logic         stream_enable_o,
    output logic         irq_o
    // verilog_format: on
);
  localparam logic [31:0] IP_VERSION = 32'h0002_0000;
  localparam logic [31:0] CAPABILITY = 32'h0000_3F7F;
  localparam logic [31:0] CTRL_MASK = 32'h0000_0007;
  localparam logic [31:0] STREAM_MASK = 32'h0000_0001;
  localparam logic [31:0] FORMAT_MASK = 32'h0000_000F;
  localparam logic [31:0] SYNC_MASK = 32'h0000_0007;

  logic        s_req;
  logic        s_write;
  logic        s_accept;
  logic [11:0] s_offset;
  logic        s_aligned;
  logic        s_access_err;
  logic        s_ready_q;
  logic s_resp_err_d, s_resp_err_q;
  logic [31:0] s_rdata_d, s_rdata_q;
  logic [31:0] s_ctrl_d, s_ctrl_q;
  logic [31:0] s_stream_d, s_stream_q;
  logic [31:0] s_format_d, s_format_q;
  logic [31:0] s_sync_d, s_sync_q;
  logic [31:0] s_frame_size_d, s_frame_size_q;
  logic [31:0] s_crop_start_d, s_crop_start_q;
  logic [31:0] s_crop_size_d, s_crop_size_q;
  logic [5:0] s_err_q;
  logic [6:0] s_intr_stat_q;
  logic [6:0] s_intr_en_q;
  logic [31:0] s_frm_cnt_q, s_line_cnt_q;
  logic [31:0] s_pixel_cnt_q, s_word_cnt_q, s_drop_cnt_q;
  logic [31:0] s_cfg_seq_d, s_cfg_seq_q;
  logic [31:0] s_cfg_sent_q;
  logic [ 1:0] s_cmd_q;

  function automatic logic [31:0] merge_wstrb(input logic [31:0] current, input logic [31:0] value,
                                              input logic [3:0] strobe);
    logic [31:0] merged;
    begin
      merged = current;
      for (int index = 0; index < 4; index++) begin
        if (strobe[index]) merged[index*8+:8] = value[index*8+:8];
      end
      return merged;
    end
  endfunction

  assign s_req           = ribp.valid && !s_ready_q;
  assign s_write         = |ribp.wstrb;
  assign s_accept        = s_req;
  assign s_offset        = ribp.addr[11:0];
  assign s_aligned       = ribp.addr[1:0] == 2'b00;
  assign ribp.ready      = s_ready_q;
  assign ribp.rdata      = s_rdata_q;
  assign ribp.resp_err   = s_resp_err_q;
  assign stream_enable_o = s_stream_q[`DVP_STREAM_ENABLE];
  always_comb begin
    config_o          = '0;
    config_o[15:0]    = s_frame_size_q[15:0];
    config_o[31:16]   = s_frame_size_q[31:16];
    config_o[47:32]   = s_crop_start_q[15:0];
    config_o[63:48]   = s_crop_start_q[31:16];
    config_o[79:64]   = s_crop_size_q[15:0];
    config_o[95:80]   = s_crop_size_q[31:16];
    config_o[96]      = s_ctrl_q[`DVP_CTRL_ENABLE];
    config_o[97]      = s_ctrl_q[`DVP_CTRL_SNAPSHOT];
    config_o[98]      = s_ctrl_q[`DVP_CTRL_CROP_ENABLE];
    config_o[99]      = s_stream_q[`DVP_STREAM_ENABLE];
    config_o[103:100] = s_format_q[3:0];
    config_o[106:104] = s_sync_q[2:0];
  end
  assign config_valid_o = s_cfg_seq_q != s_cfg_sent_q;
  assign rx_pop_o = s_accept && !s_write && !stream_enable_o && (s_offset == `RIBP_DVP_RXDATA);
  assign irq_o = |(s_intr_stat_q & s_intr_en_q);

  always_comb begin
    s_access_err = !s_aligned;
    s_rdata_d    = 32'd0;
    if (s_aligned) begin
      unique case (s_offset)
        `RIBP_DVP_CTRL: s_rdata_d = s_ctrl_q;
        `RIBP_DVP_RXDATA: s_rdata_d = rx_data_i;
        `RIBP_DVP_STATUS:
        s_rdata_d = {
          26'd0, s_err_q != 0, stream_enable_o, !fifo_full_i, fifo_empty_i, active_i, s_ctrl_q[0]
        };
        `RIBP_DVP_STREAM_CTRL: s_rdata_d = s_stream_q;
        `RIBP_DVP_FORMAT: s_rdata_d = s_format_q;
        `RIBP_DVP_SYNC_CFG: s_rdata_d = s_sync_q;
        `RIBP_DVP_FRAME_SIZE: s_rdata_d = s_frame_size_q;
        `RIBP_DVP_CROP_START: s_rdata_d = s_crop_start_q;
        `RIBP_DVP_CROP_SIZE: s_rdata_d = s_crop_size_q;
        `RIBP_DVP_FRAME_COUNT: s_rdata_d = s_frm_cnt_q;
        `RIBP_DVP_LINE_COUNT: s_rdata_d = s_line_cnt_q;
        `RIBP_DVP_PIXEL_COUNT: s_rdata_d = s_pixel_cnt_q;
        `RIBP_DVP_WORD_COUNT: s_rdata_d = s_word_cnt_q;
        `RIBP_DVP_DROP_COUNT: s_rdata_d = s_drop_cnt_q;
        `RIBP_DVP_ERROR_STATUS: s_rdata_d = {26'd0, s_err_q};
        `RIBP_DVP_INTR_STATE: s_rdata_d = {25'd0, s_intr_stat_q};
        `RIBP_DVP_INTR_ENABLE: s_rdata_d = {25'd0, s_intr_en_q};
        `RIBP_DVP_INTR_STATUS: s_rdata_d = {25'd0, s_intr_stat_q & s_intr_en_q};
        `RIBP_DVP_INTR_TEST: s_access_err = !s_write;
        `RIBP_DVP_IP_VERSION: s_rdata_d = IP_VERSION;
        `RIBP_DVP_CAPABILITY: s_rdata_d = CAPABILITY;
        `RIBP_DVP_COMMAND: s_access_err = !s_write;
        default: s_access_err = 1'b1;
      endcase
    end
    if (s_accept && s_write && active_i &&
        ((s_offset == `RIBP_DVP_CTRL) || (s_offset == `RIBP_DVP_STREAM_CTRL) ||
         (s_offset == `RIBP_DVP_FORMAT) || (s_offset == `RIBP_DVP_SYNC_CFG) ||
         (s_offset == `RIBP_DVP_FRAME_SIZE) || (s_offset == `RIBP_DVP_CROP_START) ||
         (s_offset == `RIBP_DVP_CROP_SIZE))) begin
      s_access_err = 1'b1;
    end
    if (s_accept && s_write && (s_offset == `RIBP_DVP_FRAME_SIZE) &&
        ((ribp.wdata[15:0] == 0) || (ribp.wdata[31:16] == 0))) begin
      s_access_err = 1'b1;
    end
    s_resp_err_d = s_accept && s_access_err;
  end

  assign command_valid_o = |s_cmd_q;
  assign command_abort_o = s_cmd_q[`DVP_COMMAND_ABORT];
  assign command_flush_o = s_cmd_q[`DVP_COMMAND_FLUSH];

  always_comb begin
    s_ctrl_d       = s_ctrl_q;
    s_stream_d     = s_stream_q;
    s_format_d     = s_format_q;
    s_sync_d       = s_sync_q;
    s_frame_size_d = s_frame_size_q;
    s_crop_start_d = s_crop_start_q;
    s_crop_size_d  = s_crop_size_q;
    s_cfg_seq_d    = s_cfg_seq_q;
    if (s_accept && s_write && !s_access_err) begin
      unique case (s_offset)
        `RIBP_DVP_CTRL: begin
          s_ctrl_d    = merge_wstrb(s_ctrl_q, ribp.wdata, ribp.wstrb) & CTRL_MASK;
          s_cfg_seq_d = s_cfg_seq_q + 1'b1;
        end
        `RIBP_DVP_STREAM_CTRL: begin
          s_stream_d  = merge_wstrb(s_stream_q, ribp.wdata, ribp.wstrb) & STREAM_MASK;
          s_cfg_seq_d = s_cfg_seq_q + 1'b1;
        end
        `RIBP_DVP_FORMAT: begin
          s_format_d  = merge_wstrb(s_format_q, ribp.wdata, ribp.wstrb) & FORMAT_MASK;
          s_cfg_seq_d = s_cfg_seq_q + 1'b1;
        end
        `RIBP_DVP_SYNC_CFG: begin
          s_sync_d    = merge_wstrb(s_sync_q, ribp.wdata, ribp.wstrb) & SYNC_MASK;
          s_cfg_seq_d = s_cfg_seq_q + 1'b1;
        end
        `RIBP_DVP_FRAME_SIZE: begin
          s_frame_size_d = merge_wstrb(s_frame_size_q, ribp.wdata, ribp.wstrb);
          s_cfg_seq_d    = s_cfg_seq_q + 1'b1;
        end
        `RIBP_DVP_CROP_START: begin
          s_crop_start_d = merge_wstrb(s_crop_start_q, ribp.wdata, ribp.wstrb);
          s_cfg_seq_d    = s_cfg_seq_q + 1'b1;
        end
        `RIBP_DVP_CROP_SIZE: begin
          s_crop_size_d = merge_wstrb(s_crop_size_q, ribp.wdata, ribp.wstrb);
          s_cfg_seq_d   = s_cfg_seq_q + 1'b1;
        end
        default: begin
        end
      endcase
    end
  end

  dffr #(32) u_ctrl_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ctrl_d),
      .dat_o  (s_ctrl_q)
  );
  dffr #(32) u_stream_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_stream_d),
      .dat_o  (s_stream_q)
  );
  dffr #(32) u_format_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_format_d),
      .dat_o  (s_format_q)
  );
  dffr #(32) u_sync_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_sync_d),
      .dat_o  (s_sync_q)
  );
  dffr #(32) u_frame_size_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_frame_size_d),
      .dat_o  (s_frame_size_q)
  );
  dffr #(32) u_crop_start_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_crop_start_d),
      .dat_o  (s_crop_start_q)
  );
  dffr #(32) u_crop_size_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_crop_size_d),
      .dat_o  (s_crop_size_q)
  );
  dffr #(32) u_config_seq_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_cfg_seq_d),
      .dat_o  (s_cfg_seq_q)
  );

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_cfg_sent_q  <= '0;
      s_cmd_q       <= '0;
      s_err_q       <= '0;
      s_intr_stat_q <= '0;
      s_intr_en_q   <= '0;
      s_frm_cnt_q   <= '0;
      s_line_cnt_q  <= '0;
      s_pixel_cnt_q <= '0;
      s_word_cnt_q  <= '0;
      s_drop_cnt_q  <= '0;
    end else begin
      if (config_valid_o && config_ready_i) s_cfg_sent_q <= s_cfg_seq_q;
      if (command_valid_o && command_ready_i) s_cmd_q <= '0;
      if (s_accept && s_write && !s_access_err && (s_offset == `RIBP_DVP_COMMAND)) begin
        s_cmd_q <= s_cmd_q | ribp.wdata[1:0];
      end
      s_err_q <= (s_err_q | error_flags_i) &
                 ~((s_accept && s_write && (s_offset == `RIBP_DVP_ERROR_STATUS))
                       ? ribp.wdata[5:0]
                       : 6'd0);
      if (frame_start_i) s_intr_stat_q[`DVP_INTR_FRAME_START] <= 1'b1;
      if (line_done_i) s_intr_stat_q[`DVP_INTR_LINE_DONE] <= 1'b1;
      if (frame_done_i) s_intr_stat_q[`DVP_INTR_FRAME_DONE] <= 1'b1;
      if (error_event_i) s_intr_stat_q[`DVP_INTR_OVERFLOW] <= 1'b1;
      if (s_accept && s_write && (s_offset == `RIBP_DVP_INTR_STATE))
        s_intr_stat_q <= s_intr_stat_q & ~ribp.wdata[6:0];
      if (s_accept && s_write && (s_offset == `RIBP_DVP_INTR_ENABLE))
        s_intr_en_q <= ribp.wdata[6:0];
      if (s_accept && s_write && (s_offset == `RIBP_DVP_INTR_TEST))
        s_intr_stat_q <= s_intr_stat_q | ribp.wdata[6:0];
      if (frame_stats_valid_i) begin
        s_frm_cnt_q   <= frame_stats_i[31:0];
        s_line_cnt_q  <= {16'd0, frame_stats_i[47:32]};
        s_pixel_cnt_q <= frame_stats_i[79:48];
        s_word_cnt_q  <= {16'd0, frame_stats_i[95:80]};
        s_drop_cnt_q  <= frame_stats_i[127:96];
      end
    end
  end

  dffr #(1) u_ready_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (ribp.valid && !s_ready_q),
      .dat_o  (s_ready_q)
  );
  dffer #(32) u_rdata_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_accept && !s_write),
      .dat_i  (s_rdata_d),
      .dat_o  (s_rdata_q)
  );
  dffer #(1) u_resp_err_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_accept),
      .dat_i  (s_resp_err_d),
      .dat_o  (s_resp_err_q)
  );
endmodule
