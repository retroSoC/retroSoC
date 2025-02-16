module psram_top (
    input         clk_i,
    input         rst_n_i,
    input         cfg_wr_en_i,
    input  [ 3:0] cfg_wait_i,
    output [ 3:0] cfg_wait_o,
    input         mem_valid_i,
    output        mem_ready_o,
    input  [23:0] mem_addr_i,
    input  [31:0] mem_wdata_i,
    input  [ 3:0] mem_wstrb_i,
    output [31:0] mem_rdata_o,
    output        psram_sclk_o,
    output        psram_ce_o,
    input         psram_miso_i,
    input         psram_mosi_i,
    input         psram_sio2_i,
    input         psram_sio3_i,
    output        psram_mosi_o,
    output        psram_miso_o,
    output        psram_sio2_o,
    output        psram_sio3_o,
    output        psram_sio_oen_o
);

  localparam FSM_IDLE = 0;
  localparam FSM_WE_ST = 1;
  localparam FSM_WE = 2;
  localparam FSM_RD_ST = 3;
  localparam FSM_RD = 4;

  reg         r_rd_st;
  reg         r_wr_st;
  reg  [ 7:0] r_xfer_data_bit_cnt;
  reg  [ 5:0] r_fsm_state;
  reg  [23:0] r_mem_addr;
  reg  [31:0] r_mem_wdata;

  wire [ 1:0] s_disp_addr_ofst;
  wire [ 7:0] s_disp_xfer_bit_cnt;
  wire [31:0] s_disp_wdata;
  wire        s_core_idle;

  always @(posedge clk_i or negedge rst_n_i) begin
    if (~rst_n_i) begin
      r_rd_st             <= 1'b0;
      r_wr_st             <= 1'b0;
      r_xfer_data_bit_cnt <= 8'd0;
      r_fsm_state         <= FSM_IDLE;
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
            r_xfer_data_bit_cnt <= 3'd4;
            r_mem_addr          <= mem_addr_i;
            r_mem_wdata         <= mem_wdata_i;  // TODO: no need
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
      .cfg_wr_en_i        (cfg_wr_en_i),
      .cfg_wait_i         (cfg_wait_i),
      .cfg_wait_o         (cfg_wait_o),
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
      .psram_miso_i       (psram_miso_i),
      .psram_mosi_i       (psram_mosi_i),
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
    input      [ 3:0] wstrb_i,
    input      [31:0] wdata_i,
    output reg [ 1:0] addr_ofst_o,
    output reg [ 7:0] xfer_bit_cnt_o,
    output reg [31:0] wdata_o
);
  always @(*) begin
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
