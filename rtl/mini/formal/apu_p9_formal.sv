// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module apu_p9_formal_design (
    input  logic        clk_i,
    output logic        rst_n_i,
    output logic        f_past_valid,
    output logic        busy,
    output logic        valid,
    output logic        lock,
    output logic [31:0] actual_crc,
    output logic [63:0] coefficient_id,
    output logic [31:0] status,
    output logic [ 5:0] error_code,
    output logic        done,
    output logic        abort_done,
    output logic        dma_request_valid,
    output logic [31:0] dma_request_address,
    output logic [31:0] dma_request_bytes,
    output logic        store_active,
    output logic        store_req,
    output logic        store_write,
    output logic [13:0] store_addr
);
  logic s_start_q;
  (* anyseq *) logic s_abort;
  (* anyseq *) logic s_dma_request_ready;
  (* anyseq *) logic s_dma_valid;
  (* anyseq *) logic s_dma_done;
  (* anyseq *) logic s_dma_error;
  (* anyseq *) logic [31:0] s_dma_data;
  (* anyseq *) logic s_store_ready;
  (* anyseq *) logic s_store_valid;
  (* anyseq *) logic [31:0] s_store_data;
  (* anyseq *) logic s_store_fault;

  apu_kws_coeff_loader u_dut (
      .clk_i                   (clk_i),
      .rst_n_i                 (rst_n_i),
      .start_i                 (s_start_q),
      .abort_i                 (s_abort),
      .soft_reset_i            (1'b0),
      .resource_reset_request_i(1'b0),
      .resource_reset_i        (1'b0),
      .quiesce_i               (1'b1),
      .address_i               (32'h1000_0000),
      .size_i                  (32'd61504),
      .expected_crc_i          (32'h25e7_c27d),
      .acl_base_i              (32'h1000_0000),
      .acl_limit_i             (32'h1000_f03f),
      .dma_request_valid_o     (dma_request_valid),
      .dma_request_ready_i     (s_dma_request_ready),
      .dma_request_address_o   (dma_request_address),
      .dma_request_bytes_o     (dma_request_bytes),
      .dma_data_i              (s_dma_data),
      .dma_keep_i              (4'hf),
      .dma_last_i              (1'b0),
      .dma_valid_i             (s_dma_valid),
      .dma_ready_o             (),
      .dma_done_i              (s_dma_done),
      .dma_error_i             (s_dma_error),
      .dma_error_code_i        (6'd15),
      .dma_error_stage_i       (4'd3),
      .dma_error_resp_i        (2'd2),
      .dma_error_address_i     (32'h1000_0040),
      .store_active_o          (store_active),
      .store_req_o             (store_req),
      .store_write_o           (store_write),
      .store_addr_o            (store_addr),
      .store_data_o            (),
      .store_ready_i           (s_store_ready),
      .store_valid_i           (s_store_valid),
      .store_data_i            (s_store_data),
      .store_fault_i           (s_store_fault),
      .busy_o                  (busy),
      .valid_o                 (valid),
      .lock_o                  (lock),
      .actual_crc_o            (actual_crc),
      .coefficient_id_o        (coefficient_id),
      .status_o                (status),
      .error_code_o            (error_code),
      .error_stage_o           (),
      .error_resp_o            (),
      .error_address_o         (),
      .error_detail_o          (),
      .done_o                  (done),
      .abort_done_o            (abort_done)
  );

  initial begin
    rst_n_i      = 1'b0;
    f_past_valid = 1'b0;
    s_start_q    = 1'b0;
  end

  always_ff @(posedge clk_i) begin
    rst_n_i      <= 1'b1;
    f_past_valid <= 1'b1;
    s_start_q    <= !f_past_valid;
    if (rst_n_i) begin
      assume (!s_dma_valid || busy);
      assume (!s_dma_done || busy);
      assume (!s_store_valid || store_active);
    end
  end
endmodule
