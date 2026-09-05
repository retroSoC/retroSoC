// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module apu_codec_formal;
  (* anyseq *) (* gclk *) reg clk_i;
  wire rst_n_i, f_past_valid;
  wire [2:0] scenario;
  wire [5:0] cycle;
  wire block_new, context_ready, request_valid, request_ready;
  wire dma_request_valid, dma_request_ready, memory_claim, memory_request;
  wire [31:0] dma_request_addr, dma_request_bytes;
  wire fault_valid;
  wire [5:0] fault_code;
  wire [3:0] fault_stage;
  wire [31:0] fault_detail;

  apu_codec_formal_design u_design (.*);

  always @(posedge clk_i) begin
    if (rst_n_i) begin
      if (block_new) begin
        assert (!request_ready);
        assert (!dma_request_valid);
      end
      if (dma_request_valid) begin
        assert (dma_request_addr == 32'h1000_0000);
        assert (dma_request_bytes == 32'd4);
      end
      if (memory_claim) assert (memory_request);
      if (fault_valid && (scenario == 3'd1)) begin
        assert (fault_code == 6'd11);
        assert (fault_stage == 4'd11);
        assert (fault_detail[7:0] == 8'd5);
        assert (!dma_request_valid);
      end
      if (fault_valid && (scenario == 3'd2)) begin
        assert (fault_code == 6'd8);
        assert (fault_stage == 4'd8);
        assert (fault_detail[15:0] == 16'h0051);
        assert (!dma_request_valid);
      end
    end
    if (f_past_valid && $past(rst_n_i) && $past(dma_request_valid && !dma_request_ready)) begin
      assert (dma_request_valid);
      assert (dma_request_addr == $past(dma_request_addr));
      assert (dma_request_bytes == $past(dma_request_bytes));
    end
    cover (rst_n_i && context_ready);
    cover (rst_n_i && dma_request_valid && !block_new && (cycle >= 6'd22));
    cover (rst_n_i && block_new && request_valid && !request_ready);
    cover (rst_n_i && (scenario == 3'd1) && fault_valid && (fault_detail[7:0] == 8'd5));
    cover (rst_n_i && (scenario == 3'd2) && fault_valid &&
           (fault_detail[15:0] == 16'h0051));
  end
endmodule
