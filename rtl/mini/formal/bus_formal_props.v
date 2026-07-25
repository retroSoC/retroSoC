// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module bus_formal;

  (* anyseq *) (* gclk *)reg         clk_i;
  wire        rst_n_i;
  wire        f_past_valid;
  wire        core_valid;
  wire [31:0] core_addr;
  wire [31:0] core_wdata;
  wire [ 3:0] core_wstrb;
  wire        core_ready;
  wire        dma_valid;
  wire [31:0] dma_addr;
  wire [31:0] dma_wdata;
  wire [ 3:0] dma_wstrb;
  wire        dma_ready;
  wire        natv_valid;
  wire        apb_valid;
  wire        fault_valid;
  wire        fault_reserved;
  wire        fault_sel;
  wire        arb_locked;
  wire        arb_dma_owner;

  bus_formal_design u_design (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .f_past_valid  (f_past_valid),
      .core_valid    (core_valid),
      .core_addr     (core_addr),
      .core_wdata    (core_wdata),
      .core_wstrb    (core_wstrb),
      .core_ready    (core_ready),
      .dma_valid     (dma_valid),
      .dma_addr      (dma_addr),
      .dma_wdata     (dma_wdata),
      .dma_wstrb     (dma_wstrb),
      .dma_ready     (dma_ready),
      .natv_valid    (natv_valid),
      .apb_valid     (apb_valid),
      .fault_valid   (fault_valid),
      .fault_reserved(fault_reserved),
      .fault_sel     (fault_sel),
      .arb_locked    (arb_locked),
      .arb_dma_owner (arb_dma_owner)
  );

  always @(posedge clk_i) begin
    if (f_past_valid && $past(rst_n_i && core_valid && !core_ready)) begin
      assume (core_valid);
      assume (core_addr == $past(core_addr));
      assume (core_wdata == $past(core_wdata));
      assume (core_wstrb == $past(core_wstrb));
    end
    if (f_past_valid && $past(rst_n_i && dma_valid && !dma_ready)) begin
      assume (dma_valid);
      assume (dma_addr == $past(dma_addr));
      assume (dma_wdata == $past(dma_wdata));
      assume (dma_wstrb == $past(dma_wstrb));
    end

    if (rst_n_i) begin
      assert (!(natv_valid && apb_valid));
      assert (!(fault_valid && (natv_valid || apb_valid)));
      assert (fault_valid == fault_sel);
      if (f_past_valid && $past(rst_n_i && !arb_locked && dma_valid)) begin
        assert (arb_locked && arb_dma_owner);
      end
      if (f_past_valid && $past(rst_n_i && !arb_locked && core_valid && !dma_valid)) begin
        assert (arb_locked && !arb_dma_owner);
      end
      cover (arb_locked && arb_dma_owner);
      cover (fault_valid && fault_reserved);
    end
  end

endmodule
