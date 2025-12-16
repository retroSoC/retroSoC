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
// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
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

  localparam CMD0 = {8'h40, 8'h00, 8'h00, 8'h00, 8'h00, 8'h95};
  localparam CMD8 = {8'h48, 8'h00, 8'h00, 8'h01, 8'hAA, 8'h87};
  localparam CMD55 = {8'h77, 8'h00, 8'h00, 8'h00, 8'h00, 8'hFF};
  localparam ACMD41 = {8'h69, 8'h40, 8'h00, 8'h00, 8'h00, 8'hFF};
  localparam DIV_FREQ = 200;
  localparam OVER_TIME_NUM = 25000;

  localparam FSM_IDLE = 3'd0;
  localparam FSM_SEND_CMD0 = 3'd1;
  localparam FSM_WAIT_CMD0 = 3'd2;
  localparam FSM_SEND_CMD8 = 3'd3;
  localparam FSM_SEND_CMD55 = 3'd4;
  localparam FSM_SEND_ACMD41 = 3'd5;
  localparam FSM_INIT_DONE = 3'd6;

  logic s_div_clk_d, s_div_clk_q;
  logic [7:0] s_div_cnt_d, s_div_cnt_q;  // 512 div
  logic [6:0] s_boot_cnt_d, s_boot_cnt_q;  // count 128
  logic [2:0] s_fsm_d, s_fsm_q;
  logic s_fir_clk_edge, s_sec_clk_edge;
  // resp 
  logic        r_resp_en;
  logic [47:0] r_resp_data;
  logic        r_resp_flag;
  logic [ 5:0] r_resp_bit_cnt;
  // utils
  logic [ 5:0] r_cmd_bit_cnt;
  logic [15:0] r_overflow_cnt;
  logic        r_overflow_en;
  // spi if
  logic        r_init_done;
  logic r_spisd_cs, r_spisd_mosi;

  assign init_done_o    = r_init_done;
  assign spisd_clk_o    = s_div_clk_q;
  assign spisd_cs_o     = r_spisd_cs;
  assign spisd_mosi_o   = r_spisd_mosi;
  // fir: fall sec: pos
  assign s_fir_clk_edge = s_div_clk_q && (s_div_cnt_q == '0);
  assign s_sec_clk_edge = (~s_div_clk_q) && (s_div_cnt_q == '0);

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
  dffrh #(8) u_div_cnt_dffrh (
      clk_i,
      rst_n_i,
      s_div_cnt_d,
      s_div_cnt_q
  );

  dffrh #(1) u_div_clk_dffrh (
      clk_i,
      rst_n_i,
      s_div_clk_d,
      s_div_clk_q
  );

  always_comb begin
    s_boot_cnt_d = s_boot_cnt_q;
    if (s_fir_clk_edge) begin
      if (s_fsm_q == FSM_IDLE) begin
        if (s_boot_cnt_q != '0) s_boot_cnt_d = s_boot_cnt_q - 1'b1;
      end else begin
        s_boot_cnt_d = '1;
      end
    end
  end
  dfferh #(7) u_boot_cnt_dfferh (
      clk_i,
      rst_n_i,
      s_fir_clk_edge,
      s_boot_cnt_d,
      s_boot_cnt_q
  );


  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      r_resp_en      <= '0;
      r_resp_data    <= '0;
      r_resp_flag    <= '0;
      r_resp_bit_cnt <= '0;
    end else begin
      if (s_sec_clk_edge) begin
        if (spisd_miso_i == 1'b0 && r_resp_flag == 1'b0) begin
          r_resp_flag    <= 1'b1;
          r_resp_data    <= {r_resp_data[46:0], spisd_miso_i};
          r_resp_bit_cnt <= r_resp_bit_cnt + 6'd1;
          r_resp_en      <= 1'b0;
        end else if (r_resp_flag) begin
          r_resp_data    <= {r_resp_data[46:0], spisd_miso_i};
          r_resp_bit_cnt <= r_resp_bit_cnt + 6'd1;
          if (r_resp_bit_cnt == 6'd47) begin
            r_resp_flag    <= 1'b0;
            r_resp_bit_cnt <= '0;
            r_resp_en      <= 1'b1;
          end
        end else r_resp_en <= 1'b0;
      end
    end
  end

  always_comb begin
    s_fsm_d = s_fsm_q;
    case (s_fsm_q)
      FSM_IDLE: begin
        if (s_boot_cnt_q == '0) s_fsm_d = FSM_SEND_CMD0;
      end
      FSM_SEND_CMD0: begin
        if (r_cmd_bit_cnt == 6'd47) s_fsm_d = FSM_WAIT_CMD0;
      end
      FSM_WAIT_CMD0: begin
        if (r_resp_en) begin
          if (r_resp_data[47:40] == 8'h01) s_fsm_d = FSM_SEND_CMD8;
          else s_fsm_d = FSM_IDLE;
        end else if (r_overflow_en) s_fsm_d = FSM_IDLE;
      end

      FSM_SEND_CMD8: begin
        if (r_resp_en) begin
          if (r_resp_data[19:16] == 4'b0001) s_fsm_d = FSM_SEND_CMD55;
          else s_fsm_d = FSM_IDLE;
        end
      end
      FSM_SEND_CMD55: begin
        if (r_resp_en) begin
          if (r_resp_data[47:40] == 8'h01) s_fsm_d = FSM_SEND_ACMD41;
        end
      end
      FSM_SEND_ACMD41: begin
        if (r_resp_en) begin
          if (r_resp_data[47:40] == 8'h00) s_fsm_d = FSM_INIT_DONE;
          else s_fsm_d = FSM_SEND_CMD55;
        end
      end
      FSM_INIT_DONE: s_fsm_d = FSM_INIT_DONE;
      default:       s_fsm_d = FSM_IDLE;
    endcase
  end
  dffer #(3) u_fsm_dffer (
      clk_i,
      rst_n_i,
      s_fir_clk_edge,
      s_fsm_d,
      s_fsm_q
  );

  always @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      r_init_done    <= '0;
      r_spisd_cs     <= '1;
      r_spisd_mosi   <= '1;

      r_cmd_bit_cnt  <= '0;
      r_overflow_cnt <= '0;
      r_overflow_en  <= '0;
    end else begin
      if (s_fir_clk_edge) begin
        r_overflow_en <= 1'b0;
        case (s_fsm_q)
          FSM_IDLE: begin
            r_spisd_cs   <= 1'b1;
            r_spisd_mosi <= 1'b1;
          end
          FSM_SEND_CMD0: begin
            r_spisd_cs    <= 1'b0;
            r_spisd_mosi  <= CMD0[6'd47-r_cmd_bit_cnt];
            r_cmd_bit_cnt <= r_cmd_bit_cnt + 6'd1;
            if (r_cmd_bit_cnt == 6'd47) r_cmd_bit_cnt <= '0;
          end
          FSM_WAIT_CMD0: begin
            r_spisd_mosi <= 1'b1;
            if (r_resp_en) r_spisd_cs <= 1'b1;

            r_overflow_cnt <= r_overflow_cnt + 1'b1;
            if (r_overflow_cnt == OVER_TIME_NUM) r_overflow_en <= 1'b1;
            if (r_overflow_en) r_overflow_cnt <= '0;
          end
          FSM_SEND_CMD8: begin
            if (r_cmd_bit_cnt <= 6'd47) begin
              r_cmd_bit_cnt <= r_cmd_bit_cnt + 6'd1;
              r_spisd_cs    <= 1'b0;
              r_spisd_mosi  <= CMD8[6'd47-r_cmd_bit_cnt];
            end else begin
              r_spisd_mosi <= 1'b1;
              if (r_resp_en) begin
                r_spisd_cs    <= 1'b1;
                r_cmd_bit_cnt <= '0;
              end
            end
          end
          FSM_SEND_CMD55: begin
            if (r_cmd_bit_cnt <= 6'd47) begin
              r_cmd_bit_cnt <= r_cmd_bit_cnt + 6'd1;
              r_spisd_cs    <= 1'b0;
              r_spisd_mosi  <= CMD55[6'd47-r_cmd_bit_cnt];
            end else begin
              r_spisd_mosi <= 1'b1;
              if (r_resp_en) begin
                r_spisd_cs    <= 1'b1;
                r_cmd_bit_cnt <= '0;
              end
            end
          end
          FSM_SEND_ACMD41: begin
            if (r_cmd_bit_cnt <= 6'd47) begin
              r_cmd_bit_cnt <= r_cmd_bit_cnt + 6'd1;
              r_spisd_cs    <= 1'b0;
              r_spisd_mosi  <= ACMD41[6'd47-r_cmd_bit_cnt];
            end else begin
              r_spisd_mosi <= 1'b1;
              if (r_resp_en) begin
                r_spisd_cs    <= 1'b1;
                r_cmd_bit_cnt <= '0;
              end
            end
          end
          FSM_INIT_DONE: begin
            r_init_done  <= 1'b1;
            r_spisd_cs   <= 1'b1;
            r_spisd_mosi <= 1'b1;
          end
          default: begin
            r_spisd_cs   <= 1'b1;
            r_spisd_mosi <= 1'b1;
          end
        endcase
      end
    end
  end

endmodule
