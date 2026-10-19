module spi_formal (
    input wire clk_i
);
  reg rst_n = 0;
  always @(posedge clk_i) rst_n <= 1;
  (* anyseq *) reg miso;
`ifndef SPI_FORMAL_BOUNDED
`ifndef SPI_FORMAL_REGISTER
  (* anyconst *) reg cpol, cpha, lsb, frame16;
  (* anyconst *) reg [15:0] divider;
  (* anyseq *) reg request_start, request_abort;
  (* anyseq *) reg [15:0] tx_data;
  wire active, done, sck, mosi;
  wire [15:0] rx_data;
  reg         closing = 0;
  always @(posedge clk_i) begin
    assume (divider >= 1 && divider <= 4);
    if (!rst_n || !active) closing <= 0;
    else if (request_abort) closing <= 1;
  end
  spi_phase_ctrl u_phase (
      .clk_i      (clk_i),
      .rst_n_i    (rst_n),
      .start_i    (request_start && !active),
      .abort_i    (request_abort || closing),
      .clamp_i    (!rst_n),
      .cpol_i     (cpol),
      .cpha_i     (cpha),
      .lsb_first_i(lsb),
      .frame16_i  (frame16),
      .divider_i  (divider),
      .tx_data_i  (tx_data),
      .miso_i     (miso),
      .active_o   (active),
      .done_o     (done),
      .sck_o      (sck),
      .mosi_o     (mosi),
      .rx_data_o  (rx_data)
  );
  spi_formal_props u_properties (
      .clk_i   (clk_i),
      .rst_n_i (rst_n),
      .active_i(active),
      .done_i  (done),
      .abort_i (request_abort || closing),
      .sck_i   (sck),
      .cpol_i  (cpol)
  );
