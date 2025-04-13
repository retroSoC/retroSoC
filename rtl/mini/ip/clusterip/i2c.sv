// Copyright (c) 2023-2024 Miao Yuchi <miaoyuchi@ict.ac.cn>
// i2c is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef INC_I2C_DEF_SV
`define INC_I2C_DEF_SV

/* register mapping
 * I2C_CTRL:
 * BITS:   | 31:8 | 7  | 6   | 5:0  |
 * FIELDS: | RES  | EN | IEN | RES  |
 * PERMS:  | NONE | RW | RW  | NONE |
 * ----------------------------------------------------------
 * I2C_PSCR:
 * BITS:   | 31:16 | 15:0 |
 * FIELDS: | RES   | PSCR |
 * PERMS:  | NONE  | RW   |
 * ----------------------------------------------------------
 * I2C_TXR:
 * BITS:   | 31:8 | 7:0  |
 * FIELDS: | RES  | DATA |
 * PERMS:  | NONE | RW   |
 * ----------------------------------------------------------
 * I2C_RXR:
 * BITS:   | 31:8 | 7:0  |
 * FIELDS: | RES  | DATA |
 * PERMS:  | NONE | RO   |
 * ----------------------------------------------------------
 * I2C_CMD:
 * BITS:   | 31:8 | 7   | 6   | 5  | 4  | 3   | 2:1  | 0    |
 * FIELDS: | RES  | STA | STO | RD | WR | ACK | RES  | IACK |
 * PERMS:  | NONE | WO  | WO  | WO | WO | WO  | NONE | WO   |
 * ----------------------------------------------------------
 * I2C_SR:
 * BITS:   | 31:8 | 7   | 6   | 5  | 4:2  | 1   | 0  |
 * FIELDS: | RES  | RXK | BSY | AL | RES  | TIP | IF |
 * PERMS:  | NONE | RO  | RO  | RO | NONE | RO  | RO |
 * ----------------------------------------------------------
*/

// verilog_format: off
`define I2C_CTRL 4'b0000 // BASEADDR + 0x00
`define I2C_PSCR 4'b0001 // BASEADDR + 0x04
`define I2C_TXR  4'b0010 // BASEADDR + 0x08
`define I2C_RXR  4'b0011 // BASEADDR + 0x0C
`define I2C_CMD  4'b0100 // BASEADDR + 0x10
`define I2C_SR   4'b0101 // BASEADDR + 0x14

`define I2C_CTRL_ADDR {26'b0, `I2C_CTRL, 2'b00}
`define I2C_PSCR_ADDR {26'b0, `I2C_PSCR, 2'b00}
`define I2C_TXR_ADDR  {26'b0, `I2C_TXR , 2'b00}
`define I2C_RXR_ADDR  {26'b0, `I2C_RXR , 2'b00}
`define I2C_CMD_ADDR  {26'b0, `I2C_CMD , 2'b00}
`define I2C_SR_ADDR   {26'b0, `I2C_SR  , 2'b00}

`define I2C_CTRL_WIDTH 8
`define I2C_PSCR_WIDTH 16
`define I2C_TXR_WIDTH  8
`define I2C_RXR_WIDTH  8
`define I2C_CMD_WIDTH  8
`define I2C_SR_WIDTH   8

