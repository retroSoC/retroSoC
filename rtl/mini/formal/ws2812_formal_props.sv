// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module ws2812_formal;

  (* anyseq *) (* gclk *)reg         clk_i;
  wire        rst_n_i;
  wire        f_past_valid;
  wire        rib_valid;
  wire [31:0] rib_addr;
  wire [31:0] rib_wdata;
  wire [ 3:0] rib_wstrb;
  wire        rib_ready;
  wire        rib_resp_err;
  wire        dat;
  wire        irq;
  wire        busy;
  wire        reset_active;
  wire        start;
  wire        abort_cmd;
  wire        data_valid;
  wire        data_pop;
  wire        done;
  wire        underflow;
  wire        aborted;
  wire [ 4:0] fifo_level;
  wire [31:0] load_remaining;
  wire [ 2:0] error_status;
  wire [ 3:0] intr_state;
  wire [ 3:0] intr_enable;

  ws2812_formal_design u_design (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .f_past_valid  (f_past_valid),
      .rib_valid     (rib_valid),
      .rib_addr      (rib_addr),
      .rib_wdata     (rib_wdata),
      .rib_wstrb     (rib_wstrb),
      .rib_ready     (rib_ready),
      .rib_resp_err  (rib_resp_err),
      .dat           (dat),
      .irq           (irq),
      .busy          (busy),
      .reset_active  (reset_active),
      .start         (start),
      .abort_cmd     (abort_cmd),
      .data_valid    (data_valid),
      .data_pop      (data_pop),
      .done          (done),
      .underflow     (underflow),
      .aborted       (aborted),
      .fifo_level    (fifo_level),
      .load_remaining(load_remaining),
      .error_status  (error_status),
      .intr_state    (intr_state),
      .intr_enable   (intr_enable)
  );

  always @(posedge clk_i) begin
    if (f_past_valid && $past(rst_n_i && rib_valid && !rib_ready)) begin
      assume (rib_valid);
      assume (rib_addr == $past(rib_addr));
      assume (rib_wdata == $past(rib_wdata));
      assume (rib_wstrb == $past(rib_wstrb));
    end

    if (rst_n_i) begin
      assert (fifo_level <= 5'd16);
      assert (irq == |(intr_state & intr_enable));
      if (!busy || reset_active) begin
        assert (!dat);
      end
      if (data_pop) begin
        assert (data_valid);
      end
      if (f_past_valid && $past(rst_n_i && start)) begin
        assert (busy);
      end
      if (f_past_valid && $past(rst_n_i && done)) begin
        assert (intr_state[0]);
      end
      if (f_past_valid && $past(rst_n_i && underflow)) begin
        assert (error_status[1]);
        assert (intr_state[2]);
      end
      if (f_past_valid && $past(rst_n_i && aborted)) begin
        assert (intr_state[3]);
      end

      cover (busy && dat);
      cover (reset_active);
      cover (busy && (load_remaining != 32'd0) && (fifo_level == 5'd0));
      cover (aborted);
      cover (irq);
      cover (rib_ready && rib_resp_err);
    end
  end

endmodule
