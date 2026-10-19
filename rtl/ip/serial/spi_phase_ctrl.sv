// One finite frame, exclusively clocked by PCLK. Abort never samples more bits.
module spi_phase_ctrl (
    input  logic        clk_i,
    rst_n_i,
    start_i,
    abort_i,
    clamp_i,
    input  logic        cpol_i,
    cpha_i,
    lsb_first_i,
    frame16_i,
    input  logic [15:0] divider_i,
    tx_data_i,
    input  logic        miso_i,
    output logic        active_o,
    done_o,
    sck_o,
    mosi_o,
    output logic [15:0] rx_data_o
);
  typedef struct packed {
    logic        active,     sck,     mosi;
    logic [15:0] timer,      tx_data, rx_data;
    logic [5:0]  edge_count;
  } phase_t;
  phase_t s_phase_d, s_phase_q;
  logic [3:0] s_bit;
  logic [3:0] s_next_bit;
  logic [4:0] s_last_bit;
  logic       s_trailing;
  assign s_last_bit = frame16_i ? 5'd15 : 5'd7;
  assign s_trailing = s_phase_q.edge_count[0];
  assign s_bit = lsb_first_i ? s_phase_q.edge_count[4:1] :
                             4'(s_last_bit - s_phase_q.edge_count[5:1]);
  assign s_next_bit = lsb_first_i ? s_bit[3:0] + 4'd1 : s_bit[3:0] - 4'd1;
  assign active_o = s_phase_q.active;
  assign sck_o = clamp_i ? cpol_i : s_phase_q.sck;
  assign mosi_o = s_phase_q.mosi;
  always_comb begin
    s_phase_d = s_phase_q;
    done_o    = 1'b0;
    rx_data_o = s_phase_q.rx_data;
    if (clamp_i) begin
      s_phase_d.active = 1'b0;
      s_phase_d.sck    = cpol_i;
    end else if (!s_phase_q.active) begin
      s_phase_d.sck = cpol_i;
      if (start_i && !abort_i) begin
        s_phase_d.active     = 1'b1;
        s_phase_d.edge_count = '0;
        s_phase_d.timer      = divider_i - 16'd1;
        s_phase_d.tx_data    = tx_data_i;
        s_phase_d.rx_data    = '0;
        s_phase_d.mosi       = cpha_i ? 1'b0 : tx_data_i[lsb_first_i?4'd0 : s_last_bit[3:0]];
      end
    end else if (abort_i && (s_phase_q.sck == cpol_i)) begin
      s_phase_d.active = 1'b0;
    end else if (s_phase_q.timer != 16'd0) begin
      s_phase_d.timer = s_phase_q.timer - 16'd1;
    end else if (abort_i) begin
      s_phase_d.sck    = cpol_i;
      s_phase_d.active = 1'b0;
    end else begin
      s_phase_d.timer      = divider_i - 16'd1;
      s_phase_d.sck        = !s_phase_q.sck;
      s_phase_d.edge_count = s_phase_q.edge_count + 6'd1;
      if (s_trailing == cpha_i) begin
        s_phase_d.rx_data[s_bit[3:0]] = miso_i;
        rx_data_o[s_bit[3:0]]         = miso_i;
      end
      if (cpha_i && !s_trailing) s_phase_d.mosi = s_phase_q.tx_data[s_bit[3:0]];
      if (!cpha_i && s_trailing && (s_phase_q.edge_count != {s_last_bit, 1'b1}))
        s_phase_d.mosi = s_phase_q.tx_data[s_next_bit[3:0]];
      if (s_phase_q.edge_count == {s_last_bit, 1'b1}) begin
        done_o           = 1'b1;
        s_phase_d.active = 1'b0;
      end
    end
  end
  dffr #(
      .DATA_WIDTH($bits(phase_t))
  ) u_phase (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_phase_d),
      .dat_o  (s_phase_q)
  );
`ifdef FORMAL
  // Reachable timer/edge invariants strengthen induction without constraining the environment.
  always_ff @(posedge clk_i) begin
    if (rst_n_i && s_phase_q.active) begin
      assert (s_phase_q.timer < divider_i);
      assert (s_phase_q.edge_count <= {s_last_bit, 1'b1});
    end
  end
`endif
endmodule
