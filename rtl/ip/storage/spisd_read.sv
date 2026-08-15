// Copyright 2019 EmbedFire http://www.embedfire.com
// https://github.com/Embedfire-altera <embedfire@embedfire.com>
//
// The first version of this code was derived from EmbedFire sd_read.v. The
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

module spisd_read (
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        fir_clk_edge_i,
    input  logic        sec_clk_edge_i,
    input  logic        rd_req_i,
    input  logic [31:0] rd_sec_addr_i,
    output logic        rd_data_vld_o,
    output logic [ 7:0] rd_data_o,
    output logic        rd_busy_o,
    output logic        spisd_cs_o,
    output logic        spisd_mosi_o,
    input  logic        spisd_miso_i
);

  logic        s_rd_en_d0;
  logic        s_rd_en_d1;
  logic        s_resp_en;
  // logic [ 7:0] s_resp_data;
  logic        s_resp_flag;
  logic [ 5:0] s_resp_bit_cnt;
  logic        s_rx_en_t;
  logic [ 7:0] s_rx_data_t;
  logic        s_rx_flag;
  logic [ 3:0] s_rx_bit_cnt;
  logic [ 9:0] s_rx_data_cnt;
  logic        s_rx_finish_en;
  logic [ 3:0] s_rd_ctrl_cnt;
  logic [47:0] s_cmd_rd;
  logic [ 5:0] s_cmd_bit_cnt;
  logic        s_rd_data_flag;
  logic        s_pos_rd_en;

  logic        s_rd_data_vld;
  logic [ 7:0] s_rd_data;
  logic        s_rd_busy;
  logic        s_spisd_cs;
  logic        s_spisd_mosi;

  assign rd_data_vld_o = s_rd_data_vld;
  assign rd_data_o     = s_rd_data;
  assign rd_busy_o     = s_rd_busy;
  assign spisd_cs_o    = s_spisd_cs;
  assign spisd_mosi_o  = s_spisd_mosi;

  assign s_pos_rd_en   = (~s_rd_en_d1) & s_rd_en_d0;
  // The following edge-qualified SPI receive/control processes retain ordered
  // reset/update priority; splitting them would risk changing byte timing.
  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_rd_en_d0 <= 1'b0;
      s_rd_en_d1 <= 1'b0;
    end else begin
      if (fir_clk_edge_i) begin
        s_rd_en_d0 <= rd_req_i;
        s_rd_en_d1 <= s_rd_en_d0;
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
    if (!rst_n_i) begin
      s_rx_en_t      <= '0;
      s_rx_data_t    <= '0;
      s_rx_flag      <= '0;
      s_rx_bit_cnt   <= '0;
      s_rx_data_cnt  <= '0;
      s_rx_finish_en <= '0;
    end else begin
      if (sec_clk_edge_i) begin
        s_rx_en_t      <= 1'b0;
        s_rx_finish_en <= 1'b0;
        if (s_rd_data_flag && spisd_miso_i == 1'b0 && s_rx_flag == 1'b0) s_rx_flag <= 1'b1;
        else if (s_rx_flag) begin
          s_rx_bit_cnt <= s_rx_bit_cnt + 4'd1;
          s_rx_data_t  <= {s_rx_data_t[7:0], spisd_miso_i};
          if (s_rx_bit_cnt == 4'd7) begin
            s_rx_bit_cnt  <= '0;
            s_rx_data_cnt <= s_rx_data_cnt + 1'b1;
            if (s_rx_data_cnt <= 10'd511) s_rx_en_t <= 1'b1;
            else if (s_rx_data_cnt == 10'd513) begin
              s_rx_flag      <= 1'b0;
              s_rx_finish_en <= 1'b1;
              s_rx_data_cnt  <= '0;
              s_rx_bit_cnt   <= '0;
            end
          end
        end else s_rx_data_t <= '0;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_rd_data_vld <= '0;
      s_rd_data     <= '0;
    end else begin
      if (fir_clk_edge_i) begin
        if (s_rx_en_t) begin
          s_rd_data_vld <= 1'b1;
          s_rd_data     <= s_rx_data_t;
        end else s_rd_data_vld <= 1'b0;
      end
    end
  end


  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_spisd_cs     <= 1'b1;
      s_spisd_mosi   <= 1'b1;
      s_rd_ctrl_cnt  <= '0;
      s_cmd_rd       <= '0;
      s_cmd_bit_cnt  <= '0;
      s_rd_busy      <= '0;
      s_rd_data_flag <= '0;
    end else begin
      if (fir_clk_edge_i) begin
        case (s_rd_ctrl_cnt)
          4'd0: begin
            s_rd_busy    <= 1'b0;
            s_spisd_cs   <= 1'b1;
            s_spisd_mosi <= 1'b1;
            if (s_pos_rd_en) begin
              s_cmd_rd      <= {8'h51, rd_sec_addr_i, 8'hFF};
              s_rd_ctrl_cnt <= s_rd_ctrl_cnt + 4'd1;
              s_rd_busy     <= 1'b1;
            end
          end
          4'd1: begin
            if (s_cmd_bit_cnt <= 6'd47) begin
              s_cmd_bit_cnt <= s_cmd_bit_cnt + 6'd1;
              s_spisd_cs    <= 1'b0;
              s_spisd_mosi  <= s_cmd_rd[6'd47-s_cmd_bit_cnt];
            end else begin
              s_spisd_mosi <= 1'b1;
              if (s_resp_en) begin
                s_rd_ctrl_cnt <= s_rd_ctrl_cnt + 4'd1;
                s_cmd_bit_cnt <= '0;
              end
            end
          end
          4'd2: begin
            s_rd_data_flag <= 1'b1;
            if (s_rx_finish_en) begin
              s_rd_ctrl_cnt  <= s_rd_ctrl_cnt + 4'd1;
              s_rd_data_flag <= 1'b0;
              s_spisd_cs     <= 1'b1;
            end
          end
          default: begin
            s_spisd_cs    <= 1'b1;
            s_rd_ctrl_cnt <= s_rd_ctrl_cnt + 4'd1;
          end
        endcase
      end
    end
  end

endmodule
