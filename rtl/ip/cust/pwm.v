// Copyright (c) 2023-2024 Miao Yuchi <miaoyuchi@ict.ac.cn>
// pwm is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef INC_PWM_DEF_SV
`define INC_PWM_DEF_SV

/* register mapping
 * PWM_CTRL:
 * BITS:   | 31:3 | 2   | 1  | 0    |
 * FIELDS: | RES  | CLR | EN | OVIE |
 * PERMS:  | NONE | RW  | RW | RW   |
 * ----------------------------------
 * PWM_PSCR:
 * BITS:   | 31:16 | 15:0 |
 * FIELDS: | RES   | PSCR |
 * PERMS:  | NONE  | RW   |
 * ----------------------------------
 * PWM_CNT:
 * BITS:   | 31:16 | 15:0 |
 * FIELDS: | RES   | CNT  |
 * PERMS:  | NONE  | none |
 * ----------------------------------
 * PWM_CMP:
 * BITS:   | 31:16 | 15:0 |
 * FIELDS: | RES   | CMP  |
 * PERMS:  | NONE  | RW   |
 * ----------------------------------
 * PWM_CRX:
 * BITS:   | 31:16 | 15:0 |
 * FIELDS: | RES   | CRX  |
 * PERMS:  | NONE  | RW   |
 * ----------------------------------
 * PWM_STAT:
 * BITS:   | 31:1  | 0    |
 * FIELDS: | RES   | OVIF |
 * PERMS:  | NONE  | RO   |
 * ----------------------------------
*/

// verilog_format: off
`define PWM_CTRL 4'b0000 // BASEADDR + 0x00
`define PWM_PSCR 4'b0001 // BASEADDR + 0x04
`define PWM_CNT  4'b0010 // BASEADDR + 0x08
`define PWM_CMP  4'b0011 // BASEADDR + 0x0C
`define PWM_CR0  4'b0100 // BASEADDR + 0x10
`define PWM_CR1  4'b0101 // BASEADDR + 0x14
`define PWM_CR2  4'b0110 // BASEADDR + 0x18
`define PWM_CR3  4'b0111 // BASEADDR + 0x1C
`define PWM_STAT 4'b1000 // BASEADDR + 0x20

`define PWM_CTRL_ADDR {26'b0, `PWM_CTRL, 2'b00}
`define PWM_PSCR_ADDR {26'b0, `PWM_PSCR, 2'b00}
`define PWM_CNT_ADDR  {26'b0, `PWM_CNT , 2'b00}
`define PWM_CMP_ADDR  {26'b0, `PWM_CMP , 2'b00}
`define PWM_CR0_ADDR  {26'b0, `PWM_CR0 , 2'b00}
`define PWM_CR1_ADDR  {26'b0, `PWM_CR1 , 2'b00}
`define PWM_CR2_ADDR  {26'b0, `PWM_CR2 , 2'b00}
`define PWM_CR3_ADDR  {26'b0, `PWM_CR3 , 2'b00}
`define PWM_STAT_ADDR {26'b0, `PWM_STAT, 2'b00}

`define PWM_CTRL_WIDTH 3
`define PWM_PSCR_WIDTH 16
`define PWM_CNT_WIDTH  16
`define PWM_CMP_WIDTH  16
`define PWM_CRX_WIDTH  16
`define PWM_STAT_WIDTH 1

