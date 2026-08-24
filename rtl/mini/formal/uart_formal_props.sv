// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module uart_formal;
  (* anyseq *) (* gclk *)reg         clk_i;
  wire        rst_n_i;
  wire        f_past_valid;
  wire        rib_valid;
  wire [31:0] rib_addr;
  wire [31:0] rib_wdata;
  wire [ 3:0] rib_wstrb;
  wire        rib_ready;
  wire        rib_resp_err;
  wire [ 6:0] tx_count;
  wire [ 6:0] rx_count;
  wire [ 6:0] error_status;
  wire [ 6:0] intr_state;
  wire [ 6:0] intr_enable;
  wire        tx_enable;
  wire        rx_enable;
  wire        tx_busy;
  wire        rx_active;
  wire        break_active;
  wire        auto_cts_enable;
  wire        auto_rts_enable;
  wire        cts_asserted;
  wire        rts_asserted;
  wire        tx_start_allowed;
  wire        tx_flow_blocked;
  wire        tx_data_pop;
  wire        tx_dma_stall;
  wire        rx_dma_stall;
  wire        tx;
  wire        rts_n;
  wire        irq;

  uart_formal_design u_design (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .f_past_valid    (f_past_valid),
      .rib_valid       (rib_valid),
      .rib_addr        (rib_addr),
      .rib_wdata       (rib_wdata),
      .rib_wstrb       (rib_wstrb),
      .rib_ready       (rib_ready),
      .rib_resp_err    (rib_resp_err),
      .tx_count        (tx_count),
      .rx_count        (rx_count),
      .error_status    (error_status),
      .intr_state      (intr_state),
      .intr_enable     (intr_enable),
      .tx_enable       (tx_enable),
      .rx_enable       (rx_enable),
      .tx_busy         (tx_busy),
      .rx_active       (rx_active),
      .break_active    (break_active),
      .auto_cts_enable (auto_cts_enable),
      .auto_rts_enable (auto_rts_enable),
      .cts_asserted    (cts_asserted),
      .rts_asserted    (rts_asserted),
      .tx_start_allowed(tx_start_allowed),
      .tx_flow_blocked (tx_flow_blocked),
      .tx_data_pop     (tx_data_pop),
      .tx_dma_stall    (tx_dma_stall),
      .rx_dma_stall    (rx_dma_stall),
      .tx              (tx),
      .rts_n           (rts_n),
      .irq             (irq)
  );

  always @(posedge clk_i) begin
    if (f_past_valid && $past(rst_n_i && rib_valid && !rib_ready)) begin
      assume (rib_valid);
      assume (rib_addr == $past(rib_addr));
      assume (rib_wdata == $past(rib_wdata));
      assume (rib_wstrb == $past(rib_wstrb));
    end

    if (rst_n_i) begin
      assert (tx_count <= 7'd64);
      assert (rx_count <= 7'd64);
      assert (irq == |(intr_state & intr_enable));
      if (break_active) assert (!tx);
      if (!break_active && !tx_busy) assert (tx);
      if (!tx_enable) assert (tx_dma_stall);
      if (!rx_enable) assert (rx_dma_stall);
      assert (rts_n == !rts_asserted);
      if (!auto_rts_enable || !rx_enable) assert (!rts_asserted);
      if (tx_data_pop) assert (tx_start_allowed);
      if (tx_flow_blocked) begin
        assert (auto_cts_enable);
        assert (!cts_asserted);
        assert (!tx_busy);
      end
      cover (rib_ready && rib_resp_err);
      cover (tx_busy);
      cover (rx_active);
      cover (irq);
      cover (error_status != 7'd0);
      cover (tx_flow_blocked);
      cover (rts_asserted);
    end
  end

endmodule
