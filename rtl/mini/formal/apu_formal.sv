// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "axi4_define.svh"

module apu_formal_design (
    // verilog_format: off -- expose the bounded DMA scenario and AXI observations
    input  logic        clk_i,
    output logic        rst_n_i,
    output logic        f_past_valid,
    output logic [2:0]  scenario,
    output logic [5:0]  cycle,
    output logic        busy,
    output logic        done,
    output logic        error,
    output logic        aborted,
    output logic [5:0]  error_code,
    output logic [63:0] read_bytes,
    output logic [63:0] write_bytes,
    output logic        terminal_seen,
    output logic        terminal_error,
    output logic        terminal_aborted,
    output logic [5:0]  terminal_code,
    output logic        awvalid,
    output logic        awready,
    output logic [31:0] awaddr,
    output logic [7:0]  awlen,
    output logic [2:0]  awsize,
    output logic [1:0]  awburst,
    output logic [3:0]  awcache,
    output logic [2:0]  awprot,
    output logic        wvalid,
    output logic        wready,
    output logic [3:0]  wstrb,
    output logic        wlast,
    output logic        bvalid,
    output logic        bready,
    output logic        arvalid,
    output logic        arready,
    output logic [31:0] araddr,
    output logic [7:0]  arlen,
    output logic [2:0]  arsize,
    output logic [1:0]  arburst,
    output logic [3:0]  arcache,
    output logic [2:0]  arprot,
    output logic        rvalid,
    output logic        rready,
    output logic        rlast
    // verilog_format: on
);
  (* anyconst *)logic [ 2:0] f_scenario;
  (* anyconst *)logic [31:0] f_read_data;
  logic [ 5:0] s_cycle_q;
  logic        s_read_active_q;
  logic        s_write_active_q;
  logic        s_write_response_q;
  logic        s_terminal_seen_q;
  logic        s_terminal_error_q;
  logic        s_terminal_aborted_q;
  logic [ 5:0] s_terminal_code_q;
  logic        s_request_write;
  logic        s_abort;
  logic [ 1:0] s_source_beat_q;
  logic s_done, s_error, s_aborted;
  logic [ 5:0] s_error_code;
  logic [ 3:0] s_error_stage;
  logic [ 1:0] s_error_resp;
  logic [31:0] s_error_addr;
  logic [63:0] s_read_bytes, s_write_bytes;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) read_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) write_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  assign s_request_write = f_scenario == 2'd1;
  assign s_abort = (f_scenario == 2'd3) && (s_cycle_q == 6'd4);
  assign read_axis.tready = 1'b1;
  assign write_axis.tdata = 32'hcafe_0000 | {30'd0, s_source_beat_q};
  assign write_axis.tkeep = 4'hf;
  assign write_axis.tstrb = 4'hf;
  assign write_axis.tlast = s_source_beat_q == 2'd1;
  assign write_axis.tid = '0;
  assign write_axis.tdest = '0;
  assign write_axis.tuser = '0;
  assign write_axis.tvalid = f_scenario == 2'd1;

  assign axi4.arready = !s_read_active_q &&
      ((f_scenario == 3'd0) || (f_scenario == 3'd4) || (f_scenario == 3'd5) ||
       ((f_scenario == 3'd2) && (s_cycle_q >= 6'd12)) ||
       ((f_scenario == 3'd3) && (s_cycle_q >= 6'd7)));
  assign axi4.rid = 1'b0;
  assign axi4.rdata = f_read_data;
  assign axi4.rresp = `AXI4_RESP_OKAY;
  assign axi4.rlast = f_scenario != 3'd5;
  assign axi4.ruser = 1'b0;
  assign axi4.rvalid = s_read_active_q;
  assign axi4.awready = (f_scenario == 2'd1) && !s_write_active_q && !s_write_response_q;
  assign axi4.wready = s_write_active_q;
  assign axi4.bid = 1'b0;
  assign axi4.bresp = `AXI4_RESP_OKAY;
  assign axi4.buser = 1'b0;
  assign axi4.bvalid = s_write_response_q;

  apu_dma u_dut (
      .clk_i,
      .rst_n_i,
      .abort_i(s_abort),
      .quiesce_i(1'b0),
      .bridge_epoch_i((f_scenario == 3'd4) ? 8'd1 : 8'd0),
      .perf_enable_i(1'b1),
      .counter_clear_i(1'b0),
      .request_valid_i (rst_n_i &&
                        ((s_cycle_q == 6'd0) ||
                         ((f_scenario == 3'd4) && (s_cycle_q < 6'd3)))),
      .request_ready_o(),
      .request_write_i(s_request_write),
      .request_addr_i(32'h0000_0ffc),
      .request_bytes_i(32'd8),
      .read_base_i(32'd0),
      .read_limit_i(32'h0000_ffff),
      .write_base_i(32'd0),
      .write_limit_i(32'h0000_ffff),
      .timeout_i(32'd8),
      .read_axis,
      .write_axis,
      .busy_o(busy),
      .done_o(s_done),
      .error_o(s_error),
      .aborted_o(s_aborted),
      .aborting_o(),
      .error_code_o(s_error_code),
      .error_stage_o(s_error_stage),
      .error_resp_o(s_error_resp),
      .error_addr_o(s_error_addr),
      .input_pending_o(),
      .output_pending_o(),
      .read_bytes_o(s_read_bytes),
      .write_bytes_o(s_write_bytes),
      .write_burst_done_o(),
      .write_burst_bytes_o(),
      .read_stalls_o(),
      .write_stalls_o(),
      .axi4
  );

  assign scenario         = f_scenario;
  assign cycle            = s_cycle_q;
  assign done             = s_done;
  assign error            = s_error;
  assign aborted          = s_aborted;
  assign error_code       = s_error_code;
  assign read_bytes       = s_read_bytes;
  assign write_bytes      = s_write_bytes;
  assign terminal_seen    = s_terminal_seen_q;
  assign terminal_error   = s_terminal_error_q;
  assign terminal_aborted = s_terminal_aborted_q;
  assign terminal_code    = s_terminal_code_q;
  assign awvalid          = axi4.awvalid;
  assign awready          = axi4.awready;
  assign awaddr           = axi4.awaddr;
  assign awlen            = axi4.awlen;
  assign awsize           = axi4.awsize;
  assign awburst          = axi4.awburst;
  assign awcache          = axi4.awcache;
  assign awprot           = axi4.awprot;
  assign wvalid           = axi4.wvalid;
  assign wready           = axi4.wready;
  assign wstrb            = axi4.wstrb;
  assign wlast            = axi4.wlast;
  assign bvalid           = axi4.bvalid;
  assign bready           = axi4.bready;
  assign arvalid          = axi4.arvalid;
  assign arready          = axi4.arready;
  assign araddr           = axi4.araddr;
  assign arlen            = axi4.arlen;
  assign arsize           = axi4.arsize;
  assign arburst          = axi4.arburst;
  assign arcache          = axi4.arcache;
  assign arprot           = axi4.arprot;
  assign rvalid           = axi4.rvalid;
  assign rready           = axi4.rready;
  assign rlast            = axi4.rlast;

  initial begin
    rst_n_i      = 1'b0;
    f_past_valid = 1'b0;
  end

  always_ff @(posedge clk_i) begin
    rst_n_i      <= 1'b1;
    f_past_valid <= 1'b1;
    if (!rst_n_i) begin
      s_cycle_q            <= 6'd0;
      s_terminal_seen_q    <= 1'b0;
      s_terminal_error_q   <= 1'b0;
      s_terminal_aborted_q <= 1'b0;
      s_terminal_code_q    <= 6'd0;
    end else begin
      if (s_cycle_q != 6'h3f) s_cycle_q <= s_cycle_q + 1'b1;
      if (s_done) begin
        s_terminal_seen_q    <= 1'b1;
        s_terminal_error_q   <= s_error;
        s_terminal_aborted_q <= s_aborted;
        s_terminal_code_q    <= s_error_code;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_read_active_q    <= 1'b0;
      s_write_active_q   <= 1'b0;
      s_write_response_q <= 1'b0;
      s_source_beat_q    <= 2'd0;
    end else begin
      if (axi4.arvalid && axi4.arready) s_read_active_q <= 1'b1;
      if (axi4.rvalid && axi4.rready) s_read_active_q <= 1'b0;
      if (axi4.awvalid && axi4.awready) s_write_active_q <= 1'b1;
      if (axi4.wvalid && axi4.wready) begin
        s_source_beat_q <= s_source_beat_q + 1'b1;
        if (axi4.wlast) begin
          s_write_active_q   <= 1'b0;
          s_write_response_q <= 1'b1;
        end
      end
      if (axi4.bvalid && axi4.bready) s_write_response_q <= 1'b0;
    end
  end

  logic s_unused_result;
  assign s_unused_result = ^s_error_stage ^ ^s_error_resp ^ ^s_error_addr;
endmodule
