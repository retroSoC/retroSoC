logic clk_i = 1'b0;
always #5 clk_i = ~clk_i;
logic            rst_n_i = 1'b0;
logic   [  31:0] clock_hz_i = 32'd24000000;
logic   [  31:0] user_select_i = 32'hffff_ffff;
logic   [  31:0] user_status_i = 32'hffff_ffff;
logic   [  31:0] filter_enable_i = 32'd0;
logic            gpio_ready_i = 1'b1;
logic   [  31:0] gpio_input_i = 32'd0;
logic   [  31:0] gpio_value_o;
logic   [  31:0] gpio_oe_o;
logic            dma_tx_job_i = 1'b0;
logic            dma_rx_job_i = 1'b0;
logic            dma_tx_ready_o;
logic            dma_rx_valid_o;
logic   [  31:0] dma_rx_data_o;
logic   [   3:0] dma_rx_keep_o;
logic   [   3:0] dma_rx_strb_o;
logic            dma_rx_last_o;
logic            dma_rx_id_o;
logic            dma_rx_dest_o;
logic            dma_rx_user_o;
logic            dma_tx_admit_o;
logic            dma_rx_admit_o;
logic            irq_o;
logic            dma_tx_valid;
logic   [  31:0] dma_tx_data;
logic   [   3:0] dma_tx_keep;
logic   [   3:0] dma_tx_strb;
logic            dma_tx_id;
logic            dma_tx_dest;
logic            dma_tx_user;
logic            dma_tx_last;
logic            dma_rx_ready;
logic   [  31:0] pin_cycles;
logic   [  31:0] pin_transitions;
logic   [  31:0] stream_tx_count;
logic   [  31:0] stream_rx_count;
logic   [  31:0] value;
logic   [  31:0] expected;
logic   [  31:0] vector_mem                    [0:4095];
logic   [  31:0] saved_phase;
integer          vector_count;
integer          record_base;
integer          vector_steps;
reg     [4095:0] vector_path;

