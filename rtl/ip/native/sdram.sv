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
    input logic  clk_i,
    input logic  rst_n_i,
    nmi_if.slave nmi,
    sdram_if.dut sdram
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

  localparam sdram_mode = {3'b0, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_LENGTH};

  initial begin
    $display("Clk frequence: %6d MHz", CLK_FREQ);
    $display("WAIT_100US:    %6d cycles", WAIT_100US);
    $display("TRP:           %6d cycles", TRP);
    $display("TRC:           %6d cycles", TRC);
    $display("TRCD:          %6d cycles", TRCD);
    $display("TCH:           %6d cycles", TCH);
    $display("CAS_LATENCY:   %6d cycles", CAS_LATENCY);
  end

  reg [3:0] command, command_nxt;
  reg cke, cke_nxt;
  reg [1:0] dqm;
  reg [12:0] saddr, saddr_nxt;
  reg [1:0] ba, ba_nxt;

  reg [3:0] state, state_nxt;
  reg [3:0] ret_state, ret_state_nxt;
  reg [15:0] wait_states, wait_states_nxt;
  reg        ready_nxt;
  reg [31:0] dout_nxt;
  reg [ 1:0] dqm_nxt;
  reg update_ready, update_ready_nxt;
  reg [15:0] dq, dq_nxt;
  reg oe, oe_nxt;
  reg [31:0] dout;
  reg        ready;

  // nmi
  assign nmi.ready                                                  = ready;
  assign nmi.rdata                                                  = dout;
  // sdram
  assign sdram.clk_o                                                = clk_i;
  assign sdram.cke_o                                                = cke;
  assign sdram.addr_o                                               = saddr;
  assign sdram.dqm_o                                                = dqm;
  assign {sdram.cs_n_o, sdram.ras_n_o, sdram.cas_n_o, sdram.we_n_o} = command;
  assign sdram.ba_o                                                 = ba;
  assign sdram.dq_o                                                 = dq;
  assign sdram.oe_o                                                 = oe;


  always_ff @(posedge clk_i, negedge rst_n_i) begin
    if (~rst_n_i) begin
      state        <= RESET;
      ret_state    <= RESET;
      wait_states  <= '0;
      command      <= CMD_NOP;
      ready        <= '0;
      dout         <= '0;
      // sdram
      dqm          <= '1;
      dq           <= '0;
      ba           <= '1;
      oe           <= '0;
      cke          <= '0;
      saddr        <= '0;
      update_ready <= '0;
    end else begin
      state        <= state_nxt;
      ret_state    <= ret_state_nxt;
      wait_states  <= wait_states_nxt;
      command      <= command_nxt;
      ready        <= ready_nxt;
      dout         <= dout_nxt;
      // sdram
      dqm          <= dqm_nxt;
      dq           <= dq_nxt;
      ba           <= ba_nxt;
      oe           <= oe_nxt;
      cke          <= cke_nxt;
      saddr        <= saddr_nxt;
      update_ready <= update_ready_nxt;
    end
  end

  always_comb begin
    state_nxt        = state;
    ret_state_nxt    = ret_state;
    wait_states_nxt  = wait_states;
    command_nxt      = command;
    ready_nxt        = ready;
    dout_nxt         = dout;
    // sdram
    dqm_nxt          = dqm;
    dq_nxt           = dq;
    ba_nxt           = ba;
    oe_nxt           = oe;
    cke_nxt          = cke;
    saddr_nxt        = saddr;
    update_ready_nxt = update_ready;
    case (state)
      RESET: begin
        cke_nxt         = 1'b0;
        state_nxt       = WAIT_STATE;
        ret_state_nxt   = ASSERT_CKE;
        wait_states_nxt = 16'(WAIT_100US);
      end
      ASSERT_CKE: begin
        cke_nxt         = 1'b1;
        state_nxt       = WAIT_STATE;
        ret_state_nxt   = INIT_SEQ_PRE_CHARGE_ALL;
        wait_states_nxt = 16'd2;
      end
      INIT_SEQ_PRE_CHARGE_ALL: begin
        cke_nxt         = 1'b1;
        command_nxt     = CMD_PRER;
        saddr_nxt[10]   = 1'b1;
        state_nxt       = WAIT_STATE;
        ret_state_nxt   = INIT_SEQ_AUTO_REFRESH0;
        wait_states_nxt = 16'(TRP);
      end
      INIT_SEQ_AUTO_REFRESH0: begin
        command_nxt     = CMD_RFSH;
        state_nxt       = WAIT_STATE;
        ret_state_nxt   = INIT_SEQ_AUTO_REFRESH1;
        wait_states_nxt = 16'(TRC);
      end
      INIT_SEQ_AUTO_REFRESH1: begin
        command_nxt     = CMD_RFSH;
        state_nxt       = WAIT_STATE;
        ret_state_nxt   = INIT_SEQ_LOAD_MODE;
        wait_states_nxt = 16'(TRC);
      end
      INIT_SEQ_LOAD_MODE: begin
        command_nxt     = CMD_MRS;
        saddr_nxt       = sdram_mode;
        state_nxt       = WAIT_STATE;
        ret_state_nxt   = IDLE;
        wait_states_nxt = 16'(TCH);
      end
      IDLE: begin
        oe_nxt    = 1'b0;
        dqm_nxt   = 2'b11;
        ready_nxt = 1'b0;
        if (nmi.valid && !ready) begin
          command_nxt      = CMD_ACT;
          ba_nxt           = nmi.addr[22:21];
          saddr_nxt        = {nmi.addr[24:23], nmi.addr[20:10]};
          state_nxt        = WAIT_STATE;
          ret_state_nxt    = |nmi.wstrb ? COL_WRITEL : COL_READ;
          wait_states_nxt  = 16'(TRCD);
          update_ready_nxt = 1'b1;
        end else begin
          // autorefresh
          command_nxt      = CMD_RFSH;
          saddr_nxt        = '0;
          ba_nxt           = '0;
          // TRC
          state_nxt        = WAIT_STATE;
          ret_state_nxt    = IDLE;
          wait_states_nxt  = 16'd3;
          update_ready_nxt = 1'b0;
        end
      end
      COL_READ: begin
        command_nxt     = CMD_READ;
        dqm_nxt         = 2'b00;
        // autoprecharge and column
        ba_nxt          = nmi.addr[22:21];
        saddr_nxt       = {3'b001, nmi.addr[10:2], 1'b0};
        state_nxt       = WAIT_STATE;
        ret_state_nxt   = COL_READL;
        wait_states_nxt = 16'(CAS_LATENCY);
      end
      COL_READL: begin
        command_nxt    = CMD_NOP;
        dqm_nxt        = 2'b00;
        dout_nxt[15:0] = sdram.dq_i;
        state_nxt      = COL_READH;
        //wait_states_nxt = TRP;
        // ret_state_nxt   = COL_READH;
      end
      COL_READH: begin
        command_nxt     = CMD_NOP;
        dqm_nxt         = 2'b00;
        dout_nxt[31:16] = sdram.dq_i;
        state_nxt       = WAIT_STATE;
        ret_state_nxt   = IDLE;
        wait_states_nxt = 16'(TRP);
      end
      COL_WRITEL: begin
        command_nxt = CMD_WRITE;
        dqm_nxt     = ~nmi.wstrb[1:0];
        // autoprecharge and column
        ba_nxt      = nmi.addr[22:21];
        saddr_nxt   = {3'b001, nmi.addr[10:2], 1'b0};
        dq_nxt      = nmi.wdata[15:0];
        oe_nxt      = 1'b1;
        state_nxt   = COL_WRITEH;
        //ret_state_nxt   = COL_WRITEH;
        //wait_states_nxt = TRP;
      end
      COL_WRITEH: begin
        command_nxt     = CMD_NOP;
        dqm_nxt         = ~nmi.wstrb[3:2];
        // autoprecharge and column
        ba_nxt          = nmi.addr[22:21];
        saddr_nxt       = {3'b001, nmi.addr[10:2], 1'b0};
        dq_nxt          = nmi.wdata[31:16];
        oe_nxt          = 1'b1;
        state_nxt       = WAIT_STATE;
        ret_state_nxt   = IDLE;
        wait_states_nxt = 16'(TRP);
      end
      // NOTE: notused
      // PRE_CHARGE_ALL: begin
      //   command_nxt     = CMD_PRER;
      //   // select all banks
      //   saddr_nxt[10]   = 1'b1;
      //   ba_nxt          = 0;
      //   state_nxt       = WAIT_STATE;
      //   ret_state_nxt   = IDLE;
      //   wait_states_nxt = TRP;
      // end
      WAIT_STATE: begin
        command_nxt     = CMD_NOP;
        wait_states_nxt = wait_states - 1'b1;
        if (wait_states == 16'd1) begin
          state_nxt = ret_state;
          if (ret_state == IDLE && update_ready) begin
            update_ready_nxt = 1'b0;
            ready_nxt        = 1'b1;
          end
        end
      end
      default: begin
        state_nxt = state;
      end
    endcase
  end

endmodule
