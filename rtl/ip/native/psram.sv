// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// psram is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.
//
// NOTE: for supporting cross page xfer, the max freq of 'sclk' is 84MHz
// when 'sclk' is 144MHz(max, ~6.94ns), according to TRM:
//
// tCLK(min: 6.94ns) is meet, dont have 8'h03 rd oper(min: 30.3ns)
//
// tCH/tCL(min:0.45%, max: 0.55%) tCLK is meet
//
// tKHKL(max: 1.5ns) is meet
//
// tCPH(min: 50ns) -> 50 / 6.94 = ~7.2 so wait cycles need to >= ceil(7.2) = 8,
// so 'cfg_wait_o' = 8 * 2 >= 16 in default, reset value is '18'
// for lower freq, can modify this value for performance tuning
//
// tCEM(max: 8us) is enough long for just 32bits xfer:
// QPI mode: (32(cmd+addr) + 32(data)) / 4 = 16 cycles + 6 wait cycles = 22 cycles
// for min sclk 12MHz, ~83ns * 22 = 1826ns = 1.826us
//
// tCSP(min: 2.5ns) is meet
// sclk keeps 6.94 / 2 = 3.47ns low at least after ce activing
//
// tCHD(min: 20ns) > tACLK + tCLK
// sclk keep 6.94 * 1.5 = 10.41 at least(no meet!)
// need to set 'cfg_chd_o' = ceil(ceil(20 / 6.94) - 1.5) * 2 = 3, reset value is '4'
// for lower freq, can modify this value for performance tuning
//
// tSP(min: 2ns) is meet
// data keeps 6.94 / 2 = 3.47ns low at least befer sclk


module psram_top (
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        cfg_wait_wr_en_i,
    input  logic [ 4:0] cfg_wait_i,
    output logic [ 4:0] cfg_wait_o,
    input  logic        cfg_chd_wr_en_i,
    input  logic [ 2:0] cfg_chd_i,
    output logic [ 2:0] cfg_chd_o,
    input  logic        mem_valid_i,
    output logic        mem_ready_o,
    input  logic [23:0] mem_addr_i,
    input  logic [31:0] mem_wdata_i,
    input  logic [ 3:0] mem_wstrb_i,
    output logic [31:0] mem_rdata_o,
    output logic        psram_sclk_o,
    output logic        psram_ce_o,
    input  logic        psram_mosi_i,
    input  logic        psram_miso_i,
    input  logic        psram_sio2_i,
    input  logic        psram_sio3_i,
    output logic        psram_mosi_o,
    output logic        psram_miso_o,
    output logic        psram_sio2_o,
    output logic        psram_sio3_o,
    output logic        psram_sio_oen_o
);

  localparam FSM_IDLE = 0;
  localparam FSM_WE_ST = 1;
  localparam FSM_WE = 2;
  localparam FSM_RD_ST = 3;
  localparam FSM_RD = 4;

  logic        r_rd_st;
  logic        r_wr_st;
  logic [ 7:0] r_xfer_data_bit_cnt;
  logic [ 5:0] r_fsm_state;
  logic [23:0] r_mem_addr;
  logic [31:0] r_mem_wdata;

  logic [ 1:0] s_disp_addr_ofst;
  logic [ 7:0] s_disp_xfer_bit_cnt;
  logic [31:0] s_disp_wdata;
  logic        s_core_idle;

  always_ff @(posedge clk_i, negedge rst_n_i) begin
    if (~rst_n_i) begin
      r_rd_st             <= '0;
      r_wr_st             <= '0;
      r_xfer_data_bit_cnt <= '0;
      r_fsm_state         <= FSM_IDLE;
      r_mem_addr          <= '0;
      r_mem_wdata         <= '0;
    end else begin
      case (r_fsm_state)
        FSM_IDLE: begin
          if (mem_valid_i && (|mem_wstrb_i)) begin
            r_fsm_state         <= FSM_WE_ST;
            r_xfer_data_bit_cnt <= s_disp_xfer_bit_cnt;
            r_mem_addr          <= mem_addr_i + s_disp_addr_ofst;
            r_mem_wdata         <= s_disp_wdata;
          end else if (mem_valid_i && (~(|mem_wstrb_i))) begin
            r_fsm_state         <= FSM_RD_ST;
            r_xfer_data_bit_cnt <= 8'd32;
            r_mem_addr          <= mem_addr_i;
            r_mem_wdata         <= mem_wdata_i;  // NOTE: no used
          end
        end
        FSM_WE_ST: begin
          if (s_core_idle) begin
            r_wr_st     <= 1'b1;
            r_fsm_state <= FSM_WE;
          end
        end
        FSM_WE: begin
          r_wr_st <= 1'b0;
          if (mem_ready_o) r_fsm_state <= FSM_IDLE;
        end
        FSM_RD_ST: begin
          if (s_core_idle) begin
            r_rd_st     <= 1'b1;
            r_fsm_state <= FSM_RD;
          end
        end
        FSM_RD: begin
          r_rd_st <= 1'b0;
          if (mem_ready_o) r_fsm_state <= FSM_IDLE;
        end
      endcase
    end
  end
  psram_core u_psram_core (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .cfg_wait_wr_en_i   (cfg_wait_wr_en_i),
      .cfg_wait_i         (cfg_wait_i),
      .cfg_wait_o         (cfg_wait_o),
      .cfg_chd_wr_en_i    (cfg_chd_wr_en_i),
      .cfg_chd_i          (cfg_chd_i),
      .cfg_chd_o          (cfg_chd_o),
      .mem_ready_o        (mem_ready_o),
      .mem_addr_i         (r_mem_addr),
      .mem_wdata_i        (r_mem_wdata),
      .mem_rdata_o        (mem_rdata_o),
      .xfer_data_bit_cnt_i(r_xfer_data_bit_cnt),
      .rd_st_i            (r_rd_st),
      .wr_st_i            (r_wr_st),
      .idle_o             (s_core_idle),
      .psram_sclk_o       (psram_sclk_o),
      .psram_ce_o         (psram_ce_o),
      .psram_mosi_i       (psram_mosi_i),
      .psram_miso_i       (psram_miso_i),
      .psram_sio2_i       (psram_sio2_i),
      .psram_sio3_i       (psram_sio3_i),
      .psram_mosi_o       (psram_mosi_o),
      .psram_miso_o       (psram_miso_o),
      .psram_sio2_o       (psram_sio2_o),
      .psram_sio3_o       (psram_sio3_o),
      .psram_sio_oen_o    (psram_sio_oen_o)
  );

  wr_dispatcher u_wr_dispatcher (
      .wstrb_i       (mem_wstrb_i),
      .wdata_i       (mem_wdata_i),
      .addr_ofst_o   (s_disp_addr_ofst),
      .xfer_bit_cnt_o(s_disp_xfer_bit_cnt),
      .wdata_o       (s_disp_wdata)
  );

