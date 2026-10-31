`include "ppalite_define.svh"

module ppalite_reg #(
    parameter bit ExternalRoute = 1'b0
) (
    input  logic                       clk_i,
    input  logic                       rst_n_i,
    input  logic                [31:0] clock_hz_i,
    input  logic                       route_idle_i,
    input  logic                       route_i,
    input  logic                       route_change_i,
    output logic                       route_write_o,
    output logic                       route_value_o,
    output logic                [ 2:0] processing_format_o,
    input  logic                       source_ready_i,
    input  logic                       source_quiet_i,
    input  logic                       source_done_i,
    input  logic                       source_stopped_i,
    input  logic                [31:0] source_sequence_i,
    input  logic                [31:0] source_words_i,
    input  logic                [31:0] source_geometry_i,
    input  logic                [ 7:0] source_err_i,
    input  logic                       source_config_err_i,
    input  logic                       source_stats_err_i,
    input  logic                       transport_ready_i,
    input  logic                       transport_idle_i,
    input  logic                       transport_done_i,
    input  logic                [ 7:0] transport_err_i,
    output logic                       irq_o,
           apb4_if.slave               apb4,
           ppalite_if.registers        ctrl
);
  logic [31:0] s_shadow_cfg_q;
  logic [31:0] s_shadow_size_q;
  logic [31:0] s_shadow_sampling_q;
  logic [31:0] s_shadow_destination_q;
  logic [31:0] s_shadow_capacity_q;
  logic        s_route_q;
  logic        s_route_current;
  logic        s_owner_q;
  logic        s_result_valid_q;
  logic [31:0] s_job_sequence_q;
  logic [31:0] s_source_sequence_q;
  logic [31:0] s_source_start_q;
  logic [31:0] s_result_cfg_q;
  logic [31:0] s_source_geometry_q;
  logic        s_source_done_q;
  logic        s_dma_done_q;
  logic [ 7:0] s_source_err_q;
  logic [ 7:0] s_dma_err_q;
  logic [ 7:0] s_first_err_q;
  logic [31:0] s_err_position_q;
  logic [ 4:0] s_irq_state_q;
  logic [ 4:0] s_irq_en_q;
  logic [ 4:0] s_irq_clear;
  logic [ 4:0] s_irq_set;
  logic        s_ready_q;
  logic [31:0] s_rdata_q;
  logic        s_resp_err_q;
  logic        s_req_accept;
  logic        s_access_err;
  logic [31:0] s_read_data;
  logic        s_cmd_valid;
  logic        s_cfg_valid;
  logic        s_size_valid;
  logic        s_sampling_valid;
  logic        s_layout_valid;
  logic        s_finalize_valid;
  logic        s_release_valid;
  logic [63:0] s_step_x;
  logic [63:0] s_step_y;
  logic [63:0] s_out_w;
  logic [63:0] s_out_h;
  logic [63:0] s_row;
  logic [63:0] s_stride;
  logic [63:0] s_valid;
  logic [63:0] s_transport;
  logic [63:0] s_input_words;
  logic [64:0] s_destination_end;
  logic [31:0] s_status;
  logic [31:0] s_expected_source_sequence;

  function automatic logic [2:0] decode_step(input logic [1:0] code);
    case (code)
      2'd0:    decode_step = 3'd1;
      2'd1:    decode_step = 3'd2;
      default: decode_step = 3'd4;
    endcase
  endfunction

  function automatic logic valid_cfg(input logic [31:0] value);
    valid_cfg = (value[31:7] == 25'd0) && !value[3] && (value[2:0] <= 3'd5) &&
        !((value[2:0] < 3'd2) && value[4]) && !((value[2:0] >= 3'd2) && value[5]) &&
        !(value[4] && value[6]);
  endfunction

  function automatic logic valid_sampling(input logic [31:0] value, input logic [31:0] size);
    valid_sampling = (value[31:18] == 14'd0) && (value[15:10] == 6'd0) &&
        (value[7:4] == 4'd0) && (value[1:0] != 2'd3) && (value[3:2] != 2'd3) &&
        ({1'b0, value[9:8]} < decode_step(value[1:0])) &&
        ({1'b0, value[17:16]} < decode_step(value[3:2])) && ({14'd0, value[9:8]} < size[15:0]) &&
        ({14'd0, value[17:16]} < size[31:16]);
  endfunction

  assign s_req_accept = apb4.psel && apb4.penable && !s_ready_q;
  assign s_route_current = ExternalRoute ? route_i : s_route_q;
  assign route_value_o = apb4.pwdata[0];
  assign route_write_o = s_req_accept && apb4.pwrite &&
      ({20'd0, apb4.paddr[11:0]} == `APB4_PPALITE__ROUTE) &&
      (apb4.paddr[1:0] == 2'd0) && (apb4.pstrb == 4'hf) &&
      (apb4.paddr[11:8] == 4'd0) && (apb4.pwdata[31:1] == 31'd0);
  assign processing_format_o = s_shadow_cfg_q[2:0];
  assign s_cfg_valid = valid_cfg(s_shadow_cfg_q);
  assign s_size_valid = (s_shadow_size_q[15:0] != 16'd0) && (s_shadow_size_q[31:16] != 16'd0);
  assign s_sampling_valid = valid_sampling(s_shadow_sampling_q, s_shadow_size_q);
  assign s_step_x = {61'd0, decode_step(s_shadow_sampling_q[1:0])};
  assign s_step_y = {61'd0, decode_step(s_shadow_sampling_q[3:2])};
  assign s_out_w = ({48'd0, s_shadow_size_q[15:0]} - {62'd0, s_shadow_sampling_q[9:8]} +
      s_step_x - 64'd1) / s_step_x;
  assign s_out_h = ({48'd0, s_shadow_size_q[31:16]} - {62'd0, s_shadow_sampling_q[17:16]} +
      s_step_y - 64'd1) / s_step_y;
  assign s_row = s_out_w * (s_shadow_cfg_q[4] ? 64'd1 : 64'd2);
  assign s_stride = (s_row + 64'd3) & 64'hffff_ffff_ffff_fffc;
  assign s_valid = s_row * s_out_h;
  assign s_transport = s_stride * s_out_h;
  assign s_input_words = (({48'd0, s_shadow_size_q[15:0]} + 64'd1) / 64'd2) *
      {48'd0, s_shadow_size_q[31:16]};
  assign s_destination_end = {33'd0, s_shadow_destination_q} + {1'b0, s_transport};
  assign s_layout_valid = s_cfg_valid && s_size_valid && s_sampling_valid &&
      (s_shadow_destination_q[1:0] == 2'd0) && (s_transport <= 64'h0000_0000_ffff_fffc) &&
      (s_valid <= 64'h0000_0000_ffff_ffff) &&
      ({32'd0, s_shadow_capacity_q} >= s_transport) &&
      (s_destination_end <= 65'd4294967296) &&
      (s_input_words <= 64'h0000_0000_ffff_ffff) &&
      (({48'd0, s_shadow_size_q[15:0]} * {48'd0, s_shadow_size_q[31:16]}) <=
       64'h0000_0000_ffff_ffff);
  assign s_expected_source_sequence = s_source_start_q + 32'd1;
  logic        s_monitor_active;
  logic        s_source_done_valid;
  logic        s_source_done_fault;
  logic        s_abort_close;
  logic        s_fault_close;
  logic [31:0] s_expected_input_words;

  assign s_expected_input_words = (({16'd0, ctrl.input_size[15:0]} + 32'd1) >> 1) *
      ctrl.input_size[31:16];
  assign s_monitor_active = s_owner_q && ((ctrl.state == `PPALITE_STATE_ARMED) ||
      (ctrl.state == `PPALITE_STATE_RUNNING) || (ctrl.state == `PPALITE_STATE_DRAINING) ||
      (ctrl.state == `PPALITE_STATE_VERIFY));
  assign s_source_done_valid = s_monitor_active && source_done_i && !s_source_done_q &&
      !source_stats_err_i && (source_words_i == s_expected_input_words) &&
      (source_sequence_i == s_expected_source_sequence);
  assign s_source_done_fault = s_monitor_active &&
      ((source_done_i && !s_source_done_valid) || source_stats_err_i);
  assign s_abort_close = s_req_accept && apb4.pwrite && (apb4.pstrb == 4'hf) &&
      ({20'd0, apb4.paddr[11:0]} == `APB4_PPALITE__COMMAND) && (apb4.pwdata == 32'd8) &&
      (ctrl.state != `PPALITE_STATE_IDLE) && s_owner_q;
  assign s_fault_close = s_source_done_fault ||
      (s_monitor_active && (ctrl.excess || (source_err_i != 8'd0) || source_config_err_i ||
       (transport_err_i != 8'd0) || (ctrl.core_err != 8'd0) ||
       (source_geometry_i != ctrl.input_size)));
  assign ctrl.close = s_abort_close || s_fault_close;
  assign s_finalize_valid = (ctrl.state == `PPALITE_STATE_VERIFY) && s_owner_q &&
      ctrl.input_done && ctrl.pipe_done && s_source_done_q && s_dma_done_q && source_quiet_i &&
      source_stopped_i && transport_idle_i && (s_source_err_q == 8'd0) &&
      (s_dma_err_q == 8'd0) && (ctrl.core_err == 8'd0) &&
      (source_err_i == 8'd0) && (transport_err_i == 8'd0) && !source_done_i && !ctrl.excess &&
      !source_config_err_i && !source_stats_err_i &&
      (source_geometry_i == ctrl.input_size) && (source_words_i == ctrl.input_words) &&
      (source_sequence_i == s_expected_source_sequence);
  assign s_release_valid = (ctrl.state == `PPALITE_STATE_COMPLETE) && s_owner_q &&
      s_result_valid_q && ctrl.pipe_done && source_quiet_i && source_stopped_i &&
      transport_idle_i && (s_source_err_q == 8'd0) && (s_dma_err_q == 8'd0) &&
      (ctrl.core_err == 8'd0) && (source_err_i == 8'd0) && (transport_err_i == 8'd0) &&
      !ctrl.excess && !source_done_i && !source_config_err_i && !source_stats_err_i &&
      (source_geometry_i == ctrl.input_size) && (source_words_i == ctrl.input_words) &&
      (source_sequence_i == s_expected_source_sequence);

  always_comb begin
    s_status      = 32'd0;
    s_status[2:0] = ctrl.state;
    s_status[8]   = s_owner_q;
    s_status[9]   = ctrl.input_done;
    s_status[10]  = ctrl.pipe_done;
    s_status[11]  = s_source_done_q;
    s_status[12]  = s_dma_done_q;
    s_status[13]  = s_result_valid_q;
    s_status[14]  = source_quiet_i;
    s_status[15]  = transport_idle_i;
  end

  always_comb begin
    s_cmd_valid = 1'b0;
    case (apb4.pwdata[5:0])
      6'b000001:
      s_cmd_valid = s_layout_valid && s_route_current &&
          (ctrl.state == `PPALITE_STATE_IDLE) && !s_owner_q && route_idle_i &&
          source_ready_i && source_quiet_i && transport_ready_i && transport_idle_i &&
          (source_geometry_i == s_shadow_size_q) && (source_err_i == 8'd0) &&
          (transport_err_i == 8'd0);
      6'b000010: s_cmd_valid = s_finalize_valid;
      6'b000100: s_cmd_valid = s_release_valid;
      6'b001000: s_cmd_valid = s_owner_q;
      6'b010000:
      s_cmd_valid = (ctrl.state == `PPALITE_STATE_CLOSING) && s_owner_q &&
          source_quiet_i && source_stopped_i && transport_idle_i && ctrl.local_idle;
      6'b100000:
      s_cmd_valid = !s_route_current && (ctrl.state == `PPALITE_STATE_IDLE) &&
          !s_owner_q && route_idle_i && source_quiet_i && transport_idle_i && ctrl.local_idle;
      default: s_cmd_valid = (apb4.pwdata[5:0] == 6'd0);
    endcase
  end

  always_comb begin
    s_read_data = 32'd0;
    case ({
      20'd0, apb4.paddr[11:0]
    })
      `APB4_PPALITE__IP_ID: s_read_data = `APB4_PPALITE__ID_VALUE;
      `APB4_PPALITE__IP_VERSION: s_read_data = `APB4_PPALITE__VERSION_VALUE;
      `APB4_PPALITE__CAPABILITY: s_read_data = `APB4_PPALITE__CAPABILITY_VALUE;
      `APB4_PPALITE__BUFFER_CAPABILITY: s_read_data = `APB4_PPALITE__BUFFER_VALUE;
      `APB4_PPALITE__CLOCK_HZ: s_read_data = clock_hz_i;
      `APB4_PPALITE__ROUTE: s_read_data = {31'd0, s_route_current};
      `APB4_PPALITE__STATUS: s_read_data = s_status;
      `APB4_PPALITE__CONFIG: s_read_data = s_shadow_cfg_q;
      `APB4_PPALITE__INPUT_SIZE: s_read_data = s_shadow_size_q;
      `APB4_PPALITE__SAMPLING: s_read_data = s_shadow_sampling_q;
      `APB4_PPALITE__DMA_BINDING: s_read_data = `APB4_PPALITE__DMA_BINDING_VALUE;
      `APB4_PPALITE__DESTINATION: s_read_data = s_shadow_destination_q;
      `APB4_PPALITE__CAPACITY_BYTES: s_read_data = s_shadow_capacity_q;
      `APB4_PPALITE__OUTPUT_SIZE: s_read_data = ctrl.output_size;
      `APB4_PPALITE__ROW_BYTES: s_read_data = ctrl.row_bytes;
      `APB4_PPALITE__STRIDE_BYTES: s_read_data = ctrl.stride_bytes;
      `APB4_PPALITE__VALID_BYTES: s_read_data = ctrl.valid_bytes;
      `APB4_PPALITE__TRANSPORT_BYTES: s_read_data = ctrl.transport_bytes;
      `APB4_PPALITE__EXPECTED_WORDS: s_read_data = ctrl.expected_words;
      `APB4_PPALITE__JOB_SEQUENCE: s_read_data = s_job_sequence_q;
      `APB4_PPALITE__SOURCE_SEQUENCE: s_read_data = s_source_sequence_q;
      `APB4_PPALITE__INPUT_WORDS: s_read_data = ctrl.input_words;
      `APB4_PPALITE__INPUT_PIXELS: s_read_data = ctrl.input_pixels;
      `APB4_PPALITE__INPUT_LINES: s_read_data = ctrl.input_lines;
      `APB4_PPALITE__SELECTED_PIXELS: s_read_data = ctrl.sel_pixels;
      `APB4_PPALITE__OUTPUT_WORDS: s_read_data = ctrl.output_words;
      `APB4_PPALITE__OUTPUT_LINES: s_read_data = ctrl.output_lines;
      `APB4_PPALITE__INPUT_STALL_CYCLES: s_read_data = ctrl.input_stall_cycles;
      `APB4_PPALITE__OUTPUT_STALL_CYCLES: s_read_data = ctrl.output_stall_cycles;
      `APB4_PPALITE__FIFO_LEVELS:
      s_read_data = {
        16'd0, ctrl.output_high_water, 4'd0, ctrl.output_level, 2'd0, ctrl.input_level
      };
      `APB4_PPALITE__IRQ_STATE: s_read_data = {27'd0, s_irq_state_q};
      `APB4_PPALITE__IRQ_ENABLE: s_read_data = {27'd0, s_irq_en_q};
      `APB4_PPALITE__IRQ_STATUS: s_read_data = {27'd0, (s_irq_state_q & s_irq_en_q)};
      `APB4_PPALITE__FIRST_ERROR: s_read_data = {24'd0, s_first_err_q};
      `APB4_PPALITE__ERROR_POSITION: s_read_data = s_err_position_q;
      `APB4_PPALITE__SOURCE_ERROR: s_read_data = {24'd0, s_source_err_q};
      `APB4_PPALITE__DMA_ERROR: s_read_data = {24'd0, s_dma_err_q};
      `APB4_PPALITE__RESULT_CONFIG: s_read_data = s_result_cfg_q;
      `APB4_PPALITE__SOURCE_GEOMETRY: s_read_data = s_source_geometry_q;
      default: s_read_data = 32'd0;
    endcase
  end

  always_comb begin
    s_access_err = (apb4.paddr[1:0] != 2'd0) ||
        (apb4.pwrite && (apb4.pstrb != 4'hf)) || (apb4.paddr[11:8] != 4'd0) ||
        (apb4.paddr[7:0] > 8'h9c);
    if (apb4.pwrite) begin
      case ({
        20'd0, apb4.paddr[11:0]
      })
        `APB4_PPALITE__ROUTE:
        s_access_err = s_access_err || (apb4.pwdata[31:1] != 31'd0) ||
            (ExternalRoute ? !route_change_i :
             ((ctrl.state != `PPALITE_STATE_IDLE) || s_owner_q || !route_idle_i));
        `APB4_PPALITE__COMMAND:
        s_access_err = s_access_err || (apb4.pwdata[31:6] != 26'd0) || !s_cmd_valid;
        `APB4_PPALITE__CONFIG:
        s_access_err = s_access_err || (ctrl.state != `PPALITE_STATE_IDLE) ||
            s_owner_q || !valid_cfg(apb4.pwdata);
        `APB4_PPALITE__INPUT_SIZE:
        s_access_err = s_access_err ||
            (ctrl.state != `PPALITE_STATE_IDLE) || s_owner_q || (apb4.pwdata[15:0] == 16'd0) ||
            (apb4.pwdata[31:16] == 16'd0) || !valid_sampling(s_shadow_sampling_q, apb4.pwdata);
        `APB4_PPALITE__SAMPLING:
        s_access_err = s_access_err ||
            (ctrl.state != `PPALITE_STATE_IDLE) || s_owner_q ||
            !valid_sampling(apb4.pwdata, s_shadow_size_q);
        `APB4_PPALITE__DESTINATION:
        s_access_err = s_access_err ||
            (ctrl.state != `PPALITE_STATE_IDLE) || s_owner_q || (apb4.pwdata[1:0] != 2'd0);
        `APB4_PPALITE__CAPACITY_BYTES:
        s_access_err = s_access_err || (ctrl.state != `PPALITE_STATE_IDLE) || s_owner_q;
        `APB4_PPALITE__IRQ_STATE: s_access_err = s_access_err || (apb4.pwdata[31:5] != 27'd0);
        `APB4_PPALITE__IRQ_ENABLE: s_access_err = s_access_err || (apb4.pwdata[31:5] != 27'd0);
        default: s_access_err = 1'b1;
      endcase
    end else if ({20'd0, apb4.paddr[11:0]} == `APB4_PPALITE__COMMAND) begin
      s_access_err = 1'b1;
    end
  end

  assign apb4.pready = s_ready_q;
  assign apb4.prdata = s_rdata_q;
  assign apb4.pslverr = s_resp_err_q;
  assign irq_o = ((s_irq_state_q & s_irq_en_q) != 5'd0);
  assign s_irq_clear = (s_req_accept && apb4.pwrite && !s_access_err &&
      ({20'd0, apb4.paddr[11:0]} == `APB4_PPALITE__IRQ_STATE)) ? apb4.pwdata[4:0] : 5'd0;
  assign s_irq_set = {
    ctrl.output_stall_event,
    ctrl.cmd[`PPALITE_COMMAND_ABORT],
    (s_monitor_active && (s_first_err_q == 8'd0) &&
      (ctrl.excess || (source_err_i != 8'd0) || source_config_err_i ||
       (transport_err_i != 8'd0) || (ctrl.core_err != 8'd0) ||
       (source_geometry_i != ctrl.input_size) || s_source_done_fault)),
    (ctrl.cmd[`PPALITE_COMMAND_FINALIZE] && s_finalize_valid),
    (ctrl.pipe_done && (ctrl.state == `PPALITE_STATE_DRAINING))
  };

  always_comb begin
    ctrl.cmd = 6'd0;
    if (s_req_accept && apb4.pwrite && !s_access_err &&
        ({20'd0, apb4.paddr[11:0]} == `APB4_PPALITE__COMMAND)) begin
      ctrl.cmd = apb4.pwdata[5:0];
    end
  end

  logic        s_ready_d;
  logic [31:0] s_rdata_d;
  logic        s_resp_err_d;

  always_comb begin
    s_ready_d    = s_ready_q;
    s_rdata_d    = s_rdata_q;
    s_resp_err_d = s_resp_err_q;
    if (!rst_n_i) begin
      s_ready_d    = 1'b0;
      s_rdata_d    = 32'd0;
      s_resp_err_d = 1'b0;
    end else begin
      s_ready_d = apb4.psel && apb4.penable && !s_ready_q;
      if (s_req_accept) begin
        s_rdata_d    = s_read_data;
        s_resp_err_d = s_access_err;
      end
    end
  end

  dffr #(
      .DATA_WIDTH(1)
  ) u_ready_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ready_d),
      .dat_o  (s_ready_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_rdata_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rdata_d),
      .dat_o  (s_rdata_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_resp_err_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_resp_err_d),
      .dat_o  (s_resp_err_q)
  );

  logic [31:0] s_shadow_cfg_d;
  logic [31:0] s_shadow_size_d;
  logic [31:0] s_shadow_sampling_d;
  logic [31:0] s_shadow_destination_d;
  logic [31:0] s_shadow_capacity_d;
  logic        s_route_d;
  typedef enum logic [2:0] {
    Idle     = 3'd0,
    Armed    = 3'd1,
    Running  = 3'd2,
    Draining = 3'd3,
    Verify   = 3'd4,
    Complete = 3'd5,
    Closing  = 3'd6
  } state_e;
  state_e        s_state_d;
  logic   [ 5:0] s_cfg_d;
  logic   [31:0] s_input_size_d;
  logic   [11:0] s_sampling_d;
  logic   [31:0] s_output_size_d;
  logic   [31:0] s_row_bytes_d;
  logic   [31:0] s_stride_bytes_d;
  logic   [31:0] s_valid_bytes_d;
  logic   [31:0] s_transport_bytes_d;
  logic   [31:0] s_expected_words_d;
  logic          s_owner_d;
  logic          s_result_valid_d;
  logic   [31:0] s_job_sequence_d;
  logic   [31:0] s_source_sequence_d;
  logic   [31:0] s_source_start_d;
  logic   [31:0] s_result_cfg_d;
  logic   [31:0] s_source_geometry_d;
  logic          s_source_done_d;
  logic          s_dma_done_d;
  logic   [ 7:0] s_source_err_d;
  logic   [ 7:0] s_dma_err_d;
  logic   [ 7:0] s_first_err_d;
  logic   [31:0] s_err_position_d;
  logic   [ 4:0] s_irq_state_d;
  logic   [ 4:0] s_irq_en_d;

  always_comb begin
    s_shadow_cfg_d         = s_shadow_cfg_q;
    s_shadow_size_d        = s_shadow_size_q;
    s_shadow_sampling_d    = s_shadow_sampling_q;
    s_shadow_destination_d = s_shadow_destination_q;
    s_shadow_capacity_d    = s_shadow_capacity_q;
    s_route_d              = s_route_q;
    s_state_d              = state_e'(ctrl.state);
    s_cfg_d                = ctrl.cfg;
    s_input_size_d         = ctrl.input_size;
    s_sampling_d           = ctrl.sampling;
    s_output_size_d        = ctrl.output_size;
    s_row_bytes_d          = ctrl.row_bytes;
    s_stride_bytes_d       = ctrl.stride_bytes;
    s_valid_bytes_d        = ctrl.valid_bytes;
    s_transport_bytes_d    = ctrl.transport_bytes;
    s_expected_words_d     = ctrl.expected_words;
    s_owner_d              = s_owner_q;
    s_result_valid_d       = s_result_valid_q;
    s_job_sequence_d       = s_job_sequence_q;
    s_source_sequence_d    = s_source_sequence_q;
    s_source_start_d       = s_source_start_q;
    s_result_cfg_d         = s_result_cfg_q;
    s_source_geometry_d    = s_source_geometry_q;
    s_source_done_d        = s_source_done_q;
    s_dma_done_d           = s_dma_done_q;
    s_source_err_d         = s_source_err_q;
    s_dma_err_d            = s_dma_err_q;
    s_first_err_d          = s_first_err_q;
    s_err_position_d       = s_err_position_q;
    s_irq_state_d          = s_irq_state_q;
    s_irq_en_d             = s_irq_en_q;
    if (!rst_n_i) begin
      s_shadow_cfg_d         = 32'd0;
      s_shadow_size_d        = 32'd0;
      s_shadow_sampling_d    = 32'd0;
      s_shadow_destination_d = 32'd0;
      s_shadow_capacity_d    = 32'd0;
      s_route_d              = 1'b0;
      s_state_d              = Idle;
      s_cfg_d                = 6'd0;
      s_input_size_d         = 32'd0;
      s_sampling_d           = 12'd0;
      s_output_size_d        = 32'd0;
      s_row_bytes_d          = 32'd0;
      s_stride_bytes_d       = 32'd0;
      s_valid_bytes_d        = 32'd0;
      s_transport_bytes_d    = 32'd0;
      s_expected_words_d     = 32'd0;
      s_owner_d              = 1'b0;
      s_result_valid_d       = 1'b0;
      s_job_sequence_d       = 32'd0;
      s_source_sequence_d    = 32'd0;
      s_source_start_d       = 32'd0;
      s_result_cfg_d         = 32'd0;
      s_source_geometry_d    = 32'd0;
      s_source_done_d        = 1'b0;
      s_dma_done_d           = 1'b0;
      s_source_err_d         = 8'd0;
      s_dma_err_d            = 8'd0;
      s_first_err_d          = 8'd0;
      s_err_position_d       = 32'd0;
      s_irq_state_d          = 5'd0;
      s_irq_en_d             = 5'd0;
    end else begin
      s_irq_state_d = (s_irq_state_q & ~s_irq_clear) | s_irq_set;
      if (s_monitor_active) begin
        if (s_source_done_valid) s_source_done_d = 1'b1;
        if (source_err_i != 8'd0) s_source_err_d = source_err_i;
        if (transport_err_i != 8'd0) s_dma_err_d = transport_err_i;
      end
      if (s_owner_q && transport_done_i) s_dma_done_d = 1'b1;
      if (s_req_accept && apb4.pwrite && !s_access_err) begin
        case ({
          20'd0, apb4.paddr[11:0]
        })
          `APB4_PPALITE__ROUTE: begin
            if (!ExternalRoute) s_route_d = apb4.pwdata[0];
            if (s_route_current != apb4.pwdata[0]) s_result_valid_d = 1'b0;
          end
          `APB4_PPALITE__CONFIG: begin
            s_shadow_cfg_d   = apb4.pwdata;
            s_result_valid_d = 1'b0;
          end
          `APB4_PPALITE__INPUT_SIZE: begin
            s_shadow_size_d  = apb4.pwdata;
            s_result_valid_d = 1'b0;
          end
          `APB4_PPALITE__SAMPLING: begin
            s_shadow_sampling_d = apb4.pwdata;
            s_result_valid_d    = 1'b0;
          end
          `APB4_PPALITE__DESTINATION: begin
            s_shadow_destination_d = apb4.pwdata;
            s_result_valid_d       = 1'b0;
          end
          `APB4_PPALITE__CAPACITY_BYTES: begin
            s_shadow_capacity_d = apb4.pwdata;
            s_result_valid_d    = 1'b0;
          end
          `APB4_PPALITE__IRQ_ENABLE: s_irq_en_d = apb4.pwdata[4:0];
          default: begin
          end
        endcase
      end
      if (ctrl.cmd[`PPALITE_COMMAND_ARM]) begin
        s_state_d           = Armed;
        s_cfg_d             = {s_shadow_cfg_q[6:4], s_shadow_cfg_q[2:0]};
        s_input_size_d      = s_shadow_size_q;
        s_sampling_d        = {s_shadow_sampling_q[17:16], s_shadow_sampling_q[9:0]};
        s_output_size_d     = {s_out_h[15:0], s_out_w[15:0]};
        s_row_bytes_d       = s_row[31:0];
        s_stride_bytes_d    = s_stride[31:0];
        s_valid_bytes_d     = s_valid[31:0];
        s_transport_bytes_d = s_transport[31:0];
        s_expected_words_d  = s_transport[33:2];
        s_owner_d           = 1'b1;
        s_result_valid_d    = 1'b0;
        s_job_sequence_d    = s_job_sequence_q + 32'd1;
        s_source_start_d    = source_sequence_i;
        s_result_cfg_d      = s_shadow_cfg_q;
        s_source_geometry_d = source_geometry_i;
        s_source_done_d     = 1'b0;
        s_dma_done_d        = 1'b0;
        s_source_err_d      = 8'd0;
        s_dma_err_d         = 8'd0;
        s_first_err_d       = 8'd0;
        s_err_position_d    = 32'd0;
      end
      if (ctrl.cmd[`PPALITE_COMMAND_FINALIZE]) begin
        s_state_d           = Complete;
        s_result_valid_d    = 1'b1;
        s_source_sequence_d = source_sequence_i;
      end
      if (ctrl.cmd[`PPALITE_COMMAND_RELEASE]) begin
        s_state_d = Idle;
        s_owner_d = 1'b0;
      end
      if (ctrl.cmd[`PPALITE_COMMAND_ABORT]) begin
        s_state_d        = Closing;
        s_result_valid_d = 1'b0;
        if (s_first_err_q == 8'd0) begin
          s_first_err_d    = `PPALITE_ERROR_ABORT;
          s_err_position_d = 32'hffff_ffff;
        end
      end
      if (ctrl.cmd[`PPALITE_COMMAND_RECOVER]) begin
        s_state_d        = Idle;
        s_owner_d        = 1'b0;
        s_result_valid_d = 1'b0;
        s_source_done_d  = 1'b0;
        s_dma_done_d     = 1'b0;
        s_source_err_d   = 8'd0;
        s_dma_err_d      = 8'd0;
        s_first_err_d    = 8'd0;
        s_err_position_d = 32'd0;
        s_irq_state_d    = 5'd0;
      end
      if (ctrl.cmd[`PPALITE_COMMAND_RESET]) begin
        s_shadow_cfg_d         = 32'd0;
        s_shadow_size_d        = 32'd0;
        s_shadow_sampling_d    = 32'd0;
        s_shadow_destination_d = 32'd0;
        s_shadow_capacity_d    = 32'd0;
        s_cfg_d                = 6'd0;
        s_input_size_d         = 32'd0;
        s_sampling_d           = 12'd0;
        s_output_size_d        = 32'd0;
        s_row_bytes_d          = 32'd0;
        s_stride_bytes_d       = 32'd0;
        s_valid_bytes_d        = 32'd0;
        s_transport_bytes_d    = 32'd0;
        s_expected_words_d     = 32'd0;
        s_result_valid_d       = 1'b0;
        s_result_cfg_d         = 32'd0;
        s_source_geometry_d    = 32'd0;
        s_source_done_d        = 1'b0;
        s_dma_done_d           = 1'b0;
        s_source_err_d         = 8'd0;
        s_dma_err_d            = 8'd0;
        s_first_err_d          = 8'd0;
        s_err_position_d       = 32'd0;
        s_job_sequence_d       = 32'd0;
        s_source_sequence_d    = 32'd0;
        s_source_start_d       = 32'd0;
        s_irq_state_d          = 5'd0;
        s_irq_en_d             = 5'd0;
      end
      if (s_owner_q && (ctrl.state != `PPALITE_STATE_CLOSING) &&
          (ctrl.state != `PPALITE_STATE_COMPLETE)) begin
        case (ctrl.state)
          `PPALITE_STATE_ARMED:    if (ctrl.started) s_state_d = Running;
          `PPALITE_STATE_RUNNING:  if (ctrl.input_done) s_state_d = Draining;
          `PPALITE_STATE_DRAINING: if (ctrl.pipe_done) s_state_d = Verify;
          default: begin
          end
        endcase
      end
      if ((ctrl.close || s_source_done_fault) && s_owner_q &&
          (ctrl.state != `PPALITE_STATE_CLOSING)) begin
        s_state_d        = Closing;
        s_result_valid_d = 1'b0;
        if (s_first_err_q == 8'd0) begin
          if (source_err_i != 8'd0) begin
            s_first_err_d    = `PPALITE_ERROR_SOURCE;
            s_err_position_d = 32'hffff_ffff;
          end else if (source_config_err_i || (source_geometry_i != ctrl.input_size)) begin
            s_first_err_d    = `PPALITE_ERROR_SOURCE_CONFIG;
            s_err_position_d = 32'hffff_ffff;
          end else if (source_stats_err_i) begin
            s_first_err_d    = `PPALITE_ERROR_GEOMETRY;
            s_err_position_d = 32'hffff_ffff;
          end else if ((ctrl.core_err != 8'd0) &&
              ((ctrl.core_err <= 8'd4) || (!s_source_done_fault && !ctrl.excess))) begin
            s_first_err_d    = ctrl.core_err;
            s_err_position_d = ctrl.err_position;
          end else if (s_source_done_fault) begin
            s_first_err_d    = `PPALITE_ERROR_GEOMETRY;
            s_err_position_d = 32'hffff_ffff;
          end else if (ctrl.excess) begin
            s_first_err_d    = `PPALITE_ERROR_GEOMETRY;
            s_err_position_d = ctrl.excess_position;
          end else if (transport_err_i != 8'd0) begin
            s_first_err_d    = `PPALITE_ERROR_DMA;
            s_err_position_d = 32'hffff_ffff;
          end
        end
      end
    end
  end

  dffr #(
      .DATA_WIDTH(161)
  ) u_shadow_reg (
      .clk_i(clk_i),
      .rst_n_i(rst_n_i),
      .dat_i({
        s_shadow_cfg_d,
        s_shadow_size_d,
        s_shadow_sampling_d,
        s_shadow_destination_d,
        s_shadow_capacity_d,
        s_route_d
      }),
      .dat_o({
        s_shadow_cfg_q,
        s_shadow_size_q,
        s_shadow_sampling_q,
        s_shadow_destination_q,
        s_shadow_capacity_q,
        s_route_q
      })
  );
  dffr #(
      .DATA_WIDTH(475)
  ) u_job_reg (
      .clk_i(clk_i),
      .rst_n_i(rst_n_i),
      .dat_i({
        s_state_d,
        s_cfg_d,
        s_input_size_d,
        s_sampling_d,
        s_output_size_d,
        s_row_bytes_d,
        s_stride_bytes_d,
        s_valid_bytes_d,
        s_transport_bytes_d,
        s_expected_words_d,
        s_owner_d,
        s_result_valid_d,
        s_job_sequence_d,
        s_source_sequence_d,
        s_source_start_d,
        s_result_cfg_d,
        s_source_geometry_d,
        s_source_done_d,
        s_dma_done_d,
        s_source_err_d,
        s_dma_err_d,
        s_first_err_d,
        s_err_position_d,
        s_irq_state_d,
        s_irq_en_d
      }),
      .dat_o({
        ctrl.state,
        ctrl.cfg,
        ctrl.input_size,
        ctrl.sampling,
        ctrl.output_size,
        ctrl.row_bytes,
        ctrl.stride_bytes,
        ctrl.valid_bytes,
        ctrl.transport_bytes,
        ctrl.expected_words,
        s_owner_q,
        s_result_valid_q,
        s_job_sequence_q,
        s_source_sequence_q,
        s_source_start_q,
        s_result_cfg_q,
        s_source_geometry_q,
        s_source_done_q,
        s_dma_done_q,
        s_source_err_q,
        s_dma_err_q,
        s_first_err_q,
        s_err_position_q,
        s_irq_state_q,
        s_irq_en_q
      })
  );
`ifdef FORMAL
  logic s_formal_past_q;
  always_ff @(posedge clk_i) begin
    if (!rst_n_i) begin
      s_formal_past_q <= 1'b0;
    end else begin
      s_formal_past_q <= 1'b1;
      if (s_formal_past_q) begin
        if ($past(
                s_req_accept && apb4.pwrite && s_access_err && !s_owner_q &&
            ({20'd0, apb4.paddr[11:0]} == `APB4_PPALITE__COMMAND)
            )) begin
          assert ($stable({ctrl.state, s_job_sequence_q, s_owner_q}));
        end
        if ($past(ctrl.cmd[`PPALITE_COMMAND_RECOVER])) begin
          assert (s_job_sequence_q == $past(s_job_sequence_q));
        end
        if ($past(
                s_monitor_active && (s_first_err_q == 8'd0) && (source_err_i == 8'd0) &&
            (source_geometry_i == ctrl.input_size) &&
            (ctrl.core_err == `PPALITE_ERROR_FRAMING) && (transport_err_i != 8'd0)
            )) begin
          assert (s_first_err_q == `PPALITE_ERROR_FRAMING);
        end
        if ($past(
                s_monitor_active && (s_first_err_q == 8'd0) && (source_err_i == 8'd0) &&
            (source_geometry_i == ctrl.input_size) && !s_source_done_fault && !ctrl.excess &&
            (ctrl.core_err == `PPALITE_ERROR_OUTPUT) && (transport_err_i != 8'd0)
            )) begin
          assert (s_first_err_q == `PPALITE_ERROR_OUTPUT);
        end
        if ($past(
                s_owner_q && !ctrl.cmd[`PPALITE_COMMAND_RECOVER] &&
            !ctrl.cmd[`PPALITE_COMMAND_RESET]
            ) && s_owner_q) begin
          assert ($stable(
              {
                ctrl.cfg,
                ctrl.input_size,
                ctrl.sampling,
                ctrl.output_size,
                ctrl.row_bytes,
                ctrl.stride_bytes,
                ctrl.valid_bytes,
                ctrl.transport_bytes,
                ctrl.expected_words,
                s_result_cfg_q,
                s_source_geometry_q
              }
          ));
        end
      end
    end
  end
`endif
endmodule
