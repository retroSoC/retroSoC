// Opt-in P10 observations, excluded from mapped-netlist elaboration.
wire s_p10_camera = $test$plusargs("tiny_p10_camera");
wire s_p10_audio = $test$plusargs("tiny_p10_audio");
wire s_p10_enabled = s_p10_camera ? u_dut.u_soc.s_perf_enable : (s_p10_audio && s_p6_audio_enabled);
wire [2:0] s_p10_ar, s_p10_r, s_p10_aw, s_p10_b, s_p10_error;
wire [2:0][7:0] s_p10_read_bytes, s_p10_write_bytes;
wire  [2:0][4:0] s_p10_stalled;
wire  [3:0]      s_p10_bank_issues;
logic [5:0]      s_p10_targets;
always_comb begin
  s_p10_targets = 0;
  for (integer target_index = 0; target_index < `RETROSOC_TINY__TARGET_COUNT; target_index++)
  if (!u_dut.u_soc.u_fabric.target_idle_o[target_index]) s_p10_targets++;
end
for (genvar owner = 0; owner < 3; owner++) begin : gen_p10_bus
  `define _P10_AXI u_dut.u_soc.u_masters_axi4_if[owner]
  logic [2:0] s_read_size = 0;
  always @(posedge u_dut.u_soc.s_exec_clk)
    if (`_P10_AXI.arvalid && `_P10_AXI.arready)
      s_read_size <= `_P10_AXI.arsize;
  assign s_p10_ar[owner] = `_P10_AXI.arvalid && `_P10_AXI.arready;
  assign s_p10_r[owner] = `_P10_AXI.rvalid && `_P10_AXI.rready && `_P10_AXI.rlast;
  assign s_p10_aw[owner] = `_P10_AXI.awvalid && `_P10_AXI.awready;
  assign s_p10_b[owner] = `_P10_AXI.bvalid && `_P10_AXI.bready;
  assign s_p10_error[owner] = (`_P10_AXI.rvalid && `_P10_AXI.rready && `_P10_AXI.rresp != 0) ||
      (s_p10_b[owner] && `_P10_AXI.bresp != 0);
  assign s_p10_read_bytes[owner] = (`_P10_AXI.rvalid && `_P10_AXI.rready && `_P10_AXI.rresp == 0)
      ? (8'd1 << s_read_size) : 8'd0;
  assign s_p10_write_bytes[owner] = (`_P10_AXI.wvalid && `_P10_AXI.wready) ?
      8'(`_P10_AXI.wstrb[0]) + 8'(`_P10_AXI.wstrb[1]) +
      8'(`_P10_AXI.wstrb[2]) + 8'(`_P10_AXI.wstrb[3]) : 8'd0;
  assign s_p10_stalled[owner] = {
    `_P10_AXI.bvalid && !`_P10_AXI.bready,
    `_P10_AXI.wvalid && !`_P10_AXI.wready,
    `_P10_AXI.awvalid && !`_P10_AXI.awready,
    `_P10_AXI.rvalid && !`_P10_AXI.rready,
    `_P10_AXI.arvalid && !`_P10_AXI.arready
  };
  `undef _P10_AXI
end
for (genvar bank = 0; bank < 4; bank++) begin : gen_p10_bank
  assign s_p10_bank_issues[bank] = u_dut.u_soc.u_sram.gen_group[bank].u_group.s_issue;
end
tiny_p10_observer u_p10_observer (
    .clk_i             (u_dut.u_soc.s_exec_clk),
    .rst_n_i           (u_dut.u_soc.s_fabric_rst_n && (s_p10_camera || s_p10_audio)),
    .enable_i          (s_p10_enabled),
    .read_accept_i     (s_p10_ar),
    .read_done_i       (s_p10_r),
    .write_accept_i    (s_p10_aw),
    .write_done_i      (s_p10_b),
    .error_i           (s_p10_error),
    .read_bytes_i      (s_p10_read_bytes),
    .write_bytes_i     (s_p10_write_bytes),
    .stalled_i         (s_p10_stalled),
    .active_targets_i  (s_p10_targets),
    .bank_issues_i     (s_p10_bank_issues),
    .dma_beat_overlap_i((s_p10_read_bytes[1] != 0) && (s_p10_write_bytes[1] != 0))
);
