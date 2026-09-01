// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND.

module jpeg_entropy_encoder #(
    parameter int unsigned ElementWidth = 24,
    parameter int unsigned TokenSlots   = 4,
    parameter int unsigned TokenWidth   = 32
) (
    // verilog_format: off -- preserve block, table, and token interface columns
    input  logic                                  clk_i,
    input  logic                                  rst_n_i,
    input  logic                                  start_i,
    input  logic [64*ElementWidth-1:0]            block_i,
    input  logic signed [ElementWidth-1:0]         previous_dc_i,
    input  logic [12*16-1:0]                      dc_code_i,
    input  logic [12*5-1:0]                       dc_length_i,
    input  logic [256*16-1:0]                     ac_code_i,
    input  logic [256*5-1:0]                      ac_length_i,
    output logic                                  start_ready_o,
    output logic signed [ElementWidth-1:0]         dc_o,
    output logic [TokenSlots*TokenWidth-1:0]      token_bits_o,
    output logic [TokenSlots*6-1:0]               token_length_o,
    output logic [$clog2(TokenSlots+1)-1:0]        token_count_o,
    output logic                                  token_valid_o,
    output logic                                  token_last_o,
    input  logic                                  token_ready_i,
    output logic                                  error_o
    // verilog_format: on
);
  localparam int unsigned EmitCountWidth = $clog2(TokenSlots + 1);
  typedef enum logic [1:0] {
    Idle,
    Dc,
    Ac
  } state_e;

  state_e                                 s_state_d;
  state_e                                 s_state_q;
  logic        [                     1:0] s_state_bits_q;
  logic        [                     3:0] s_group_d;
  logic        [                     3:0] s_group_q;
  logic        [                     3:0] s_run_d;
  logic        [                     3:0] s_run_q;
  logic        [                     5:0] s_last_nonzero_d;
  logic        [                     5:0] s_last_nonzero_q;
  logic signed [        ElementWidth-1:0] s_dc_d;
  logic signed [        ElementWidth-1:0] s_dc_q;
  logic                                   s_err_d;
  logic                                   s_err_q;
  logic        [                     3:0] s_run_work;
  logic        [$clog2(TokenSlots+1)-1:0] s_emit_count;
  logic signed [        ElementWidth-1:0] s_coefficient_work;
  logic        [                     4:0] s_category_work;
  logic        [                     7:0] s_symbol_work;
  logic        [                    15:0] s_code_work;
  logic        [                     4:0] s_code_len_work;
  logic        [        ElementWidth-1:0] s_amplitude_work;
  logic        [                     5:0] s_total_len_work;

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

  function automatic logic [4:0] value_category(input logic signed [ElementWidth-1:0] value_i);
    logic [ElementWidth-1:0] s_magnitude;
    logic [             4:0] s_category;
    begin
      s_magnitude = value_i < 0 ? ElementWidth'(-value_i) : ElementWidth'(value_i);
      s_category  = 5'd0;
      for (int unsigned index = 0; index < ElementWidth; index++) begin
        if (s_magnitude[index]) begin
          s_category = 5'(index + 1);
        end
      end
      return s_category;
    end
  endfunction

  function automatic logic [ElementWidth-1:0] amplitude_bits(
      input logic signed [ElementWidth-1:0] value_i, input logic [4:0] category_i);
    logic [ElementWidth-1:0] s_mask;
    begin
      s_mask = (ElementWidth'(1) << category_i) - 1'b1;
      return value_i < 0 ? ElementWidth'(value_i) & s_mask : ElementWidth'(value_i);
    end
  endfunction

  function automatic logic [5:0] last_nonzero_index(input logic [64*ElementWidth-1:0] block_i);
    logic [5:0] s_last;
    begin
      s_last = 6'd0;
      for (int unsigned index = 1; index < 64; index++) begin
        if ($signed(block_i[zigzag_index(6'(index))*ElementWidth+:ElementWidth]) != 0) begin
          s_last = 6'(index);
        end
      end
      return s_last;
    end
  endfunction

  function automatic logic [TokenWidth-1:0] compose_token(
      input logic [15:0] code_i, input logic [ElementWidth-1:0] amplitude_i,
      input logic [4:0] category_i);
    logic [TokenWidth-1:0] s_code;
    logic [TokenWidth-1:0] s_amplitude;
    logic [TokenWidth-1:0] s_mask;
    begin
      s_code      = TokenWidth'(code_i);
      s_amplitude = TokenWidth'(amplitude_i);
      s_mask      = (TokenWidth'(1) << category_i) - 1'b1;
      return (s_code << category_i) | (s_amplitude & s_mask);
    end
  endfunction

  assign s_state_q     = state_e'(s_state_bits_q);
  assign start_ready_o = s_state_q == Idle;
  assign dc_o          = s_dc_q;
  assign token_count_o = s_emit_count;
  assign token_valid_o = s_emit_count != '0;
  assign error_o       = s_err_q;

  always_comb begin
    s_state_d          = s_state_q;
    s_group_d          = s_group_q;
    s_run_d            = s_run_q;
    s_last_nonzero_d   = s_last_nonzero_q;
    s_dc_d             = s_dc_q;
    s_err_d            = s_err_q;
    token_bits_o       = '0;
    token_length_o     = '0;
    token_last_o       = 1'b0;
    s_emit_count       = '0;
    s_run_work         = s_run_q;
    s_coefficient_work = '0;
    s_category_work    = '0;
    s_symbol_work      = '0;
    s_code_work        = '0;
    s_code_len_work    = '0;
    s_amplitude_work   = '0;
    s_total_len_work   = '0;

    unique case (s_state_q)
      Idle: begin
        s_group_d = 4'd0;
        s_run_d   = 4'd0;
        if (start_i) begin
          s_dc_d           = block_i[0+:ElementWidth];
          s_last_nonzero_d = last_nonzero_index(block_i);
          s_err_d          = 1'b0;
          s_state_d        = Dc;
        end
      end
      Dc: begin
        s_coefficient_work = s_dc_q - previous_dc_i;
        s_category_work    = value_category(s_coefficient_work);
        if (s_category_work > 5'd11) begin
          s_err_d = 1'b1;
        end else begin
          s_code_work = dc_code_i[s_category_work*16+:16];
          s_code_len_work = dc_length_i[s_category_work*5+:5];
          s_amplitude_work = amplitude_bits(s_coefficient_work, s_category_work);
          s_total_len_work = {1'b0, s_code_len_work} + s_category_work;
          token_bits_o[0+:TokenWidth] =
              compose_token(s_code_work, s_amplitude_work, s_category_work);
          token_length_o[0+:6] = s_total_len_work;
          s_emit_count = EmitCountWidth'(1);
          if (s_code_len_work == 5'd0) begin
            s_err_d = 1'b1;
          end
        end
        if ((s_emit_count == '0) || token_ready_i) begin
          s_state_d = Ac;
        end
      end
      Ac: begin
        for (int unsigned lane = 0; lane < 4; lane++) begin
          if (((s_group_q * 4) + lane + 1) < 64) begin
            s_coefficient_work =
                block_i[zigzag_index(6'((s_group_q*4)+lane+1))*ElementWidth+:ElementWidth];
            if (s_coefficient_work == 0) begin
              if ((s_run_work == 4'd15) &&
                  (6'((s_group_q * 4) + lane + 1) < s_last_nonzero_q)) begin
                s_code_work     = ac_code_i[8'hf0*16+:16];
                s_code_len_work = ac_length_i[8'hf0*5+:5];
                if (s_emit_count < EmitCountWidth'(TokenSlots)) begin
                  token_bits_o[s_emit_count*TokenWidth+:TokenWidth] = TokenWidth'(s_code_work);
                  token_length_o[s_emit_count*6+:6]                 = {1'b0, s_code_len_work};
                  s_emit_count += 1'b1;
                end else begin
                  s_err_d = 1'b1;
                end
                if (s_code_len_work == 5'd0) begin
                  s_err_d = 1'b1;
                end
                s_run_work = 4'd0;
              end else if (s_run_work != 4'd15) begin
                s_run_work += 1'b1;
              end
            end else begin
              s_category_work  = value_category(s_coefficient_work);
              s_symbol_work    = {s_run_work, s_category_work[3:0]};
              s_code_work      = ac_code_i[s_symbol_work*16+:16];
              s_code_len_work  = ac_length_i[s_symbol_work*5+:5];
              s_amplitude_work = amplitude_bits(s_coefficient_work, s_category_work);
              s_total_len_work = {1'b0, s_code_len_work} + s_category_work;
              if ((s_category_work == 5'd0) || (s_category_work > 5'd10) ||
                  (s_code_len_work == 5'd0)) begin
                s_err_d = 1'b1;
              end else if (s_emit_count < EmitCountWidth'(TokenSlots)) begin
                token_bits_o[s_emit_count*TokenWidth+:TokenWidth] =
                    compose_token(s_code_work, s_amplitude_work, s_category_work);
                token_length_o[s_emit_count*6+:6] = s_total_len_work;
                s_emit_count += 1'b1;
              end else begin
                s_err_d = 1'b1;
              end
              s_run_work = 4'd0;
            end
          end
        end
        if (s_group_q == 4'd15 && s_run_work != 4'd0) begin
          s_code_work     = ac_code_i[0+:16];
          s_code_len_work = ac_length_i[0+:5];
          if (s_emit_count < EmitCountWidth'(TokenSlots)) begin
            token_bits_o[s_emit_count*TokenWidth+:TokenWidth] = TokenWidth'(s_code_work);
            token_length_o[s_emit_count*6+:6]                 = {1'b0, s_code_len_work};
            s_emit_count += 1'b1;
          end else begin
            s_err_d = 1'b1;
          end
          if (s_code_len_work == 5'd0) begin
            s_err_d = 1'b1;
          end
          s_run_work = 4'd0;
        end
        token_last_o = s_group_q == 4'd15;
        if (s_emit_count == '0) begin
          s_run_d   = s_run_work;
          s_group_d = s_group_q + 1'b1;
        end else if (token_ready_i) begin
          s_run_d = s_run_work;
          if (s_group_q == 4'd15) begin
            s_state_d = Idle;
          end else begin
            s_group_d = s_group_q + 1'b1;
          end
        end
      end
      default: begin
        s_state_d = Idle;
      end
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
      .DATA_WIDTH(4)
  ) u_group_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_group_d),
      .dat_o  (s_group_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_run_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_run_d),
      .dat_o  (s_run_q)
  );
  dffr #(
      .DATA_WIDTH(6)
  ) u_last_nonzero_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_last_nonzero_d),
      .dat_o  (s_last_nonzero_q)
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
    if (TokenSlots < 4 || TokenWidth < 27 || ElementWidth < 16) begin
      $fatal(1, "jpeg_entropy_encoder: invalid token or coefficient width");
    end
  end
`endif

`ifndef SV_ASSRT_DISABLE
  always_ff @(posedge clk_i) begin
    if (rst_n_i && (s_state_q != Idle)) begin
      assert ($stable(block_i));
      assert ($stable(previous_dc_i));
      assert ($stable(dc_code_i));
      assert ($stable(dc_length_i));
      assert ($stable(ac_code_i));
      assert ($stable(ac_length_i));
    end
  end
`endif
endmodule
