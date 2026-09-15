`ifdef GA2D_FORMAL_DESIGN
// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module ga2d_formal_design (
    // verilog_format: off -- AXI observations are grouped by channel.
    input  logic        clk_i,
    output logic        rst_n_i,
    output logic        f_past_valid,
    output logic [3:0]  scenario,
    output logic        start_i,
    output logic        resource_stop_i,
    output logic        bridge_clear_busy_i,
    output logic [7:0]  bridge_epoch_i,
    output logic        busy,
    output logic        draining,
    output logic        done,
    output logic        aborted,
    output logic        error,
    output logic        recovery_required,
    output logic        safe_idle,
    output logic [2:0]  irq_event,
    output logic        error_valid,
    output logic [6:0]  error_code,
    output logic [3:0]  error_stage,
    output logic [1:0]  error_axi_response,
    output logic [31:0] error_address,
    output logic [63:0] read_bytes,
    output logic [63:0] write_bytes,
    output logic [15:0] lines_done,
    output logic [5:0]  foreground_fifo_count,
    output logic [5:0]  background_fifo_count,
    output logic [5:0]  output_fifo_count,
    output logic        read_reserved,
    output logic        read_owner,
    output logic        next_read_owner,
    output logic        inplace_background,
    output logic [31:0] bg_captured_pixels,
    output logic [32:0] write_cover_end_pixel,
    output logic        awvalid,
    output logic        awready,
    output logic [2:0]  awid,
    output logic [31:0] awaddr,
    output logic [7:0]  awlen,
    output logic [2:0]  awsize,
    output logic [1:0]  awburst,
    output logic        awlock,
    output logic [3:0]  awcache,
    output logic [2:0]  awprot,
    output logic [3:0]  awqos,
    output logic [3:0]  awregion,
    output logic        awuser,
    output logic        wvalid,
    output logic        wready,
    output logic [63:0] wdata,
    output logic [7:0]  wstrb,
    output logic        wlast,
    output logic        wuser,
    output logic        bvalid,
    output logic        bready,
    output logic [2:0]  bid,
    output logic [1:0]  bresp,
    output logic        buser,
    output logic        arvalid,
    output logic        arready,
    output logic [2:0]  arid,
    output logic [31:0] araddr,
    output logic [7:0]  arlen,
    output logic [2:0]  arsize,
    output logic [1:0]  arburst,
    output logic        arlock,
    output logic [3:0]  arcache,
    output logic [2:0]  arprot,
    output logic [3:0]  arqos,
    output logic [3:0]  arregion,
    output logic        aruser,
    output logic        rvalid,
    output logic        rready,
    output logic [2:0]  rid,
    output logic [63:0] rdata,
    output logic [1:0]  rresp,
    output logic        rlast,
    output logic        ruser,
    output logic        protocol_residual_rvalid
    // verilog_format: on
);
  // Properties are parsed separately from design.v, where this Yosys frontend
  // cannot import ga2d_pkg; preserve the packed production port layout here.
  typedef struct packed {
    logic [31:0] timeout_cycles;
    logic [31:0] job_config;
    logic [31:0] global_alpha;
    logic [31:0] color;
    logic [31:0] size;
    logic [31:0] fg_address;
    logic [31:0] fg_pitch;
    logic [31:0] fg_format;
    logic [31:0] bg_address;
    logic [31:0] bg_pitch;
    logic [31:0] bg_format;
    logic [31:0] dst_address;
    logic [31:0] dst_pitch;
    logic [31:0] dst_format;
  } formal_ga2d_config_t;

  localparam logic [31:0] FormalSramBase = 32'h3000_0000;
  localparam logic [1:0] OperationFill = 2'd0;
  localparam logic [1:0] OperationCopy = 2'd1;
  localparam logic [1:0] OperationBlend = 2'd3;
  localparam logic [2:0] FormatRgb565 = 3'd0;
  localparam logic [2:0] FormatA8 = 3'd4;
  localparam logic [1:0] AxiRespOkay = 2'b00;
  localparam logic [1:0] AxiRespSlverr = 2'b10;

  (* anyconst *)logic                [3:0] f_scenario;
  logic                [7:0] s_cycle_q;
  logic                      s_stop_after_aw_q;
  logic                      s_ar_stalled_q;
  logic                      s_aw_stalled_q;
  logic                      s_w_stalled_q;
  logic                      s_read_active_q;
  logic                [8:0] s_read_beats_q;
  logic                      s_bad_read_sent_q;
  logic                      s_residual_r_pending_q;
  logic                      s_residual_r_valid_q;
  logic                [1:0] s_residual_r_delay_q;
  logic                      s_write_active_q;
  logic                [8:0] s_write_beats_q;
  logic                      s_bvalid_q;
  logic                [1:0] s_bresp_q;
  formal_ga2d_config_t       s_config;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  assign scenario            = f_scenario;
  assign start_i             = rst_n_i && (s_cycle_q == 8'd0);
  assign resource_stop_i     = (f_scenario == 4'd3) && s_stop_after_aw_q;
  assign bridge_clear_busy_i = (f_scenario == 4'd4) && (s_cycle_q == 8'd4);
  assign bridge_epoch_i      = ((f_scenario == 4'd4) && (s_cycle_q >= 8'd5)) ? 8'd1 : 8'd0;

  always_comb begin
    s_config                = '0;
    s_config.timeout_cycles = 32'd64;
    s_config.job_config     = {30'd0, OperationFill};
    s_config.color          = 32'h7a12_3456;
    s_config.size           = {16'd1, 16'd1};
    s_config.dst_address    = FormalSramBase + 32'h40;
    s_config.dst_pitch      = 32'd2;
    s_config.dst_format     = {29'd0, FormatRgb565};
    if (f_scenario == 4'd2) begin
      s_config.size      = {16'd1, 16'd60};
      s_config.dst_pitch = 32'd120;
    end
    if (f_scenario == 4'd7) begin
      s_config.size      = {16'd1, 16'd64};
      s_config.dst_pitch = 32'd128;
    end
    if ((f_scenario == 4'd1) || (f_scenario == 4'd6) || (f_scenario == 4'd8)) begin
      s_config.job_config = {30'd0, OperationCopy};
      s_config.fg_address = FormalSramBase + 32'h20;
      s_config.fg_pitch   = 32'd2;
      s_config.fg_format  = {29'd0, FormatRgb565};
    end
    if ((f_scenario == 4'd9) || (f_scenario == 4'd10)) begin
      s_config.job_config  = {30'd0, OperationBlend};
      s_config.fg_address  = FormalSramBase + 32'h20;
      s_config.fg_pitch    = 32'd1;
      s_config.fg_format   = {29'd0, FormatA8};
      s_config.bg_address  = FormalSramBase + 32'h40;
      s_config.bg_pitch    = 32'd2;
      s_config.bg_format   = {29'd0, FormatRgb565};
      s_config.dst_address = FormalSramBase + 32'h60;
      s_config.dst_pitch   = 32'd2;
      s_config.dst_format  = {29'd0, FormatRgb565};
      if (f_scenario == 4'd10) begin
        s_config.dst_address = FormalSramBase + 32'h40;
      end
    end
  end

  assign axi4.arready = !s_read_active_q && !s_residual_r_pending_q &&
                        !s_residual_r_valid_q && (!axi4.arvalid || s_ar_stalled_q);
  assign axi4.rid = ((f_scenario == 4'd8) && s_read_active_q && !s_bad_read_sent_q) ? 3'd1 : 3'd0;
  assign axi4.rdata = 64'h8877_6655_4433_2211;
  assign axi4.rresp = (f_scenario == 4'd6) ? AxiRespSlverr : AxiRespOkay;
  assign axi4.rlast = s_residual_r_valid_q || (s_read_active_q && (s_read_beats_q == 9'd1));
  assign axi4.ruser = 1'b0;
  assign axi4.rvalid = s_read_active_q || s_residual_r_valid_q;
  assign axi4.awready = !s_write_active_q && !s_bvalid_q && (!axi4.awvalid || s_aw_stalled_q);
  assign axi4.wready = s_write_active_q && !s_bvalid_q && (!axi4.wvalid || s_w_stalled_q);
  assign axi4.bid = 3'd0;
  assign axi4.bresp = s_bresp_q;
  assign axi4.buser = 1'b0;
  assign axi4.bvalid = s_bvalid_q;

  assign busy = u_dut.busy_o;
  assign draining = u_dut.draining_o;
  assign done = u_dut.done_o;
  assign aborted = u_dut.aborted_o;
  assign error = u_dut.error_o;
  assign recovery_required = u_dut.recovery_required_o;
  assign safe_idle = u_dut.safe_idle_o;
  assign irq_event = u_dut.irq_event_o;
  assign error_valid = u_dut.error_valid_o;
  assign error_code = u_dut.error_code_o;
  assign error_stage = u_dut.error_stage_o;
  assign error_axi_response = u_dut.error_axi_response_o;
  assign error_address = u_dut.error_address_o;
  assign read_bytes = u_dut.read_bytes_o;
  assign write_bytes = u_dut.write_bytes_o;
  assign lines_done = u_dut.lines_done_o;
  assign foreground_fifo_count = u_dut.u_dma.unused_fg_fifo_count;
  assign background_fifo_count = u_dut.u_dma.unused_bg_fifo_count;
  assign output_fifo_count = u_dut.u_dma.unused_output_fifo_count;
  assign read_reserved = u_dut.u_dma.s_read_reserved_q;
  assign read_owner = u_dut.u_dma.s_read_owner_q;
  assign next_read_owner = u_dut.u_dma.s_next_read_owner_q;
  assign inplace_background = u_dut.u_dma.s_inplace_background_q;
  assign bg_captured_pixels = u_dut.u_dma.s_bg_captured_pixels_q;
  assign write_cover_end_pixel = u_dut.u_dma.s_write_cover_end_pixel;
  assign awvalid = axi4.awvalid;
  assign awready = axi4.awready;
  assign awid = axi4.awid;
  assign awaddr = axi4.awaddr;
  assign awlen = axi4.awlen;
  assign awsize = axi4.awsize;
  assign awburst = axi4.awburst;
  assign awlock = axi4.awlock;
  assign awcache = axi4.awcache;
  assign awprot = axi4.awprot;
  assign awqos = axi4.awqos;
  assign awregion = axi4.awregion;
  assign awuser = axi4.awuser;
  assign wvalid = axi4.wvalid;
  assign wready = axi4.wready;
  assign wdata = axi4.wdata;
  assign wstrb = axi4.wstrb;
  assign wlast = axi4.wlast;
  assign wuser = axi4.wuser;
  assign bvalid = axi4.bvalid;
  assign bready = axi4.bready;
  assign bid = axi4.bid;
  assign bresp = axi4.bresp;
  assign buser = axi4.buser;
  assign arvalid = axi4.arvalid;
  assign arready = axi4.arready;
  assign arid = axi4.arid;
  assign araddr = axi4.araddr;
  assign arlen = axi4.arlen;
  assign arsize = axi4.arsize;
  assign arburst = axi4.arburst;
  assign arlock = axi4.arlock;
  assign arcache = axi4.arcache;
  assign arprot = axi4.arprot;
  assign arqos = axi4.arqos;
  assign arregion = axi4.arregion;
  assign aruser = axi4.aruser;
  assign rvalid = axi4.rvalid;
  assign rready = axi4.rready;
  assign rid = axi4.rid;
  assign rdata = axi4.rdata;
  assign rresp = axi4.rresp;
  assign rlast = axi4.rlast;
  assign ruser = axi4.ruser;
  assign protocol_residual_rvalid = s_residual_r_valid_q;

  ga2d_core u_dut (
      .clk_i               (clk_i),
      .rst_n_i             (rst_n_i),
      .start_i             (start_i),
      .abort_i             (1'b0),
      .soft_reset_i        (1'b0),
      .resource_stop_i     (resource_stop_i),
      .bridge_clear_busy_i (bridge_clear_busy_i),
      .bridge_epoch_i      (bridge_epoch_i),
      .data_ready_i        (1'b1),
      .mem_pad_mode_i      (2'd0),
      .config_i            (s_config),
      .busy_o              (),
      .draining_o          (),
      .done_o              (),
      .aborted_o           (),
      .error_o             (),
      .recovery_required_o (),
      .safe_idle_o         (),
      .irq_event_o         (),
      .error_valid_o       (),
      .error_code_o        (),
      .error_stage_o       (),
      .error_axi_response_o(),
      .error_address_o     (),
      .cycles_o            (),
      .read_bytes_o        (),
      .write_bytes_o       (),
      .read_stalls_o       (),
      .write_stalls_o      (),
      .pipe_stalls_o       (),
      .lines_done_o        (),
      .axi4                (axi4)
  );

  initial begin
    rst_n_i      = 1'b0;
    f_past_valid = 1'b0;
  end

  always_ff @(posedge clk_i) begin
    rst_n_i      <= 1'b1;
    f_past_valid <= 1'b1;
    if (!rst_n_i) begin
      s_cycle_q              <= '0;
      s_stop_after_aw_q      <= 1'b0;
      s_ar_stalled_q         <= 1'b0;
      s_aw_stalled_q         <= 1'b0;
      s_w_stalled_q          <= 1'b0;
      s_read_active_q        <= 1'b0;
      s_read_beats_q         <= '0;
      s_bad_read_sent_q      <= 1'b0;
      s_residual_r_pending_q <= 1'b0;
      s_residual_r_valid_q   <= 1'b0;
      s_residual_r_delay_q   <= '0;
      s_write_active_q       <= 1'b0;
      s_write_beats_q        <= '0;
      s_bvalid_q             <= 1'b0;
      s_bresp_q              <= AxiRespOkay;
    end else begin
      s_cycle_q <= s_cycle_q + 1'b1;
      if (axi4.awvalid && !axi4.awready) begin
        s_aw_stalled_q <= 1'b1;
        if (f_scenario == 4'd3) begin
          s_stop_after_aw_q <= 1'b1;
        end
      end
      if (axi4.wvalid && !axi4.wready) begin
        s_w_stalled_q <= 1'b1;
      end
      if (axi4.arvalid && !axi4.arready) begin
        s_ar_stalled_q <= 1'b1;
      end

      if (bridge_clear_busy_i) begin
        s_read_active_q        <= 1'b0;
        s_read_beats_q         <= '0;
        s_bad_read_sent_q      <= 1'b0;
        s_residual_r_pending_q <= 1'b0;
        s_residual_r_valid_q   <= 1'b0;
        s_residual_r_delay_q   <= '0;
        s_write_active_q       <= 1'b0;
        s_write_beats_q        <= '0;
        s_bvalid_q             <= 1'b0;
      end else begin
        if (axi4.arvalid && axi4.arready) begin
          s_read_active_q <= 1'b1;
          s_read_beats_q  <= {1'b0, axi4.arlen} + 1'b1;
        end
        if (s_read_active_q && axi4.rvalid && axi4.rready) begin
          if ((f_scenario == 4'd8) && !s_bad_read_sent_q) begin
            s_read_active_q        <= 1'b0;
            s_read_beats_q         <= '0;
            s_bad_read_sent_q      <= 1'b1;
            s_residual_r_pending_q <= 1'b1;
            s_residual_r_delay_q   <= 2'd2;
          end else if (s_read_beats_q == 9'd1) begin
            s_read_active_q <= 1'b0;
            s_read_beats_q  <= '0;
          end else begin
            s_read_beats_q <= s_read_beats_q - 1'b1;
          end
        end
        if (s_residual_r_pending_q) begin
          if (s_residual_r_delay_q == 2'd0) begin
            s_residual_r_pending_q <= 1'b0;
            s_residual_r_valid_q   <= 1'b1;
          end else begin
            s_residual_r_delay_q <= s_residual_r_delay_q - 1'b1;
          end
        end
        if (s_residual_r_valid_q && axi4.rready) begin
          s_residual_r_valid_q <= 1'b0;
        end

        if (axi4.awvalid && axi4.awready) begin
          s_write_active_q <= 1'b1;
          s_write_beats_q  <= {1'b0, axi4.awlen} + 1'b1;
        end
        if (s_write_active_q && axi4.wvalid && axi4.wready) begin
          if (s_write_beats_q == 9'd1) begin
            s_write_active_q <= 1'b0;
            s_write_beats_q  <= '0;
            s_bvalid_q       <= 1'b1;
            s_bresp_q        <= (f_scenario == 4'd5) ? AxiRespSlverr : AxiRespOkay;
          end else begin
            s_write_beats_q <= s_write_beats_q - 1'b1;
          end
        end
        if (s_bvalid_q && axi4.bready) begin
          s_bvalid_q <= 1'b0;
        end
      end
    end
  end
endmodule
`endif
