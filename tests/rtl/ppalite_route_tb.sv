`timescale 1ns / 1ps
`include "dvp_define.svh"
`include "ppalite_define.svh"

module ppalite_route_tb;
  logic       clk_i = 1'b0;
  logic       pixel_clk_i = 1'b0;
  logic       rst_n_i = 1'b0;
  logic       source_rst_n_i = 1'b0;
  logic       pixel_run = 1'b1;
  logic       href_i = 1'b0;
  logic       vsync_i = 1'b0;
  logic [7:0] dat_i = 8'd0;
  always #5 clk_i = ~clk_i;
  always #7 if (pixel_run) pixel_clk_i = ~pixel_clk_i;

  logic [31:0] dvp_paddr = 0, dvp_pwdata = 0;
  logic dvp_psel = 0, dvp_penable = 0, dvp_pwrite = 0;
  logic [3:0] dvp_pstrb = 0;
  wire dvp_pready, dvp_pslverr;
  wire [31:0] dvp_prdata;
  logic [31:0] ppa_paddr = 0, ppa_pwdata = 0;
  logic ppa_psel = 0, ppa_penable = 0, ppa_pwrite = 0;
  logic [3:0] ppa_pstrb = 0;
  wire ppa_pready, ppa_pslverr;
  wire [31:0] ppa_prdata;
  logic dma_idle = 1'b1, dma_start = 1'b0;
  logic transport_ready = 1'b1, transport_idle = 1'b1, transport_admitted = 1'b0;
  logic       transport_done = 1'b0;
  logic [7:0] transport_err = 8'd0;
  logic       stream_isolated = 1'b0;
  logic       out_ready = 1'b1;
  wire out_valid, out_last, out_id, out_dest, out_user;
  wire [31:0] out_data;
  wire [3:0] out_keep, out_strb;
  wire dvp_irq, ppa_irq;
  wire [127:0] source_config;
  wire source_status_valid, source_lifecycle_idle, source_reset_ready;
  wire [`APB4_DVP__FRAME_STATS_WIDTH-1:0] source_frame_stats;
  wire                                    source_frame_stats_valid;
  wire [                             5:0] source_error;

`ifndef PPALITE_ROUTE_DUT
  `define PPALITE_ROUTE_DUT apb4_ppalite_route_top