`define I2C_PSCR_MAX_VAL {(`I2C_PSCR_WIDTH){1'b1}}

`define I2C_CMD_NOP   4'b0000
`define I2C_CMD_START 4'b0001
`define I2C_CMD_STOP  4'b0010
`define I2C_CMD_WRITE 4'b0100
`define I2C_CMD_READ  4'b1000
// verilog_format: on
`endif



/////////////////////////////////////////////////////////////////////
////                                                             ////
////  WISHBONE rev.B2 compliant I2C Master bit-controller        ////
////                                                             ////
////                                                             ////
////  Author: Richard Herveille                                  ////
////          richard@asics.ws                                   ////
////          www.asics.ws                                       ////
////                                                             ////
////  Downloaded from: http://www.opencores.org/projects/i2c/    ////
////                                                             ////
/////////////////////////////////////////////////////////////////////
////                                                             ////
//// Copyright (C) 2001 Richard Herveille                        ////
////                    richard@asics.ws                         ////
////                                                             ////
//// This source file may be used and distributed without        ////
//// restriction provided that this copyright statement is not   ////
//// removed from the file and that any derivative work contains ////
//// the original copyright notice and the associated disclaimer.////
////                                                             ////
////     THIS SOFTWARE IS PROVIDED ``AS IS'' AND WITHOUT ANY     ////
//// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED   ////
//// TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS   ////
//// FOR A PARTICULAR PURPOSE. IN NO EVENT SHALL THE AUTHOR      ////
//// OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,         ////
//// INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES    ////
//// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE   ////
//// GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR        ////
//// BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF  ////
//// LIABILITY, WHETHER IN  CONTRACT, STRICT LIABILITY, OR TORT  ////
//// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT  ////
//// OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE         ////
//// POSSIBILITY OF SUCH DAMAGE.                                 ////
////                                                             ////
/////////////////////////////////////////////////////////////////////
//
/////////////////////////////////////
// Bit controller section
/////////////////////////////////////
//
// Translate simple commands into SCL/SDA transitions
// Each command has 5 states, A/B/C/D/idle
//
// start:	SCL	~~~~~~~~~~\____
//	SDA	~~~~~~~~\______
//		 x | A | B | C | D | i
//
// repstart	SCL	____/~~~~\___
//	SDA	__/~~~\______
//		 x | A | B | C | D | i
//
// stop	SCL	____/~~~~~~~~
//	SDA	==\____/~~~~~
//		 x | A | B | C | D | i
//
//- write	SCL	____/~~~~\____
//	SDA	==X=========X=
//		 x | A | B | C | D | i
//
//- read	SCL	____/~~~~\____
//	SDA	XXXX=====XXXX
//		 x | A | B | C | D | i
//

// Timing:     Normal mode      Fast mode
///////////////////////////////////////////////////////////////////////
// Fscl        100KHz           400KHz
// Th_scl      4.0us            0.6us   High period of SCL
// Tl_scl      4.7us            1.3us   Low period of SCL
// Tsu:sta     4.7us            0.6us   setup time for a repeated start condition
// Tsu:sto     4.0us            0.6us   setup time for a stop conditon
// Tbuf        4.7us            1.3us   Bus free time between a stop and start condition
//
// -- Adaptable modifications are redistributed under compatible License --
//
// Copyright (c) 2023-2024 Miao Yuchi <miaoyuchi@ict.ac.cn>
// i2c is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module i2c_master_bit_ctrl (
    input             clk_i,      // system clock
    input             rst_n_i,    // asynchronous active low reset
    input             ena_i,      // core enable signal
    input      [15:0] clk_cnt_i,  // clock prescale value
    input      [ 3:0] cmd_i,      // command (from byte controller)
    output reg        cmd_ack_o,  // command complete acknowledge
    output reg        busy_o,     // i2c bus busy_o
    output reg        al_o,       // i2c bus arbitration lost
    input             dat_i,
    output reg        dat_o,
    input             scl_i,      // i2c clock line input
    output            scl_o,      // i2c clock line output
    output reg        scl_dir_o,  // i2c clock line output enable (active low)
    input             sda_i,      // i2c data line input
    output            sda_o,      // i2c data line output
    output reg        sda_dir_o   // i2c data line output enable (active low)
);

  reg [1:0] r_cSCL, r_cSDA;  // capture SCL and SDA
  reg [2:0] r_fSCL, r_fSDA;  // SCL and SDA filter inputs
  reg r_sSCL, r_sSDA;  // filtered and synchronized SCL and SDA inputs
  reg r_dSCL, r_dSDA;  // delayed versions of r_sSCL and r_sSDA
  reg        r_dscl_dir;  // delayed scl_dir_o
  reg        r_sda_chk;  // check SDA output (Multi-master arbitration)
  reg        r_clk_en;  // clock generation signals
  reg        r_slave_wait;  // slave inserts wait states
  reg [15:0] r_cnt;  // clock divider counter (synthesis)
  reg [13:0] r_filter_cnt;  // clock divider for filter


  // state machine variable
  reg [17:0] r_c_state;
  // whenever the slave is not ready it can delay the cycle by pulling SCL low
  // delay scl_dir_o
  always @(posedge clk_i) r_dscl_dir <= #1 scl_dir_o;

  // r_slave_wait is asserted when master wants to drive SCL high, but the slave pulls it low
  // r_slave_wait remains asserted until the slave releases SCL
  always @(posedge clk_i or negedge rst_n_i)
    if (!rst_n_i) r_slave_wait <= #1 1'b0;
    else r_slave_wait <= #1 (scl_dir_o & ~r_dscl_dir & ~r_sSCL) | (r_slave_wait & ~r_sSCL);
  // scl_dir_o & ~r_dscl_dir mean scl_dir rise edge trigger

  // master drives SCL high, but another master pulls it low
  // master start counting down its low cycle now (clock synchronization)
  wire s_scl_sync = r_dSCL & ~r_sSCL & scl_dir_o;
  // r_dSCL & ~r_sSCL mean scl fall edge trigger

  // generate clk_i enable signal
  always @(posedge clk_i or negedge rst_n_i)
    if (~rst_n_i) begin
      r_cnt    <= #1 16'h0;
      r_clk_en <= #1 1'b1;
    end else if (~|r_cnt || !ena_i || s_scl_sync) begin
      r_cnt    <= #1 clk_cnt_i;
      r_clk_en <= #1 1'b1;
    end else if (r_slave_wait) begin
      r_cnt    <= #1 r_cnt;
      r_clk_en <= #1 1'b0;
    end else begin
      r_cnt    <= #1 r_cnt - 16'h1;
      r_clk_en <= #1 1'b0;
    end


  // generate bus status controller
  // capture SDA and SCL
  // reduce metastability risk
  always @(posedge clk_i or negedge rst_n_i)
    if (!rst_n_i) begin
      r_cSCL <= #1 2'b00;
      r_cSDA <= #1 2'b00;
    end else begin
      r_cSCL <= #1{r_cSCL[0], scl_i};
      r_cSDA <= #1{r_cSDA[0], sda_i};
    end


  // filter SCL and SDA signals; (attempt to) remove glitches
  always @(posedge clk_i or negedge rst_n_i)
    if (!rst_n_i) r_filter_cnt <= #1 14'h0;
    else if (!ena_i) r_filter_cnt <= #1 14'h0;
    else if (~|r_filter_cnt) r_filter_cnt <= #1 clk_cnt_i >> 2;  //16x I2C bus frequency
    else r_filter_cnt <= #1 r_filter_cnt - 1;


  always @(posedge clk_i or negedge rst_n_i)
    if (!rst_n_i) begin
      r_fSCL <= #1 3'b111;
      r_fSDA <= #1 3'b111;
    end else if (~|r_filter_cnt) begin
      r_fSCL <= #1{r_fSCL[1:0], r_cSCL[1]};
      r_fSDA <= #1{r_fSDA[1:0], r_cSDA[1]};
    end


  // generate filtered SCL and SDA signals
  always @(posedge clk_i or negedge rst_n_i)
    if (~rst_n_i) begin
      r_sSCL <= #1 1'b1;
      r_sSDA <= #1 1'b1;

      r_dSCL <= #1 1'b1;
      r_dSDA <= #1 1'b1;
    end else begin  // every 2 bits of 3 bits calc bit-and
      r_sSCL <= #1 &r_fSCL[2:1] | &r_fSCL[1:0] | (r_fSCL[2] & r_fSCL[0]);
      r_sSDA <= #1 &r_fSDA[2:1] | &r_fSDA[1:0] | (r_fSDA[2] & r_fSDA[0]);

      r_dSCL <= #1 r_sSCL;
      r_dSDA <= #1 r_sSDA;
    end

  // detect start condition => detect falling edge on SDA while SCL is high
  // detect stop condition => detect rising edge on SDA while SCL is high
  reg r_sta_cond;
  reg r_sto_cond;
  always @(posedge clk_i or negedge rst_n_i)
    if (~rst_n_i) begin
      r_sta_cond <= #1 1'b0;
      r_sto_cond <= #1 1'b0;
    end else begin
      r_sta_cond <= #1 ~r_sSDA & r_dSDA & r_sSCL;
      r_sto_cond <= #1 r_sSDA & ~r_dSDA & r_sSCL;
    end


  // generate i2c bus busy_o signal
  always @(posedge clk_i or negedge rst_n_i)
    if (!rst_n_i) busy_o <= #1 1'b0;
    else busy_o <= #1 (r_sta_cond | busy_o) & ~r_sto_cond;


  // generate arbitration lost signal
  // aribitration lost when:
  // 1) master drives SDA high, but the i2c bus is low
  // 2) stop detected while not requested
  reg r_cmd_stop;
  always @(posedge clk_i or negedge rst_n_i)
    if (~rst_n_i) r_cmd_stop <= #1 1'b0;
    else if (r_clk_en) r_cmd_stop <= #1 cmd_i == `I2C_CMD_STOP;

  always @(posedge clk_i or negedge rst_n_i)
    if (~rst_n_i) al_o <= #1 1'b0;
    else al_o <= #1 (r_sda_chk & ~r_sSDA & sda_dir_o) | (|r_c_state & r_sto_cond & ~r_cmd_stop);

  // generate dat_o signal (store SDA on rising edge of SCL)
  always @(posedge clk_i) if (r_sSCL & ~r_dSCL) dat_o <= #1 r_sSDA;


  // generate statemachine
  // nxt_state decoder
  parameter [17:0] idle = 18'b0_0000_0000_0000_0000;
  parameter [17:0] start_a = 18'b0_0000_0000_0000_0001;
  parameter [17:0] start_b = 18'b0_0000_0000_0000_0010;
  parameter [17:0] start_c = 18'b0_0000_0000_0000_0100;
  parameter [17:0] start_d = 18'b0_0000_0000_0000_1000;
  parameter [17:0] start_e = 18'b0_0000_0000_0001_0000;
  parameter [17:0] stop_a = 18'b0_0000_0000_0010_0000;
  parameter [17:0] stop_b = 18'b0_0000_0000_0100_0000;
  parameter [17:0] stop_c = 18'b0_0000_0000_1000_0000;
  parameter [17:0] stop_d = 18'b0_0000_0001_0000_0000;
  parameter [17:0] rd_a = 18'b0_0000_0010_0000_0000;
  parameter [17:0] rd_b = 18'b0_0000_0100_0000_0000;
  parameter [17:0] rd_c = 18'b0_0000_1000_0000_0000;
  parameter [17:0] rd_d = 18'b0_0001_0000_0000_0000;
  parameter [17:0] wr_a = 18'b0_0010_0000_0000_0000;
  parameter [17:0] wr_b = 18'b0_0100_0000_0000_0000;
  parameter [17:0] wr_c = 18'b0_1000_0000_0000_0000;
  parameter [17:0] wr_d = 18'b1_0000_0000_0000_0000;

  always @(posedge clk_i or negedge rst_n_i)
    if (!rst_n_i) begin
      r_c_state <= #1 idle;
      cmd_ack_o <= #1 1'b0;
      scl_dir_o <= #1 1'b1;
      sda_dir_o <= #1 1'b1;
      r_sda_chk <= #1 1'b0;
    end else if (al_o) begin
      r_c_state <= #1 idle;
      cmd_ack_o <= #1 1'b0;
      scl_dir_o <= #1 1'b1;
      sda_dir_o <= #1 1'b1;
      r_sda_chk <= #1 1'b0;
    end else begin
      cmd_ack_o <= #1 1'b0;  // default no command acknowledge + assert cmd_ack_o only 1clk cycle

      if (r_clk_en)
        case (r_c_state)  // synopsys full_case parallel_case
          // idle state
          idle: begin
            case (cmd_i)  // synopsys full_case parallel_case
              `I2C_CMD_START: r_c_state <= #1 start_a;
              `I2C_CMD_STOP:  r_c_state <= #1 stop_a;
              `I2C_CMD_WRITE: r_c_state <= #1 wr_a;
              `I2C_CMD_READ:  r_c_state <= #1 rd_a;
              default:        r_c_state <= #1 idle;
            endcase

            scl_dir_o <= #1 scl_dir_o;  // keep SCL in same state
            sda_dir_o <= #1 sda_dir_o;  // keep SDA in same state
            r_sda_chk <= #1 1'b0;  // don't check SDA output
          end

          start_a: begin
            r_c_state <= #1 start_b;
            scl_dir_o <= #1 scl_dir_o;  // keep SCL in same state
            sda_dir_o <= #1 1'b1;  // set SDA high
            r_sda_chk <= #1 1'b0;  // don't check SDA output
          end

          start_b: begin
            r_c_state <= #1 start_c;
            scl_dir_o <= #1 1'b1;  // set SCL high
            sda_dir_o <= #1 1'b1;  // keep SDA high
            r_sda_chk <= #1 1'b0;  // don't check SDA output
          end

          start_c: begin
            r_c_state <= #1 start_d;
            scl_dir_o <= #1 1'b1;  // keep SCL high
            sda_dir_o <= #1 1'b0;  // set SDA low
            r_sda_chk <= #1 1'b0;  // don't check SDA output
          end

          start_d: begin
            r_c_state <= #1 start_e;
            scl_dir_o <= #1 1'b1;  // keep SCL high
            sda_dir_o <= #1 1'b0;  // keep SDA low
            r_sda_chk <= #1 1'b0;  // don't check SDA output
          end

          start_e: begin
            r_c_state <= #1 idle;
            cmd_ack_o <= #1 1'b1;
            scl_dir_o <= #1 1'b0;  // set SCL low
            sda_dir_o <= #1 1'b0;  // keep SDA low
            r_sda_chk <= #1 1'b0;  // don't check SDA output
          end

          stop_a: begin
            r_c_state <= #1 stop_b;
            scl_dir_o <= #1 1'b0;  // keep SCL low
            sda_dir_o <= #1 1'b0;  // set SDA low
            r_sda_chk <= #1 1'b0;  // don't check SDA output
          end

          stop_b: begin
            r_c_state <= #1 stop_c;
            scl_dir_o <= #1 1'b1;  // set SCL high
            sda_dir_o <= #1 1'b0;  // keep SDA low
            r_sda_chk <= #1 1'b0;  // don't check SDA output
          end

          stop_c: begin
            r_c_state <= #1 stop_d;
            scl_dir_o <= #1 1'b1;  // keep SCL high
            sda_dir_o <= #1 1'b0;  // keep SDA low
            r_sda_chk <= #1 1'b0;  // don't check SDA output
          end

          stop_d: begin
            r_c_state <= #1 idle;
            cmd_ack_o <= #1 1'b1;
            scl_dir_o <= #1 1'b1;  // keep SCL high
            sda_dir_o <= #1 1'b1;  // set SDA high
            r_sda_chk <= #1 1'b0;  // don't check SDA output
          end

          rd_a: begin
            r_c_state <= #1 rd_b;
            scl_dir_o <= #1 1'b0;  // keep SCL low
            sda_dir_o <= #1 1'b1;  // tri-state SDA
            r_sda_chk <= #1 1'b0;  // don't check SDA output
          end

          rd_b: begin
            r_c_state <= #1 rd_c;
            scl_dir_o <= #1 1'b1;  // set SCL high
            sda_dir_o <= #1 1'b1;  // keep SDA tri-stated
            r_sda_chk <= #1 1'b0;  // don't check SDA output
          end

          rd_c: begin
            r_c_state <= #1 rd_d;
            scl_dir_o <= #1 1'b1;  // keep SCL high
            sda_dir_o <= #1 1'b1;  // keep SDA tri-stated
            r_sda_chk <= #1 1'b0;  // don't check SDA output
          end

          rd_d: begin
            r_c_state <= #1 idle;
            cmd_ack_o <= #1 1'b1;
            scl_dir_o <= #1 1'b0;  // set SCL low
            sda_dir_o <= #1 1'b1;  // keep SDA tri-stated
            r_sda_chk <= #1 1'b0;  // don't check SDA output
          end

          wr_a: begin
            r_c_state <= #1 wr_b;
            scl_dir_o <= #1 1'b0;  // keep SCL low
            sda_dir_o <= #1 dat_i;  // set SDA
            r_sda_chk <= #1 1'b0;  // don't check SDA output (SCL low)
          end

          wr_b: begin
            r_c_state <= #1 wr_c;
            scl_dir_o <= #1 1'b1;  // set SCL high
            sda_dir_o <= #1 dat_i;  // keep SDA
            r_sda_chk <= #1 1'b0;  // don't check SDA output yet
            // allow some time for SDA and SCL to settle
          end

          wr_c: begin
            r_c_state <= #1 wr_d;
            scl_dir_o <= #1 1'b1;  // keep SCL high
            sda_dir_o <= #1 dat_i;
            r_sda_chk <= #1 1'b1;  // check SDA output
          end

          wr_d: begin
            r_c_state <= #1 idle;
            cmd_ack_o <= #1 1'b1;
            scl_dir_o <= #1 1'b0;  // set SCL low
            sda_dir_o <= #1 dat_i;
            r_sda_chk <= #1 1'b0;  // don't check SDA output (SCL low)
          end

        endcase
    end

  // assign scl and sda output (always zero)
  assign scl_o = 1'b0;
  assign sda_o = 1'b0;

