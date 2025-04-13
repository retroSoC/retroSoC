/*
 *  PicoSoC - A simple example SoC using PicoRV32
 *
 *  Copyright (C) 2017  Clifford Wolf <clifford@clifford.at>
 *  Copyright (C) 2025  Yuchi Miao <miaoyuchi@ict.ac.cn>
 *
 *  Permission to use, copy, modify, and/or distribute this software for any
 *  purpose with or without fee is hereby granted, provided that the above
 *  copyright notice and this permission notice appear in all copies.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 *  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 *  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 *  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 *  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 *  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 *  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 */

module simpleuart (
    input  logic        clk_i,
    input  logic        rst_n_i,
    output logic        ser_tx,
    input  logic        ser_rx,
    input  logic [ 3:0] reg_div_we,
    input  logic [31:0] reg_div_di,
    output logic [31:0] reg_div_do,
    input  logic        reg_dat_we,
    input  logic        reg_dat_re,
    input  logic [31:0] reg_dat_di,
    output logic [31:0] reg_dat_do,
    output logic        reg_dat_wait,
    output logic        irq_out
);
  logic [31:0] r_cfg_divider;
  logic [ 3:0] r_recv_state;
  logic [31:0] r_recv_divcnt;
  logic [ 7:0] r_recv_pattern;
  logic [ 7:0] r_recv_buf_data;
  logic        r_recv_buf_valid;
  logic [ 9:0] r_send_pattern;
  logic [ 3:0] r_send_bitcnt;
  logic [31:0] r_send_divcnt;
  logic        r_send_dummy;

  assign ser_tx       = r_send_pattern[0];
  assign reg_div_do   = r_cfg_divider;
  assign reg_dat_wait = reg_dat_we && (r_send_bitcnt || r_send_dummy);
  assign reg_dat_do   = r_recv_buf_valid ? r_recv_buf_data : '1;
  assign irq_out      = r_recv_buf_valid;

  always_ff @(posedge clk_i, negedge rst_n_i) begin
    if (!rst_n_i) begin
      r_cfg_divider <= 32'd1;
    end else begin
      if (reg_div_we[0]) r_cfg_divider[7:0] <= reg_div_di[7:0];
      if (reg_div_we[1]) r_cfg_divider[15:8] <= reg_div_di[15:8];
      if (reg_div_we[2]) r_cfg_divider[23:16] <= reg_div_di[23:16];
      if (reg_div_we[3]) r_cfg_divider[31:24] <= reg_div_di[31:24];
    end
  end

  always_ff @(posedge clk_i, negedge rst_n_i) begin
    if (!rst_n_i) begin
      r_recv_state     <= '0;
      r_recv_divcnt    <= '0;
      r_recv_pattern   <= '0;
      r_recv_buf_data  <= '0;
      r_recv_buf_valid <= '0;
    end else begin
      r_recv_divcnt <= r_recv_divcnt + 1'b1;
      if (reg_dat_re) r_recv_buf_valid <= '0;

      unique case (r_recv_state)
        4'd0: begin
          if (!ser_rx) r_recv_state <= 1'b1;
          r_recv_divcnt <= '0;
        end
        4'd1: begin
          if (2 * r_recv_divcnt > r_cfg_divider) begin
            r_recv_state  <= 4'd2;
            r_recv_divcnt <= '0;
          end
        end
        4'd10: begin
          if (r_recv_divcnt > r_cfg_divider) begin
            r_recv_buf_data  <= r_recv_pattern;
            r_recv_buf_valid <= 1'b1;
            r_recv_state     <= '0;
          end
        end
        default: begin
          if (r_recv_divcnt > r_cfg_divider) begin
            r_recv_pattern <= {ser_rx, r_recv_pattern[7:1]};
            r_recv_state   <= r_recv_state + 1'b1;
            r_recv_divcnt  <= '0;
          end
        end
      endcase
    end
  end

  always_ff @(posedge clk_i, negedge rst_n_i) begin
    if (!rst_n_i) begin
      r_send_pattern <= '1;
      r_send_bitcnt  <= '0;
      r_send_divcnt  <= '0;
      r_send_dummy   <= 1'b1;
    end else begin
      if (reg_div_we) r_send_dummy <= 1'b1;
      r_send_divcnt <= r_send_divcnt + 1'b1;

      if (r_send_dummy && !r_send_bitcnt) begin
        r_send_pattern <= '1;
        r_send_bitcnt  <= 4'd15;
        r_send_divcnt  <= '0;
        r_send_dummy   <= '0;
      end else if (reg_dat_we && !r_send_bitcnt) begin
        r_send_pattern <= {1'b1, reg_dat_di[7:0], 1'b0};
        r_send_bitcnt  <= 4'd10;
        r_send_divcnt  <= '0;
      end else if (r_send_divcnt > r_cfg_divider && r_send_bitcnt) begin
        r_send_pattern <= {1'b1, r_send_pattern[9:1]};
        r_send_bitcnt  <= r_send_bitcnt - 1'b1;
        r_send_divcnt  <= '0;
      end
    end
  end
endmodule
