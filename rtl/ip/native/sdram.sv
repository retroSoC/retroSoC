/*
 *  mt48lc16m16a2_ctrl - A sdram controller
 *
 *  Copyright (C) 2022  Hirosh Dabui <hirosh@dabui.de>
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

interface sdram_if ();
  logic        clk_o;
  logic        cke_o;
  logic        cs_n_o;
  logic        ras_n_o;
  logic        cas_n_o;
  logic        we_n_o;
  logic [ 1:0] ba_o;
  logic [12:0] addr_o;
  logic [ 1:0] dqm_o;
  logic        oe_o;
  logic [15:0] dq_i;
  logic [15:0] dq_o;

  modport dut(
      output clk_o,
      output cke_o,
      output cs_n_o,
      output ras_n_o,
      output cas_n_o,
      output we_n_o,
      output ba_o,
      output addr_o,
      output dqm_o,
      output oe_o,
      input dq_i,
      output dq_o
  );
  // verilog_format: on
endinterface

module nmi_sdram #(
    parameter CLK_FREQ = 72,
    parameter TRP_NS   = 20,
    parameter TRC_NS   = 66,
    parameter TRCD_NS  = 20,
    parameter TCH_NS   = 2,
    parameter CAS      = 3'd2
) (
    // verilog_format: off
    input logic  clk_i,
    input logic  rst_n_i,
    nmi_if.slave nmi,
    sdram_if.dut sdram
    // verilog_format: on
);


  // CLK_FREQ * 1/CLK_FREQe6s = 1us
  localparam ONE_OVER_MICROSECOND = CLK_FREQ;
  localparam WAIT_100US = 100 * ONE_OVER_MICROSECOND;
  // command period; PRE to ACT in ns, e.g. 20ns
  localparam TRP = $rtoi((TRP_NS * ONE_OVER_MICROSECOND / 1000) + 1);
  // tRC command period (REF to REF/ACT TO ACT) in ns
  localparam TRC = $rtoi((TRC_NS * ONE_OVER_MICROSECOND / 1000) + 1);
  // tRCD active command to read/write command delay; row-col-delay in ns
  localparam TRCD = $rtoi((TRCD_NS * ONE_OVER_MICROSECOND / 1000) + 1);
  // tCH command hold time
  localparam TCH = $rtoi((TCH_NS * ONE_OVER_MICROSECOND / 1000) + 1);
  // 000: 1-burst, 001: 2-burst
  // 010: 4-burst, 011: 8-burst
  localparam BURST_LENGTH = 3'b001;
  // 0: sequential, 1: interleaved
  localparam ACCESS_TYPE = 1'b0;
  // 2/3 allowed, tRCD=20ns -> 3 cycles@128MHz
  localparam CAS_LATENCY = CAS;
  // only 00 (standard operation) allowed
  localparam OP_MODE = 2'b00;
  // 0: write burst enabled, 1: only single access write
  localparam NO_WRITE_BURST = 1'b0;
  // (CS, RAS, CAS, WE)
  // mode register set
  localparam CMD_MRS = 4'b0000;
  // bank active
  localparam CMD_ACT = 4'b0011;
  // have read variant with autoprecharge set A10=H
  localparam CMD_READ = 4'b0101;
  // A10=H to have autoprecharge
  localparam CMD_WRITE = 4'b0100;
  // burst stop
  localparam CMD_BST = 4'b0110;
  // precharge selected bank, A10=H both banks
  localparam CMD_PRER = 4'b0010;
  // auto refresh (cke=H), selfrefresh assign cke=L
  localparam CMD_RFSH = 4'b0001;
  localparam CMD_NOP = 4'b0111;
  localparam SDRAM_MODE = {3'b0, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_LENGTH};

  // verilog_format: off
  localparam RESET                   = 4'd0;
  localparam ASSERT_CKE              = 4'd1;
  localparam INIT_SEQ_PRE_CHARGE_ALL = 4'd2;
  localparam INIT_SEQ_AUTO_REFRESH0  = 4'd3;
  localparam INIT_SEQ_AUTO_REFRESH1  = 4'd4;
  localparam INIT_SEQ_LOAD_MODE      = 4'd5;
  localparam IDLE                    = 4'd6;
  localparam COL_READ                = 4'd7;
  localparam COL_READL               = 4'd8;
  localparam COL_READH               = 4'd9;
  localparam COL_WRITEL              = 4'd10;
  localparam COL_WRITEH              = 4'd11;
  localparam AUTO_REFRESH            = 4'd12;
  localparam PRE_CHARGE_ALL          = 4'd13;
  localparam WAIT_STATE              = 4'd14;
  localparam LAST_STATE              = 4'd15;
  // verilog_format: on


  initial begin
    $display("Clk frequence: %6d MHz", CLK_FREQ);
    $display("WAIT_100US:    %6d cycles", WAIT_100US);
    $display("TRP:           %6d cycles", TRP);
    $display("TRC:           %6d cycles", TRC);
    $display("TRCD:          %6d cycles", TRCD);
    $display("TCH:           %6d cycles", TCH);
    $display("CAS_LATENCY:   %6d cycles", CAS_LATENCY);
  end


  logic [3:0] s_state_d, s_state_q;
  logic [3:0] s_ret_state_d, s_ret_state_q;
  logic [15:0] s_wait_cnt_d, s_wait_cnt_q;
  logic [3:0] s_cmd_d, s_cmd_q;
  logic s_ready_d, s_ready_q;
  logic [31:0] s_rdata_d, s_rdata_q;
  // sdram
  logic [1:0] s_dqm_d, s_dqm_q;
  logic [15:0] s_dq_d, s_dq_q;
  logic [1:0] s_ba_q, s_ba_d;
  logic s_oe_q, s_oe_d;
  logic s_cke_q, s_cke_d;
  logic [12:0] s_addr_d, s_addr_q;
  logic s_upd_ready_d, s_upd_ready_q;


  // nmi
  assign nmi.ready                                                  = s_ready_q;
  assign nmi.rdata                                                  = s_rdata_q;
  // sdram
  assign sdram.clk_o                                                = clk_i;
  assign sdram.cke_o                                                = s_cke_q;
  assign sdram.addr_o                                               = s_addr_q;
  assign sdram.dqm_o                                                = s_dqm_q;
  assign {sdram.cs_n_o, sdram.ras_n_o, sdram.cas_n_o, sdram.we_n_o} = s_cmd_q;
  assign sdram.ba_o                                                 = s_ba_q;
  assign sdram.dq_o                                                 = s_dq_q;
  assign sdram.oe_o                                                 = s_oe_q;



  always_comb begin
    s_state_d     = s_state_q;
    s_ret_state_d = s_ret_state_q;
    s_wait_cnt_d  = s_wait_cnt_q;
    s_cmd_d       = s_cmd_q;
    s_ready_d     = s_ready_q;
    s_rdata_d     = s_rdata_q;
    // sdram
    s_dqm_d       = s_dqm_q;
    s_dq_d        = s_dq_q;
    s_ba_d        = s_ba_q;
    s_oe_d        = s_oe_q;
    s_cke_d       = s_cke_q;
    s_addr_d      = s_addr_q;
    s_upd_ready_d = s_upd_ready_q;
    case (s_state_q)
      RESET: begin
        s_cke_d       = 1'b0;
        s_state_d     = WAIT_STATE;
        s_ret_state_d = ASSERT_CKE;
        s_wait_cnt_d  = 16'(WAIT_100US);
      end
      ASSERT_CKE: begin
        s_cke_d       = 1'b1;
        s_state_d     = WAIT_STATE;
        s_ret_state_d = INIT_SEQ_PRE_CHARGE_ALL;
        s_wait_cnt_d  = 16'd2;
      end
      INIT_SEQ_PRE_CHARGE_ALL: begin
        s_cke_d       = 1'b1;
        s_cmd_d       = CMD_PRER;
        s_addr_d[10]  = 1'b1;
        s_state_d     = WAIT_STATE;
        s_ret_state_d = INIT_SEQ_AUTO_REFRESH0;
        s_wait_cnt_d  = 16'(TRP);
      end
      INIT_SEQ_AUTO_REFRESH0: begin
        s_cmd_d       = CMD_RFSH;
        s_state_d     = WAIT_STATE;
        s_ret_state_d = INIT_SEQ_AUTO_REFRESH1;
        s_wait_cnt_d  = 16'(TRC);
      end
      INIT_SEQ_AUTO_REFRESH1: begin
        s_cmd_d       = CMD_RFSH;
        s_state_d     = WAIT_STATE;
        s_ret_state_d = INIT_SEQ_LOAD_MODE;
        s_wait_cnt_d  = 16'(TRC);
      end
      INIT_SEQ_LOAD_MODE: begin
        s_cmd_d       = CMD_MRS;
        s_addr_d      = SDRAM_MODE;
        s_state_d     = WAIT_STATE;
        s_ret_state_d = IDLE;
        s_wait_cnt_d  = 16'(TCH);
      end
      IDLE: begin
        s_oe_d    = 1'b0;
        s_dqm_d   = 2'b11;
        s_ready_d = 1'b0;
        if (nmi.valid && !s_ready_q) begin
          s_cmd_d       = CMD_ACT;
          s_ba_d        = nmi.addr[22:21];
          s_addr_d      = {nmi.addr[24:23], nmi.addr[20:10]};
          s_state_d     = WAIT_STATE;
          s_ret_state_d = |nmi.wstrb ? COL_WRITEL : COL_READ;
          s_wait_cnt_d  = 16'(TRCD);
          s_upd_ready_d = 1'b1;
        end else begin
          // autorefresh
          s_cmd_d       = CMD_RFSH;
          s_addr_d      = '0;
          s_ba_d        = '0;
          // TRC
          s_state_d     = WAIT_STATE;
          s_ret_state_d = IDLE;
          s_wait_cnt_d  = 16'(TRC);
          s_upd_ready_d = 1'b0;
        end
      end
      COL_READ: begin
        s_cmd_d       = CMD_READ;
        s_dqm_d       = 2'b00;
        // autoprecharge and column
        s_ba_d        = nmi.addr[22:21];
        s_addr_d      = {3'b001, nmi.addr[10:2], 1'b0};
        s_state_d     = WAIT_STATE;
        s_ret_state_d = COL_READL;
        s_wait_cnt_d  = 16'(CAS_LATENCY);
      end
      COL_READL: begin
        s_cmd_d         = CMD_NOP;
        s_dqm_d         = 2'b00;
        s_rdata_d[15:0] = sdram.dq_i;
        s_state_d       = COL_READH;
        //s_wait_cnt_d = TRP;
        // s_ret_state_d   = COL_READH;
      end
      COL_READH: begin
        s_cmd_d          = CMD_NOP;
        s_dqm_d          = 2'b00;
        s_rdata_d[31:16] = sdram.dq_i;
        s_state_d        = WAIT_STATE;
        s_ret_state_d    = IDLE;
        s_wait_cnt_d     = 16'(TRP);
      end
      COL_WRITEL: begin
        s_cmd_d   = CMD_WRITE;
        s_dqm_d   = ~nmi.wstrb[1:0];
        // autoprecharge and column
        s_ba_d    = nmi.addr[22:21];
        s_addr_d  = {3'b001, nmi.addr[10:2], 1'b0};
        s_dq_d    = nmi.wdata[15:0];
        s_oe_d    = 1'b1;
        s_state_d = COL_WRITEH;
        //s_ret_state_d   = COL_WRITEH;
        //s_wait_cnt_d = TRP;
      end
      COL_WRITEH: begin
        s_cmd_d       = CMD_NOP;
        s_dqm_d       = ~nmi.wstrb[3:2];
        // autoprecharge and column
        s_ba_d        = nmi.addr[22:21];
        s_addr_d      = {3'b001, nmi.addr[10:2], 1'b0};
        s_dq_d        = nmi.wdata[31:16];
        s_oe_d        = 1'b1;
        s_state_d     = WAIT_STATE;
        s_ret_state_d = IDLE;
        s_wait_cnt_d  = 16'(TRP);
      end
      // NOTE: notused
      // PRE_CHARGE_ALL: begin
      //   s_cmd_d     = CMD_PRER;
      //   // select all banks
      //   s_addr_d[10]   = 1'b1;
      //   s_ba_d          = 0;
      //   s_state_d       = WAIT_STATE;
      //   s_ret_state_d   = IDLE;
      //   s_wait_cnt_d = TRP;
      // end
      WAIT_STATE: begin
        s_cmd_d      = CMD_NOP;
        s_wait_cnt_d = s_wait_cnt_q - 1'b1;
        if (s_wait_cnt_q == 16'd1) begin
          s_state_d = s_ret_state_q;
          if (s_ret_state_q == IDLE && s_upd_ready_q) begin
            s_upd_ready_d = 1'b0;
            s_ready_d     = 1'b1;
          end
        end
      end
      default: begin
        s_state_d = s_state_q;
      end
    endcase
  end

  always_ff @(posedge clk_i, negedge rst_n_i) begin
    if (~rst_n_i) begin
      s_state_q     <= RESET;
      s_ret_state_q <= RESET;
      s_wait_cnt_q  <= '0;
      s_cmd_q       <= CMD_NOP;
      s_ready_q     <= '0;
      s_rdata_q     <= '0;
      // sdram
      s_dqm_q       <= '1;
      s_dq_q        <= '0;
      s_ba_q        <= '1;
      s_oe_q        <= '0;
      s_cke_q       <= '0;
      s_addr_q      <= '0;
      s_upd_ready_q <= '0;
    end else begin
      s_state_q     <= s_state_d;
      s_ret_state_q <= s_ret_state_d;
      s_wait_cnt_q  <= s_wait_cnt_d;
      s_cmd_q       <= s_cmd_d;
      s_ready_q     <= s_ready_d;
      s_rdata_q     <= s_rdata_d;
      // sdram
      s_dqm_q       <= s_dqm_d;
      s_dq_q        <= s_dq_d;
      s_ba_q        <= s_ba_d;
      s_oe_q        <= s_oe_d;
      s_cke_q       <= s_cke_d;
      s_addr_q      <= s_addr_d;
      s_upd_ready_q <= s_upd_ready_d;
    end
  end

endmodule