`define PWM_PSCR_MIN_VAL  {{(`PWM_PSCR_WIDTH-2){1'b0}}, 2'd2}
// verilog_format: on
`endif



// Copyright (c) 2023-2024 Miao Yuchi <miaoyuchi@ict.ac.cn>
// pwm is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module apb4_pwm (
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
    output     [ 3:0] pwm_o,
    output            irq_o
);

  wire [3:0] s_apb4_addr;
  wire s_apb4_wr_hdshk, s_apb4_rd_hdshk;
  wire [`PWM_CTRL_WIDTH-1:0] s_pwm_ctrl_d, s_pwm_ctrl_q;
  wire s_pwm_ctrl_en;
  wire [`PWM_PSCR_WIDTH-1:0] s_pwm_pscr_d, s_pwm_pscr_q;
  wire                      s_pwm_pscr_en;
  reg  [`PWM_CNT_WIDTH-1:0] s_pwm_cnt_d;
  wire [`PWM_CNT_WIDTH-1:0] s_pwm_cnt_q;
  wire                      s_pwm_cnt_en;
  wire [`PWM_CMP_WIDTH-1:0] s_pwm_cmp_d, s_pwm_cmp_q;
  wire s_pwm_cmp_en;
  wire [`PWM_CRX_WIDTH-1:0] s_pwm_cr0_d, s_pwm_cr0_q;
  wire s_pwm_cr0_en;
  wire [`PWM_CRX_WIDTH-1:0] s_pwm_cr1_d, s_pwm_cr1_q;
  wire s_pwm_cr1_en;
  wire [`PWM_CRX_WIDTH-1:0] s_pwm_cr2_d, s_pwm_cr2_q;
  wire s_pwm_cr2_en;
  wire [`PWM_CRX_WIDTH-1:0] s_pwm_cr3_d, s_pwm_cr3_q;
  wire                       s_pwm_cr3_en;
  reg  [`PWM_STAT_WIDTH-1:0] s_pwm_stat_d;
  wire [`PWM_STAT_WIDTH-1:0] s_pwm_stat_q;
  wire                       s_pwm_stat_en;
  wire s_bit_ovie, s_bit_en, s_bit_clr, s_bit_ovif;
  wire s_valid, s_done, s_tc_trg, s_normal_mode, s_ov_irq_trg;

  assign s_apb4_addr     = paddr[5:2];
  assign s_apb4_wr_hdshk = psel && penable && pwrite;
  assign s_apb4_rd_hdshk = psel && penable && (~pwrite);
  assign pready          = 1'b1;
  assign pslverr         = 1'b0;

  assign s_bit_ovie      = s_pwm_ctrl_q[0];
  assign s_bit_en        = s_pwm_ctrl_q[1];
  assign s_bit_clr       = s_pwm_ctrl_q[2];
  assign s_bit_ovif      = s_pwm_stat_q[0];
  assign s_normal_mode   = s_bit_en & s_done;
  assign irq_o           = s_bit_ovif;

  assign s_pwm_ctrl_en   = s_apb4_wr_hdshk && s_apb4_addr == `PWM_CTRL;
  assign s_pwm_ctrl_d    = pwdata[`PWM_CTRL_WIDTH-1:0];
  dffer #(`PWM_CTRL_WIDTH) u_pwm_ctrl_dffer (
      pclk,
      presetn,
      s_pwm_ctrl_en,
      s_pwm_ctrl_d,
      s_pwm_ctrl_q
  );

  assign s_pwm_pscr_en = s_apb4_wr_hdshk && s_apb4_addr == `PWM_PSCR;
  assign s_pwm_pscr_d  = pwdata[`PWM_PSCR_WIDTH-1:0];
  dffer #(`PWM_PSCR_WIDTH) u_pwm_pscr_dffer (
      pclk,
      presetn,
      s_pwm_pscr_en,
      s_pwm_pscr_d,
      s_pwm_pscr_q
  );

  assign s_valid = s_apb4_wr_hdshk && s_apb4_addr == `PWM_PSCR && s_done;
  clk_int_div_simple #(`PWM_PSCR_WIDTH) u_clk_int_div_simple (
      .clk_i        (pclk),
      .rst_n_i      (presetn),
      .div_i        (s_pwm_pscr_q),
      .clk_init_i   (1'b0),
      .div_valid_i  (s_valid),
      .div_ready_o  (),
      .div_done_o   (s_done),
      .clk_cnt_o    (),
      .clk_fir_trg_o(),
      .clk_sec_trg_o(s_tc_trg),
      .clk_o        ()
  );

  assign s_pwm_cnt_en = s_bit_clr || (s_normal_mode && s_tc_trg);
  always @(*) begin
    s_pwm_cnt_d = s_pwm_cnt_q;
    if (s_bit_clr) begin
      s_pwm_cnt_d = 'h0;
    end else if (s_normal_mode) begin
      if (s_pwm_cnt_q >= s_pwm_cmp_q - 1) begin
        s_pwm_cnt_d = 'h0;
      end else begin
        s_pwm_cnt_d = s_pwm_cnt_q + 1'b1;
      end
    end
  end
  dffer #(`PWM_CNT_WIDTH) u_pwm_cnt_dffer (
      pclk,
      presetn,
      s_pwm_cnt_en,
      s_pwm_cnt_d,
      s_pwm_cnt_q
  );

  assign s_pwm_cmp_en = s_apb4_wr_hdshk && s_apb4_addr == `PWM_CMP;
  assign s_pwm_cmp_d  = pwdata[`PWM_CMP_WIDTH-1:0];
  dffer #(`PWM_CMP_WIDTH) u_pwm_cmp_dffer (
      pclk,
      presetn,
      s_pwm_cmp_en,
      s_pwm_cmp_d,
      s_pwm_cmp_q
  );

  assign s_pwm_cr0_en = s_apb4_wr_hdshk && s_apb4_addr == `PWM_CR0;
  assign s_pwm_cr0_d  = pwdata[`PWM_CRX_WIDTH-1:0];
  dffer #(`PWM_CRX_WIDTH) u_pwm_cr0_dffer (
      pclk,
      presetn,
      s_pwm_cr0_en,
      s_pwm_cr0_d,
      s_pwm_cr0_q
  );

  assign s_pwm_cr1_en = s_apb4_wr_hdshk && s_apb4_addr == `PWM_CR1;
  assign s_pwm_cr1_d  = pwdata[`PWM_CRX_WIDTH-1:0];
  dffer #(`PWM_CRX_WIDTH) u_pwm_cr1_dffer (
      pclk,
      presetn,
      s_pwm_cr1_en,
      s_pwm_cr1_d,
      s_pwm_cr1_q
  );

  assign s_pwm_cr2_en = s_apb4_wr_hdshk && s_apb4_addr == `PWM_CR2;
  assign s_pwm_cr2_d  = pwdata[`PWM_CRX_WIDTH-1:0];
  dffer #(`PWM_CRX_WIDTH) u_pwm_cr2_dffer (
      pclk,
      presetn,
      s_pwm_cr2_en,
      s_pwm_cr2_d,
      s_pwm_cr2_q
  );

  assign s_pwm_cr3_en = s_apb4_wr_hdshk && s_apb4_addr == `PWM_CR3;
  assign s_pwm_cr3_d  = pwdata[`PWM_CRX_WIDTH-1:0];
  dffer #(`PWM_CRX_WIDTH) u_pwm_cr3_dffer (
      pclk,
      presetn,
      s_pwm_cr3_en,
      s_pwm_cr3_d,
      s_pwm_cr3_q
  );

  // NOTE: need to assure the s_pwmcrrx_q less than s_pwmcmp_q
  assign pwm_o[0] = s_pwm_cnt_q >= s_pwm_cr0_q;
  assign pwm_o[1] = s_pwm_cnt_q >= s_pwm_cr1_q;
  assign pwm_o[2] = s_pwm_cnt_q >= s_pwm_cr2_q;
  assign pwm_o[3] = s_pwm_cnt_q >= s_pwm_cr3_q;

  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_irq_cdc_sync (
      pclk,
      presetn,
      s_pwm_cnt_q >= s_pwm_cmp_q - 1,
      s_ov_irq_trg
  );

  assign s_pwm_stat_en = (s_bit_ovif && s_apb4_rd_hdshk && s_apb4_addr == `PWM_STAT) || (~s_bit_ovif && s_bit_en && s_bit_ovie && s_ov_irq_trg);
  always @(*) begin
    s_pwm_stat_d = s_pwm_stat_q;
    if (s_bit_ovif && s_apb4_rd_hdshk && s_apb4_addr == `PWM_STAT) begin
      s_pwm_stat_d = 'h0;
    end else if (~s_bit_ovif && s_bit_en && s_bit_ovie && s_ov_irq_trg) begin
      s_pwm_stat_d = 'h1;
    end
  end
  dffer #(`PWM_STAT_WIDTH) u_pwm_stat_dffer (
      pclk,
      presetn,
      s_pwm_stat_en,
      s_pwm_stat_d,
      s_pwm_stat_q
  );

  always @(*) begin
    prdata = 'h0;
    if (s_apb4_rd_hdshk) begin
      case (s_apb4_addr)
        `PWM_CTRL: prdata[`PWM_CTRL_WIDTH-1:0] = s_pwm_ctrl_q;
        `PWM_PSCR: prdata[`PWM_PSCR_WIDTH-1:0] = s_pwm_pscr_q;
        `PWM_CMP:  prdata[`PWM_CMP_WIDTH-1:0] = s_pwm_cmp_q;
        `PWM_CR0:  prdata[`PWM_CRX_WIDTH-1:0] = s_pwm_cr0_q;
        `PWM_CR1:  prdata[`PWM_CRX_WIDTH-1:0] = s_pwm_cr1_q;
        `PWM_CR2:  prdata[`PWM_CRX_WIDTH-1:0] = s_pwm_cr2_q;
        `PWM_CR3:  prdata[`PWM_CRX_WIDTH-1:0] = s_pwm_cr3_q;
        `PWM_STAT: prdata[`PWM_STAT_WIDTH-1:0] = s_pwm_stat_q;
        default:   prdata = 'h0;
      endcase
    end
  end
endmodule
