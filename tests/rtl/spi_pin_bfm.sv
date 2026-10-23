// Pin-only oracle: no DUT state/shifter references. Timing is counted in PCLKs.
// Fault bits: 0 half-period, 1 CS setup, 2 first-bit setup, 3 incomplete frame,
// 4 CS hold, 5 CS inactive, 6 edge after abort, 7 pause polarity, 8 payload.
// Normal fixtures must fail on any fault; the checker fixture tests rejection.
module spi_pin_bfm (
    input  logic   [15:0] divider_i,
    setup_i,
    hold_i,
    inactive_i,
    input  logic          segment_i,
    pause_i,
    input  logic   [15:0] dummy_i,
    input  logic          clk_i,
    begin_i,
    enabled_i,
    abort_i,
    input  logic          cpol_i,
    cpha_i,
    lsb_i,
    frame16_i,
    input  logic   [ 1:0] direction_i,
    input  logic          cs_n_i,
    sck_i,
    mosi_i,
    output logic          miso_o,
    output integer        frames_o,
    edges_o,
    output logic   [ 8:0] faults_o
);
  logic          previous_sck = 0;
  logic   [15:0] received = 0;
  integer        samples = 0;
  integer        index_bit;
  integer        width_bits;
  logic   [31:0] expected_word;
  logic [15:0] expected_frame, response;
  integer cycle = 0, last_edge = 0, segment_start = 0, released = 0;
  integer frame_edges = 0;
  logic previous_cs = 1, previous_mosi = 0;
  logic have_edge = 0, have_release = 0, aborted = 0;
  function automatic logic [15:0] reply(input integer frame);
    return 16'ha5c3 ^ (16'(frame) * 16'h1237);
  endfunction
  always @(negedge clk_i) begin
    width_bits = frame16_i ? 16 : 8;
    if (begin_i) begin
      cycle         = 0;
      last_edge     = 0;
      segment_start = 0;
      released      = 0;
      frame_edges   = 0;
      have_edge     = 0;
      have_release  = 0;
      aborted       = 0;
      faults_o      = 0;
      previous_cs   = cs_n_i;
      previous_mosi = mosi_i;
      frames_o      = 0;
      edges_o       = 0;
      samples       = 0;
      received      = 0;
      previous_sck  = cpol_i;
      response      = reply(0);
      miso_o        = response[lsb_i?0 : width_bits-1];
    end else if (enabled_i) begin
      cycle++;
      if (segment_i || (previous_cs && !cs_n_i)) segment_start = cycle;
      if (abort_i) aborted = 1;
      if (previous_cs && !cs_n_i && have_release && cycle - released < integer'(inactive_i))
        faults_o[5] = 1;
      if (!previous_cs && cs_n_i) begin
        if (sck_i != cpol_i || (!aborted && frame_edges != 0)) faults_o[3] = 1;
        if (have_edge && cycle - last_edge < integer'(hold_i)) faults_o[4] = 1;
        have_release = 1;
        released     = cycle;
      end
      if (pause_i && (!cs_n_i && sck_i != cpol_i)) faults_o[7] = 1;
      if (!cs_n_i && sck_i != previous_sck) begin
        if (have_edge) begin
          // Only the idle CPOL interval BETWEEN complete frames may stretch.
          if (cycle - last_edge < integer'(divider_i) ||
              ((frame_edges != 0) && cycle - last_edge != integer'(divider_i)))
            faults_o[0] = 1;
        end
        if (aborted && (previous_sck == cpol_i || sck_i != cpol_i)) faults_o[6] = 1;
        if (!have_edge && cycle - segment_start < integer'(setup_i)) faults_o[1] = 1;
        if (frame_edges == 0 && !cpha_i && mosi_i != previous_mosi) faults_o[2] = 1;
        last_edge   = cycle;
        have_edge   = 1;
        frame_edges = (frame_edges + 1) % (2 * width_bits);
        edges_o++;
        if (!aborted && ((sck_i == cpol_i) == cpha_i)) begin
          index_bit           = lsb_i ? samples : width_bits - 1 - samples;
          received[index_bit] = mosi_i;
          samples++;
          if (samples == width_bits) begin
            expected_word  = 32'h80ff017e ^ (32'(frames_o / (32 / width_bits)) * 32'h01020408);
            expected_frame = 16'(expected_word >> ((frames_o % (32 / width_bits)) * width_bits));
            if (direction_i == 2) expected_frame = dummy_i;
            if ((received & (frame16_i ? 16'hffff : 16'h00ff)) !==
              (expected_frame & (frame16_i ? 16'hffff : 16'h00ff)))
              faults_o[8] = 1;
            frames_o++;
            samples  = 0;
            received = 0;
          end
        end else if (!aborted) begin
          response = reply(frames_o);
          miso_o   = response[lsb_i?samples : width_bits-1-samples];
        end
      end else if (!cs_n_i && have_edge && frame_edges != 0 &&
                   (!aborted || sck_i != cpol_i) && cycle - last_edge > integer'(divider_i))
        faults_o[0] = 1;
      previous_sck  = sck_i;
      previous_cs   = cs_n_i;
      previous_mosi = mosi_i;
    end
  end
endmodule
