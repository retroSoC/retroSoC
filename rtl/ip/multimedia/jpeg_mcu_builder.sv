// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND.

module jpeg_mcu_builder #(
    parameter int unsigned DataWidth   = 64,
    parameter int unsigned MaxMcuBytes = 768
) (
    // verilog_format: off -- preserve command, raster-stream, and block columns
    input  logic              clk_i,
    input  logic              rst_n_i,
    input  logic              start_i,
    input  logic [ 1:0]       sampling_i,
    input  logic [ 2:0]       format_i,
    input  logic [ 4:0]       valid_width_i,
    input  logic [ 4:0]       valid_height_i,
    axi4_stream_if.sink       pixel_axis,
    output logic              start_ready_o,
    output logic [511:0]      block_o,
    output logic              block_valid_o,
    input  logic              block_ready_i,
    output logic              block_last_o,
    output logic              done_o,
    output logic              error_o
    // verilog_format: on
);
  localparam int unsigned InputBytes = DataWidth / 8;
  localparam int unsigned ByteCountWidth = $clog2(MaxMcuBytes + 1);

  typedef enum logic [2:0] {
    Idle,
    Capture,
    Blocks,
    Done
  } state_e;

  state_e                      s_state_d;
  state_e                      s_state_q;
  logic   [               2:0] s_state_bits_q;
  logic   [               1:0] s_sampling_d;
  logic   [               1:0] s_sampling_q;
  logic   [               2:0] s_format_d;
  logic   [               2:0] s_format_q;
  logic   [               4:0] s_width_d;
  logic   [               4:0] s_width_q;
  logic   [               4:0] s_height_d;
  logic   [               4:0] s_height_q;
  logic   [ByteCountWidth-1:0] s_byte_cnt_d;
  logic   [ByteCountWidth-1:0] s_byte_cnt_q;
  logic   [ByteCountWidth-1:0] s_expected_bytes_d;
  logic   [ByteCountWidth-1:0] s_expected_bytes_q;
  logic   [               2:0] s_block_cnt_d;
  logic   [               2:0] s_block_cnt_q;
  logic   [ MaxMcuBytes*8-1:0] s_raw_d;
  logic   [ MaxMcuBytes*8-1:0] s_raw_q;
  logic                        s_err_d;
  logic                        s_err_q;
  logic   [               2:0] s_expected_blocks;
  logic   [             511:0] s_generated_block;
  logic   [  ByteCountWidth:0] s_bytes_after_beat;
  logic   [               3:0] s_input_byte_cnt;
  logic                        s_keep_legal;

  function automatic logic [7:0] raw_byte(input logic [MaxMcuBytes*8-1:0] raw_i,
                                          input integer index_i);
    if ((index_i < 0) || (index_i >= MaxMcuBytes)) begin
      return 8'd0;
    end
    return raw_i[index_i*8+:8];
  endfunction

  function automatic logic [23:0] pixel_ycbcr(
      input logic [MaxMcuBytes*8-1:0] raw_i, input logic [2:0] format_i, input integer width_i,
      input integer height_i, input integer x_i, input integer y_i);
    integer        s_x;
    integer        s_y;
    integer        s_index;
    integer        s_pair;
    integer        s_uv_stride;
    integer        s_uv_base;
    logic   [ 7:0] s_red;
    logic   [ 7:0] s_green;
    logic   [ 7:0] s_blue;
    logic   [ 7:0] s_luma;
    logic   [ 7:0] s_cb;
    logic   [ 7:0] s_cr;
    logic   [15:0] s_rgb565;
    begin
      s_x     = (x_i >= width_i) ? width_i - 1 : x_i;
      s_y     = (y_i >= height_i) ? height_i - 1 : y_i;
      s_red   = 8'd0;
      s_green = 8'd0;
      s_blue  = 8'd0;
      s_luma  = 8'd0;
      s_cb    = 8'd128;
      s_cr    = 8'd128;
      unique case (format_i)
        3'd0: begin
          s_luma = raw_byte(raw_i, (s_y * width_i) + s_x);
        end
        3'd1: begin
          s_index  = ((s_y * width_i) + s_x) * 2;
          s_rgb565 = {raw_byte(raw_i, s_index + 1), raw_byte(raw_i, s_index)};
          s_red    = {s_rgb565[15:11], s_rgb565[15:13]};
          s_green  = {s_rgb565[10:5], s_rgb565[10:9]};
          s_blue   = {s_rgb565[4:0], s_rgb565[4:2]};
          s_luma   = (77 * s_red + 150 * s_green + 29 * s_blue + 128) >> 8;
          s_cb     = ((-43 * s_red - 85 * s_green + 128 * s_blue + 128) >>> 8) + 128;
          s_cr     = ((128 * s_red - 107 * s_green - 21 * s_blue + 128) >>> 8) + 128;
        end
        3'd2: begin
          s_index = ((s_y * width_i) + s_x) * 3;
          s_red   = raw_byte(raw_i, s_index);
          s_green = raw_byte(raw_i, s_index + 1);
          s_blue  = raw_byte(raw_i, s_index + 2);
          s_luma  = (77 * s_red + 150 * s_green + 29 * s_blue + 128) >> 8;
          s_cb    = ((-43 * s_red - 85 * s_green + 128 * s_blue + 128) >>> 8) + 128;
          s_cr    = ((128 * s_red - 107 * s_green - 21 * s_blue + 128) >>> 8) + 128;
        end
        3'd3: begin
          s_pair = ((s_y * width_i) + (s_x & ~1)) * 2;
          s_luma = raw_byte(raw_i, s_pair + ((s_x & 1) * 2));
          s_cb   = raw_byte(raw_i, s_pair + 1);
          s_cr   = raw_byte(raw_i, s_pair + 3);
        end
        default: begin
          s_luma      = raw_byte(raw_i, (s_y * width_i) + s_x);
          s_uv_stride = (width_i + 1) & ~1;
          s_uv_base   = width_i * height_i;
          s_pair      = s_uv_base + ((s_y >> 1) * s_uv_stride) + ((s_x >> 1) * 2);
          s_cb        = raw_byte(raw_i, s_pair);
          s_cr        = raw_byte(raw_i, s_pair + 1);
        end
      endcase
      return {s_cr, s_cb, s_luma};
    end
  endfunction

  function automatic logic [7:0] component_sample(
      input logic [MaxMcuBytes*8-1:0] raw_i, input logic [1:0] sampling_i,
      input logic [2:0] format_i, input integer width_i, input integer height_i,
      input integer block_i, input integer sample_i);
    integer        s_x;
    integer        s_y;
    integer        s_component;
    logic   [23:0] s_pixel0;
    logic   [23:0] s_pixel1;
    logic   [23:0] s_pixel2;
    logic   [23:0] s_pixel3;
    logic   [ 9:0] s_sum;
    begin
      s_x         = sample_i & 7;
      s_y         = sample_i >> 3;
      s_component = 0;
      if (sampling_i == 2'd0) begin
        s_component = 0;
      end else if (sampling_i == 2'd1) begin
        s_component = block_i;
      end else if (sampling_i == 2'd2) begin
        if (block_i < 2) begin
          s_x += block_i * 8;
        end else begin
          s_x *= 2;
          s_component = block_i - 1;
        end
      end else if (block_i < 4) begin
        s_x += (block_i & 1) * 8;
        s_y += (block_i >> 1) * 8;
      end else begin
        s_x *= 2;
        s_y *= 2;
        s_component = block_i - 3;
      end
      s_pixel0 = pixel_ycbcr(raw_i, format_i, width_i, height_i, s_x, s_y);
      if ((sampling_i == 2'd2) && (block_i >= 2)) begin
        s_pixel1 = pixel_ycbcr(raw_i, format_i, width_i, height_i, s_x + 1, s_y);
        s_sum = 10'((s_component == 1) ? s_pixel0[15:8] : s_pixel0[23:16]) +
                10'((s_component == 1) ? s_pixel1[15:8] : s_pixel1[23:16]);
        return 8'((s_sum + 1'b1) >> 1);
      end
      if ((sampling_i == 2'd3) && (block_i >= 4)) begin
        s_pixel1 = pixel_ycbcr(raw_i, format_i, width_i, height_i, s_x + 1, s_y);
        s_pixel2 = pixel_ycbcr(raw_i, format_i, width_i, height_i, s_x, s_y + 1);
        s_pixel3 = pixel_ycbcr(raw_i, format_i, width_i, height_i, s_x + 1, s_y + 1);
        s_sum = 10'((s_component == 1) ? s_pixel0[15:8] : s_pixel0[23:16]) +
                10'((s_component == 1) ? s_pixel1[15:8] : s_pixel1[23:16]) +
                10'((s_component == 1) ? s_pixel2[15:8] : s_pixel2[23:16]) +
                10'((s_component == 1) ? s_pixel3[15:8] : s_pixel3[23:16]);
        return 8'((s_sum + 10'd2) >> 2);
      end
      unique case (s_component)
        0:       return s_pixel0[7:0];
        1:       return s_pixel0[15:8];
        default: return s_pixel0[23:16];
      endcase
    end
  endfunction

  always_comb begin
    unique case (s_sampling_q)
      2'd0:    s_expected_blocks = 3'd1;
      2'd1:    s_expected_blocks = 3'd3;
      2'd2:    s_expected_blocks = 3'd4;
      default: s_expected_blocks = 3'd6;
    endcase
    for (int unsigned index = 0; index < 64; index++) begin
      s_generated_block[index*8+:8] = component_sample(
        s_raw_q,
        s_sampling_q,
        s_format_q,
        int'(s_width_q),
        int'(s_height_q),
        int'(s_block_cnt_q),
        index
      );
    end
  end

  always_comb begin
    s_input_byte_cnt = 4'd0;
    s_keep_legal     = (pixel_axis.tkeep != '0) && (pixel_axis.tkeep == pixel_axis.tstrb);
    for (int unsigned lane = 0; lane < InputBytes; lane++) begin
      if (pixel_axis.tkeep[lane]) begin
        s_input_byte_cnt += 1'b1;
      end else if ((lane < (InputBytes - 1)) && pixel_axis.tkeep[lane+1]) begin
        s_keep_legal = 1'b0;
      end
    end
    s_bytes_after_beat = {1'b0, s_byte_cnt_q} + (ByteCountWidth + 1)'(s_input_byte_cnt);
  end

  assign s_state_q         = state_e'(s_state_bits_q);
  assign pixel_axis.tready = s_state_q == Capture;
  assign start_ready_o     = s_state_q == Idle;
  assign block_o           = s_generated_block;
  assign block_valid_o     = s_state_q == Blocks;
  assign block_last_o      = (s_state_q == Blocks) && (s_block_cnt_q + 1'b1 == s_expected_blocks);
  assign done_o            = s_state_q == Done;
  assign error_o           = s_err_q;

  always_comb begin
    s_state_d          = s_state_q;
    s_sampling_d       = s_sampling_q;
    s_format_d         = s_format_q;
    s_width_d          = s_width_q;
    s_height_d         = s_height_q;
    s_byte_cnt_d       = s_byte_cnt_q;
    s_expected_bytes_d = s_expected_bytes_q;
    s_block_cnt_d      = s_block_cnt_q;
    s_raw_d            = s_raw_q;
    s_err_d            = s_err_q;
    unique case (s_state_q)
      Idle: begin
        if (start_i) begin
          s_sampling_d  = sampling_i;
          s_format_d    = format_i;
          s_width_d     = valid_width_i;
          s_height_d    = valid_height_i;
          s_byte_cnt_d  = '0;
          s_block_cnt_d = '0;
          s_raw_d       = '0;
          unique case (format_i)
            3'd0: s_expected_bytes_d = ByteCountWidth'(int'(valid_width_i) * int'(valid_height_i));
            3'd1, 3'd3:
            s_expected_bytes_d = ByteCountWidth'(int'(valid_width_i) * int'(valid_height_i) * 2);
            3'd2:
            s_expected_bytes_d = ByteCountWidth'(int'(valid_width_i) * int'(valid_height_i) * 3);
            default:
            s_expected_bytes_d = ByteCountWidth'(
                (int'(valid_width_i) * int'(valid_height_i)) +
                (((int'(valid_width_i) + 1) & ~1) * ((int'(valid_height_i) + 1) >> 1))
            );
          endcase
          s_err_d = (format_i > 3'd4) || (valid_width_i == 5'd0) ||
                    (valid_height_i == 5'd0) || (valid_width_i > 5'd16) ||
                    (valid_height_i > 5'd16);
          s_state_d = Capture;
        end
      end
      Capture: begin
        if (pixel_axis.tvalid && pixel_axis.tready) begin
          if (!s_keep_legal || (s_bytes_after_beat > {1'b0, s_expected_bytes_q})) begin
            s_err_d = 1'b1;
          end
          for (int unsigned lane = 0; lane < InputBytes; lane++) begin
            if (pixel_axis.tkeep[lane] && ((int'(s_byte_cnt_q) + lane) < MaxMcuBytes)) begin
              s_raw_d[(int'(s_byte_cnt_q)+lane)*8+:8] = pixel_axis.tdata[lane*8+:8];
            end
          end
          s_byte_cnt_d = ByteCountWidth'(s_bytes_after_beat);
          if (s_bytes_after_beat >= {1'b0, s_expected_bytes_q}) begin
            s_block_cnt_d = 3'd0;
            s_state_d     = Blocks;
          end
        end
      end
      Blocks: begin
        if (block_valid_o && block_ready_i) begin
          if (block_last_o) begin
            s_state_d = Done;
          end else begin
            s_block_cnt_d = s_block_cnt_q + 1'b1;
          end
        end
      end
      Done:    s_state_d = Idle;
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
      .DATA_WIDTH(ByteCountWidth)
  ) u_byte_cnt_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_byte_cnt_d),
      .dat_o  (s_byte_cnt_q)
  );
  dffr #(
      .DATA_WIDTH(ByteCountWidth)
  ) u_expected_bytes_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_expected_bytes_d),
      .dat_o  (s_expected_bytes_q)
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
      .DATA_WIDTH(MaxMcuBytes * 8)
  ) u_raw_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_raw_d),
      .dat_o  (s_raw_q)
  );
  dffr u_err_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_d),
      .dat_o  (s_err_q)
  );

`ifndef SYNTHESIS
  initial begin
    if (DataWidth != 64 || MaxMcuBytes < 768) begin
      $fatal(1, "jpeg_mcu_builder: unsupported buffer geometry");
    end
  end
`endif
endmodule
