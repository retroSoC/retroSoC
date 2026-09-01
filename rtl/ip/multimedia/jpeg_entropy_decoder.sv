// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND.

module jpeg_entropy_decoder #(
    parameter int unsigned ElementWidth = 24,
    parameter int unsigned WindowWidth  = 32,
    parameter int unsigned SearchLanes  = 16
) (
    // verilog_format: off -- preserve block, table, and bit-window interface columns
    input  logic                                  clk_i,
    input  logic                                  rst_n_i,
    input  logic                                  start_i,
    input  logic signed [ElementWidth-1:0]         previous_dc_i,
    input  logic [12*16-1:0]                      dc_code_i,
    input  logic [12*5-1:0]                       dc_length_i,
    input  logic [256*16-1:0]                     ac_code_i,
    input  logic [256*5-1:0]                      ac_length_i,
    input  logic [WindowWidth-1:0]                bit_window_i,
    input  logic [$clog2(WindowWidth+1)-1:0]      bit_count_i,
    output logic [$clog2(WindowWidth+1)-1:0]      bit_consume_o,
    output logic                                  bit_consume_valid_o,
    output logic                                  start_ready_o,
    output logic [64*ElementWidth-1:0]            block_o,
    output logic signed [ElementWidth-1:0]         dc_o,
    output logic                                  result_valid_o,
    input  logic                                  result_ready_i,
    output logic                                  error_o
    // verilog_format: on
);
  typedef enum logic [1:0] {
    Idle,
    Dc,
    Ac,
    Result
  } state_e;

  localparam int unsigned CountWidth = $clog2(WindowWidth + 1);

  state_e                            s_state_d;
  state_e                            s_state_q;
  logic        [                1:0] s_state_bits_q;
  logic        [                6:0] s_coeff_index_d;
  logic        [                6:0] s_coeff_index_q;
  logic        [                7:0] s_search_base_d;
  logic        [                7:0] s_search_base_q;
  logic        [64*ElementWidth-1:0] s_block_d;
  logic        [64*ElementWidth-1:0] s_block_q;
  logic signed [   ElementWidth-1:0] s_dc_d;
  logic signed [   ElementWidth-1:0] s_dc_q;
  logic                              s_err_d;
  logic                              s_err_q;
  logic                              s_match;
  logic        [                7:0] s_symbol;
  logic        [                4:0] s_code_len;
  logic        [               15:0] s_code;
  logic        [                4:0] s_value_len;
  logic        [     CountWidth-1:0] s_total_len;
  logic        [   ElementWidth-1:0] s_amplitude;
  logic signed [   ElementWidth-1:0] s_value;
  logic        [                3:0] s_run;
  logic        [                6:0] s_next_index;

  function automatic logic [5:0] zigzag_index(input logic [5:0] index_i);
    begin
      unique case (index_i)
        6'd0:    zigzag_index = 6'd0;
        6'd1:    zigzag_index = 6'd1;
        6'd2:    zigzag_index = 6'd8;
        6'd3:    zigzag_index = 6'd16;
        6'd4:    zigzag_index = 6'd9;
        6'd5:    zigzag_index = 6'd2;
        6'd6:    zigzag_index = 6'd3;
        6'd7:    zigzag_index = 6'd10;
        6'd8:    zigzag_index = 6'd17;
        6'd9:    zigzag_index = 6'd24;
        6'd10:   zigzag_index = 6'd32;
        6'd11:   zigzag_index = 6'd25;
        6'd12:   zigzag_index = 6'd18;
        6'd13:   zigzag_index = 6'd11;
        6'd14:   zigzag_index = 6'd4;
        6'd15:   zigzag_index = 6'd5;
        6'd16:   zigzag_index = 6'd12;
        6'd17:   zigzag_index = 6'd19;
        6'd18:   zigzag_index = 6'd26;
        6'd19:   zigzag_index = 6'd33;
        6'd20:   zigzag_index = 6'd40;
        6'd21:   zigzag_index = 6'd48;
        6'd22:   zigzag_index = 6'd41;
        6'd23:   zigzag_index = 6'd34;
        6'd24:   zigzag_index = 6'd27;
        6'd25:   zigzag_index = 6'd20;
        6'd26:   zigzag_index = 6'd13;
        6'd27:   zigzag_index = 6'd6;
        6'd28:   zigzag_index = 6'd7;
        6'd29:   zigzag_index = 6'd14;
        6'd30:   zigzag_index = 6'd21;
        6'd31:   zigzag_index = 6'd28;
        6'd32:   zigzag_index = 6'd35;
        6'd33:   zigzag_index = 6'd42;
        6'd34:   zigzag_index = 6'd49;
        6'd35:   zigzag_index = 6'd56;
        6'd36:   zigzag_index = 6'd57;
        6'd37:   zigzag_index = 6'd50;
        6'd38:   zigzag_index = 6'd43;
        6'd39:   zigzag_index = 6'd36;
        6'd40:   zigzag_index = 6'd29;
        6'd41:   zigzag_index = 6'd22;
        6'd42:   zigzag_index = 6'd15;
        6'd43:   zigzag_index = 6'd23;
        6'd44:   zigzag_index = 6'd30;
        6'd45:   zigzag_index = 6'd37;
        6'd46:   zigzag_index = 6'd44;
        6'd47:   zigzag_index = 6'd51;
        6'd48:   zigzag_index = 6'd58;
        6'd49:   zigzag_index = 6'd59;
        6'd50:   zigzag_index = 6'd52;
        6'd51:   zigzag_index = 6'd45;
        6'd52:   zigzag_index = 6'd38;
        6'd53:   zigzag_index = 6'd31;
        6'd54:   zigzag_index = 6'd39;
        6'd55:   zigzag_index = 6'd46;
        6'd56:   zigzag_index = 6'd53;
        6'd57:   zigzag_index = 6'd60;
        6'd58:   zigzag_index = 6'd61;
        6'd59:   zigzag_index = 6'd54;
        6'd60:   zigzag_index = 6'd47;
        6'd61:   zigzag_index = 6'd55;
        6'd62:   zigzag_index = 6'd62;
        default: zigzag_index = 6'd63;
      endcase
    end
  endfunction

  function automatic logic signed [ElementWidth-1:0] extend_value(
      input logic [ElementWidth-1:0] amplitude_i, input logic [4:0] length_i);
    logic [ElementWidth-1:0] s_threshold;
    logic [ElementWidth-1:0] s_mask;
    begin
      if (length_i == 5'd0) begin
        return '0;
      end
      s_threshold = ElementWidth'(1) << (length_i - 1'b1);
      s_mask      = (ElementWidth'(1) << length_i) - 1'b1;
      return amplitude_i >= s_threshold ? $signed(amplitude_i) : $signed(amplitude_i | ~s_mask);
    end
  endfunction

  assign s_state_q      = state_e'(s_state_bits_q);
  assign start_ready_o  = s_state_q == Idle;
  assign block_o        = s_block_q;
  assign dc_o           = s_dc_q;
  assign result_valid_o = s_state_q == Result;
  assign error_o        = s_err_q;

  always_comb begin
    s_match    = 1'b0;
    s_symbol   = 8'd0;
    s_code_len = 5'd0;
    s_code     = 16'd0;
    if (s_state_q == Dc) begin
      for (int unsigned symbol = 0; symbol < 12; symbol++) begin
        if (!s_match && (dc_length_i[symbol*5+:5] != 5'd0) &&
            (6'(dc_length_i[symbol*5+:5]) <= bit_count_i) &&
            (dc_code_i[symbol*16+:16] ==
             16'(bit_window_i >> (WindowWidth - int'(dc_length_i[symbol*5+:5]))))) begin
          s_match    = 1'b1;
          s_symbol   = 8'(symbol);
          s_code_len = dc_length_i[symbol*5+:5];
          s_code     = dc_code_i[symbol*16+:16];
        end
      end
    end else if (s_state_q == Ac) begin
      for (int unsigned lane = 0; lane < SearchLanes; lane++) begin
        if (!s_match && ((int'(s_search_base_q) + lane) < 256) &&
            (ac_length_i[(int'(s_search_base_q)+lane)*5+:5] != 5'd0) &&
            (6'(ac_length_i[(int'(s_search_base_q)+lane)*5+:5]) <= bit_count_i) &&
            (ac_code_i[(int'(s_search_base_q)+lane)*16+:16] ==
             16'(bit_window_i >>
                 (WindowWidth - int'(ac_length_i[(int'(s_search_base_q)+lane)*5+:5]))))) begin
          s_match    = 1'b1;
          s_symbol   = s_search_base_q + 8'(lane);
          s_code_len = ac_length_i[(int'(s_search_base_q)+lane)*5+:5];
          s_code     = ac_code_i[(int'(s_search_base_q)+lane)*16+:16];
        end
      end
    end
  end

  always_comb begin
    s_state_d = s_state_q;
    s_coeff_index_d = s_coeff_index_q;
    s_search_base_d = s_search_base_q;
    s_block_d = s_block_q;
    s_dc_d = s_dc_q;
    s_err_d = s_err_q;
    bit_consume_o = '0;
    bit_consume_valid_o = 1'b0;
    s_value_len = {1'b0, s_symbol[3:0]};
    s_total_len = CountWidth'(s_code_len + s_value_len);
    s_amplitude = ElementWidth'(
        bit_window_i >> (WindowWidth - int'(s_code_len) - int'(s_value_len))
    ) & ((ElementWidth'(1) << s_value_len) - 1'b1);
    s_value = extend_value(s_amplitude, s_value_len);
    s_run = s_symbol[7:4];
    s_next_index = s_coeff_index_q + {3'd0, s_run};

    unique case (s_state_q)
      Idle: begin
        if (start_i) begin
          s_coeff_index_d = 7'd1;
          s_search_base_d = 8'd0;
          s_block_d       = '0;
          s_dc_d          = previous_dc_i;
          s_err_d         = 1'b0;
          s_state_d       = Dc;
        end
      end
      Dc: begin
        if (s_match && (s_symbol <= 8'd11) && (s_total_len <= bit_count_i)) begin
          bit_consume_o              = s_total_len;
          bit_consume_valid_o        = 1'b1;
          s_dc_d                     = s_dc_q + s_value;
          s_block_d[0+:ElementWidth] = s_dc_q + s_value;
          s_search_base_d            = 8'd0;
          s_state_d                  = Ac;
        end else if (bit_count_i >= CountWidth'(16)) begin
          s_err_d   = 1'b1;
          s_state_d = Result;
        end
      end
      Ac: begin
        if (s_match && (s_total_len <= bit_count_i)) begin
          if (s_symbol == 8'h00) begin
            bit_consume_o       = CountWidth'(s_code_len);
            bit_consume_valid_o = 1'b1;
            s_search_base_d     = 8'd0;
            s_state_d           = Result;
          end else if (s_symbol == 8'hf0) begin
            bit_consume_o       = CountWidth'(s_code_len);
            bit_consume_valid_o = 1'b1;
            if (s_coeff_index_q > 7'd48) begin
              s_err_d   = 1'b1;
              s_state_d = Result;
            end else begin
              s_coeff_index_d = s_coeff_index_q + 7'd16;
              s_search_base_d = 8'd0;
            end
          end else if ((s_value_len == 5'd0) || (s_value_len > 5'd10) ||
                       (s_next_index >= 7'd64)) begin
            s_err_d   = 1'b1;
            s_state_d = Result;
          end else begin
            bit_consume_o                                                         = s_total_len;
            bit_consume_valid_o                                                   = 1'b1;
            s_block_d[zigzag_index(s_next_index[5:0])*ElementWidth+:ElementWidth] = s_value;
            if (s_next_index == 7'd63) begin
              s_state_d = Result;
            end else begin
              s_coeff_index_d = s_next_index + 1'b1;
              s_search_base_d = 8'd0;
            end
          end
        end else if (!s_match) begin
          if ((int'(s_search_base_q) + SearchLanes) >= 256) begin
            s_search_base_d = 8'd0;
            if (bit_count_i >= CountWidth'(16)) begin
              s_err_d   = 1'b1;
              s_state_d = Result;
            end
          end else begin
            s_search_base_d = s_search_base_q + 8'(SearchLanes);
          end
        end
      end
      Result: begin
        if (result_ready_i) begin
          s_state_d = Idle;
        end
      end
      default: s_state_d = Idle;
    endcase
  end

  dffr #(
      .DATA_WIDTH(2)
  ) u_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_state_d),
      .dat_o  (s_state_bits_q)
  );
  dffr #(
      .DATA_WIDTH(7)
  ) u_coeff_index_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_coeff_index_d),
      .dat_o  (s_coeff_index_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_search_base_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_search_base_d),
      .dat_o  (s_search_base_q)
  );
  dffr #(
      .DATA_WIDTH(64 * ElementWidth)
  ) u_block_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_block_d),
      .dat_o  (s_block_q)
  );
  dffr #(
      .DATA_WIDTH(ElementWidth)
  ) u_dc_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_dc_d),
      .dat_o  (s_dc_q)
  );
  dffr u_err_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_d),
      .dat_o  (s_err_q)
  );

`ifndef SYNTHESIS
  initial begin
    if ((ElementWidth < 16) || (WindowWidth < 27) || (SearchLanes < 1) ||
        (SearchLanes > 256) || ((256 % SearchLanes) != 0)) begin
      $fatal(1, "jpeg_entropy_decoder: invalid coefficient or window width");
    end
  end
`endif
endmodule
