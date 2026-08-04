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
  wire        user_cmd_valid;
  wire        user_cmd_ready;
  wire [31:0] user_cmd_addr;
  wire        user_cmd_write;
  wire [ 1:0] user_cmd_len;
  wire        dma_cmd_valid;
  wire        dma_cmd_ready;
  wire [31:0] dma_cmd_addr;
  wire        dma_cmd_write;
  wire [ 1:0] dma_cmd_len;
  wire        rib_cmd_valid;
  wire [ 1:0] rib_cmd_len;
  wire        apb_valid;
  wire        fault_valid;
  wire        fault_access;
  wire        arb_locked;
  wire [ 1:0] arb_owner;
  wire        cmd_accepted;
  wire        terminal_rsp;

  bus_formal_design u_design (.*);

  always @(posedge clk_i) begin
    if (f_past_valid && $past(rst_n_i && mgmt_valid && !mgmt_ready)) begin
      assume (mgmt_valid);
      assume (mgmt_addr == $past(mgmt_addr));
      assume (mgmt_wstrb == $past(mgmt_wstrb));
    end
    if (f_past_valid && $past(rst_n_i && user_cmd_valid && !user_cmd_ready)) begin
      assume (user_cmd_valid);
      assume (user_cmd_addr == $past(user_cmd_addr));
      assume (user_cmd_write == $past(user_cmd_write));
      assume (user_cmd_len == $past(user_cmd_len));
    end
    if (f_past_valid && $past(rst_n_i && dma_cmd_valid && !dma_cmd_ready)) begin
      assume (dma_cmd_valid);
      assume (dma_cmd_addr == $past(dma_cmd_addr));
      assume (dma_cmd_write == $past(dma_cmd_write));
      assume (dma_cmd_len == $past(dma_cmd_len));
    end
    if (rst_n_i) begin
      assert (!(rib_cmd_valid && apb_valid));
      assert (!(fault_valid && (rib_cmd_valid || apb_valid)));
      assert (!cmd_accepted || arb_locked);
      if (rib_cmd_valid) begin
        assert (rib_cmd_len == 2'd0 || rib_cmd_len == 2'd3);
      end
      if (f_past_valid && $past(rst_n_i && arb_locked && !terminal_rsp)) begin
        assert (arb_locked);
        assert (arb_owner == $past(arb_owner));
      end
      if (f_past_valid && $past(rst_n_i && cmd_accepted && !terminal_rsp)) begin
        assert (cmd_accepted);
      end
      cover (rib_cmd_valid && rib_cmd_len == 2'd3);
      cover (arb_locked && arb_owner == 2'd1);
      cover (arb_locked && arb_owner == 2'd2);
      cover (fault_valid && fault_access);
    end
  end

endmodule
