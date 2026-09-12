// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module apu_kws_formal;
  (* anyseq *) (* gclk *)reg         clk_i;
  wire        rst_n_i;
  wire        f_past_valid;
  wire        dma_request_valid;
  wire [31:0] dma_request_address;
  wire [31:0] dma_request_bytes;
  wire        dma_ready;
  wire        local_request;
  wire        valid;
  wire        lock;
  wire        done;
  wire        abort_done;
  wire        loader_busy;
  wire [ 5:0] error_code;
  wire [ 3:0] error_stage;
  wire [ 1:0] error_resp;
  wire [31:0] error_address;
  wire [31:0] error_detail;
  wire        early_error_pending;
  wire [ 5:0] expected_error_code;
  wire [ 3:0] expected_error_stage;
  wire [ 1:0] expected_error_resp;
  wire [31:0] expected_error_address;
  wire [31:0] requested_size;
  wire        kws_direct_allowed;
  wire        kws_start;
  wire        kws_start_ready;
  wire        kws_abort;
  wire        kws_direct_done;
  wire        kws_transport_start;
  wire        kws_busy;
  wire        kws_idle;

  apu_kws_formal_design u_design (.*);

  always @(posedge clk_i) begin
    if (rst_n_i) begin
      assert (!local_request);
      assert (!valid);
      assert (!lock);
      assert (valid == lock);
      assert (!(done && abort_done));
      if (done || abort_done) assert (!loader_busy);
      if (abort_done) begin
        assert (!valid);
        assert (!lock);
        assert (error_code == 6'd0);
      end
      if (done && early_error_pending) begin
        assert (error_code == expected_error_code);
        assert (error_stage == expected_error_stage);
        assert (error_resp == expected_error_resp);
        assert (error_address == expected_error_address);
        assert (error_detail == 32'd0);
      end
      assert (!kws_transport_start);
      if (kws_idle) assert (kws_direct_allowed);
      if (kws_start) assert (kws_busy);
      if (kws_direct_done) assert (kws_idle);
      if ($past(rst_n_i && kws_start && !kws_start_ready && !kws_abort) && !kws_abort) begin
        assert (kws_start);
        assert (kws_busy);
      end
      if ($past(rst_n_i && kws_start && kws_abort)) begin
        assert (kws_direct_done);
        assert (kws_idle);
      end
      if (requested_size != 32'd32768) begin
        assert (!dma_request_valid);
        assert (!dma_ready);
        if (done) assert (error_code == 6'd12);
      end
      if (dma_request_valid) begin
        assert (requested_size == 32'd32768);
        assert (dma_request_address == 32'h1000_0000);
        assert (dma_request_bytes == 32'd64);
      end
    end
    cover (rst_n_i && done && (requested_size != 32'd32768) && (error_code == 6'd12));
    cover (rst_n_i && dma_request_valid && (requested_size == 32'd32768));
    cover (rst_n_i && done && early_error_pending && (error_detail == 32'd0));
    cover (rst_n_i && abort_done && !done && !loader_busy);
    cover (rst_n_i && kws_start);
    cover (rst_n_i && kws_start && !kws_start_ready && !kws_abort);
    cover (rst_n_i && kws_start && kws_abort);
    cover (rst_n_i && kws_direct_done && kws_idle);
  end
endmodule
