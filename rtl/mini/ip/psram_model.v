/*
	Copyright 2020 Efabless Corp.

	Author: Mohamed Shalan (mshalan@efabless.com)
  adjusted for KianV-RISCV rv32ima tapeout by Hirosh Dabui <hirosh@dabui.de>
  modified for retroSoC by Yuchi Miao <miaoyuchi@ict.ac.cn>
	
	Licensed under the Apache License, Version 2.0 (the "License"); 
	you may not use this file except in compliance with the License. 
	You may obtain a copy of the License at:
	http://www.apache.org/licenses/LICENSE-2.0
	Unless required by applicable law or agreed to in writing, software 
	distributed under the License is distributed on an "AS IS" BASIS, 
	WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. 
	See the License for the specific language governing permissions and 
	limitations under the License.
*/

// A behavioral model for a quad I/O SPI PSRAM 

module psram_model (
    input       sck_i,
    input       ce_n_i,
    inout [3:0] dat_io
);

  localparam ST_IDLE = 3'h0;
  localparam ST_CMD = 3'h1;
  localparam ST_ADDR = 3'h2;
  localparam ST_DUMMY = 3'h3;
  localparam ST_DR = 3'h4;
  localparam ST_DW = 3'h5;

  // 8M
  reg [ 7:0] RAM                   [8*1024*1024-1:0];

  reg [ 7:0] r_cmd;
  reg [23:0] r_addr;
  reg [ 7:0] r_data;
  reg [ 7:0] r_cnt;
  reg [ 2:0] r_fsm_state = ST_IDLE;

  always @(negedge ce_n_i or posedge ce_n_i)
    if (!ce_n_i) begin
      r_fsm_state <= ST_CMD;
      r_cnt       <= 8'd0;
      r_addr = 24'hFFFFFF;
      r_data = 8'd0;
    end else if (ce_n_i) r_fsm_state <= ST_IDLE;

  always @(posedge sck_i)
    case (r_fsm_state)
      ST_CMD:   if (r_cnt == 7) r_fsm_state <= ST_ADDR;
      ST_ADDR:
      if (r_cnt == 13) begin
        if (r_cmd == 8'hEB) r_fsm_state <= ST_DUMMY;
        else if (r_cmd == 8'h38) r_fsm_state <= ST_DW;
      end
      ST_DUMMY: if (r_cnt == 19) r_fsm_state <= ST_DR;
    endcase

  always @(posedge sck_i)
    case (r_fsm_state)
      ST_CMD:  r_cmd <= {r_cmd[6:0], dat_io[0]};
      ST_ADDR: r_addr <= {r_addr[20:0], dat_io};
      ST_DW:   r_data <= {r_data[3:0], dat_io};
    endcase

  always @(posedge sck_i) r_cnt <= r_cnt + 1;

  always @(negedge sck_i or ce_n_i)
    if (r_fsm_state == ST_DW)
      if (r_cnt >= 16)
        if ((r_cnt - 16) % 2 == 0 || ce_n_i) begin
          RAM[r_addr] = r_data;
          //   $display("PSRAM: Write to %x, value: %x", r_addr, RAM[r_addr]);
          r_addr      = r_addr + 1;
        end

  always @(posedge sck_i)
    if (r_fsm_state == ST_DUMMY || r_fsm_state == ST_DR)
      if (r_cnt >= 19)
        if ((r_cnt - 19) % 2 == 0) begin
          r_data = RAM[r_addr];
          r_addr = r_addr + 1;
          //      $display("PSRAM: Read from %x, value: %x", r_addr-1, r_data);
        end

  reg [3:0] do_;
  always @(negedge sck_i)
    if (r_fsm_state == ST_DR) begin
      do_    = r_data[7:4];
      r_data = r_data << 4;
    end

  assign dat_io = (r_fsm_state == ST_DR) ? do_ : 4'bz;

endmodule
