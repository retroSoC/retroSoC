// Copyright (c) 2023-2024 Miao Yuchi <miaoyuchi@ict.ac.cn>
// uart is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef INC_UART_DEF_SV
`define INC_UART_DEF_SV

/* register mapping
 * UART_LCR:
 * BITS:   | 31:9 | 8:7 | 6   | 5   | 4:3 | 2    | 1    | 0    |
 * FIELDS: | RES  | PS  | PEN | STB | WLS | PEIE | TXIE | RXIE |
 * PERMS:  | NONE | RW  | RW  | RW  | RW  | RW   | RW   | RW   |
  * --------------------------------------------------------------------------
 * UART_DIV:
 * BITS:   | 31:16 | 15:0 |
 * FIELDS: | RES   | DIV  |
 * PERMS:  | NONE  | RW   |
  * --------------------------------------------------------------------------
 * UART_TRX:
 * BITS:   | 31:8 | 7:0 || BITS:   | 31:8 | 7:0 |
 * FIELDS: | RES  | RX  || FIELDS: | RES  | TX  |
 * PERMS:  | NONE | RO  || PERMS:  | NONE | WO  |
  * --------------------------------------------------------------------------
 * UART_FCR:
 * BITS:   | 31:4 | 3:2         | 1      | 0      |
 * FIELDS: | RES  | RX_TRG_LEVL | TF_CLR | RF_CLR |
 * PERMS:  | NONE | WO          | WO     | WO     |
 * ---------------------------------------------------------------------------
 * UART_LSR:
 * BITS:   | 31:9 | 8    | 7    | 6    | 5    | 4  | 3  | 2    | 1    | 0    |
 * FIELDS: | RES  | FULL | EMPT | TEMT | THRE | PE | DR | PEIP | TXIP | RXIP |
 * PERMS:  | NONE | RO   | RO   | RO   | RO   | RO | RO | RO   | RO   | RO   |
 * ---------------------------------------------------------------------------
*/

// verilog_format: off
`define UART_LCR 4'b0000 // BASEADDR + 0x00
`define UART_DIV 4'b0001 // BASEADDR + 0x04
`define UART_TRX 4'b0010 // BASEADDR + 0x08
`define UART_FCR 4'b0011 // BASEADDR + 0x0C
`define UART_LSR 4'b0100 // BASEADDR + 0x10

`define UART_LCR_ADDR {26'b0, `UART_LCR, 2'b00}
`define UART_DIV_ADDR {26'b0, `UART_DIV, 2'b00}
`define UART_TRX_ADDR {26'b0, `UART_TRX, 2'b00}
`define UART_FCR_ADDR {26'b0, `UART_FCR, 2'b00}
`define UART_LSR_ADDR {26'b0, `UART_LSR, 2'b00}

