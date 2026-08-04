// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module rib_adapter_formal;
  (* anyseq *) (* gclk *)reg  clk_i;
  wire rst_n_i;
  wire f_past_valid;
  wire cmd_valid, cmd_ready, cmd_write;
  wire [31:0] cmd_addr;
  wire [ 1:0] cmd_len;
  wire w_valid, w_ready, wlast;
  wire [31:0] wdata;
  wire [ 3:0] wstrb;
  wire rsp_valid, rsp_ready, rsp_last;
  wire [31:0] rsp_rdata;
  wire [ 2:0] rsp_code;
  wire [ 1:0] rsp_beat;
  wire ribp_valid, ribp_ready;
  wire [31:0] ribp_addr, ribp_wdata;
  wire [3:0] ribp_wstrb;
  wire source_valid, source_ready;
  wire [31:0] source_addr;
  wire [ 3:0] source_wstrb;
  wire adapted_cmd_valid, adapted_cmd_ready;
  wire [31:0] adapted_cmd_addr;
  wire [ 1:0] adapted_cmd_len;
  wire adapted_w_valid, adapted_w_ready, adapted_wlast;
  wire [31:0] adapted_wdata;
  wire [ 3:0] adapted_wstrb;

  rib_adapter_formal_design u_design (.*);

  always @(posedge clk_i) begin
    if (f_past_valid && $past(rst_n_i && cmd_valid && !cmd_ready)) begin
      assume (cmd_valid);
      assume (cmd_addr == $past(cmd_addr));
      assume (cmd_write == $past(cmd_write));
      assume (cmd_len == $past(cmd_len));
    end
    if (f_past_valid && $past(rst_n_i && w_valid && !w_ready)) begin
      assume (w_valid);
      assume (wdata == $past(wdata));
      assume (wstrb == $past(wstrb));
      assume (wlast == $past(wlast));
    end
    if (f_past_valid && $past(rst_n_i && source_valid && !source_ready)) begin
      assume (source_valid);
      assume (source_addr == $past(source_addr));
      assume (source_wstrb == $past(source_wstrb));
    end
    if (rst_n_i) begin
      if (f_past_valid && $past(rst_n_i && ribp_valid && !ribp_ready)) begin
        assert (ribp_valid);
        assert (ribp_addr == $past(ribp_addr));
        assert (ribp_wdata == $past(ribp_wdata));
        assert (ribp_wstrb == $past(ribp_wstrb));
      end
      if (f_past_valid && $past(rst_n_i && rsp_valid && !rsp_ready)) begin
        assert (rsp_valid);
        assert (rsp_rdata == $past(rsp_rdata));
        assert (rsp_code == $past(rsp_code));
        assert (rsp_beat == $past(rsp_beat));
        assert (rsp_last == $past(rsp_last));
      end
      assert (rsp_beat <= 2'd3);
      if (adapted_cmd_valid) assert (adapted_cmd_len == 2'd0);
      if (adapted_w_valid) assert (adapted_wlast);
      if (f_past_valid && $past(rst_n_i && adapted_cmd_valid && !adapted_cmd_ready)) begin
        assert (adapted_cmd_valid);
        assert (adapted_cmd_addr == $past(adapted_cmd_addr));
      end
      if (f_past_valid && $past(rst_n_i && adapted_w_valid && !adapted_w_ready)) begin
        assert (adapted_w_valid);
        assert (adapted_wdata == $past(adapted_wdata));
        assert (adapted_wstrb == $past(adapted_wstrb));
        assert (adapted_wlast);
      end
      cover (ribp_valid && cmd_len == 2'd3 && ribp_addr == cmd_addr + 32'd12);
      cover (rsp_valid && rsp_last && rsp_beat == 2'd3);
      cover (adapted_w_valid && adapted_wlast);
    end
  end
endmodule
