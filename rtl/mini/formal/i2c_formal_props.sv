// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module i2c_formal;
  (* anyseq, gclk *) logic clk_i;
  wire        rst_n_i;
  wire        f_past_valid;
  wire        rib_valid;
  wire [31:0] rib_addr;
  wire [31:0] rib_wdata;
  wire [ 3:0] rib_wstrb;
  wire        rib_ready;
  wire        rib_resp_err;
  wire [ 4:0] command_count;
  wire [ 4:0] rx_count;
  wire [10:0] error_status;
  wire [ 7:0] intr_state;
  wire [ 7:0] intr_enable;
  wire        command_valid;
  wire        command_pop;
  wire        rx_full;
  wire        rx_push;
  wire        busy;
  wire        recovery_active;
  wire        scl_o;
  wire        sda_o;
  wire        scl_oe;
  wire        sda_oe;
  wire        tx_dma_stall;
  wire        rx_dma_stall;
  wire        irq;

  i2c_formal_design u_design (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .f_past_valid   (f_past_valid),
      .rib_valid      (rib_valid),
      .rib_addr       (rib_addr),
      .rib_wdata      (rib_wdata),
      .rib_wstrb      (rib_wstrb),
      .rib_ready      (rib_ready),
      .rib_resp_err   (rib_resp_err),
      .command_count  (command_count),
      .rx_count       (rx_count),
      .error_status   (error_status),
      .intr_state     (intr_state),
      .intr_enable    (intr_enable),
      .command_valid  (command_valid),
      .command_pop    (command_pop),
      .rx_full        (rx_full),
      .rx_push        (rx_push),
      .busy           (busy),
      .recovery_active(recovery_active),
      .scl_o          (scl_o),
      .sda_o          (sda_o),
      .scl_oe         (scl_oe),
      .sda_oe         (sda_oe),
      .tx_dma_stall   (tx_dma_stall),
      .rx_dma_stall   (rx_dma_stall),
      .irq            (irq)
  );

  always @(posedge clk_i) begin
    if (f_past_valid && $past(rst_n_i && rib_valid && !rib_ready)) begin
      assume (rib_valid);
      assume (rib_addr == $past(rib_addr));
      assume (rib_wdata == $past(rib_wdata));
      assume (rib_wstrb == $past(rib_wstrb));
    end

    if (rst_n_i) begin
      assert (command_count <= 5'd16);
      assert (rx_count <= 5'd16);
      assert (!scl_o);
      assert (!sda_o);
      assert (irq == |(intr_state & intr_enable));
      if (command_pop) assert (command_valid);
      if (!busy) begin
        assert (!scl_oe);
        assert (!sda_oe);
      end
      if (recovery_active) assert (busy);

      cover (rib_ready && rib_resp_err);
      cover (command_count != 5'd0);
      cover (rx_count != 5'd0);
      cover (busy && scl_oe);
      cover (busy && sda_oe);
      cover (recovery_active);
      cover (irq);
      cover (error_status != 11'd0);
      cover (!tx_dma_stall);
      cover (!rx_dma_stall);
    end
  end

endmodule