`define UART_LCR_WIDTH 9
`define UART_DIV_WIDTH 16
`define UART_TRX_WIDTH 8
`define UART_FCR_WIDTH 4
`define UART_LSR_WIDTH 9

`define UART_DIV_MIN_VAL  {{(`UART_DIV_WIDTH-2){1'b0}}, 2'd2}
`define UART_LSR_RESET_VAL 9'h0E0
// verilog_format: on
`endif


// Copyright 2017 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the “License”); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an “AS IS” BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// -- Adaptable modifications are redistributed under compatible License --
//
// Copyright (c) 2023-2024 Miao Yuchi <miaoyuchi@ict.ac.cn>
// uart is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module uart_irq #(
    parameter FIFO_DEPTH     = 16,
    parameter LOG_FIFO_DEPTH = $clog2(FIFO_DEPTH)

) (
    input                     clk_i,
    input                     rst_n_i,
    input                     clr_int_i,
    input  [             2:0] irq_en_i,
    input                     thre_i,
    input                     cti_i,
    input                     pe_i,
    input  [LOG_FIFO_DEPTH:0] rx_elem_i,
    input  [LOG_FIFO_DEPTH:0] tx_elem_i,
    input  [             1:0] trg_level_i,
    output [             2:0] ip_o,
    output                    irq_o
);

  reg  [2:0] s_ip_d;
  wire [2:0] s_ip_q;
  reg        s_trg_level_done;

  always @(*) begin
    s_trg_level_done = 1'b0;
    case (trg_level_i)
      2'b00:   if (rx_elem_i == 4'd1) s_trg_level_done = 1'b1;
      2'b01:   if (rx_elem_i == 4'd2) s_trg_level_done = 1'b1;
      2'b10:   if (rx_elem_i == 4'd8) s_trg_level_done = 1'b1;
      2'b11:   if (rx_elem_i == 4'd14) s_trg_level_done = 1'b1;
      default: s_trg_level_done = 1'b0;
    endcase
  end

  always @(*) begin
    s_ip_d = s_ip_q;
    if (clr_int_i) begin
      s_ip_d = 3'b000;
    end else if (irq_en_i[2] & pe_i) begin
      s_ip_d = 3'b100;
    end else if (irq_en_i[1] & tx_elem_i == 0) begin
      s_ip_d = 3'b010;
    end else if (irq_en_i[0] & (s_trg_level_done | thre_i)) begin
      s_ip_d = 3'b001;
    end else if (irq_en_i[0] & cti_i) begin
      s_ip_d = 3'b001;
    end
  end

  dffr #(3) u_ip_dffr (
      clk_i,
      rst_n_i,
      s_ip_d,
      s_ip_q
  );

  assign ip_o  = s_ip_q;
  assign irq_o = s_ip_q != 3'b000;

endmodule

// Copyright 2017 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the “License”); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an “AS IS” BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// -- Adaptable modifications are redistributed under compatible License --
//
// Copyright (c) 2023-2024 Miao Yuchi <miaoyuchi@ict.ac.cn>
// uart is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module uart_rx (
    input             clk_i,
    input             rst_n_i,
    input             rx_i,
    output            busy_o,
    input             cfg_en_i,
    input      [15:0] cfg_div_i,
    input             cfg_parity_en_i,
    input      [ 1:0] cfg_parity_sel_i,
    input      [ 1:0] cfg_bits_i,
    output reg        err_o,
    input             err_clr_i,
    output     [ 7:0] rx_data_o,
    output reg        rx_valid_o,
    input             rx_ready_i
);

  localparam IDLE = 3'd0;
  localparam START_BIT = 3'd1;
  localparam DATA = 3'd2;
  localparam SAVE_DATA = 3'd3;
  localparam PARITY = 3'd4;
  localparam STOP_BIT = 3'd5;

  reg [2:0] s_fsm_d, s_fsm_q;
  reg [7:0] s_reg_data_d, s_reg_data_q;
  reg [2:0] s_reg_bit_cnt_d, s_reg_bit_cnt_q;
  reg [2:0] reg_rx_sync;
  reg [2:0] s_target_bits;
  reg s_parity_bit_d, s_parity_bit_q;
  reg         s_sample_data;
  reg         s_baudgen_en;
  reg         s_bit_done;
  reg         s_start_bit;
  reg         s_set_error;
  wire        s_rx_fall;
  reg  [15:0] s_baud_cnt;

  assign busy_o = (s_fsm_q != IDLE);
  always @(*) begin
    case (cfg_bits_i)
      2'b00:   s_target_bits = 3'd4;
      2'b01:   s_target_bits = 3'd5;
      2'b10:   s_target_bits = 3'd6;
      2'b11:   s_target_bits = 3'd7;
      default: s_target_bits = 3'd4;
    endcase
  end

  always @(*) begin
    s_sample_data   = 1'b0;
    rx_valid_o      = 1'b0;
    s_baudgen_en    = 1'b0;
    s_start_bit     = 1'b0;
    s_set_error     = 1'b0;
    s_fsm_d         = s_fsm_q;
    s_parity_bit_d  = s_parity_bit_q;
    s_reg_bit_cnt_d = s_reg_bit_cnt_q;
    s_reg_data_d    = s_reg_data_q;
    case (s_fsm_q)
      IDLE: begin
        if (s_rx_fall) begin
          s_fsm_d      = START_BIT;
          s_baudgen_en = 1'b1;
          s_start_bit  = 1'b1;
        end
      end
      START_BIT: begin
        s_parity_bit_d = 1'b0;
        s_baudgen_en   = 1'b1;
        s_start_bit    = 1'b1;
        if (s_bit_done) s_fsm_d = DATA;
      end
      DATA: begin
        s_baudgen_en   = 1'b1;
        s_parity_bit_d = s_parity_bit_q ^ reg_rx_sync[2];
        case (cfg_bits_i)
          2'b00: s_reg_data_d = {3'b000, reg_rx_sync[2], s_reg_data_q[4:1]};
          2'b01: s_reg_data_d = {2'b00, reg_rx_sync[2], s_reg_data_q[5:1]};
          2'b10: s_reg_data_d = {1'b0, reg_rx_sync[2], s_reg_data_q[6:1]};
          2'b11: s_reg_data_d = {reg_rx_sync[2], s_reg_data_q[7:1]};
        endcase

        if (s_bit_done) begin
          s_sample_data = 1'b1;
          if (s_reg_bit_cnt_q == s_target_bits) begin
            s_reg_bit_cnt_d = 'h0;
            s_fsm_d         = SAVE_DATA;
          end else begin
            s_reg_bit_cnt_d = s_reg_bit_cnt_q + 1;
          end
        end
      end
      SAVE_DATA: begin
        s_baudgen_en = 1'b1;
        rx_valid_o   = 1'b1;
        if (rx_ready_i)
          if (cfg_parity_en_i) s_fsm_d = PARITY;
          else s_fsm_d = STOP_BIT;
      end
      PARITY: begin
        s_baudgen_en = 1'b1;
        if (s_bit_done) begin
          case (cfg_parity_sel_i)
            2'b00: if (reg_rx_sync[2] != ~s_parity_bit_q) s_set_error = 1'b1;
            2'b01: if (reg_rx_sync[2] != s_parity_bit_q) s_set_error = 1'b1;
            2'b10: if (reg_rx_sync[2] != 1'b0) s_set_error = 1'b1;
            2'b11: if (reg_rx_sync[2] != 1'b1) s_set_error = 1'b1;
          endcase
          s_fsm_d = STOP_BIT;
        end
      end
      STOP_BIT: begin
        s_baudgen_en = 1'b1;
        if (s_bit_done) begin
          s_fsm_d = IDLE;
        end
      end
      default: s_fsm_d = IDLE;
    endcase
  end

  always @(posedge clk_i or negedge rst_n_i) begin
    if (~rst_n_i) begin
      s_fsm_q         <= IDLE;
      s_reg_data_q    <= 8'hFF;
      s_reg_bit_cnt_q <= 'h0;
      s_parity_bit_q  <= 1'b0;
    end else begin
      if (s_bit_done) begin
        s_parity_bit_q <= s_parity_bit_d;
      end

      if (s_sample_data) begin
        s_reg_data_q <= s_reg_data_d;
      end

      s_reg_bit_cnt_q <= s_reg_bit_cnt_d;
      if (cfg_en_i) s_fsm_q <= s_fsm_d;
      else s_fsm_q <= IDLE;
    end
  end

  assign s_rx_fall = ~reg_rx_sync[1] & reg_rx_sync[2];
  always @(posedge clk_i or negedge rst_n_i) begin
    if (~rst_n_i) reg_rx_sync <= 3'b111;
    else begin
      if (cfg_en_i) reg_rx_sync <= {reg_rx_sync[1:0], rx_i};
      else reg_rx_sync <= 3'b111;
    end
  end

  always @(posedge clk_i or negedge rst_n_i) begin
    if (~rst_n_i) begin
      s_baud_cnt <= 'h0;
      s_bit_done <= 1'b0;
    end else begin
      if (s_baudgen_en) begin
        if (!s_start_bit && (s_baud_cnt == cfg_div_i)) begin
          s_baud_cnt <= 'h0;
          s_bit_done <= 1'b1;
        end else if (s_start_bit && (s_baud_cnt == {1'b0, cfg_div_i[15:1]})) begin
          s_baud_cnt <= 'h0;
          s_bit_done <= 1'b1;
        end else begin
          s_baud_cnt <= s_baud_cnt + 1;
          s_bit_done <= 1'b0;
        end
      end else begin
        s_baud_cnt <= 'h0;
        s_bit_done <= 1'b0;
      end
    end
  end

  always @(posedge clk_i or negedge rst_n_i) begin
    if (~rst_n_i) begin
      err_o <= 1'b0;
    end else begin
      if (err_clr_i) begin
        err_o <= 1'b0;
      end else begin
        if (s_set_error) err_o <= 1'b1;
      end
    end
  end

  assign rx_data_o = s_reg_data_q;

endmodule

// Copyright 2017 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the “License”); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// , agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an “AS IS” BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express , implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// -- Adaptable modifications are redistributed under compatible License --
//
// Copyright (c) 2023-2024 Miao Yuchi <miaoyuchi@ict.ac.cn>
// uart is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module uart_tx (
    input             clk_i,
    input             rst_n_i,
    output reg        tx_o,
    output            busy_o,
    input             cfg_en_i,
    input      [15:0] cfg_div_i,         // NOTE: no parameterization
    input             cfg_parity_en_i,
    input      [ 1:0] cfg_parity_sel_i,
    input      [ 1:0] cfg_bits_i,
    input             cfg_stop_bits_i,
    input      [ 7:0] tx_data_i,
    input             tx_valid_i,
    output reg        tx_ready_o
);

  localparam IDLE = 3'd0;
  localparam START_BIT = 3'd1;
  localparam DATA = 3'd2;
  localparam PARITY = 3'd3;
  localparam STOP_BIT_FIRST = 3'd4;
  localparam STOP_BIT_LAST = 3'd5;

  reg [2:0] s_fsm_d, s_fsm_q;
  reg [7:0] s_reg_data_d, s_reg_data_q;
  reg [2:0] s_reg_bit_cnt_d, s_reg_bit_cnt_q;
  reg [2:0] s_target_bits;
  reg s_parity_bit_d, s_parity_bit_q;
  reg        s_sample_data;
  reg        s_baudgen_en;
  reg        s_bit_done;
  reg [15:0] baud_cnt;  // NOTE: no parameterization

  assign busy_o = (s_fsm_q != IDLE);
  always @(*) begin
    case (cfg_bits_i)
      2'b00:   s_target_bits = 3'd4;
      2'b01:   s_target_bits = 3'd5;
      2'b10:   s_target_bits = 3'd6;
      2'b11:   s_target_bits = 3'd7;
      default: s_target_bits = 3'd4;
    endcase
  end

  always @(*) begin
    tx_o            = 1'b1;
    s_sample_data   = 1'b0;
    tx_ready_o      = 1'b0;
    s_baudgen_en    = 1'b0;
    s_fsm_d         = s_fsm_q;
    s_parity_bit_d  = s_parity_bit_q;
    s_reg_bit_cnt_d = s_reg_bit_cnt_q;
    s_reg_data_d    = {1'b1, s_reg_data_q[7:1]};
    case (s_fsm_q)
      IDLE: begin
        if (cfg_en_i) tx_ready_o = 1'b1;
        if (tx_valid_i) begin
          s_fsm_d       = START_BIT;
          s_sample_data = 1'b1;
          s_reg_data_d  = tx_data_i;
        end
      end
      START_BIT: begin
        tx_o           = 1'b0;
        s_parity_bit_d = 1'b0;
        s_baudgen_en   = 1'b1;
        if (s_bit_done) s_fsm_d = DATA;
      end
      DATA: begin
        tx_o           = s_reg_data_q[0];
        s_baudgen_en   = 1'b1;
        s_parity_bit_d = s_parity_bit_q ^ s_reg_data_q[0];
        if (s_bit_done) begin
          if (s_reg_bit_cnt_q == s_target_bits) begin
            s_reg_bit_cnt_d = 'h0;
            if (cfg_parity_en_i) begin
              s_fsm_d = PARITY;
            end else begin
              s_fsm_d = STOP_BIT_FIRST;
            end
          end else begin
            s_reg_bit_cnt_d = s_reg_bit_cnt_q + 1;
            s_sample_data   = 1'b1;
          end
        end
      end
      PARITY: begin
        case (cfg_parity_sel_i)
          2'b00: tx_o = ~s_parity_bit_q;
          2'b01: tx_o = s_parity_bit_q;
          2'b10: tx_o = 1'b0;
          2'b11: tx_o = 1'b1;
        endcase

        s_baudgen_en = 1'b1;
        if (s_bit_done) s_fsm_d = STOP_BIT_FIRST;
      end
      STOP_BIT_FIRST: begin
        tx_o         = 1'b1;
        s_baudgen_en = 1'b1;
        if (s_bit_done) begin
          if (cfg_stop_bits_i) s_fsm_d = STOP_BIT_LAST;
          else s_fsm_d = IDLE;
        end
      end
      STOP_BIT_LAST: begin
        tx_o         = 1'b1;
        s_baudgen_en = 1'b1;
        if (s_bit_done) begin
          s_fsm_d = IDLE;
        end
      end
      default: s_fsm_d = IDLE;
    endcase
  end

  always @(posedge clk_i, negedge rst_n_i) begin
    if (~rst_n_i) begin
      s_fsm_q         <= IDLE;
      s_reg_data_q    <= 8'hFF;
      s_reg_bit_cnt_q <= 'h0;
      s_parity_bit_q  <= 1'b0;
    end else begin
      if (s_bit_done) begin
        s_parity_bit_q <= s_parity_bit_d;
      end

      if (s_sample_data) begin
        s_reg_data_q <= s_reg_data_d;
      end

      s_reg_bit_cnt_q <= s_reg_bit_cnt_d;
      if (cfg_en_i) s_fsm_q <= s_fsm_d;
      else s_fsm_q <= IDLE;
    end
  end

  always @(posedge clk_i, negedge rst_n_i) begin
    if (~rst_n_i) begin
      baud_cnt   <= 'h0;
      s_bit_done <= 1'b0;
    end else begin
      if (s_baudgen_en) begin
        if (baud_cnt == cfg_div_i) begin
          baud_cnt   <= 'h0;
          s_bit_done <= 1'b1;
        end else begin
          baud_cnt   <= baud_cnt + 1;
          s_bit_done <= 1'b0;
        end
      end else begin
        baud_cnt   <= 'h0;
        s_bit_done <= 1'b0;
      end
    end
  end

endmodule

// Copyright 2017 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the “License”); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an “AS IS” BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// -- Adaptable modifications are redistributed under compatible License --
//
// Copyright (c) 2023-2024 Miao Yuchi <miaoyuchi@ict.ac.cn>
// uart is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module apb4_uart #(
    parameter FIFO_DEPTH     = 32,
    parameter LOG_FIFO_DEPTH = $clog2(FIFO_DEPTH)
) (
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
    input             uart_rx_i,
    output            uart_tx_o,
    output            irq_o
);

  wire [3:0] s_apb4_addr;
  wire s_apb4_wr_hdshk, s_apb4_rd_hdshk;
  wire [`UART_LCR_WIDTH-1:0] s_uart_lcr_d, s_uart_lcr_q;
  wire s_uart_lcr_en;
  wire [`UART_DIV_WIDTH-1:0] s_uart_div_d, s_uart_div_q;
  wire s_uart_div_en;
  wire [`UART_FCR_WIDTH-1:0] s_uart_fcr_d, s_uart_fcr_q;
  wire                       s_uart_fcr_en;
  reg  [`UART_LSR_WIDTH-1:0] s_uart_lsr_d;
  wire [`UART_LSR_WIDTH-1:0] s_uart_lsr_q;
  wire s_bit_stb, s_bit_pen, s_bit_rf_clr, s_bit_tf_clr;
  wire s_bit_pe, s_bit_thre;
  wire [1:0] s_bit_wls, s_bit_ps, s_bit_rx_trg_levl;
  wire [2:0] s_bit_ie;
  reg        s_clr_int;
  wire       s_parity_err;
  reg        s_tx_push_valid;
  wire       s_tx_push_ready;
  wire s_tx_empty, s_tx_full;
  wire s_tx_pop_valid, s_tx_pop_ready;
  wire s_rx_push_valid, s_rx_push_ready, s_rx_empty, s_rx_full;
  wire       s_rx_pop_valid;
  reg        s_rx_pop_ready;
  wire [2:0] s_lsr_ip;
  reg  [7:0] s_tx_push_data;
  wire [7:0] s_tx_pop_data, s_rx_push_data;
  wire [8:0] s_rx_pop_data;
  wire [LOG_FIFO_DEPTH:0] s_tx_elem, s_rx_elem;

  assign s_apb4_addr       = paddr[5:2];
  assign s_apb4_wr_hdshk   = psel && penable && pwrite;
  assign s_apb4_rd_hdshk   = psel && penable && (~pwrite);
  assign pready            = 1'b1;
  assign pslverr           = 1'b0;

  assign s_bit_ie          = s_uart_lcr_q[2:0];
  assign s_bit_wls         = s_uart_lcr_q[4:3];
  assign s_bit_stb         = s_uart_lcr_q[5];
  assign s_bit_pen         = s_uart_lcr_q[6];
  assign s_bit_ps          = s_uart_lcr_q[8:7];

  assign s_bit_rf_clr      = s_uart_fcr_q[0];
  assign s_bit_tf_clr      = s_uart_fcr_q[1];
  assign s_bit_rx_trg_levl = s_uart_fcr_q[3:2];

  assign s_bit_pe          = s_uart_lsr_q[4];
  assign s_bit_thre        = s_uart_lsr_q[5];

  assign s_uart_lcr_en     = s_apb4_wr_hdshk && s_apb4_addr == `UART_LCR;
  assign s_uart_lcr_d      = pwdata[`UART_LCR_WIDTH-1:0];
  dffer #(`UART_LCR_WIDTH) u_uart_lcr_dffer (
      pclk,
      presetn,
      s_uart_lcr_en,
      s_uart_lcr_d,
      s_uart_lcr_q
  );

  assign s_uart_div_en = s_apb4_wr_hdshk && s_apb4_addr == `UART_DIV;
  assign s_uart_div_d  = pwdata[`UART_DIV_WIDTH-1:0];
  dfferc #(`UART_DIV_WIDTH, `UART_DIV_MIN_VAL) u_uart_div_dfferc (
      pclk,
      presetn,
      s_uart_div_en,
      s_uart_div_d,
      s_uart_div_q
  );

  always @(*) begin
    s_tx_push_valid = 1'b0;
    s_tx_push_data  = 8'd0;
    if (s_apb4_wr_hdshk && s_apb4_addr == `UART_TRX) begin
      s_tx_push_valid = 1'b1;
      s_tx_push_data  = pwdata[`UART_TRX_WIDTH-1:0];
    end
  end

  assign s_uart_fcr_en = s_apb4_wr_hdshk && s_apb4_addr == `UART_FCR;
  assign s_uart_fcr_d  = pwdata[`UART_FCR_WIDTH-1:0];
  dffer #(`UART_FCR_WIDTH) u_uart_fcr_dffer (
      pclk,
      presetn,
      s_uart_fcr_en,
      s_uart_fcr_d,
      s_uart_fcr_q
  );

  always @(*) begin
    s_uart_lsr_d[2:0] = s_lsr_ip;
    s_uart_lsr_d[3]   = s_rx_pop_valid;
    s_uart_lsr_d[4]   = s_rx_pop_data[8];
    s_uart_lsr_d[5]   = ~(|s_tx_elem);
    s_uart_lsr_d[6]   = s_tx_pop_ready & ~(|s_tx_elem);
    s_uart_lsr_d[7]   = s_rx_empty;
    s_uart_lsr_d[8]   = s_tx_full;
  end
  dffrc #(`UART_LSR_WIDTH, `UART_LSR_RESET_VAL) u_uart_lsr_dffrc (
      pclk,
      presetn,
      s_uart_lsr_d,
      s_uart_lsr_q
  );

  always @(*) begin
    prdata         = 32'd0;
    s_rx_pop_ready = 1'b0;
    s_clr_int      = 1'b0;
    if (s_apb4_rd_hdshk) begin
      case (s_apb4_addr)
        `UART_LCR: prdata[`UART_LCR_WIDTH-1:0] = s_uart_lcr_q;
        `UART_DIV: prdata[`UART_DIV_WIDTH-1:0] = s_uart_div_q;
        `UART_TRX: begin
          s_rx_pop_ready              = 1'b1;
          prdata[`UART_TRX_WIDTH-1:0] = s_rx_pop_data[7:0];
        end
        `UART_LSR: begin
          s_clr_int                   = 1'b1;
          prdata[`UART_LSR_WIDTH-1:0] = s_uart_lsr_q;
        end
        default:   prdata = 32'd0;
      endcase
    end
  end

  assign s_tx_push_ready = ~s_tx_full;
  assign s_tx_pop_valid  = ~s_tx_empty;
  fifo #(
      .DATA_WIDTH  (8),
      .BUFFER_DEPTH(FIFO_DEPTH)
  ) u_tx_fifo (
      .clk_i  (pclk),
      .rst_n_i(presetn),
      .flush_i(s_bit_tf_clr),
      .cnt_o  (s_tx_elem),
      .push_i (s_tx_push_valid),
      .full_o (s_tx_full),
      .dat_i  (s_tx_push_data),
      .pop_i  (s_tx_pop_ready),
      .empty_o(s_tx_empty),
      .dat_o  (s_tx_pop_data)
  );

  uart_tx u_uart_tx (
      .clk_i           (pclk),
      .rst_n_i         (presetn),
      .tx_o            (uart_tx_o),
      .busy_o          (),
      .cfg_en_i        (1'b1),
      .cfg_div_i       (s_uart_div_q[`UART_DIV_WIDTH-1:0]),
      .cfg_parity_en_i (s_bit_pen),
      .cfg_parity_sel_i(s_bit_ps),
      .cfg_bits_i      (s_bit_wls),
      .cfg_stop_bits_i (s_bit_stb),
      .tx_data_i       (s_tx_pop_data),
      .tx_valid_i      (s_tx_pop_valid),
      .tx_ready_o      (s_tx_pop_ready)
  );

  assign s_rx_push_ready = ~s_rx_full;
  assign s_rx_pop_valid  = ~s_rx_empty;
  fifo #(
      .DATA_WIDTH  (9),
      .BUFFER_DEPTH(FIFO_DEPTH)
  ) u_rx_fifo (
      .clk_i  (pclk),
      .rst_n_i(presetn),
      .flush_i(s_bit_rf_clr),
      .cnt_o  (s_rx_elem),
      .push_i (s_rx_push_valid),
      .full_o (s_rx_full),
      .dat_i  ({s_parity_err, s_rx_push_data}),
      .pop_i  (s_rx_pop_ready),
      .empty_o(s_rx_empty),
      .dat_o  (s_rx_pop_data)
  );

  uart_rx u_uart_rx (
      .clk_i           (pclk),
      .rst_n_i         (presetn),
      .rx_i            (uart_rx_i),
      .busy_o          (),
      .cfg_en_i        (1'b1),
      .cfg_div_i       (s_uart_div_q[`UART_DIV_WIDTH-1:0]),
      .cfg_parity_en_i (s_bit_pen),
      .cfg_parity_sel_i(s_bit_ps),
      .cfg_bits_i      (s_bit_wls),
      .err_o           (s_parity_err),
      .err_clr_i       (1'b1),
      .rx_data_o       (s_rx_push_data),
      .rx_valid_o      (s_rx_push_valid),
      .rx_ready_i      (s_rx_push_ready)
  );

  uart_irq #(
      .FIFO_DEPTH(FIFO_DEPTH)
  ) u_uart_irq (
      .clk_i      (pclk),
      .rst_n_i    (presetn),
      .clr_int_i  (s_clr_int),
      .irq_en_i   (s_bit_ie),
      .thre_i     (s_bit_thre),
      .cti_i      (1'b0),
      .pe_i       (s_bit_pe),
      .rx_elem_i  (s_rx_elem),
      .tx_elem_i  (s_tx_elem),
      .trg_level_i(s_bit_rx_trg_levl),
      .ip_o       (s_lsr_ip),
      .irq_o      (irq_o)
  );
endmodule

