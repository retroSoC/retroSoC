// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND.

module jpeg_table_cache #(
    parameter int unsigned ReciprocalWidth = 25
) (
    // verilog_format: off -- preserve command, table lookup, and cached table columns
    input  logic                              clk_i,
    input  logic                              rst_n_i,
    input  logic                              start_i,
    input  logic [ 1:0]                       context_i,
    input  logic [ 1:0]                       quant_id_i,
    input  logic [ 1:0]                       dc_id_i,
    input  logic [ 1:0]                       ac_id_i,
    output logic                              start_ready_o,
    output logic                              lookup_o,
    output logic [ 1:0]                       lookup_context_o,
    output logic [ 3:0]                       lookup_kind_o,
    output logic [ 7:0]                       lookup_index_o,
    input  logic [31:0]                       lookup_data_i,
    input  logic                              lookup_valid_i,
    input  logic                              lookup_err_i,
    output logic [64*8-1:0]                   quant_o,
    output logic [64*ReciprocalWidth-1:0]     reciprocal_o,
    output logic [12*16-1:0]                  dc_code_o,
    output logic [12*5-1:0]                   dc_length_o,
    output logic [256*16-1:0]                 ac_code_o,
    output logic [256*5-1:0]                  ac_length_o,
    output logic                              result_valid_o,
    input  logic                              result_ready_i,
    output logic                              error_o
    // verilog_format: on
);
  typedef enum logic [2:0] {
    Idle,
    QuantIssue,
    QuantWait,
    DcIssue,
    DcWait,
    AcIssue,
    AcWait,
    Result
  } state_e;

  state_e                          s_state_d;
  state_e                          s_state_q;
  logic   [                   2:0] s_state_bits_q;
  logic   [                   1:0] s_context_d;
  logic   [                   1:0] s_context_q;
  logic   [                   1:0] s_quant_id_d;
  logic   [                   1:0] s_quant_id_q;
  logic   [                   1:0] s_dc_id_d;
  logic   [                   1:0] s_dc_id_q;
  logic   [                   1:0] s_ac_id_d;
  logic   [                   1:0] s_ac_id_q;
  logic   [                   7:0] s_index_d;
  logic   [                   7:0] s_index_q;
  logic   [              64*8-1:0] s_quant_d;
  logic   [              64*8-1:0] s_quant_q;
  logic   [64*ReciprocalWidth-1:0] s_reciprocal_d;
  logic   [64*ReciprocalWidth-1:0] s_reciprocal_q;
  logic   [             12*16-1:0] s_dc_code_d;
  logic   [             12*16-1:0] s_dc_code_q;
  logic   [              12*5-1:0] s_dc_len_d;
  logic   [              12*5-1:0] s_dc_len_q;
  logic   [            256*16-1:0] s_ac_code_d;
  logic   [            256*16-1:0] s_ac_code_q;
  logic   [             256*5-1:0] s_ac_len_d;
  logic   [             256*5-1:0] s_ac_len_q;
  logic                            s_err_d;
  logic                            s_err_q;
  logic   [                   7:0] s_quant_value;
  logic   [   ReciprocalWidth-1:0] s_reciprocal_value;

  function automatic logic [ReciprocalWidth-1:0] reciprocal_value(input logic [7:0] quant_i);
    logic [ReciprocalWidth:0] s_numerator;
    begin
      if (quant_i == 8'd0) begin
        return '0;
      end
      s_numerator = (ReciprocalWidth + 1)'(1 << 24) + (ReciprocalWidth + 1)'(quant_i) - 1'b1;
      return ReciprocalWidth'(s_numerator / (ReciprocalWidth + 1)'(quant_i));
    end
  endfunction

  assign s_state_q = state_e'(s_state_bits_q);
  assign start_ready_o = s_state_q == Idle;
  assign lookup_o = (s_state_q == QuantIssue) || (s_state_q == DcIssue) || (s_state_q == AcIssue);
  assign lookup_context_o = s_context_q;
  assign lookup_kind_o = (s_state_q == QuantIssue) ? {2'd0, s_quant_id_q} :
                         (s_state_q == DcIssue) ? (4'd4 + {2'd0, s_dc_id_q}) :
                                                 (4'd8 + {2'd0, s_ac_id_q});
  assign lookup_index_o = s_index_q;
  assign quant_o = s_quant_q;
  assign reciprocal_o = s_reciprocal_q;
  assign dc_code_o = s_dc_code_q;
  assign dc_length_o = s_dc_len_q;
  assign ac_code_o = s_ac_code_q;
  assign ac_length_o = s_ac_len_q;
  assign result_valid_o = s_state_q == Result;
  assign error_o = s_err_q;
  assign s_quant_value = lookup_data_i[7:0];
  assign s_reciprocal_value = (lookup_data_i[31:8] != 24'd0) ?
                                  {1'b0, lookup_data_i[31:8]} :
                                  reciprocal_value(
      lookup_data_i[7:0]
  );

  always_comb begin
    s_state_d      = s_state_q;
    s_context_d    = s_context_q;
    s_quant_id_d   = s_quant_id_q;
    s_dc_id_d      = s_dc_id_q;
    s_ac_id_d      = s_ac_id_q;
    s_index_d      = s_index_q;
    s_quant_d      = s_quant_q;
    s_reciprocal_d = s_reciprocal_q;
    s_dc_code_d    = s_dc_code_q;
    s_dc_len_d     = s_dc_len_q;
    s_ac_code_d    = s_ac_code_q;
    s_ac_len_d     = s_ac_len_q;
    s_err_d        = s_err_q;

    unique case (s_state_q)
      Idle: begin
        if (start_i) begin
          s_context_d    = context_i;
          s_quant_id_d   = quant_id_i;
          s_dc_id_d      = dc_id_i;
          s_ac_id_d      = ac_id_i;
          s_index_d      = 8'd0;
          s_quant_d      = '0;
          s_reciprocal_d = '0;
          s_dc_code_d    = '0;
          s_dc_len_d     = '0;
          s_ac_code_d    = '0;
          s_ac_len_d     = '0;
          s_err_d        = 1'b0;
          s_state_d      = QuantIssue;
        end
      end
      QuantIssue: begin
        s_state_d = QuantWait;
      end
      QuantWait: begin
        if (lookup_valid_i || lookup_err_i) begin
          if (lookup_err_i || (s_quant_value == 8'd0)) begin
            s_err_d = 1'b1;
          end else begin
            s_quant_d[s_index_q*8+:8]                                  = s_quant_value;
            s_reciprocal_d[s_index_q*ReciprocalWidth+:ReciprocalWidth] = s_reciprocal_value;
          end
          if (s_index_q == 8'd63) begin
            s_index_d = 8'd0;
            s_state_d = DcIssue;
          end else begin
            s_index_d = s_index_q + 1'b1;
            s_state_d = QuantIssue;
          end
        end
      end
      DcIssue: begin
        s_state_d = DcWait;
      end
      DcWait: begin
        if (lookup_valid_i || lookup_err_i) begin
          if (lookup_err_i || (lookup_data_i[20:16] == 5'd0)) begin
            s_err_d = 1'b1;
          end else begin
            s_dc_code_d[s_index_q*16+:16] = lookup_data_i[15:0];
            s_dc_len_d[s_index_q*5+:5]    = lookup_data_i[20:16];
          end
          if (s_index_q == 8'd11) begin
            s_index_d = 8'd0;
            s_state_d = AcIssue;
          end else begin
            s_index_d = s_index_q + 1'b1;
            s_state_d = DcIssue;
          end
        end
      end
      AcIssue: begin
        s_state_d = AcWait;
      end
      AcWait: begin
        if (lookup_valid_i || lookup_err_i) begin
          if (lookup_err_i) begin
            s_err_d = 1'b1;
          end else begin
            s_ac_code_d[s_index_q*16+:16] = lookup_data_i[15:0];
            s_ac_len_d[s_index_q*5+:5]    = lookup_data_i[20:16];
          end
          if (s_index_q == 8'hff) begin
            s_index_d = 8'd0;
            s_state_d = Result;
          end else begin
            s_index_d = s_index_q + 1'b1;
            s_state_d = AcIssue;
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
      .DATA_WIDTH(3)
  ) u_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_state_d),
      .dat_o  (s_state_bits_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_context_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_context_d),
      .dat_o  (s_context_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_quant_id_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_quant_id_d),
      .dat_o  (s_quant_id_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_dc_id_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_dc_id_d),
      .dat_o  (s_dc_id_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_ac_id_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ac_id_d),
      .dat_o  (s_ac_id_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_index_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_index_d),
      .dat_o  (s_index_q)
  );
  dffr #(
      .DATA_WIDTH(64 * 8)
  ) u_quant_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_quant_d),
      .dat_o  (s_quant_q)
  );
  dffr #(
      .DATA_WIDTH(64 * ReciprocalWidth)
  ) u_reciprocal_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_reciprocal_d),
      .dat_o  (s_reciprocal_q)
  );
  dffr #(
      .DATA_WIDTH(12 * 16)
  ) u_dc_code_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_dc_code_d),
      .dat_o  (s_dc_code_q)
  );
  dffr #(
      .DATA_WIDTH(12 * 5)
  ) u_dc_len_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_dc_len_d),
      .dat_o  (s_dc_len_q)
  );
  dffr #(
      .DATA_WIDTH(256 * 16)
  ) u_ac_code_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ac_code_d),
      .dat_o  (s_ac_code_q)
  );
  dffr #(
      .DATA_WIDTH(256 * 5)
  ) u_ac_len_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ac_len_d),
      .dat_o  (s_ac_len_q)
  );
  dffr u_err_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_d),
      .dat_o  (s_err_q)
  );

`ifndef SYNTHESIS
  initial begin
    if (ReciprocalWidth != 25) begin
      $fatal(1, "jpeg_table_cache: reciprocal width must be 25 bits");
    end
  end
`endif
endmodule
