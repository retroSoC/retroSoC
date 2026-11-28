logic s_p4_logic_active = $test$plusargs(
    "piolite_p4_scenario_LOGIC_CAPTURE"
) || $test$plusargs(
    "piolite_p4_scenario_CONTENTION"
);
logic s_p4_logic_owned_q;
logic [7:0] s_p4_logic_value_q;
logic [4:0] s_p4_logic_pc_q;
logic [31:0] s_p4_logic_retired_q;
integer s_p4_logic_epoch;
integer s_p4_logic_cycle;
integer s_p4_logic_last_sample;
integer s_p4_logic_samples[3];
integer s_p4_logic_first[3];
integer s_p4_logic_last[3];
integer s_p4_logic_min_period[3];
integer s_p4_logic_max_period[3];
logic [31:0] s_p4_logic_fnv[3];
logic [31:0] s_p4_logic_current_fnv;
integer s_p4_logic_current_samples;
integer s_p4_logic_current_first;
integer s_p4_logic_current_last;
integer s_p4_logic_current_min;
integer s_p4_logic_current_max;
wire s_p4_logic_owned = s_p4_logic_active && (&u_dut.u_soc.s_piolite_gpio_user_status[15:8]);

assign s_gpio_8  = s_p4_logic_owned ? s_p4_logic_value_q[0] : 1'bz;
assign s_gpio_9  = s_p4_logic_owned ? s_p4_logic_value_q[1] : 1'bz;
assign s_gpio_10 = s_p4_logic_owned ? s_p4_logic_value_q[2] : 1'bz;
assign s_gpio_11 = s_p4_logic_owned ? s_p4_logic_value_q[3] : 1'bz;
assign s_gpio_12 = s_p4_logic_owned ? s_p4_logic_value_q[4] : 1'bz;
assign s_gpio_13 = s_p4_logic_owned ? s_p4_logic_value_q[5] : 1'bz;
assign s_gpio_14 = s_p4_logic_owned ? s_p4_logic_value_q[6] : 1'bz;
assign s_gpio_15 = s_p4_logic_owned ? s_p4_logic_value_q[7] : 1'bz;

function automatic [7:0] s_p4_logic_next(input [7:0] value, input integer pattern);
  if (pattern == 0) s_p4_logic_next = value + 8'd1;
  else if (pattern == 1) s_p4_logic_next = (value >> 1) ^ (value[0] ? 8'hb8 : 8'd0);
  else s_p4_logic_next = value + 8'd73;
endfunction

initial begin
  s_p4_logic_owned_q         = 1'b0;
  s_p4_logic_value_q         = 8'd0;
  s_p4_logic_pc_q            = 5'd0;
  s_p4_logic_retired_q       = 32'd0;
  s_p4_logic_epoch           = -1;
  s_p4_logic_cycle           = 0;
  s_p4_logic_last_sample     = 0;
  s_p4_logic_current_fnv     = 32'h811c9dc5;
  s_p4_logic_current_samples = 0;
  s_p4_logic_current_first   = 0;
  s_p4_logic_current_last    = 0;
  s_p4_logic_current_min     = 1000000;
  s_p4_logic_current_max     = 0;
  for (integer index = 0; index < 3; index++) begin
    s_p4_logic_samples[index]    = 0;
    s_p4_logic_first[index]      = 0;
    s_p4_logic_last[index]       = 0;
    s_p4_logic_min_period[index] = 0;
    s_p4_logic_max_period[index] = 0;
    s_p4_logic_fnv[index]        = 32'd0;
  end
end

always @(negedge s_clk) begin
  if (s_p4_logic_active) begin
    if (s_p4_logic_owned && !s_p4_logic_owned_q) begin
      s_p4_logic_epoch = s_p4_logic_epoch + 1;
      if (s_p4_logic_epoch > 2) $fatal(1, "SIM_TEST_FAIL P4 logic acquisition count");
      s_p4_logic_cycle           = 0;
      s_p4_logic_last_sample     = 0;
      s_p4_logic_current_fnv     = 32'h811c9dc5;
      s_p4_logic_current_samples = 0;
      s_p4_logic_current_first   = 0;
      s_p4_logic_current_last    = 0;
      s_p4_logic_current_min     = 1000000;
      s_p4_logic_current_max     = 0;
      case (s_p4_logic_epoch)
        0:       s_p4_logic_value_q = 8'h31;
        1:       s_p4_logic_value_q = 8'h01;
        default: s_p4_logic_value_q = 8'h20;
      endcase
    end else if (!s_p4_logic_owned && s_p4_logic_owned_q) begin
      if (s_p4_logic_current_samples != 32768)
        $fatal(1, "SIM_TEST_FAIL P4 logic sample count %0d", s_p4_logic_current_samples);
      s_p4_logic_samples[s_p4_logic_epoch]    = s_p4_logic_current_samples;
      s_p4_logic_first[s_p4_logic_epoch]      = s_p4_logic_current_first;
      s_p4_logic_last[s_p4_logic_epoch]       = s_p4_logic_current_last;
      s_p4_logic_min_period[s_p4_logic_epoch] = s_p4_logic_current_min;
      s_p4_logic_max_period[s_p4_logic_epoch] = s_p4_logic_current_max;
      s_p4_logic_fnv[s_p4_logic_epoch]        = s_p4_logic_current_fnv;
    end else if (s_p4_logic_owned) begin
      s_p4_logic_cycle = s_p4_logic_cycle + 1;
      if ((u_dut.u_soc.u_piolite.u_ctrl.runtime[0].retired_count != s_p4_logic_retired_q) &&
          ((s_p4_logic_pc_q == 5'd4) || (s_p4_logic_pc_q == 5'd6))) begin
        if (s_p4_logic_current_samples >= 32768) $fatal(1, "SIM_TEST_FAIL P4 logic extra sample");
        if (s_p4_logic_current_samples == 0) begin
          s_p4_logic_current_first = s_gpio[15:8];
        end else begin
          if ((s_p4_logic_cycle - s_p4_logic_last_sample) != 24)
            $fatal(
                1, "SIM_TEST_FAIL P4 logic period %0d", s_p4_logic_cycle - s_p4_logic_last_sample
            );
          if ((s_p4_logic_cycle - s_p4_logic_last_sample) < s_p4_logic_current_min)
            s_p4_logic_current_min = s_p4_logic_cycle - s_p4_logic_last_sample;
          if ((s_p4_logic_cycle - s_p4_logic_last_sample) > s_p4_logic_current_max)
            s_p4_logic_current_max = s_p4_logic_cycle - s_p4_logic_last_sample;
        end
        s_p4_logic_current_last    = s_gpio[15:8];
        s_p4_logic_current_fnv     = (s_p4_logic_current_fnv ^ s_gpio[15:8]) * 32'd16777619;
        s_p4_logic_current_samples = s_p4_logic_current_samples + 1;
        s_p4_logic_last_sample     = s_p4_logic_cycle;
      end
      if ((s_p4_logic_cycle != 0) && ((s_p4_logic_cycle % 24) == 0))
        s_p4_logic_value_q = s_p4_logic_next(s_p4_logic_value_q, s_p4_logic_epoch);
    end
    s_p4_logic_pc_q      = u_dut.u_soc.u_piolite.u_ctrl.runtime[0].pc;
    s_p4_logic_retired_q = u_dut.u_soc.u_piolite.u_ctrl.runtime[0].retired_count;
    s_p4_logic_owned_q   = s_p4_logic_owned;
  end
end

always @(posedge u_dut.s_test_done) begin
  if (s_p4_logic_active && u_dut.s_test_pass) begin
    if (s_p4_logic_epoch != 2) $fatal(1, "SIM_TEST_FAIL P4 logic epochs %0d", s_p4_logic_epoch);
    for (integer index = 0; index < 3; index++) begin
      if ((s_p4_logic_samples[index] != 32768) || (s_p4_logic_min_period[index] != 24) ||
          (s_p4_logic_max_period[index] != 24))
        $fatal(1, "SIM_TEST_FAIL P4 logic BFM coverage %0d", index);
      $display(
          "PIOLITE_P4_BFM_LOGIC pattern=%0d samples=%0d first=%02x last=%02x fnv=%08x min_period=%0d max_period=%0d",
          index, s_p4_logic_samples[index], s_p4_logic_first[index], s_p4_logic_last[index],
          s_p4_logic_fnv[index], s_p4_logic_min_period[index], s_p4_logic_max_period[index]);
    end
  end
