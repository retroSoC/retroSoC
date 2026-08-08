// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

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
  wire [ 5:0] intr_state;
  wire [ 5:0] intr_enable;
  wire        tx_enable;
  wire        rx_enable;
  wire        tx_busy;
  wire        rx_active;
  wire        break_active;
  wire        tx_dma_stall;
  wire        rx_dma_stall;
  wire        tx;
  wire        irq;

  uart_formal_design u_design (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .f_past_valid(f_past_valid),
      .rib_valid   (rib_valid),
      .rib_addr    (rib_addr),
      .rib_wdata   (rib_wdata),
      .rib_wstrb   (rib_wstrb),
      .rib_ready   (rib_ready),
      .rib_resp_err(rib_resp_err),
      .tx_count    (tx_count),
      .rx_count    (rx_count),
      .error_status(error_status),
      .intr_state  (intr_state),
      .intr_enable (intr_enable),
      .tx_enable   (tx_enable),
      .rx_enable   (rx_enable),
      .tx_busy     (tx_busy),
      .rx_active   (rx_active),
      .break_active(break_active),
      .tx_dma_stall(tx_dma_stall),
      .rx_dma_stall(rx_dma_stall),
      .tx          (tx),
      .irq         (irq)
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
      cover (rib_ready && rib_resp_err);
      cover (tx_busy);
      cover (rx_active);
      cover (irq);
      cover (error_status != 7'd0);
    end
  end

endmodule