`endif
`endif
`ifdef SPI_FORMAL_BOUNDED
  // Component contract: register legality/stability is proved separately.
  // All command values and legal FIFO service interleavings remain symbolic.
  spi_ctrl_if u_session ();
  reg [7:0] model_cycles = 0;
  always @(posedge clk_i) begin
    if (!rst_n) model_cycles <= 0;
    else if (model_cycles != 192) model_cycles <= model_cycles + 1;
    if (rst_n) cover (model_cycles == 192);
  end
  reg [4:0] session_cfg = 0;
  reg [3:0] segment_cfg = 0;
  reg [2:0] frame_count = 0;
  reg [2:0] period_value = 1;
  reg [1:0] setup_value = 1, hold_value = 1, inactive_value = 1;
  (* anyseq *)reg       update_configuration;
  (* anyseq *)reg [4:0] next_session;
  (* anyseq *)reg [3:0] next_segment;
  (* anyseq *)reg [2:0] next_count;
  (* anyseq *) reg [1:0] next_period, next_setup, next_hold, next_inactive;
  (* anyseq *) reg [8:0] command_value;
  (* anyseq *) reg [1:0] fifo_access, pending_start;
  (* anyseq *) reg [3:0] transport;
  (* anyseq *) reg route_ok, gpio_ok, handback, dma_fault, credit_fault_value;
  (* anyseq *)reg                             apb_pending;
  (* anyseq *)reg                      [31:0] payload;
  spi_pkg::configuration_t        model_cfg;
  spi_pkg::status_t               model_status;
  wire                     [31:0] claim_mask;
  wire core_sck, core_mosi, core_cs, core_oe;
  assign claim_mask = (session_cfg[3] || session_cfg[4]) ? 32'hd8000000 : 32'h98000000;
  always @* begin
    model_cfg                 = '0;
    model_cfg.session         = session_cfg;
    model_cfg.segment         = segment_cfg;
    model_cfg.frames          = {29'd0, frame_count};
    model_cfg.divider         = {13'd0, period_value};
    model_cfg.setup_cycles    = {14'd0, setup_value};
    model_cfg.hold_cycles     = {14'd0, hold_value};
    model_cfg.inactive_cycles = {14'd0, inactive_value};
    model_cfg.dummy           = 16'hffff;
    model_cfg.watermarks      = 12'h100;
  end
  assign u_session.cfg     = model_cfg;
  assign model_status      = u_session.stat;
  assign u_session.cmd     = command_value;
  assign u_session.tx_data = payload;
  assign u_session.tx_push = (fifo_access == 1) && u_session.tx_ready && command_value == 0;
  assign u_session.rx_pop  = (fifo_access == 2) && u_session.rx_ready && command_value == 0;
  always @(posedge clk_i) begin
    assume (next_count <= 5);
    assume (next_session[4:3] != 2'b11);
    assume (next_segment[2:1] != 2'd3);
    assume (next_setup != 0 && next_hold != 0 && next_inactive != 0);
    if (!rst_n) begin
      session_cfg    <= 0;
      segment_cfg    <= 0;
      frame_count    <= 0;
      period_value   <= 1;
      setup_value    <= 1;
      hold_value     <= 1;
      inactive_value <= 1;
    end else if (update_configuration && command_value == 0) begin
      if (u_session.session_writable) begin
        session_cfg    <= next_session;
        period_value   <= {1'b0, next_period} + 3'd1;
        setup_value    <= next_setup;
        hold_value     <= next_hold;
        inactive_value <= next_inactive;
      end
      if (u_session.segment_writable) begin
        segment_cfg <= next_segment;
        if (next_count != 0) frame_count <= next_count;
      end
    end
    if (rst_n) begin
      assert (model_status.status[3:0] <= 8);
      if (!gpio_ok || !route_ok) assert (!core_oe);
      cover (core_oe && !core_cs && core_sck != $past(core_sck));
      cover (u_session.events[0]);
      cover (model_status.status[3:0] == 8);
    end
  end
  spi_master_core u_session_core (
      .apb_pending_i      (apb_pending),
      .clk_i              (clk_i),
      .rst_n_i            (rst_n),
      .claim_i            (claim_mask),
      .ready_pins_i       (route_ok ? claim_mask : 32'd0),
      .gpio_ready_i       (gpio_ok),
      .handback_i         (handback),
      .dma_status_i       (transport),
      .dma_start_pending_i(pending_start),
      .dma_error_i        (dma_fault),
      .credit_fault_i     (credit_fault_value),
      .miso_i             (miso),
      .sck_o              (core_sck),
      .mosi_o             (core_mosi),
      .cs_n_o             (core_cs),
      .output_enable_o    (core_oe),
      .ctrl               (u_session)
  );
`endif
`ifdef SPI_FORMAL_REGISTER
  apb4_if u_apb (
      .pclk   (clk_i),
      .presetn(rst_n)
  );
  spi_ctrl_if u_ctrl ();
  (* anyseq *) reg [31:0] address_data, write_data, rx_data_value;
  (* anyseq *) reg selected, access_phase, writing, command_error;
  (* anyseq *)reg [1:0] ready_value;
  (* anyseq *)reg [5:0] event_value;
  (* anyseq *) reg [1:0] origin_value, credit_value, retire_value;
  (* anyseq *)reg [4:0] request_value;
  (* anyseq *)reg [2:0] channel_value;
  wire irq, credit_fault;
  wire       fifo_pending;
  wire [1:0] committed;
  reg        register_past_valid = 0;
  assign u_apb.paddr             = address_data;
  assign u_apb.pwdata            = write_data;
  assign u_apb.pstrb             = 4'hf;
  assign u_apb.pprot             = 0;
  assign u_apb.psel              = selected;
  assign u_apb.penable           = access_phase;
  assign u_apb.pwrite            = writing;
  assign u_ctrl.stat             = '0;
  assign u_ctrl.cmd_err          = command_error;
  assign u_ctrl.session_writable = 1;
  assign u_ctrl.segment_writable = 1;
  assign u_ctrl.tx_ready         = ready_value[0];
  assign u_ctrl.rx_ready         = ready_value[1];
  assign u_ctrl.rx_data          = rx_data_value;
  assign u_ctrl.events           = event_value;
  assign u_ctrl.clear_events     = 0;
  assign u_ctrl.clear_bindings   = 0;
  spi_reg u_reg (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n),
      .clock_hz_i         (32'd24000000),
      .origin_i           (origin_value),
      .request_i          (request_value),
      .channel_i          (channel_value),
      .credit_valid_i     (credit_value),
      .credit_retire_i    (retire_value),
      .dma_status_i       (4'd0),
      .dma_start_pending_i(2'd0),
      .credit_commit_o    (committed),
      .credit_pending_o   (),               // Observed through the wrapper in integration fixtures.
      .fifo_pending_o     (fifo_pending),
      .credit_fault_o     (credit_fault),
      .irq_o              (irq),
      .apb4               (u_apb),
      .ctrl               (u_ctrl)
  );
  always @(posedge clk_i) begin
    register_past_valid <= rst_n;
    if (rst_n && register_past_valid) begin
      if ($past(selected && access_phase)) assert (u_apb.pready);
      if ($past(u_ctrl.tx_push || u_ctrl.rx_pop)) assert (fifo_pending);
      if ($past(u_apb.pready)) begin
        assert (u_apb.prdata == $past(u_apb.prdata));
        assert (u_apb.pslverr == $past(u_apb.pslverr));
      end
      if (origin_value != 1) assert (committed == 0);
      if (u_apb.pready) begin
        assert (!u_ctrl.tx_push && !u_ctrl.rx_pop && u_ctrl.cmd == 0);
      end
    end
  end
`endif
endmodule
