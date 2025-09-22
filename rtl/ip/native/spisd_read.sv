// Copyright 2019 EmbedFire http://www.embedfire.com
// https://github.com/Embedfire-altera <embedfire@embedfire.com>
//
// The first version of this code was derived from EmbedFire sd_read.v. The
// original code is open source on Gitee, but it doesn't specify an open-source
// license. I'm re-releasing it here under the most compatible license(PSL License).
// If anyone knows what the original license is, please contact <miaoyuchi@ict.ac.cn>.
//
// -- Adaptable modifications are redistributed under compatible License --
//
// Copyright (c) 2023-2025 Miao Yuchi <miaoyuchi@ict.ac.cn>
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

  logic        r_rd_en_d0;
  logic        r_rd_en_d1;
  logic        r_resp_en;
  // logic [ 7:0] r_resp_data;
  logic        r_resp_flag;
  logic [ 5:0] r_resp_bit_cnt;
  logic        r_rx_en_t;
  logic [ 7:0] r_rx_data_t;
  logic        r_rx_flag;
  logic [ 3:0] r_rx_bit_cnt;
  logic [ 9:0] r_rx_data_cnt;
  logic        r_rx_finish_en;
  logic [ 3:0] r_rd_ctrl_cnt;
  logic [47:0] r_cmd_rd;
  logic [ 5:0] r_cmd_bit_cnt;
  logic        r_rd_data_flag;
  logic        s_pos_rd_en;

  logic        r_rd_data_vld;
  logic [ 7:0] r_rd_data;
  logic        r_rd_busy;
  logic        r_spisd_cs;
  logic        r_spisd_mosi;

  assign rd_data_vld_o = r_rd_data_vld;
  assign rd_data_o     = r_rd_data;
  assign rd_busy_o     = r_rd_busy;
  assign spisd_cs_o    = r_spisd_cs;
  assign spisd_mosi_o  = r_spisd_mosi;

  assign s_pos_rd_en   = (~r_rd_en_d1) & r_rd_en_d0;
  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      r_rd_en_d0 <= 1'b0;
      r_rd_en_d1 <= 1'b0;
    end else begin
      if (fir_clk_edge_i) begin
        r_rd_en_d0 <= rd_req_i;
        r_rd_en_d1 <= r_rd_en_d0;
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
    if (!rst_n_i) begin
      r_rx_en_t      <= '0;
      r_rx_data_t    <= '0;
      r_rx_flag      <= '0;
      r_rx_bit_cnt   <= '0;
      r_rx_data_cnt  <= '0;
      r_rx_finish_en <= '0;
    end else begin
      if (sec_clk_edge_i) begin
        r_rx_en_t      <= 1'b0;
        r_rx_finish_en <= 1'b0;
        if (r_rd_data_flag && spisd_miso_i == 1'b0 && r_rx_flag == 1'b0) r_rx_flag <= 1'b1;
        else if (r_rx_flag) begin
          r_rx_bit_cnt <= r_rx_bit_cnt + 4'd1;
          r_rx_data_t  <= {r_rx_data_t[7:0], spisd_miso_i};
          if (r_rx_bit_cnt == 4'd7) begin
            r_rx_bit_cnt  <= '0;
            r_rx_data_cnt <= r_rx_data_cnt + 1'b1;
            if (r_rx_data_cnt <= 10'd511) r_rx_en_t <= 1'b1;
            else if (r_rx_data_cnt == 10'd513) begin
              r_rx_flag      <= 1'b0;
              r_rx_finish_en <= 1'b1;
              r_rx_data_cnt  <= '0;
              r_rx_bit_cnt   <= '0;
            end
          end
        end else r_rx_data_t <= '0;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      r_rd_data_vld <= '0;
      r_rd_data     <= '0;
    end else begin
      if (fir_clk_edge_i) begin
        if (r_rx_en_t) begin
          r_rd_data_vld <= 1'b1;
          r_rd_data     <= r_rx_data_t;
        end else r_rd_data_vld <= 1'b0;
      end
    end
  end


  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      r_spisd_cs     <= 1'b1;
      r_spisd_mosi   <= 1'b1;
      r_rd_ctrl_cnt  <= '0;
      r_cmd_rd       <= '0;
      r_cmd_bit_cnt  <= '0;
      r_rd_busy      <= '0;
      r_rd_data_flag <= '0;
    end else begin
      if (fir_clk_edge_i) begin
        case (r_rd_ctrl_cnt)
          4'd0: begin
            r_rd_busy    <= 1'b0;
            r_spisd_cs   <= 1'b1;
            r_spisd_mosi <= 1'b1;
            if (s_pos_rd_en) begin
              r_cmd_rd      <= {8'h51, rd_sec_addr_i, 8'hFF};
              r_rd_ctrl_cnt <= r_rd_ctrl_cnt + 4'd1;
              r_rd_busy     <= 1'b1;
            end
          end
          4'd1: begin
            if (r_cmd_bit_cnt <= 6'd47) begin
              r_cmd_bit_cnt <= r_cmd_bit_cnt + 6'd1;
              r_spisd_cs    <= 1'b0;
              r_spisd_mosi  <= r_cmd_rd[6'd47-r_cmd_bit_cnt];
            end else begin
              r_spisd_mosi <= 1'b1;
              if (r_resp_en) begin
                r_rd_ctrl_cnt <= r_rd_ctrl_cnt + 4'd1;
                r_cmd_bit_cnt <= '0;
              end
            end
          end
          4'd2: begin
            r_rd_data_flag <= 1'b1;
            if (r_rx_finish_en) begin
              r_rd_ctrl_cnt  <= r_rd_ctrl_cnt + 4'd1;
              r_rd_data_flag <= 1'b0;
              r_spisd_cs     <= 1'b1;
            end
          end
          default: begin
            r_spisd_cs    <= 1'b1;
            r_rd_ctrl_cnt <= r_rd_ctrl_cnt + 4'd1;
          end
        endcase
      end
    end
  end

endmodule
