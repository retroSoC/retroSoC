module psram_core (
    input             clk_i,
    input             rst_n_i,
    input             cfg_wr_en_i,
    input      [ 3:0] cfg_wait_i,
    output reg [ 3:0] cfg_wait_o,
    output reg        mem_ready_o,
    input      [23:0] mem_addr_i,
    input      [31:0] mem_wdata_i,
    output     [31:0] mem_rdata_o,
    input      [ 7:0] xfer_data_bit_cnt_i,
    input             rd_st_i,
    input             wr_st_i,
    output            idle_o,
    output reg        psram_sclk_o,
    output reg        psram_ce_o,
    input             psram_miso_i,
    input             psram_mosi_i,
    input             psram_sio2_i,
    input             psram_sio3_i,
    output reg        psram_mosi_o,
    output reg        psram_miso_o,
    output reg        psram_sio2_o,
    output reg        psram_sio3_o,
    output            psram_sio_oen_o
);

  `define BOOT_COUNTER 18'd40_000

  localparam FSM_INIT = 0;
  localparam FSM_RSTEN = 1;
  localparam FSM_RSTEN2RST = 2;
  localparam FSM_RST = 3;
  localparam FSM_RST2QE = 4;
  localparam FSM_QE = 5;
  localparam FSM_QE2IDLE = 6;
  localparam FSM_IDLE = 7;
  localparam FSM_SEND = 8;
  localparam FSM_SEND_QPI = 9;
  localparam FSM_RD_PRE_QPI = 10;
  localparam FSM_RD_QPI = 11;
  localparam FSM_WR_QPI = 12;
  localparam FSM_RD2IDLE = 13;
  localparam FSM_WR2IDLE = 14;

  reg [ 4:0] r_fsm_state;
  reg [ 4:0] r_fsm_state_tgt;
  reg [17:0] r_boot_cnt;
  // ca mean: cmd + addr
  reg [31:0] r_xfer_ca;
  reg [31:0] r_xfer_data;
  reg [ 7:0] r_xfer_ca_bit_cnt;
  reg [ 7:0] r_xfer_data_bit_cnt;
  reg [ 3:0] r_ce_cnt;
  reg [ 3:0] r_rd_wait_cnt;
  reg        r_dev_rst;
  reg        r_wr_st;
  reg        r_rd_st;

  // wait cycles(mmio)
  always @(posedge clk_i or negedge rst_n_i) begin
    if (~rst_n_i) cfg_wait_o <= 4'd8;
    else if (cfg_wr_en_i) cfg_wait_o <= cfg_wait_i;
  end

  assign idle_o          = r_fsm_state == FSM_IDLE;
  assign mem_rdata_o     = r_xfer_data;
  assign psram_sio_oen_o = (r_fsm_state == FSM_RD_PRE_QPI) | (r_fsm_state == FSM_RD_QPI);


  always @(*) begin
    if (r_fsm_state == FSM_INIT) begin
      {psram_sio3_o, psram_sio2_o, psram_miso_o, psram_mosi_o} = 4'd0;
    end else if (r_fsm_state != FSM_IDLE) begin
      if (r_fsm_state < FSM_SEND_QPI) begin  // spi mode
        psram_mosi_o                               = r_xfer_ca[31];
        {psram_sio3_o, psram_sio2_o, psram_miso_o} = 3'd0;
      end else begin  // qpi mode
        {psram_sio3_o, psram_sio2_o, psram_miso_o, psram_mosi_o} = r_fsm_state == FSM_WR_QPI ? 
        {r_xfer_data[31], r_xfer_data[30], r_xfer_data[29], r_xfer_data[28]} :
        {r_xfer_ca[31], r_xfer_ca[30], r_xfer_ca[29], r_xfer_ca[28]};
      end
    end else begin
      {psram_sio3_o, psram_sio2_o, psram_miso_o, psram_mosi_o} = 4'd0;
    end
  end

  always @(posedge clk_i or negedge rst_n_i) begin
    if (~rst_n_i) r_rd_st <= 1'b0;
    else if (rd_st_i) r_rd_st <= 1'b1;
    else if (r_fsm_state == FSM_RD2IDLE) r_rd_st <= 1'b0;
  end

  always @(posedge clk_i or negedge rst_n_i) begin
    if (~rst_n_i) r_wr_st <= 1'b0;
    else if (wr_st_i) r_wr_st <= 1'b1;
    else if (r_fsm_state == FSM_WR2IDLE) r_wr_st <= 1'b0;
  end

  // >150us, ce high, sclk low, si/so/sio[3:0] low
  always @(posedge clk_i or negedge rst_n_i) begin
    if (~rst_n_i) begin
      r_fsm_state         <= FSM_INIT;
      r_fsm_state_tgt     <= FSM_INIT;
      r_boot_cnt          <= `BOOT_COUNTER;
      r_xfer_ca           <= 32'd0;
      r_xfer_data         <= 32'd0;
      r_xfer_ca_bit_cnt   <= 8'd0;
      r_xfer_data_bit_cnt <= 8'd0;
      r_ce_cnt            <= 4'd0;
      r_rd_wait_cnt       <= 4'd0;
      r_dev_rst           <= 1'b1;
      mem_ready_o         <= 1'b0;
      psram_sclk_o        <= 1'b0;
      psram_ce_o          <= 1'b1;
    end else begin
      mem_ready_o <= 1'b0;
      case (r_fsm_state)
        FSM_INIT: begin
          if (r_boot_cnt == 18'd0) r_fsm_state <= FSM_RSTEN;
          else r_boot_cnt <= r_boot_cnt - 1'b1;
        end
        FSM_RSTEN: begin
          r_xfer_ca         <= {8'h66, 24'd0};
          r_xfer_ca_bit_cnt <= 8'd8;
          psram_ce_o        <= 1'b0;
          r_ce_cnt          <= cfg_wait_o;
          r_fsm_state       <= FSM_SEND;
          r_fsm_state_tgt   <= FSM_RSTEN2RST;
        end
        FSM_RSTEN2RST: begin  // tCPH >= 50ns, when 192MHz, ce need keep high(>=10 cycles)
          if (r_ce_cnt != cfg_wait_o) psram_ce_o <= 1'b1;
          if (r_ce_cnt == 4'd0) r_fsm_state <= FSM_RST;
          r_ce_cnt <= r_ce_cnt - 1'b1;
        end
        FSM_RST: begin
          r_xfer_ca         <= {8'h99, 24'd0};
          r_xfer_ca_bit_cnt <= 8'd8;
          psram_ce_o        <= 1'b0;
          r_ce_cnt          <= cfg_wait_o;
          r_fsm_state       <= FSM_SEND;
          r_fsm_state_tgt   <= FSM_RST2QE;
        end
        FSM_RST2QE: begin
          if (r_ce_cnt != cfg_wait_o) psram_ce_o <= 1'b1;
          if (r_ce_cnt == 4'd0) r_fsm_state <= FSM_QE;
          r_ce_cnt <= r_ce_cnt - 1'b1;
        end
        FSM_QE: begin
          r_xfer_ca         <= {8'h35, 24'd0};
          r_xfer_ca_bit_cnt <= 8'd8;
          psram_ce_o        <= 1'b0;
          r_ce_cnt          <= cfg_wait_o;
          r_fsm_state       <= FSM_SEND;
          r_fsm_state_tgt   <= FSM_QE2IDLE;
        end
        FSM_QE2IDLE: begin
          if (r_ce_cnt != cfg_wait_o) psram_ce_o <= 1'b1;
          if (r_ce_cnt == 4'd0) r_fsm_state <= FSM_IDLE;
          r_ce_cnt <= r_ce_cnt - 1'b1;
        end
        FSM_IDLE: begin
          psram_sclk_o <= 1'b0;
          // release dev rst ctrl signal
          if (r_dev_rst) begin
            r_dev_rst  <= 1'b0;
            psram_ce_o <= 1'b1;
          end else if (r_wr_st) begin
            r_xfer_ca           <= {8'h38, mem_addr_i[23:0]};
            r_xfer_ca_bit_cnt   <= 32;
            r_fsm_state         <= FSM_SEND_QPI;
            r_fsm_state_tgt     <= FSM_WR_QPI;
            r_xfer_data_bit_cnt <= 8'd0;
            psram_ce_o          <= 1'b0;
          end else if (r_rd_st) begin
            r_xfer_ca           <= {8'hEB, mem_addr_i[23:0]};
            r_xfer_ca_bit_cnt   <= 32;
            r_fsm_state         <= FSM_SEND_QPI;
            r_fsm_state_tgt     <= FSM_RD_PRE_QPI;
            r_rd_wait_cnt       <= 4'd12;  // wait 6 cycle afer cmd+addr accrondig to TRM
            r_xfer_data_bit_cnt <= 8'd0;
            psram_ce_o          <= 1'b0;
          end else begin
            psram_ce_o <= 1'b1;
          end
        end
        FSM_SEND: begin
          psram_sclk_o <= ~psram_sclk_o;
          if (psram_sclk_o) begin
            r_xfer_ca_bit_cnt <= r_xfer_ca_bit_cnt - 1'b1;
            r_xfer_ca         <= {r_xfer_ca[30:0], 1'b1};
            if (r_xfer_ca_bit_cnt == 8'd1) begin
              r_fsm_state <= r_fsm_state_tgt;
            end
          end
        end
        FSM_SEND_QPI: begin
          psram_sclk_o <= ~psram_sclk_o;
          if (psram_sclk_o) begin
            r_xfer_ca_bit_cnt <= r_xfer_ca_bit_cnt - 8'd4;
            r_xfer_ca         <= {r_xfer_ca[27:0], 4'd1};
            if (r_xfer_ca_bit_cnt == 8'd4) begin
              r_fsm_state <= r_fsm_state_tgt;
              r_xfer_data <= mem_wdata_i;  // for r_fsm_state_tgt == FSM_WR_QPI
            end
          end
        end
        FSM_RD_PRE_QPI: begin
          // 6 cycles
          psram_sclk_o  <= ~psram_sclk_o;
          r_rd_wait_cnt <= r_rd_wait_cnt - 1'b1;
          if (r_rd_wait_cnt == 4'd0) r_fsm_state <= FSM_RD_QPI;
        end
        FSM_RD_QPI: begin
          // the first 'psram_sclk_o' is 0 in this state
          psram_sclk_o <= ~psram_sclk_o;
          if (psram_sclk_o) begin
            r_xfer_data <= {
              r_xfer_data[27:0], psram_sio3_i, psram_sio2_i, psram_miso_i, psram_mosi_i
            };
            r_xfer_data_bit_cnt <= r_xfer_data_bit_cnt + 8'd4;
            if (r_xfer_data_bit_cnt == xfer_data_bit_cnt_i) begin
              r_fsm_state <= FSM_RD2IDLE;
              r_ce_cnt    <= cfg_wait_o;
            end
          end
        end
        FSM_WR_QPI: begin
          // the first 'psram_sclk_o' is 0 in this state
          psram_sclk_o <= ~psram_sclk_o;
          if (psram_sclk_o) begin
            r_xfer_data         <= {r_xfer_data[27:0], 4'd1};
            r_xfer_data_bit_cnt <= r_xfer_data_bit_cnt + 8'd4;
            if (r_xfer_data_bit_cnt == xfer_data_bit_cnt_i - 8'd4) begin
              r_fsm_state <= FSM_WR2IDLE;
              r_ce_cnt    <= cfg_wait_o;
            end
          end
        end
        FSM_RD2IDLE: begin
          if (r_ce_cnt != cfg_wait_o) psram_ce_o <= 1'b1;
          if (r_ce_cnt == 4'd0) begin
            r_fsm_state <= FSM_IDLE;
            mem_ready_o <= 1'b1;
          end
          r_ce_cnt <= r_ce_cnt - 1'b1;
        end
        FSM_WR2IDLE: begin
          if (r_ce_cnt != cfg_wait_o) psram_ce_o <= 1'b1;
          if (r_ce_cnt == 4'd0) begin
            r_fsm_state <= FSM_IDLE;
            mem_ready_o <= 1'b1;
          end
          r_ce_cnt <= r_ce_cnt - 1'b1;
        end
      endcase
    end
  end
endmodule
