// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module apu_p9_formal;
  (* anyseq *) (* gclk *) reg clk_i;
  wire rst_n_i;
  wire f_past_valid;
  wire busy;
  wire valid;
  wire lock;
  wire [31:0] actual_crc;
  wire [63:0] coefficient_id;
  wire [31:0] status;
  wire [5:0] error_code;
  wire done;
  wire abort_done;
  wire dma_request_valid;
  wire [31:0] dma_request_address;
  wire [31:0] dma_request_bytes;
  wire store_active;
  wire store_req;
  wire store_write;
  wire [13:0] store_addr;

  apu_p9_formal_design u_design (.*);

  always @(posedge clk_i) begin
    if (rst_n_i) begin
      assert (valid == lock);
      assert (!(done && abort_done));
      assert (!store_req || store_active);
      assert (!store_req || (store_addr < 14'd15360));
      if (store_write) assert (store_active && busy);
      if (valid) begin
        assert (actual_crc == 32'h25e7_c27d);
        assert (coefficient_id == 64'h806c_780d_8a0b_038d);
        assert (status[2:1] == 2'b11);
      end
      if (done && valid) assert (!busy);
      if (done && (error_code != 6'd0)) begin
        assert (!valid);
        assert (!lock);
      end
      if (dma_request_valid) begin
        assert (busy);
        assert ((dma_request_address == 32'h1000_0000) || (dma_request_address == 32'h1000_0040));
        assert ((dma_request_bytes == 32'd64) || (dma_request_bytes == 32'd61440));
      end
    end
    cover (rst_n_i && dma_request_valid);
    cover (rst_n_i && abort_done && !done);
  end
endmodule
