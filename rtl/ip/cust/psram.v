module psram_top (
    input             clk_i,
    input             rst_n_i,
    input      [23:0] addr_i,
    input      [ 3:0] wstrb_i,
    input      [31:0] wdata_i,
    output reg [31:0] rdata_o,
    input             we_i,
    input             rd_i,
    output            ready_o,
    input             cfg_wr_en_i,
    input      [ 3:0] cfg_wait_i,
    output     [ 3:0] cfg_wait_o,
    output            psram_sclk_o,
    output            psram_ce_o,
    input             psram_miso_i,
    input             psram_mosi_i,
    input             psram_sio2_i,
    input             psram_sio3_i,
    output            psram_mosi_o,
    output            psram_miso_o,
    output            psram_sio2_o,
    output            psram_sio3_o,
    output            psram_sio_oen_o
);

  localparam FSM_IDLE = 0;
  localparam FSM_WE_ST = 5;
  localparam FSM_WE = 10;
  localparam FSM_RD_ST = 15;
  localparam FSM_RD = 20;

  reg  [ 7:0] r_data_buf         [3:0];
  reg         r_core_ready;
  reg         r_ready_clk;
  reg  [23:0] r_addr;
  reg  [ 3:0] r_byte_xfer_cnt;
  reg         r_rd_st;
  reg         r_rd_end;
  reg         r_we_st;
  reg         r_we_end;
  reg         r_byte_avail_old;
  reg         r_rdy_nxt_byte_old;
  reg         r_byte_avail_pos;
  reg         r_rdy_nxt_byte_pos;
  reg  [ 5:0] r_fsm_state;

  wire [ 7:0] s_rdata;
  wire        s_byte_avail;
  wire        s_rdy_nxt_byte;
  wire        s_core_ready;

  assign ready_o = r_ready_clk & !(rd_i | we_i);

  always @(posedge clk_i or negedge rst_n_i) begin
    if (~rst_n_i) r_ready_clk <= 1'b0;
    else r_ready_clk <= r_core_ready;
  end

  psram_core u_psram_core (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .rd_st_i        (r_rd_st),
      .rd_end_i       (r_rd_end),
      .we_st_i        (r_we_st),
      .we_end_i       (r_we_end),
      .addr_i         (r_addr),
      .rdata_o        (s_rdata),
      .byte_avail_o   (s_byte_avail),
      .wdata_i        (r_data_buf[r_byte_xfer_cnt]),
      .rdy_nxt_byte_o (s_rdy_nxt_byte),
      .ready_o        (s_core_ready),
      .cfg_wr_en_i    (cfg_wr_en_i),
      .cfg_wait_i     (cfg_wait_i),
      .cfg_wait_o     (cfg_wait_o),
      .psram_sclk_o   (psram_sclk_o),
      .psram_ce_o     (psram_ce_o),
      .psram_miso_i   (psram_miso_i),
      .psram_mosi_i   (psram_mosi_i),
      .psram_sio2_i   (psram_sio2_i),
      .psram_sio3_i   (psram_sio3_i),
      .psram_mosi_o   (psram_mosi_o),
      .psram_miso_o   (psram_miso_o),
      .psram_sio2_o   (psram_sio2_o),
      .psram_sio3_o   (psram_sio3_o),
      .psram_sio_oen_o(psram_sio_oen_o)
  );


  always @(posedge clk_i or negedge rst_n_i) begin
    if (~rst_n_i) begin
      r_byte_avail_old   <= 1'b0;
      r_rdy_nxt_byte_old <= 1'b0;
    end else begin
      r_byte_avail_old   <= s_byte_avail;
      r_rdy_nxt_byte_old <= s_rdy_nxt_byte;
    end
  end
  always @(*) begin
    r_byte_avail_pos   = !r_byte_avail_old & s_byte_avail;
    r_rdy_nxt_byte_pos = !r_rdy_nxt_byte_old & s_rdy_nxt_byte;
  end

  always @(posedge clk_i or negedge rst_n_i) begin
    if (~rst_n_i) begin
      r_rd_st         <= 1'b0;
      r_rd_end        <= 1'b0;
      r_we_st         <= 1'b0;
      r_we_end        <= 1'b0;
      r_fsm_state     <= FSM_IDLE;
      r_core_ready    <= 1'b0;
      r_byte_xfer_cnt <= 4'd0;
    end else begin
      case (r_fsm_state)
        // go FSM_IDLE right after reset, but first memory operation will
        // hang until the psram is ready_o
        FSM_IDLE: begin
          if (we_i) begin
            r_fsm_state     <= FSM_WE_ST;
            r_core_ready    <= 1'b0;
            r_byte_xfer_cnt <= 4'd4;
          end else if (rd_i) begin
            r_fsm_state     <= FSM_RD_ST;
            r_core_ready    <= 1'b0;
            r_byte_xfer_cnt <= 4'd4;
          end else begin
            r_core_ready <= s_core_ready;
          end
          r_addr        <= addr_i;
          r_data_buf[3] <= wdata_i[31:24];
          r_data_buf[2] <= wdata_i[23:16];
          r_data_buf[1] <= wdata_i[15:8];
          r_data_buf[0] <= wdata_i[7:0];
          r_we_end      <= 1'b0;
          r_rd_end      <= 1'b0;
        end
        FSM_WE_ST: begin
          if (s_core_ready) begin
            r_we_st     <= 1'b1;
            r_fsm_state <= FSM_WE;
          end
        end
        FSM_WE: begin
          r_we_st <= 1'b0;
          if (r_rdy_nxt_byte_pos) begin
            r_byte_xfer_cnt <= r_byte_xfer_cnt - 1'b1;
          end
          if (r_byte_xfer_cnt == 4'd0) begin
            r_fsm_state <= FSM_IDLE;
            r_we_end    <= 1'b1;
          end
        end
        FSM_RD_ST: begin
          if (s_core_ready) begin
            r_rd_st     <= 1'b1;
            r_fsm_state <= FSM_RD;
          end
        end
        FSM_RD: begin
          r_rd_st <= 1'b0;
          if (r_byte_avail_pos) begin
            r_byte_xfer_cnt               <= r_byte_xfer_cnt - 1'b1;
            r_data_buf[r_byte_xfer_cnt-1] <= s_rdata;
          end
          if (r_byte_xfer_cnt == 4'd1) begin
            r_rd_end <= 1'b1;
          end
          if (r_byte_xfer_cnt == 4'd0) begin
            rdata_o     <= {r_data_buf[3], r_data_buf[2], r_data_buf[1], r_data_buf[0]};
            r_fsm_state <= FSM_IDLE;
          end
        end
      endcase
    end
  end
endmodule



module psram_core (
    input             clk_i,
    input             rst_n_i,
    input             rd_st_i,
    input             rd_end_i,
    input             we_st_i,
    input             we_end_i,
    input      [23:0] addr_i,
    input      [ 7:0] wdata_i,
    output reg [ 7:0] rdata_o,
    output reg        byte_avail_o,
    output reg        rdy_nxt_byte_o,
    output            ready_o,
    input             cfg_wr_en_i,
    input      [ 3:0] cfg_wait_i,
    output reg [ 3:0] cfg_wait_o,
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
  localparam FSM_QPI2IDLE = 6;
  localparam FSM_IDLE = 7;
  localparam FSM_SEND = 8;
  localparam FSM_SEND_QUAD = 9;
  localparam FSM_RD_PRE_QUAD = 10;
  localparam FSM_RD_QUAD = 11;
  localparam FSM_WR_PRE_QUAD = 12;
  localparam FSM_WR_QUAD = 13;
  localparam FSM_RD2IDLE = 14;
  localparam FSM_WR2IDLE = 15;


  reg [ 4:0] r_fsm_state;
  reg [ 4:0] r_fsm_state_tgt;
  reg [17:0] r_boot_cnt;
  reg [31:0] r_xfer_cmd_addr;
  reg [ 7:0] r_send_cnt;
  reg [ 7:0] r_xfer_data;
  reg [ 3:0] r_ce_cnt;
  reg [ 2:0] r_byte_cnt;  // auto-overflow from 7 to 0
  reg [ 3:0] r_rd_wait_cnt;
  reg        r_rsting;
  reg        r_we_st;
  reg        r_rd_st;
  reg        r_rd_end;
  reg        r_we_end;

  // wait cycles(mmio)
  always @(posedge clk_i or negedge rst_n_i) begin
    if (~rst_n_i) cfg_wait_o <= 4'd8;
    else if (cfg_wr_en_i) cfg_wait_o <= cfg_wait_i;
  end

  assign ready_o         = r_fsm_state == FSM_IDLE;
  assign psram_sio_oen_o = (r_fsm_state == FSM_RD_PRE_QUAD) | (r_fsm_state == FSM_RD_QUAD);

  always @(*) begin
    if (r_fsm_state == FSM_INIT) begin
      {psram_sio3_o, psram_sio2_o, psram_miso_o, psram_mosi_o} = 4'd0;
    end else if (r_fsm_state != FSM_IDLE) begin
      if (r_fsm_state < FSM_SEND_QUAD) begin  // spi mode
        psram_mosi_o                               = r_xfer_cmd_addr[31];
        {psram_sio3_o, psram_sio2_o, psram_miso_o} = 3'd0;
      end else begin  // qpi mode
        {psram_sio3_o, psram_sio2_o, psram_miso_o, psram_mosi_o} = r_fsm_state == FSM_WR_QUAD ? 
        {r_xfer_data[7], r_xfer_data[6], r_xfer_data[5], r_xfer_data[4]} :
        {r_xfer_cmd_addr[31], r_xfer_cmd_addr[30], r_xfer_cmd_addr[29], r_xfer_cmd_addr[28]};
      end
    end else begin
      {psram_sio3_o, psram_sio2_o, psram_miso_o, psram_mosi_o} = 4'd0;
    end
  end

  always @(posedge clk_i or negedge rst_n_i) begin
    if (~rst_n_i) r_rd_end <= 1'b0;
    else if ((r_fsm_state == FSM_RD_QUAD) & rd_end_i) r_rd_end <= 1'b1;
    else if (r_fsm_state != FSM_RD_QUAD) r_rd_end <= 1'b0;
  end

  always @(posedge clk_i or negedge rst_n_i) begin
    if (~rst_n_i) r_we_end <= 1'b0;
    else if ((r_fsm_state == FSM_WR_QUAD) & we_end_i) r_we_end <= 1'b1;
    else if (r_fsm_state != FSM_WR_QUAD) r_we_end <= 1'b0;
  end

  always @(posedge clk_i or negedge rst_n_i) begin
    if (~rst_n_i) r_we_st <= 1'b0;  // TODO: check
    else if (we_st_i) r_we_st <= 1'b1;
    else if (r_fsm_state == FSM_WR2IDLE) r_we_st <= 1'b0;
  end

  always @(posedge clk_i or negedge rst_n_i) begin
    if (~rst_n_i) r_rd_st <= 1'b0;
    else if (rd_st_i) r_rd_st <= 1'b1;
    else if (r_fsm_state == FSM_RD2IDLE) r_rd_st <= 1'b0;
  end

  // >150us, ce high, sclk low, si/so/sio[3:0] low
  always @(posedge clk_i or negedge rst_n_i) begin
    if (~rst_n_i) begin
      r_fsm_state     <= FSM_INIT;
      r_fsm_state_tgt <= FSM_INIT;
      r_boot_cnt      <= `BOOT_COUNTER;
      r_xfer_cmd_addr <= 32'd0;
      r_send_cnt      <= 8'd0;
      r_xfer_data     <= 8'd0;
      r_byte_cnt      <= 3'd0;
      r_ce_cnt        <= 4'd0;
      r_rd_wait_cnt   <= 4'd0;
      r_rsting        <= 1'b1;
      byte_avail_o    <= 1'b0;
      rdy_nxt_byte_o  <= 1'b0;
      psram_ce_o      <= 1'b1;
      psram_sclk_o    <= 1'b0;
    end else
      case (r_fsm_state)
        FSM_INIT: begin
          if (r_boot_cnt == 18'd0) r_fsm_state <= FSM_RSTEN;
          else r_boot_cnt <= r_boot_cnt - 1'b1;
        end
        FSM_RSTEN: begin
          r_xfer_cmd_addr <= {8'h66, 24'd0};
          r_send_cnt      <= 8'd8;
          psram_ce_o      <= 1'b0;
          r_ce_cnt        <= cfg_wait_o;
          r_fsm_state     <= FSM_SEND;
          r_fsm_state_tgt <= FSM_RSTEN2RST;

        end
        FSM_RSTEN2RST: begin  // tCPH >= 50ns, max 192MHz, ce need keep high > 10 cycles
          if (r_ce_cnt != cfg_wait_o) psram_ce_o <= 1'b1;
          if (r_ce_cnt == 4'd0) r_fsm_state <= FSM_RST;
          r_ce_cnt <= r_ce_cnt - 1'b1;
        end
        FSM_RST: begin
          r_xfer_cmd_addr <= {8'h99, 24'd0};
          r_send_cnt      <= 8'd8;
          psram_ce_o      <= 1'b0;
          r_ce_cnt        <= cfg_wait_o;
          r_fsm_state     <= FSM_SEND;
          r_fsm_state_tgt <= FSM_RST2QE;
        end
        FSM_RST2QE: begin
          if (r_ce_cnt != cfg_wait_o) psram_ce_o <= 1'b1;
          if (r_ce_cnt == 4'd0) r_fsm_state <= FSM_QE;
          r_ce_cnt <= r_ce_cnt - 1'b1;
        end
        FSM_QE: begin
          r_xfer_cmd_addr <= {8'h35, 24'd0};
          r_send_cnt      <= 8'd8;
          psram_ce_o      <= 1'b0;
          r_ce_cnt        <= cfg_wait_o;
          r_fsm_state     <= FSM_SEND;
          r_fsm_state_tgt <= FSM_QPI2IDLE;

        end
        FSM_QPI2IDLE: begin
          if (r_ce_cnt != cfg_wait_o) psram_ce_o <= 1'b1;
          if (r_ce_cnt == 4'd0) r_fsm_state <= FSM_IDLE;
          r_ce_cnt <= r_ce_cnt - 1'b1;
        end
        FSM_IDLE: begin
          psram_sclk_o <= 1'b0;
          // release rst ctrl
          if (r_rsting) begin
            r_rsting   <= 1'b0;
            psram_ce_o <= 1'b1;
          end else if (r_we_st) begin
            r_xfer_cmd_addr <= {8'h38, addr_i[23:0]};
            r_send_cnt      <= 8 + 24;
            r_fsm_state     <= FSM_SEND_QUAD;
            r_fsm_state_tgt <= FSM_WR_PRE_QUAD;
            r_byte_cnt      <= 3'd0;
            psram_ce_o      <= 1'b0;
          end else if (r_rd_st) begin
            r_xfer_cmd_addr <= {8'hEB, addr_i[23:0]};
            r_send_cnt      <= 8 + 24;
            r_fsm_state     <= FSM_SEND_QUAD;
            r_fsm_state_tgt <= FSM_RD_PRE_QUAD;
            r_rd_wait_cnt   <= 4'd12;
            r_byte_cnt      <= 3'd0;
            psram_ce_o      <= 1'b0;
          end else begin
            psram_ce_o <= 1'b1;
          end
        end
        FSM_SEND: begin
          // the first bit is automatically prepared
          // before r_fsm_state <= FSM_SEND:
          // 'psram_sclk_o' should be zero, 'psram_ce_o' should be 0
          // 'psram_ce_o' will be kept 0 after 'r_fsm_state_tgt'
          psram_sclk_o <= ~psram_sclk_o;
          if (psram_sclk_o) begin
            r_send_cnt      <= r_send_cnt - 1'b1;
            r_xfer_cmd_addr <= {r_xfer_cmd_addr[30:0], 1'b1};
            if (r_send_cnt == 8'd1) begin
              r_fsm_state <= r_fsm_state_tgt;
            end
          end
        end
        FSM_SEND_QUAD: begin
          psram_sclk_o <= ~psram_sclk_o;
          if (psram_sclk_o) begin
            r_send_cnt      <= r_send_cnt - 8'd4;
            r_xfer_cmd_addr <= {r_xfer_cmd_addr[27:0], 4'd1};
            if (r_send_cnt == 8'd4) begin
              r_fsm_state <= r_fsm_state_tgt;
            end
          end
          if (r_fsm_state_tgt == FSM_WR_PRE_QUAD) rdy_nxt_byte_o <= 1'b1;
        end
        FSM_RD_PRE_QUAD: begin
          // 6 cycles
          psram_sclk_o  <= ~psram_sclk_o;
          r_rd_wait_cnt <= r_rd_wait_cnt - 1'b1;
          if (r_rd_wait_cnt == 4'd0) r_fsm_state <= FSM_RD_QUAD;
        end
        FSM_RD_QUAD: begin
          if (r_rd_end & psram_sclk_o == 1'b0 & r_byte_cnt == 3'd0) begin
            r_fsm_state <= FSM_RD2IDLE;
            r_ce_cnt    <= cfg_wait_o;
          end else psram_sclk_o <= ~psram_sclk_o;
          if (psram_sclk_o) begin
            r_byte_cnt <= r_byte_cnt + 3'd4;
            r_xfer_data <= {
              r_xfer_data[3:0], psram_sio3_i, psram_sio2_i, psram_miso_i, psram_mosi_i
            };
            if (r_byte_cnt == 3'd4) begin
              byte_avail_o <= 1'b1;
              rdata_o <= {r_xfer_data[3:0], psram_sio3_i, psram_sio2_i, psram_miso_i, psram_mosi_i};
            end else byte_avail_o <= 1'b0;
          end
        end
        FSM_WR_PRE_QUAD: begin
          r_xfer_data    <= wdata_i;
          rdy_nxt_byte_o <= 1'b0;
          r_fsm_state    <= FSM_WR_QUAD;
        end
        FSM_WR_QUAD: begin
          psram_sclk_o <= ~psram_sclk_o;
          if (psram_sclk_o) begin
            r_xfer_data <= r_byte_cnt == 3'd4 ? wdata_i : {r_xfer_data[3:0], 4'd1};
            r_byte_cnt  <= r_byte_cnt + 3'd4;
            if (r_byte_cnt == 3'd0) rdy_nxt_byte_o <= 1'b1;
            else rdy_nxt_byte_o <= 1'b0;
            if (r_we_end & r_byte_cnt == 3'd4) begin
              r_fsm_state <= FSM_WR2IDLE;
              r_ce_cnt    <= cfg_wait_o;
            end
          end
        end
        FSM_RD2IDLE: begin
          if (r_ce_cnt != cfg_wait_o) psram_ce_o <= 1'b1;
          if (r_ce_cnt == 4'd0) r_fsm_state <= FSM_IDLE;
          r_ce_cnt     <= r_ce_cnt - 1'b1;
          byte_avail_o <= 1'b0;
        end
        FSM_WR2IDLE: begin
          if (r_ce_cnt != cfg_wait_o) psram_ce_o <= 1'b1;
          if (r_ce_cnt == 4'd0) r_fsm_state <= FSM_IDLE;
          r_ce_cnt       <= r_ce_cnt - 1'b1;
          rdy_nxt_byte_o <= 1'b0;
        end
      endcase
  end
endmodule
