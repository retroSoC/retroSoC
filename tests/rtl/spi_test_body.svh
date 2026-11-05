logic clk_i = 0;
always #20.833 clk_i = !clk_i;  // SAFE24, rounded to the fixture's 1 ps precision.
logic        rst_n_i = '0;
logic [31:0] clock_hz_i = '0;
logic [ 1:0] origin_i = '0;
logic [ 4:0] request_i = '0;
logic [ 2:0] channel_i = '0;
logic [ 1:0] credit_valid_i = '0;
logic [ 1:0] credit_retire_i = '0;
logic [ 1:0] dma_start_pending_i = '0;
logic [ 3:0] dma_status_i = '0;
logic        dma_error_i = '0;
logic [31:0] user_select_i = '0;
logic [31:0] handoff_i = '0;
logic [31:0] alt_enable_i = '0;
logic [31:0] alt_select_i = '0;
logic [31:0] output_enable_i = '0;
logic [31:0] open_drain_i = '0;
logic        gpio_ready_i = '0;
logic        miso_i;
logic        sck_o;
logic        mosi_o;
logic        cs_n_o;
logic        output_enable_o;
logic        irq_o;
logic [ 1:0] credit_commit_o;
logic [31:0] paddr_i = 0, pwdata_i = 0, prdata_o;
logic [3:0] pstrb_i = 0;
logic psel_i = 0, penable_i = 0, pwrite_i = 0, pready_o, pslverr_o;
logic model_begin = 0, model_enable = 0, model_abort = 0;
logic model_segment = 0, model_pause = 0;
logic session_owned, lifecycle_idle;
logic [15:0] model_divider = 1, model_setup = 1, model_hold = 1, model_inactive = 1;
logic [8:0] model_faults;
logic cpol = 0, cpha = 0, lsb = 0, frame16 = 0;
logic [1:0] direction = 0;
integer observed_frames, observed_edges;
logic [31:0] value, expected, word_value;
logic    [31:0] random_state;
logic    [15:0] dummy_value = 16'hffff;
realtime        access_accept_time;
`ifndef SPI_DUT
`define SPI_DUT apb4_spi_block_top
`endif
`SPI_DUT u_dut (
    .clk_i              (clk_i),
    .rst_n_i            (rst_n_i),
    .clock_hz_i         (clock_hz_i),
    .origin_i           (origin_i),
    .request_i          (request_i),
    .channel_i          (channel_i),
    .credit_valid_i     (credit_valid_i),
    .credit_retire_i    (credit_retire_i),
    .dma_start_pending_i(dma_start_pending_i),
    .dma_status_i       (dma_status_i),
    .dma_error_i        (dma_error_i),
    .user_select_i      (user_select_i),
    .handoff_i          (handoff_i),
    .alt_enable_i       (alt_enable_i),
    .alt_select_i       (alt_select_i),
    .output_enable_i    (output_enable_i),
    .open_drain_i       (open_drain_i),
    .gpio_ready_i       (gpio_ready_i),
    .miso_i             (miso_i),
    .sck_o              (sck_o),
    .mosi_o             (mosi_o),
    .cs_n_o             (cs_n_o),
    .output_enable_o    (output_enable_o),
    .irq_o              (irq_o),
    .credit_commit_o    (credit_commit_o),
    .dma_admit_ready_o  (),
    .session_owned_o    (session_owned),
    .lifecycle_idle_o   (lifecycle_idle),
    .paddr_i            (paddr_i),
    .pwdata_i           (pwdata_i),
    .pstrb_i            (pstrb_i),
    .psel_i             (psel_i),
    .penable_i          (penable_i),
    .pwrite_i           (pwrite_i),
    .prdata_o           (prdata_o),
    .pready_o           (pready_o),
    .pslverr_o          (pslverr_o)
);
spi_pin_bfm u_model (
    .divider_i  (model_divider),
    .setup_i    (model_setup),
    .hold_i     (model_hold),
    .inactive_i (model_inactive),
    .segment_i  (model_segment),
    .pause_i    (model_pause),
    .faults_o   (model_faults),
    .dummy_i    (dummy_value),
    .clk_i      (clk_i),
    .begin_i    (model_begin),
    .enabled_i  (model_enable),
    .abort_i    (model_abort),
    .cpol_i     (cpol),
    .cpha_i     (cpha),
    .lsb_i      (lsb),
    .frame16_i  (frame16),
    .direction_i(direction),
    .cs_n_i     (cs_n_o),
    .sck_i      (sck_o),
    .mosi_i     (mosi_o),
    .miso_o     (miso_i),
    .frames_o   (observed_frames),
    .edges_o    (observed_edges)
);
// Registered-APB first access edge is the side-effect edge. Observe only
// public bus signals; response completion remains checked by access().
always @(posedge clk_i) begin
  model_segment <= 0;
  if (!rst_n_i || !model_enable) model_abort <= 0;
  else begin
    if (psel_i && penable_i && !pready_o && pwrite_i && paddr_i == 32'h18) begin
      if (pwdata_i == 8) model_segment <= 1;
      if (pwdata_i == 32) model_abort <= 1;
    end
    if (!model_begin && model_faults != 0)
      $fatal(1, "SPI pin checker faults=%h edges=%0d", model_faults, observed_edges);
  end
end
task automatic access (input logic write_access, input logic [11:0] offset, input logic [31:0] data,
                       input logic [3:0] strobe, input logic error_expected,
                       output logic [31:0] result_data);
  @(negedge clk_i);
  psel_i    = 1;
  penable_i = 0;
  pwrite_i  = write_access;
  paddr_i   = {20'd0, offset};
  pwdata_i  = data;
  pstrb_i   = strobe;
  @(negedge clk_i);
  penable_i = 1;
  for (integer timeout_cycles = 0; !pready_o; timeout_cycles++) begin
    if (timeout_cycles == 3) $fatal(1, "SPI APB response exceeded local bound");
    @(negedge clk_i);
  end
  if (pslverr_o !== error_expected)
    $fatal(
        1, "SPI APB offset=%h data=%h error=%b expected=%b", offset, data, pslverr_o, error_expected
    );
  result_data = prdata_o;
  @(posedge clk_i);
  access_accept_time = $realtime;
  @(negedge clk_i);
  psel_i    = 0;
  penable_i = 0;
  @(negedge clk_i);
endtask
task automatic wr(input logic [11:0] offset, input logic [31:0] data, input logic err);
  logic [31:0] unused_data;
  access (1, offset, data, 4'hf, err, unused_data);
  if (!err) begin
    case (offset)
      12'h024: model_divider = data[15:0];
      12'h028: model_setup = data[15:0];
      12'h02c: model_hold = data[15:0];
      12'h030: model_inactive = data[15:0];
      default: ;
    endcase
  end
endtask
task automatic rd(input logic [11:0] offset, output logic [31:0] data);
  access (0, offset, 0, 0, 0, data);
endtask
task automatic reset_dut;
  model_enable        = 0;
  model_abort         = 0;
  model_pause         = 0;
  model_divider       = 1;
  model_setup         = 1;
  model_hold          = 1;
  model_inactive      = 1;
  rst_n_i             = 0;
  origin_i            = 0;
  request_i           = 0;
  channel_i           = 0;
  credit_valid_i      = 0;
  credit_retire_i     = 0;
  dma_status_i        = 0;
  dma_start_pending_i = 0;
  dma_error_i         = 0;
  user_select_i       = 0;
  handoff_i           = 0;
  open_drain_i        = 0;
  alt_enable_i        = 32'hd8000000;
  alt_select_i        = 32'hd0000000;
  output_enable_i     = 0;
  gpio_ready_i        = 1;
  clock_hz_i          = 24000000;
  repeat (3) @(negedge clk_i);
  rst_n_i = 1;
  repeat (3) @(negedge clk_i);
endtask
task automatic wait_state(input integer state_value);
  integer cycles;
  logic   reached;
  cycles  = 0;
  reached = 0;
  while (!reached && cycles < 3000000) begin
    rd(12'h01c, value);
    reached = value[3:0] == 4'(state_value);
    cycles++;
  end
  if (!reached) $fatal(1, "SPI state timeout wanted=%0d", state_value);
endtask
task automatic begin_model;
  @(posedge clk_i);
  model_begin  = 1;
  model_enable = 1;
  @(posedge clk_i);
  model_begin = 0;
endtask
task automatic segment_test(input integer count, input integer divider);
  integer words;
  $display("SPI_P1_CASE time=%0t mode=%0d%0d width16=%0d order=%0d dir=%0d count=%0d div=%0d",
           $time, cpol, cpha, frame16, lsb, direction, count, divider);
  reset_dut();
  wr(12'h020, {27'd0, 1'b0, (direction != 0), lsb, cpha, cpol}, 0);
  wr(12'h024, 32'(divider), 0);
  wr(12'h034, {29'd0, direction, frame16}, 0);
  wr(12'h038, 32'(count), 0);
  wr(12'h03c, {16'd0, dummy_value}, 0);
  wr(12'h018, 1, 0);
  wait_state(1);
  wr(12'h018, 4, 0);
  words = (count * (frame16 ? 2 : 1) + 3) / 4;
  if (direction != 2)
    for (integer index = 0; index < words; index++)
      wr(12'h04c, 32'h80ff017e ^ (32'(index) * 32'h01020408), 0);
  begin_model();
  wr(12'h018, 8, 0);
  wait_state(1);
  if (observed_frames != count || observed_edges != 2 * count * (frame16 ? 16 : 8))
    $fatal(1, "SPI edge/frame mismatch: %0d/%0d", observed_frames, observed_edges);
  if (direction != 0) begin
    rd(12'h01c, value);
    if (!value[6] || value[7]) $fatal(1, "RX data lost pending ownership");
    wr(12'h018, 4, 1);
    for (integer index = 0; index < words; index++) begin
      expected = 0;
      for (integer lane = 0; lane < (frame16 ? 2 : 4); lane++) begin
        if (index * (frame16 ? 2 : 4) + lane < count)
          expected |= (32'(16'ha5c3^(16'(index*(frame16?2:4)+lane)*16'h1237)) &
                         (frame16?32'hffff:32'hff)) << (lane*(frame16?16:8));
      end
      rd(12'h050, word_value);
      if (word_value !== expected)
        $fatal(1, "SPI RX packing got=%h expected=%h", word_value, expected);
    end
  end
  rd(12'h01c, value);
  if (value[6] || !value[7]) $fatal(1, "SPI cleanup failed");
  rd(12'h074, value);
  if (value != 32'(count)) $fatal(1, "SPI wrong completed frame count");
  rd(12'h060, value);
  if (value[1:0] != 2'b11) $fatal(1, "SPI missing wire completion events");
  model_enable = 0;
endtask
task automatic wait_pressure(input integer status_bit);
  integer attempts, saved_edges;
  logic reached;
  logic [31:0] status_value, before_stalls, after_stalls;
  attempts = 0;
  reached  = 0;
  while (!reached && attempts < 20000) begin
    rd(12'h01c, status_value);
    reached = status_value[status_bit];
    attempts++;
  end
  if (!reached) $fatal(1, "SPI pressure state not reached bit=%0d", status_bit);
  model_pause = 1;
  saved_edges = observed_edges;
  rd(status_bit == 8 ? 12'h088 : 12'h08c, before_stalls);
  repeat (31) @(negedge clk_i);
  rd(status_bit == 8 ? 12'h088 : 12'h08c, after_stalls);
  if (cs_n_o || sck_o != cpol || observed_edges != saved_edges ||
      saved_edges % (frame16 ? 32 : 16) != 0 || after_stalls - before_stalls < 31)
    $fatal(1, "SPI pressure did not pause at a complete frame boundary");
  $display("SPI_PRESSURE_WAIT bit=%0d edges=%0d cycles=%0d", status_bit, saved_edges,
           after_stalls - before_stalls);
endtask

task automatic checked_abort;
  integer bound_cycles, cycles, saved_frames;
  realtime accepted;
  logic [31:0] events_value, frames_value;
  saved_frames = observed_frames;
  wr(12'h064, 4, 0);
  wr(12'h060, 63, 0);
  wr(12'h018, 32, 0);
  accepted     = access_accept_time;
  bound_cycles = 2 * integer'(model_divider) + integer'(model_hold) + integer'(model_inactive) + 2;
  cycles       = 0;
  while (!irq_o && cycles < bound_cycles) begin
    @(negedge clk_i);
    cycles++;
  end
  if (!irq_o || $realtime - accepted > real'(bound_cycles) * 41.666 + 0.01 ||
      !cs_n_o || sck_o != cpol)
    $fatal(1, "SPI pressure/phase abort deadline");
  rd(12'h060, events_value);
  rd(12'h074, frames_value);
  if (events_value[3:0] != 4 || observed_frames != saved_frames ||
      frames_value != 32'(saved_frames))
    $fatal(1, "SPI aborted transfer changed successful frame/event counts");
  wr(12'h018, 64, 0);
  rd(12'h01c, events_value);
  if (!events_value[5] || events_value[6] || output_enable_o)
    $fatal(1, "SPI pressure recovery lost reservation or retained data");
  model_pause  = 0;
  model_enable = 0;
endtask

task automatic pressure_test(input integer abort_kind);
  integer count, words, polls;
  logic [31:0] levels, received_word, expected_word, status_value;
  count = frame16 ? 19 : 37;
  words = 10;
  reset_dut();
  wr(12'h020, {27'd0, 1'b0, (direction != 0), lsb, cpha, cpol}, 0);
  wr(12'h024, 1 + 2 * 32'(cpol) + 4 * 32'(cpha), 0);
  wr(12'h034, {29'd0, direction, frame16}, 0);
  wr(12'h038, 32'(count), 0);
  wr(12'h03c, {16'd0, dummy_value}, 0);
  wr(12'h018, 1, 0);
  wait_state(1);
  wr(12'h018, 4, 0);
  if (direction != 2) wr(12'h04c, 32'h80ff017e, 0);
  begin_model();
  wr(12'h018, 8, 0);
  if (direction != 2) begin
    wait_pressure(8);
    if (abort_kind != 1) begin
      model_pause = 0;
      for (integer index = 1; index < words; index++) begin
        rd(12'h05c, levels);
        polls = 0;
        while (levels[3:0] == 8 && polls < 20000) begin
          rd(12'h05c, levels);
          polls++;
        end
        if (levels[3:0] == 8) $fatal(1, "SPI TX service did not resume");
        wr(12'h04c, 32'h80ff017e ^ (32'(index) * 32'h01020408), 0);
      end
    end
  end
  if (abort_kind == 1) checked_abort();
  else begin
    if (direction != 0) begin
      wait_pressure(9);
      rd(12'h05c, levels);
      if (levels[11:8] != 8) $fatal(1, "SPI RX pause did not reach a full FIFO");
    end
    if (abort_kind == 2) checked_abort();
    else begin
      model_pause = 0;
      if (direction != 0) begin
        for (integer index = 0; index < words; index++) begin
          rd(12'h05c, levels);
          polls = 0;
          while (levels[11:8] == 0 && polls < 20000) begin
            rd(12'h05c, levels);
            polls++;
          end
          if (levels[11:8] == 0) $fatal(1, "SPI RX service did not resume");
          rd(12'h050, received_word);
          expected_word = 0;
          for (integer lane = 0; lane < (frame16 ? 2 : 4); lane++) begin
            if (index * (frame16 ? 2 : 4) + lane < count)
              expected_word |= (32'(16'ha5c3 ^ (16'(index * (frame16 ? 2 : 4) + lane) *
                                  16'h1237)) & (frame16 ? 32'hffff : 32'hff)) <<
                                  (lane * (frame16 ? 16 : 8));
          end
          if (received_word !== expected_word) $fatal(1, "SPI pressure RX data/tail mismatch");
          repeat (23 + index % 3) @(negedge clk_i);
        end
      end
      wait_state(1);
      rd(12'h01c, status_value);
      if (status_value[6] || !status_value[7] || observed_frames != count ||
          observed_edges != count * (frame16 ? 32 : 16))
        $fatal(1, "SPI pressure cleanup");
      rd(12'h074, status_value);
      if (status_value != 32'(count)) $fatal(1, "SPI pressure frame accounting");
      rd(12'h07c, status_value);
      if (status_value != (direction == 2 ? 0 : 10)) $fatal(1, "SPI pressure TX accounting");
      rd(12'h080, status_value);
      if (status_value != (direction == 0 ? 0 : 10)) $fatal(1, "SPI pressure RX production");
      rd(12'h084, status_value);
      if (status_value != (direction == 0 ? 0 : 10)) $fatal(1, "SPI pressure RX removal");
      rd(12'h060, status_value);
      if (status_value[3:0] != 3) $fatal(1, "SPI pressure terminal events");
      model_enable = 0;
    end
  end
  $display(
      "SPI_PRESSURE_CASE mode=%0d%0d width16=%0d order=%0d dir=%0d abort=%0d frames=%0d words=10",
      cpol, cpha, frame16, lsb, direction, abort_kind, count);
endtask

task automatic phase_abort_test(input integer delay_cycles);
  reset_dut();
  direction = 0;
  wr(12'h020, {29'd0, lsb, cpha, cpol}, 0);
  wr(12'h024, 7, 0);
  wr(12'h034, {31'd0, frame16}, 0);
  wr(12'h038, 5, 0);
  wr(12'h018, 1, 0);
  wait_state(1);
  wr(12'h018, 4, 0);
  wr(12'h04c, 32'h80ff017e, 0);
  begin_model();
  wr(12'h018, 8, 0);
  while (sck_o == cpol) @(negedge clk_i);
  repeat (delay_cycles) @(negedge clk_i);
  checked_abort();
  $display("SPI_PHASE_ABORT mode=%0d%0d width16=%0d delay=%0d", cpol, cpha, frame16, delay_cycles);
endtask

initial begin
  if (TestKind == 0 || TestKind == 3) begin
    for (integer mode = 0; mode < 4; mode++)
    for (integer width_case = 0; width_case < 2; width_case++)
    for (integer order = 0; order < 2; order++)
    for (integer dir = 0; dir < 3; dir++) begin
      cpol      = 1'(mode / 2);
      cpha      = 1'(mode % 2);
      frame16   = 1'(width_case);
      lsb       = 1'(order);
      direction = 2'(dir);
      segment_test(5, 1 + mode);
    end
    cpol      = 0;
    cpha      = 0;
    frame16   = 0;
    lsb       = 0;
    direction = 1;
    if (TestKind == 0) begin
      segment_test(1, 65535);
      // Fixed seed; the oracle still decodes pins independently of the DUT.
      random_state = 32'h53504931;
      for (integer sample_index = 0; sample_index < 256; sample_index++) begin
        random_state = (random_state >> 1) ^ ((random_state[0] != 0) ? 32'h80200003 : 32'd0);
        cpol         = random_state[0];
        cpha         = random_state[1];
        lsb          = random_state[2];
        frame16      = random_state[3];
        direction    = 2'(random_state[5:4] % 3);
        dummy_value  = random_state[31:16];
        segment_test(1 + integer'(random_state[9:6]), 1 + integer'(random_state[11:10]));
      end
    end
    // Complete-core stress also runs against each PDK's mapped netlist.
    for (integer mode = 0; mode < 4; mode++)
    for (integer width_case = 0; width_case < 2; width_case++)
    for (integer order = 0; order < 2; order++)
    for (integer dir = 0; dir < 3; dir++) begin
      cpol      = 1'(mode / 2);
      cpha      = 1'(mode % 2);
      frame16   = 1'(width_case);
      lsb       = 1'(order);
      direction = 2'(dir);
      pressure_test(0);
    end
    for (integer mode = 0; mode < 4; mode++)
    for (integer width_case = 0; width_case < 2; width_case++) begin
      cpol      = 1'(mode / 2);
      cpha      = 1'(mode % 2);
      frame16   = 1'(width_case);
      lsb       = 0;
      direction = 0;
      pressure_test(1);
      direction = 2;
      pressure_test(2);
      for (integer delay_cycles = 0; delay_cycles < 14; delay_cycles++)
      phase_abort_test(delay_cycles);
    end
  end else if (TestKind == 1) begin
    reset_dut();
    rd(12'h000, value);
    if (value != 32'h53504930) $fatal(1, "SPI ID");
    rd(12'h008, value);
    if (value != 32'h3f7f) $fatal(1, "SPI capability");
    wr(12'h064, 256, 0);
    if (!irq_o) $fatal(1, "SPI low-watermark level missing");
    wr(12'h060, 63, 0);
    if (!irq_o) $fatal(1, "SPI W1C incorrectly cleared watermark level");
    wr(12'h064, 0, 0);
    wr(12'h000, 0, 1);
    wr(12'h024, 0, 1);
    wr(12'h020, 24, 1);
    wr(12'h038, 0, 1);
    wr(12'h03c, 32'h10000, 1);
    wr(12'h018, 3, 1);
    wr(12'h018, 8, 1);
    access (1, 12'h020, 0, 4'h1, 1, value);
    access (0, 12'h001, 0, 0, 1, value);
    access (0, 12'h100, 0, 0, 1, value);
    access (0, 12'h018, 0, 0, 1, value);
    origin_i = 2;
    access (0, 12'h000, 0, 0, 1, value);
    origin_i = 0;
    wr(12'h018, 1, 0);
    wait_state(1);
    wr(12'h018, 4, 1);  // Reset FRAME_COUNT is still unconfigured.
    for (integer width_case = 0; width_case < 2; width_case++) begin
      wr(12'h034, 32'(width_case), 0);
      wr(12'h038, 32'hffffffff, 0);
      wr(12'h018, 4, 1);
      wr(12'h038, width_case == 0 ? 32'hfffffffd : 32'h7fffffff, 0);
      wr(12'h018, 4, 1);
    end
    wr(12'h034, 0, 0);
    wr(12'h020, 0, 1);
    wr(12'h038, 32'hffffffff, 0);
    wr(12'h018, 4, 1);
    wr(12'h038, 40, 0);
    wr(12'h018, 4, 0);
    for (integer index = 0; index < 8; index++) wr(12'h04c, 32'(index), 0);
    wr(12'h04c, 32'hdeadbeef, 1);
    rd(12'h07c, value);
    if (value != 8) $fatal(1, "SPI FIFO quota changed on error");
    wr(12'h054, 0, 1);
    access (0, 12'h050, 0, 0, 1, value);
    wr(12'h018, 32, 0);
    wait_state(8);
    repeat (8) @(negedge clk_i);
    wr(12'h018, 64, 0);
    rd(12'h01c, value);
    if (!value[5] || value[3:0] != 0) $fatal(1, "SPI recovery ownership");
    wr(12'h018, 128, 1);
    alt_enable_i    = 0;
    output_enable_i = 0;
    wr(12'h018, 128, 0);
    wr(12'h018, 256, 0);
    reset_dut();
    wr(12'h038, 1, 0);
    wr(12'h018, 1, 0);
    wait_state(1);
    wr(12'h018, 4, 0);
    wr(12'h018, 8, 0);
    repeat (4) @(negedge clk_i);
    wr(12'h060, 16, 0);
    rd(12'h060, value);
    if (!value[4]) $fatal(1, "SPI event did not dominate W1C");
    wr(12'h018, 32, 0);
    repeat (8) @(negedge clk_i);
    wr(12'h018, 64, 0);
    // A source-qualified credit is consumed only once, and CPU cannot steal it.
    reset_dut();
    wr(12'h040, 32'h80000003, 0);
    wr(12'h038, 8, 0);
    wr(12'h018, 1, 0);
    wait_state(1);
    wr(12'h018, 4, 0);
    credit_valid_i = 1;
    wr(12'h054, 32'h80ff017e, 1);
    wr(12'h04c, 32'h80ff017e, 1);
    origin_i  = 1;
    request_i = 16;
    channel_i = 3;
    wr(12'h054, 32'h80ff017e, 0);
    credit_retire_i = 1;
    @(negedge clk_i);
    credit_retire_i = 0;
    wr(12'h054, 32'h81fd0576, 0);
    wr(12'h054, 32'hdeadbeef, 1);
    origin_i        = 0;
    credit_valid_i  = 0;
    credit_retire_i = 1;
    repeat (8) @(negedge clk_i);
    credit_retire_i = 0;
    rd(12'h07c, value);
    if (value != 2) $fatal(1, "SPI duplicate credit mutated FIFO");
    rd(12'h06c, value);
    if (value != 4) $fatal(1, "SPI credit fault not latched");
    wr(12'h018, 64, 0);
    // A consumed credit remains transport-busy until its terminal retirement.
    reset_dut();
    wr(12'h040, 32'h80000003, 0);
    wr(12'h038, 1, 0);
    wr(12'h018, 1, 0);
    wait_state(1);
    wr(12'h018, 4, 0);
    origin_i       = 1;
    request_i      = 16;
    channel_i      = 3;
    credit_valid_i = 1;
    wr(12'h054, 32'h80ff017e, 0);
    origin_i       = 0;
    credit_valid_i = 0;
    wr(12'h018, 8, 0);
    wait_state(1);
    rd(12'h01c, value);
    if (!value[6] || value[7] || value[11]) $fatal(1, "SPI retired credit too early");
    wr(12'h018, 4, 1);
    wr(12'h040, 0, 1);
    credit_retire_i = 1;
    @(negedge clk_i);
    credit_retire_i = 0;
    repeat (2) @(negedge clk_i);
    rd(12'h01c, value);
    if (value[6] || !value[7] || !value[11])
      $fatal(1, "SPI credit retirement did not clean segment");
    for (integer width_case = 0; width_case < 2; width_case++) begin
      reset_dut();
      wr(12'h034, 32'(width_case), 0);
      wr(12'h038, width_case == 0 ? 32'hfffffffc : 32'h7ffffffe, 0);
      wr(12'h018, 1, 0);
      wait_state(1);
      wr(12'h018, 4, 0);
      rd(12'h09c, value);
      if (value != 32'hfffffffc) $fatal(1, "SPI maximum payload arithmetic");
      rd(12'h078, value);
      if (value != 32'h3fffffff) $fatal(1, "SPI maximum quota arithmetic");
      wr(12'h018, 32, 0);
      repeat (8) @(negedge clk_i);
      wr(12'h018, 64, 0);
    end
  end else begin
    for (integer target = 0; target < 8; target++) begin
      integer  bound_cycles;
      realtime abort_accepted;
      reset_dut();
      wr(12'h024, 4, 0);
      if (target == 3) wr(12'h028, 32, 0);
      if (target == 5) wr(12'h02c, 32, 0);
      if (target == 7) wr(12'h030, 32, 0);
      wr(12'h064, 4, 0);
      wr(12'h034, target == 6 ? 8 : 0, 0);
      wr(12'h038, 1, 0);
      wr(12'h018, 1, 0);
      if (target != 7) wait_state(1);
      if (target == 0) wr(12'h018, 2, 0);
      if (target >= 2 && target <= 6) wr(12'h018, 4, 0);
      if (target >= 3 && target <= 6) begin
        wr(12'h04c, 32'h80ff017e, 0);
        wr(12'h018, 8, 0);
      end
      wait_state(target);
      wr(12'h060, 63, 0);
      wr(12'h018, 32, 0);
      abort_accepted = access_accept_time;
      bound_cycles   = 8 + (target == 5 ? 32 : 1) + (target == 7 ? 32 : 1) + 2;
      for (integer cycles = 0; cycles < bound_cycles && !irq_o; cycles++) @(negedge clk_i);
      if (!irq_o || $realtime - abort_accepted > real'(bound_cycles) * 41.666 + 0.01)
        $fatal(1, "SPI ABORT deadline state=%0d", target);
      if (!cs_n_o || sck_o) $fatal(1, "SPI ABORT wire state=%0d", target);
      if (target == 0 && output_enable_o) $fatal(1, "SPI ABORT re-enabled disabled outputs");
      wr(12'h018, 64, 0);
    end
    for (integer abort_delay = 0; abort_delay < 40; abort_delay++) begin
      reset_dut();
      wr(12'h038, 5, 0);
      wr(12'h018, 1, 0);
      wait_state(1);
      wr(12'h018, 4, 0);
      wr(12'h04c, 32'habcdef01, 0);
      wr(12'h018, 8, 0);
      repeat (abort_delay) @(negedge clk_i);
      wr(12'h018, 32, 0);
      repeat (8) @(negedge clk_i);
      if (!cs_n_o || sck_o) $fatal(1, "SPI abort wire bound");
      rd(12'h060, value);
      if (value[1:0] != 0 || !value[2]) $fatal(1, "SPI aborted segment reported success");
      dma_status_i = 1;
      wr(12'h018, 64, 1);
      dma_status_i = 0;
      wr(12'h018, 64, 0);
    end
    // Maximum CS delays are exercised on pins, not only read back from CSRs.
    reset_dut();
    wr(12'h038, 1, 0);
    wr(12'h018, 1, 0);
    wait_state(1);
    wr(12'h018, 4, 0);
    wr(12'h018, 32, 0);
    gpio_ready_i = 0;
    repeat (3) @(negedge clk_i);
    rd(12'h06c, value);
    if (value != 2) $fatal(1, "SPI closing did not monitor GPIO readiness");
    if (output_enable_o || !cs_n_o) $fatal(1, "SPI closing guard clamp");
    wr(12'h018, 64, 0);
    rd(12'h01c, value);
    if (value[3:0] != 0 || !value[5]) $fatal(1, "SPI persistent closing guard recovery");
    // Maximum CS delays are exercised on pins, not only read back from CSRs.
    begin
      realtime asserted_at, first_edge, last_edge, released_at;
      reset_dut();
      cpol      = 0;
      cpha      = 0;
      lsb       = 0;
      frame16   = 0;
      direction = 0;
      for (integer offset = 40; offset <= 48; offset += 4) begin
        wr(12'(offset), 0, 1);
        wr(12'(offset), 65535, 0);
      end
      wr(12'h038, 1, 0);
      wr(12'h018, 1, 0);
      wait_state(1);
      rd(12'h060, value);
      if (value[1:0] != 0) $fatal(1, "SPI initial gap emitted DONE");
      wr(12'h018, 4, 0);
      wr(12'h04c, 32'h80ff017e, 0);
      begin_model();
      fork
        begin
          @(negedge cs_n_o);
          asserted_at = $realtime;
          @(posedge sck_o);
          first_edge = $realtime;
          if (first_edge - asserted_at < 65535.0 * 41.666 - 0.01)
            $fatal(1, "SPI short maximum setup");
          repeat (7) @(posedge sck_o);
          @(negedge sck_o);
          last_edge = $realtime;
          @(posedge cs_n_o);
          released_at = $realtime;
          if (released_at - last_edge < 65535.0 * 41.666 - 0.01)
            $fatal(1, "SPI short maximum hold");
        end
        begin
          wr(12'h018, 8, 0);
          wait_state(1);
        end
      join
      if ($realtime - released_at < 65535.0 * 41.666 - 0.01)
        $fatal(1, "SPI short maximum inactive gap");
      model_enable = 0;
    end
    // Held-CS transitions preserve mode/timing and wait for segment cleanup.
    reset_dut();
    wr(12'h038, 3, 0);
    wr(12'h018, 1, 0);
    wait_state(1);
    wr(12'h018, 4, 0);
    wr(12'h04c, 32'h80ff017e, 0);
    wr(12'h018, 8, 0);
    wait_state(4);
    rst_n_i = 0;
    #1;
    if (output_enable_o || !cs_n_o) $fatal(1, "SPI asynchronous reset did not clamp pads");
    repeat (2) @(negedge clk_i);
    rst_n_i = 1;
    rd(12'h01c, value);
    if (value[6:0] != 0) $fatal(1, "SPI reset retained a traffic epoch");
    rd(12'h05c, value);
    if (value != 0) $fatal(1, "SPI reset retained FIFO validity");
    // Held-CS transitions preserve mode/timing and wait for segment cleanup.
    reset_dut();
    cpol      = 0;
    cpha      = 0;
    lsb       = 0;
    frame16   = 0;
    direction = 0;
    wr(12'h034, 8, 0);
    wr(12'h038, 1, 0);
    wr(12'h018, 1, 0);
    wait_state(1);
    wr(12'h018, 4, 0);
    wr(12'h04c, 32'h80ff017e, 0);
    begin_model();
    wr(12'h018, 8, 0);
    wait_state(6);
    model_enable = 0;
    if (cs_n_o || observed_frames != 1 || observed_edges != 16) $fatal(1, "SPI held command");
    wr(12'h024, 2, 1);
    wr(12'h034, 9, 0);
    wr(12'h038, 1, 0);
    frame16 = 1;
    wr(12'h018, 4, 0);
    wr(12'h04c, 32'h80ff017e, 0);
    begin_model();
    wr(12'h018, 8, 0);
    wait_state(6);
    model_enable = 0;
    if (cs_n_o || observed_frames != 1 || observed_edges != 32)
      $fatal(1, "SPI held frame-width switch");
    wr(12'h018, 16, 0);
    wait_state(1);
    wr(12'h018, 2, 0);
    rd(12'h01c, value);
    if (!value[5] || output_enable_o) $fatal(1, "SPI DISABLE reservation");
    reset_dut();
    wr(12'h038, 1, 0);
    wr(12'h018, 1, 0);
    wait_state(1);
    wr(12'h018, 4, 0);
    handoff_i = 32'h08000000;
    repeat (3) @(negedge clk_i);
    if (output_enable_o || !cs_n_o) $fatal(1, "SPI guard clamp");
    rd(12'h06c, value);
    if (value != 1) $fatal(1, "SPI first fault");
    wr(12'h018, 64, 0);
    repeat (3) @(negedge clk_i);
    rd(12'h01c, value);
    if (value[3:0] != 0 || !value[5]) $fatal(1, "SPI repeated guard fault");
    // Display D/C is ordinary GPIO output; an invalid electrical mode closes ownership.
    reset_dut();
    alt_enable_i[30]    = 0;
    output_enable_i[30] = 1;
    wr(12'h020, 16, 0);
    wr(12'h018, 1, 0);
    wait_state(1);
    rd(12'h090, value);
    if (value != 32'hd8000000) $fatal(1, "SPI display claim mask");
    open_drain_i[30] = 1;
    repeat (3) @(negedge clk_i);
    if (output_enable_o) $fatal(1, "SPI display electrical guard");
    wr(12'h018, 64, 0);
  end
  if (TestKind == 3) begin
    reset_dut();
    wr(12'h024, 0, 1);
    wr(12'h038, 1, 0);
    wr(12'h018, 1, 0);
    wait_state(1);
    wr(12'h018, 4, 0);
    wr(12'h018, 8, 0);
    wait_state(4);
    wr(12'h018, 32, 0);
    repeat (8) @(negedge clk_i);
    if (!cs_n_o || sck_o) $fatal(1, "SPI netlist abort bound");
    wr(12'h018, 64, 0);
    alt_enable_i    = 0;
    output_enable_i = 0;
    wr(12'h018, 128, 0);
    rd(12'h01c, value);
    if (value[5]) $fatal(1, "SPI netlist release");
  end
  $display("SPI_P1_PASS %s", TestName);
  $finish;
end
initial begin
  #100000000;
  $fatal(1, "SIM_TEST_TIMEOUT SPI fixture");
end
