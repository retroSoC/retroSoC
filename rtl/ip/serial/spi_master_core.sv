`include "spi_define.svh"

module spi_master_core (
    input  logic                   apb_pending_i,
    input  logic                   clk_i,
    rst_n_i,
    input  logic            [31:0] claim_i,
    ready_pins_i,
    input  logic                   gpio_ready_i,
    handback_i,
    input  logic            [ 3:0] dma_status_i,
    input  logic            [ 1:0] dma_start_pending_i,
    input  logic                   dma_error_i,
    credit_fault_i,
    miso_i,
    output logic                   sck_o,
    mosi_o,
    cs_n_o,
    output_enable_o,
           spi_ctrl_if.core        ctrl
);
  typedef struct packed {
    spi_pkg::wire_state_e state;
    logic                 owned,         pending,   complete, cs_active, gap_event,   close_done;
    logic                 guard_faulted;
    logic                 enabled;
    logic [1:0]           close_phase;
    logic [15:0]          timer;
    logic [31:0]          pins,          frames,    words,    payload,   frame_count, fault_frame;
    logic [31:0]          tx_stalls,     rx_stalls;
    logic [3:0]           segment;
    logic [7:0]           fault;
  } core_t;
  core_t s_core_d, s_core_q;
  spi_pkg::configuration_t s_cfg;
  spi_pkg::status_t        s_stat;
  logic s_transport_idle, s_clean, s_guard_fault, s_normal_fault, s_close;
  logic s_cmd_accept, s_clear, s_phase_active, s_phase_done, s_start;
  logic s_tx_ready, s_rx_ready, s_tx_frame_ready, s_rx_frame_ready, s_empty;
  logic s_tx_wait, s_rx_wait, s_last, s_data_live;
  logic [3:0] s_tx_level, s_rx_level;
  logic [15:0] s_tx_frame, s_rx_frame;
  logic [31:0] s_tx_words, s_rx_words, s_rx_removed;
  logic [63:0] s_payload, s_transport;
  logic [7:0] s_fault_code;
  // Watermarks belong exclusively to the register block's IRQ-level logic.
  logic       s_unused;
  assign s_cfg = ctrl.cfg;
  assign ctrl.stat = s_stat;
  assign s_unused = ^s_cfg.watermarks;

  assign s_transport_idle = (dma_status_i == 4'd0) &&
      (dma_start_pending_i == 2'd0) && !apb_pending_i;
  assign s_clean = !s_core_q.pending && s_empty && s_transport_idle;
  assign s_guard_fault = s_core_q.owned && s_core_q.enabled &&
      !s_core_q.guard_faulted &&
      (!gpio_ready_i || ((ready_pins_i & s_core_q.pins) != s_core_q.pins));
  assign s_normal_fault = s_core_q.owned && (s_core_q.state != spi_pkg::Disabled) &&
      (s_core_q.state != spi_pkg::Closing) &&
      (dma_error_i || credit_fault_i);
  assign s_fault_code = !gpio_ready_i ? 8'd2 : s_guard_fault ? 8'd1 : dma_error_i ? 8'd3 : 8'd4;
  assign s_close = s_guard_fault || s_normal_fault || (s_cmd_accept && ctrl.cmd[`APB4_SPI__ABORT]);
  assign s_payload = {32'd0, s_cfg.frames} << (s_cfg.segment[0] ? 1 : 0);
  assign s_transport = (s_payload + 64'd3) & 64'hffff_ffff_ffff_fffc;
  assign s_data_live = s_core_q.pending && (s_core_q.state != spi_pkg::Closing) && !s_close;
  assign ctrl.session_writable = (s_core_q.state == spi_pkg::Disabled) &&
      !s_core_q.owned && s_transport_idle;
  assign ctrl.segment_writable = s_transport_idle && !s_guard_fault && !s_normal_fault &&
      ((!s_core_q.owned && (s_core_q.state == spi_pkg::Disabled)) ||
       (s_clean && ((s_core_q.state == spi_pkg::Idle) || (s_core_q.state == spi_pkg::Held))));
  always_comb begin
    ctrl.cmd_err = 1'b0;
    unique case (ctrl.cmd)
      9'd0: ctrl.cmd_err = 1'b0;
      9'b000000001:
      ctrl.cmd_err = (s_core_q.state != spi_pkg::Disabled) ||
          s_core_q.owned || !s_clean || !gpio_ready_i || (ready_pins_i != claim_i);
      9'b000000010: ctrl.cmd_err = (s_core_q.state != spi_pkg::Idle) || !s_clean;
      9'b000000100:
      ctrl.cmd_err = !ctrl.segment_writable || !s_core_q.owned ||
          (s_cfg.frames == 32'd0) || (s_transport > 64'hffff_fffc) ||
          (s_cfg.segment[2:1] == 2'd3) ||
          ((s_cfg.segment[2:1] != 2'd0) && !s_cfg.session[3]) ||
          ((s_cfg.segment[2:1] == 2'd0) && s_cfg.rx_binding[31]) ||
          ((s_cfg.segment[2:1] == 2'd2) && s_cfg.tx_binding[31]);
      9'b000001000: ctrl.cmd_err = (s_core_q.state != spi_pkg::Armed);
      9'b000010000: ctrl.cmd_err = (s_core_q.state != spi_pkg::Held) || !s_clean;
      9'b000100000: ctrl.cmd_err = !s_core_q.owned;
      9'b001000000:
      ctrl.cmd_err = (s_core_q.state != spi_pkg::Closing) ||
          !s_core_q.close_done || !s_transport_idle;
      9'b010000000:
      ctrl.cmd_err = (s_core_q.state != spi_pkg::Disabled) ||
          !s_core_q.owned || !s_clean || !handback_i ||
          s_cfg.tx_binding[31] || s_cfg.rx_binding[31];
      9'b100000000: ctrl.cmd_err = !ctrl.session_writable;
      default: ctrl.cmd_err = 1'b1;
    endcase
    if ((ctrl.cmd != 9'd0) && (s_guard_fault || s_normal_fault)) ctrl.cmd_err = 1'b1;
  end
  assign s_cmd_accept = (ctrl.cmd != 9'd0) && !ctrl.cmd_err;
  assign s_clear = s_cmd_accept && (ctrl.cmd[`APB4_SPI__ARM] ||
      ctrl.cmd[`APB4_SPI__RECOVER] || ctrl.cmd[`APB4_SPI__RESET]);
  assign ctrl.clear_events = s_cmd_accept &&
      (ctrl.cmd[`APB4_SPI__RECOVER] || ctrl.cmd[`APB4_SPI__RESET]);
  assign ctrl.clear_bindings = s_cmd_accept && (ctrl.cmd[`APB4_SPI__DISABLE] ||
      ctrl.cmd[`APB4_SPI__RECOVER] || ctrl.cmd[`APB4_SPI__RESET]);
  assign ctrl.tx_ready = s_data_live && s_tx_ready && (s_core_q.segment[2:1] != 2'd2);
  assign ctrl.rx_ready = s_data_live && s_rx_ready && (s_core_q.segment[2:1] != 2'd0);
  assign s_start = (s_core_q.state == spi_pkg::Shift) && !s_phase_active &&
      (s_core_q.frames < s_core_q.frame_count) && s_tx_frame_ready && s_rx_frame_ready && !s_close;
  assign s_last = s_core_q.frames == (s_core_q.frame_count - 32'd1);
  assign s_tx_wait = (s_core_q.state == spi_pkg::Shift) && !s_phase_active && !s_tx_frame_ready;
  assign s_rx_wait = (s_core_q.state == spi_pkg::Shift) && !s_phase_active && !s_rx_frame_ready;
  assign cs_n_o = !(s_core_q.cs_active && !s_guard_fault);
  assign output_enable_o = s_core_q.owned && s_core_q.enabled &&
      gpio_ready_i && ((ready_pins_i & s_core_q.pins) == s_core_q.pins);

  always_comb begin
    s_core_d    = s_core_q;
    ctrl.events = '0;
    if (s_core_q.pending && s_core_q.complete && s_empty && s_transport_idle &&
        ((s_core_q.segment[2:1] == 2'd2) || (s_tx_words == s_core_q.words)) &&
        ((s_core_q.segment[2:1] == 2'd0) ||
         ((s_rx_words == s_core_q.words) && (s_rx_removed == s_core_q.words))))
      s_core_d.pending = 1'b0;
    if (s_tx_wait && !s_close) begin
      ctrl.events[4] = 1'b1;
      if (s_core_q.tx_stalls != 32'hffff_ffff) s_core_d.tx_stalls = s_core_q.tx_stalls + 32'd1;
    end
    if (s_rx_wait && !s_close) begin
      ctrl.events[5] = 1'b1;
      if (s_core_q.rx_stalls != 32'hffff_ffff) s_core_d.rx_stalls = s_core_q.rx_stalls + 32'd1;
    end
    unique case (s_core_q.state)
      spi_pkg::Disabled, spi_pkg::Idle, spi_pkg::Armed, spi_pkg::Held: ;
      spi_pkg::Setup: begin
        if (s_core_q.timer == 16'd0) s_core_d.state = spi_pkg::Shift;
        else s_core_d.timer = s_core_q.timer - 16'd1;
      end
      spi_pkg::Shift: begin
        if (s_phase_done) begin
          s_core_d.frames = s_core_q.frames + 32'd1;
          if (s_last) begin
            s_core_d.state = spi_pkg::Hold;
            s_core_d.timer = s_cfg.hold_cycles - 16'd1;
          end
        end
      end
      spi_pkg::Hold: begin
        if (s_core_q.timer != 16'd0) s_core_d.timer = s_core_q.timer - 16'd1;
        else begin
          ctrl.events[0]    = 1'b1;
          s_core_d.complete = 1'b1;
          if (s_core_q.segment[3]) s_core_d.state = spi_pkg::Held;
          else begin
            s_core_d.state     = spi_pkg::Gap;
            s_core_d.cs_active = 1'b0;
            s_core_d.gap_event = 1'b1;
            s_core_d.timer     = s_cfg.inactive_cycles - 16'd1;
          end
        end
      end
      spi_pkg::Gap: begin
        if (s_core_q.timer != 16'd0) s_core_d.timer = s_core_q.timer - 16'd1;
        else begin
          s_core_d.state     = spi_pkg::Idle;
          ctrl.events[1]     = s_core_q.gap_event;
          s_core_d.gap_event = 1'b0;
        end
      end
      spi_pkg::Closing: begin
        if (!s_core_q.close_done) begin
          if (s_core_q.close_phase == 2'd0) begin
            if (!s_phase_active) begin
              s_core_d.close_phase = 2'd1;
              s_core_d.timer       = s_cfg.hold_cycles - 16'd1;
            end
          end else if (s_core_q.timer != 16'd0) s_core_d.timer = s_core_q.timer - 16'd1;
          else if (s_core_q.close_phase == 2'd1) begin
            s_core_d.cs_active   = 1'b0;
            s_core_d.close_phase = 2'd2;
            s_core_d.timer       = s_cfg.inactive_cycles - 16'd1;
          end else begin
            s_core_d.close_done = 1'b1;
            ctrl.events[2]      = (s_core_q.fault == 8'd0);
          end
        end
      end
      default: begin
        s_core_d.state      = spi_pkg::Closing;
        s_core_d.close_done = 1'b1;
        s_core_d.cs_active  = 1'b0;
        s_core_d.fault      = 8'd5;
        ctrl.events[3]      = 1'b1;
      end
    endcase
    if (s_cmd_accept) begin
      unique case (ctrl.cmd)
        9'b000000001: begin
          s_core_d.owned     = 1'b1;
          s_core_d.enabled   = 1'b1;
          s_core_d.pins      = claim_i;
          s_core_d.state     = spi_pkg::Gap;
          s_core_d.gap_event = 1'b0;
          s_core_d.timer     = s_cfg.inactive_cycles - 16'd1;
        end
        9'b000000010: begin
          s_core_d.state   = spi_pkg::Disabled;
          s_core_d.enabled = 1'b0;
        end
        9'b000000100: begin
          s_core_d.state       = spi_pkg::Armed;
          s_core_d.segment     = s_cfg.segment;
          s_core_d.frame_count = s_cfg.frames;
          s_core_d.words       = s_transport[33:2];
          s_core_d.payload     = s_payload[31:0];
          s_core_d.frames      = '0;
          s_core_d.tx_stalls   = '0;
          s_core_d.rx_stalls   = '0;
          s_core_d.complete    = 1'b0;
          s_core_d.pending     = 1'b1;
        end
        9'b000001000: begin
          s_core_d.state     = spi_pkg::Setup;
          s_core_d.cs_active = 1'b1;
          s_core_d.timer     = s_cfg.setup_cycles - 16'd1;
        end
        9'b000010000: begin
          s_core_d.state     = spi_pkg::Gap;
          s_core_d.cs_active = 1'b0;
          s_core_d.gap_event = 1'b1;
          s_core_d.timer     = s_cfg.inactive_cycles - 16'd1;
        end
        9'b001000000: begin
          s_core_d       = '0;
          s_core_d.owned = s_core_q.owned;
          s_core_d.pins  = s_core_q.pins;
          s_core_d.state = spi_pkg::Disabled;
        end
        9'b010000000: begin
          s_core_d.owned = 1'b0;
          s_core_d.pins  = '0;
        end
        9'b100000000: s_core_d = '0;
        default:      ;
      endcase
    end
    if (s_close && ((s_core_q.state != spi_pkg::Closing) || s_guard_fault)) begin
      s_core_d.state       = spi_pkg::Closing;
      s_core_d.complete    = 1'b0;
      s_core_d.close_phase = '0;
      s_core_d.close_done  = s_guard_fault;
      ctrl.events[1:0]     = '0;
      if (s_guard_fault) begin
        s_core_d.cs_active     = 1'b0;
        s_core_d.guard_faulted = 1'b1;
        s_core_d.enabled       = 1'b0;
      end
      if (s_guard_fault || s_normal_fault) begin
        ctrl.events[3] = 1'b1;
        if (s_core_q.fault == 8'd0) begin
          s_core_d.fault       = s_fault_code;
          s_core_d.fault_frame = s_core_q.frames;
        end
      end
    end
  end
  always_comb begin
    s_stat = '0;
    s_stat.status[3:0] = s_core_q.state;
    s_stat.status[4] = s_core_q.cs_active;
    s_stat.status[5] = s_core_q.owned;
    s_stat.status[6] = s_core_q.pending;
    s_stat.status[7] = s_clean;
    s_stat.status[8] = s_tx_wait;
    s_stat.status[9] = s_rx_wait;
    s_stat.status[10] = !s_core_q.cs_active &&
        ((s_core_q.state == spi_pkg::Idle) || (s_core_q.state == spi_pkg::Disabled));
    s_stat.status[11] = s_transport_idle;
    s_stat.status[12] = gpio_ready_i && (ready_pins_i == claim_i);
    s_stat.levels = {20'd0, s_rx_level, 4'd0, s_tx_level};
    s_stat.fault = {24'd0, s_core_q.fault};
    s_stat.fault_frame = s_core_q.fault_frame;
    s_stat.frames = s_core_q.frames;
    s_stat.words = s_core_q.words;
    s_stat.tx_words = s_tx_words;
    s_stat.rx_words = s_rx_words;
    s_stat.rx_removed = s_rx_removed;
    s_stat.tx_stalls = s_core_q.tx_stalls;
    s_stat.rx_stalls = s_core_q.rx_stalls;
    s_stat.pins = s_core_q.pins;
    s_stat.ready_pins = ready_pins_i & s_core_q.pins;
    s_stat.payload = s_core_q.payload;
  end
  dffr #(
      .DATA_WIDTH($bits(core_t))
  ) u_core (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_core_d),
      .dat_o  (s_core_q)
  );
  spi_phase_ctrl u_phase_ctrl (
      .clk_i      (clk_i),
      .rst_n_i    (rst_n_i),
      .start_i    (s_start),
      .abort_i    (s_close || (s_core_q.state == spi_pkg::Closing)),
      .clamp_i    (!output_enable_o),
      .cpol_i     (s_cfg.session[0]),
      .cpha_i     (s_cfg.session[1]),
      .lsb_first_i(s_cfg.session[2]),
      .frame16_i  (s_core_q.segment[0]),
      .divider_i  (s_cfg.divider),
      .tx_data_i  ((s_core_q.segment[2:1] == 2'd2) ? s_cfg.dummy : s_tx_frame),
      .miso_i     (miso_i && s_cfg.session[3]),
      .active_o   (s_phase_active),
      .done_o     (s_phase_done),
      .sck_o      (sck_o),
      .mosi_o     (mosi_o),
      .rx_data_o  (s_rx_frame)
  );
  spi_word_packer u_word_packer (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .clear_i         (s_clear),
      .frame16_i       (s_core_q.segment[0]),
      .direction_i     (s_core_q.segment[2:1]),
      .quota_i         (s_core_q.words),
      .tx_data_i       (ctrl.tx_data),
      .tx_push_i       (ctrl.tx_push),
      .rx_pop_i        (ctrl.rx_pop),
      .frame_start_i   (s_start),
      .frame_done_i    (s_phase_done && !s_close),
      .last_frame_i    (s_last),
      .rx_frame_i      (s_rx_frame),
      .tx_frame_o      (s_tx_frame),
      .rx_data_o       (ctrl.rx_data),
      .tx_words_o      (s_tx_words),
      .rx_words_o      (s_rx_words),
      .rx_removed_o    (s_rx_removed),
      .tx_ready_o      (s_tx_ready),
      .rx_ready_o      (s_rx_ready),
      .tx_frame_ready_o(s_tx_frame_ready),
      .rx_frame_ready_o(s_rx_frame_ready),
      .empty_o         (s_empty),
      .tx_level_o      (s_tx_level),
      .rx_level_o      (s_rx_level)
  );
`ifdef FORMAL
  always_ff @(posedge clk_i) begin
    if (rst_n_i) begin
      assert (s_core_q.state <= spi_pkg::Closing);
      assert (s_tx_level <= 4'd8 && s_rx_level <= 4'd8);
      assert (s_tx_words <= s_core_q.words);
      assert (s_rx_words <= s_core_q.words);
      assert (s_rx_removed <= s_rx_words);
      assert (!ctrl.tx_push || (ctrl.tx_ready && !s_close));
      assert (!ctrl.rx_pop || (ctrl.rx_ready && !s_close));
    end
  end
`endif
endmodule
