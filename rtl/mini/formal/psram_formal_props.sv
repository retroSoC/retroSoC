// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module psram_formal;

  (* anyseq *) (* gclk *)reg          clk_i;

  logic        rst_n_i;
  logic        f_past_valid;
  logic        awvalid;
  logic        awready;
  logic [31:0] awaddr;
  logic [ 7:0] awlen;
  logic [ 2:0] awsize;
  logic [ 1:0] awburst;
  logic        wvalid;
  logic        wready;
  logic [31:0] wdata;
  logic [ 3:0] wstrb;
  logic        wlast;
  logic        bvalid;
  logic        bready;
  logic [ 1:0] bresp;
  logic        arvalid;
  logic        arready;
  logic [31:0] araddr;
  logic [ 7:0] arlen;
  logic [ 2:0] arsize;
  logic [ 1:0] arburst;
  logic        rvalid;
  logic        rready;
  logic [31:0] rdata;
  logic [ 1:0] rresp;
  logic        rlast;
  logic        mem_req_valid;
  logic        mem_req_ready;
  logic        mem_req_write;
  logic [ 1:0] mem_req_chip;
  logic [22:0] mem_req_addr;
  logic [ 2:0] mem_req_len;
  logic [31:0] mem_req_wdata;
  logic        phy_abort;
  logic        phy_req_valid;
  logic        phy_req_ready;
  logic [ 3:0] phy_req_cmd;
  logic [ 1:0] phy_req_chip;
  logic        phy_req_qpi;
  logic [22:0] phy_req_addr;
  logic [ 5:0] phy_req_len;
  logic [63:0] phy_req_wdata;
  logic        phy_busy;
  logic        phy_done;
  logic        phy_error;
  logic        phy_sclk;
  logic [ 3:0] phy_nss;
  logic [ 3:0] phy_io_oe;
  logic [ 3:0] phy_io_do;

  psram_formal_design u_design (.*);

  always @(posedge clk_i) begin
    if (f_past_valid && $past(rst_n_i)) begin
      if ($past(awvalid && !awready)) begin
        assume (awvalid);
        assume (awaddr == $past(awaddr));
        assume (awlen == $past(awlen));
        assume (awsize == $past(awsize));
        assume (awburst == $past(awburst));
      end
      if ($past(wvalid && !wready)) begin
        assume (wvalid);
        assume (wdata == $past(wdata));
        assume (wstrb == $past(wstrb));
        assume (wlast == $past(wlast));
      end
      if ($past(arvalid && !arready)) begin
        assume (arvalid);
        assume (araddr == $past(araddr));
        assume (arlen == $past(arlen));
        assume (arsize == $past(arsize));
        assume (arburst == $past(arburst));
      end
      if ($past(bvalid && !bready)) begin
        assert (bvalid);
        assert (bresp == $past(bresp));
      end
      if ($past(rvalid && !rready)) begin
        assert (rvalid);
        assert (rdata == $past(rdata));
        assert (rresp == $past(rresp));
        assert (rlast == $past(rlast));
      end
      if ($past(mem_req_valid && !mem_req_ready)) begin
        assert (mem_req_valid);
        assert (mem_req_write == $past(mem_req_write));
        assert (mem_req_chip == $past(mem_req_chip));
        assert (mem_req_addr == $past(mem_req_addr));
        assert (mem_req_len == $past(mem_req_len));
        assert (mem_req_wdata == $past(mem_req_wdata));
      end
      if ($past(phy_req_valid && !phy_req_ready)) begin
        assume (phy_req_valid);
        assume (phy_req_cmd == $past(phy_req_cmd));
        assume (phy_req_chip == $past(phy_req_chip));
        assume (phy_req_qpi == $past(phy_req_qpi));
        assume (phy_req_addr == $past(phy_req_addr));
        assume (phy_req_len == $past(phy_req_len));
        assume (phy_req_wdata == $past(phy_req_wdata));
      end
      if ($past(phy_abort && phy_busy)) begin
        assert (phy_nss == 4'hF);
        assert (!phy_sclk);
        assert (phy_done);
        assert (phy_error);
      end
    end

    if (rst_n_i) begin
      assume (phy_req_cmd <= 4'd10);
      assume ((phy_req_len >= 6'd1) && (phy_req_len <= 6'd8));
      assert (!((awvalid && awready) && (arvalid && arready)));
      assert ((~phy_nss & ((~phy_nss) - 1'b1)) == 4'd0);
      if (phy_done) begin
        assert (phy_nss == 4'hF);
        assert (!phy_sclk);
      end

      cover (awvalid && awready);
      cover (bvalid && (bresp == 2'b00));
      cover (bvalid && (bresp == 2'b10));
      cover (arvalid && arready);
      cover (rvalid && (rresp == 2'b00));
      cover (rvalid && (rresp == 2'b10));
      cover (mem_req_valid && mem_req_write);
      cover (mem_req_valid && !mem_req_write);
      cover (phy_done && !phy_error);
      cover (phy_done && phy_error);
    end
  end

endmodule