apb4_if u_apb (
    .pclk   (clk_i),
    .presetn(rst_n_i)
);
`ifndef PIOLITE_DUT
`define PIOLITE_DUT apb4_piolite
`endif
`PIOLITE_DUT u_dut (
    .clk_i          (clk_i),
    .rst_n_i        (rst_n_i),
    .clock_hz_i     (clock_hz_i),
    .user_select_i  (user_select_i),
    .user_status_i  (user_status_i),
    .filter_enable_i(filter_enable_i),
    .gpio_ready_i   (gpio_ready_i),
    .gpio_input_i   (gpio_input_i),
    .gpio_value_o   (gpio_value_o),
    .gpio_oe_o      (gpio_oe_o),
    .dma_tx_job_i   (dma_tx_job_i),
    .dma_rx_job_i   (dma_rx_job_i),
    .dma_tx_valid_i (dma_tx_valid),
    .dma_tx_ready_o (dma_tx_ready_o),
    .dma_tx_data_i  (dma_tx_data),
    .dma_tx_keep_i  (dma_tx_keep),
    .dma_tx_strb_i  (dma_tx_strb),
    .dma_tx_id_i    (dma_tx_id),
    .dma_tx_dest_i  (dma_tx_dest),
    .dma_tx_user_i  (dma_tx_user),
    .dma_tx_last_i  (dma_tx_last),
    .dma_rx_valid_o (dma_rx_valid_o),
    .dma_rx_ready_i (dma_rx_ready),
    .dma_rx_data_o  (dma_rx_data_o),
    .dma_rx_keep_o  (dma_rx_keep_o),
    .dma_rx_strb_o  (dma_rx_strb_o),
    .dma_rx_last_o  (dma_rx_last_o),
    .dma_rx_id_o    (dma_rx_id_o),
    .dma_rx_dest_o  (dma_rx_dest_o),
    .dma_rx_user_o  (dma_rx_user_o),
    .dma_tx_admit_o (dma_tx_admit_o),
    .dma_rx_admit_o (dma_rx_admit_o),
    .irq_o          (irq_o),
`ifdef PIOLITE_SCALAR_APB
    .paddr_i        (u_apb.paddr),
    .pprot_i        (u_apb.pprot),
    .psel_i         (u_apb.psel),
    .penable_i      (u_apb.penable),
    .pwrite_i       (u_apb.pwrite),
    .pwdata_i       (u_apb.pwdata),
    .pstrb_i        (u_apb.pstrb),
    .pready_o       (u_apb.pready),
    .prdata_o       (u_apb.prdata),
    .pslverr_o      (u_apb.pslverr)
`else
    .apb4           (u_apb)
`endif
);

piolite_pin_bfm u_pin_bfm (
    .clk_i             (clk_i),
    .rst_n_i           (rst_n_i),
    .value_i           (gpio_value_o),
    .oe_i              (gpio_oe_o),
    .cycle_count_o     (pin_cycles),
    .transition_count_o(pin_transitions)
);

piolite_stream_bfm u_stream_bfm (
    .clk_i              (clk_i),
    .rst_n_i            (rst_n_i),
    .tx_valid_o         (dma_tx_valid),
    .tx_ready_i         (dma_tx_ready_o),
    .tx_data_o          (dma_tx_data),
    .tx_keep_o          (dma_tx_keep),
    .tx_strb_o          (dma_tx_strb),
    .tx_id_o            (dma_tx_id),
    .tx_dest_o          (dma_tx_dest),
    .tx_user_o          (dma_tx_user),
    .tx_last_o          (dma_tx_last),
    .rx_valid_i         (dma_rx_valid_o),
    .rx_ready_o         (dma_rx_ready),
    .rx_data_i          (dma_rx_data_o),
    .rx_keep_i          (dma_rx_keep_o),
    .rx_strb_i          (dma_rx_strb_o),
    .rx_last_i          (dma_rx_last_o),
    .rx_id_i            (dma_rx_id_o),
    .rx_dest_i          (dma_rx_dest_o),
    .rx_user_i          (dma_rx_user_o),
    .tx_accepted_count_o(stream_tx_count),
    .rx_accepted_count_o(stream_rx_count)
);

always @(posedge clk_i) begin
  if (rst_n_i && ((gpio_oe_o & ~(user_select_i & user_status_i & ~filter_enable_i)) != 0))
    $fatal(1, "PIOLITE output authorization clamp failed: %h", gpio_oe_o);
  if (rst_n_i && !gpio_ready_i && (gpio_oe_o != 0)) $fatal(1, "PIOLITE readiness clamp failed");
end

task automatic access (input logic write_access, input logic [11:0] offset, input logic [31:0] data,
                       input logic [3:0] strobe, input logic error_expected,
                       output logic [31:0] result_data);
  @(negedge clk_i);
  u_apb.psel    = 1'b1;
  u_apb.penable = 1'b0;
  u_apb.pwrite  = write_access;
  u_apb.paddr   = {20'd0, offset};
  u_apb.pwdata  = data;
  u_apb.pstrb   = strobe;
  u_apb.pprot   = 3'd0;
  @(negedge clk_i);
  u_apb.penable = 1'b1;
  for (integer timeout_cycles = 0; !u_apb.pready; timeout_cycles++) begin
    if (timeout_cycles == 3) $fatal(1, "PIOLITE APB response exceeded bound");
    @(negedge clk_i);
  end
  if (u_apb.pslverr !== error_expected)
    $fatal(1, "PIOLITE APB offset=%h error=%b expected=%b", offset, u_apb.pslverr, error_expected);
  result_data = u_apb.prdata;
  @(posedge clk_i);
  @(negedge clk_i);
  u_apb.psel    = 1'b0;
  u_apb.penable = 1'b0;
  @(negedge clk_i);
endtask

task automatic wr(input logic [11:0] offset, input logic [31:0] data, input logic err);
  logic [31:0] unused_data;
  access (1'b1, offset, data, 4'hf, err, unused_data);
endtask

task automatic rd(input logic [11:0] offset, output logic [31:0] data);
  access (1'b0, offset, 32'd0, 4'd0, 1'b0, data);
endtask

task automatic check_reg(input logic [11:0] offset, input logic [31:0] expected_data);
  logic [31:0] observed;
  rd(offset, observed);
  if (observed !== expected_data)
    $fatal(1, "PIOLITE register %h got=%h expected=%h", offset, observed, expected_data);
endtask

task automatic reset_dut;
  rst_n_i         = 1'b0;
  user_select_i   = 32'hffff_ffff;
  user_status_i   = 32'hffff_ffff;
  filter_enable_i = 32'd0;
  gpio_ready_i    = 1'b1;
  gpio_input_i    = 32'd0;
  dma_tx_job_i    = 1'b0;
  dma_rx_job_i    = 1'b0;
  u_apb.psel      = 1'b0;
  u_apb.penable   = 1'b0;
  u_apb.pwrite    = 1'b0;
  u_apb.paddr     = 32'd0;
  u_apb.pwdata    = 32'd0;
  u_apb.pstrb     = 4'd0;
  u_apb.pprot     = 3'd0;
  u_stream_bfm.reset_bfm();
  repeat (3) @(negedge clk_i);
  rst_n_i = 1'b1;
  repeat (3) @(negedge clk_i);
endtask

task automatic write_program(input integer sm, input logic [4:0] base, input logic [5:0] length,
                             input logic [4:0] wrap_bottom, input logic [4:0] wrap_top);
  logic [11:0] sm_base;
  sm_base = sm == 0 ? 12'h200 : 12'h280;
  wr(sm_base + 12'h00c, (32'(length) << 8) | (32'(base) << 16) | 32'(base), 1'b0);
  wr(sm_base + 12'h010, (32'(wrap_top) << 8) | 32'(wrap_bottom), 1'b0);
endtask

task automatic run_vectors;
  if (!$value$plusargs("PIOLITE_VECTORS=%s", vector_path))
    $fatal(1, "PIOLITE vector file plusarg is required");
  $readmemh(vector_path, vector_mem);
  if (vector_mem[0] !== 32'd29) $fatal(1, "PIOLITE vector file/count is invalid");
  vector_count = vector_mem[0];
  for (integer vector_index = 0; vector_index < vector_count; vector_index++) begin
    $display("PIOLITE_P2_VECTOR index=%0d", vector_index);
    reset_dut();
    record_base  = 1 + vector_index * 78;
    vector_steps = vector_mem[record_base+18];
    wr(12'h208, vector_mem[record_base+0], 1'b0);
    wr(12'h204, vector_mem[record_base+3], 1'b0);
    wr(12'h20c, vector_mem[record_base+1], 1'b0);
    wr(12'h210, vector_mem[record_base+2], 1'b0);
    wr(12'h214, vector_mem[record_base+4], 1'b0);
    wr(12'h218, vector_mem[record_base+5], 1'b0);
    wr(12'h21c, vector_mem[record_base+6], 1'b0);
    wr(12'h220, vector_mem[record_base+7], 1'b0);
    wr(12'h224, vector_mem[record_base+8], 1'b0);
    wr(12'h228, vector_mem[record_base+9], 1'b0);
    wr(12'h22c, vector_mem[record_base+10], 1'b0);
    wr(12'h230, vector_mem[record_base+11], 1'b0);
    wr(12'h234, vector_mem[record_base+12], 1'b0);
    wr(12'h238, vector_mem[record_base+13], 1'b0);
    for (integer word_index = 0; word_index < (vector_mem[record_base+1] >> 8); word_index++)
    wr(12'h100 + 12'(word_index * 4), vector_mem[record_base+38+word_index], 1'b0);
    for (integer tx_index = 0; tx_index < vector_mem[record_base+16]; tx_index++)
    wr(12'h240, vector_mem[record_base+14+tx_index], 1'b0);
    gpio_input_i = vector_mem[record_base+17];
    fork
      begin
        if (vector_mem[record_base+37] < (vector_mem[record_base+1] >> 8)) begin
          @(posedge clk_i);
          while (!(u_apb.psel && u_apb.penable && !u_apb.pready && u_apb.pwrite &&
                   u_apb.paddr[11:0] == 12'h040))
          @(posedge clk_i);
          @(negedge clk_i);
`ifndef PIOLITE_SCALAR_APB
          force u_dut.u_core.u_imem.s_valid_q = (32'd1 << vector_mem[record_base+37]) - 32'd1;
          repeat (2) @(negedge clk_i);
          release u_dut.u_core.u_imem.s_valid_q;
`endif
        end
      end
      begin
        wr(12'h040, 32'd1, 1'b0);
      end
    join
    repeat (vector_steps + 4) @(negedge clk_i);
    check_reg(12'h200, vector_mem[record_base+19]);
    check_reg(12'h254, vector_mem[record_base+20]);
    check_reg(12'h258, vector_mem[record_base+21]);
    check_reg(12'h25c, vector_mem[record_base+22]);
    check_reg(12'h260, vector_mem[record_base+23]);
    check_reg(12'h264, vector_mem[record_base+24]);
    check_reg(12'h268, vector_mem[record_base+25]);
    check_reg(12'h26c, vector_mem[record_base+26]);
    check_reg(12'h270, vector_mem[record_base+27]);
    check_reg(12'h274, vector_mem[record_base+28]);
    check_reg(12'h278, vector_mem[record_base+29]);
    check_reg(12'h27c, vector_mem[record_base+30]);
    check_reg(12'h248, vector_mem[record_base+31] | (vector_mem[record_base+32] << 8));
    check_reg(12'h24c, vector_mem[record_base+33]);
    check_reg(12'h018, vector_mem[record_base+34]);
    u_pin_bfm.expect_pins(vector_mem[record_base+35], vector_mem[record_base+36]);
    for (integer rx_index = 0; rx_index < vector_mem[record_base+32]; rx_index++)
    check_reg(12'h244, vector_mem[record_base+70+rx_index]);
    $display("PIOLITE_P2_CYCLES vector=%0d edges=%0d", vector_index, vector_steps);
  end
endtask

task automatic core_dual_halt;
  reset_dut();
  wr(12'h100, 32'h00000020, 1'b0);
  wr(12'h104, 32'h00000020, 1'b0);
  write_program(0, 0, 1, 0, 0);
  write_program(1, 1, 1, 1, 1);
  wr(12'h040, 32'h3, 1'b0);
  repeat (4) @(negedge clk_i);
  check_reg(12'h200, 32'h3);
  check_reg(12'h280, 32'h3);
  check_reg(12'h26c, 32'd1);
  check_reg(12'h2ec, 32'd1);
  check_reg(12'h278, 32'd1);
  check_reg(12'h2f8, 32'd1);
  $display("PIOLITE_P2_CYCLES case=dual_halt edges=1");
endtask

task automatic core_flag_event_race;
  logic race_seen;
`ifndef PIOLITE_SCALAR_APB
  reset_dut();
  wr(12'h100, 32'h0000a080, 1'b0);
  wr(12'h104, 32'h00000020, 1'b0);
  wr(12'h108, 32'h0000a000, 1'b0);
  wr(12'h10c, 32'h00000020, 1'b0);
  write_program(0, 0, 2, 0, 1);
  write_program(1, 2, 2, 2, 3);
  wr(12'h208, 32'd8, 1'b0);
  wr(12'h288, 32'd8, 1'b0);
  wr(12'h040, 32'h3, 1'b0);
  race_seen = 1'b0;
  fork
    begin
      @(negedge clk_i);
      while (!((u_dut.u_ctrl.runtime[0].tick_count == 1) &&
               (u_dut.u_ctrl.runtime[0].divider_remaining == 2)))
      @(negedge clk_i);
      u_apb.psel    = 1'b1;
      u_apb.penable = 1'b0;
      u_apb.pwrite  = 1'b1;
      u_apb.paddr   = 32'h24c;
      u_apb.pwdata  = 32'd1;
      u_apb.pstrb   = 4'hf;
      @(negedge clk_i);
      u_apb.penable = 1'b1;
      while (!u_apb.pready) @(negedge clk_i);
      @(posedge clk_i);
      @(negedge clk_i);
      u_apb.psel    = 1'b0;
      u_apb.penable = 1'b0;
    end
    begin
      @(posedge clk_i);
      while (!(u_apb.psel && u_apb.penable && !u_apb.pready && u_apb.pwrite &&
               (u_apb.paddr[11:0] == 12'h24c) && u_dut.u_core.gen_sm[0].u_sm.s_commit))
      @(posedge clk_i);
      race_seen = 1'b1;
    end
  join
  if (!race_seen) $fatal(1, "PIOLITE EVENTS W1C did not coincide with HALT commit");
  check_reg(12'h018, 32'd1);
  check_reg(12'h24c, 32'd1);
  $display("PIOLITE_P2_COVER PL-V08 same-edge-command-commit-and-set-wins-w1c");
`endif
endtask

task automatic pause_at_first_tick;
`ifndef PIOLITE_SCALAR_APB
  logic pause_seen;
  pause_seen = 1'b0;
  fork
    begin
      @(negedge clk_i);
      while (!((u_dut.u_ctrl.runtime[0].tick_count == 0) &&
               (u_dut.u_ctrl.runtime[0].divider_remaining == 2)))
      @(negedge clk_i);
      u_apb.psel    = 1'b1;
      u_apb.penable = 1'b0;
      u_apb.pwrite  = 1'b1;
      u_apb.paddr   = 32'h044;
      u_apb.pwdata  = 32'd1;
      u_apb.pstrb   = 4'hf;
      @(negedge clk_i);
      u_apb.penable = 1'b1;
      while (!u_apb.pready) @(negedge clk_i);
      @(posedge clk_i);
      @(negedge clk_i);
      u_apb.psel    = 1'b0;
      u_apb.penable = 1'b0;
    end
    begin
      @(posedge clk_i);
      while (!(u_apb.psel && u_apb.penable && !u_apb.pready && u_apb.pwrite &&
               (u_apb.paddr[11:0] == 12'h044) &&
               (u_dut.u_ctrl.runtime[0].divider_remaining == 1)))
      @(posedge clk_i);
      pause_seen = 1'b1;
    end
  join
  if (!pause_seen) $fatal(1, "PIOLITE PAUSE did not land on the first execution tick");
`endif
endtask

task automatic check_paused_baseline(input logic [3:0] tx_level);
  check_reg(12'h200, 32'd2);
  check_reg(12'h254, 32'd0);
  check_reg(12'h258, 32'd0);
  check_reg(12'h25c, 32'd0);
  check_reg(12'h260, 32'd0);
  check_reg(12'h264, 32'h0002_0001);
  check_reg(12'h268, 32'd0);
  check_reg(12'h26c, 32'd0);
  check_reg(12'h270, 32'd0);
  check_reg(12'h274, 32'd0);
  check_reg(12'h278, 32'd0);
  check_reg(12'h27c, 32'd1);
  check_reg(12'h24c, 32'd0);
  check_reg(12'h248, {20'd0, 4'd0, 4'd0, tx_level});
  check_reg(12'h018, 32'd0);
  u_pin_bfm.expect_pins(32'h0000_00c0, 32'd1);
endtask

task automatic pause_candidate(input logic [15:0] word, input logic preload_tx);
  reset_dut();
  wr(12'h100, {16'd0, word}, 1'b0);
  wr(12'h104, 32'h0000_0020, 1'b0);
  write_program(0, 0, 2, 0, 1);
  wr(12'h204, 32'h0000_001f, 1'b0);
  wr(12'h208, 32'd8, 1'b0);
  wr(12'h214, 32'h0000_2000, 1'b0);
  wr(12'h218, 32'h0000_2000, 1'b0);
  wr(12'h21c, 32'h0000_0800, 1'b0);
  wr(12'h220, 32'hffff_ffff, 1'b0);
  wr(12'h224, 32'hffff_ffff, 1'b0);
  wr(12'h228, 32'h0000_00c0, 1'b0);
  wr(12'h22c, 32'h0000_0001, 1'b0);
  wr(12'h230, 32'h0002_0001, 1'b0);
  wr(12'h234, 32'h0000_0820, 1'b0);
  if (preload_tx) wr(12'h240, 32'hd31a5a69, 1'b0);
  wr(12'h040, 32'd1, 1'b0);
  pause_at_first_tick();
  check_paused_baseline(preload_tx ? 4'd1 : 4'd0);
endtask

task automatic core_pause_atomicity;
`ifndef PIOLITE_SCALAR_APB
  pause_candidate(16'h4028, 1'b0);
  pause_candidate(16'h5004, 1'b1);
  pause_candidate(16'h31ff, 1'b0);
  pause_candidate(16'ha080, 1'b0);
  pause_candidate(16'h0020, 1'b0);
  $display("PIOLITE_P2_COVER PL-V08 pause-suppresses-all-candidate-side-effects");
`endif
endtask

task automatic core_pin_delay;
  reset_dut();
  wr(12'h100, 32'h00001101, 1'b0);
  wr(12'h104, 32'h00000020, 1'b0);
  write_program(0, 0, 2, 0, 1);
  wr(12'h208, 32'd2, 1'b0);
  wr(12'h21c, 32'h00000100, 1'b0);
  wr(12'h220, 32'd1, 1'b0);
  wr(12'h224, 32'd1, 1'b0);
  wr(12'h22c, 32'd1, 1'b0);
  wr(12'h040, 32'd1, 1'b0);
  repeat (8) @(negedge clk_i);
  u_pin_bfm.expect_pins(32'd1, 32'd1);
  check_reg(12'h200, 32'd3);
  check_reg(12'h26c, 32'd3);
  check_reg(12'h278, 32'd2);
  $display("PIOLITE_P2_CYCLES case=pin_delay pclk_edges=6 sm_ticks=3 transitions=%0d",
           pin_transitions);
endtask

task automatic core_pause_resume;
  reset_dut();
  wr(12'h100, 32'h00008040, 1'b0);
  wr(12'h104, 32'h00000020, 1'b0);
  write_program(0, 0, 2, 0, 1);
  wr(12'h208, 32'd4, 1'b0);
  wr(12'h220, 32'd1, 1'b0);
  wr(12'h040, 32'd1, 1'b0);
  repeat (2) @(negedge clk_i);
  wr(12'h044, 32'd1, 1'b0);
  check_reg(12'h200, 32'd2);
  rd(12'h27c, saved_phase);
  rd(12'h26c, value);
  repeat (10) @(negedge clk_i);
  check_reg(12'h27c, saved_phase);
  check_reg(12'h26c, value);
  wr(12'h048, 32'd1, 1'b0);
  repeat (6) @(negedge clk_i);
  rd(12'h200, value);
  if ((value[2:0] != 1) || (value[6:4] != 1)) $fatal(1, "PIOLITE WAIT did not stall");
  gpio_input_i[0] = 1'b1;
  repeat (6) @(negedge clk_i);
  check_reg(12'h200, 32'd3);
  $display("PIOLITE_P2_COVER PL-V03 dual-tick-divider-delay-and-pause-resume");
endtask

task automatic core_counter_boundaries;
  for (integer test_index = 0; test_index < 3; test_index++) begin
    reset_dut();
    wr(12'h100, 32'h00006010, 1'b0);
    wr(12'h104, 32'h00006058, 1'b0);
    wr(12'h108, 32'h00009063, 1'b0);
    wr(12'h10c, 32'h00000020, 1'b0);
    write_program(0, 0, 4, 0, 3);
    case (test_index)
      0:       wr(12'h230, {16'd1, 16'd0}, 1'b0);
      1:       wr(12'h230, {16'd0, 16'd1}, 1'b0);
      default: wr(12'h230, 32'hffff_ffff, 1'b0);
    endcase
    wr(12'h040, 32'd1, 1'b0);
    repeat (6) @(negedge clk_i);
    check_reg(12'h200, 32'd3);
    case (test_index)
      0: begin
        check_reg(12'h25c, 32'd0);
        check_reg(12'h260, 32'd1);
        check_reg(12'h264, 32'h0001_0000);
      end
      1: begin
        check_reg(12'h25c, 32'd1);
        check_reg(12'h260, 32'd0);
        check_reg(12'h264, 32'd0);
      end
      default: begin
        check_reg(12'h25c, 32'h0000_ffff);
        check_reg(12'h260, 32'h0000_ffff);
        check_reg(12'h264, 32'hffff_fffe);
      end
    endcase
    check_reg(12'h278, 32'd4);
  end
  $display("PIOLITE_P2_COVER PL-V04 counters-move-wrap-and-branches");
endtask

task automatic core_autopush_full;
  reset_dut();
  for (integer index = 0; index < 9; index++) wr(12'h100 + 12'(index * 4), 32'h00004028, 1'b0);
  wr(12'h124, 32'h00000020, 1'b0);
  write_program(0, 0, 10, 0, 9);
  wr(12'h204, 32'h0000_000a, 1'b0);
  wr(12'h230, 32'h0000_005a, 1'b0);
  wr(12'h234, 32'h0000_0820, 1'b0);
  wr(12'h040, 32'd1, 1'b0);
  repeat (12) @(negedge clk_i);
  check_reg(12'h248, 32'h0000_0800);
  check_reg(12'h25c, 32'd0);
  rd(12'h200, value);
  if ((value[2:0] != 1) || (value[6:4] != 4)) $fatal(1, "PIOLITE autopush did not stall RX");
  rd(12'h274, value);
  if (value == 0) $fatal(1, "PIOLITE RX stall counter did not advance");
  check_reg(12'h278, 32'd8);
  check_reg(12'h244, 32'h0000_005a);
  repeat (3) @(negedge clk_i);
  check_reg(12'h248, 32'h0000_0800);
  rd(12'h278, value);
  if ((value < 9) || (value > 10)) $fatal(1, "PIOLITE autopush resume retirement mismatch");
  check_reg(12'h25c, 32'd0);
  for (integer index = 0; index < 8; index++) check_reg(12'h244, 32'h0000_005a);
  repeat (3) @(negedge clk_i);
  check_reg(12'h200, 32'd3);
  check_reg(12'h278, 32'd10);
  $display("PIOLITE_P2_COVER PL-V05 exact-autopush-threshold-and-atomic-stall");
  $display("PIOLITE_P2_COVER PL-V06 pre-sample-backpressure-and-stall-accounting");
endtask

task automatic apb_repeated_tx;
  reset_dut();
  @(negedge clk_i);
  u_apb.psel    = 1'b1;
  u_apb.penable = 1'b0;
  u_apb.pwrite  = 1'b1;
  u_apb.paddr   = 32'h240;
  u_apb.pwdata  = 32'h89ab_cdef;
  u_apb.pstrb   = 4'hf;
  @(negedge clk_i);
  u_apb.penable = 1'b1;
  while (!u_apb.pready) @(negedge clk_i);
  repeat (5) @(negedge clk_i);
  u_apb.psel    = 1'b0;
  u_apb.penable = 1'b0;
  @(negedge clk_i);
  check_reg(12'h248, 32'd1);
endtask

function automatic logic [31:0] global_reset_value(input logic [11:0] offset);
  case (offset)
    12'h000:          global_reset_value = 32'h5049_4f4c;
    12'h004, 12'h008: global_reset_value = 32'h0001_0000;
    12'h00c:          global_reset_value = 32'h0808_2002;
    12'h010, 12'h03c: global_reset_value = 32'hffff_ffff;
    12'h014:          global_reset_value = 32'd24000000;
    12'h024:          global_reset_value = 32'h0003_0000;
    default:          global_reset_value = 32'd0;
  endcase
endfunction

function automatic logic [31:0] sm_reset_value(input logic [11:0] offset);
  case (offset)
    12'h008: sm_reset_value = 32'd1;
    12'h034: sm_reset_value = 32'h0000_2020;
    12'h03c: sm_reset_value = 32'h0000_0100;
    default: sm_reset_value = 32'd0;
  endcase
endfunction

function automatic logic global_is_ro(input logic [11:0] offset);
  case (offset)
    12'h000, 12'h004, 12'h008, 12'h00c, 12'h010, 12'h014, 12'h018, 12'h024,
    12'h034, 12'h038, 12'h03c:
    global_is_ro = 1'b1;
    default: global_is_ro = 1'b0;
  endcase
endfunction

function automatic logic global_is_wo(input logic [11:0] offset);
  case (offset)
    12'h01c, 12'h020, 12'h040, 12'h044, 12'h048, 12'h04c, 12'h050, 12'h054, 12'h058:
    global_is_wo = 1'b1;
    default: global_is_wo = 1'b0;
  endcase
endfunction

function automatic logic sm_is_ro(input logic [11:0] offset);
  case (offset)
    12'h000, 12'h044, 12'h048, 12'h054, 12'h058, 12'h05c, 12'h060, 12'h064,
    12'h068, 12'h06c, 12'h070, 12'h074, 12'h078, 12'h07c:
    sm_is_ro = 1'b1;
    default: sm_is_ro = 1'b0;
  endcase
endfunction

task automatic apb_reset_access_matrix;
  reset_dut();
  for (integer index = 0; index < 23; index++) begin
    if (global_is_wo(12'(index * 4))) access (1'b0, 12'(index * 4), 32'd0, 4'd0, 1'b1, value);
    else begin
      check_reg(12'(index * 4), global_reset_value(12'(index * 4)));
      if (global_is_ro(12'(index * 4))) wr(12'(index * 4), 32'd0, 1'b1);
    end
  end
  for (integer index = 0; index < 32; index++) check_reg(12'(12'h100 + index * 4), 32'd0);
  for (integer sm = 0; sm < 2; sm++) begin
    for (integer index = 0; index < 32; index++) begin
      automatic logic [11:0] offset;
      offset = 12'((sm == 0 ? 32'h200 : 32'h280) + index * 4);
      if (12'(index * 4) == 12'h040) access (1'b0, offset, 32'd0, 4'd0, 1'b1, value);
      else if (12'(index * 4) == 12'h044) begin
        access (1'b0, offset, 32'd0, 4'd0, 1'b1, value);
        wr(offset, 32'd0, 1'b1);
      end else begin
        check_reg(offset, sm_reset_value(12'(index * 4)));
        if (sm_is_ro(12'(index * 4))) wr(offset, 32'd0, 1'b1);
      end
    end
  end
endtask

task automatic apb_rw_fields;
  reset_dut();
  wr(12'h204, 32'h0000_001f, 1'b0);
  check_reg(12'h204, 32'h0000_001f);
  wr(12'h208, 32'h0000_ffff, 1'b0);
  check_reg(12'h208, 32'h0000_ffff);
  wr(12'h20c, 32'h0001_0201, 1'b0);
  check_reg(12'h20c, 32'h0001_0201);
  wr(12'h210, 32'h0000_0201, 1'b0);
  check_reg(12'h210, 32'h0000_0201);
  wr(12'h214, 32'h0000_2000, 1'b0);
  check_reg(12'h214, 32'h0000_2000);
  wr(12'h218, 32'h0000_1001, 1'b0);
  check_reg(12'h218, 32'h0000_1001);
  wr(12'h21c, 32'h0000_0802, 1'b0);
  check_reg(12'h21c, 32'h0000_0802);
  wr(12'h220, 32'h0000_00ff, 1'b0);
  check_reg(12'h220, 32'h0000_00ff);
  wr(12'h224, 32'h0000_00f0, 1'b0);
  check_reg(12'h224, 32'h0000_00f0);
  wr(12'h228, 32'h0000_0080, 1'b0);
  check_reg(12'h228, 32'h0000_0080);
  wr(12'h22c, 32'h0000_0080, 1'b0);
  check_reg(12'h22c, 32'h0000_0080);
  wr(12'h230, 32'hffff_0001, 1'b0);
  check_reg(12'h230, 32'hffff_0001);
  wr(12'h234, 32'h0000_2001, 1'b0);
  check_reg(12'h234, 32'h0000_2001);
  wr(12'h238, 32'h0000_031f, 1'b0);
  check_reg(12'h238, 32'h0000_031f);
  wr(12'h23c, 32'h0000_0808, 1'b0);
  check_reg(12'h23c, 32'h0000_0808);
  wr(12'h250, 32'h0000_003f, 1'b0);
  check_reg(12'h250, 32'h0000_003f);
  wr(12'h028, 32'h0303_0f03, 1'b0);
  check_reg(12'h028, 32'h0303_0f03);
  wr(12'h028, 32'd0, 1'b0);
  wr(12'h02c, 32'h8000_0300, 1'b0);
  check_reg(12'h02c, 32'h8000_0300);
  wr(12'h030, 32'h8000_0201, 1'b0);
  check_reg(12'h030, 32'h8000_0201);
  wr(12'h02c, 32'd0, 1'b0);
  wr(12'h030, 32'd0, 1'b0);
endtask

task automatic run_apb;
  apb_reset_access_matrix();
  apb_rw_fields();
  reset_dut();
  check_reg(12'h000, 32'h50494f4c);
  check_reg(12'h004, 32'h00010000);
  check_reg(12'h008, 32'h00010000);
  check_reg(12'h00c, 32'h08082002);
  check_reg(12'h014, 32'd24000000);
  check_reg(12'h208, 32'd1);
  check_reg(12'h234, 32'h00002020);
  check_reg(12'h23c, 32'h00000100);
  check_reg(12'h038, 32'd0);
  wr(12'h208, 32'd0, 1'b1);
  check_reg(12'h208, 32'd1);
  wr(12'h204, 32'h8000_0000, 1'b1);
  check_reg(12'h204, 32'd0);
  wr(12'h100, 32'h00000020, 1'b0);
  check_reg(12'h038, 32'd1);
  check_reg(12'h100, 32'h00000020);
  wr(12'h100, 32'h00010020, 1'b1);
  check_reg(12'h100, 32'h00000020);
  access (1'b1, 12'h204, 32'd0, 4'h1, 1'b1, value);
  access (1'b0, 12'h001, 32'd0, 4'd0, 1'b1, value);
  access (1'b0, 12'h300, 32'd0, 4'd0, 1'b1, value);
  access (1'b0, 12'h05c, 32'd0, 4'd0, 1'b1, value);
  access (1'b0, 12'h240, 32'd0, 4'd0, 1'b1, value);
  access (1'b0, 12'h244, 32'd0, 4'd0, 1'b1, value);
  access (1'b0, 12'h380, 32'd0, 4'd0, 1'b1, value);
  access (1'b0, 12'h400, 32'd0, 4'd0, 1'b1, value);
  access (1'b1, 12'h204, 32'd0, 4'd0, 1'b1, value);
  for (integer index = 0; index < 6; index++) wr(12'(12'h040 + index * 4), 32'd4, 1'b1);
  wr(12'h058, 32'd2, 1'b1);
  wr(12'h01c, 32'h0000_0010, 1'b1);
  wr(12'h028, 32'h0400_0000, 1'b1);
  wr(12'h02c, 32'h8000_0002, 1'b1);
  wr(12'h030, 32'h8000_0002, 1'b1);
  wr(12'h20c, 32'd0, 1'b1);
  wr(12'h20c, 32'h0020_0200, 1'b1);
  wr(12'h210, 32'h0000_0020, 1'b1);
  wr(12'h214, 32'h0000_2100, 1'b1);
  wr(12'h218, 32'h0000_0080, 1'b1);
  wr(12'h21c, 32'h0000_0900, 1'b1);
  wr(12'h228, 32'd1, 1'b1);
  wr(12'h22c, 32'd1, 1'b1);
  wr(12'h234, 32'd0, 1'b1);
  wr(12'h234, 32'h0000_2000, 1'b1);
  wr(12'h238, 32'h0000_0020, 1'b1);
  wr(12'h23c, 32'd0, 1'b1);
  wr(12'h24c, 32'h0000_0040, 1'b1);
  wr(12'h250, 32'h0000_0040, 1'b1);
  for (integer index = 0; index < 8; index++) wr(12'h240, 32'(index), 1'b0);
  wr(12'h240, 32'hdead_beef, 1'b1);
  check_reg(12'h248, 32'd8);
  wr(12'h23c, 32'h0000_0108, 1'b0);
  wr(12'h028, 32'd4, 1'b1);
  wr(12'h028, 32'h0001_0000, 1'b0);
  if (!irq_o) $fatal(1, "PIOLITE TX level watermark did not assert IRQ");
  wr(12'h028, 32'd0, 1'b0);
  user_select_i = 32'd0;
  user_status_i = 32'd0;
  wr(12'h058, 32'd1, 1'b0);
  check_reg(12'h038, 32'd0);
  check_reg(12'h248, 32'd0);
  apb_repeated_tx();
  apb_live_write_atomicity();
  $display("PIOLITE_P2_COVER PL-V07 all-csr-reset-access-fields-and-errors");
endtask

task automatic apb_live_write_atomicity;
  start_wait_with_output();
  wr(12'h204, 32'h0000_001f, 1'b1);
  check_reg(12'h204, 32'd0);
  wr(12'h208, 32'd2, 1'b1);
  check_reg(12'h208, 32'd1);
  wr(12'h100, 32'h0000_0020, 1'b1);
  check_reg(12'h100, 32'h0000_8040);
  check_reg(12'h038, 32'd3);
  wr(12'h050, 32'd1, 1'b0);
  check_reg(12'h200, 32'd4);
  wr(12'h204, 32'h0000_001f, 1'b1);
  check_reg(12'h204, 32'd0);
  wr(12'h208, 32'd2, 1'b1);
  check_reg(12'h208, 32'd1);
  wr(12'h100, 32'h0000_0020, 1'b1);
  check_reg(12'h100, 32'h0000_8040);
  check_reg(12'h038, 32'd3);
  wr(12'h054, 32'd1, 1'b0);
  check_reg(12'h200, 32'd0);
  wr(12'h02c, 32'h8000_0300, 1'b0);
  dma_tx_job_i = 1'b1;
  wr(12'h204, 32'h0000_001f, 1'b1);
  check_reg(12'h204, 32'd0);
  wr(12'h208, 32'd2, 1'b1);
  check_reg(12'h208, 32'd1);
  wr(12'h100, 32'h0000_0020, 1'b1);
  check_reg(12'h100, 32'h0000_8040);
  check_reg(12'h038, 32'd3);
  dma_tx_job_i = 1'b0;
  wr(12'h02c, 32'd0, 1'b0);
  $display("PIOLITE_P2_COVER PL-V07 live-config-imem-write-atomicity");
endtask

task automatic start_wait_with_output;
  reset_dut();
  wr(12'h100, 32'h00008040, 1'b0);
  wr(12'h104, 32'h00000020, 1'b0);
  write_program(0, 0, 2, 0, 1);
  wr(12'h220, 32'd1, 1'b0);
  wr(12'h224, 32'd1, 1'b0);
  wr(12'h22c, 32'd1, 1'b0);
  wr(12'h040, 32'd1, 1'b0);
endtask

task automatic lifecycle_abort_reset;
  start_wait_with_output();
  repeat (2) @(negedge clk_i);
  wr(12'h050, 32'd1, 1'b0);
  check_reg(12'h200, 32'd4);
  u_pin_bfm.expect_quiescent();
  check_reg(12'h24c, 32'd2);
  wr(12'h040, 32'd1, 1'b1);
  wr(12'h04c, 32'd1, 1'b1);
  wr(12'h24c, 32'd2, 1'b0);
  check_reg(12'h24c, 32'd0);
  wr(12'h050, 32'd1, 1'b0);
  check_reg(12'h24c, 32'd2);
  wr(12'h054, 32'd1, 1'b0);
  check_reg(12'h200, 32'd0);
  check_reg(12'h24c, 32'd0);
  check_reg(12'h220, 32'd1);
endtask

task automatic lifecycle_guard_loss;
  start_wait_with_output();
  repeat (2) @(negedge clk_i);
  user_select_i[0] = 1'b0;
  #1;
  u_pin_bfm.expect_quiescent();
  repeat (2) @(negedge clk_i);
  check_reg(12'h254, 32'd6);
  check_reg(12'h200, 32'd4);
  user_select_i = 32'hffff_ffff;
  repeat (2) @(negedge clk_i);
  check_reg(12'h200, 32'd4);
  wr(12'h054, 32'd1, 1'b0);
endtask

task automatic lifecycle_disabled_resources;
  reset_dut();
  wr(12'h240, 32'h1234_5678, 1'b0);
  wr(12'h050, 32'd1, 1'b0);
  check_reg(12'h200, 32'd4);
  wr(12'h240, 32'hdead_beef, 1'b1);
  access (1'b0, 12'h244, 32'd0, 4'd0, 1'b1, value);
  wr(12'h054, 32'd1, 1'b0);
  check_reg(12'h248, 32'd0);
endtask

task automatic lifecycle_invalid_stream;
  reset_dut();
  wr(12'h02c, 32'h8000_0300, 1'b0);
  u_stream_bfm.send_tx(32'h1122_3344, 4'h0, 4'hf, 1'b0);
  repeat (3) @(negedge clk_i);
  check_reg(12'h254, 32'd8);
  check_reg(12'h200, 32'd4);
  u_stream_bfm.send_tx(32'h5566_7788, 4'hf, 4'hf, 1'b0);
  check_reg(12'h034, 32'h0000_0010);
  wr(12'h054, 32'd1, 1'b0);
  check_reg(12'h02c, 32'd0);
endtask

task automatic lifecycle_rx_valid;
  reset_dut();
  wr(12'h100, 32'h00004028, 1'b0);
  wr(12'h104, 32'h00007080, 1'b0);
  wr(12'h108, 32'h00000020, 1'b0);
  write_program(0, 0, 3, 0, 2);
  wr(12'h204, 32'h0000_0008, 1'b0);
  wr(12'h230, 32'h0000_00ca, 1'b0);
  wr(12'h040, 32'd1, 1'b0);
  repeat (5) @(negedge clk_i);
  check_reg(12'h200, 32'd3);
  check_reg(12'h248, 32'h0000_0100);
  wr(12'h04c, 32'd1, 1'b0);
  wr(12'h030, 32'h8000_0200, 1'b0);
  repeat (3) @(negedge clk_i);
  if (!dma_rx_valid_o || (dma_rx_data_o !== 32'hca)) $fatal(1, "PIOLITE RX held beat missing");
  repeat (5) @(negedge clk_i);
  wr(12'h050, 32'd1, 1'b0);
  if (!dma_rx_valid_o || (dma_rx_data_o !== 32'hca)) $fatal(1, "PIOLITE abort withdrew RX VALID");
  u_stream_bfm.expect_rx(32'hca, 10);
  wr(12'h054, 32'd1, 1'b0);
  check_reg(12'h030, 32'd0);
endtask

task automatic lifecycle_paused_dma_snapshot;
  reset_dut();
  wr(12'h100, 32'h00008040, 1'b0);
  wr(12'h104, 32'h00000020, 1'b0);
  write_program(0, 0, 2, 0, 1);
  wr(12'h220, 32'd1, 1'b0);
  wr(12'h02c, 32'h8000_0300, 1'b0);
  wr(12'h040, 32'd1, 1'b0);
  repeat (2) @(negedge clk_i);
  wr(12'h044, 32'd1, 1'b0);
  rd(12'h27c, saved_phase);
  rd(12'h26c, expected);
  u_stream_bfm.send_tx(32'h0123_4567, 4'hf, 4'hf, 1'b0);
  u_stream_bfm.send_tx(32'h89ab_cdef, 4'hf, 4'hf, 1'b0);
  check_reg(12'h248, 32'd2);
  check_reg(12'h200, 32'd2);
  check_reg(12'h258, 32'd0);
  check_reg(12'h25c, 32'd0);
  check_reg(12'h260, 32'd0);
  check_reg(12'h264, 32'd0);
  check_reg(12'h27c, saved_phase);
  check_reg(12'h26c, expected);
  wr(12'h050, 32'd1, 1'b0);
  wr(12'h054, 32'd1, 1'b0);
  $display("PIOLITE_P2_COVER PL-V08 paused-snapshot-while-dma-progresses");
endtask

task automatic lifecycle_tx_discard;
  reset_dut();
  for (integer index = 0; index < 8; index++) wr(12'h240, 32'(index), 1'b0);
  wr(12'h02c, 32'h8000_0300, 1'b0);
  u_stream_bfm.send_tx(32'hdead_beef, 4'hf, 4'hf, 1'b0);
  repeat (2) @(negedge clk_i);
  rd(12'h034, value);
  if (!value[2]) $fatal(1, "PIOLITE TX beat was not held at full FIFO");
  wr(12'h050, 32'd1, 1'b0);
  repeat (2) @(negedge clk_i);
  rd(12'h034, value);
  if (value[2] || !value[4]) $fatal(1, "PIOLITE closing did not discard held TX beat");
  u_stream_bfm.send_tx(32'hc001_d00d, 4'hf, 4'hf, 1'b0);
  wr(12'h054, 32'd1, 1'b0);
endtask

task automatic run_netlist;
  core_dual_halt();
  reset_dut();
  check_reg(12'h000, 32'h50494f4c);
  check_reg(12'h00c, 32'h08082002);
  wr(12'h100, 32'h00000020, 1'b0);
  write_program(0, 0, 1, 0, 0);
  wr(12'h040, 32'd1, 1'b0);
  repeat (3) @(negedge clk_i);
  check_reg(12'h200, 32'd3);
endtask

initial begin
  case (TestKind)
    0:       run_vectors();
    1: begin
      core_dual_halt();
      core_flag_event_race();
      core_pause_atomicity();
      core_pin_delay();
      core_pause_resume();
      core_counter_boundaries();
      core_autopush_full();
    end
    3:       run_apb();
    4: begin
      $display("PIOLITE_P2_LIFECYCLE case=abort_reset");
      lifecycle_abort_reset();
      $display("PIOLITE_P2_LIFECYCLE case=guard_loss");
      lifecycle_guard_loss();
      $display("PIOLITE_P2_LIFECYCLE case=disabled_resources");
      lifecycle_disabled_resources();
      $display("PIOLITE_P2_LIFECYCLE case=invalid_stream");
      lifecycle_invalid_stream();
      $display("PIOLITE_P2_LIFECYCLE case=rx_valid");
      lifecycle_rx_valid();
      lifecycle_paused_dma_snapshot();
      $display("PIOLITE_P2_LIFECYCLE case=tx_discard");
      lifecycle_tx_discard();
    end
    5:       run_netlist();
    default: $fatal(1, "PIOLITE invalid TestKind");
  endcase
  $display("PIOLITE_P2_PASS %s", TestName);
  $finish;
end

initial begin
  #20000000;
  $fatal(1, "SIM_TEST_TIMEOUT PIOLITE fixture");
end