end

logic s_p4_pulse_active = $test$plusargs("piolite_p4_scenario_PULSE");
logic s_p4_pulse_owned_q;
logic s_p4_pulse_level_q;
logic s_p4_pulse_high_seen;
logic s_p4_pulse_high_valid;
logic [4:0] s_p4_pulse_pc_q;
logic [31:0] s_p4_pulse_retired_q;
integer s_p4_pulse_sessions;
integer s_p4_pulse_pairs;
integer s_p4_pulse_cycle;
integer s_p4_pulse_high_start;
integer s_p4_pulse_low_start;
integer s_p4_pulse_high_width;
integer s_p4_pulse_high[6];
integer s_p4_pulse_low[6];
wire s_p4_pulse_owned = s_p4_pulse_active && u_dut.u_soc.s_piolite_gpio_user_status[2];
wire s_p4_pulse_driven = s_p4_pulse_owned && u_dut.u_soc.u_piolite.u_ctrl.runtime[0].output_oe[2];
assign s_gpio_3 = s_p4_pulse_active ? s_gpio_2 : 1'bz;

initial begin
  s_p4_pulse_owned_q    = 1'b0;
  s_p4_pulse_level_q    = 1'b0;
  s_p4_pulse_high_seen  = 1'b0;
  s_p4_pulse_high_valid = 1'b0;
  s_p4_pulse_pc_q       = 5'd0;
  s_p4_pulse_retired_q  = 32'd0;
  s_p4_pulse_sessions   = 0;
  s_p4_pulse_pairs      = 0;
  s_p4_pulse_cycle      = 0;
  s_p4_pulse_high_start = 0;
  s_p4_pulse_low_start  = 0;
  s_p4_pulse_high_width = 0;
  for (integer index = 0; index < 6; index++) begin
    s_p4_pulse_high[index] = 0;
    s_p4_pulse_low[index]  = 0;
  end
end

