// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND.

module jpeg_marker_parser (
    // verilog_format: off -- preserve byte, table, header, and error interface columns
    input  logic          clk_i,
    input  logic          rst_n_i,
    input  logic          start_i,
    input  logic [ 1:0]   table_context_i,
    input  logic [ 7:0]   byte_i,
    input  logic          byte_valid_i,
    output logic          byte_ready_o,
    output logic [ 1:0]   table_context_o,
    output logic [ 3:0]   table_kind_o,
    output logic [ 7:0]   table_index_o,
    output logic [31:0]   table_data_o,
    output logic          table_write_o,
    output logic          table_commit_o,
    output logic          header_valid_o,
    input  logic          header_ready_i,
    output logic          entropy_o,
    output logic [15:0]   width_o,
    output logic [15:0]   height_o,
    output logic [ 1:0]   sampling_o,
    output logic [ 1:0]   component_count_o,
    output logic [23:0]   component_id_o,
    output logic [23:0]   component_factor_o,
    output logic [ 5:0]   quant_table_o,
    output logic [ 5:0]   dc_table_o,
    output logic [ 5:0]   ac_table_o,
    output logic [15:0]   restart_interval_o,
    output logic [31:0]   marker_count_o,
    output logic          error_o,
    output logic [ 4:0]   error_code_o
    // verilog_format: on
);
  typedef enum logic [4:0] {
    Idle,
    SoiPrefix,
    SoiCode,
    MarkerPrefix,
    MarkerCode,
    LengthHigh,
    LengthLow,
    Skip,
    DqtInfo,
    DqtData,
    DhtInfo,
    DhtCounts,
    DhtAdvance,
    DhtValues,
    SofData,
    DriData,
    SosData,
    HeaderReady,
    Entropy,
    Error
  } state_e;

  localparam logic [4:0] ErrorMarker = 5'd4;
  localparam logic [4:0] ErrorProcess = 5'd5;
  localparam logic [4:0] ErrorPrecision = 5'd6;
  localparam logic [4:0] ErrorSampling = 5'd7;
  localparam logic [4:0] ErrorLength = 5'd8;
  localparam logic [4:0] ErrorHuffman = 5'd9;
  localparam logic [4:0] ErrorTruncated = 5'd10;

  state_e             s_state_d;
  state_e             s_state_q;
  logic   [ 4:0]      s_state_bits_q;
  logic   [ 1:0]      s_context_d;
  logic   [ 1:0]      s_context_q;
  logic   [ 7:0]      s_marker_d;
  logic   [ 7:0]      s_marker_q;
  logic   [ 7:0]      s_len_high_d;
  logic   [ 7:0]      s_len_high_q;
  logic   [15:0]      s_remaining_d;
  logic   [15:0]      s_remaining_q;
  logic   [15:0]      s_payload_index_d;
  logic   [15:0]      s_payload_index_q;
  logic   [15:0]      s_width_d;
  logic   [15:0]      s_width_q;
  logic   [15:0]      s_height_d;
  logic   [15:0]      s_height_q;
  logic   [ 1:0]      s_component_cnt_d;
  logic   [ 1:0]      s_component_cnt_q;
  logic   [ 2:0][7:0] s_component_id_d;
  logic   [ 2:0][7:0] s_component_id_q;
  logic   [ 2:0][7:0] s_component_factor_d;
  logic   [ 2:0][7:0] s_component_factor_q;
  logic   [ 2:0][1:0] s_quant_table_d;
  logic   [ 2:0][1:0] s_quant_table_q;
  logic   [ 2:0][1:0] s_dc_table_d;
  logic   [ 2:0][1:0] s_dc_table_q;
  logic   [ 2:0][1:0] s_ac_table_d;
  logic   [ 2:0][1:0] s_ac_table_q;
  logic   [15:0]      s_restart_interval_d;
  logic   [15:0]      s_restart_interval_q;
  logic   [31:0]      s_marker_cnt_d;
  logic   [31:0]      s_marker_cnt_q;
  logic   [ 7:0]      s_dqt_info_d;
  logic   [ 7:0]      s_dqt_info_q;
  logic   [ 6:0]      s_table_index_d;
  logic   [ 6:0]      s_table_index_q;
  logic   [ 7:0]      s_dht_info_d;
  logic   [ 7:0]      s_dht_info_q;
  logic   [15:0][7:0] s_huff_counts_d;
  logic   [15:0][7:0] s_huff_counts_q;
  logic   [ 4:0]      s_huff_len_d;
  logic   [ 4:0]      s_huff_len_q;
  logic   [ 8:0]      s_huff_values_d;
  logic   [ 8:0]      s_huff_values_q;
  logic   [ 7:0]      s_huff_len_remaining_d;
  logic   [ 7:0]      s_huff_len_remaining_q;
  logic   [15:0]      s_huff_code_d;
  logic   [15:0]      s_huff_code_q;
  logic   [ 7:0]      s_sos_ss_d;
  logic   [ 7:0]      s_sos_ss_q;
  logic   [ 7:0]      s_sos_se_d;
  logic   [ 7:0]      s_sos_se_q;
  logic               s_err_d;
  logic               s_err_q;
  logic   [ 4:0]      s_err_code_d;
  logic   [ 4:0]      s_err_code_q;
  logic   [15:0]      s_segment_len;
  logic               s_byte_accept;
  logic   [ 1:0]      s_component_index;
  logic   [ 1:0]      s_sos_component_index;

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

  function automatic logic [31:0] saturating_increment(input logic [31:0] value_i);
    return (&value_i) ? value_i : value_i + 1'b1;
  endfunction

  assign s_state_q = state_e'(s_state_bits_q);
  assign byte_ready_o = (s_state_q != Idle) && (s_state_q != DhtAdvance) &&
                        (s_state_q != HeaderReady) && (s_state_q != Entropy) &&
                        (s_state_q != Error);
  assign s_byte_accept = byte_valid_i && byte_ready_o;
  assign s_segment_len = {s_len_high_q, byte_i};
  assign header_valid_o = s_state_q == HeaderReady;
  assign entropy_o = s_state_q == Entropy;
  assign width_o = s_width_q;
  assign height_o = s_height_q;
  assign component_count_o = s_component_cnt_q;
  assign component_id_o = s_component_id_q;
  assign component_factor_o = s_component_factor_q;
  assign quant_table_o = s_quant_table_q;
  assign dc_table_o = s_dc_table_q;
  assign ac_table_o = s_ac_table_q;
  assign restart_interval_o = s_restart_interval_q;
  assign marker_count_o = s_marker_cnt_q;
  assign error_o = s_err_q;
  assign error_code_o = s_err_code_q;
  assign table_context_o = s_context_q;
  assign sampling_o = (s_component_cnt_q == 2'd1) ? 2'd0 :
                      (s_component_factor_q[0] == 8'h11) ? 2'd1 :
                      (s_component_factor_q[0] == 8'h21) ? 2'd2 : 2'd3;

  always_comb begin
    s_component_index = '0;
    if (s_payload_index_q >= 16'd6) begin
      s_component_index = 2'((int'(s_payload_index_q) - 6) / 3);
    end
    s_sos_component_index = 2'((int'(s_payload_index_q) - 1) / 2);
  end

  always_comb begin
    s_state_d              = s_state_q;
    s_context_d            = s_context_q;
    s_marker_d             = s_marker_q;
    s_len_high_d           = s_len_high_q;
    s_remaining_d          = s_remaining_q;
    s_payload_index_d      = s_payload_index_q;
    s_width_d              = s_width_q;
    s_height_d             = s_height_q;
    s_component_cnt_d      = s_component_cnt_q;
    s_component_id_d       = s_component_id_q;
    s_component_factor_d   = s_component_factor_q;
    s_quant_table_d        = s_quant_table_q;
    s_dc_table_d           = s_dc_table_q;
    s_ac_table_d           = s_ac_table_q;
    s_restart_interval_d   = s_restart_interval_q;
    s_marker_cnt_d         = s_marker_cnt_q;
    s_dqt_info_d           = s_dqt_info_q;
    s_table_index_d        = s_table_index_q;
    s_dht_info_d           = s_dht_info_q;
    s_huff_counts_d        = s_huff_counts_q;
    s_huff_len_d           = s_huff_len_q;
    s_huff_values_d        = s_huff_values_q;
    s_huff_len_remaining_d = s_huff_len_remaining_q;
    s_huff_code_d          = s_huff_code_q;
    s_sos_ss_d             = s_sos_ss_q;
    s_sos_se_d             = s_sos_se_q;
    s_err_d                = s_err_q;
    s_err_code_d           = s_err_code_q;
    table_kind_o           = 4'd0;
    table_index_o          = 8'd0;
    table_data_o           = 32'd0;
    table_write_o          = 1'b0;
    table_commit_o         = 1'b0;

    if (start_i) begin
      s_state_d            = SoiPrefix;
      s_context_d          = table_context_i;
      s_remaining_d        = 16'd0;
      s_payload_index_d    = 16'd0;
      s_width_d            = 16'd0;
      s_height_d           = 16'd0;
      s_component_cnt_d    = 2'd0;
      s_component_id_d     = '0;
      s_component_factor_d = '0;
      s_quant_table_d      = '0;
      s_dc_table_d         = '0;
      s_ac_table_d         = '0;
      s_restart_interval_d = 16'd0;
      s_marker_cnt_d       = 32'd0;
      s_err_d              = 1'b0;
      s_err_code_d         = 5'd0;
    end else begin
      unique case (s_state_q)
        Idle: begin
        end
        SoiPrefix: begin
          if (s_byte_accept) begin
            if (byte_i == 8'hff) begin
              s_state_d = SoiCode;
            end else begin
              s_err_d      = 1'b1;
              s_err_code_d = ErrorMarker;
              s_state_d    = Error;
            end
          end
        end
        SoiCode: begin
          if (s_byte_accept) begin
            if (byte_i == 8'hd8) begin
              s_marker_cnt_d = 32'd1;
              s_state_d      = MarkerPrefix;
            end else begin
              s_err_d      = 1'b1;
              s_err_code_d = ErrorMarker;
              s_state_d    = Error;
            end
          end
        end
        MarkerPrefix: begin
          if (s_byte_accept && (byte_i == 8'hff)) begin
            s_state_d = MarkerCode;
          end else if (s_byte_accept) begin
            s_err_d      = 1'b1;
            s_err_code_d = ErrorMarker;
            s_state_d    = Error;
          end
        end
        MarkerCode: begin
          if (s_byte_accept) begin
            if (byte_i == 8'hff) begin
              s_state_d = MarkerCode;
            end else if ((byte_i == 8'hd8) || (byte_i == 8'hd9) ||
                         ((byte_i >= 8'hd0) && (byte_i <= 8'hd7))) begin
              s_err_d      = 1'b1;
              s_err_code_d = ErrorMarker;
              s_state_d    = Error;
            end else if ((byte_i == 8'hc1) || (byte_i == 8'hc2) ||
                         (byte_i == 8'hc3) || ((byte_i >= 8'hc5) && (byte_i <= 8'hcf))) begin
              s_err_d      = 1'b1;
              s_err_code_d = ErrorProcess;
              s_state_d    = Error;
            end else if (byte_i == 8'hdc) begin
              s_err_d      = 1'b1;
              s_err_code_d = ErrorProcess;
              s_state_d    = Error;
            end else begin
              s_marker_d     = byte_i;
              s_marker_cnt_d = saturating_increment(s_marker_cnt_q);
              s_state_d      = LengthHigh;
            end
          end
        end
        LengthHigh: begin
          if (s_byte_accept) begin
            s_len_high_d = byte_i;
            s_state_d    = LengthLow;
          end
        end
        LengthLow: begin
          if (s_byte_accept) begin
            if (s_segment_len < 16'd2) begin
              s_err_d      = 1'b1;
              s_err_code_d = ErrorLength;
              s_state_d    = Error;
            end else begin
              s_remaining_d     = s_segment_len - 16'd2;
              s_payload_index_d = 16'd0;
              unique case (s_marker_q)
                8'hdb: s_state_d = DqtInfo;
                8'hc4: s_state_d = DhtInfo;
                8'hc0: s_state_d = SofData;
                8'hdd: s_state_d = DriData;
                8'hda: s_state_d = SosData;
                default: begin
                  if ((s_marker_q >= 8'he0 && s_marker_q <= 8'hef) || (s_marker_q == 8'hfe)) begin
                    if (s_segment_len == 16'd2) begin
                      s_state_d = MarkerPrefix;
                    end else begin
                      s_state_d = Skip;
                    end
                  end else begin
                    s_err_d      = 1'b1;
                    s_err_code_d = ErrorMarker;
                    s_state_d    = Error;
                  end
                end
              endcase
            end
          end
        end
        Skip: begin
          if (s_byte_accept) begin
            s_remaining_d = s_remaining_q - 1'b1;
            if (s_remaining_q == 16'd1) begin
              s_state_d = MarkerPrefix;
            end
          end
        end
        DqtInfo: begin
          if (s_byte_accept) begin
            if ((byte_i[7:4] != 4'd0) || (byte_i[3:0] > 4'd3) || (s_remaining_q < 16'd65)) begin
              s_err_d      = 1'b1;
              s_err_code_d = ErrorPrecision;
              s_state_d    = Error;
            end else begin
              s_dqt_info_d    = byte_i;
              s_table_index_d = 7'd0;
              s_remaining_d   = s_remaining_q - 1'b1;
              s_state_d       = DqtData;
            end
          end
        end
        DqtData: begin
          if (s_byte_accept) begin
            if (byte_i == 8'd0) begin
              s_err_d      = 1'b1;
              s_err_code_d = ErrorPrecision;
              s_state_d    = Error;
            end else begin
              table_kind_o  = s_dqt_info_q[3:0];
              table_index_o = {2'd0, zigzag_index(s_table_index_q[5:0])};
              table_data_o  = {24'd0, byte_i};
              table_write_o = 1'b1;
              s_remaining_d = s_remaining_q - 1'b1;
              if (s_table_index_q == 7'd63) begin
                s_table_index_d = 7'd0;
                if (s_remaining_q == 16'd1) begin
                  s_state_d = MarkerPrefix;
                end else begin
                  s_state_d = DqtInfo;
                end
              end else begin
                s_table_index_d = s_table_index_q + 1'b1;
              end
            end
          end
        end
        DhtInfo: begin
          if (s_byte_accept) begin
            if ((byte_i[7:4] > 4'd1) || (byte_i[3:0] > 4'd3) || (s_remaining_q < 16'd18)) begin
              s_err_d      = 1'b1;
              s_err_code_d = ErrorHuffman;
              s_state_d    = Error;
            end else begin
              s_dht_info_d    = byte_i;
              s_huff_counts_d = '0;
              s_table_index_d = 7'd0;
              s_huff_values_d = 9'd0;
              s_remaining_d   = s_remaining_q - 1'b1;
              s_state_d       = DhtCounts;
            end
          end
        end
        DhtCounts: begin
          if (s_byte_accept) begin
            s_huff_counts_d[s_table_index_q[3:0]] = byte_i;
            s_huff_values_d                       = s_huff_values_q + 9'(byte_i);
            s_remaining_d                         = s_remaining_q - 1'b1;
            if (s_table_index_q == 7'd15) begin
              if ((s_huff_values_q + 9'(byte_i) == 9'd0) ||
                  (s_huff_values_q + 9'(byte_i) > 9'd256) ||
                  (s_remaining_q - 1'b1 < 16'(s_huff_values_q + 9'(byte_i)))) begin
                s_err_d      = 1'b1;
                s_err_code_d = ErrorHuffman;
                s_state_d    = Error;
              end else begin
                s_huff_len_d  = 5'd1;
                s_huff_code_d = 16'd0;
                s_state_d     = DhtAdvance;
              end
            end else begin
              s_table_index_d = s_table_index_q + 1'b1;
            end
          end
        end
        DhtAdvance: begin
          if (s_huff_values_q == 9'd0) begin
            if (s_remaining_q == 16'd0) begin
              s_state_d = MarkerPrefix;
            end else begin
              s_state_d = DhtInfo;
            end
          end else if (s_huff_len_q > 5'd16) begin
            s_err_d      = 1'b1;
            s_err_code_d = ErrorHuffman;
            s_state_d    = Error;
          end else if (s_huff_counts_q[s_huff_len_q-1'b1] != 8'd0) begin
            s_huff_len_remaining_d = s_huff_counts_q[s_huff_len_q-1'b1];
            s_state_d              = DhtValues;
          end else begin
            s_huff_code_d = s_huff_code_q << 1;
            s_huff_len_d  = s_huff_len_q + 1'b1;
          end
        end
        DhtValues: begin
          if (s_byte_accept) begin
            table_kind_o = (s_dht_info_q[7:4] != 4'd0) ?
                               (4'd8 + s_dht_info_q[3:0]) :
                               (4'd4 + s_dht_info_q[3:0]);
            table_index_o = byte_i;
            table_data_o = {11'd0, s_huff_len_q, s_huff_code_q};
            table_write_o = 1'b1;
            s_huff_code_d = s_huff_code_q + 1'b1;
            s_huff_values_d = s_huff_values_q - 1'b1;
            s_huff_len_remaining_d = s_huff_len_remaining_q - 1'b1;
            s_remaining_d = s_remaining_q - 1'b1;
            if (s_huff_values_q == 9'd1) begin
              if (s_remaining_q == 16'd1) begin
                s_state_d = MarkerPrefix;
              end else begin
                s_state_d = DhtInfo;
              end
            end else if (s_huff_len_remaining_q == 8'd1) begin
              s_huff_code_d = (s_huff_code_q + 1'b1) << 1;
              s_huff_len_d  = s_huff_len_q + 1'b1;
              s_state_d     = DhtAdvance;
            end
          end
        end
        SofData: begin
          if (s_byte_accept) begin
            s_remaining_d = s_remaining_q - 1'b1;
            unique case (s_payload_index_q)
              16'd0: begin
                if (byte_i != 8'd8) begin
                  s_err_d      = 1'b1;
                  s_err_code_d = ErrorPrecision;
                  s_state_d    = Error;
                end
              end
              16'd1: s_height_d[15:8] = byte_i;
              16'd2: s_height_d[7:0] = byte_i;
              16'd3: s_width_d[15:8] = byte_i;
              16'd4: s_width_d[7:0] = byte_i;
              16'd5: begin
                if ((byte_i != 8'd1) && (byte_i != 8'd3)) begin
                  s_err_d      = 1'b1;
                  s_err_code_d = ErrorSampling;
                  s_state_d    = Error;
                end else begin
                  s_component_cnt_d = byte_i[1:0];
                end
              end
              default: begin
                if (((s_payload_index_q - 16'd6) % 3) == 0) begin
                  s_component_id_d[s_component_index] = byte_i;
                end else if (((s_payload_index_q - 16'd6) % 3) == 1) begin
                  s_component_factor_d[s_component_index] = byte_i;
                end else if (byte_i > 8'd3) begin
                  s_err_d      = 1'b1;
                  s_err_code_d = ErrorSampling;
                  s_state_d    = Error;
                end else begin
                  s_quant_table_d[s_component_index] = byte_i[1:0];
                end
              end
            endcase
            s_payload_index_d = s_payload_index_q + 1'b1;
            if ((s_remaining_q == 16'd1) && (s_state_d != Error)) begin
              if ((s_width_d == 16'd0) || (s_height_d == 16'd0) ||
                  (s_payload_index_q + 1'b1 != 16'(6 + (3 * s_component_cnt_q))) ||
                  ((s_component_cnt_q == 2'd1) && (s_component_factor_d[0] != 8'h11)) ||
                  ((s_component_cnt_q == 2'd3) &&
                   !((s_component_factor_d[0] == 8'h11) ||
                     (s_component_factor_d[0] == 8'h21) ||
                     (s_component_factor_d[0] == 8'h22))) ||
                  ((s_component_cnt_q == 2'd3) &&
                   ((s_component_factor_d[1] != 8'h11) ||
                    (s_component_factor_d[2] != 8'h11)))) begin
                s_err_d      = 1'b1;
                s_err_code_d = ErrorLength;
                s_state_d    = Error;
              end else begin
                s_state_d = MarkerPrefix;
              end
            end
          end
        end
        DriData: begin
          if (s_byte_accept) begin
            if (s_remaining_q == 16'd2) begin
              s_restart_interval_d[15:8] = byte_i;
            end else if (s_remaining_q == 16'd1) begin
              s_restart_interval_d[7:0] = byte_i;
              s_state_d                 = MarkerPrefix;
            end else begin
              s_err_d      = 1'b1;
              s_err_code_d = ErrorLength;
              s_state_d    = Error;
            end
            s_remaining_d = s_remaining_q - 1'b1;
          end
        end
        SosData: begin
          if (s_byte_accept) begin
            s_remaining_d = s_remaining_q - 1'b1;
            if (s_payload_index_q == 16'd0) begin
              if (byte_i != {6'd0, s_component_cnt_q}) begin
                s_err_d      = 1'b1;
                s_err_code_d = ErrorSampling;
                s_state_d    = Error;
              end
            end else if (s_payload_index_q <= (2 * s_component_cnt_q)) begin
              if (s_payload_index_q[0]) begin
                if (byte_i != s_component_id_q[s_sos_component_index]) begin
                  s_err_d      = 1'b1;
                  s_err_code_d = ErrorSampling;
                  s_state_d    = Error;
                end
              end else if ((byte_i[7:4] > 4'd3) || (byte_i[3:0] > 4'd3)) begin
                s_err_d      = 1'b1;
                s_err_code_d = ErrorHuffman;
                s_state_d    = Error;
              end else begin
                s_dc_table_d[s_sos_component_index] = byte_i[5:4];
                s_ac_table_d[s_sos_component_index] = byte_i[1:0];
              end
            end else if (s_payload_index_q == (1 + (2 * s_component_cnt_q))) begin
              s_sos_ss_d = byte_i;
            end else if (s_payload_index_q == (2 + (2 * s_component_cnt_q))) begin
              s_sos_se_d = byte_i;
            end else if (s_payload_index_q == (3 + (2 * s_component_cnt_q))) begin
              if ((s_sos_ss_q != 8'd0) || (s_sos_se_q != 8'd63) || (byte_i != 8'd0) ||
                  (s_remaining_q != 16'd1)) begin
                s_err_d      = 1'b1;
                s_err_code_d = ErrorProcess;
                s_state_d    = Error;
              end else begin
                table_commit_o = 1'b1;
                s_state_d      = HeaderReady;
              end
            end else begin
              s_err_d      = 1'b1;
              s_err_code_d = ErrorLength;
              s_state_d    = Error;
            end
            s_payload_index_d = s_payload_index_q + 1'b1;
          end
        end
        HeaderReady: begin
          if (header_ready_i) begin
            s_state_d = Entropy;
          end
        end
        Entropy: begin
        end
        Error: begin
        end
        default: s_state_d = Error;
      endcase
    end
  end

  dffr #(
      .DATA_WIDTH(5)
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
      .DATA_WIDTH(8)
  ) u_marker_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_marker_d),
      .dat_o  (s_marker_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_len_high_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_len_high_d),
      .dat_o  (s_len_high_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_remaining_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_remaining_d),
      .dat_o  (s_remaining_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_payload_index_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_payload_index_d),
      .dat_o  (s_payload_index_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_width_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_width_d),
      .dat_o  (s_width_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_height_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_height_d),
      .dat_o  (s_height_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_component_cnt_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_component_cnt_d),
      .dat_o  (s_component_cnt_q)
  );
  dffr #(
      .DATA_WIDTH(24)
  ) u_component_id_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_component_id_d),
      .dat_o  (s_component_id_q)
  );
  dffr #(
      .DATA_WIDTH(24)
  ) u_component_factor_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_component_factor_d),
      .dat_o  (s_component_factor_q)
  );
  dffr #(
      .DATA_WIDTH(6)
  ) u_quant_table_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_quant_table_d),
      .dat_o  (s_quant_table_q)
  );
  dffr #(
      .DATA_WIDTH(6)
  ) u_dc_table_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_dc_table_d),
      .dat_o  (s_dc_table_q)
  );
  dffr #(
      .DATA_WIDTH(6)
  ) u_ac_table_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ac_table_d),
      .dat_o  (s_ac_table_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_restart_interval_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_restart_interval_d),
      .dat_o  (s_restart_interval_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_marker_cnt_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_marker_cnt_d),
      .dat_o  (s_marker_cnt_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_dqt_info_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_dqt_info_d),
      .dat_o  (s_dqt_info_q)
  );
  dffr #(
      .DATA_WIDTH(7)
  ) u_table_index_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_table_index_d),
      .dat_o  (s_table_index_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_dht_info_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_dht_info_d),
      .dat_o  (s_dht_info_q)
  );
  dffr #(
      .DATA_WIDTH(16 * 8)
  ) u_huff_counts_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_huff_counts_d),
      .dat_o  (s_huff_counts_q)
  );
  dffr #(
      .DATA_WIDTH(5)
  ) u_huff_len_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_huff_len_d),
      .dat_o  (s_huff_len_q)
  );
  dffr #(
      .DATA_WIDTH(9)
  ) u_huff_values_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_huff_values_d),
      .dat_o  (s_huff_values_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_huff_len_remaining_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_huff_len_remaining_d),
      .dat_o  (s_huff_len_remaining_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_huff_code_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_huff_code_d),
      .dat_o  (s_huff_code_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_sos_ss_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_sos_ss_d),
      .dat_o  (s_sos_ss_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_sos_se_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_sos_se_d),
      .dat_o  (s_sos_se_q)
  );
  dffr u_err_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_d),
      .dat_o  (s_err_q)
  );
  dffr #(
      .DATA_WIDTH(5)
  ) u_err_code_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_code_d),
      .dat_o  (s_err_code_q)
  );
endmodule
