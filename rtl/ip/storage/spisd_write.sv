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
// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
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

  localparam logic [7:0] HeadByte = 8'hFE;

  logic        s_wr_en_d0;
  logic        s_wr_en_d1;
  logic        s_resp_en;
  // logic [ 7:0] s_resp_data;
  logic        s_resp_flag;
  logic [ 5:0] s_resp_bit_cnt;
  logic [ 3:0] s_wr_ctrl_cnt;
  logic [47:0] s_cmd_wr;
  logic [ 5:0] s_cmd_bit_cnt;
  logic [ 3:0] s_bit_cnt;
  logic [ 8:0] s_data_cnt;
  logic [ 7:0] s_wr_data_t;
  logic        s_detect_done_flag;
  logic [ 7:0] s_detect_data;
  logic        s_pos_wr_en;

  logic        s_wr_data_req;
  logic        s_wr_busy;
  logic        s_spisd_cs;
  logic        s_spisd_mosi;

  assign wr_data_req_o = s_wr_data_req;
  assign wr_busy_o     = s_wr_busy;
  assign spisd_cs_o    = s_spisd_cs;
  assign spisd_mosi_o  = s_spisd_mosi;

  assign s_pos_wr_en   = (~s_wr_en_d1) & s_wr_en_d0;
  // The following edge-qualified SPI transmit/control processes retain ordered
  // reset/update priority; splitting them would risk changing byte timing.
  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_wr_en_d0 <= 1'b0;
      s_wr_en_d1 <= 1'b0;
    end else begin
      if (fir_clk_edge_i) begin
        s_wr_en_d0 <= wr_req_i;
        s_wr_en_d1 <= s_wr_en_d0;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_resp_en      <= '0;
      // s_resp_data    <= '0;
      s_resp_flag    <= '0;
      s_resp_bit_cnt <= '0;
    end else begin
      if (sec_clk_edge_i) begin
        if (spisd_miso_i == 1'b0 && s_resp_flag == 1'b0) begin
          s_resp_flag    <= 1'b1;
          // s_resp_data    <= {s_resp_data[6:0], spisd_miso_i};
          s_resp_bit_cnt <= s_resp_bit_cnt + 6'd1;
          s_resp_en      <= 1'b0;
        end else if (s_resp_flag) begin
          // s_resp_data    <= {s_resp_data[6:0], spisd_miso_i};
          s_resp_bit_cnt <= s_resp_bit_cnt + 6'd1;
          if (s_resp_bit_cnt == 6'd7) begin
            s_resp_flag    <= 1'b0;
            s_resp_bit_cnt <= '0;
            s_resp_en      <= 1'b1;
          end
        end else s_resp_en <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) s_detect_data <= '0;
    else begin
      if (fir_clk_edge_i) begin
        if (s_detect_done_flag) s_detect_data <= {s_detect_data[6:0], spisd_miso_i};
        else s_detect_data <= '0;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_spisd_cs         <= 1'b1;
      s_spisd_mosi       <= 1'b1;
      s_wr_ctrl_cnt      <= '0;
      s_wr_busy          <= '0;
      s_cmd_wr           <= '0;
      s_cmd_bit_cnt      <= '0;
      s_bit_cnt          <= '0;
      s_wr_data_t        <= '0;
      s_data_cnt         <= '0;
      s_wr_data_req      <= '0;
      s_detect_done_flag <= '0;
    end else begin
      if (fir_clk_edge_i) begin
        s_wr_data_req <= 1'b0;
        case (s_wr_ctrl_cnt)
          4'd0: begin
            s_wr_busy    <= 1'b0;
            s_spisd_cs   <= 1'b1;
            s_spisd_mosi <= 1'b1;
            if (s_pos_wr_en) begin
              s_cmd_wr      <= {8'h58, wr_sec_addr_i, 8'hFF};
              s_wr_ctrl_cnt <= s_wr_ctrl_cnt + 4'd1;
              s_wr_busy     <= 1'b1;
            end
          end
          4'd1: begin
            if (s_cmd_bit_cnt <= 6'd47) begin
              s_cmd_bit_cnt <= s_cmd_bit_cnt + 6'd1;
              s_spisd_cs    <= 1'b0;
              s_spisd_mosi  <= s_cmd_wr[6'd47-s_cmd_bit_cnt];
            end else begin
              s_spisd_mosi <= 1'b1;
              if (s_resp_en) begin
                s_wr_ctrl_cnt <= s_wr_ctrl_cnt + 4'd1;
                s_cmd_bit_cnt <= '0;
                s_bit_cnt     <= 4'd1;
              end
            end
          end
          4'd2: begin
            s_bit_cnt <= s_bit_cnt + 4'd1;

            if (s_bit_cnt >= 4'd8 && s_bit_cnt <= 4'd15) begin
              s_spisd_mosi <= HeadByte[4'd15-s_bit_cnt];
              if (s_bit_cnt == 4'd14) s_wr_data_req <= 1'b1;
              else if (s_bit_cnt == 4'd15) s_wr_ctrl_cnt <= s_wr_ctrl_cnt + 4'd1;
            end
          end
          4'd3: begin
            s_bit_cnt <= s_bit_cnt + 4'd1;
            if (s_bit_cnt == 4'd0) begin
              s_spisd_mosi <= wr_data_i[4'd7-s_bit_cnt];
              s_wr_data_t  <= wr_data_i;
            end else s_spisd_mosi <= s_wr_data_t[4'd7-s_bit_cnt];

            if ((s_bit_cnt == 4'd6) && (s_data_cnt <= 9'd511)) s_wr_data_req <= 1'b1;
            if (s_bit_cnt == 4'd7) begin
              s_bit_cnt  <= '0;
              s_data_cnt <= s_data_cnt + 1'b1;
              if (s_data_cnt == 9'd511) begin
                s_data_cnt    <= '0;
                s_wr_ctrl_cnt <= s_wr_ctrl_cnt + 4'd1;
              end
            end
          end
          4'd4: begin
            s_bit_cnt    <= s_bit_cnt + 4'd1;
            s_spisd_mosi <= 1'b1;
            if (s_bit_cnt == 4'd15) s_wr_ctrl_cnt <= s_wr_ctrl_cnt + 4'd1;
          end
          4'd5: begin
            if (s_resp_en) s_wr_ctrl_cnt <= s_wr_ctrl_cnt + 4'd1;
          end
          4'd6: begin
            s_detect_done_flag <= 1'b1;
            if (s_detect_data == 8'hFF) begin
              s_wr_ctrl_cnt      <= s_wr_ctrl_cnt + 4'd1;
              s_detect_done_flag <= 1'b0;
            end
          end
          default: begin
            s_spisd_cs    <= 1'b1;
            s_wr_ctrl_cnt <= s_wr_ctrl_cnt + 4'd1;
          end
        endcase
      end
    end
  end
endmodule
