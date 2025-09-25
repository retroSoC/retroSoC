// Copyright 2019 EmbedFire http://www.embedfire.com
// https://github.com/Embedfire-altera <embedfire@embedfire.com>
//
// The first version of this code was derived from EmbedFire sd_write.v. The
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

module spisd_write (
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        fir_clk_edge_i,
    input  logic        sec_clk_edge_i,
    input  logic        wr_req_i,
    input  logic [31:0] wr_sec_addr_i,
    output logic        wr_data_req_o,
    input  logic [ 7:0] wr_data_i,
    output logic        wr_busy_o,
    output logic        spisd_cs_o,
    output logic        spisd_mosi_o,
    input  logic        spisd_miso_i
);

  localparam HEAD_BYTE = 8'hFE;

  logic        r_wr_en_d0;
  logic        r_wr_en_d1;
  logic        r_resp_en;
  // logic [ 7:0] r_resp_data;
  logic        r_resp_flag;
  logic [ 5:0] r_resp_bit_cnt;
  logic [ 3:0] r_wr_ctrl_cnt;
  logic [47:0] r_cmd_wr;
  logic [ 5:0] r_cmd_bit_cnt;
  logic [ 3:0] r_bit_cnt;
  logic [ 8:0] r_data_cnt;
  logic [ 7:0] r_wr_data_t;
  logic        r_detect_done_flag;
  logic [ 7:0] r_detect_data;
  logic        s_pos_wr_en;

  logic        r_wr_data_req;
  logic        r_wr_busy;
  logic        r_spisd_cs;
  logic        r_spisd_mosi;

  assign wr_data_req_o = r_wr_data_req;
  assign wr_busy_o     = r_wr_busy;
  assign spisd_cs_o    = r_spisd_cs;
  assign spisd_mosi_o  = r_spisd_mosi;

  assign s_pos_wr_en   = (~r_wr_en_d1) & r_wr_en_d0;
  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      r_wr_en_d0 <= 1'b0;
      r_wr_en_d1 <= 1'b0;
    end else begin
      if (fir_clk_edge_i) begin
        r_wr_en_d0 <= wr_req_i;
        r_wr_en_d1 <= r_wr_en_d0;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      r_resp_en      <= '0;
      // r_resp_data    <= '0;
      r_resp_flag    <= '0;
      r_resp_bit_cnt <= '0;
    end else begin
      if (sec_clk_edge_i) begin
        if (spisd_miso_i == 1'b0 && r_resp_flag == 1'b0) begin
          r_resp_flag    <= 1'b1;
          // r_resp_data    <= {r_resp_data[6:0], spisd_miso_i};
          r_resp_bit_cnt <= r_resp_bit_cnt + 6'd1;
          r_resp_en      <= 1'b0;
        end else if (r_resp_flag) begin
          // r_resp_data    <= {r_resp_data[6:0], spisd_miso_i};
          r_resp_bit_cnt <= r_resp_bit_cnt + 6'd1;
          if (r_resp_bit_cnt == 6'd7) begin
            r_resp_flag    <= 1'b0;
            r_resp_bit_cnt <= '0;
            r_resp_en      <= 1'b1;
          end
        end else r_resp_en <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) r_detect_data <= '0;
    else begin
      if (fir_clk_edge_i) begin
        if (r_detect_done_flag) r_detect_data <= {r_detect_data[6:0], spisd_miso_i};
        else r_detect_data <= '0;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      r_spisd_cs         <= 1'b1;
      r_spisd_mosi       <= 1'b1;
      r_wr_ctrl_cnt      <= '0;
      r_wr_busy          <= '0;
      r_cmd_wr           <= '0;
      r_cmd_bit_cnt      <= '0;
      r_bit_cnt          <= '0;
      r_wr_data_t        <= '0;
      r_data_cnt         <= '0;
      r_wr_data_req      <= '0;
      r_detect_done_flag <= '0;
    end else begin
      if (fir_clk_edge_i) begin
        r_wr_data_req <= 1'b0;
        case (r_wr_ctrl_cnt)
          4'd0: begin
            r_wr_busy    <= 1'b0;
            r_spisd_cs   <= 1'b1;
            r_spisd_mosi <= 1'b1;
            if (s_pos_wr_en) begin
              r_cmd_wr      <= {8'h58, wr_sec_addr_i, 8'hFF};
              r_wr_ctrl_cnt <= r_wr_ctrl_cnt + 4'd1;
              r_wr_busy     <= 1'b1;
            end
          end
          4'd1: begin
            if (r_cmd_bit_cnt <= 6'd47) begin
              r_cmd_bit_cnt <= r_cmd_bit_cnt + 6'd1;
              r_spisd_cs    <= 1'b0;
              r_spisd_mosi  <= r_cmd_wr[6'd47-r_cmd_bit_cnt];
            end else begin
              r_spisd_mosi <= 1'b1;
              if (r_resp_en) begin
                r_wr_ctrl_cnt <= r_wr_ctrl_cnt + 4'd1;
                r_cmd_bit_cnt <= '0;
                r_bit_cnt     <= 4'd1;
              end
            end
          end
          4'd2: begin
            r_bit_cnt <= r_bit_cnt + 4'd1;

            if (r_bit_cnt >= 4'd8 && r_bit_cnt <= 4'd15) begin
              r_spisd_mosi <= HEAD_BYTE[4'd15-r_bit_cnt];
              if (r_bit_cnt == 4'd14) r_wr_data_req <= 1'b1;
              else if (r_bit_cnt == 4'd15) r_wr_ctrl_cnt <= r_wr_ctrl_cnt + 4'd1;
            end
          end
          4'd3: begin
            r_bit_cnt <= r_bit_cnt + 4'd1;
            if (r_bit_cnt == 4'd0) begin
              r_spisd_mosi <= wr_data_i[4'd7-r_bit_cnt];
              r_wr_data_t  <= wr_data_i;
            end else r_spisd_mosi <= r_wr_data_t[4'd7-r_bit_cnt];

            if ((r_bit_cnt == 4'd6) && (r_data_cnt <= 9'd511)) r_wr_data_req <= 1'b1;
            if (r_bit_cnt == 4'd7) begin
              r_bit_cnt  <= '0;
              r_data_cnt <= r_data_cnt + 1'b1;
              if (r_data_cnt == 9'd511) begin
                r_data_cnt    <= '0;
                r_wr_ctrl_cnt <= r_wr_ctrl_cnt + 4'd1;
              end
            end
          end
          4'd4: begin
            r_bit_cnt    <= r_bit_cnt + 4'd1;
            r_spisd_mosi <= 1'b1;
            if (r_bit_cnt == 4'd15) r_wr_ctrl_cnt <= r_wr_ctrl_cnt + 4'd1;
          end
          4'd5: begin
            if (r_resp_en) r_wr_ctrl_cnt <= r_wr_ctrl_cnt + 4'd1;
          end
          4'd6: begin
            r_detect_done_flag <= 1'b1;
            if (r_detect_data == 8'hFF) begin
              r_wr_ctrl_cnt      <= r_wr_ctrl_cnt + 4'd1;
              r_detect_done_flag <= 1'b0;
            end
          end
          default: begin
            r_spisd_cs    <= 1'b1;
            r_wr_ctrl_cnt <= r_wr_ctrl_cnt + 4'd1;
          end
        endcase
      end
    end
  end
endmodule
