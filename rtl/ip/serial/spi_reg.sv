`include "spi_define.svh"

// The private qualifier is captured with this APB access, never taken from PPROT.
module spi_reg (
    input  logic                        clk_i,
    rst_n_i,
    input  logic                 [31:0] clock_hz_i,
    input  logic                 [ 1:0] origin_i,
    input  logic                 [ 4:0] request_i,
    input  logic                 [ 2:0] channel_i,
    input  logic                 [ 1:0] credit_valid_i,
    credit_retire_i,
    input  logic                 [ 3:0] dma_status_i,
    input  logic                 [ 1:0] dma_start_pending_i,
    output logic                 [ 1:0] credit_commit_o,
    output logic                 [ 1:0] credit_pending_o,
    output logic                        fifo_pending_o,
    output logic                        credit_fault_o,
    irq_o,
           apb4_if.slave                apb4,
           spi_ctrl_if.registers        ctrl
);
  localparam spi_pkg::configuration_t ResetCfg = {
    5'd0, 16'd1, 16'd1, 16'd1, 16'd1, 4'd0, 32'd0, 16'hffff, 32'd0, 32'd0, 12'h100
  };
  spi_pkg::configuration_t s_cfg_d, s_cfg_q;
  spi_pkg::status_t s_stat;
  logic s_req, s_req_accept, s_access_err, s_ready_d, s_ready_q;
  logic s_resp_err_d, s_resp_err_q;
  logic [31:0] s_rdata_d, s_rdata_q, s_read_data;
  logic [5:0] s_irq_d, s_irq_q, s_irq_clear;
  logic [9:0] s_irq_en_d, s_irq_en_q, s_irq_stat;
  logic [1:0] s_credit_used_d, s_credit_used_q;
  logic s_data_access_d, s_data_access_q;
  logic s_cpu, s_tx_sel, s_rx_sel, s_dma_tx, s_dma_rx, s_tx_qualified, s_rx_qualified;
  logic s_session_write, s_segment_write;
  logic [11:0] s_offset;
  assign s_stat = ctrl.stat;
  assign ctrl.cfg = s_cfg_q;
  assign s_req = apb4.psel && apb4.penable;
  assign s_req_accept = s_req && !s_ready_q;
  assign s_offset = apb4.paddr[11:0];
  assign s_cpu = origin_i == 2'd0;
  assign s_dma_tx = s_offset == `APB4_SPI__DMA_TXDATA;
  assign s_dma_rx = s_offset == `APB4_SPI__DMA_RXDATA;
  assign s_tx_sel = s_dma_tx || (s_offset == `APB4_SPI__CPU_TXDATA);
  assign s_rx_sel = s_dma_rx || (s_offset == `APB4_SPI__CPU_RXDATA);
  assign s_tx_qualified = (origin_i == 2'd1) && (request_i == 5'd16) &&
      s_cfg_q.tx_binding[31] && (channel_i == s_cfg_q.tx_binding[2:0]) &&
      credit_valid_i[0] && !s_credit_used_q[0];
  assign s_rx_qualified = (origin_i == 2'd1) && (request_i == 5'd17) &&
      s_cfg_q.rx_binding[31] && (channel_i == s_cfg_q.rx_binding[2:0]) &&
      credit_valid_i[1] && !s_credit_used_q[1];
  assign credit_pending_o = credit_valid_i | s_credit_used_q;
  assign fifo_pending_o = s_ready_q && s_data_access_q;
  assign s_data_access_d = s_req_accept ? (s_tx_sel || s_rx_sel) : s_data_access_q;
  assign credit_fault_o = s_req_accept && (origin_i == 2'd1) && s_stat.status[5] &&
      ((s_dma_tx && (!s_tx_qualified || !apb4.pwrite || (apb4.pstrb != 4'hf) ||
        (s_stat.tx_words >= s_stat.words) || (s_stat.levels[3:0] == 4'd8))) ||
       (s_dma_rx && (!s_rx_qualified || apb4.pwrite ||
        (s_stat.rx_removed >= s_stat.rx_words) || (s_stat.rx_removed >= s_stat.words))));
  assign s_session_write = ctrl.session_writable;
  assign s_segment_write = ctrl.segment_writable && (dma_start_pending_i == 2'd0);
  assign ctrl.cmd = (s_req_accept && s_cpu && apb4.pwrite &&
      (s_offset == `APB4_SPI__COMMAND) && (apb4.paddr[1:0] == 2'd0) &&
      (apb4.pstrb == 4'hf) && (apb4.pwdata[31:9] == 23'd0)) ? apb4.pwdata[8:0] : 9'd0;
  assign s_irq_stat = s_irq_en_q &
      { (s_stat.levels[11:8] >= s_cfg_q.watermarks[11:8]),
        (s_stat.levels[3:0] <= s_cfg_q.watermarks[3:0]), 2'd0, s_irq_q };
  assign irq_o = (s_irq_stat != 10'd0);
  assign apb4.pready = s_ready_q;
  assign apb4.prdata = s_rdata_q;
  assign apb4.pslverr = s_resp_err_q;

  always_comb begin
    s_cfg_d = s_cfg_q;
    s_read_data = '0;
    s_irq_en_d = s_irq_en_q;
    s_irq_clear = '0;
    ctrl.tx_data = apb4.pwdata;
    ctrl.tx_push = 1'b0;
    ctrl.rx_pop = 1'b0;
    credit_commit_o = '0;
    s_credit_used_d = s_credit_used_q & ~credit_retire_i;
    s_access_err = (apb4.paddr[1:0] != 2'd0) ||
        (apb4.pwrite && (apb4.pstrb != 4'hf)) ||
        (!s_cpu && !(s_dma_tx || s_dma_rx));
    unique case (s_offset)
      `APB4_SPI__IP_ID:             s_read_data = `APB4_SPI__ID_VALUE;
      `APB4_SPI__IP_VERSION:        s_read_data = `APB4_SPI__VERSION_VALUE;
      `APB4_SPI__CAPABILITY:        s_read_data = `APB4_SPI__CAPABILITY_VALUE;
      `APB4_SPI__FIFO_CAPABILITY:   s_read_data = `APB4_SPI__FIFO_VALUE;
      `APB4_SPI__CLOCK_HZ:          s_read_data = clock_hz_i;
      `APB4_SPI__ROUTABLE_MASK:     s_read_data = `APB4_SPI__ROUTES_VALUE;
      `APB4_SPI__STATUS:            s_read_data = s_stat.status;
      `APB4_SPI__FIFO_LEVELS:       s_read_data = s_stat.levels;
      `APB4_SPI__FAULT_CODE:        s_read_data = s_stat.fault;
      `APB4_SPI__FAULT_FRAME:       s_read_data = s_stat.fault_frame;
      `APB4_SPI__FRAMES_DONE:       s_read_data = s_stat.frames;
      `APB4_SPI__TRANSPORT_WORDS:   s_read_data = s_stat.words;
      `APB4_SPI__TX_WORDS_ACCEPTED: s_read_data = s_stat.tx_words;
      `APB4_SPI__RX_WORDS_PRODUCED: s_read_data = s_stat.rx_words;
      `APB4_SPI__RX_WORDS_REMOVED:  s_read_data = s_stat.rx_removed;
      `APB4_SPI__TX_STALL_CYCLES:   s_read_data = s_stat.tx_stalls;
      `APB4_SPI__RX_STALL_CYCLES:   s_read_data = s_stat.rx_stalls;
      `APB4_SPI__SESSION_PINS:      s_read_data = s_stat.pins;
      `APB4_SPI__DMA_STATUS:        s_read_data = {28'd0, dma_status_i};
      `APB4_SPI__PINS_READY:        s_read_data = s_stat.ready_pins;
      `APB4_SPI__PAYLOAD_BYTES:     s_read_data = s_stat.payload;
      `APB4_SPI__IRQ_STATUS:        s_read_data = {22'd0, s_irq_stat};
      `APB4_SPI__SESSION_CFG:       s_read_data = {27'd0, s_cfg_q.session};
      `APB4_SPI__DIV:               s_read_data = {16'd0, s_cfg_q.divider};
      `APB4_SPI__CS_SETUP:          s_read_data = {16'd0, s_cfg_q.setup_cycles};
      `APB4_SPI__CS_HOLD:           s_read_data = {16'd0, s_cfg_q.hold_cycles};
      `APB4_SPI__CS_INACTIVE:       s_read_data = {16'd0, s_cfg_q.inactive_cycles};
      `APB4_SPI__SEG_CONFIG:        s_read_data = {28'd0, s_cfg_q.segment};
      `APB4_SPI__FRAME_COUNT:       s_read_data = s_cfg_q.frames;
      `APB4_SPI__DUMMY:             s_read_data = {16'd0, s_cfg_q.dummy};
      `APB4_SPI__TX_BIND:           s_read_data = s_cfg_q.tx_binding;
      `APB4_SPI__RX_BIND:           s_read_data = s_cfg_q.rx_binding;
      `APB4_SPI__WATERMARKS:        s_read_data = {20'd0, s_cfg_q.watermarks};
      `APB4_SPI__IRQ_STATE:         s_read_data = {26'd0, s_irq_q};
      `APB4_SPI__IRQ_ENABLE:        s_read_data = {22'd0, s_irq_en_q};
      `APB4_SPI__COMMAND: begin
        if (!apb4.pwrite || (apb4.pwdata[31:9] != 23'd0)) s_access_err = 1'b1;
        if (ctrl.cmd_err) s_access_err = 1'b1;
      end
      `APB4_SPI__CPU_TXDATA, `APB4_SPI__DMA_TXDATA: begin
        if (!apb4.pwrite || !ctrl.tx_ready ||
            (s_dma_tx ? !s_tx_qualified : (!s_cpu || s_cfg_q.tx_binding[31])))
          s_access_err = 1'b1;
      end
      `APB4_SPI__CPU_RXDATA, `APB4_SPI__DMA_RXDATA: begin
        s_read_data = ctrl.rx_data;
        if (apb4.pwrite || !ctrl.rx_ready ||
            (s_dma_rx ? !s_rx_qualified : (!s_cpu || s_cfg_q.rx_binding[31])))
          s_access_err = 1'b1;
      end
      default:                      s_access_err = 1'b1;
    endcase
    if (s_req_accept && apb4.pwrite) begin
      unique case (s_offset)
        `APB4_SPI__SESSION_CFG: begin
          if (!s_session_write || (apb4.pwdata[31:5] != 27'd0) || (apb4.pwdata[4:3] == 2'b11))
            s_access_err = 1'b1;
          s_cfg_d.session = apb4.pwdata[4:0];
        end
        `APB4_SPI__DIV, `APB4_SPI__CS_SETUP, `APB4_SPI__CS_HOLD, `APB4_SPI__CS_INACTIVE: begin
          if (!s_session_write || (apb4.pwdata[31:16] != 16'd0) || (apb4.pwdata[15:0] == 16'd0))
            s_access_err = 1'b1;
          unique case (s_offset)
            `APB4_SPI__DIV:      s_cfg_d.divider = apb4.pwdata[15:0];
            `APB4_SPI__CS_SETUP: s_cfg_d.setup_cycles = apb4.pwdata[15:0];
            `APB4_SPI__CS_HOLD:  s_cfg_d.hold_cycles = apb4.pwdata[15:0];
            default:             s_cfg_d.inactive_cycles = apb4.pwdata[15:0];
          endcase
        end
        `APB4_SPI__SEG_CONFIG: begin
          if (!s_segment_write || (apb4.pwdata[31:4] != 28'd0) || (apb4.pwdata[2:1] == 2'd3))
            s_access_err = 1'b1;
          s_cfg_d.segment = apb4.pwdata[3:0];
        end
        `APB4_SPI__FRAME_COUNT: begin
          if (!s_segment_write || (apb4.pwdata == 32'd0)) s_access_err = 1'b1;
          s_cfg_d.frames = apb4.pwdata;
        end
        `APB4_SPI__DUMMY: begin
          if (!s_segment_write || (apb4.pwdata[31:16] != 16'd0)) s_access_err = 1'b1;
          s_cfg_d.dummy = apb4.pwdata[15:0];
        end
        `APB4_SPI__TX_BIND, `APB4_SPI__RX_BIND: begin
          if (!s_segment_write || ((apb4.pwdata & 32'h7fff_fff8) != 32'd0)) s_access_err = 1'b1;
          if (s_offset == `APB4_SPI__TX_BIND) s_cfg_d.tx_binding = apb4.pwdata;
          else s_cfg_d.rx_binding = apb4.pwdata;
          if (s_cfg_d.tx_binding[31] && s_cfg_d.rx_binding[31] &&
              (s_cfg_d.tx_binding[2:0] == s_cfg_d.rx_binding[2:0]))
            s_access_err = 1'b1;
        end
        `APB4_SPI__WATERMARKS: begin
          if (((apb4.pwdata & 32'hffff_f0f0) != 32'd0) ||
              (apb4.pwdata[3:0] > 4'd8) || (apb4.pwdata[11:8] == 4'd0) ||
              (apb4.pwdata[11:8] > 4'd8))
            s_access_err = 1'b1;
          s_cfg_d.watermarks = apb4.pwdata[11:0];
        end
        `APB4_SPI__IRQ_STATE: begin
          if (apb4.pwdata[31:6] != 26'd0) s_access_err = 1'b1;
          s_irq_clear = apb4.pwdata[5:0];
        end
        `APB4_SPI__IRQ_ENABLE: begin
          if ((apb4.pwdata & 32'hffff_fcc0) != 32'd0) s_access_err = 1'b1;
          s_irq_en_d = apb4.pwdata[9:0];
        end
        `APB4_SPI__COMMAND, `APB4_SPI__CPU_TXDATA, `APB4_SPI__DMA_TXDATA: ;
        default:                                                          s_access_err = 1'b1;
      endcase
    end
    if (s_access_err) begin
      s_cfg_d     = s_cfg_q;
      s_irq_en_d  = s_irq_en_q;
      s_irq_clear = '0;
    end
    if (s_req_accept && !s_access_err) begin
      ctrl.tx_push    = s_tx_sel && apb4.pwrite;
      ctrl.rx_pop     = s_rx_sel && !apb4.pwrite;
      credit_commit_o = {ctrl.rx_pop && s_dma_rx, ctrl.tx_push && s_dma_tx};
      s_credit_used_d = s_credit_used_d | credit_commit_o;
    end
    s_irq_d = ctrl.clear_events ? 6'd0 : ((s_irq_q & ~s_irq_clear) | ctrl.events);
    if (ctrl.clear_bindings) begin
      s_cfg_d.tx_binding = '0;
      s_cfg_d.rx_binding = '0;
    end
    if (s_req_accept && !s_access_err && ctrl.cmd[`APB4_SPI__RESET]) begin
      s_cfg_d    = ResetCfg;
      s_irq_en_d = '0;
    end
    s_ready_d    = s_req;
    s_rdata_d    = s_req_accept ? s_read_data : s_rdata_q;
    s_resp_err_d = s_req_accept ? s_access_err : s_resp_err_q;
  end
  dffrc #(
      .DATA_WIDTH($bits(spi_pkg::configuration_t)),
      .RESET_VAL (ResetCfg)
  ) u_configuration (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_cfg_d),
      .dat_o  (s_cfg_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_response_ready (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ready_d),
      .dat_o  (s_ready_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_response_data (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rdata_d),
      .dat_o  (s_rdata_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_response_error (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_resp_err_d),
      .dat_o  (s_resp_err_q)
  );
  dffr #(
      .DATA_WIDTH(6)
  ) u_irq_state (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_irq_d),
      .dat_o  (s_irq_q)
  );
  dffr #(
      .DATA_WIDTH(10)
  ) u_irq_enable (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_irq_en_d),
      .dat_o  (s_irq_en_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_credit_used (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_credit_used_d),
      .dat_o  (s_credit_used_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_data_access (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_data_access_d),
      .dat_o  (s_data_access_q)
  );
`ifdef FORMAL
  always_ff @(posedge clk_i) begin
    if (rst_n_i) begin
      assert ((credit_commit_o & s_credit_used_q) == 2'd0);
      if (origin_i != 2'd1) assert (credit_commit_o == 2'd0);
      assert (!ctrl.tx_push || ctrl.tx_ready);
      assert (!ctrl.rx_pop || ctrl.rx_ready);
      if (s_dma_tx && !s_tx_qualified) assert (!ctrl.tx_push);
      if (s_dma_rx && !s_rx_qualified) assert (!ctrl.rx_pop);
    end
  end
`endif
endmodule
