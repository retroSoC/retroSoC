`include "piolite_define.svh"

module piolite_reg (
    input  logic                       clk_i,
    input  logic                       rst_n_i,
    input  logic                [31:0] clock_hz_i,
    input  logic                [31:0] user_select_i,
    input  logic                       tx_job_i,
    input  logic                       rx_job_i,
    input  logic                       tx_held_i,
    input  logic                       rx_held_i,
    input  logic                       tx_closing_i,
    input  logic                       rx_closing_i,
    output logic                       irq_o,
           apb4_if.slave               apb4,
           piolite_if.registers        ctrl
);
  localparam piolite_pkg::sm_config_t ResetSmCfg = '{
      options: 5'd0,
      divider: 16'd1,
      base: 5'd0,
      length: 6'd0,
      entry: 5'd0,
      wrap_bottom: 5'd0,
      wrap_top: 5'd0,
      in_pins: '{base: 5'd0, width: 6'd0},
      out_pins: '{base: 5'd0, width: 6'd0},
      set_pins: '{base: 5'd0, width: 6'd0},
      claim_mask: 32'd0,
      output_mask: 32'd0,
      initial_value: 32'd0,
      initial_oe: 32'd0,
      initial_x: 16'd0,
      initial_y: 16'd0,
      tx_bits: 6'd32,
      rx_bits: 6'd32,
      test_pin: 5'd0,
      test_flag: 2'd0,
      tx_low: 4'd0,
      rx_high: 4'd1
  };

  piolite_pkg::sm_config_t        s_cfg_d          [0:1];
  piolite_pkg::sm_config_t        s_cfg_q          [0:1];
  logic                    [31:0] s_tx_bind_d;
  logic                    [31:0] s_tx_bind_q;
  logic                    [31:0] s_rx_bind_d;
  logic                    [31:0] s_rx_bind_q;
  logic                    [ 5:0] s_event_en_d     [0:1];
  logic                    [ 5:0] s_event_en_q     [0:1];
  logic                    [27:0] s_irq_en_d;
  logic                    [27:0] s_irq_en_q;
  logic                           s_req;
  logic                           s_req_accept;
  logic                           s_access_err;
  logic                           s_ready_d;
  logic                           s_ready_q;
  logic                           s_resp_err_d;
  logic                           s_resp_err_q;
  logic                    [31:0] s_rdata_d;
  logic                    [31:0] s_rdata_q;
  logic                    [31:0] s_read_data;
  logic                    [11:0] s_offset;
  logic                    [ 6:0] s_sm_offset;
  logic                           s_sm_access;
  logic                           s_imem_access;
  logic                           s_sm_index;
  logic                    [ 1:0] s_cfg_writable;
  logic                    [ 1:0] s_dma_busy;
  logic                           s_start_ok;
  logic                           s_bind_ok;
  logic                           s_block_reset_ok;
  logic                    [31:0] s_region;
  logic                    [27:0] s_irq_sources;

  assign s_req               = apb4.psel && apb4.penable;
  assign s_req_accept        = s_req && !s_ready_q;
  assign s_offset            = apb4.paddr[11:0];
  assign s_sm_access         = (apb4.paddr[11:9] == 3'b001) && !apb4.paddr[8];
  assign s_imem_access       = (apb4.paddr[11:8] == 4'h1) && !apb4.paddr[7];
  assign s_sm_index          = apb4.paddr[7];
  assign s_sm_offset         = apb4.paddr[6:0];
  assign apb4.pready         = s_ready_q;
  assign apb4.prdata         = s_rdata_q;
  assign apb4.pslverr        = s_resp_err_q;
  assign ctrl.tx_bind        = s_tx_bind_q;
  assign ctrl.rx_bind        = s_rx_bind_q;
  assign ctrl.cfg[0]         = s_cfg_q[0];
  assign ctrl.cfg[1]         = s_cfg_q[1];
  assign ctrl.imem_read_addr = apb4.paddr[6:2];
  assign irq_o               = ((s_irq_sources & s_irq_en_q) != 28'd0);

  always_comb begin
    s_irq_sources       = 28'd0;
    s_irq_sources[11:8] = ctrl.flags[3:0];
    for (integer index = 0; index < 2; index++) begin
      s_irq_sources[index]    = ((ctrl.runtime[index].events & s_event_en_q[index]) != 6'd0);
      s_irq_sources[16+index] = (ctrl.tx_level[index] <= s_cfg_q[index].tx_low);
      s_irq_sources[24+index] = (ctrl.rx_level[index] >= s_cfg_q[index].rx_high);
    end
  end

  always_comb begin
    s_cfg_d              = s_cfg_q;
    s_tx_bind_d          = s_tx_bind_q;
    s_rx_bind_d          = s_rx_bind_q;
    s_event_en_d         = s_event_en_q;
    s_irq_en_d           = s_irq_en_q;
    s_read_data          = 32'd0;
    s_access_err         = (apb4.paddr[1:0] != 2'd0) || (apb4.pwrite && (apb4.pstrb != 4'hf));
    s_cfg_writable       = 2'd0;
    s_dma_busy           = 2'd0;
    s_start_ok           = 1'b1;
    s_bind_ok            = 1'b1;
    s_block_reset_ok     = 1'b1;
    s_region             = 32'd0;
    ctrl.cmd_start       = 2'd0;
    ctrl.cmd_pause       = 2'd0;
    ctrl.cmd_resume      = 2'd0;
    ctrl.cmd_disable     = 2'd0;
    ctrl.cmd_abort       = 2'd0;
    ctrl.cmd_sm_reset    = 2'd0;
    ctrl.cmd_block_reset = 1'b0;
    ctrl.flag_set        = 4'd0;
    ctrl.flag_clear      = 4'd0;
    ctrl.event_clear[0]  = 6'd0;
    ctrl.event_clear[1]  = 6'd0;
    ctrl.cpu_tx_push     = 2'd0;
    ctrl.cpu_rx_pop      = 2'd0;
    ctrl.cpu_tx_data     = apb4.pwdata;
    ctrl.imem_write      = 1'b0;
    ctrl.imem_write_addr = apb4.paddr[6:2];
    ctrl.imem_write_data = apb4.pwdata[15:0];

    for (integer index = 0; index < 2; index++) begin
      s_dma_busy[index] = (s_tx_bind_q[31] && (s_tx_bind_q[0] == index[0]) &&
          (tx_job_i || tx_held_i || tx_closing_i)) ||
          (s_rx_bind_q[31] && (s_rx_bind_q[0] == index[0]) &&
          (rx_job_i || rx_held_i || rx_closing_i));
      s_cfg_writable[index] = (ctrl.runtime[index].state == piolite_pkg::Disabled) &&
          !s_dma_busy[index];
      if (!s_block_reset_ok || (ctrl.runtime[index].state != piolite_pkg::Disabled))
        s_block_reset_ok = 1'b0;
      if (apb4.pwdata[index]) begin
        if ((ctrl.runtime[index].state != piolite_pkg::Disabled) ||
            (ctrl.runtime[index].fault_code != `PIOLITE_FAULT_NONE) ||
            !piolite_pkg::config_scalar_legal(
                s_cfg_q[index]
            ) || !ctrl.start_guard_ok[index] || (ctrl.rx_level[index] != 4'd0))
          s_start_ok = 1'b0;
        s_region = piolite_pkg::bit_mask(s_cfg_q[index].length) << s_cfg_q[index].base;
        if ((ctrl.imem_valid & s_region) != s_region) s_start_ok = 1'b0;
      end
    end
    if (s_tx_bind_q[31] || s_rx_bind_q[31] || tx_job_i || rx_job_i || tx_held_i ||
        rx_held_i || tx_closing_i || rx_closing_i || (user_select_i != 32'd0))
      s_block_reset_ok = 1'b0;
    if ((apb4.pwdata[1:0] != 2'd0) && ((s_cfg_q[0].output_mask & s_cfg_q[1].output_mask) != 32'd0))
      s_start_ok = 1'b0;

    if (s_sm_access) begin
      unique case ({
        5'd0, s_sm_offset
      })
        `APB4_PIOLITE__SM_STATUS: begin
          s_read_data = {
            23'd0,
            ctrl.runtime[s_sm_index].last_fifo_failed,
            1'b0,
            ctrl.runtime[s_sm_index].stall,
            1'b0,
            ctrl.runtime[s_sm_index].state
          };
          if (apb4.pwrite) s_access_err = 1'b1;
        end
        `APB4_PIOLITE__SM_CONFIG:        s_read_data = {27'd0, s_cfg_q[s_sm_index].options};
        `APB4_PIOLITE__SM_DIV:           s_read_data = {16'd0, s_cfg_q[s_sm_index].divider};
        `APB4_PIOLITE__SM_PROGRAM: begin
          s_read_data = {
            11'd0,
            s_cfg_q[s_sm_index].entry,
            2'd0,
            s_cfg_q[s_sm_index].length,
            3'd0,
            s_cfg_q[s_sm_index].base
          };
        end
        `APB4_PIOLITE__SM_WRAP: begin
          s_read_data = {
            19'd0, s_cfg_q[s_sm_index].wrap_top, 3'd0, s_cfg_q[s_sm_index].wrap_bottom
          };
        end
        `APB4_PIOLITE__SM_IN_PINS: begin
          s_read_data = {
            18'd0, s_cfg_q[s_sm_index].in_pins.width, 3'd0, s_cfg_q[s_sm_index].in_pins.base
          };
        end
        `APB4_PIOLITE__SM_OUT_PINS: begin
          s_read_data = {
            18'd0, s_cfg_q[s_sm_index].out_pins.width, 3'd0, s_cfg_q[s_sm_index].out_pins.base
          };
        end
        `APB4_PIOLITE__SM_SET_PINS: begin
          s_read_data = {
            18'd0, s_cfg_q[s_sm_index].set_pins.width, 3'd0, s_cfg_q[s_sm_index].set_pins.base
          };
        end
        `APB4_PIOLITE__SM_CLAIM_MASK:    s_read_data = s_cfg_q[s_sm_index].claim_mask;
        `APB4_PIOLITE__SM_OUTPUT_MASK:   s_read_data = s_cfg_q[s_sm_index].output_mask;
        `APB4_PIOLITE__SM_INITIAL_VALUE: s_read_data = s_cfg_q[s_sm_index].initial_value;
        `APB4_PIOLITE__SM_INITIAL_OE:    s_read_data = s_cfg_q[s_sm_index].initial_oe;
        `APB4_PIOLITE__SM_INITIAL_XY: begin
          s_read_data = {s_cfg_q[s_sm_index].initial_y, s_cfg_q[s_sm_index].initial_x};
        end
        `APB4_PIOLITE__SM_SHIFT_LIMITS: begin
          s_read_data = {18'd0, s_cfg_q[s_sm_index].rx_bits, 2'd0, s_cfg_q[s_sm_index].tx_bits};
        end
        `APB4_PIOLITE__SM_TEST_SELECT: begin
          s_read_data = {22'd0, s_cfg_q[s_sm_index].test_flag, 3'd0, s_cfg_q[s_sm_index].test_pin};
        end
        `APB4_PIOLITE__SM_WATERMARKS: begin
          s_read_data = {20'd0, s_cfg_q[s_sm_index].rx_high, 4'd0, s_cfg_q[s_sm_index].tx_low};
        end
        `APB4_PIOLITE__SM_TXDATA: begin
          if (!apb4.pwrite || (ctrl.runtime[s_sm_index].state == piolite_pkg::Closing) ||
              !ctrl.cpu_guard_ok[s_sm_index] ||
              (s_tx_bind_q[31] && (s_tx_bind_q[0] == s_sm_index)) ||
              (ctrl.tx_level[s_sm_index] == 4'd8))
            s_access_err = 1'b1;
        end
        `APB4_PIOLITE__SM_RXDATA: begin
          s_read_data = ctrl.cpu_rx_data[s_sm_index];
          if (apb4.pwrite || (ctrl.runtime[s_sm_index].state == piolite_pkg::Closing) ||
              !ctrl.cpu_guard_ok[s_sm_index] ||
              (s_rx_bind_q[31] && (s_rx_bind_q[0] == s_sm_index)) ||
              (ctrl.rx_level[s_sm_index] == 4'd0))
            s_access_err = 1'b1;
        end
        `APB4_PIOLITE__SM_FIFO_LEVELS: begin
          s_read_data = {20'd0, ctrl.rx_level[s_sm_index], 4'd0, ctrl.tx_level[s_sm_index]};
          if (apb4.pwrite) s_access_err = 1'b1;
        end
        `APB4_PIOLITE__SM_EVENTS:        s_read_data = {26'd0, ctrl.runtime[s_sm_index].events};
        `APB4_PIOLITE__SM_EVENT_ENABLE:  s_read_data = {26'd0, s_event_en_q[s_sm_index]};
        `APB4_PIOLITE__SM_FAULT: begin
          s_read_data = {
            19'd0, ctrl.runtime[s_sm_index].fault_pc, ctrl.runtime[s_sm_index].fault_code
          };
          if (apb4.pwrite) s_access_err = 1'b1;
        end
        `APB4_PIOLITE__SM_PC: begin
          s_read_data = {27'd0, ctrl.runtime[s_sm_index].pc};
          if (apb4.pwrite) s_access_err = 1'b1;
        end
        `APB4_PIOLITE__SM_ISR: begin
          s_read_data = ctrl.runtime[s_sm_index].isr;
          if (apb4.pwrite) s_access_err = 1'b1;
        end
        `APB4_PIOLITE__SM_OSR: begin
          s_read_data = ctrl.runtime[s_sm_index].osr;
          if (apb4.pwrite) s_access_err = 1'b1;
        end
        `APB4_PIOLITE__SM_XY: begin
          s_read_data = {ctrl.runtime[s_sm_index].y, ctrl.runtime[s_sm_index].x};
          if (apb4.pwrite) s_access_err = 1'b1;
        end
        `APB4_PIOLITE__SM_SHIFT_COUNTS: begin
          s_read_data = {
            18'd0, ctrl.runtime[s_sm_index].osr_count, 2'd0, ctrl.runtime[s_sm_index].isr_count
          };
          if (apb4.pwrite) s_access_err = 1'b1;
        end
        `APB4_PIOLITE__SM_TICK_COUNT: begin
          s_read_data = ctrl.runtime[s_sm_index].tick_count;
          if (apb4.pwrite) s_access_err = 1'b1;
        end
        `APB4_PIOLITE__SM_TX_STALL_COUNT: begin
          s_read_data = ctrl.runtime[s_sm_index].tx_stall_count;
          if (apb4.pwrite) s_access_err = 1'b1;
        end
        `APB4_PIOLITE__SM_RX_STALL_COUNT: begin
          s_read_data = ctrl.runtime[s_sm_index].rx_stall_count;
          if (apb4.pwrite) s_access_err = 1'b1;
        end
        `APB4_PIOLITE__SM_RETIRED_COUNT: begin
          s_read_data = ctrl.runtime[s_sm_index].retired_count;
          if (apb4.pwrite) s_access_err = 1'b1;
        end
        `APB4_PIOLITE__SM_EXEC_PHASE: begin
          s_read_data = {
            12'd0,
            ctrl.runtime[s_sm_index].delay_remaining,
            ctrl.runtime[s_sm_index].divider_remaining
          };
          if (apb4.pwrite) s_access_err = 1'b1;
        end
        default:                         s_access_err = 1'b1;
      endcase
    end else if (s_imem_access) begin
      s_read_data = {16'd0, ctrl.imem_read_data};
    end else begin
      unique case (s_offset)
        `APB4_PIOLITE__IP_ID: begin
          s_read_data = `APB4_PIOLITE__ID_VALUE;
          if (apb4.pwrite) s_access_err = 1'b1;
        end
        `APB4_PIOLITE__IP_VERSION: begin
          s_read_data = `APB4_PIOLITE__VERSION_VALUE;
          if (apb4.pwrite) s_access_err = 1'b1;
        end
        `APB4_PIOLITE__ISA_VERSION: begin
          s_read_data = `APB4_PIOLITE__ISA_VALUE;
          if (apb4.pwrite) s_access_err = 1'b1;
        end
        `APB4_PIOLITE__CAPABILITY: begin
          s_read_data = `APB4_PIOLITE__CAPABILITY_VALUE;
          if (apb4.pwrite) s_access_err = 1'b1;
        end
        `APB4_PIOLITE__ROUTABLE_MASK: begin
          s_read_data = `APB4_PIOLITE__ROUTES_VALUE;
          if (apb4.pwrite) s_access_err = 1'b1;
        end
        `APB4_PIOLITE__CLOCK_HZ: begin
          s_read_data = clock_hz_i;
          if (apb4.pwrite) s_access_err = 1'b1;
        end
        `APB4_PIOLITE__FLAGS: begin
          s_read_data = {28'd0, ctrl.flags[3:0]};
          if (apb4.pwrite) s_access_err = 1'b1;
        end
        `APB4_PIOLITE__FLAG_SET, `APB4_PIOLITE__FLAG_CLEAR: begin
          if (!apb4.pwrite) s_access_err = 1'b1;
        end
        `APB4_PIOLITE__IRQ_STATUS: begin
          s_read_data = {4'd0, s_irq_sources};
          if (apb4.pwrite) s_access_err = 1'b1;
        end
        `APB4_PIOLITE__IRQ_ENABLE: s_read_data = {4'd0, s_irq_en_q};
        `APB4_PIOLITE__TX_BIND:    s_read_data = s_tx_bind_q;
        `APB4_PIOLITE__RX_BIND:    s_read_data = s_rx_bind_q;
        `APB4_PIOLITE__TRANSPORT_STATUS: begin
          s_read_data = {
            26'd0, rx_closing_i, tx_closing_i, rx_held_i, tx_held_i, rx_job_i, tx_job_i
          };
          if (apb4.pwrite) s_access_err = 1'b1;
        end
        `APB4_PIOLITE__IMEM_VALID: begin
          s_read_data = ctrl.imem_valid;
          if (apb4.pwrite) s_access_err = 1'b1;
        end
        `APB4_PIOLITE__OWNED_MASK: begin
          s_read_data = user_select_i;
          if (apb4.pwrite) s_access_err = 1'b1;
        end
        `APB4_PIOLITE__START: begin
          if (!apb4.pwrite || ((apb4.pwdata[1:0] != 2'd0) && !s_start_ok)) s_access_err = 1'b1;
        end
        `APB4_PIOLITE__PAUSE: begin
          if (!apb4.pwrite) s_access_err = 1'b1;
          for (integer index = 0; index < 2; index++)
          if (apb4.pwdata[index] && (ctrl.runtime[index].state != piolite_pkg::Running))
            s_access_err = 1'b1;
        end
        `APB4_PIOLITE__RESUME: begin
          if (!apb4.pwrite) s_access_err = 1'b1;
          for (integer index = 0; index < 2; index++)
          if (apb4.pwdata[index] && (ctrl.runtime[index].state != piolite_pkg::Paused))
            s_access_err = 1'b1;
        end
        `APB4_PIOLITE__DISABLE: begin
          if (!apb4.pwrite) s_access_err = 1'b1;
          for (integer index = 0; index < 2; index++)
          if (apb4.pwdata[index] &&
                ((ctrl.runtime[index].state == piolite_pkg::Closing) || s_dma_busy[index] &&
                 ((s_tx_bind_q[31] && (s_tx_bind_q[0] == index[0]) && tx_job_i) ||
                  (s_rx_bind_q[31] && (s_rx_bind_q[0] == index[0]) && rx_job_i))))
            s_access_err = 1'b1;
        end
        `APB4_PIOLITE__ABORT: begin
          if (!apb4.pwrite) s_access_err = 1'b1;
        end
        `APB4_PIOLITE__SM_RESET: begin
          if (!apb4.pwrite) s_access_err = 1'b1;
          for (integer index = 0; index < 2; index++) begin
            if (apb4.pwdata[index] &&
                !((ctrl.runtime[index].state == piolite_pkg::Disabled) ||
                  (ctrl.runtime[index].state == piolite_pkg::Closing)))
              s_access_err = 1'b1;
            if (apb4.pwdata[index] &&
                ((s_tx_bind_q[31] && (s_tx_bind_q[0] == index[0]) && tx_job_i) ||
                 (s_rx_bind_q[31] && (s_rx_bind_q[0] == index[0]) && rx_job_i)))
              s_access_err = 1'b1;
          end
        end
        `APB4_PIOLITE__BLOCK_RESET: begin
          if (!apb4.pwrite || (apb4.pwdata[0] && !s_block_reset_ok)) s_access_err = 1'b1;
        end
        default:                   s_access_err = 1'b1;
      endcase
    end

    if (s_req_accept && apb4.pwrite) begin
      if ((s_offset inside {`APB4_PIOLITE__START, `APB4_PIOLITE__PAUSE,
            `APB4_PIOLITE__RESUME, `APB4_PIOLITE__DISABLE, `APB4_PIOLITE__ABORT,
            `APB4_PIOLITE__SM_RESET}) && (apb4.pwdata[31:2] != 30'd0))
        s_access_err = 1'b1;
      if ((s_offset == `APB4_PIOLITE__BLOCK_RESET) && (apb4.pwdata[31:1] != 31'd0))
        s_access_err = 1'b1;
      if (s_sm_access) begin
        if (!s_cfg_writable[s_sm_index] &&
            !({5'd0, s_sm_offset} inside {`APB4_PIOLITE__SM_TXDATA,
              `APB4_PIOLITE__SM_EVENTS, `APB4_PIOLITE__SM_EVENT_ENABLE}))
          s_access_err = 1'b1;
        unique case ({
          5'd0, s_sm_offset
        })
          `APB4_PIOLITE__SM_CONFIG: begin
            if (apb4.pwdata[31:5] != 27'd0) s_access_err = 1'b1;
            s_cfg_d[s_sm_index].options = apb4.pwdata[4:0];
          end
          `APB4_PIOLITE__SM_DIV: begin
            if ((apb4.pwdata[31:16] != 16'd0) || (apb4.pwdata[15:0] == 16'd0)) s_access_err = 1'b1;
            s_cfg_d[s_sm_index].divider = apb4.pwdata[15:0];
          end
          `APB4_PIOLITE__SM_PROGRAM: begin
            if ((apb4.pwdata & 32'hffe0_c0e0) != 32'd0 ||
                (apb4.pwdata[13:8] == 6'd0) || (apb4.pwdata[13:8] > 6'd32))
              s_access_err = 1'b1;
            s_cfg_d[s_sm_index].base   = apb4.pwdata[4:0];
            s_cfg_d[s_sm_index].length = apb4.pwdata[13:8];
            s_cfg_d[s_sm_index].entry  = apb4.pwdata[20:16];
          end
          `APB4_PIOLITE__SM_WRAP: begin
            if ((apb4.pwdata & 32'hffff_e0e0) != 32'd0) s_access_err = 1'b1;
            s_cfg_d[s_sm_index].wrap_bottom = apb4.pwdata[4:0];
            s_cfg_d[s_sm_index].wrap_top    = apb4.pwdata[12:8];
          end
          `APB4_PIOLITE__SM_IN_PINS, `APB4_PIOLITE__SM_OUT_PINS, `APB4_PIOLITE__SM_SET_PINS: begin
            if ((apb4.pwdata & 32'hffff_c0e0) != 32'd0 ||
                ({1'b0, apb4.pwdata[4:0]} + apb4.pwdata[13:8]) > 7'd32)
              s_access_err = 1'b1;
            if (({5'd0, s_sm_offset} == `APB4_PIOLITE__SM_SET_PINS) && (apb4.pwdata[13:8] > 6'd8))
              s_access_err = 1'b1;
            if ({5'd0, s_sm_offset} == `APB4_PIOLITE__SM_IN_PINS) begin
              s_cfg_d[s_sm_index].in_pins.base  = apb4.pwdata[4:0];
              s_cfg_d[s_sm_index].in_pins.width = apb4.pwdata[13:8];
            end else if ({5'd0, s_sm_offset} == `APB4_PIOLITE__SM_OUT_PINS) begin
              s_cfg_d[s_sm_index].out_pins.base  = apb4.pwdata[4:0];
              s_cfg_d[s_sm_index].out_pins.width = apb4.pwdata[13:8];
            end else begin
              s_cfg_d[s_sm_index].set_pins.base  = apb4.pwdata[4:0];
              s_cfg_d[s_sm_index].set_pins.width = apb4.pwdata[13:8];
            end
          end
          `APB4_PIOLITE__SM_CLAIM_MASK:  s_cfg_d[s_sm_index].claim_mask = apb4.pwdata;
          `APB4_PIOLITE__SM_OUTPUT_MASK: s_cfg_d[s_sm_index].output_mask = apb4.pwdata;
          `APB4_PIOLITE__SM_INITIAL_VALUE: begin
            if ((apb4.pwdata & ~s_cfg_q[s_sm_index].output_mask) != 32'd0) s_access_err = 1'b1;
            s_cfg_d[s_sm_index].initial_value = apb4.pwdata;
          end
          `APB4_PIOLITE__SM_INITIAL_OE: begin
            if ((apb4.pwdata & ~s_cfg_q[s_sm_index].output_mask) != 32'd0) s_access_err = 1'b1;
            s_cfg_d[s_sm_index].initial_oe = apb4.pwdata;
          end
          `APB4_PIOLITE__SM_INITIAL_XY: begin
            s_cfg_d[s_sm_index].initial_x = apb4.pwdata[15:0];
            s_cfg_d[s_sm_index].initial_y = apb4.pwdata[31:16];
          end
          `APB4_PIOLITE__SM_SHIFT_LIMITS: begin
            if ((apb4.pwdata & 32'hffff_c0c0) != 32'd0 ||
                (apb4.pwdata[5:0] == 6'd0) || (apb4.pwdata[5:0] > 6'd32) ||
                (apb4.pwdata[13:8] == 6'd0) || (apb4.pwdata[13:8] > 6'd32))
              s_access_err = 1'b1;
            s_cfg_d[s_sm_index].tx_bits = apb4.pwdata[5:0];
            s_cfg_d[s_sm_index].rx_bits = apb4.pwdata[13:8];
          end
          `APB4_PIOLITE__SM_TEST_SELECT: begin
            if ((apb4.pwdata & 32'hffff_fce0) != 32'd0) s_access_err = 1'b1;
            s_cfg_d[s_sm_index].test_pin  = apb4.pwdata[4:0];
            s_cfg_d[s_sm_index].test_flag = apb4.pwdata[9:8];
          end
          `APB4_PIOLITE__SM_WATERMARKS: begin
            if ((apb4.pwdata & 32'hffff_f0f0) != 32'd0 || (apb4.pwdata[3:0] > 4'd8) ||
                (apb4.pwdata[11:8] == 4'd0) || (apb4.pwdata[11:8] > 4'd8))
              s_access_err = 1'b1;
            s_cfg_d[s_sm_index].tx_low  = apb4.pwdata[3:0];
            s_cfg_d[s_sm_index].rx_high = apb4.pwdata[11:8];
          end
          `APB4_PIOLITE__SM_EVENTS: begin
            if (apb4.pwdata[31:6] != 26'd0) s_access_err = 1'b1;
          end
          `APB4_PIOLITE__SM_EVENT_ENABLE: begin
            if (apb4.pwdata[31:6] != 26'd0) s_access_err = 1'b1;
            s_event_en_d[s_sm_index] = apb4.pwdata[5:0];
          end
          `APB4_PIOLITE__SM_TXDATA:      ;
          default:                       s_access_err = 1'b1;
        endcase
      end else if (s_imem_access) begin
        if (apb4.pwdata[31:16] != 16'd0) s_access_err = 1'b1;
        for (integer index = 0; index < 2; index++)
        if (ctrl.runtime[index].state != piolite_pkg::Disabled) s_access_err = 1'b1;
        if (s_tx_bind_q[31] || s_rx_bind_q[31] || tx_job_i || rx_job_i || tx_held_i ||
            rx_held_i || tx_closing_i || rx_closing_i)
          s_access_err = 1'b1;
      end else begin
        unique case (s_offset)
          `APB4_PIOLITE__FLAG_SET, `APB4_PIOLITE__FLAG_CLEAR: begin
            if (apb4.pwdata[31:4] != 28'd0) s_access_err = 1'b1;
          end
          `APB4_PIOLITE__IRQ_ENABLE: begin
            if ((apb4.pwdata & ~`APB4_PIOLITE__IRQ_MASK) != 32'd0) s_access_err = 1'b1;
            s_irq_en_d = apb4.pwdata[27:0];
          end
          `APB4_PIOLITE__TX_BIND, `APB4_PIOLITE__RX_BIND: begin
            if ((apb4.pwdata & 32'h7fff_f8fc) != 32'd0 || (apb4.pwdata[1:0] > 2'd1))
              s_access_err = 1'b1;
            if (ctrl.runtime[apb4.pwdata[0]].state != piolite_pkg::Disabled) s_bind_ok = 1'b0;
            if (s_offset == `APB4_PIOLITE__TX_BIND) begin
              if ((ctrl.runtime[s_tx_bind_q[0]].state != piolite_pkg::Disabled) ||
                  tx_job_i || tx_held_i || tx_closing_i)
                s_bind_ok = 1'b0;
              s_tx_bind_d = apb4.pwdata;
              if (apb4.pwdata[31] && !ctrl.start_guard_ok[apb4.pwdata[0]]) s_bind_ok = 1'b0;
              if (apb4.pwdata[31] && s_rx_bind_q[31] && (apb4.pwdata[10:8] == s_rx_bind_q[10:8]))
                s_bind_ok = 1'b0;
            end else begin
              if ((ctrl.runtime[s_rx_bind_q[0]].state != piolite_pkg::Disabled) ||
                  rx_job_i || rx_held_i || rx_closing_i)
                s_bind_ok = 1'b0;
              s_rx_bind_d = apb4.pwdata;
              if (apb4.pwdata[31] && !ctrl.start_guard_ok[apb4.pwdata[0]]) s_bind_ok = 1'b0;
              if (apb4.pwdata[31] && s_tx_bind_q[31] && (apb4.pwdata[10:8] == s_tx_bind_q[10:8]))
                s_bind_ok = 1'b0;
            end
            if (!s_bind_ok) s_access_err = 1'b1;
          end
          `APB4_PIOLITE__START, `APB4_PIOLITE__PAUSE, `APB4_PIOLITE__RESUME,
          `APB4_PIOLITE__DISABLE, `APB4_PIOLITE__ABORT, `APB4_PIOLITE__SM_RESET,
          `APB4_PIOLITE__BLOCK_RESET:
          ;
          default: s_access_err = 1'b1;
        endcase
      end
    end

    if (s_access_err) begin
      s_cfg_d      = s_cfg_q;
      s_tx_bind_d  = s_tx_bind_q;
      s_rx_bind_d  = s_rx_bind_q;
      s_event_en_d = s_event_en_q;
      s_irq_en_d   = s_irq_en_q;
    end

    if (s_req_accept && !s_access_err) begin
      if (s_sm_access) begin
        if ({5'd0, s_sm_offset} == `APB4_PIOLITE__SM_TXDATA)
          ctrl.cpu_tx_push[s_sm_index] = apb4.pwrite;
        if ({5'd0, s_sm_offset} == `APB4_PIOLITE__SM_RXDATA)
          ctrl.cpu_rx_pop[s_sm_index] = !apb4.pwrite;
        if (apb4.pwrite && ({5'd0, s_sm_offset} == `APB4_PIOLITE__SM_EVENTS))
          ctrl.event_clear[s_sm_index] = apb4.pwdata[5:0];
      end else if (s_imem_access) begin
        ctrl.imem_write = apb4.pwrite;
      end else if (apb4.pwrite) begin
        unique case (s_offset)
          `APB4_PIOLITE__FLAG_SET:    ctrl.flag_set = apb4.pwdata[3:0];
          `APB4_PIOLITE__FLAG_CLEAR:  ctrl.flag_clear = apb4.pwdata[3:0];
          `APB4_PIOLITE__START:       ctrl.cmd_start = apb4.pwdata[1:0];
          `APB4_PIOLITE__PAUSE:       ctrl.cmd_pause = apb4.pwdata[1:0];
          `APB4_PIOLITE__RESUME:      ctrl.cmd_resume = apb4.pwdata[1:0];
          `APB4_PIOLITE__DISABLE:     ctrl.cmd_disable = apb4.pwdata[1:0];
          `APB4_PIOLITE__ABORT:       ctrl.cmd_abort = apb4.pwdata[1:0];
          `APB4_PIOLITE__SM_RESET:    ctrl.cmd_sm_reset = apb4.pwdata[1:0];
          `APB4_PIOLITE__BLOCK_RESET: ctrl.cmd_block_reset = apb4.pwdata[0];
          default:                    ;
        endcase
      end
    end

    for (integer index = 0; index < 2; index++) begin
      if (ctrl.cmd_sm_reset[index]) begin
        if (s_tx_bind_q[31] && (s_tx_bind_q[0] == index[0])) s_tx_bind_d = 32'd0;
        if (s_rx_bind_q[31] && (s_rx_bind_q[0] == index[0])) s_rx_bind_d = 32'd0;
      end
    end
    if (ctrl.cmd_block_reset) begin
      s_cfg_d[0]      = ResetSmCfg;
      s_cfg_d[1]      = ResetSmCfg;
      s_tx_bind_d     = 32'd0;
      s_rx_bind_d     = 32'd0;
      s_event_en_d[0] = 6'd0;
      s_event_en_d[1] = 6'd0;
      s_irq_en_d      = 28'd0;
    end
    s_ready_d    = s_req;
    s_rdata_d    = s_req_accept ? s_read_data : s_rdata_q;
    s_resp_err_d = s_req_accept ? s_access_err : s_resp_err_q;
  end

  for (genvar index = 0; index < 2; index++) begin : gen_registers
    dffrc #(
        .DATA_WIDTH($bits(piolite_pkg::sm_config_t)),
        .RESET_VAL (ResetSmCfg)
    ) u_cfg (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_cfg_d[index]),
        .dat_o  (s_cfg_q[index])
    );
    dffr #(
        .DATA_WIDTH(6)
    ) u_event_en (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_event_en_d[index]),
        .dat_o  (s_event_en_q[index])
    );
  end
  dffr #(
      .DATA_WIDTH(32)
  ) u_tx_bind (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_tx_bind_d),
      .dat_o  (s_tx_bind_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_rx_bind (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rx_bind_d),
      .dat_o  (s_rx_bind_q)
  );
  dffr #(
      .DATA_WIDTH(28)
  ) u_irq_en (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_irq_en_d),
      .dat_o  (s_irq_en_q)
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
`ifdef FORMAL
  logic s_formal_past_q;
  always_ff @(posedge clk_i) begin
    if (!rst_n_i) s_formal_past_q <= 1'b0;
    else begin
      s_formal_past_q <= 1'b1;
      if (s_formal_past_q && $past(s_req)) assert (apb4.pready);
      if (apb4.pready) begin
        assert (ctrl.cpu_tx_push == 2'd0 && ctrl.cpu_rx_pop == 2'd0);
        assert (ctrl.cmd_start == 2'd0 && ctrl.cmd_pause == 2'd0 &&
                ctrl.cmd_resume == 2'd0 && ctrl.cmd_disable == 2'd0 &&
                ctrl.cmd_abort == 2'd0 && ctrl.cmd_sm_reset == 2'd0 &&
                !ctrl.cmd_block_reset && !ctrl.imem_write);
      end
      if (s_formal_past_q && $past(apb4.pready)) begin
        assert (apb4.prdata == $past(apb4.prdata));
        assert (apb4.pslverr == $past(apb4.pslverr));
      end
    end
  end
`endif
endmodule
