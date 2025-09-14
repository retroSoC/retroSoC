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

`ifndef SIMP_UART_DEF_SV
`define SIMP_UART_DEF_SV

// verilog_format: off
`define SIMP_UART_DIV 8'h00
`define SIMP_UART_DAT 8'h04
// verilog_format: on

`endif

interface simp_uart_if ();
  logic tx;
  logic rx;
  logic irq;

  modport dut(output tx, input rx, output irq);
endinterface

module simple_uart (
    // verilog_format: off
    input logic      clk_i,
    input logic      rst_n_i,
    nmi_if.slave     nmi,
    simp_uart_if.dut uart
    // verilog_format: on
);

  logic s_nmi_wr_hdshk, s_nmi_rd_hdshk;
  logic s_nmi_ready_d, s_nmi_ready_q;
  logic s_nmi_rdata_en;
  logic [31:0] s_nmi_rdata_d, s_nmi_rdata_q;

  logic s_uart_div_en;
  logic [31:0] s_uart_div_d, s_uart_div_q;
  logic        s_send_dat_wait;
  logic        s_uart_dat_en;
  // register
  logic [ 3:0] r_recv_state;
  logic [31:0] r_recv_divcnt;
  logic [ 7:0] r_recv_pattern;
  logic [ 7:0] r_recv_buf_data;
  logic        r_recv_buf_valid;
  logic [ 9:0] r_send_pattern;
  logic [ 3:0] r_send_bitcnt;
  logic [31:0] r_send_divcnt;
  logic        r_send_dummy;


  assign s_nmi_wr_hdshk = nmi.valid && (~s_nmi_ready_q) && (|nmi.wstrb);
  assign s_nmi_rd_hdshk = nmi.valid && (~s_nmi_ready_q) && (~(|nmi.wstrb));
  assign nmi.ready      = s_nmi_ready_q;
  assign nmi.rdata      = s_nmi_rdata_q;

  assign uart.tx        = r_send_pattern[0];
  assign uart.irq       = r_recv_buf_valid;

  assign s_uart_div_en  = s_nmi_wr_hdshk && nmi.addr[7:0] == `SIMP_UART_DIV;
  always_comb begin
    s_uart_div_d = s_uart_div_q;
    if (nmi.wstrb[0]) s_uart_div_d[7:0] = nmi.wdata[7:0];
    if (nmi.wstrb[1]) s_uart_div_d[15:8] = nmi.wdata[15:8];
    if (nmi.wstrb[2]) s_uart_div_d[23:16] = nmi.wdata[23:16];
    if (nmi.wstrb[3]) s_uart_div_d[31:24] = nmi.wdata[31:24];
  end
  dfferh #(32) u_uart_div_dfferh (
      clk_i,
      rst_n_i,
      s_uart_div_en,
      s_uart_div_d,
      s_uart_div_q
  );

  assign s_uart_dat_en   = s_nmi_wr_hdshk && nmi.addr[7:0] == `SIMP_UART_DAT;
  assign s_send_dat_wait = s_uart_dat_en && nmi.wstrb[0] && (r_send_bitcnt || r_send_dummy);
  assign s_nmi_ready_d   = nmi.valid && (~s_nmi_ready_q) && (~s_send_dat_wait);
  dffr #(1) u_nmi_ready_dffr (
      clk_i,
      rst_n_i,
      s_nmi_ready_d,
      s_nmi_ready_q
  );

  assign s_nmi_rdata_en = s_nmi_rd_hdshk;
  always_comb begin
    s_nmi_rdata_d = s_nmi_rdata_q;
    unique case (nmi.addr[7:0])
      `SIMP_UART_DIV: s_nmi_rdata_d = s_uart_div_q;
      `SIMP_UART_DAT: s_nmi_rdata_d = r_recv_buf_valid ? {24'd0, r_recv_buf_data} : '1;
      default:        s_nmi_rdata_d = s_nmi_rdata_q;
    endcase
  end
  dffer #(32) u_nmi_rdata_dffer (
      clk_i,
      rst_n_i,
      s_nmi_rdata_en,
      s_nmi_rdata_d,
      s_nmi_rdata_q
  );


  always_ff @(posedge clk_i, negedge rst_n_i) begin
    if (!rst_n_i) begin
      r_recv_state     <= '0;
      r_recv_divcnt    <= '0;
      r_recv_pattern   <= '0;
      r_recv_buf_data  <= '0;
      r_recv_buf_valid <= '0;
    end else begin
      r_recv_divcnt <= r_recv_divcnt + 1'b1;
      if (s_uart_dat_en) r_recv_buf_valid <= '0;
      case (r_recv_state)
        4'd0: begin
          if (!uart.rx) r_recv_state <= 1'b1;
          r_recv_divcnt <= '0;
        end
        4'd1: begin
          if (2 * r_recv_divcnt > s_uart_div_q) begin
            r_recv_state  <= 4'd2;
            r_recv_divcnt <= '0;
          end
        end
        4'd10: begin
          if (r_recv_divcnt > s_uart_div_q) begin
            r_recv_buf_data  <= r_recv_pattern;
            r_recv_buf_valid <= 1'b1;
            r_recv_state     <= '0;
          end
        end
        default: begin
          if (r_recv_divcnt > s_uart_div_q) begin
            r_recv_pattern <= {uart.rx, r_recv_pattern[7:1]};
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
      if (s_uart_div_en) r_send_dummy <= 1'b1;
      r_send_divcnt <= r_send_divcnt + 1'b1;

      if (r_send_dummy && !r_send_bitcnt) begin
        r_send_pattern <= '1;
        r_send_bitcnt  <= 4'd15;
        r_send_divcnt  <= '0;
        r_send_dummy   <= '0;
      end else if (s_uart_dat_en && nmi.wstrb[0] && !r_send_bitcnt) begin
        r_send_pattern <= {1'b1, nmi.wdata[7:0], 1'b0};
        r_send_bitcnt  <= 4'd10;
        r_send_divcnt  <= '0;
      end else if (r_send_divcnt > s_uart_div_q && r_send_bitcnt) begin
        r_send_pattern <= {1'b1, r_send_pattern[9:1]};
        r_send_bitcnt  <= r_send_bitcnt - 1'b1;
        r_send_divcnt  <= '0;
      end
    end
  end
endmodule