endmodule


module wr_dispatcher (
    input  logic [ 3:0] wstrb_i,
    input  logic [31:0] wdata_i,
    output logic [ 1:0] addr_ofst_o,
    output logic [ 7:0] xfer_bit_cnt_o,
    output logic [31:0] wdata_o
);
  always_comb begin
    wdata_o = wdata_i;
    case (wstrb_i)
      4'b0001: begin
        addr_ofst_o    = 2'd0;
        xfer_bit_cnt_o = 8'd8;
        wdata_o[31:24] = wdata_i[7:0];
      end
      4'b0010: begin
        addr_ofst_o    = 2'd1;
        xfer_bit_cnt_o = 8'd8;
        wdata_o[31:24] = wdata_i[15:8];
      end
      4'b0100: begin
        addr_ofst_o    = 2'd2;
        xfer_bit_cnt_o = 8'd8;
        wdata_o[31:24] = wdata_i[23:16];
      end
      4'b1000: begin
        addr_ofst_o    = 2'd3;
        xfer_bit_cnt_o = 8'd8;
        wdata_o[31:24] = wdata_i[31:24];
      end
      4'b0011: begin
        addr_ofst_o    = 2'd0;
        xfer_bit_cnt_o = 8'd16;
        wdata_o[31:16] = wdata_i[15:0];
      end
      4'b1100: begin
        addr_ofst_o    = 2'd2;
        xfer_bit_cnt_o = 8'd16;
        wdata_o[31:16] = wdata_i[31:16];
      end
      4'b1111: begin
        addr_ofst_o    = 2'd0;
        xfer_bit_cnt_o = 8'd32;
        wdata_o[31:0]  = wdata_i[31:0];
      end
      default: begin
        addr_ofst_o    = 2'd0;
        xfer_bit_cnt_o = 8'd32;
        wdata_o        = wdata_i[31:0];
      end
    endcase
  end
endmodule
