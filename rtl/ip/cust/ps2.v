// Copyright (c) 2023-2024 Miao Yuchi <miaoyuchi@ict.ac.cn>
// ps2 is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef INC_PS2_DEF_SV
`define INC_PS2_DEF_SV

/* register mapping
 * PS2_CTRL:
 * BITS:   | 31:2 | 1  | 0   |
 * FIELDS: | RES  | EN | ITN |
 * PERMS:  | NONE | RW | RW  |
 * ---------------------------
 * PS2_DATA:
 * BITS:   | 31:8 | 7:0  |
 * FIELDS: | RES  | DATA |
 * PERMS:  | NONE | RO   |
 * ---------------------------
 * PS2_STAT:
 * BITS:   | 31:1 | 0   |
 * FIELDS: | RES  | ITF |
 * PERMS:  | NONE | RO  |
 * ---------------------------
*/

// verilog_format: off
`define PS2_CTRL 4'b0000 // BASEADDR + 0x00
`define PS2_DATA 4'b0001 // BASEADDR + 0x04
`define PS2_STAT 4'b0010 // BASEADDR + 0x08

`define PS2_CTRL_ADDR {26'b0, `PS2_CTRL, 2'b00}
`define PS2_DATA_ADDR {26'b0, `PS2_DATA, 2'b00}
`define PS2_STAT_ADDR {26'b0, `PS2_STAT, 2'b00}

`define PS2_CTRL_WIDTH 2
`define PS2_DATA_WIDTH 8
`define PS2_STAT_WIDTH 1
// verilog_format: on
`endif

// Copyright (c) 2023-2024 Miao Yuchi <miaoyuchi@ict.ac.cn>
// ps2 is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

// only support keyboard now
module apb4_ps2 (
    input             pclk,
    input             presetn,
    input      [31:0] paddr,
    input      [ 2:0] pprot,
    input             psel,
    input             penable,
    input             pwrite,
    input      [31:0] pwdata,
    input      [ 3:0] pstrb,
    output            pready,
    output reg [31:0] prdata,
    output            pslverr,
    input             ps2_clk_i,
    input             ps2_dat_i,
    output            irq_o
);

  wire [3:0] s_apb4_addr;
  wire s_apb4_wr_hdshk, s_apb4_rd_hdshk;
  wire [`PS2_CTRL_WIDTH-1:0] s_ps2_ctrl_d, s_ps2_ctrl_q;
  wire                       s_ps2_ctrl_en;
  reg  [`PS2_STAT_WIDTH-1:0] s_ps2_stat_d;
  wire [`PS2_STAT_WIDTH-1:0] s_ps2_stat_q;
  wire                       s_ps2_stat_en;
  reg  [                3:0] s_cnt_d;
  wire [                3:0] s_cnt_q;
  reg  [                9:0] s_dat_d;
  wire [                9:0] s_dat_q;
  wire                       s_fifo_empty;
  reg                        s_fifo_push_valid;
  wire [                7:0] s_fifo_rd_dat;
  wire s_bit_itn, s_bit_en, s_bit_itf, s_clk_fe, s_irq_trg;

  assign s_apb4_addr     = paddr[5:2];
  assign s_apb4_wr_hdshk = psel && penable && pwrite;
  assign s_apb4_rd_hdshk = psel && penable && (~pwrite);
  assign pready          = 1'b1;
  assign pslverr         = 1'b0;

  assign s_bit_itn       = s_ps2_ctrl_q[0];
  assign s_bit_en        = s_ps2_ctrl_q[1];
  assign s_bit_itf       = s_ps2_stat_q[0];
  assign irq_o           = s_bit_itf;

  assign s_ps2_ctrl_en   = s_apb4_wr_hdshk && s_apb4_addr == `PS2_CTRL;
  assign s_ps2_ctrl_d    = pwdata[`PS2_CTRL_WIDTH-1:0];
  dffer #(`PS2_CTRL_WIDTH) u_ps2_ctrl_dffer (
      pclk,
      presetn,
      s_ps2_ctrl_en,
      s_ps2_ctrl_d,
      s_ps2_ctrl_q
  );

  edge_det_fe #(2, 1) u_ps2_clk_edge_det_fe (
      pclk,
      presetn,
      ps2_clk_i,
      s_clk_fe
  );

  always @(*) begin
    s_cnt_d = s_cnt_q;
    if (s_clk_fe) begin
      if (s_cnt_q == 4'd10) begin
        s_cnt_d = 'h0;
      end else begin
        s_cnt_d = s_cnt_q + 1'b1;
      end
    end
  end
  dffer #(4) u_cnt_dffer (
      pclk,
      presetn,
      s_clk_fe,
      s_cnt_d,
      s_cnt_q
  );

  always @(*) begin
    s_dat_d = s_dat_q;
    if (s_clk_fe) begin
      if (s_cnt_q < 4'd10) begin
        s_dat_d[s_cnt_q] = ps2_dat_i;
      end
    end
  end
  dffer #(10) u_dat_dffer (
      pclk,
      presetn,
      s_clk_fe,
      s_dat_d,
      s_dat_q
  );

  always @(*) begin
    s_fifo_push_valid = 1'b0;
    if (s_bit_en && s_clk_fe) begin
      if (s_cnt_q == 4'd10) begin
        if (s_dat_q[0] == 1'b0 && ps2_dat_i && (^s_dat_q[9:1])) begin
          s_fifo_push_valid = 1'b1;
        end
      end
    end
  end
  fifo #(
      .DATA_WIDTH  (8),
      .BUFFER_DEPTH(16)
  ) u_ps2_fifo (
      .clk_i  (pclk),
      .rst_n_i(presetn),
      .flush_i(1'b0),
      .full_o (),
      .empty_o(s_fifo_empty),
      .cnt_o  (),
      .dat_i  (s_dat_q[8:1]),
      .push_i (s_fifo_push_valid),
      .dat_o  (s_fifo_rd_dat),
      .pop_i  (s_apb4_rd_hdshk && s_apb4_addr == `PS2_DATA)
  );

  assign s_irq_trg = ~s_fifo_empty;
  assign s_ps2_stat_en = (s_bit_itf && s_apb4_rd_hdshk && s_apb4_addr == `PS2_STAT) || (~s_bit_itf && s_bit_en && s_bit_itn && s_irq_trg);
  always @(*) begin
    s_ps2_stat_d = s_ps2_stat_q;
    if (s_bit_itf && s_apb4_rd_hdshk && s_apb4_addr == `PS2_STAT) begin
      s_ps2_stat_d = 'h0;
    end else if (~s_bit_itf && s_bit_en && s_bit_itn && s_irq_trg) begin
      s_ps2_stat_d = 'h1;
    end
  end
  dffer #(`PS2_STAT_WIDTH) u_ps2_stat_dffer (
      pclk,
      presetn,
      s_ps2_stat_en,
      s_ps2_stat_d,
      s_ps2_stat_q
  );

  // verilog_format: off
  always @(*) begin
    prdata = 'h0;
    if (s_apb4_rd_hdshk) begin
       case (s_apb4_addr)
        `PS2_CTRL: prdata[`PS2_CTRL_WIDTH-1:0] = s_ps2_ctrl_q;
        `PS2_DATA: prdata[`PS2_DATA_WIDTH-1:0] = (s_fifo_empty || ~s_bit_en) ? 'h0 : s_fifo_rd_dat;
        `PS2_STAT: prdata[`PS2_STAT_WIDTH-1:0] = s_ps2_stat_q;
        default:   prdata = 'h0;
      endcase
    end
  end
  // verilog_format: on
endmodule