always @(negedge s_clk) begin
  if (s_p4_pulse_active) begin
    s_p4_pulse_cycle = s_p4_pulse_cycle + 1;
    if (s_p4_pulse_owned && !s_p4_pulse_owned_q) begin
      s_p4_pulse_sessions   = s_p4_pulse_sessions + 1;
      s_p4_pulse_high_seen  = 1'b0;
      s_p4_pulse_high_valid = 1'b0;
      s_p4_pulse_level_q    = s_gpio_2;
      s_p4_pulse_pc_q       = u_dut.u_soc.u_piolite.u_ctrl.runtime[0].pc;
      s_p4_pulse_retired_q  = u_dut.u_soc.u_piolite.u_ctrl.runtime[0].retired_count;
      s_p4_pulse_high_start = s_p4_pulse_cycle;
      s_p4_pulse_low_start  = s_p4_pulse_cycle;
      s_p4_pulse_high_width = 0;
    end
    if ($test$plusargs("piolite_p4_diagnose") && (u_dut.u_soc.u_piolite.u_ctrl.runtime[0].pc == 8))
      $display(
          "P4_PULSE_HIGH session=%0d driven=%b oe=%b pin=%b pcq=%0d retired=%0d prev=%0d",
          s_p4_pulse_sessions,
          s_p4_pulse_driven,
          u_dut.u_soc.u_piolite.u_ctrl.runtime[0].output_oe[2],
          s_gpio_2,
          s_p4_pulse_pc_q,
          u_dut.u_soc.u_piolite.u_ctrl.runtime[0].retired_count,
          s_p4_pulse_retired_q
      );
    if (s_p4_pulse_driven) begin
      if ((u_dut.u_soc.u_piolite.u_ctrl.runtime[0].retired_count != s_p4_pulse_retired_q) &&
          ((s_p4_pulse_pc_q == 5'd8) || (s_p4_pulse_pc_q == 5'd12))) begin
        if (s_p4_pulse_high_seen) begin
          if ($test$plusargs("piolite_p4_diagnose"))
            $display(
                "P4_PULSE_PAIR session=%0d index=%0d high=%0d low=%0d",
                s_p4_pulse_sessions,
                s_p4_pulse_pairs,
                s_p4_pulse_high_width,
                s_p4_pulse_cycle - s_p4_pulse_low_start
            );
          if (s_p4_pulse_pairs >= 6) begin
            $display(
                "P4_PULSE_DEBUG sessions=%0d pairs=%0d high=%0d low=%0d pc=%0d state=%0d x=%0d y=%0d",
                s_p4_pulse_sessions, s_p4_pulse_pairs, s_p4_pulse_high_width,
                s_p4_pulse_cycle - s_p4_pulse_low_start, u_dut.u_soc.u_piolite.u_ctrl.runtime[0].pc,
                u_dut.u_soc.u_piolite.u_ctrl.runtime[0].state,
                u_dut.u_soc.u_piolite.u_ctrl.runtime[0].x,
                u_dut.u_soc.u_piolite.u_ctrl.runtime[0].y);
            $fatal(1, "SIM_TEST_FAIL P4 pulse extra pair");
          end
          s_p4_pulse_high[s_p4_pulse_pairs] = s_p4_pulse_high_width;
          s_p4_pulse_low[s_p4_pulse_pairs]  = s_p4_pulse_cycle - s_p4_pulse_low_start;
          s_p4_pulse_pairs                  = s_p4_pulse_pairs + 1;
          s_p4_pulse_high_seen              = 1'b0;
        end
        if (s_p4_pulse_pc_q == 5'd8) begin
          s_p4_pulse_high_start = s_p4_pulse_cycle;
          s_p4_pulse_high_valid = 1'b1;
        end
      end
      if (!s_gpio_2 && s_p4_pulse_level_q && s_p4_pulse_high_valid) begin
        s_p4_pulse_high_width = s_p4_pulse_cycle - s_p4_pulse_high_start;
        s_p4_pulse_low_start  = s_p4_pulse_cycle;
        s_p4_pulse_high_seen  = 1'b1;
        s_p4_pulse_high_valid = 1'b0;
      end
      s_p4_pulse_level_q = s_gpio_2;
    end
    s_p4_pulse_pc_q      = u_dut.u_soc.u_piolite.u_ctrl.runtime[0].pc;
    s_p4_pulse_retired_q = u_dut.u_soc.u_piolite.u_ctrl.runtime[0].retired_count;
    s_p4_pulse_owned_q   = s_p4_pulse_owned;
  end
end

always @(posedge u_dut.s_test_done) begin
  if (s_p4_pulse_active && u_dut.s_test_pass) begin
    if ((s_p4_pulse_sessions != 7) || (s_p4_pulse_pairs != 6))
      $fatal(
          1, "SIM_TEST_FAIL P4 pulse sessions=%0d pairs=%0d", s_p4_pulse_sessions, s_p4_pulse_pairs
      );
    for (integer index = 0; index < 6; index++)
    $display(
        "PIOLITE_P4_BFM_PULSE case=%0d high=%0d low=%0d",
        index,
        s_p4_pulse_high[index],
        s_p4_pulse_low[index]
    );
    $display("PIOLITE_P4_BFM_PULSE_ABORT complete=1");
  end
end

logic          s_p4_spi_active = $test$plusargs("piolite_p4_scenario_SPI");
logic          s_p4_spi_miso_q;
logic          s_p4_spi_sck_q;
logic          s_p4_spi_cs_q;
logic          s_p4_spi_owned_q;
logic          s_p4_spi_starved;
integer        s_p4_spi_sessions;
integer        s_p4_spi_idle_cycles;
integer        s_p4_spi_frames;
integer        s_p4_spi_cycle;
integer        s_p4_spi_mode;
integer        s_p4_spi_width;
integer        s_p4_spi_cpol;
integer        s_p4_spi_cpha;
integer        s_p4_spi_bits;
integer        s_p4_spi_cs_start;
integer        s_p4_spi_last_leading;
integer        s_p4_spi_leading_count;
integer        s_p4_spi_last_edge;
integer        s_p4_spi_min_period;
integer        s_p4_spi_max_period;
integer        s_p4_spi_modes                                                                [12];
integer        s_p4_spi_widths                                                               [12];
integer        s_p4_spi_periods                                                              [12];
integer        s_p4_spi_setups                                                               [12];
integer        s_p4_spi_holds                                                                [12];
logic   [31:0] s_p4_spi_tx                                                                   [12];
logic   [31:0] s_p4_spi_rx                                                                   [12];
logic   [31:0] s_p4_spi_mosi;
logic   [31:0] s_p4_spi_expected;
wire           s_p4_spi_owned = s_p4_spi_active && u_dut.u_soc.s_piolite_gpio_user_status[5];
assign s_gpio_7 = s_p4_spi_active ? s_p4_spi_miso_q : 1'bz;

function automatic [31:0] s_p4_spi_width_mask(input integer width);
  if (width == 32) s_p4_spi_width_mask = 32'hffff_ffff;
  else s_p4_spi_width_mask = (32'd1 << width) - 1;
endfunction
function automatic [31:0] s_p4_spi_expected_rx(input integer mode, input integer width);
  s_p4_spi_expected_rx = (32'h5a3c_c35a ^ (mode * 32'h0102_0408) ^ width) &
      s_p4_spi_width_mask(width);
endfunction

initial begin
  s_p4_spi_miso_q      = 1'b0;
  s_p4_spi_sck_q       = 1'b0;
  s_p4_spi_cs_q        = 1'b1;
  s_p4_spi_owned_q     = 1'b0;
  s_p4_spi_starved     = 1'b0;
  s_p4_spi_sessions    = 0;
  s_p4_spi_idle_cycles = 0;
  s_p4_spi_frames      = 0;
  s_p4_spi_cycle       = 0;
  s_p4_spi_bits        = 0;
  s_p4_spi_mosi        = 32'd0;
  s_p4_spi_expected    = 32'd0;
end

always @(negedge s_clk) begin
  if (s_p4_spi_active) begin
    s_p4_spi_cycle = s_p4_spi_cycle + 1;
    if (s_p4_spi_owned && !s_p4_spi_owned_q) begin
      s_p4_spi_sessions    = s_p4_spi_sessions + 1;
      s_p4_spi_idle_cycles = 0;
    end
    if (s_p4_spi_owned && (s_p4_spi_frames == 0) && s_p4_spi_cs_q)
      s_p4_spi_idle_cycles = s_p4_spi_idle_cycles + 1;
    if (!s_p4_spi_owned && s_p4_spi_owned_q && (s_p4_spi_sessions == 1) &&
        (s_p4_spi_frames == 0) && (s_p4_spi_idle_cycles >= 32))
      s_p4_spi_starved = 1'b1;

    if (!s_p4_spi_cs_q && s_gpio_5) begin
      if (s_p4_spi_bits != s_p4_spi_width)
        $fatal(1, "SIM_TEST_FAIL P4 SPI short frame %0d/%0d", s_p4_spi_bits, s_p4_spi_width);
      if ((s_p4_spi_cycle - s_p4_spi_last_edge) == 0) $fatal(1, "SIM_TEST_FAIL P4 SPI CS hold");
      if (s_p4_spi_frames >= 12) $fatal(1, "SIM_TEST_FAIL P4 SPI extra frame");
      s_p4_spi_modes[s_p4_spi_frames]   = s_p4_spi_mode;
      s_p4_spi_widths[s_p4_spi_frames]  = s_p4_spi_width;
      s_p4_spi_periods[s_p4_spi_frames] = s_p4_spi_max_period;
      s_p4_spi_setups[s_p4_spi_frames]  = s_p4_spi_cs_start;
      s_p4_spi_holds[s_p4_spi_frames]   = s_p4_spi_cycle - s_p4_spi_last_edge;
      s_p4_spi_tx[s_p4_spi_frames]      = s_p4_spi_mosi;
      s_p4_spi_rx[s_p4_spi_frames]      = s_p4_spi_expected;
      s_p4_spi_frames                   = s_p4_spi_frames + 1;
      s_p4_spi_miso_q                   = 1'b0;
    end

    if (s_p4_spi_cs_q && !s_gpio_5) begin
      if (s_p4_spi_frames >= 12) $fatal(1, "SIM_TEST_FAIL P4 SPI frame count");
      s_p4_spi_mode  = s_p4_spi_frames / 3;
      s_p4_spi_width = 8 << (s_p4_spi_frames % 3);
      s_p4_spi_cpol  = s_p4_spi_mode >= 2;
      s_p4_spi_cpha  = s_p4_spi_mode & 1;
      if (s_gpio_4 != s_p4_spi_cpol[0]) $fatal(1, "SIM_TEST_FAIL P4 SPI idle polarity");
      s_p4_spi_bits          = 0;
      s_p4_spi_mosi          = 32'd0;
      s_p4_spi_expected      = s_p4_spi_expected_rx(s_p4_spi_mode, s_p4_spi_width);
      s_p4_spi_cs_start      = s_p4_spi_cycle;
      s_p4_spi_last_leading  = 0;
      s_p4_spi_leading_count = 0;
      s_p4_spi_last_edge     = s_p4_spi_cycle;
      s_p4_spi_min_period    = 1000000;
      s_p4_spi_max_period    = 0;
      if (s_p4_spi_cpha == 0) s_p4_spi_miso_q = s_p4_spi_expected[0];
    end

    if (!s_gpio_5 && (s_gpio_4 != s_p4_spi_sck_q)) begin
      if (s_gpio_4 != s_p4_spi_cpol[0]) begin
        s_p4_spi_leading_count = s_p4_spi_leading_count + 1;
        if (s_p4_spi_leading_count == 1) s_p4_spi_cs_start = s_p4_spi_cycle - s_p4_spi_cs_start;
        else begin
          if ((s_p4_spi_cycle - s_p4_spi_last_leading) != 24)
            $fatal(
                1, "SIM_TEST_FAIL P4 SPI SCK period %0d", s_p4_spi_cycle - s_p4_spi_last_leading
            );
          s_p4_spi_min_period = 24;
          s_p4_spi_max_period = 24;
        end
        s_p4_spi_last_leading = s_p4_spi_cycle;
        if (s_p4_spi_cpha == 0) begin
          if (s_p4_spi_bits >= s_p4_spi_width) $fatal(1, "SIM_TEST_FAIL P4 SPI extra bit");
          s_p4_spi_mosi[s_p4_spi_bits] = s_gpio_6;
        end else begin
          s_p4_spi_miso_q = s_p4_spi_expected[s_p4_spi_bits];
        end
      end else begin
        if (s_p4_spi_cpha != 0) begin
          if (s_p4_spi_bits >= s_p4_spi_width) $fatal(1, "SIM_TEST_FAIL P4 SPI extra bit");
          s_p4_spi_mosi[s_p4_spi_bits] = s_gpio_6;
        end
        s_p4_spi_bits = s_p4_spi_bits + 1;
        if ((s_p4_spi_cpha == 0) && (s_p4_spi_bits < s_p4_spi_width))
          s_p4_spi_miso_q = s_p4_spi_expected[s_p4_spi_bits];
      end
      s_p4_spi_last_edge = s_p4_spi_cycle;
    end
    s_p4_spi_sck_q   = s_gpio_4;
    s_p4_spi_cs_q    = s_gpio_5;
    s_p4_spi_owned_q = s_p4_spi_owned;
  end
end

always @(posedge u_dut.s_test_done) begin
  if (s_p4_spi_active && u_dut.s_test_pass) begin
    if (!s_p4_spi_starved || (s_p4_spi_frames != 12))
      $fatal(
          1,
          "SIM_TEST_FAIL P4 SPI coverage starved=%0d frames=%0d",
          s_p4_spi_starved,
          s_p4_spi_frames
      );
    $display("PIOLITE_P4_BFM_SPI_STARVATION safe=1");
    for (integer index = 0; index < 12; index++) begin
      if ((s_p4_spi_periods[index] != 24) || (s_p4_spi_setups[index] <= 0) ||
          (s_p4_spi_holds[index] <= 0))
        $fatal(1, "SIM_TEST_FAIL P4 SPI timing case %0d", index);
      $display("PIOLITE_P4_BFM_SPI mode=%0d width=%0d tx=%08x rx=%08x rate=%0d setup=%0d hold=%0d",
               s_p4_spi_modes[index], s_p4_spi_widths[index], s_p4_spi_tx[index],
               s_p4_spi_rx[index], 24000000 / s_p4_spi_periods[index], s_p4_spi_setups[index],
               s_p4_spi_holds[index]);
    end
  end
end

logic s_p4_uart_active = $test$plusargs("piolite_p4_scenario_UART");
logic s_p4_uart_rx_drive;
logic s_p4_uart_tx_owned_q;
logic s_p4_uart_tx_pin_q;
logic [31:0] s_p4_uart_tx_oe_seen;
integer s_p4_uart_start_edges;
logic s_p4_uart_tx_frame;
logic [7:0] s_p4_uart_tx_byte;
integer s_p4_uart_tx_sessions;
integer s_p4_uart_tx_cycle;
integer s_p4_uart_tx_start;
integer s_p4_uart_tx_previous_start;
integer s_p4_uart_tx_target;
integer s_p4_uart_tx_bit;
integer s_p4_uart_tx_count;
integer s_p4_uart_tx_counts[6];
logic [31:0] s_p4_uart_tx_fnv;
logic [31:0] s_p4_uart_tx_fnvs[6];
logic [31:0] s_p4_uart_expected_fnvs[6];
integer s_p4_uart_rx_sessions;
logic s_p4_uart_rx_starved;
logic s_p4_uart_break_seen;
logic s_p4_uart_framing_seen;
logic s_p4_uart_tx_starved;
wire s_p4_uart_tx_owned = s_p4_uart_active && u_dut.u_soc.s_piolite_gpio_user_status[0];
wire s_p4_uart_rx_owned = s_p4_uart_active && u_dut.u_soc.s_piolite_gpio_user_status[1];
assign s_gpio_1 = s_p4_uart_active ? s_p4_uart_rx_drive : 1'bz;

function automatic [7:0] s_p4_uart_expected_byte(input integer phase, input integer index);
  begin
    case (index)
      0:       s_p4_uart_expected_byte = 8'h00 ^ phase[7:0];
      1:       s_p4_uart_expected_byte = 8'hff ^ phase[7:0];
      2:       s_p4_uart_expected_byte = 8'ha5 ^ phase[7:0];
      3:       s_p4_uart_expected_byte = 8'h5a ^ phase[7:0];
      default: s_p4_uart_expected_byte = (index * 73) + (phase * 29) + ((index >> 2) * 11);
    endcase
  end
endfunction

function automatic [31:0] s_p4_uart_fnv_step(input [31:0] hash, input [7:0] value);
  s_p4_uart_fnv_step = (hash ^ value) * 32'd16777619;
endfunction

task automatic s_p4_uart_send_byte(input [7:0] value);
  begin
    s_p4_uart_rx_drive = 1'b0;
    repeat (208) @(negedge s_clk);
    for (integer index = 0; index < 8; index++) begin
      s_p4_uart_rx_drive = value[index];
      repeat (208) @(negedge s_clk);
    end
    s_p4_uart_rx_drive = 1'b1;
    repeat (208) @(negedge s_clk);
  end
endtask

initial begin
  s_p4_uart_rx_drive     = 1'b1;
  s_p4_uart_rx_sessions  = 0;
  s_p4_uart_rx_starved   = 1'b0;
  s_p4_uart_break_seen   = 1'b0;
  s_p4_uart_framing_seen = 1'b0;
  for (integer phase_index = 0; phase_index < 8; phase_index++) begin
    integer        phase;
    integer        rx_sm;
    integer        offsets[4];
    logic   [31:0] hash;
    rx_sm      = ((phase_index >= 4) && (phase_index <= 6)) ? 0 : 1;
    offsets[0] = 0;
    offsets[1] = 3;
    offsets[2] = 7;
    offsets[3] = 13;
    wait (s_p4_uart_rx_owned);
    s_p4_uart_rx_sessions = s_p4_uart_rx_sessions + 1;
    wait ((u_dut.u_soc.u_piolite.u_ctrl.runtime[rx_sm].state == 1) &&
          (u_dut.u_soc.u_piolite.u_ctrl.runtime[rx_sm].pc ==
           u_dut.u_soc.u_piolite.u_ctrl.cfg[rx_sm].entry));
    repeat (208) @(negedge s_clk);
    hash = 32'h811c9dc5;
    if (phase_index == 4) begin
      for (integer index = 0; index < 12; index++)
      s_p4_uart_send_byte(s_p4_uart_expected_byte(0, index));
    end else if (phase_index == 5) begin
      s_p4_uart_rx_drive = 1'b0;
      repeat (3000) @(negedge s_clk);
      s_p4_uart_rx_drive = 1'b1;
    end else if (phase_index == 6) begin
      s_p4_uart_rx_drive = 1'b0;
      repeat (208) @(negedge s_clk);
      for (integer index = 0; index < 9; index++) repeat (208) @(negedge s_clk);
      wait ((u_dut.u_soc.u_piolite.u_ctrl.runtime[0].pc == 10) &&
            (u_dut.u_soc.u_piolite.u_ctrl.runtime[0].stall == 1));
      repeat (208) @(negedge s_clk);
      s_p4_uart_send_byte(8'h5a);
    end else begin
      phase = (phase_index < 4) ? offsets[phase_index] : 0;
      repeat (phase) @(negedge s_clk);
      for (integer index = 0; index < 16; index++) begin
        logic [7:0] value;
        value = s_p4_uart_expected_byte(phase, index);
        s_p4_uart_send_byte(value);
        hash = s_p4_uart_fnv_step(hash, value);
      end
      if (phase_index == 7) s_p4_uart_expected_fnvs[5] = hash;
      else s_p4_uart_expected_fnvs[phase_index] = hash;
    end
    s_p4_uart_rx_drive = 1'b1;
    wait (!s_p4_uart_rx_owned);
    @(negedge s_clk);
  end
end

initial begin
  s_p4_uart_tx_owned_q        = 1'b0;
  s_p4_uart_tx_pin_q          = 1'b1;
  s_p4_uart_tx_oe_seen        = 32'd0;
  s_p4_uart_start_edges       = 0;
  s_p4_uart_tx_frame          = 1'b0;
  s_p4_uart_tx_byte           = 8'd0;
  s_p4_uart_tx_sessions       = 0;
  s_p4_uart_tx_cycle          = 0;
  s_p4_uart_tx_previous_start = -1;
  s_p4_uart_tx_count          = 0;
  s_p4_uart_tx_fnv            = 32'h811c9dc5;
  s_p4_uart_tx_starved        = 1'b0;
end

always @(negedge s_clk) begin
  if (s_p4_uart_active) begin
    s_p4_uart_tx_cycle = s_p4_uart_tx_cycle + 1;
    if (s_p4_uart_tx_owned && !s_p4_uart_tx_owned_q) begin
      s_p4_uart_tx_frame          = 1'b0;
      s_p4_uart_tx_previous_start = -1;
      s_p4_uart_tx_count          = 0;
      s_p4_uart_tx_fnv            = 32'h811c9dc5;
      s_p4_uart_tx_oe_seen        = 32'd0;
      s_p4_uart_start_edges       = 0;
    end
    if (s_p4_uart_tx_owned) begin
      if (!s_gpio_0 && s_p4_uart_tx_pin_q) s_p4_uart_start_edges = s_p4_uart_start_edges + 1;
      s_p4_uart_tx_oe_seen = s_p4_uart_tx_oe_seen |
          u_dut.u_soc.u_piolite.u_ctrl.runtime[0].output_oe;
      s_p4_uart_tx_pin_q = s_gpio_0;
      if (!s_p4_uart_tx_frame && !s_gpio_0 &&
          (u_dut.u_soc.u_piolite.u_ctrl.runtime[0].pc == 2)) begin
        s_p4_uart_tx_frame  = 1'b1;
        s_p4_uart_tx_start  = s_p4_uart_tx_cycle;
        s_p4_uart_tx_target = s_p4_uart_tx_cycle + 104;
        s_p4_uart_tx_bit    = -1;
        s_p4_uart_tx_byte   = 8'd0;
        if ((s_p4_uart_tx_previous_start >= 0) &&
            ((s_p4_uart_tx_start - s_p4_uart_tx_previous_start) != 2080))
          $fatal(
              1,
              "SIM_TEST_FAIL P4 UART frame spacing %0d",
              s_p4_uart_tx_start - s_p4_uart_tx_previous_start
          );
        s_p4_uart_tx_previous_start = s_p4_uart_tx_start;
      end
      if (s_p4_uart_tx_frame && (s_p4_uart_tx_sessions != 4) &&
          (s_p4_uart_tx_cycle == s_p4_uart_tx_target)) begin
        if (s_p4_uart_tx_bit < 0) begin
          if (s_gpio_0) $fatal(1, "SIM_TEST_FAIL P4 UART start bit");
          s_p4_uart_tx_bit    = 0;
          s_p4_uart_tx_target = s_p4_uart_tx_start + 312;
        end else if (s_p4_uart_tx_bit < 8) begin
          s_p4_uart_tx_byte[s_p4_uart_tx_bit] = s_gpio_0;
          s_p4_uart_tx_bit                    = s_p4_uart_tx_bit + 1;
          s_p4_uart_tx_target                 = s_p4_uart_tx_target + 208;
        end else begin
          if (!s_gpio_0) $fatal(1, "SIM_TEST_FAIL P4 UART stop bit");
          if (s_p4_uart_tx_count >= 16) $fatal(1, "SIM_TEST_FAIL P4 UART extra byte");
          s_p4_uart_tx_fnv   = s_p4_uart_fnv_step(s_p4_uart_tx_fnv, s_p4_uart_tx_byte);
          s_p4_uart_tx_count = s_p4_uart_tx_count + 1;
          s_p4_uart_tx_frame = 1'b0;
        end
      end
    end else if (s_p4_uart_tx_owned_q) begin
      if (s_p4_uart_tx_sessions == 4) begin
        if ((s_p4_uart_tx_count == 0) && s_p4_uart_tx_frame &&
            ((s_p4_uart_tx_cycle - s_p4_uart_tx_start) > 2080))
          s_p4_uart_tx_starved = 1'b1;
      end else begin
        if ((s_p4_uart_tx_count != 16) && !$test$plusargs("piolite_p4_diagnose")) begin
          $display(
              "P4_UART_DEBUG session=%0d count=%0d pin=%b oe_seen=%08x starts=%0d value=%08x pc=%0d state=%0d",
              s_p4_uart_tx_sessions, s_p4_uart_tx_count, s_gpio_0, s_p4_uart_tx_oe_seen,
              s_p4_uart_start_edges, u_dut.u_soc.u_piolite.u_ctrl.runtime[0].output_value,
              u_dut.u_soc.u_piolite.u_ctrl.runtime[0].pc,
              u_dut.u_soc.u_piolite.u_ctrl.runtime[0].state);
          $fatal(1, "SIM_TEST_FAIL P4 UART decoded count %0d", s_p4_uart_tx_count);
        end
        if (s_p4_uart_tx_sessions >= 6) $fatal(1, "SIM_TEST_FAIL P4 UART extra session");
        s_p4_uart_tx_counts[s_p4_uart_tx_sessions] = s_p4_uart_tx_count;
        s_p4_uart_tx_fnvs[s_p4_uart_tx_sessions]   = s_p4_uart_tx_fnv;
      end
      s_p4_uart_tx_sessions = s_p4_uart_tx_sessions + 1;
    end
    s_p4_uart_tx_owned_q = s_p4_uart_tx_owned;
  end
end

always @(posedge u_dut.s_test_done) begin
  if (s_p4_uart_active && u_dut.s_test_pass) begin
    if ((s_p4_uart_tx_sessions != 6) || (s_p4_uart_rx_sessions != 8) ||
        !s_p4_uart_rx_starved || !s_p4_uart_break_seen || !s_p4_uart_framing_seen ||
        !s_p4_uart_tx_starved)
      $fatal(
          1,
          "SIM_TEST_FAIL P4 UART sessions/errors tx=%0d rx=%0d flags=%0d%0d%0d%0d",
          s_p4_uart_tx_sessions,
          s_p4_uart_rx_sessions,
          s_p4_uart_rx_starved,
          s_p4_uart_break_seen,
          s_p4_uart_framing_seen,
          s_p4_uart_tx_starved
      );
    for (integer index = 0; index < 4; index++) begin
      if ((s_p4_uart_tx_counts[index] != 16) ||
          (s_p4_uart_tx_fnvs[index] != s_p4_uart_expected_fnvs[index]))
        $fatal(1, "SIM_TEST_FAIL P4 UART data oracle case %0d", index);
      $display(
          "PIOLITE_P4_BFM_UART case=%0d phase=%0d bytes=16 baud=115384 error_ppm=1603 fnv=%08x",
          index, (index == 0) ? 0 : (index == 1) ? 3 : (index == 2) ? 7 : 13,
          s_p4_uart_tx_fnvs[index]);
    end
    if ((s_p4_uart_tx_counts[5] != 16) || (s_p4_uart_tx_fnvs[5] != s_p4_uart_expected_fnvs[5]))
      $fatal(1, "SIM_TEST_FAIL P4 UART recovery oracle");
    $display("PIOLITE_P4_BFM_UART_RX_STARVATION detected=1");
    $display("PIOLITE_P4_BFM_UART_BREAK detected=1");
    $display("PIOLITE_P4_BFM_UART_FRAMING detected=1");
    $display("PIOLITE_P4_BFM_UART_TX_STARVATION detected=1");
    $display("PIOLITE_P4_BFM_UART_RECOVERY phase=0 bytes=16 baud=115384 error_ppm=1603 fnv=%08x",
             s_p4_uart_tx_fnvs[5]);
  end
end

logic s_p4_ir_active = $test$plusargs("piolite_p4_scenario_IR");
logic s_p4_ir_rx_drive;
logic s_p4_ir_tx_owned_q;
logic s_p4_ir_tx_level_q;
logic [2:0] s_p4_ir_tx_state_q;
integer s_p4_ir_tx_cycle;
integer s_p4_ir_last_rising;
integer s_p4_ir_mark_count;
integer s_p4_ir_tx_sessions;
integer s_p4_ir_tx_cases;
integer s_p4_ir_marks[6];
integer s_p4_ir_spaces[6];
integer s_p4_ir_periods[6];
integer s_p4_ir_period_min;
integer s_p4_ir_period_max;
integer s_p4_ir_rx_sessions;
logic s_p4_ir_timeout_seen;
logic s_p4_ir_overflow_seen;
wire s_p4_ir_tx_owned = s_p4_ir_active && u_dut.u_soc.s_piolite_gpio_user_status[12];
wire s_p4_ir_tx_driven = s_p4_ir_tx_owned && u_dut.u_soc.u_piolite.u_ctrl.runtime[0].output_oe[12];
wire s_p4_ir_rx_owned = s_p4_ir_active && u_dut.u_soc.s_piolite_gpio_user_status[13];
assign s_gpio_13 = s_p4_ir_active ? s_p4_ir_rx_drive : 1'bz;

function automatic integer s_p4_ir_expected_space(input integer session);
  case (session)
    0, 3, 4, 5: s_p4_ir_expected_space = 8;
    1:          s_p4_ir_expected_space = 4;
    default:    s_p4_ir_expected_space = 2;
  endcase
endfunction

task automatic s_p4_ir_drive_level(input logic level, input integer ticks);
  begin
    s_p4_ir_rx_drive = level;
    repeat (ticks * 211) @(negedge s_clk);
  end
endtask

initial begin
  integer durations[6];
  durations[0]          = 5;
  durations[1]          = 7;
  durations[2]          = 13;
  durations[3]          = 9;
  durations[4]          = 1;
  durations[5]          = 11;
  s_p4_ir_rx_drive      = 1'b0;
  s_p4_ir_rx_sessions   = 0;
  s_p4_ir_timeout_seen  = 1'b0;
  s_p4_ir_overflow_seen = 1'b0;
  for (integer index = 0; index < 6; index++) begin
    wait (s_p4_ir_rx_owned);
    s_p4_ir_rx_sessions = s_p4_ir_rx_sessions + 1;
    wait ((u_dut.u_soc.u_piolite.u_ctrl.runtime[1].state == 1) &&
          (u_dut.u_soc.u_piolite.u_ctrl.runtime[1].pc == u_dut.u_soc.u_piolite.u_ctrl.cfg[1].entry));
    repeat (211) @(negedge s_clk);
    if (index == 3) begin
      s_p4_ir_rx_drive = 1'b0;
      repeat (3000) @(negedge s_clk);
      s_p4_ir_rx_drive = 1'b1;
    end else if (index == 4) begin
      for (integer pair = 0; pair < 6; pair++) begin
        s_p4_ir_drive_level(1'b1, durations[(pair%3)*2]);
        s_p4_ir_drive_level(1'b0, durations[((pair%3)*2)+1]);
        s_p4_ir_drive_level(1'b1, 2);
      end
    end else if (index == 5) begin
      s_p4_ir_drive_level(1'b1, 5);
      s_p4_ir_drive_level(1'b0, 7);
      s_p4_ir_drive_level(1'b1, 2);
    end else begin
      s_p4_ir_drive_level(1'b1, durations[index*2]);
      s_p4_ir_drive_level(1'b0, durations[(index*2)+1]);
      s_p4_ir_drive_level(1'b1, 2);
    end
    s_p4_ir_rx_drive = 1'b0;
    wait (!s_p4_ir_rx_owned);
    @(negedge s_clk);
  end
end

initial begin
  s_p4_ir_tx_owned_q  = 1'b0;
  s_p4_ir_tx_level_q  = 1'b0;
  s_p4_ir_tx_state_q  = 3'd0;
  s_p4_ir_tx_cycle    = 0;
  s_p4_ir_last_rising = 0;
  s_p4_ir_mark_count  = 0;
  s_p4_ir_tx_sessions = 0;
  s_p4_ir_tx_cases    = 0;
end

always @(negedge s_clk) begin
  if (s_p4_ir_active) begin
    s_p4_ir_tx_cycle = s_p4_ir_tx_cycle + 1;
    if (s_p4_ir_tx_owned && !s_p4_ir_tx_owned_q) begin
      if (s_p4_ir_tx_sessions >= 6) $fatal(1, "SIM_TEST_FAIL P4 IR extra TX session");
      s_p4_ir_tx_sessions = s_p4_ir_tx_sessions + 1;
      s_p4_ir_last_rising = 0;
      s_p4_ir_mark_count  = 0;
      s_p4_ir_period_min  = 1000000;
      s_p4_ir_period_max  = 0;
      s_p4_ir_tx_state_q  = 3'd0;
    end
    if (s_p4_ir_tx_driven) begin
      if (s_gpio_12 && !s_p4_ir_tx_level_q) begin
        if (s_p4_ir_last_rising != 0) begin
          integer period;
          period = s_p4_ir_tx_cycle - s_p4_ir_last_rising;
          if (period != 633)
            $fatal(
                1,
                "SIM_TEST_FAIL P4 IR carrier period %0d session=%0d mark=%0d pc=%0d state=%0d stall=%0d",
                period,
                s_p4_ir_tx_sessions - 1,
                s_p4_ir_mark_count,
                u_dut.u_soc.u_piolite.u_ctrl.runtime[0].pc,
                u_dut.u_soc.u_piolite.u_ctrl.runtime[0].state,
                u_dut.u_soc.u_piolite.u_ctrl.runtime[0].stall
            );
          if (period < s_p4_ir_period_min) s_p4_ir_period_min = period;
          if (period > s_p4_ir_period_max) s_p4_ir_period_max = period;
        end
        s_p4_ir_last_rising = s_p4_ir_tx_cycle;
        s_p4_ir_mark_count  = s_p4_ir_mark_count + 1;
      end
      if ((u_dut.u_soc.u_piolite.u_ctrl.runtime[0].state == 3) && (s_p4_ir_tx_state_q != 3)) begin
        integer session;
        session = s_p4_ir_tx_sessions - 1;
        if ((session < 0) || (session > 5)) $fatal(1, "SIM_TEST_FAIL P4 IR invalid TX session");
        if (s_p4_ir_last_rising == 0) $fatal(1, "SIM_TEST_FAIL P4 IR missing carrier");
        if ((s_p4_ir_mark_count > 1) &&
            ((s_p4_ir_period_min != 633) || (s_p4_ir_period_max != 633)))
          $fatal(
              1, "SIM_TEST_FAIL P4 IR carrier range %0d/%0d", s_p4_ir_period_min, s_p4_ir_period_max
          );
        s_p4_ir_marks[session]   = s_p4_ir_mark_count;
        s_p4_ir_spaces[session]  = (s_p4_ir_tx_cycle - s_p4_ir_last_rising - 633) / 211;
        s_p4_ir_periods[session] = (s_p4_ir_mark_count > 1) ? 633 : 0;
        if (s_p4_ir_spaces[session] != s_p4_ir_expected_space(session))
          $fatal(1, "SIM_TEST_FAIL P4 IR space %0d", s_p4_ir_spaces[session]);
        s_p4_ir_tx_cases = s_p4_ir_tx_cases + 1;
      end
      s_p4_ir_tx_level_q = s_gpio_12;
      s_p4_ir_tx_state_q = u_dut.u_soc.u_piolite.u_ctrl.runtime[0].state;
    end
    s_p4_ir_tx_owned_q = s_p4_ir_tx_owned;
  end
end

always @(negedge s_clk) begin
  if (s_p4_uart_active && s_p4_uart_rx_owned) begin
    if ((s_p4_uart_rx_sessions == 5) && (u_dut.u_soc.u_piolite.u_ctrl.runtime[0].events[4]))
      s_p4_uart_rx_starved = 1'b1;
    if ((s_p4_uart_rx_sessions == 6) &&
        (u_dut.u_soc.u_piolite.u_ctrl.runtime[0].pc == 10) &&
        (u_dut.u_soc.u_piolite.u_ctrl.runtime[0].stall == 1))
      s_p4_uart_break_seen = 1'b1;
    if ((s_p4_uart_rx_sessions == 7) &&
        (u_dut.u_soc.u_piolite.u_ctrl.runtime[0].pc == 10) &&
        (u_dut.u_soc.u_piolite.u_ctrl.runtime[0].stall == 1))
      s_p4_uart_framing_seen = 1'b1;
  end
  if (s_p4_ir_active && s_p4_ir_rx_owned) begin
    if ((s_p4_ir_rx_sessions == 4) &&
        (u_dut.u_soc.u_piolite.u_ctrl.runtime[1].pc ==
         u_dut.u_soc.u_piolite.u_ctrl.cfg[1].entry) &&
        (u_dut.u_soc.u_piolite.u_ctrl.runtime[1].stall == 1))
      s_p4_ir_timeout_seen = 1'b1;
    if ((s_p4_ir_rx_sessions == 5) && u_dut.u_soc.u_piolite.u_ctrl.runtime[1].events[4])
      s_p4_ir_overflow_seen = 1'b1;
  end
end

always @(posedge u_dut.s_test_done) begin
  if (s_p4_ir_active && u_dut.s_test_pass) begin
    if ((s_p4_ir_tx_sessions != 6) || (s_p4_ir_tx_cases != 6) || (s_p4_ir_rx_sessions != 6) ||
        !s_p4_ir_timeout_seen || !s_p4_ir_overflow_seen)
      $fatal(
          1,
          "SIM_TEST_FAIL P4 IR coverage sessions=%0d tx=%0d rx=%0d errors=%0d%0d",
          s_p4_ir_tx_sessions,
          s_p4_ir_tx_cases,
          s_p4_ir_rx_sessions,
          s_p4_ir_timeout_seen,
          s_p4_ir_overflow_seen
      );
    for (integer index = 0; index < 3; index++) begin
      if ((s_p4_ir_periods[index] != 633) && (s_p4_ir_periods[index] != 0))
        $fatal(1, "SIM_TEST_FAIL P4 IR period case %0d", index);
      $display(
          "PIOLITE_P4_BFM_IR case=%0d mark=%0d space=%0d high=%0d low=%0d rate=%0d error_ppm=2245",
          index, s_p4_ir_marks[index], s_p4_ir_spaces[index] / 2,
          (index == 0) ? 5 : (index == 1) ? 13 : 1, (index == 0) ? 7 : (index == 1) ? 9 : 11,
          (s_p4_ir_periods[index] == 0) ? 0 : (24000000 + 316) / 633);
    end
    if ((s_p4_ir_marks[5] != 3) || (s_p4_ir_spaces[5] != 8) || (s_p4_ir_periods[5] != 633))
      $fatal(1, "SIM_TEST_FAIL P4 IR recovery oracle");
    $display("PIOLITE_P4_BFM_IR_TIMEOUT detected=1");
    $display("PIOLITE_P4_BFM_IR_OVERFLOW detected=1");
    $display("PIOLITE_P4_BFM_IR_RECOVERY mark=3 space=4 high=5 low=7 rate=37915 error_ppm=2245");
  end
end

logic          s_p4_led_active = $test$plusargs("piolite_p4_scenario_LED");
logic          s_p4_led_clock_q;
logic          s_p4_led_latch_q;
logic          s_p4_led_owned_q;
logic   [15:0] s_p4_led_shift;
logic   [31:0] s_p4_led_fnv;
integer        s_p4_led_bits;
integer        s_p4_led_rows;
integer        s_p4_led_sessions;
integer        s_p4_led_cycle;
integer        s_p4_led_first_latch;
integer        s_p4_led_frame_period;
logic          s_p4_led_stall_blank;
logic          s_p4_led_abort_blank;
wire           s_p4_led_owned = s_p4_led_active && u_dut.u_soc.s_piolite_gpio_user_status[16];

initial begin
  s_p4_led_clock_q      = 1'b0;
  s_p4_led_latch_q      = 1'b0;
  s_p4_led_owned_q      = 1'b0;
  s_p4_led_shift        = 16'd0;
  s_p4_led_fnv          = 32'h811c9dc5;
  s_p4_led_bits         = 0;
  s_p4_led_rows         = 0;
  s_p4_led_sessions     = 0;
  s_p4_led_cycle        = 0;
  s_p4_led_first_latch  = 0;
  s_p4_led_frame_period = 0;
  s_p4_led_stall_blank  = 1'b0;
  s_p4_led_abort_blank  = 1'b0;
end

always @(negedge s_clk) begin
  if (s_p4_led_active) begin
    s_p4_led_cycle = s_p4_led_cycle + 1;
    if (s_p4_led_owned && !s_p4_led_owned_q) s_p4_led_sessions = s_p4_led_sessions + 1;
    if (s_p4_led_owned && u_dut.u_soc.u_piolite.u_ctrl.runtime[0].output_oe[16]) begin
      if (s_gpio_16 && !s_p4_led_clock_q && !s_gpio_17) begin
        if (s_p4_led_bits >= 16) $fatal(1, "SIM_TEST_FAIL P4 LED extra shift bit");
        s_p4_led_shift[s_p4_led_bits] = s_gpio_19;
        s_p4_led_bits                 = s_p4_led_bits + 1;
      end
      if (s_gpio_17 && !s_p4_led_latch_q) begin
        logic [15:0] expected;
        logic [ 7:0] row;
        logic [ 7:0] columns;
        if ((s_p4_led_bits != 16) || !s_gpio_18)
          $fatal(1, "SIM_TEST_FAIL P4 LED latch bits=%0d blank=%0d", s_p4_led_bits, s_gpio_18);
        row      = s_p4_led_rows & 7;
        columns  = 8'h81 ^ (row * 8'h11) ^ (s_p4_led_rows >> 3);
        expected = {columns, 8'd1 << row};
        if (s_p4_led_shift != expected)
          $fatal(
              1,
              "SIM_TEST_FAIL P4 LED row %0d got=%04x expected=%04x",
              s_p4_led_rows,
              s_p4_led_shift,
              expected
          );
        if (s_p4_led_rows == 0) s_p4_led_first_latch = s_p4_led_cycle;
        if (s_p4_led_rows == 8) s_p4_led_frame_period = s_p4_led_cycle - s_p4_led_first_latch;
        if (s_p4_led_rows >= 16) $fatal(1, "SIM_TEST_FAIL P4 LED extra latch");
        s_p4_led_fnv  = s_p4_uart_fnv_step(s_p4_led_fnv, s_p4_led_shift[7:0]);
        s_p4_led_fnv  = s_p4_uart_fnv_step(s_p4_led_fnv, s_p4_led_shift[15:8]);
        s_p4_led_rows = s_p4_led_rows + 1;
        s_p4_led_bits = 0;
      end
    end
    if ((u_dut.u_soc.u_piolite.u_ctrl.runtime[0].stall == 3) && s_gpio_18)
      s_p4_led_stall_blank = 1'b1;
    if (!s_p4_led_owned && s_p4_led_owned_q && (s_p4_led_sessions == 2) &&
        s_p4_led_stall_blank && (s_p4_led_rows == 16))
      s_p4_led_abort_blank = 1'b1;
    s_p4_led_clock_q = s_gpio_16;
    s_p4_led_latch_q = s_gpio_17;
    s_p4_led_owned_q = s_p4_led_owned;
  end
end

always @(posedge u_dut.s_test_done) begin
  if (s_p4_led_active && u_dut.s_test_pass) begin
    if ((s_p4_led_rows != 16) || (s_p4_led_frame_period != 61600) || !s_p4_led_abort_blank)
      $fatal(
          1,
          "SIM_TEST_FAIL P4 LED rows=%0d period=%0d abort=%0d",
          s_p4_led_rows,
          s_p4_led_frame_period,
          s_p4_led_abort_blank
      );
    $display("PIOLITE_P4_BFM_LED frames=2 rows=16 fps=%0d blank=1 fnv=%08x",
             24000000 / s_p4_led_frame_period, s_p4_led_fnv);
    $display("PIOLITE_P4_BFM_LED_ABORT blank=1");
  end
end

logic s_p4_gamepad_active = $test$plusargs("piolite_p4_scenario_GAMEPAD");
logic s_p4_gamepad_data;
logic s_p4_gamepad_latch_q;
logic s_p4_gamepad_clock_q;
logic s_p4_gamepad_owned_q;
logic [4:0] s_p4_gamepad_pc_q;
logic [31:0] s_p4_gamepad_retired_q;
logic [7:0] s_p4_gamepad_byte;
integer s_p4_gamepad_bit;
integer s_p4_gamepad_sessions;
integer s_p4_gamepad_scans;
integer s_p4_gamepad_counts[4];
logic [31:0] s_p4_gamepad_fnv;
logic [31:0] s_p4_gamepad_fnvs[4];
wire s_p4_gamepad_owned = s_p4_gamepad_active && u_dut.u_soc.s_piolite_gpio_user_status[20];
assign s_gpio_22 = s_p4_gamepad_active ? s_p4_gamepad_data : 1'bz;

function automatic [7:0] s_p4_gamepad_pattern(input integer session, input integer scan);
  begin
    case (session)
      0:       s_p4_gamepad_pattern = 8'ha5;
      1: begin
        case (scan)
          0:       s_p4_gamepad_pattern = 8'h00;
          1:       s_p4_gamepad_pattern = 8'hff;
          2:       s_p4_gamepad_pattern = 8'h5a;
          default: s_p4_gamepad_pattern = 8'hc3;
        endcase
      end
      2: begin
        case (scan)
          0:       s_p4_gamepad_pattern = 8'h00;
          1:       s_p4_gamepad_pattern = 8'hff;
          2:       s_p4_gamepad_pattern = 8'h96;
          default: s_p4_gamepad_pattern = 8'h42;
        endcase
      end
      default: s_p4_gamepad_pattern = 8'h69;
    endcase
  end
endfunction

initial begin
  s_p4_gamepad_data      = 1'b1;
  s_p4_gamepad_latch_q   = 1'b1;
  s_p4_gamepad_clock_q   = 1'b0;
  s_p4_gamepad_owned_q   = 1'b0;
  s_p4_gamepad_pc_q      = 5'd0;
  s_p4_gamepad_retired_q = 32'd0;
  s_p4_gamepad_byte      = 8'hff;
  s_p4_gamepad_bit       = 0;
  s_p4_gamepad_sessions  = 0;
  s_p4_gamepad_scans     = 0;
  s_p4_gamepad_fnv       = 32'h811c9dc5;
end

always @(negedge s_clk) begin
  if (s_p4_gamepad_active) begin
    if (s_p4_gamepad_owned && !s_p4_gamepad_owned_q) begin
      if (s_p4_gamepad_sessions >= 4) $fatal(1, "SIM_TEST_FAIL P4 gamepad extra session");
      s_p4_gamepad_scans     = 0;
      s_p4_gamepad_fnv       = 32'h811c9dc5;
      s_p4_gamepad_bit       = 0;
      s_p4_gamepad_data      = 1'b1;
      s_p4_gamepad_pc_q      = u_dut.u_soc.u_piolite.u_ctrl.runtime[0].pc;
      s_p4_gamepad_retired_q = u_dut.u_soc.u_piolite.u_ctrl.runtime[0].retired_count;
    end
    if (s_p4_gamepad_owned) begin
      if ((u_dut.u_soc.u_piolite.u_ctrl.runtime[0].retired_count != s_p4_gamepad_retired_q) &&
          (s_p4_gamepad_pc_q == 5'd6) && (s_p4_gamepad_bit == 7)) begin
        s_p4_gamepad_fnv   = s_p4_uart_fnv_step(s_p4_gamepad_fnv, s_p4_gamepad_byte);
        s_p4_gamepad_scans = s_p4_gamepad_scans + 1;
      end
      s_p4_gamepad_pc_q      = u_dut.u_soc.u_piolite.u_ctrl.runtime[0].pc;
      s_p4_gamepad_retired_q = u_dut.u_soc.u_piolite.u_ctrl.runtime[0].retired_count;
      if (!s_gpio_21 && s_p4_gamepad_latch_q) begin
        s_p4_gamepad_byte = s_p4_gamepad_pattern(s_p4_gamepad_sessions, s_p4_gamepad_scans);
        s_p4_gamepad_bit  = 0;
        s_p4_gamepad_data = s_p4_gamepad_byte[0];
      end
      if (!s_gpio_20 && s_p4_gamepad_clock_q) begin
        if (s_p4_gamepad_bit == 7) begin
          s_p4_gamepad_bit = 0;
        end else begin
          s_p4_gamepad_bit  = s_p4_gamepad_bit + 1;
          s_p4_gamepad_data = s_p4_gamepad_byte[s_p4_gamepad_bit];
        end
      end
    end else if (s_p4_gamepad_owned_q) begin
      if (s_p4_gamepad_scans != ((s_p4_gamepad_sessions == 2) ? 2 : 4))
        $fatal(
            1,
            "SIM_TEST_FAIL P4 gamepad session %0d scans %0d",
            s_p4_gamepad_sessions,
            s_p4_gamepad_scans
        );
      s_p4_gamepad_counts[s_p4_gamepad_sessions] = s_p4_gamepad_scans;
      s_p4_gamepad_fnvs[s_p4_gamepad_sessions]   = s_p4_gamepad_fnv;
      s_p4_gamepad_sessions                      = s_p4_gamepad_sessions + 1;
      s_p4_gamepad_data                          = 1'b1;
    end
    s_p4_gamepad_latch_q = s_gpio_21;
    s_p4_gamepad_clock_q = s_gpio_20;
    s_p4_gamepad_owned_q = s_p4_gamepad_owned;
  end
end

always @(posedge u_dut.s_test_done) begin
  if (s_p4_gamepad_active && u_dut.s_test_pass) begin
    if (s_p4_gamepad_sessions != 4)
      $fatal(1, "SIM_TEST_FAIL P4 gamepad sessions %0d", s_p4_gamepad_sessions);
    for (integer index = 0; index < 4; index++)
    $display(
        "PIOLITE_P4_BFM_GAMEPAD session=%0d scans=%0d fnv=%08x disconnected=%0d",
        index,
        s_p4_gamepad_counts[index],
        s_p4_gamepad_fnvs[index],
        index == 2
    );
  end
end

logic s_p4_contend_active = $test$plusargs("piolite_p4_scenario_CONTENTION");
logic s_p4_contend_owned_q;
integer s_p4_contend_epoch;
integer s_p4_contend_gap;
integer s_p4_contend_max;
integer s_p4_contend_gaps[3];
integer s_p4_contend_overlap[3];
integer s_p4_contend_late[3];
integer s_p4_contend_overlap_current;
integer s_p4_contend_late_current;
wire s_p4_contend_owned = s_p4_contend_active && (&u_dut.u_soc.s_piolite_gpio_user_status[15:8]);

initial begin
  s_p4_contend_owned_q         = 1'b0;
  s_p4_contend_epoch           = -1;
  s_p4_contend_gap             = 0;
  s_p4_contend_max             = 0;
  s_p4_contend_overlap_current = 0;
  s_p4_contend_late_current    = 0;
  for (integer index = 0; index < 3; index++) begin
    s_p4_contend_gaps[index]    = 0;
    s_p4_contend_overlap[index] = 0;
    s_p4_contend_late[index]    = 0;
  end
end

always @(negedge s_clk) begin
  if (s_p4_contend_active) begin
    if (s_p4_contend_owned && !s_p4_contend_owned_q) begin
      s_p4_contend_epoch           = s_p4_contend_epoch + 1;
      s_p4_contend_gap             = 0;
      s_p4_contend_max             = 0;
      s_p4_contend_overlap_current = 0;
      s_p4_contend_late_current    = 0;
    end
    if (s_p4_contend_owned) begin
      if (u_dut.u_soc.u_dma.u_dma_core.s_write_candidate[2] &&
          !(u_dut.u_soc.u_dma.u_dma_core.s_axi_write_start_valid &&
            u_dut.u_soc.u_dma.u_dma_core.s_axi_write_start_ready &&
            (u_dut.u_soc.u_dma.u_dma_core.s_write_rr_selected == 2))) begin
        s_p4_contend_gap = s_p4_contend_gap + 1;
      end else begin
        if (s_p4_contend_gap > s_p4_contend_max) s_p4_contend_max = s_p4_contend_gap;
        s_p4_contend_gap = 0;
      end
      if (u_dut.u_soc.u_dma.u_dma_core.s_busy_q[1] && u_dut.u_soc.u_piolite_rx_axis_if.tvalid) begin
        s_p4_contend_overlap_current = s_p4_contend_overlap_current + 1;
        if (s_p4_logic_current_samples > 32000)
          s_p4_contend_late_current = s_p4_contend_late_current + 1;
      end
    end else if (s_p4_contend_owned_q) begin
      if (s_p4_contend_gap > s_p4_contend_max) s_p4_contend_max = s_p4_contend_gap;
      if ((s_p4_contend_epoch < 0) || (s_p4_contend_epoch > 2))
        $fatal(1, "SIM_TEST_FAIL P4 contention epoch");
      s_p4_contend_gaps[s_p4_contend_epoch]    = s_p4_contend_max;
      s_p4_contend_overlap[s_p4_contend_epoch] = s_p4_contend_overlap_current;
      s_p4_contend_late[s_p4_contend_epoch]    = s_p4_contend_late_current;
      if ($test$plusargs("piolite_p4_diagnose"))
        $display(
            "P4_CONTEND_EPOCH epoch=%0d gap=%0d overlap=%0d late_overlap=%0d",
            s_p4_contend_epoch,
            s_p4_contend_max,
            s_p4_contend_overlap_current,
            s_p4_contend_late_current
        );
    end
    s_p4_contend_owned_q = s_p4_contend_owned;
  end
end

always @(posedge u_dut.s_test_done) begin
  if (s_p4_contend_active && u_dut.s_test_pass) begin
    if (s_p4_contend_epoch != 2) $fatal(1, "SIM_TEST_FAIL P4 contention epochs");
    for (integer index = 0; index < 3; index++) begin
      if ((s_p4_contend_gaps[index] <= 0) || (s_p4_contend_overlap[index] <= 0) ||
          (s_p4_contend_late[index] <= 0))
        $fatal(1, "SIM_TEST_FAIL P4 contention was not observed %0d", index);
      $display("PIOLITE_P4_BFM_CONTEND pattern=%0d longest_gap=%0d overlap=%0d late_overlap=%0d",
               index, s_p4_contend_gaps[index], s_p4_contend_overlap[index],
               s_p4_contend_late[index]);
    end
  end
end
