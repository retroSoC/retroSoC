// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND.

module jpeg_mcu_reconstructor (
    // verilog_format: off -- preserve command, block, and raster-stream interface columns
    input  logic              clk_i,
    input  logic              rst_n_i,
    input  logic              start_i,
    input  logic [ 1:0]       sampling_i,
    input  logic [ 2:0]       format_i,
    input  logic [ 4:0]       valid_width_i,
    input  logic [ 4:0]       valid_height_i,
    input  logic [511:0]      block_i,
    input  logic              block_valid_i,
    output logic              block_ready_o,
    output logic              start_ready_o,
    axi4_stream_if.source     pixel_axis,
    output logic              done_o,
    output logic              error_o
    // verilog_format: on
);
  typedef enum logic [2:0] {
    Idle,
    Load,
    Pixels,
    Nv12Chroma,
    Done
  } state_e;

  state_e               s_state_d;
  state_e               s_state_q;
  logic   [ 2:0]        s_state_bits_q;
  logic   [ 1:0]        s_sampling_d;
  logic   [ 1:0]        s_sampling_q;
  logic   [ 2:0]        s_format_d;
  logic   [ 2:0]        s_format_q;
  logic   [ 4:0]        s_width_d;
  logic   [ 4:0]        s_width_q;
  logic   [ 4:0]        s_height_d;
  logic   [ 4:0]        s_height_q;
  logic   [ 2:0]        s_block_cnt_d;
  logic   [ 2:0]        s_block_cnt_q;
  logic   [ 5:0][511:0] s_blocks_d;
  logic   [ 5:0][511:0] s_blocks_q;
  logic   [ 4:0]        s_x_d;
  logic   [ 4:0]        s_x_q;
  logic   [ 4:0]        s_y_d;
  logic   [ 4:0]        s_y_q;
  logic                 s_err_d;
  logic                 s_err_q;
  logic   [ 2:0]        s_expected_blocks;
  logic   [ 7:0]        s_y0;
  logic   [ 7:0]        s_y1;
  logic   [ 7:0]        s_cb0;
  logic   [ 7:0]        s_cb1;
  logic   [ 7:0]        s_cr0;
  logic   [ 7:0]        s_cr1;
  logic   [ 7:0]        s_red0;
  logic   [ 7:0]        s_green0;
  logic   [ 7:0]        s_blue0;
  logic   [ 7:0]        s_red1;
  logic   [ 7:0]        s_green1;
  logic   [ 7:0]        s_blue1;
  logic   [15:0]        s_rgb565_0;
  logic   [15:0]        s_rgb565_1;
  logic                 s_second_valid;
  logic                 s_pixel_accept;
  logic   [ 4:0]        s_x_next;

  function automatic logic [7:0] block_sample(input logic [511:0] block_i, input logic [2:0] x_i,
                                              input logic [2:0] y_i);
    return block_i[((y_i*8)+x_i)*8+:8];
  endfunction

  function automatic logic [7:0] clamp_color(input logic signed [17:0] value_i);
    if (value_i < 0) begin
      return 8'd0;
    end
    if (value_i > 255) begin
      return 8'd255;
    end
    return value_i[7:0];
  endfunction

  function automatic logic [23:0] ycbcr_to_rgb(input logic [7:0] y_i, input logic [7:0] cb_i,
                                               input logic [7:0] cr_i);
    logic signed [ 9:0] s_cb;
    logic signed [ 9:0] s_cr;
    logic signed [17:0] s_red;
    logic signed [17:0] s_green;
    logic signed [17:0] s_blue;
    begin
      s_cb    = $signed({1'b0, cb_i}) - 10'sd128;
      s_cr    = $signed({1'b0, cr_i}) - 10'sd128;
      s_red   = $signed(18'({1'b0, y_i})) + ((18'sd359 * s_cr + 18'sd128) >>> 8);
      s_green = $signed(18'({1'b0, y_i})) -
                ((18'sd88 * s_cb + 18'sd183 * s_cr + 18'sd128) >>> 8);
      s_blue  = $signed(18'({1'b0, y_i})) + ((18'sd454 * s_cb + 18'sd128) >>> 8);
      return {clamp_color(s_red), clamp_color(s_green), clamp_color(s_blue)};
    end
  endfunction

  function automatic logic [7:0] average_chroma(input logic [7:0] left_i,
                                                input logic [7:0] right_i);
    logic [8:0] s_sum;
    begin
      s_sum = {1'b0, left_i} + {1'b0, right_i} + 1'b1;
      return s_sum[8:1];
    end
  endfunction

  always_comb begin
    unique case (s_sampling_q)
      2'd0:    s_expected_blocks = 3'd1;
      2'd1:    s_expected_blocks = 3'd3;
      2'd2:    s_expected_blocks = 3'd4;
      default: s_expected_blocks = 3'd6;
    endcase
  end

  always_comb begin
    s_y0  = 8'd0;
    s_y1  = 8'd0;
    s_cb0 = 8'd128;
    s_cb1 = 8'd128;
    s_cr0 = 8'd128;
    s_cr1 = 8'd128;
    unique case (s_sampling_q)
      2'd0: begin
        s_y0 = block_sample(s_blocks_q[0], s_x_q[2:0], s_y_q[2:0]);
        s_y1 = block_sample(s_blocks_q[0], s_x_next[2:0], s_y_q[2:0]);
      end
      2'd1: begin
        s_y0  = block_sample(s_blocks_q[0], s_x_q[2:0], s_y_q[2:0]);
        s_y1  = block_sample(s_blocks_q[0], s_x_next[2:0], s_y_q[2:0]);
        s_cb0 = block_sample(s_blocks_q[1], s_x_q[2:0], s_y_q[2:0]);
        s_cb1 = block_sample(s_blocks_q[1], s_x_next[2:0], s_y_q[2:0]);
        s_cr0 = block_sample(s_blocks_q[2], s_x_q[2:0], s_y_q[2:0]);
        s_cr1 = block_sample(s_blocks_q[2], s_x_next[2:0], s_y_q[2:0]);
      end
      2'd2: begin
        s_y0  = block_sample(s_blocks_q[s_x_q[3]], s_x_q[2:0], s_y_q[2:0]);
        s_y1  = block_sample(s_blocks_q[s_x_next[3]], s_x_next[2:0], s_y_q[2:0]);
        s_cb0 = block_sample(s_blocks_q[2], s_x_q[3:1], s_y_q[2:0]);
        s_cb1 = block_sample(s_blocks_q[2], s_x_next[3:1], s_y_q[2:0]);
        s_cr0 = block_sample(s_blocks_q[3], s_x_q[3:1], s_y_q[2:0]);
        s_cr1 = block_sample(s_blocks_q[3], s_x_next[3:1], s_y_q[2:0]);
      end
      default: begin
        s_y0  = block_sample(s_blocks_q[{s_y_q[3], s_x_q[3]}], s_x_q[2:0], s_y_q[2:0]);
        s_y1  = block_sample(s_blocks_q[{s_y_q[3], s_x_next[3]}], s_x_next[2:0], s_y_q[2:0]);
        s_cb0 = block_sample(s_blocks_q[4], s_x_q[3:1], s_y_q[3:1]);
        s_cb1 = block_sample(s_blocks_q[4], s_x_next[3:1], s_y_q[3:1]);
        s_cr0 = block_sample(s_blocks_q[5], s_x_q[3:1], s_y_q[3:1]);
        s_cr1 = block_sample(s_blocks_q[5], s_x_next[3:1], s_y_q[3:1]);
      end
    endcase
  end

  assign {s_red0, s_green0, s_blue0} = ycbcr_to_rgb(s_y0, s_cb0, s_cr0);
  assign {s_red1, s_green1, s_blue1} = ycbcr_to_rgb(s_y1, s_cb1, s_cr1);
  assign s_rgb565_0                  = {s_red0[7:3], s_green0[7:2], s_blue0[7:3]};
  assign s_rgb565_1                  = {s_red1[7:3], s_green1[7:2], s_blue1[7:3]};
  assign s_x_next                    = s_x_q + 1'b1;
  assign s_second_valid              = (s_x_q + 1'b1) < s_width_q;
  assign s_pixel_accept              = pixel_axis.tvalid && pixel_axis.tready;
  assign s_state_q                   = state_e'(s_state_bits_q);
  assign start_ready_o               = s_state_q == Idle;
  assign block_ready_o               = s_state_q == Load;
  assign done_o                      = s_state_q == Done;
  assign error_o                     = s_err_q;

  always_comb begin
    pixel_axis.tdata  = '0;
    pixel_axis.tkeep  = '0;
    pixel_axis.tstrb  = '0;
    pixel_axis.tlast  = 1'b0;
    pixel_axis.tid    = '0;
    pixel_axis.tdest  = '0;
    pixel_axis.tuser  = '0;
    pixel_axis.tvalid = (s_state_q == Pixels) || (s_state_q == Nv12Chroma);
    if (s_state_q == Nv12Chroma) begin
      pixel_axis.tdata[7:0]  = s_cb0;
      pixel_axis.tdata[15:8] = s_cr0;
      pixel_axis.tkeep       = 8'h03;
      pixel_axis.tstrb       = 8'h03;
      pixel_axis.tlast       = (s_x_q + 2 >= s_width_q);
      pixel_axis.tdest       = 1'b1;
      pixel_axis.tuser       = (s_x_q == 5'd0) && (s_y_q == 5'd0);
    end else begin
      unique case (s_format_q)
        3'd0: begin
          pixel_axis.tdata[7:0]  = s_y0;
          pixel_axis.tdata[15:8] = s_y1;
          pixel_axis.tkeep       = s_second_valid ? 8'h03 : 8'h01;
        end
        3'd1: begin
          pixel_axis.tdata[15:0]  = s_rgb565_0;
          pixel_axis.tdata[31:16] = s_rgb565_1;
          pixel_axis.tkeep        = s_second_valid ? 8'h0f : 8'h03;
        end
        3'd2: begin
          pixel_axis.tdata[23:0]  = {s_blue0, s_green0, s_red0};
          pixel_axis.tdata[47:24] = {s_blue1, s_green1, s_red1};
          pixel_axis.tkeep        = s_second_valid ? 8'h3f : 8'h07;
        end
        3'd3: begin
          pixel_axis.tdata[31:0] = {
            average_chroma(s_cr0, s_cr1), s_y1, average_chroma(s_cb0, s_cb1), s_y0
          };
          pixel_axis.tkeep = 8'h0f;
        end
        default: begin
          pixel_axis.tdata[7:0]  = s_y0;
          pixel_axis.tdata[15:8] = s_y1;
          pixel_axis.tkeep       = s_second_valid ? 8'h03 : 8'h01;
        end
      endcase
      pixel_axis.tstrb = pixel_axis.tkeep;
      pixel_axis.tlast = (s_x_q + 2 >= s_width_q);
      pixel_axis.tuser = (s_x_q == 5'd0) && (s_y_q == 5'd0);
    end
  end

  always_comb begin
    s_state_d     = s_state_q;
    s_sampling_d  = s_sampling_q;
    s_format_d    = s_format_q;
    s_width_d     = s_width_q;
    s_height_d    = s_height_q;
    s_block_cnt_d = s_block_cnt_q;
    s_blocks_d    = s_blocks_q;
    s_x_d         = s_x_q;
    s_y_d         = s_y_q;
    s_err_d       = s_err_q;
    unique case (s_state_q)
      Idle: begin
        if (start_i) begin
          s_sampling_d = sampling_i;
          s_format_d = format_i;
          s_width_d = valid_width_i;
          s_height_d = valid_height_i;
          s_block_cnt_d = 3'd0;
          s_blocks_d = '0;
          s_x_d = 5'd0;
          s_y_d = 5'd0;
          s_err_d = (format_i > 3'd4) || (valid_width_i == 5'd0) ||
                    (valid_height_i == 5'd0) || (valid_width_i > 5'd16) ||
                    (valid_height_i > 5'd16);
          s_state_d = Load;
        end
      end
      Load: begin
        if (block_valid_i) begin
          s_blocks_d[s_block_cnt_q] = block_i;
          if (s_block_cnt_q + 1'b1 == s_expected_blocks) begin
            s_x_d     = 5'd0;
            s_y_d     = 5'd0;
            s_state_d = Pixels;
          end else begin
            s_block_cnt_d = s_block_cnt_q + 1'b1;
          end
        end
      end
      Pixels: begin
        if (s_pixel_accept) begin
          if (s_x_q + 2 >= s_width_q) begin
            s_x_d = 5'd0;
            if (s_y_q + 1'b1 >= s_height_q) begin
              s_y_d     = 5'd0;
              s_state_d = (s_format_q == 3'd4 && s_sampling_q != 2'd0) ? Nv12Chroma : Done;
            end else begin
              s_y_d = s_y_q + 1'b1;
            end
          end else begin
            s_x_d = s_x_q + 2;
          end
        end
      end
      Nv12Chroma: begin
        if (s_pixel_accept) begin
          if (s_x_q + 2 >= s_width_q) begin
            s_x_d = 5'd0;
            if (s_y_q + 2 >= s_height_q) begin
              s_state_d = Done;
            end else begin
              s_y_d = s_y_q + 2;
            end
          end else begin
            s_x_d = s_x_q + 2;
          end
        end
      end
      Done: begin
        s_state_d = Idle;
      end
      default: s_state_d = Idle;
    endcase
  end

  dffr #(
      .DATA_WIDTH(3)
  ) u_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_state_d),
      .dat_o  (s_state_bits_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_sampling_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_sampling_d),
      .dat_o  (s_sampling_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_format_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_format_d),
      .dat_o  (s_format_q)
  );
  dffr #(
      .DATA_WIDTH(5)
  ) u_width_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_width_d),
      .dat_o  (s_width_q)
  );
  dffr #(
      .DATA_WIDTH(5)
  ) u_height_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_height_d),
      .dat_o  (s_height_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_block_cnt_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_block_cnt_d),
      .dat_o  (s_block_cnt_q)
  );
  dffr #(
      .DATA_WIDTH(6 * 512)
  ) u_blocks_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_blocks_d),
      .dat_o  (s_blocks_q)
  );
  dffr #(
      .DATA_WIDTH(5)
  ) u_x_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_x_d),
      .dat_o  (s_x_q)
  );
  dffr #(
      .DATA_WIDTH(5)
  ) u_y_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_y_d),
      .dat_o  (s_y_q)
  );
  dffr u_err_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_d),
      .dat_o  (s_err_q)
  );
endmodule