endmodule



/////////////////////////////////////////////////////////////////////
////                                                             ////
////  WISHBONE rev.B2 compliant I2C Master byte-controller       ////
////                                                             ////
////                                                             ////
////  Author: Richard Herveille                                  ////
////          richard@asics.ws                                   ////
////          www.asics.ws                                       ////
////                                                             ////
////  Downloaded from: http://www.opencores.org/projects/i2c/    ////
////                                                             ////
/////////////////////////////////////////////////////////////////////
////                                                             ////
//// Copyright (C) 2001 Richard Herveille                        ////
////                    richard@asics.ws                         ////
////                                                             ////
//// This source file may be used and distributed without        ////
//// restriction provided that this copyright statement is not   ////
//// removed from the file and that any derivative work contains ////
//// the original copyright notice and the associated disclaimer.////
////                                                             ////
////     THIS SOFTWARE IS PROVIDED ``AS IS'' AND WITHOUT ANY     ////
//// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED   ////
//// TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS   ////
//// FOR A PARTICULAR PURPOSE. IN NO EVENT SHALL THE AUTHOR      ////
//// OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,         ////
//// INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES    ////
//// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE   ////
//// GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR        ////
//// BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF  ////
//// LIABILITY, WHETHER IN  CONTRACT, STRICT LIABILITY, OR TORT  ////
//// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT  ////
//// OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE         ////
//// POSSIBILITY OF SUCH DAMAGE.                                 ////
////                                                             ////
/////////////////////////////////////////////////////////////////////
//
// -- Adaptable modifications are redistributed under compatible License --
//
// Copyright (c) 2023-2024 Miao Yuchi <miaoyuchi@ict.ac.cn>
// i2c is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module i2c_master_byte_ctrl (
    input             clk_i,
    input             rst_n_i,
    input             ena_i,
    input      [15:0] clk_cnt_i,
    input             start_i,
    input             stop_i,
    input             read_i,
    input             write_i,
    input             ack_i,
    input      [ 7:0] dat_i,
    output reg        cmd_ack_o,
    output reg        ack_o,
    output     [ 7:0] dat_o,
    output            i2c_busy_o,
    output            i2c_al_o,
    input             scl_i,
    output            scl_o,
    output            scl_dir_o,
    input             sda_i,
    output            sda_o,
    output            sda_dir_o
);

  // statemachine
  parameter [4:0] ST_IDLE = 5'b0_0000;
  parameter [4:0] ST_START = 5'b0_0001;
  parameter [4:0] ST_READ = 5'b0_0010;
  parameter [4:0] ST_WRITE = 5'b0_0100;
  parameter [4:0] ST_ACK = 5'b0_1000;
  parameter [4:0] ST_STOP = 5'b1_0000;

  // signals for bit_controller
  reg [3:0] core_cmd;
  reg       core_txd;
  wire core_ack, core_rxd;

  // signals for shift register
  reg [7:0] sr;  //8bit shift register
  reg shift, ld;

  // signals for state machine
  wire       go;
  reg  [2:0] dcnt;
  wire       cnt_done;

  // hookup bit_controller
  i2c_master_bit_ctrl u_i2c_master_bit_ctrl (
      .clk_i    (clk_i),
      .rst_n_i  (rst_n_i),
      .ena_i    (ena_i),
      .clk_cnt_i(clk_cnt_i),
      .cmd_i    (core_cmd),
      .cmd_ack_o(core_ack),
      .busy_o   (i2c_busy_o),
      .al_o     (i2c_al_o),
      .dat_i    (core_txd),
      .dat_o    (core_rxd),
      .scl_i    (scl_i),
      .scl_o    (scl_o),
      .scl_dir_o(scl_dir_o),
      .sda_i    (sda_i),
      .sda_o    (sda_o),
      .sda_dir_o(sda_dir_o)
  );

  // generate go-signal
  assign go    = (read_i | write_i | stop_i) & ~cmd_ack_o;

  // assign dat_o output to shift-register
  assign dat_o = sr;

  // generate shift register
  always @(posedge clk_i or negedge rst_n_i)
    if (!rst_n_i) sr <= #1 8'h0;
    else if (ld) sr <= #1 dat_i;
    else if (shift) sr <= #1{sr[6:0], core_rxd};  // tx and rx use one shift register

  // generate counter
  always @(posedge clk_i or negedge rst_n_i)
    if (!rst_n_i) dcnt <= #1 3'h0;
    else if (ld) dcnt <= #1 3'h7;
    else if (shift) dcnt <= #1 dcnt - 3'h1;

  assign cnt_done = ~(|dcnt);

  reg [4:0] c_state;
  always @(posedge clk_i or negedge rst_n_i)
    if (!rst_n_i) begin
      core_cmd  <= #1 `I2C_CMD_NOP;
      core_txd  <= #1 1'b0;
      shift     <= #1 1'b0;
      ld        <= #1 1'b0;
      cmd_ack_o <= #1 1'b0;
      c_state   <= #1 ST_IDLE;
      ack_o     <= #1 1'b0;
    end else if (i2c_al_o) begin
      core_cmd  <= #1 `I2C_CMD_NOP;
      core_txd  <= #1 1'b0;
      shift     <= #1 1'b0;
      ld        <= #1 1'b0;
      cmd_ack_o <= #1 1'b0;
      c_state   <= #1 ST_IDLE;
      ack_o     <= #1 1'b0;
    end else begin
      // initially reset all signals
      core_txd  <= #1 sr[7];
      shift     <= #1 1'b0;
      ld        <= #1 1'b0;
      cmd_ack_o <= #1 1'b0;

      case (c_state)  // synopsys full_case parallel_case
        ST_IDLE:
        if (go) begin
          if (start_i) begin
            c_state  <= #1 ST_START;
            core_cmd <= #1 `I2C_CMD_START;
          end else if (read_i) begin
            c_state  <= #1 ST_READ;
            core_cmd <= #1 `I2C_CMD_READ;
          end else if (write_i) begin
            c_state  <= #1 ST_WRITE;
            core_cmd <= #1 `I2C_CMD_WRITE;
          end else  // stop_i
          begin
            c_state  <= #1 ST_STOP;
            core_cmd <= #1 `I2C_CMD_STOP;
          end

          ld <= #1 1'b1;
        end

        ST_START:
        if (core_ack) begin
          if (read_i) begin
            c_state  <= #1 ST_READ;
            core_cmd <= #1 `I2C_CMD_READ;
          end else begin
            c_state  <= #1 ST_WRITE;
            core_cmd <= #1 `I2C_CMD_WRITE;
          end

          ld <= #1 1'b1;
        end

        ST_WRITE:
        if (core_ack)
          if (cnt_done) begin
            c_state  <= #1 ST_ACK;
            core_cmd <= #1 `I2C_CMD_READ;  // NOTE: read the ack
          end else begin
            c_state  <= #1 ST_WRITE;  // stay in same state
            core_cmd <= #1 `I2C_CMD_WRITE;  // write_i next bit
            shift    <= #1 1'b1;
          end

        ST_READ:
        if (core_ack) begin
          if (cnt_done) begin
            c_state  <= #1 ST_ACK;
            core_cmd <= #1 `I2C_CMD_WRITE;  // NOTE: write the ack
          end else begin
            c_state  <= #1 ST_READ;  // stay in same state
            core_cmd <= #1 `I2C_CMD_READ;  // read_i next bit
          end

          shift    <= #1 1'b1;
          core_txd <= #1 ack_i;
        end

        ST_ACK:
        if (core_ack) begin
          if (stop_i) begin
            c_state  <= #1 ST_STOP;
            core_cmd <= #1 `I2C_CMD_STOP;
          end else begin
            c_state   <= #1 ST_IDLE;
            core_cmd  <= #1 `I2C_CMD_NOP;

            // generate command acknowledge signal
            cmd_ack_o <= #1 1'b1;
          end

          // assign ack_o output to bit_controller_rxd (contains last received bit)
          ack_o    <= #1 core_rxd;

          core_txd <= #1 1'b1;
        end else core_txd <= #1 ack_i;

        ST_STOP:
        if (core_ack) begin
          c_state   <= #1 ST_IDLE;
          core_cmd  <= #1 `I2C_CMD_NOP;

          // generate command acknowledge signal
          cmd_ack_o <= #1 1'b1;
        end

      endcase
    end
