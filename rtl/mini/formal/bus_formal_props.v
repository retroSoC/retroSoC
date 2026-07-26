// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module bus_formal;

  (* anyseq *) (* gclk *)reg         clk_i;
  wire        rst_n_i;
  wire        f_past_valid;
  wire        mgmt_valid;
  wire [31:0] mgmt_addr;
  wire [ 3:0] mgmt_wstrb;
  wire        mgmt_ready;
  wire        user_valid;
  wire [31:0] user_addr;
  wire [ 3:0] user_wstrb;
  wire        user_ready;
  wire        dma_valid;
  wire        dma_ready;
  wire        natv_valid;
  wire        apb_valid;
  wire        fault_valid;
  wire        fault_access;
  wire        arb_locked;
  wire [ 1:0] arb_owner;

  bus_formal_design u_design (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .f_past_valid(f_past_valid),
      .mgmt_valid  (mgmt_valid),
      .mgmt_addr   (mgmt_addr),
      .mgmt_wstrb  (mgmt_wstrb),
      .mgmt_ready  (mgmt_ready),
      .user_valid  (user_valid),
      .user_addr   (user_addr),
      .user_wstrb  (user_wstrb),
      .user_ready  (user_ready),
      .dma_valid   (dma_valid),
      .dma_ready   (dma_ready),
      .natv_valid  (natv_valid),
      .apb_valid   (apb_valid),
      .fault_valid (fault_valid),
      .fault_access(fault_access),
      .arb_locked  (arb_locked),
      .arb_owner   (arb_owner)
  );

  always @(posedge clk_i) begin
    if (f_past_valid && $past(rst_n_i && mgmt_valid && !mgmt_ready)) begin
      assume (mgmt_valid);
      assume (mgmt_addr == $past(mgmt_addr));
      assume (mgmt_wstrb == $past(mgmt_wstrb));
    end
    if (f_past_valid && $past(rst_n_i && user_valid && !user_ready)) begin
      assume (user_valid);
      assume (user_addr == $past(user_addr));
      assume (user_wstrb == $past(user_wstrb));
    end
    if (rst_n_i) begin
      assert (!(natv_valid && apb_valid));
      assert (!(fault_valid && (natv_valid || apb_valid)));
      if (fault_access) begin
        assert (fault_valid);
      end
      if (f_past_valid && $past(
              rst_n_i && !arb_locked && mgmt_valid && !user_valid && !dma_valid
          )) begin
        assert (arb_locked && arb_owner == 2'd0);
      end
      cover (arb_locked && arb_owner == 2'd1);
      cover (fault_access);
    end
  end

endmodule
