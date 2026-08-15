// Copyright 2019 EmbedFire http://www.embedfire.com
// https://github.com/Embedfire-altera <embedfire@embedfire.com>
//
// The first version of this code was derived from EmbedFire sd_init.v. The
// original code is open source on Github, but it doesn't specify an open-source
// license. I'm re-releasing it here under the most compatible license(PSL License).
// If anyone knows what the original license is, please contact <miaoyuchi@ict.ac.cn>.
//
// -- Adaptable modifications are redistributed under compatible License --
//
// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module spisd_init (
    input  logic clk_i,
    input  logic rst_n_i,
    output logic init_done_o,
    output logic spisd_clk_o,
    output logic spisd_cs_o,
    output logic spisd_mosi_o,
    input  logic spisd_miso_i
);

  localparam logic [47:0] Cmd0 = {8'h40, 8'h00, 8'h00, 8'h00, 8'h00, 8'h95};
  localparam logic [47:0] Cmd8 = {8'h48, 8'h00, 8'h00, 8'h01, 8'hAA, 8'h87};
  localparam logic [47:0] Cmd55 = {8'h77, 8'h00, 8'h00, 8'h00, 8'h00, 8'hFF};
  localparam logic [47:0] Acmd41 = {8'h69, 8'h40, 8'h00, 8'h00, 8'h00, 8'hFF};
  localparam int signed DivFreq = 32'sd200;
  localparam int signed OverTimeNum = 32'sd25000;

  typedef enum logic [2:0] {
    Idle       = 3'd0,
    SendCmd0   = 3'd1,
    WaitCmd0   = 3'd2,
    SendCmd8   = 3'd3,
    SendCmd55  = 3'd4,
    SendAcmd41 = 3'd5,
    InitDone   = 3'd6
  } spisd_init_state_e;

  logic s_div_clk_d, s_div_clk_q;
  logic [7:0] s_div_cnt_d, s_div_cnt_q;  // 512 div
  logic [6:0] s_boot_cnt_d, s_boot_cnt_q;  // count 128
  spisd_init_state_e s_fsm_d, s_fsm_q;
  logic [2:0] s_fsm_bits_q;
  logic s_fir_clk_edge, s_sec_clk_edge;
  // Response signals.
  logic        s_resp_en;
  logic [47:0] s_resp_data;
  logic        s_resp_flag;
  logic [ 5:0] s_resp_bit_cnt;
  // utils
  logic [ 5:0] s_cmd_bit_cnt;
  logic [15:0] s_overflow_cnt;
  logic        s_overflow_en;
  // spi if
  logic        s_init_done;
  logic s_spisd_cs, s_spisd_mosi;

  assign init_done_o    = s_init_done;
  assign spisd_clk_o    = s_div_clk_q;
  assign spisd_cs_o     = s_spisd_cs;
  assign spisd_mosi_o   = s_spisd_mosi;
  // fir: fall sec: pos
  assign s_fir_clk_edge = s_div_clk_q && (s_div_cnt_q == '0);
  assign s_sec_clk_edge = (~s_div_clk_q) && (s_div_cnt_q == '0);
  assign s_fsm_q        = spisd_init_state_e'(s_fsm_bits_q);

  always_comb begin
    s_div_cnt_d = s_div_cnt_q;
    s_div_clk_d = s_div_clk_q;
    if (s_div_cnt_q == '0) begin
      s_div_cnt_d = '1;
      s_div_clk_d = ~s_div_clk_q;
    end else begin
      s_div_cnt_d = s_div_cnt_q - 1'b1;
    end
  end
  dffrh #(
      .DATA_WIDTH(8)
  ) u_div_cnt_dffrh (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_div_cnt_d),
      .dat_o  (s_div_cnt_q)
  );

  dffrh #(
      .DATA_WIDTH(1)
  ) u_div_clk_dffrh (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_div_clk_d),
      .dat_o  (s_div_clk_q)
  );

  always_comb begin
    s_boot_cnt_d = s_boot_cnt_q;
    if (s_fir_clk_edge) begin
      if (s_fsm_q == Idle) begin
        if (s_boot_cnt_q != '0) s_boot_cnt_d = s_boot_cnt_q - 1'b1;
      end else begin
        s_boot_cnt_d = '1;
      end
    end
  end
  dfferh #(
      .DATA_WIDTH(7)
  ) u_boot_cnt_dfferh (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_fir_clk_edge),
      .dat_i  (s_boot_cnt_d),
      .dat_o  (s_boot_cnt_q)
  );


  // Response capture and command sequencing depend on edge-qualified ordered
  // updates, so the processes remain intact to preserve SPI timing exactly.
  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_resp_en      <= '0;
      s_resp_data    <= '0;
      s_resp_flag    <= '0;
      s_resp_bit_cnt <= '0;
    end else begin
      if (s_sec_clk_edge) begin
        if (spisd_miso_i == 1'b0 && s_resp_flag == 1'b0) begin
          s_resp_flag    <= 1'b1;
          s_resp_data    <= {s_resp_data[46:0], spisd_miso_i};
          s_resp_bit_cnt <= s_resp_bit_cnt + 6'd1;
          s_resp_en      <= 1'b0;
        end else if (s_resp_flag) begin
          s_resp_data    <= {s_resp_data[46:0], spisd_miso_i};
          s_resp_bit_cnt <= s_resp_bit_cnt + 6'd1;
          if (s_resp_bit_cnt == 6'd47) begin
            s_resp_flag    <= 1'b0;
            s_resp_bit_cnt <= '0;
            s_resp_en      <= 1'b1;
          end
        end else s_resp_en <= 1'b0;
      end
    end
  end

  always_comb begin
    s_fsm_d = s_fsm_q;
    case (s_fsm_q)
      Idle: begin
        if (s_boot_cnt_q == '0) s_fsm_d = SendCmd0;
      end
      SendCmd0: begin
        if (s_cmd_bit_cnt == 6'd47) s_fsm_d = WaitCmd0;
      end
      WaitCmd0: begin
        if (s_resp_en) begin
          if (s_resp_data[47:40] == 8'h01) s_fsm_d = SendCmd8;
          else s_fsm_d = Idle;
        end else if (s_overflow_en) s_fsm_d = Idle;
      end

      SendCmd8: begin
        if (s_resp_en) begin
          if (s_resp_data[19:16] == 4'b0001) s_fsm_d = SendCmd55;
          else s_fsm_d = Idle;
        end
      end
      SendCmd55: begin
        if (s_resp_en) begin
          if (s_resp_data[47:40] == 8'h01) s_fsm_d = SendAcmd41;
        end
      end
      SendAcmd41: begin
        if (s_resp_en) begin
          if (s_resp_data[47:40] == 8'h00) s_fsm_d = InitDone;
          else s_fsm_d = SendCmd55;
        end
      end
      InitDone: s_fsm_d = InitDone;
      default:  s_fsm_d = Idle;
    endcase
  end
  dffer #(
      .DATA_WIDTH(3)
  ) u_fsm_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_fir_clk_edge),
      .dat_i  (s_fsm_d),
      .dat_o  (s_fsm_bits_q)
  );

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_init_done    <= '0;
      s_spisd_cs     <= '1;
      s_spisd_mosi   <= '1;

      s_cmd_bit_cnt  <= '0;
      s_overflow_cnt <= '0;
      s_overflow_en  <= '0;
    end else begin
      if (s_fir_clk_edge) begin
        s_overflow_en <= 1'b0;
        case (s_fsm_q)
          Idle: begin
            s_spisd_cs   <= 1'b1;
            s_spisd_mosi <= 1'b1;
          end
          SendCmd0: begin
            s_spisd_cs    <= 1'b0;
            s_spisd_mosi  <= Cmd0[6'd47-s_cmd_bit_cnt];
            s_cmd_bit_cnt <= s_cmd_bit_cnt + 6'd1;
            if (s_cmd_bit_cnt == 6'd47) s_cmd_bit_cnt <= '0;
          end
          WaitCmd0: begin
            s_spisd_mosi <= 1'b1;
            if (s_resp_en) s_spisd_cs <= 1'b1;

            s_overflow_cnt <= s_overflow_cnt + 1'b1;
            if (s_overflow_cnt == OverTimeNum) s_overflow_en <= 1'b1;
            if (s_overflow_en) s_overflow_cnt <= '0;
          end
          SendCmd8: begin
            if (s_cmd_bit_cnt <= 6'd47) begin
              s_cmd_bit_cnt <= s_cmd_bit_cnt + 6'd1;
              s_spisd_cs    <= 1'b0;
              s_spisd_mosi  <= Cmd8[6'd47-s_cmd_bit_cnt];
            end else begin
              s_spisd_mosi <= 1'b1;
              if (s_resp_en) begin
                s_spisd_cs    <= 1'b1;
                s_cmd_bit_cnt <= '0;
              end
            end
          end
          SendCmd55: begin
            if (s_cmd_bit_cnt <= 6'd47) begin
              s_cmd_bit_cnt <= s_cmd_bit_cnt + 6'd1;
              s_spisd_cs    <= 1'b0;
              s_spisd_mosi  <= Cmd55[6'd47-s_cmd_bit_cnt];
            end else begin
              s_spisd_mosi <= 1'b1;
              if (s_resp_en) begin
                s_spisd_cs    <= 1'b1;
                s_cmd_bit_cnt <= '0;
              end
            end
          end
          SendAcmd41: begin
            if (s_cmd_bit_cnt <= 6'd47) begin
              s_cmd_bit_cnt <= s_cmd_bit_cnt + 6'd1;
              s_spisd_cs    <= 1'b0;
              s_spisd_mosi  <= Acmd41[6'd47-s_cmd_bit_cnt];
            end else begin
              s_spisd_mosi <= 1'b1;
              if (s_resp_en) begin
                s_spisd_cs    <= 1'b1;
                s_cmd_bit_cnt <= '0;
              end
            end
          end
          InitDone: begin
            s_init_done  <= 1'b1;
            s_spisd_cs   <= 1'b1;
            s_spisd_mosi <= 1'b1;
          end
          default: begin
            s_spisd_cs   <= 1'b1;
            s_spisd_mosi <= 1'b1;
          end
        endcase
      end
    end
  end

endmodule