endmodule



// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// -- Adaptable modifications are redistributed under compatible License --
//
// Copyright (c) 2023-2024 Miao Yuchi <miaoyuchi@ict.ac.cn>
// i2c is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module apb4_i2c (
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
    input             scl_i,
    output            scl_o,
    output            scl_dir_o,
    input             sda_i,
    output            sda_o,
    output            sda_dir_o,
    output            irq_o
);

  wire [3:0] s_apb4_addr;
  wire s_apb4_wr_hdshk, s_apb4_rd_hdshk;
  wire [ `I2C_SR_WIDTH-1:0] s_i2c_sr;
  wire [`I2C_RXR_WIDTH-1:0] s_i2c_rxr;
  wire [`I2C_CTRL_WIDTH-1:0] s_i2c_ctrl_d, s_i2c_ctrl_q;
  wire s_i2c_ctrl_en;
  wire [`I2C_PSCR_WIDTH-1:0] s_i2c_pscr_d, s_i2c_pscr_q;
  wire s_i2c_pscr_en;
  wire [`I2C_TXR_WIDTH-1:0] s_i2c_txr_d, s_i2c_txr_q;
  wire                      s_i2c_txr_en;
  reg  [`I2C_CMD_WIDTH-1:0] s_i2c_cmd_d;
  wire [`I2C_CMD_WIDTH-1:0] s_i2c_cmd_q;
  wire                      s_i2c_cmd_en;

  wire s_bit_ien, s_bit_en;
  wire s_bit_iack, s_bit_ack, s_bit_wr, s_bit_rd, s_bit_sto, s_bit_sta;
  wire s_i2c_done, s_i2c_irxack, s_i2c_busy, s_i2c_al;
  wire s_i2c_rxack_d, s_i2c_rxack_q;
  wire s_i2c_tip_d, s_i2c_tip_q;
  wire s_i2c_irq_d, s_i2c_irq_q;
  wire s_i2c_al_d, s_i2c_al_q;
  wire s_irq_d, s_irq_q;

  assign s_apb4_addr     = paddr[5:2];
  assign s_apb4_wr_hdshk = psel && penable && pwrite;
  assign s_apb4_rd_hdshk = psel && penable && (~pwrite);
  assign pready          = 1'b1;
  assign pslverr         = 1'b0;

  assign s_bit_ien       = s_i2c_ctrl_q[6];
  assign s_bit_en        = s_i2c_ctrl_q[7];

  assign s_bit_iack      = s_i2c_cmd_q[0];
  assign s_bit_ack       = s_i2c_cmd_q[3];
  assign s_bit_wr        = s_i2c_cmd_q[4];
  assign s_bit_rd        = s_i2c_cmd_q[5];
  assign s_bit_sto       = s_i2c_cmd_q[6];
  assign s_bit_sta       = s_i2c_cmd_q[7];

  assign s_i2c_sr[0]     = s_i2c_irq_q;
  assign s_i2c_sr[1]     = s_i2c_tip_q;
  assign s_i2c_sr[4:2]   = 3'b0;
  assign s_i2c_sr[5]     = s_i2c_al_q;
  assign s_i2c_sr[6]     = s_i2c_busy;
  assign s_i2c_sr[7]     = s_i2c_rxack_q;

  assign irq_o           = s_irq_q;

  assign s_i2c_ctrl_en   = s_apb4_wr_hdshk && s_apb4_addr == `I2C_CTRL;
  assign s_i2c_ctrl_d    = pwdata[`I2C_CTRL_WIDTH-1:0];
  dffer #(`I2C_CTRL_WIDTH) u_i2c_ctrl_dffer (
      pclk,
      presetn,
      s_i2c_ctrl_en,
      s_i2c_ctrl_d,
      s_i2c_ctrl_q
  );

  assign s_i2c_pscr_en = s_apb4_wr_hdshk && s_apb4_addr == `I2C_PSCR;
  assign s_i2c_pscr_d  = pwdata[`I2C_PSCR_WIDTH-1:0];
  dfferc #(`I2C_PSCR_WIDTH, `I2C_PSCR_MAX_VAL) u_i2c_pscr_dfferc (
      pclk,
      presetn,
      s_i2c_pscr_en,
      s_i2c_pscr_d,
      s_i2c_pscr_q
  );

  assign s_i2c_txr_en = s_apb4_wr_hdshk && s_apb4_addr == `I2C_TXR;
  assign s_i2c_txr_d  = pwdata[`I2C_TXR_WIDTH-1:0];
  dffer #(`I2C_TXR_WIDTH) u_i2c_txr_dffer (
      pclk,
      presetn,
      s_i2c_txr_en,
      s_i2c_txr_d,
      s_i2c_txr_q
  );

  assign s_i2c_cmd_en = (s_i2c_done | s_i2c_al) || (s_apb4_wr_hdshk && s_apb4_addr == `I2C_CMD && s_bit_en);
  always @(*) begin
    s_i2c_cmd_d      = s_i2c_cmd_q;
    s_i2c_cmd_d[2:0] = 3'b0;
    if (s_i2c_done | s_i2c_al) begin  // clear the cmd flag when trans done or err
      s_i2c_cmd_d[7:4] = 4'b0;
    end else if (s_apb4_wr_hdshk && s_apb4_addr == `I2C_CMD && s_bit_en) begin
      s_i2c_cmd_d = pwdata[`I2C_CMD_WIDTH-1:0];
    end
  end
  dffer #(`I2C_CMD_WIDTH) u_i2c_cmd_dffer (
      pclk,
      presetn,
      s_i2c_cmd_en,
      s_i2c_cmd_d,
      s_i2c_cmd_q
  );

  assign s_i2c_al_d = s_i2c_al | (s_i2c_al_q & (~s_bit_sta));
  dffr #(1) u_i2c_al_dffr (
      pclk,
      presetn,
      s_i2c_al_d,
      s_i2c_al_q
  );

  assign s_i2c_rxack_d = s_i2c_irxack;
  dffr #(1) u_i2c_rxack_dffr (
      pclk,
      presetn,
      s_i2c_rxack_d,
      s_i2c_rxack_q
  );

  assign s_i2c_tip_d = s_bit_wr | s_bit_rd;
  dffr #(1) u_i2c_tip_dffr (
      pclk,
      presetn,
      s_i2c_tip_d,
      s_i2c_tip_q
  );

  assign s_i2c_irq_d = (s_i2c_done | s_i2c_al | s_i2c_irq_q) & (~s_bit_iack);
  dffr #(1) u_i2c_irq_dffr (
      pclk,
      presetn,
      s_i2c_irq_d,
      s_i2c_irq_q
  );

  assign s_irq_d = s_i2c_irq_q && s_bit_ien;
  dffr #(1) u_irq_dffr (
      pclk,
      presetn,
      s_irq_d,
      s_irq_q
  );

  always @(*) begin
    prdata = 32'h0;
    if (s_apb4_rd_hdshk) begin
      case (s_apb4_addr)
        `I2C_CTRL: prdata[`I2C_CTRL_WIDTH-1:0] = s_i2c_ctrl_q;
        `I2C_PSCR: prdata[`I2C_PSCR_WIDTH-1:0] = s_i2c_pscr_q;
        `I2C_TXR:  prdata[`I2C_TXR_WIDTH-1:0] = s_i2c_txr_q;
        `I2C_RXR:  prdata[`I2C_RXR_WIDTH-1:0] = s_i2c_rxr;
        `I2C_SR:   prdata[`I2C_SR_WIDTH-1:0] = s_i2c_sr;
        default:   prdata = 32'h0;
      endcase
    end
  end

  i2c_master_byte_ctrl u_i2c_master_byte_ctrl (
      .clk_i     (pclk),
      .rst_n_i   (presetn),
      .ena_i     (s_bit_en),
      .clk_cnt_i (s_i2c_pscr_q),
      .start_i   (s_bit_sta),
      .stop_i    (s_bit_sto),
      .read_i    (s_bit_rd),
      .write_i   (s_bit_wr),
      .ack_i     (s_bit_ack),
      .dat_i     (s_i2c_txr_q),
      .cmd_ack_o (s_i2c_done),
      .ack_o     (s_i2c_irxack),
      .dat_o     (s_i2c_rxr),
      .i2c_busy_o(s_i2c_busy),
      .i2c_al_o  (s_i2c_al),
      .scl_i     (scl_i),
      .scl_o     (scl_o),
      .scl_dir_o (scl_dir_o),
      .sda_i     (sda_i),
      .sda_o     (sda_o),
      .sda_dir_o (sda_dir_o)
  );

endmodule
