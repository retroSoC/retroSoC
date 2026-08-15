// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module psram_core (
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic [ 4:0] cfg_wait_i,
    input  logic [ 2:0] cfg_chd_i,
    input  logic        cfg_init_i,
    output logic        mem_ready_o,
    input  logic [23:0] mem_addr_i,
    input  logic [31:0] mem_wdata_i,
    output logic [31:0] mem_rdata_o,
    input  logic [ 7:0] xfer_data_bit_cnt_i,
    input  logic        rd_st_i,
    input  logic        wr_st_i,
    output logic        init_done_o,
    output logic        idle_o,
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
  // sclk(max: 144MHz ~ 6.94ns)
  // 6.94 * 50000 = 347us / 2 = 174us > 150us
  localparam logic [17:0] BootCounter = 18'd50_000;

  typedef enum logic [4:0] {
    Init               = 5'd0,
    ResetEnable        = 5'd1,
    ResetEnableToReset = 5'd2,
    Reset              = 5'd3,
    ResetToQuadEnable  = 5'd4,
    QuadEnable         = 5'd5,
    QuadEnableToIdle   = 5'd6,
    Idle               = 5'd7,
    Send               = 5'd8,
    SendQpi            = 5'd9,
    ReadPreQpi         = 5'd10,
    ReadQpi            = 5'd11,
    WriteQpi           = 5'd12,
    ReadToIdle         = 5'd13,
    WriteToIdle        = 5'd14
  } psram_state_e;

  psram_state_e        s_fsm_state;
  psram_state_e        s_fsm_state_tgt;
  logic         [17:0] s_boot_cnt;
  // ca mean: cmd + addr
  logic         [31:0] s_xfer_ca;
  logic         [31:0] s_xfer_data;
  logic         [ 7:0] s_xfer_ca_bit_cnt;
  logic         [ 7:0] s_xfer_data_bit_cnt;
  logic         [ 7:0] s_xfer_byte_data;
  logic         [ 4:0] s_ce_cnt;
  logic         [ 3:0] s_rd_wait_cnt;
  logic         [ 2:0] s_cfg_chd;
  logic                s_dev_rst;
  logic                s_wr_st;
  logic                s_rd_st;
  logic                s_init_done;

  logic                s_xfer_new_byte_upd;
  logic         [ 7:0] s_xfer_new_byte;


  assign init_done_o     = s_init_done;
  assign idle_o          = s_fsm_state == Idle;
  assign psram_sio_oen_o = (s_fsm_state == ReadPreQpi) | (s_fsm_state == ReadQpi);
  assign mem_rdata_o     = s_xfer_data;

  always_comb begin
    if (s_fsm_state == Init) begin
      {psram_sio3_o, psram_sio2_o, psram_miso_o, psram_mosi_o} = 4'd0;
    end else if (s_fsm_state != Idle) begin
      if (s_fsm_state < SendQpi) begin  // spi mode
        psram_mosi_o                               = s_xfer_ca[31];
        {psram_sio3_o, psram_sio2_o, psram_miso_o} = 3'd0;
      end else begin  // qpi mode
        {psram_sio3_o, psram_sio2_o, psram_miso_o, psram_mosi_o} =
            s_fsm_state == WriteQpi
                ? {s_xfer_byte_data[7:4]}
                : {s_xfer_ca[31], s_xfer_ca[30], s_xfer_ca[29], s_xfer_ca[28]};
      end
    end else begin
      {psram_sio3_o, psram_sio2_o, psram_miso_o, psram_mosi_o} = 4'd0;
    end
  end

  // These protocol-state processes retain ordered update and reset priority;
  // decomposing them into Common DFFs would risk changing same-cycle behavior.
  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (~rst_n_i) s_rd_st <= 1'b0;
    else if (rd_st_i) s_rd_st <= 1'b1;
    else if (s_fsm_state == ReadToIdle) s_rd_st <= 1'b0;
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (~rst_n_i) s_wr_st <= 1'b0;
    else if (wr_st_i) s_wr_st <= 1'b1;
    else if (s_fsm_state == WriteToIdle) s_wr_st <= 1'b0;
  end

  // >150us, ce high, sclk low, si/so/sio[3:0] low
  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (~rst_n_i) begin
      s_fsm_state         <= Init;
      s_fsm_state_tgt     <= Init;
      s_boot_cnt          <= BootCounter;
      s_xfer_ca           <= 32'd0;
      s_xfer_data         <= 32'd0;
      s_xfer_ca_bit_cnt   <= 8'd0;
      s_xfer_data_bit_cnt <= 8'd0;
      s_xfer_byte_data    <= 8'd0;
      s_ce_cnt            <= 5'd0;
      s_rd_wait_cnt       <= 4'd0;
      s_cfg_chd           <= 3'd0;
      s_dev_rst           <= 1'b1;
      s_init_done         <= 1'b0;
      mem_ready_o         <= 1'b0;
      psram_sclk_o        <= 1'b0;
      psram_ce_o          <= 1'b1;
    end else begin
      mem_ready_o <= 1'b0;
      /* verilator lint_off CASEINCOMPLETE */
      case (s_fsm_state)
        Init: begin
          if (s_boot_cnt != '0) s_boot_cnt <= s_boot_cnt - 1'b1;
          else if (cfg_init_i) s_fsm_state <= ResetEnable;
        end
        ResetEnable: begin
          s_xfer_ca         <= {8'h66, 24'd0};
          s_xfer_ca_bit_cnt <= 8'd8;
          s_cfg_chd         <= 3'd0;
          psram_ce_o        <= 1'b0;
          s_ce_cnt          <= cfg_wait_i;
          s_fsm_state       <= Send;
          s_fsm_state_tgt   <= ResetEnableToReset;
        end
        ResetEnableToReset: begin  // tCPH >= 50ns, when 192MHz, ce need keep high(>=10 cycles)
          if (s_cfg_chd == cfg_chd_i) begin
            if (s_ce_cnt != cfg_wait_i) psram_ce_o <= 1'b1;
            if (s_ce_cnt == 5'd0) s_fsm_state <= Reset;
            s_ce_cnt <= s_ce_cnt - 1'b1;
          end else begin
            s_cfg_chd <= s_cfg_chd + 1'b1;
          end
        end
        Reset: begin
          s_xfer_ca         <= {8'h99, 24'd0};
          s_xfer_ca_bit_cnt <= 8'd8;
          s_cfg_chd         <= 3'd0;
          psram_ce_o        <= 1'b0;
          s_ce_cnt          <= cfg_wait_i;
          s_fsm_state       <= Send;
          s_fsm_state_tgt   <= ResetToQuadEnable;
        end
        ResetToQuadEnable: begin
          if (s_cfg_chd == cfg_chd_i) begin
            if (s_ce_cnt != cfg_wait_i) psram_ce_o <= 1'b1;
            if (s_ce_cnt == 5'd0) s_fsm_state <= QuadEnable;
            s_ce_cnt <= s_ce_cnt - 1'b1;
          end else begin
            s_cfg_chd <= s_cfg_chd + 1'b1;
          end
        end
        QuadEnable: begin
          s_xfer_ca         <= {8'h35, 24'd0};
          s_xfer_ca_bit_cnt <= 8'd8;
          s_cfg_chd         <= 3'd0;
          psram_ce_o        <= 1'b0;
          s_ce_cnt          <= cfg_wait_i;
          s_fsm_state       <= Send;
          s_fsm_state_tgt   <= QuadEnableToIdle;
        end
        QuadEnableToIdle: begin
          if (s_cfg_chd == cfg_chd_i) begin
            if (s_ce_cnt != cfg_wait_i) psram_ce_o <= 1'b1;
            if (s_ce_cnt == 5'd0) begin
              s_fsm_state <= Idle;
              s_init_done <= 1'b1;
            end
            s_ce_cnt <= s_ce_cnt - 1'b1;
          end else begin
            s_cfg_chd <= s_cfg_chd + 1'b1;
          end
        end
        Idle: begin
          psram_sclk_o <= 1'b0;
          // release dev rst ctrl signal
          if (s_dev_rst) begin
            s_dev_rst  <= 1'b0;
            psram_ce_o <= 1'b1;
          end else if (s_wr_st) begin
            s_xfer_ca           <= {8'h38, mem_addr_i[23:0]};
            s_xfer_ca_bit_cnt   <= 8'd32;
            s_fsm_state         <= SendQpi;
            s_fsm_state_tgt     <= WriteQpi;
            s_xfer_data_bit_cnt <= 8'd0;
            s_cfg_chd           <= 3'd0;
            psram_ce_o          <= 1'b0;
          end else if (s_rd_st) begin
            s_xfer_ca           <= {8'hEB, mem_addr_i[23:0]};
            s_xfer_ca_bit_cnt   <= 8'd32;
            s_fsm_state         <= SendQpi;
            s_fsm_state_tgt     <= ReadPreQpi;
            s_rd_wait_cnt       <= 4'd12;  // wait 6 cycle afer cmd+addr accrondig to TRM
            s_xfer_data_bit_cnt <= 8'd0;
            s_cfg_chd           <= 3'd0;
            psram_ce_o          <= 1'b0;
          end else begin
            psram_ce_o <= 1'b1;
          end
        end
        Send: begin
          psram_sclk_o <= ~psram_sclk_o;
          if (psram_sclk_o) begin
            s_xfer_ca_bit_cnt <= s_xfer_ca_bit_cnt - 1'b1;
            s_xfer_ca         <= {s_xfer_ca[30:0], 1'b1};
            if (s_xfer_ca_bit_cnt == 8'd1) begin
              s_fsm_state <= s_fsm_state_tgt;
            end
          end
        end
        SendQpi: begin
          psram_sclk_o <= ~psram_sclk_o;
          if (psram_sclk_o) begin
            s_xfer_ca_bit_cnt <= s_xfer_ca_bit_cnt - 8'd4;
            s_xfer_ca         <= {s_xfer_ca[27:0], 4'd1};
            if (s_xfer_ca_bit_cnt == 8'd4) begin
              s_fsm_state      <= s_fsm_state_tgt;
              s_xfer_data      <= mem_wdata_i;
              s_xfer_byte_data <= mem_wdata_i[7:0];
            end
          end
        end
        ReadPreQpi: begin
          // 6 cycles
          psram_sclk_o  <= ~psram_sclk_o;
          s_rd_wait_cnt <= s_rd_wait_cnt - 1'b1;
          if (s_rd_wait_cnt == 4'd0) s_fsm_state <= ReadQpi;
        end
        ReadQpi: begin
          // the first 'psram_sclk_o' is 0 in this state
          psram_sclk_o <= ~psram_sclk_o;
          if (psram_sclk_o) begin
            if (s_xfer_data_bit_cnt == 8'd8) s_xfer_data[7:0] <= s_xfer_byte_data;
            else if (s_xfer_data_bit_cnt == 8'd16) s_xfer_data[15:8] <= s_xfer_byte_data;
            else if (s_xfer_data_bit_cnt == 8'd24) s_xfer_data[23:16] <= s_xfer_byte_data;
            s_xfer_byte_data <= {
              s_xfer_byte_data[3:0], psram_sio3_i, psram_sio2_i, psram_miso_i, psram_mosi_i
            };
            s_xfer_data_bit_cnt <= s_xfer_data_bit_cnt + 8'd4;
            if (s_xfer_data_bit_cnt == xfer_data_bit_cnt_i - 8'd4) begin
              s_fsm_state <= ReadToIdle;
              s_ce_cnt    <= cfg_wait_i;
            end
          end
        end
        WriteQpi: begin
          // the first 'psram_sclk_o' is 0 in this state
          psram_sclk_o <= ~psram_sclk_o;
          if (psram_sclk_o) begin
            if (s_xfer_new_byte_upd) s_xfer_byte_data <= s_xfer_new_byte;
            else s_xfer_byte_data <= {s_xfer_byte_data[3:0], 4'hF};

            s_xfer_data_bit_cnt <= s_xfer_data_bit_cnt + 8'd4;
            if (s_xfer_data_bit_cnt == xfer_data_bit_cnt_i - 8'd4) begin
              s_fsm_state <= WriteToIdle;
              s_ce_cnt    <= cfg_wait_i;
            end
          end
        end
        ReadToIdle: begin
          if (s_cfg_chd == cfg_chd_i) begin
            if (s_ce_cnt != cfg_wait_i) begin
              psram_ce_o         <= 1'b1;
              s_xfer_data[31:24] <= s_xfer_byte_data;  // HACK:
            end
            if (s_ce_cnt == 5'd0) begin
              s_fsm_state <= Idle;
              mem_ready_o <= 1'b1;
            end
            s_ce_cnt <= s_ce_cnt - 1'b1;
          end else begin
            s_cfg_chd <= s_cfg_chd + 1'b1;
          end
        end
        WriteToIdle: begin
          if (s_cfg_chd == cfg_chd_i) begin
            if (s_ce_cnt != cfg_wait_i) psram_ce_o <= 1'b1;
            if (s_ce_cnt == 5'd0) begin
              s_fsm_state <= Idle;
              mem_ready_o <= 1'b1;
            end
            s_ce_cnt <= s_ce_cnt - 1'b1;
          end else begin
            s_cfg_chd <= s_cfg_chd + 1'b1;
          end
        end
        default: begin
          s_fsm_state  <= Init;
          psram_sclk_o <= 1'b0;
          psram_ce_o   <= 1'b1;
        end
      endcase
    end
  end

  load_new_byte u_load_new_byte (
      .xfer_data_bit_cnt_i(s_xfer_data_bit_cnt),
      .wr_data_i          (s_xfer_data),
      .xfer_new_byte_upd_o(s_xfer_new_byte_upd),
      .xfer_new_byte_o    (s_xfer_new_byte)
  );

endmodule


module load_new_byte (
    input  logic [ 7:0] xfer_data_bit_cnt_i,
    input  logic [31:0] wr_data_i,
    output logic        xfer_new_byte_upd_o,
    output logic [ 7:0] xfer_new_byte_o
);
  assign xfer_new_byte_upd_o = (xfer_data_bit_cnt_i == 8'd4)  |
                               (xfer_data_bit_cnt_i == 8'd12) |
                               (xfer_data_bit_cnt_i == 8'd20);

  assign xfer_new_byte_o = ({8{xfer_data_bit_cnt_i == 8'd4} } & wr_data_i[15:8])  |
                           ({8{xfer_data_bit_cnt_i == 8'd12}} & wr_data_i[23:16]) |
                           ({8{xfer_data_bit_cnt_i == 8'd20}} & wr_data_i[31:24]);
endmodule