`endif
  `PPALITE_ROUTE_DUT u_dut (
      .clk_i                     (clk_i),
      .pixel_clk_i               (pixel_clk_i),
      .rst_n_i                   (rst_n_i),
      .source_rst_n_i            (source_rst_n_i),
      .href_i                    (href_i),
      .vsync_i                   (vsync_i),
      .dat_i                     (dat_i),
      .dvp_paddr_i               (dvp_paddr),
      .dvp_pprot_i               (3'd0),
      .dvp_psel_i                (dvp_psel),
      .dvp_penable_i             (dvp_penable),
      .dvp_pwrite_i              (dvp_pwrite),
      .dvp_pwdata_i              (dvp_pwdata),
      .dvp_pstrb_i               (dvp_pstrb),
      .dvp_pready_o              (dvp_pready),
      .dvp_prdata_o              (dvp_prdata),
      .dvp_pslverr_o             (dvp_pslverr),
      .ppa_paddr_i               (ppa_paddr),
      .ppa_pprot_i               (3'd0),
      .ppa_psel_i                (ppa_psel),
      .ppa_penable_i             (ppa_penable),
      .ppa_pwrite_i              (ppa_pwrite),
      .ppa_pwdata_i              (ppa_pwdata),
      .ppa_pstrb_i               (ppa_pstrb),
      .ppa_pready_o              (ppa_pready),
      .ppa_prdata_o              (ppa_prdata),
      .ppa_pslverr_o             (ppa_pslverr),
      .dma_idle_i                (dma_idle),
      .dma_start_i               (dma_start),
      .transport_ready_i         (transport_ready),
      .transport_idle_i          (transport_idle),
      .transport_admitted_i      (transport_admitted),
      .transport_done_i          (transport_done),
      .transport_err_i           (transport_err),
      .stream_isolated_i         (stream_isolated),
      .out_valid_o               (out_valid),
      .out_ready_i               (out_ready),
      .out_data_o                (out_data),
      .out_keep_o                (out_keep),
      .out_strb_o                (out_strb),
      .out_last_o                (out_last),
      .out_id_o                  (out_id),
      .out_dest_o                (out_dest),
      .out_user_o                (out_user),
      .dvp_irq_o                 (dvp_irq),
      .ppa_irq_o                 (ppa_irq),
      .source_config_o           (source_config),
      .source_status_valid_o     (source_status_valid),
      .source_lifecycle_idle_o   (source_lifecycle_idle),
      .source_reset_ready_o      (source_reset_ready),
      .source_frame_stats_o      (source_frame_stats),
      .source_frame_stats_valid_o(source_frame_stats_valid),
      .source_error_o            (source_error)
  );

  integer        case_id = 0;
  integer        received = 0;
  integer        expected_count = 0;
  logic          checking = 1'b0;
  logic   [31:0] expected_data          [0:255];
  logic   [ 3:0] expected_keep          [0:255];
  logic          expected_last          [0:255];
  logic          expected_user          [0:255];
  logic          stalled_q = 1'b0;
  logic   [43:0] stalled_payload_q = '0;

  always @(posedge clk_i) begin
    if (!rst_n_i) begin
      stalled_q <= 1'b0;
    end else begin
      if (stalled_q && ({out_data, out_keep, out_strb, out_last, out_id, out_dest, out_user} !==
                        stalled_payload_q)) begin
        $fatal(1, "SIM_TEST_FAIL route output changed under backpressure");
      end
      stalled_q         <= out_valid && !out_ready;
      stalled_payload_q <= {out_data, out_keep, out_strb, out_last, out_id, out_dest, out_user};
      if (checking && out_valid && out_ready) begin
        if (received >= expected_count || out_data !== expected_data[received] ||
            out_keep !== expected_keep[received] || out_strb !== expected_keep[received] ||
            out_last !== expected_last[received] || out_user !== expected_user[received] ||
            out_id !== 1'b0 || out_dest !== 1'b0) begin
          $fatal(1, "SIM_TEST_FAIL route word=%0d data=%h keep=%h last=%b user=%b", received,
                 out_data, out_keep, out_last, out_user);
        end
        received <= received + 1;
      end
    end
  end

  task automatic access (input logic ppa, input logic write_access, input logic [31:0] address,
                         input logic [31:0] wdata, input logic expected_err,
                         output logic [31:0] rdata);
    @(negedge clk_i);
    if (ppa) begin
      ppa_paddr   = address;
      ppa_pwdata  = wdata;
      ppa_pstrb   = write_access ? 4'hf : 4'd0;
      ppa_pwrite  = write_access;
      ppa_psel    = 1'b1;
      ppa_penable = 1'b0;
    end else begin
      dvp_paddr   = address;
      dvp_pwdata  = wdata;
      dvp_pstrb   = write_access ? 4'hf : 4'd0;
      dvp_pwrite  = write_access;
      dvp_psel    = 1'b1;
      dvp_penable = 1'b0;
    end
    @(negedge clk_i);
    if (ppa) ppa_penable = 1'b1;
    else dvp_penable = 1'b1;
    for (integer timeout = 0; !(ppa ? ppa_pready : dvp_pready); timeout++) begin
      if (timeout == 15) $fatal(1, "SIM_TEST_TIMEOUT route APB ppa=%0d addr=%h", ppa, address);
      @(negedge clk_i);
    end
    if ((ppa ? ppa_pslverr : dvp_pslverr) !== expected_err) begin
      $fatal(1, "SIM_TEST_FAIL route APB ppa=%0d addr=%h err=%b expected=%b", ppa, address,
             (ppa ? ppa_pslverr : dvp_pslverr), expected_err);
    end
    rdata = ppa ? ppa_prdata : dvp_prdata;
    $display("PPALITE_TRACE_APB ppa=%0d write=%0d addr=%h data=%h err=%b", ppa, write_access,
             address, rdata, (ppa ? ppa_pslverr : dvp_pslverr));
    @(negedge clk_i);
    if (ppa) begin
      ppa_psel    = 1'b0;
      ppa_penable = 1'b0;
      ppa_pwrite  = 1'b0;
      ppa_pstrb   = 4'd0;
    end else begin
      dvp_psel    = 1'b0;
      dvp_penable = 1'b0;
      dvp_pwrite  = 1'b0;
      dvp_pstrb   = 4'd0;
    end
  endtask

  task automatic dvp_wr(input logic [31:0] address, input logic [31:0] data, input logic err);
    logic [31:0] unused;
    access (1'b0, 1'b1, address, data, err, unused);
  endtask
  task automatic dvp_custom(input logic [31:0] address, input logic [31:0] data,
                            input logic write_access, input logic [3:0] strobe, input logic err);
    @(negedge clk_i);
    dvp_paddr   = address;
    dvp_pwdata  = data;
    dvp_pstrb   = strobe;
    dvp_pwrite  = write_access;
    dvp_psel    = 1'b1;
    dvp_penable = 1'b0;
    @(negedge clk_i);
    dvp_penable = 1'b1;
    for (integer timeout = 0; !dvp_pready; timeout++) begin
      if (timeout == 15) $fatal(1, "SIM_TEST_TIMEOUT custom DVP APB addr=%h", address);
      @(negedge clk_i);
    end
    if (dvp_pslverr !== err) begin
      $fatal(1, "SIM_TEST_FAIL custom DVP APB addr=%h err=%b expected=%b", address, dvp_pslverr,
             err);
    end
    @(negedge clk_i);
    dvp_psel    = 1'b0;
    dvp_penable = 1'b0;
    dvp_pwrite  = 1'b0;
    dvp_pstrb   = 4'd0;
  endtask
  task automatic ppa_wr(input logic [31:0] address, input logic [31:0] data, input logic err);
    logic [31:0] unused;
    access (1'b1, 1'b1, address, data, err, unused);
  endtask
  task automatic dvp_expect(input logic [31:0] address, input logic [31:0] expected);
    logic [31:0] value;
    access (1'b0, 1'b0, address, 32'd0, 1'b0, value);
    if (value !== expected)
      $fatal(1, "SIM_TEST_FAIL DVP addr=%h got=%h expected=%h", address, value, expected);
  endtask
  task automatic dvp_nonzero(input logic [31:0] address);
    logic [31:0] value;
    access (1'b0, 1'b0, address, 32'd0, 1'b0, value);
    if (value == 0) $fatal(1, "SIM_TEST_FAIL DVP addr=%h is zero", address);
  endtask
  task automatic ppa_expect(input logic [31:0] address, input logic [31:0] expected);
    logic [31:0] value;
    access (1'b1, 1'b0, address, 32'd0, 1'b0, value);
`ifndef PPALITE_ROUTE_NETLIST
    if (address == 32'h01c) begin
      $display(
          "PPALITE_TRACE_STATUS state=%0d owner=%b result=%b src_done=%b dma_done=%b internal=%h value=%h",
          u_dut.u_ppa.u_ctrl.state, u_dut.u_ppa.u_reg.s_owner_q,
          u_dut.u_ppa.u_reg.s_result_valid_q, u_dut.u_ppa.u_reg.s_source_done_q,
          u_dut.u_ppa.u_reg.s_dma_done_q, u_dut.u_ppa.u_reg.s_status, value);
      $display("PPALITE_TRACE_RDATA addr=%h read_data=%h rdata_q=%h bus=%h", u_dut.u_ppa_apb.paddr,
               u_dut.u_ppa.u_reg.s_read_data, u_dut.u_ppa.u_reg.s_rdata_q, ppa_prdata);
    end
`endif
    if (value !== expected)
      $fatal(1, "SIM_TEST_FAIL PPA addr=%h got=%h expected=%h", address, value, expected);
  endtask
  task automatic ppa_status(input logic [2:0] expected);
    logic [31:0] value;
    access (1'b1, 1'b0, 32'h01c, 32'd0, 1'b0, value);
    if (value[2:0] !== expected)
      $fatal(1, "SIM_TEST_FAIL PPA state=%0d expected=%0d status=%h", value[2:0], expected, value);
  endtask

  task automatic check_early_eof;
    logic [31:0] value;
    access (1'b1, 1'b0, 32'h01c, 32'd0, 1'b0, value);
    if ((value[2:0] == `PPALITE_STATE_CLOSING) || !value[11] || value[9]) begin
      $fatal(1, "SIM_TEST_FAIL early EOF was not retained while INPUT_DONE=0: %h", value);
    end
  endtask

  task automatic configure_dvp(input integer width, input integer height);
    dvp_wr(32'h000, 32'd0, 1'b0);
    dvp_wr(32'h018, {16'(height), 16'(width)}, 1'b0);
    dvp_wr(32'h01c, 32'd0, 1'b0);
    dvp_wr(32'h020, {16'(height), 16'(width)}, 1'b0);
    dvp_wr(32'h010, 32'd0, 1'b0);
    dvp_wr(32'h014, 32'd0, 1'b0);
    dvp_wr(32'h00c, 32'd1, 1'b0);
    dvp_wr(32'h000, 32'd2, 1'b0);
    repeat (100) @(negedge pixel_clk_i);
  endtask

  task automatic configure_ppa(input integer width, input integer height);
    ppa_wr(32'h020, 32'd0, 1'b0);
    ppa_wr(32'h024, {16'(height), 16'(width)}, 1'b0);
    ppa_wr(32'h028, 32'd0, 1'b0);
    ppa_wr(32'h030, 32'h00010000, 1'b0);
    ppa_wr(32'h034, 32'h00010000, 1'b0);
  endtask

  task automatic expected_frame(input integer width, input integer height, input logic processed);
    integer words_per_row = (width + 1) / 2;
    expected_count = words_per_row * height;
    for (integer row = 0; row < height; row++) begin
      for (integer column = 0; column < words_per_row; column++) begin
        integer index = row * words_per_row + column;
        integer base = row * 8 + column * 4;
        if ((width % 2 != 0) && (column == width / 2)) begin
          expected_data[index] = {16'd0, 8'(base), 8'(base + 1)};
          expected_keep[index] = processed ? 4'hf : 4'h3;
        end else begin
          expected_data[index] = {8'(base + 2), 8'(base + 3), 8'(base), 8'(base + 1)};
          expected_keep[index] = 4'hf;
        end
        expected_last[index] = column == words_per_row - 1;
        expected_user[index] = index == 0;
      end
    end
    received = 0;
    checking = 1'b1;
  endtask

  task automatic wait_source_enabled;
    for (integer timeout = 0; timeout < 100; timeout++) begin
      logic [31:0] status;
      access (1'b0, 1'b0, 32'h008, 32'd0, 1'b0, status);
      if (status[0]) return;
      repeat (2) @(negedge pixel_clk_i);
    end
    $fatal(1, "SIM_TEST_TIMEOUT DVP enable acknowledgement case=%0d", case_id);
  endtask

  task automatic send_frame(input integer width, input integer height, input logic malformed);
    wait_source_enabled();
`ifndef PPALITE_ROUTE_NETLIST
    $display("PPALITE_TRACE_FRAME_BEGIN case=%0d en=%b active=%b line=%0d pixel=%0d", case_id,
             u_dut.u_dvp.u_dvp_core.s_en, u_dut.u_dvp.u_dvp_core.s_frm_active_q,
             u_dut.u_dvp.u_dvp_core.s_line_q, u_dut.u_dvp.u_dvp_core.s_pixel_total_q);
`endif
    repeat (3) @(negedge pixel_clk_i);
    vsync_i = 1'b1;
    repeat (3) @(negedge pixel_clk_i);
    vsync_i = 1'b0;
    repeat (3) @(negedge pixel_clk_i);
    for (integer row = 0; row < height; row++) begin
      integer bytes = (malformed && row == 0) ? 4 : width * 2;
      href_i = 1'b1;
      for (integer index = 0; index < bytes; index++) begin
        dat_i = 8'(row * 8 + index);
        @(negedge pixel_clk_i);
      end
      href_i = 1'b0;
      repeat (3) @(negedge pixel_clk_i);
    end
    vsync_i = 1'b1;
    repeat (3) @(negedge pixel_clk_i);
    vsync_i = 1'b0;
`ifndef PPALITE_ROUTE_NETLIST
    $display("PPALITE_TRACE_FRAME_END case=%0d en=%b active=%b line=%0d pixel=%0d", case_id,
             u_dut.u_dvp.u_dvp_core.s_en, u_dut.u_dvp.u_dvp_core.s_frm_active_q,
             u_dut.u_dvp.u_dvp_core.s_line_q, u_dut.u_dvp.u_dvp_core.s_pixel_total_q);
`endif
    repeat (100) @(negedge clk_i);
  endtask

  task automatic finish_frame(input integer frame_index);
`ifndef PPALITE_ROUTE_NETLIST
    $display(
        "PPALITE_TRACE_FINISH expected=%0d state=%0d en=%b active=%b stats=%h valid=%b core_en=%b snap=%b pending=%b",
        frame_index, u_dut.u_ppa.u_ctrl.state, u_dut.u_route.source_enabled_i,
        u_dut.u_route.source_active_i, u_dut.source_frame_stats_o,
        u_dut.source_frame_stats_valid_o, u_dut.u_dvp.u_dvp_core.s_en,
        u_dut.u_dvp.u_dvp_core.s_snapshot_done_q, u_dut.u_route.source_config_pending_i);
    $display("PPALITE_TRACE_ENABLE host_ctrl=%h cdc_en=%b applied_en=%b cancel=%b/%b epochs=%b%b%b",
             u_dut.u_dvp.u_dvp_reg.s_ctrl_q, u_dut.u_dvp.s_cfg_pclk_q[96],
             u_dut.u_dvp.s_cfg_applied_pclk_q[96], u_dut.u_dvp.s_cfg_cancel_q,
             u_dut.u_dvp.s_cfg_cancel_apply, u_dut.u_dvp.s_cfg_epoch_q,
             u_dut.u_dvp.s_cfg_epoch_pclk_q, u_dut.u_dvp.s_cfg_epoch_latched_q);
`endif
    dvp_expect(32'h024, 32'(frame_index));
    transport_done = 1'b1;
    @(negedge clk_i);
    transport_done = 1'b0;
    transport_idle = 1'b1;
    dvp_wr(32'h000, 32'd2, 1'b0);
    repeat (100) @(negedge pixel_clk_i);
    if (received != expected_count)
      $fatal(1, "SIM_TEST_FAIL route received=%0d expected=%0d", received, expected_count);
    checking = 1'b0;
    ppa_wr(32'h018, 32'd2, 1'b0);
    ppa_expect(32'h01c, 32'h0000_ff05);
    ppa_wr(32'h018, 32'd4, 1'b0);
    ppa_status(`PPALITE_STATE_IDLE);
    transport_admitted = 1'b0;
  endtask

  task automatic route_race;
    dma_start = 1'b1;
    ppa_wr(32'h014, 32'd0, 1'b1);
    ppa_wr(32'h014, 32'd1, 1'b0);
    ppa_expect(32'h014, 32'd1);
    dma_start = 1'b0;
    dma_idle  = 1'b1;
    $display("PPALITE_P2_COVER route-start-priority-and-same-value-noop");
  endtask

  task automatic source_arm_race;
    @(negedge clk_i);
    dvp_paddr   = 32'h014;
    dvp_pwdata  = 32'd0;
    dvp_pstrb   = 4'hf;
    dvp_pwrite  = 1'b1;
    dvp_psel    = 1'b1;
    dvp_penable = 1'b0;
    ppa_paddr   = 32'h018;
    ppa_pwdata  = 32'd1;
    ppa_pstrb   = 4'hf;
    ppa_pwrite  = 1'b1;
    ppa_psel    = 1'b1;
    ppa_penable = 1'b0;
    @(negedge clk_i);
    dvp_penable = 1'b1;
    ppa_penable = 1'b1;
    @(negedge clk_i);
    if (!dvp_pready || dvp_pslverr || !ppa_pready || !ppa_pslverr) begin
      $fatal(1, "SIM_TEST_FAIL source-update/ARM priority dvp=%b/%b ppa=%b/%b", dvp_pready,
             dvp_pslverr, ppa_pready, ppa_pslverr);
    end
    dvp_psel    = 1'b0;
    dvp_penable = 1'b0;
    dvp_pwrite  = 1'b0;
    dvp_pstrb   = 4'd0;
    ppa_psel    = 1'b0;
    ppa_penable = 1'b0;
    ppa_pwrite  = 1'b0;
    ppa_pstrb   = 4'd0;
    repeat (100) @(negedge pixel_clk_i);
    $display("PPALITE_P2_COVER accepted-source-update-beats-arm");
  endtask

  task automatic route_source_race;
    @(negedge clk_i);
    dvp_paddr   = 32'h014;
    dvp_pwdata  = 32'd0;
    dvp_pstrb   = 4'hf;
    dvp_pwrite  = 1'b1;
    dvp_psel    = 1'b1;
    dvp_penable = 1'b0;
    ppa_paddr   = 32'h014;
    ppa_pwdata  = 32'd1;
    ppa_pstrb   = 4'hf;
    ppa_pwrite  = 1'b1;
    ppa_psel    = 1'b1;
    ppa_penable = 1'b0;
    @(negedge clk_i);
    dvp_penable = 1'b1;
    ppa_penable = 1'b1;
    @(negedge clk_i);
    if (!dvp_pready || dvp_pslverr || !ppa_pready || !ppa_pslverr) begin
      $fatal(1, "SIM_TEST_FAIL source-update/route priority dvp=%b/%b ppa=%b/%b", dvp_pready,
             dvp_pslverr, ppa_pready, ppa_pslverr);
    end
    dvp_psel    = 1'b0;
    dvp_penable = 1'b0;
    dvp_pwrite  = 1'b0;
    dvp_pstrb   = 4'd0;
    ppa_psel    = 1'b0;
    ppa_penable = 1'b0;
    ppa_pwrite  = 1'b0;
    ppa_pstrb   = 4'd0;
    repeat (100) @(negedge pixel_clk_i);
    $display("PPALITE_P2_COVER source-cdc-beats-route-change");
  endtask

  initial begin
    #2000000;
    $fatal(1, "SIM_TEST_TIMEOUT PPALite route case=%0d", case_id);
  end

  initial begin
    if (!$value$plusargs("case=%d", case_id)) case_id = 1;
    repeat (6) @(negedge clk_i);
    rst_n_i        = 1'b1;
    source_rst_n_i = 1'b1;
    repeat (100) @(negedge pixel_clk_i);
    case (case_id)
      1: begin
        configure_dvp(4, 2);
        configure_ppa(4, 2);
        ppa_wr(32'h014, 32'd1, 1'b0);
        dvp_wr(32'h000, 32'd3, 1'b1);
        dvp_expect(32'h000, 32'd2);
        source_arm_race();
        ppa_wr(32'h018, 32'd1, 1'b0);
        transport_admitted = 1'b1;
        transport_idle     = 1'b0;
        dvp_wr(32'h010, 32'd1, 1'b1);
        dvp_expect(32'h010, 32'd0);
        dvp_wr(32'h04c, 32'd1, 1'b1);
        dvp_expect(32'h038, 32'd0);
`ifndef PPALITE_ROUTE_NETLIST
        $display(
            "PPALITE_TRACE_START state=%0d route=%b cfg_pending=%b cmd_pending=%b enabled=%b admitted=%b",
            u_dut.u_route.capture_state_i, u_dut.u_route.route_o,
            u_dut.u_route.source_config_pending_i, u_dut.u_route.source_command_pending_i,
            u_dut.u_route.source_enabled_i, u_dut.u_route.transport_admitted_i);
        $display(
            "PPALITE_TRACE_CLOSE first=%h core=%h cfg_err=%b stats_err=%b src_err=%h valid=%b geom=%h/%h",
            u_dut.u_ppa.u_reg.s_first_err_q, u_dut.u_ppa.u_ctrl.core_err,
            u_dut.u_route.source_config_err_o, u_dut.u_route.source_stats_err_o,
            u_dut.u_route.source_err_o, u_dut.u_route.source_status_valid_i,
            u_dut.u_route.source_geometry_o, u_dut.u_ppa.u_ctrl.input_size);
`endif
        dvp_wr(32'h000, 32'd3, 1'b0);
        expected_frame(4, 2, 1'b1);
        send_frame(4, 2, 1'b0);
        finish_frame(1);
        ppa_expect(32'h050, 32'd1);
        ppa_expect(32'h054, 32'd1);
        ppa_expect(32'h014, 32'd1);
        route_race();
        ppa_wr(32'h014, 32'd0, 1'b0);
        ppa_expect(32'h014, 32'd0);
        $display("PPALITE_P2_COVER process-complete-release-route-retention");
      end
      2: begin
        configure_dvp(3, 1);
        ppa_wr(32'h014, 32'd0, 1'b0);
        dvp_wr(32'h000, 32'd3, 1'b0);
        expected_frame(3, 1, 1'b0);
        out_ready = 1'b0;
        send_frame(3, 1, 1'b0);
        repeat (10) @(negedge clk_i);
        out_ready = 1'b1;
        repeat (20) @(negedge clk_i);
        if (received != expected_count) $fatal(1, "SIM_TEST_FAIL raw odd-width drain");
        checking = 1'b0;
        dvp_expect(32'h030, 32'd2);
        dvp_wr(32'h000, 32'd2, 1'b0);
        repeat (100) @(negedge pixel_clk_i);
        configure_ppa(3, 1);
        ppa_wr(32'h014, 32'd1, 1'b0);
        ppa_wr(32'h018, 32'd1, 1'b0);
        transport_admitted = 1'b1;
        transport_idle     = 1'b0;
        dvp_wr(32'h000, 32'd3, 1'b0);
        expected_frame(3, 1, 1'b1);
        send_frame(3, 1, 1'b0);
        finish_frame(2);
        $display("PPALITE_P2_COVER raw-parity-odd-tail-and-process-packed-tail");
      end
      3: begin
        configure_dvp(4, 2);
        configure_ppa(4, 2);
        ppa_wr(32'h014, 32'd1, 1'b0);
        ppa_wr(32'h018, 32'd1, 1'b0);
        transport_admitted = 1'b1;
        transport_idle     = 1'b0;
        dvp_wr(32'h000, 32'd3, 1'b0);
        expected_frame(4, 2, 1'b1);
        send_frame(4, 2, 1'b0);
        finish_frame(1);
        ppa_wr(32'h018, 32'd1, 1'b0);
        transport_admitted = 1'b1;
        transport_idle     = 1'b0;
        dvp_wr(32'h000, 32'd3, 1'b0);
        expected_frame(4, 2, 1'b1);
        send_frame(4, 2, 1'b0);
        finish_frame(2);
        ppa_expect(32'h050, 32'd2);
        ppa_expect(32'h054, 32'd2);
        $display("PPALITE_P2_COVER repeated-snapshot-frame-and-job-epochs");
      end
      4: begin
        configure_dvp(4, 2);
        configure_ppa(4, 2);
        ppa_wr(32'h014, 32'd1, 1'b0);
        ppa_wr(32'h018, 32'd1, 1'b0);
        transport_admitted = 1'b1;
        transport_idle     = 1'b0;
        pixel_run          = 1'b0;
        dvp_wr(32'h000, 32'd3, 1'b0);
        ppa_wr(32'h018, 32'd8, 1'b0);
        ppa_wr(32'h018, 32'd16, 1'b1);
        transport_idle  = 1'b1;
        stream_isolated = 1'b1;
        dvp_wr(32'h04c, 32'd1, 1'b0);
        ppa_wr(32'h018, 32'd16, 1'b1);
        ppa_status(`PPALITE_STATE_CLOSING);
        pixel_run = 1'b1;
        repeat (100) @(negedge pixel_clk_i);
        dvp_wr(32'h04c, 32'd1, 1'b0);
        repeat (100) @(negedge pixel_clk_i);
        dvp_wr(32'h038, 32'h3f, 1'b0);
        repeat (100) @(negedge pixel_clk_i);
        ppa_wr(32'h018, 32'd16, 1'b0);
        ppa_status(`PPALITE_STATE_IDLE);
        ppa_expect(32'h014, 32'd1);
        $display("PPALITE_P2_COVER missing-pixclk-retains-owner-until-acknowledgement");
      end
      5: begin
        configure_dvp(4, 2);
        configure_ppa(4, 2);
        ppa_wr(32'h014, 32'd1, 1'b0);
        ppa_wr(32'h018, 32'd1, 1'b0);
        transport_admitted = 1'b1;
        transport_idle     = 1'b0;
        dvp_wr(32'h000, 32'd3, 1'b0);
        repeat (20) @(negedge pixel_clk_i);
        source_rst_n_i = 1'b0;
        repeat (20) @(negedge clk_i);
        ppa_status(`PPALITE_STATE_CLOSING);
        ppa_wr(32'h014, 32'd0, 1'b1);
        ppa_expect(32'h014, 32'd1);
        source_rst_n_i = 1'b1;
        repeat (100) @(negedge pixel_clk_i);
        transport_idle  = 1'b1;
        stream_isolated = 1'b1;
        dvp_wr(32'h04c, 32'd1, 1'b0);
        repeat (100) @(negedge pixel_clk_i);
        dvp_wr(32'h038, 32'h3f, 1'b0);
        repeat (100) @(negedge pixel_clk_i);
        ppa_wr(32'h018, 32'd16, 1'b0);
        ppa_status(`PPALITE_STATE_IDLE);
        ppa_expect(32'h014, 32'd1);
        $display("PPALITE_P2_COVER unilateral-source-reset-closes-and-preserves-route");
      end
      6: begin
        configure_dvp(4, 2);
        dvp_wr(32'h01c, 32'h00010000, 1'b0);
        dvp_wr(32'h020, 32'h00010002, 1'b0);
        dvp_wr(32'h000, 32'd6, 1'b0);
        repeat (100) @(negedge pixel_clk_i);
        configure_ppa(2, 1);
        ppa_wr(32'h014, 32'd1, 1'b0);
        ppa_wr(32'h018, 32'd1, 1'b0);
        transport_admitted = 1'b1;
        transport_idle     = 1'b0;
        dvp_wr(32'h000, 32'd7, 1'b0);
        send_frame(4, 2, 1'b1);
        ppa_status(`PPALITE_STATE_CLOSING);
        ppa_expect(32'h088, 32'd1);
        dvp_expect(32'h038, 32'h00000004);
        transport_idle  = 1'b1;
        stream_isolated = 1'b1;
        dvp_wr(32'h04c, 32'd1, 1'b0);
        repeat (100) @(negedge pixel_clk_i);
        dvp_wr(32'h000, 32'd6, 1'b0);
        repeat (100) @(negedge pixel_clk_i);
        dvp_wr(32'h038, 32'h3f, 1'b0);
        repeat (100) @(negedge pixel_clk_i);
        ppa_wr(32'h018, 32'd16, 1'b0);
        ppa_status(`PPALITE_STATE_IDLE);
        ppa_expect(32'h014, 32'd1);
        $display("PPALITE_P2_COVER malformed-row-outside-crop-closes-capture");
      end
      7: begin
        configure_dvp(4, 2);
        configure_ppa(4, 2);
        ppa_wr(32'h014, 32'd1, 1'b0);
        ppa_wr(32'h018, 32'd1, 1'b0);
        dvp_wr(32'h000, 32'd3, 1'b1);
        dvp_expect(32'h000, 32'd2);
        ppa_wr(32'h018, 32'd8, 1'b0);
        transport_idle  = 1'b1;
        stream_isolated = 1'b1;
        dvp_wr(32'h04c, 32'd1, 1'b0);
        repeat (100) @(negedge pixel_clk_i);
        dvp_wr(32'h038, 32'h3f, 1'b0);
        repeat (100) @(negedge pixel_clk_i);
        ppa_wr(32'h018, 32'd16, 1'b0);
        ppa_status(`PPALITE_STATE_IDLE);
        ppa_wr(32'h018, 32'd1, 1'b0);
        transport_admitted = 1'b1;
        transport_idle     = 1'b0;
        dvp_wr(32'h000, 32'd3, 1'b0);
        expected_frame(4, 2, 1'b1);
        send_frame(4, 2, 1'b0);
        finish_frame(1);
        $display("PPALITE_P2_COVER source-start-requires-exact-dma-admission");
      end
      8: begin
        configure_dvp(4, 4);
        configure_ppa(4, 4);
        ppa_wr(32'h028, 32'h00000008, 1'b0);
        ppa_wr(32'h014, 32'd1, 1'b0);
        ppa_wr(32'h018, 32'd1, 1'b0);
        transport_admitted = 1'b1;
        transport_idle     = 1'b0;
        dvp_wr(32'h000, 32'd3, 1'b0);
        expected_frame(4, 4, 1'b1);
        expected_count = 2;
        send_frame(4, 4, 1'b0);
        finish_frame(1);
        dvp_expect(32'h030, 32'd8);
        ppa_expect(32'h058, 32'd8);
        ppa_expect(32'h06c, 32'd1);
        $display("PPALITE_P2_COVER dropped-trailing-rows-drain-after-output-completion");
      end
      9: begin
        configure_dvp(4, 2);
        configure_ppa(4, 2);
        ppa_wr(32'h014, 32'd1, 1'b0);
        ppa_wr(32'h018, 32'd1, 1'b0);
        transport_idle     = 1'b0;
        transport_admitted = 1'b0;
        @(negedge clk_i);
        dvp_paddr   = 32'd0;
        dvp_pwdata  = 32'd3;
        dvp_pstrb   = 4'hf;
        dvp_pwrite  = 1'b1;
        dvp_psel    = 1'b1;
        dvp_penable = 1'b0;
        @(negedge clk_i);
        dvp_penable = 1'b1;
        @(negedge clk_i);
        transport_admitted = 1'b1;
        for (integer timeout = 0; !dvp_pready; timeout++) begin
          if (timeout == 15) $fatal(1, "SIM_TEST_TIMEOUT rejection response");
          @(negedge clk_i);
        end
        if (!dvp_pslverr) $fatal(1, "SIM_TEST_FAIL changing legality hid rejection");
        @(negedge clk_i);
        dvp_penable = 1'b0;
        @(negedge clk_i);
        dvp_penable = 1'b1;
        for (integer timeout = 0; !dvp_pready; timeout++) begin
          if (timeout == 15) $fatal(1, "SIM_TEST_TIMEOUT back-to-back legal response");
          @(negedge clk_i);
        end
        if (dvp_pslverr) $fatal(1, "SIM_TEST_FAIL back-to-back legal transfer rejected");
        dvp_psel    = 1'b0;
        dvp_penable = 1'b0;
        dvp_pwrite  = 1'b0;
        dvp_pstrb   = 4'd0;
        expected_frame(4, 2, 1'b1);
        send_frame(4, 2, 1'b0);
        finish_frame(1);
        $display("PPALITE_P2_COVER rejection-response-legality-change-and-back-to-back");
      end
      10: begin
        configure_dvp(24, 1);
        configure_ppa(24, 1);
        ppa_wr(32'h014, 32'd1, 1'b0);
        ppa_wr(32'h018, 32'd1, 1'b0);
        transport_admitted = 1'b1;
        transport_idle     = 1'b0;
        out_ready          = 1'b0;
        dvp_wr(32'h000, 32'd3, 1'b0);
        expected_frame(24, 1, 1'b1);
        send_frame(24, 1, 1'b0);
        check_early_eof();
        out_ready = 1'b1;
        finish_frame(1);
        $display("PPALITE_P2_COVER source-eof-before-input-done-drains");
      end
      11: begin
        configure_dvp(300, 1);
        configure_ppa(300, 1);
        ppa_wr(32'h014, 32'd1, 1'b0);
        ppa_wr(32'h018, 32'd1, 1'b0);
        transport_admitted = 1'b1;
        transport_idle     = 1'b0;
        out_ready          = 1'b0;
        dvp_wr(32'h000, 32'd3, 1'b0);
        send_frame(300, 1, 1'b0);
        ppa_status(`PPALITE_STATE_CLOSING);
        dvp_expect(32'h038, 32'h00000001);
        transport_idle  = 1'b1;
        stream_isolated = 1'b1;
        dvp_wr(32'h04c, 32'd1, 1'b0);
        repeat (100) @(negedge pixel_clk_i);
        dvp_wr(32'h000, 32'd2, 1'b0);
        repeat (100) @(negedge pixel_clk_i);
        dvp_wr(32'h038, 32'h3f, 1'b0);
        repeat (100) @(negedge pixel_clk_i);
        out_ready = 1'b1;
        repeat (20) @(negedge clk_i);
        ppa_wr(32'h018, 32'd16, 1'b0);
        ppa_status(`PPALITE_STATE_IDLE);
        configure_dvp(4, 2);
        configure_ppa(4, 2);
        ppa_wr(32'h018, 32'd1, 1'b0);
        transport_admitted = 1'b1;
        transport_idle     = 1'b0;
        dvp_wr(32'h000, 32'd3, 1'b0);
        expected_frame(4, 2, 1'b1);
        send_frame(4, 2, 1'b0);
        finish_frame(1);
        dvp_expect(32'h034, 32'd0);
        $display("PPALITE_P2_COVER overflow-recovery-resets-drop-count-epoch");
      end
      12: begin
        configure_dvp(4, 2);
        dvp_wr(32'h01c, 32'h00000003, 1'b0);
        dvp_wr(32'h020, 32'h00010002, 1'b0);
        dvp_wr(32'h000, 32'd6, 1'b0);
        repeat (100) @(negedge pixel_clk_i);
        configure_ppa(2, 1);
        ppa_wr(32'h014, 32'd1, 1'b0);
        ppa_wr(32'h018, 32'd1, 1'b1);
        ppa_status(`PPALITE_STATE_IDLE);
        ppa_wr(32'h014, 32'd0, 1'b0);
        dvp_wr(32'h000, 32'd7, 1'b0);
        repeat (100) @(negedge pixel_clk_i);
        dvp_expect(32'h038, 32'h00000010);
        dvp_wr(32'h04c, 32'd1, 1'b0);
        repeat (100) @(negedge pixel_clk_i);
        dvp_wr(32'h038, 32'h3f, 1'b0);
        repeat (100) @(negedge pixel_clk_i);
        $display("PPALITE_P2_COVER invalid-crop-extent-rejected-before-arm");
      end
      13: begin
        configure_dvp(4, 2);
        configure_ppa(4, 2);
        dma_idle = 1'b0;
        ppa_wr(32'h014, 32'd1, 1'b1);
        ppa_expect(32'h014, 32'd0);
        dma_idle       = 1'b1;
        transport_idle = 1'b0;
        ppa_wr(32'h014, 32'd1, 1'b1);
        ppa_expect(32'h014, 32'd0);
        transport_idle = 1'b1;
        route_source_race();
        ppa_wr(32'h014, 32'd1, 1'b0);
        ppa_wr(32'h014, 32'd0, 1'b0);
        out_ready = 1'b0;
        dvp_wr(32'h000, 32'd3, 1'b0);
        expected_frame(4, 2, 1'b0);
        send_frame(4, 2, 1'b0);
        ppa_wr(32'h014, 32'd1, 1'b1);
        ppa_expect(32'h014, 32'd0);
        dvp_wr(32'h000, 32'd2, 1'b0);
        out_ready = 1'b1;
        repeat (100) @(negedge pixel_clk_i);
        ppa_wr(32'h014, 32'd1, 1'b0);
        ppa_wr(32'h018, 32'd1, 1'b0);
        transport_admitted = 1'b1;
        transport_idle     = 1'b0;
        dvp_wr(32'h000, 32'd3, 1'b0);
        expected_frame(4, 2, 1'b1);
        out_ready = 1'b0;
        send_frame(4, 2, 1'b0);
        ppa_wr(32'h014, 32'd0, 1'b1);
        ppa_expect(32'h014, 32'd1);
        out_ready = 1'b1;
        finish_frame(2);
        $display("PPALITE_P2_COVER full-route-barrier-no-side-effects");
      end
      14: begin
        configure_dvp(4, 2);
        configure_ppa(4, 2);
        pixel_run = 1'b0;
        dvp_wr(32'h000, 32'd3, 1'b0);
        dvp_wr(32'h04c, 32'd1, 1'b0);
        pixel_run = 1'b1;
        repeat (100) @(negedge pixel_clk_i);
        dvp_expect(32'h000, 32'd3);
        ppa_wr(32'h014, 32'd1, 1'b0);
        dvp_wr(32'h010, 32'd1, 1'b1);
        dvp_expect(32'h010, 32'd0);
        dvp_custom(32'h000, 32'd0, 1'b1, 4'b1000, 1'b1);
        dvp_expect(32'h000, 32'd3);
        dvp_wr(32'h038, 32'h3f, 1'b0);
        repeat (100) @(negedge pixel_clk_i);
        ppa_wr(32'h018, 32'd1, 1'b0);
        transport_admitted = 1'b1;
        transport_idle     = 1'b0;
        dvp_wr(32'h000, 32'd3, 1'b0);
        $display("PPALITE_P2_COVER cancelled-enable-reapply-requires-arm-and-dma");
      end
      15: begin
        configure_dvp(4, 2);
        configure_ppa(4, 2);
        ppa_wr(32'h014, 32'd1, 1'b0);
        @(negedge clk_i);
        dvp_paddr   = 32'h014;
        dvp_pwdata  = 32'd1;
        dvp_pstrb   = 4'hf;
        dvp_pwrite  = 1'b0;
        dvp_psel    = 1'b1;
        dvp_penable = 1'b0;
        ppa_paddr   = 32'h018;
        ppa_pwdata  = 32'd1;
        ppa_pstrb   = 4'hf;
        ppa_pwrite  = 1'b1;
        ppa_psel    = 1'b1;
        ppa_penable = 1'b0;
        @(negedge clk_i);
        dvp_penable = 1'b1;
        ppa_penable = 1'b1;
        @(negedge clk_i);
        if (!dvp_pready || !dvp_pslverr || !ppa_pready || ppa_pslverr) begin
          $fatal(1, "SIM_TEST_FAIL direction/strobe ARM race dvp=%b/%b ppa=%b/%b", dvp_pready,
                 dvp_pslverr, ppa_pready, ppa_pslverr);
        end
        dvp_psel    = 1'b0;
        dvp_penable = 1'b0;
        dvp_pwrite  = 1'b0;
        dvp_pstrb   = 4'd0;
        ppa_psel    = 1'b0;
        ppa_penable = 1'b0;
        ppa_pwrite  = 1'b0;
        ppa_pstrb   = 4'd0;
        repeat (100) @(negedge pixel_clk_i);
        dvp_expect(32'h014, 32'd0);
        dvp_custom(32'h000, 32'd3, 1'b0, 4'hf, 1'b1);
        dvp_expect(32'h000, 32'd2);
        dvp_custom(32'h010, 32'd1, 1'b1, 4'd0, 1'b1);
        dvp_expect(32'h010, 32'd0);
        $display("PPALITE_P2_COVER direction-strobe-mismatch-has-no-side-effects");
      end
      16: begin
        configure_dvp(4, 2);
        configure_ppa(4, 2);
        ppa_wr(32'h014, 32'd1, 1'b0);
        ppa_wr(32'h018, 32'd1, 1'b0);
        transport_admitted = 1'b1;
        transport_idle     = 1'b0;
        dvp_wr(32'h000, 32'd3, 1'b0);
        ppa_wr(32'h018, 32'd8, 1'b0);
        transport_idle  = 1'b1;
        stream_isolated = 1'b1;
        dvp_wr(32'h00c, 32'd0, 1'b1);
        dvp_expect(32'h00c, 32'd1);
        dvp_wr(32'h010, 32'd1, 1'b1);
        dvp_expect(32'h010, 32'd0);
        dvp_wr(32'h014, 32'd1, 1'b1);
        dvp_expect(32'h014, 32'd0);
        dvp_wr(32'h018, 32'h00030005, 1'b1);
        dvp_expect(32'h018, 32'h00020004);
        dvp_wr(32'h01c, 32'd1, 1'b1);
        dvp_expect(32'h01c, 32'd0);
        dvp_wr(32'h020, 32'h00010001, 1'b1);
        dvp_expect(32'h020, 32'h00020004);
        dvp_wr(32'h04c, 32'd1, 1'b0);
        repeat (100) @(negedge pixel_clk_i);
        dvp_wr(32'h000, 32'd2, 1'b0);
        dvp_wr(32'h04c, 32'd2, 1'b0);
        repeat (100) @(negedge pixel_clk_i);
        dvp_wr(32'h038, 32'h3f, 1'b0);
        repeat (100) @(negedge pixel_clk_i);
        ppa_wr(32'h018, 32'd16, 1'b0);
        ppa_status(`PPALITE_STATE_IDLE);
        $display("PPALITE_P2_COVER closing-isolation-rejects-source-configuration");
      end
      17: begin
        configure_dvp(4, 2);
        configure_ppa(4, 2);
        ppa_wr(32'h014, 32'd1, 1'b0);
        ppa_wr(32'h018, 32'd1, 1'b0);
        transport_admitted = 1'b1;
        transport_idle     = 1'b0;
        @(negedge clk_i);
        dvp_paddr   = 32'h000;
        dvp_pwdata  = 32'd3;
        dvp_pstrb   = 4'hf;
        dvp_pwrite  = 1'b1;
        dvp_psel    = 1'b1;
        dvp_penable = 1'b0;
        ppa_paddr   = 32'h018;
        ppa_pwdata  = 32'd8;
        ppa_pstrb   = 4'hf;
        ppa_pwrite  = 1'b1;
        ppa_psel    = 1'b1;
        ppa_penable = 1'b0;
        @(negedge clk_i);
        dvp_penable = 1'b1;
        ppa_penable = 1'b1;
        @(negedge clk_i);
        if (!dvp_pready || !dvp_pslverr || !ppa_pready || ppa_pslverr) begin
          $fatal(1, "SIM_TEST_FAIL ABORT/start priority dvp=%b/%b ppa=%b/%b", dvp_pready,
                 dvp_pslverr, ppa_pready, ppa_pslverr);
        end
        dvp_psel    = 1'b0;
        dvp_penable = 1'b0;
        dvp_pwrite  = 1'b0;
        dvp_pstrb   = 4'd0;
        ppa_psel    = 1'b0;
        ppa_penable = 1'b0;
        ppa_pwrite  = 1'b0;
        ppa_pstrb   = 4'd0;
        repeat (100) @(negedge pixel_clk_i);
        dvp_expect(32'h000, 32'd2);
        ppa_status(`PPALITE_STATE_CLOSING);
        transport_idle  = 1'b1;
        stream_isolated = 1'b1;
        dvp_wr(32'h04c, 32'd1, 1'b0);
        repeat (100) @(negedge pixel_clk_i);
        dvp_wr(32'h038, 32'h3f, 1'b0);
        repeat (100) @(negedge pixel_clk_i);
        ppa_wr(32'h018, 32'd16, 1'b0);
        ppa_status(`PPALITE_STATE_IDLE);
        $display("PPALITE_P2_COVER abort-beats-same-edge-source-start");
      end
      18: begin
        configure_dvp(4, 2);
        configure_ppa(4, 2);
        ppa_wr(32'h014, 32'd1, 1'b0);
        ppa_wr(32'h018, 32'd1, 1'b0);
        transport_admitted = 1'b1;
        transport_idle     = 1'b0;
        transport_err      = 8'd1;
        dvp_wr(32'h000, 32'd3, 1'b1);
        dvp_expect(32'h000, 32'd2);
        ppa_status(`PPALITE_STATE_CLOSING);
        transport_err = 8'd0;
        $display("PPALITE_P2_COVER transport-fault-beats-same-edge-source-start");
      end
      default: $fatal(1, "SIM_TEST_FAIL unknown PPALite route case=%0d", case_id);
    endcase
    $display("SIM_TEST_PASS PPALITE_P2 case=%0d", case_id);
    $finish;
  end
endmodule
