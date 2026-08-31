// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND.

module jpeg_header_writer (
    // verilog_format: off -- preserve command, quantization table, and byte columns
    input  logic          clk_i,
    input  logic          rst_n_i,
    input  logic          start_i,
    input  logic [15:0]   width_i,
    input  logic [15:0]   height_i,
    input  logic [ 1:0]   sampling_i,
    input  logic [15:0]   restart_interval_i,
    input  logic [511:0]  luma_quant_i,
    input  logic [511:0]  chroma_quant_i,
    output logic          start_ready_o,
    output logic [ 7:0]   byte_o,
    output logic          byte_valid_o,
    input  logic          byte_ready_i,
    output logic          done_o,
    output logic          error_o
    // verilog_format: on
);
  localparam int unsigned GrayDhtBytes = 212;
  localparam int unsigned ColorDhtBytes = 420;
  localparam logic [GrayDhtBytes*8-1:0] GrayDht = {
    256'hfaf9f8f7f6f5f4f3f2f1eae9e8e7e6e5e4e3e2e1dad9d8d7d6d5d4d3d2cac9c8,
    256'hc7c6c5c4c3c2bab9b8b7b6b5b4b3b2aaa9a8a7a6a5a4a3a29a99989796959493,
    256'h928a898887868584837a797877767574736a696867666564635a595857565554,
    256'h534a494847464544433a3938373635342a29282726251a191817160a09827262,
    256'h3324f0d15215c1b1422308a19181321471220761511306413121120511040003,
    256'h02017d010000040405050304020303010200100b0a0908070605040302010000,
    160'h00000000000001010101010105010000d200c4ff
  };
  localparam logic [ColorDhtBytes*8-1:0] ColorDht = {
    256'hfaf9f8f7f6f5f4f3f2eae9e8e7e6e5e4e3e2dad9d8d7d6d5d4d3d2cac9c8c7c6,
    256'hc5c4c3c2bab9b8b7b6b5b4b3b2aaa9a8a7a6a5a4a3a29a99989796959493928a,
    256'h89888786858483827a797877767574736a696867666564635a59585756555453,
    256'h4a494847464544433a39383736352a292827261a191817f125e13424160ad172,
    256'h6215f052332309c1b1a191421408813222137161075141120631210504110302,
    256'h010077020100040405070403040402010200110b0a0908070605040302010000,
    256'h00000000010101010101010101030001faf9f8f7f6f5f4f3f2f1eae9e8e7e6e5,
    256'he4e3e2e1dad9d8d7d6d5d4d3d2cac9c8c7c6c5c4c3c2bab9b8b7b6b5b4b3b2aa,
    256'ha9a8a7a6a5a4a3a29a99989796959493928a898887868584837a797877767574,
    256'h736a696867666564635a595857565554534a494847464544433a393837363534,
    256'h2a29282726251a191817160a098272623324f0d15215c1b1422308a191813214,
    256'h7122076151130641312112051104000302017d01000004040505030402030301,
    256'h0200100b0a090807060504030201000000000000000001010101010105010000,
    32'ha201c4ff
  };

  logic         s_active_d;
  logic         s_active_q;
  logic [  9:0] s_position_d;
  logic [  9:0] s_position_q;
  logic [ 15:0] s_width_d;
  logic [ 15:0] s_width_q;
  logic [ 15:0] s_height_d;
  logic [ 15:0] s_height_q;
  logic [  1:0] s_sampling_d;
  logic [  1:0] s_sampling_q;
  logic [ 15:0] s_restart_d;
  logic [ 15:0] s_restart_q;
  logic [511:0] s_luma_quant_d;
  logic [511:0] s_luma_quant_q;
  logic [511:0] s_chroma_quant_d;
  logic [511:0] s_chroma_quant_q;
  logic         s_done_d;
  logic         s_done_q;
  logic         s_err_d;
  logic         s_err_q;
  logic         s_gray;
  logic [  9:0] s_dqt_start;
  logic [  9:0] s_dqt_bytes;
  logic [  9:0] s_sof_start;
  logic [  9:0] s_sof_bytes;
  logic [  9:0] s_dht_start;
  logic [  9:0] s_dht_bytes;
  logic [  9:0] s_dri_start;
  logic [  9:0] s_dri_bytes;
  logic [  9:0] s_sos_start;
  logic [  9:0] s_sos_bytes;
  logic [  9:0] s_total_bytes;
  logic [  9:0] s_relative;

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

  assign s_gray        = s_sampling_q == 2'd0;
  assign s_dqt_start   = 10'd20;
  assign s_dqt_bytes   = s_gray ? 10'd69 : 10'd134;
  assign s_sof_start   = s_dqt_start + s_dqt_bytes;
  assign s_sof_bytes   = s_gray ? 10'd13 : 10'd19;
  assign s_dht_start   = s_sof_start + s_sof_bytes;
  assign s_dht_bytes   = s_gray ? 10'(GrayDhtBytes) : 10'(ColorDhtBytes);
  assign s_dri_start   = s_dht_start + s_dht_bytes;
  assign s_dri_bytes   = (s_restart_q == 16'd0) ? 10'd0 : 10'd6;
  assign s_sos_start   = s_dri_start + s_dri_bytes;
  assign s_sos_bytes   = s_gray ? 10'd10 : 10'd14;
  assign s_total_bytes = s_sos_start + s_sos_bytes;
  assign start_ready_o = !s_active_q;
  assign byte_valid_o  = s_active_q;
  assign done_o        = s_done_q;
  assign error_o       = s_err_q;

  always_comb begin
    byte_o     = 8'd0;
    s_relative = 10'd0;
    if (s_position_q == 10'd0) begin
      byte_o = 8'hff;
    end else if (s_position_q == 10'd1) begin
      byte_o = 8'hd8;
    end else if (s_position_q < 10'd20) begin
      s_relative = s_position_q - 10'd2;
      unique case (s_relative)
        10'd0:          byte_o = 8'hff;
        10'd1:          byte_o = 8'he0;
        10'd2:          byte_o = 8'h00;
        10'd3:          byte_o = 8'h10;
        10'd4:          byte_o = 8'h4a;
        10'd5:          byte_o = 8'h46;
        10'd6:          byte_o = 8'h49;
        10'd7:          byte_o = 8'h46;
        10'd8:          byte_o = 8'h00;
        10'd9:          byte_o = 8'h01;
        10'd10:         byte_o = 8'h02;
        10'd11:         byte_o = 8'h00;
        10'd13, 10'd15: byte_o = 8'h01;
        default:        byte_o = 8'h00;
      endcase
    end else if (s_position_q < s_sof_start) begin
      s_relative = s_position_q - s_dqt_start;
      if (s_relative == 10'd0) byte_o = 8'hff;
      else if (s_relative == 10'd1) byte_o = 8'hdb;
      else if (s_relative == 10'd2) byte_o = 8'h00;
      else if (s_relative == 10'd3) byte_o = s_gray ? 8'h43 : 8'h84;
      else if (s_relative == 10'd4) byte_o = 8'h00;
      else if (s_relative < 10'd69) begin
        byte_o = s_luma_quant_q[zigzag_index(6'(s_relative-5))*8+:8];
      end else if (s_relative == 10'd69) begin
        byte_o = 8'h01;
      end else begin
        byte_o = s_chroma_quant_q[zigzag_index(6'(s_relative-70))*8+:8];
      end
    end else if (s_position_q < s_dht_start) begin
      s_relative = s_position_q - s_sof_start;
      if (s_relative == 10'd0) byte_o = 8'hff;
      else if (s_relative == 10'd1) byte_o = 8'hc0;
      else if (s_relative == 10'd2) byte_o = 8'h00;
      else if (s_relative == 10'd3) byte_o = s_gray ? 8'h0b : 8'h11;
      else if (s_relative == 10'd4) byte_o = 8'h08;
      else if (s_relative == 10'd5) byte_o = s_height_q[15:8];
      else if (s_relative == 10'd6) byte_o = s_height_q[7:0];
      else if (s_relative == 10'd7) byte_o = s_width_q[15:8];
      else if (s_relative == 10'd8) byte_o = s_width_q[7:0];
      else if (s_relative == 10'd9) byte_o = s_gray ? 8'd1 : 8'd3;
      else if (s_relative == 10'd10) byte_o = 8'd1;
      else if (s_relative == 10'd11) begin
        unique case (s_sampling_q)
          2'd0, 2'd1: byte_o = 8'h11;
          2'd2:       byte_o = 8'h21;
          default:    byte_o = 8'h22;
        endcase
      end else if (s_relative == 10'd12) byte_o = 8'd0;
      else if (s_relative == 10'd13) byte_o = 8'd2;
      else if (s_relative == 10'd14) byte_o = 8'h11;
      else if (s_relative == 10'd15) byte_o = 8'd1;
      else if (s_relative == 10'd16) byte_o = 8'd3;
      else if (s_relative == 10'd17) byte_o = 8'h11;
      else byte_o = 8'd1;
    end else if (s_position_q < s_dri_start) begin
      s_relative = s_position_q - s_dht_start;
      byte_o     = s_gray ? GrayDht[s_relative*8+:8] : ColorDht[s_relative*8+:8];
    end else if (s_position_q < s_sos_start) begin
      s_relative = s_position_q - s_dri_start;
      unique case (s_relative)
        10'd0:   byte_o = 8'hff;
        10'd1:   byte_o = 8'hdd;
        10'd2:   byte_o = 8'h00;
        10'd3:   byte_o = 8'h04;
        10'd4:   byte_o = s_restart_q[15:8];
        default: byte_o = s_restart_q[7:0];
      endcase
    end else begin
      s_relative = s_position_q - s_sos_start;
      if (s_relative == 10'd0) byte_o = 8'hff;
      else if (s_relative == 10'd1) byte_o = 8'hda;
      else if (s_relative == 10'd2) byte_o = 8'h00;
      else if (s_relative == 10'd3) byte_o = s_gray ? 8'h08 : 8'h0c;
      else if (s_relative == 10'd4) byte_o = s_gray ? 8'd1 : 8'd3;
      else if (s_relative == 10'd5) byte_o = 8'd1;
      else if (s_relative == 10'd6) byte_o = 8'h00;
      else if (!s_gray && s_relative == 10'd7) byte_o = 8'd2;
      else if (!s_gray && s_relative == 10'd8) byte_o = 8'h11;
      else if (!s_gray && s_relative == 10'd9) byte_o = 8'd3;
      else if (!s_gray && s_relative == 10'd10) byte_o = 8'h11;
      else if (s_relative == s_sos_bytes - 3) byte_o = 8'd0;
      else if (s_relative == s_sos_bytes - 2) byte_o = 8'd63;
      else byte_o = 8'd0;
    end
  end

  always_comb begin
    s_active_d       = s_active_q;
    s_position_d     = s_position_q;
    s_width_d        = s_width_q;
    s_height_d       = s_height_q;
    s_sampling_d     = s_sampling_q;
    s_restart_d      = s_restart_q;
    s_luma_quant_d   = s_luma_quant_q;
    s_chroma_quant_d = s_chroma_quant_q;
    s_done_d         = 1'b0;
    s_err_d          = s_err_q;
    if (start_i && start_ready_o) begin
      s_width_d        = width_i;
      s_height_d       = height_i;
      s_sampling_d     = sampling_i;
      s_restart_d      = restart_interval_i;
      s_luma_quant_d   = luma_quant_i;
      s_chroma_quant_d = chroma_quant_i;
      s_position_d     = 10'd0;
      s_err_d          = (width_i == 16'd0) || (height_i == 16'd0);
      s_active_d       = 1'b1;
    end
    if (byte_valid_o && byte_ready_i) begin
      if (s_position_q + 1'b1 == s_total_bytes) begin
        s_active_d = 1'b0;
        s_done_d   = 1'b1;
      end else begin
        s_position_d = s_position_q + 1'b1;
      end
    end
  end

  dffr u_active_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_active_d),
      .dat_o  (s_active_q)
  );
  dffr #(
      .DATA_WIDTH(10)
  ) u_position_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_position_d),
      .dat_o  (s_position_q)
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
  ) u_sampling_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_sampling_d),
      .dat_o  (s_sampling_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_restart_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_restart_d),
      .dat_o  (s_restart_q)
  );
  dffr #(
      .DATA_WIDTH(512)
  ) u_luma_quant_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_luma_quant_d),
      .dat_o  (s_luma_quant_q)
  );
  dffr #(
      .DATA_WIDTH(512)
  ) u_chroma_quant_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_chroma_quant_d),
      .dat_o  (s_chroma_quant_q)
  );
  dffr u_done_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_done_d),
      .dat_o  (s_done_q)
  );
  dffr u_err_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_d),
      .dat_o  (s_err_q)
  );
endmodule
