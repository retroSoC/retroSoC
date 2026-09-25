// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module apu_kws_coeff_store (
    // verilog_format: off -- preserve the four coefficient-client columns
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        abort_i,
    input  logic        valid_i,
    input  logic        loader_active_i,
    input  logic        loader_req_i,
    input  logic        loader_write_i,
    input  logic [13:0] loader_addr_i,
    input  logic [31:0] loader_data_i,
    output logic        loader_ready_o,
    output logic        loader_valid_o,
    output logic [31:0] loader_data_o,
    output logic        loader_fault_o,
    input  logic        frontend_req_valid_i,
    output logic        frontend_req_ready_o,
    input  logic [ 3:0] frontend_kind_i,
    input  logic [13:0] frontend_index_i,
    output logic        frontend_resp_valid_o,
    input  logic        frontend_resp_ready_i,
    output logic [63:0] frontend_resp_data_o,
    output logic        frontend_resp_fault_o,
    input  logic        inference_req_valid_i,
    output logic        inference_req_ready_o,
    input  logic [ 6:0] inference_index_i,
    output logic        inference_resp_valid_o,
    input  logic        inference_resp_ready_i,
    output logic [31:0] inference_resp_data_o,
    output logic        inference_resp_fault_o,
    input  logic        profile_req_valid_i,
    output logic        profile_req_ready_o,
    input  logic [10:0] profile_index_i,
    output logic        profile_resp_valid_o,
    input  logic        profile_resp_ready_i,
    output logic [31:0] profile_resp_data_o,
    output logic        profile_resp_fault_o
    // verilog_format: on
);
  localparam int unsigned BankCount = 15;

  logic [BankCount-1:0]       s_bank_cs;
  logic [BankCount-1:0]       s_bank_wren;
  logic [BankCount-1:0][ 9:0] s_bank_addr;
  logic [BankCount-1:0][31:0] s_bank_wdata;
  logic [BankCount-1:0][31:0] s_bank_rdata;

  logic                       s_front_legal;
  logic [3:0] s_front_bank_low, s_front_bank_high;
  logic [9:0] s_front_row_low, s_front_row_high;
  logic s_front_pair;
  logic s_front_accept;
  logic s_front_pending_q;
  logic s_front_fault_q;
  logic [3:0] s_front_bank_low_q, s_front_bank_high_q;
  logic       s_front_pair_q;

  logic       s_infer_legal;
  logic       s_infer_accept;
  logic       s_infer_pending_q;
  logic       s_infer_fault_q;

  logic       s_profile_legal;
  logic [3:0] s_profile_bank;
  logic [9:0] s_profile_row;
  logic       s_profile_accept;
  logic       s_profile_pending_q;
  logic       s_profile_fault_q;
  logic [3:0] s_profile_bank_q;

  logic       s_loader_accept;
  logic       s_loader_pending_q;
  logic       s_loader_fault_q;
  logic [3:0] s_loader_bank_q;

  always_comb begin
    s_front_legal     = 1'b1;
    s_front_bank_low  = 4'd0;
    s_front_bank_high = 4'd0;
    s_front_row_low   = 10'd0;
    s_front_row_high  = 10'd0;
    s_front_pair      = 1'b0;
    unique case (frontend_kind_i)
      4'd0: begin
        s_front_legal   = frontend_index_i < 14'd480;
        s_front_row_low = frontend_index_i[9:0];
      end
      4'd1: begin
        s_front_legal     = frontend_index_i < 14'd256;
        s_front_bank_low  = 4'd1;
        s_front_bank_high = 4'd2;
        s_front_row_low   = frontend_index_i[9:0];
        s_front_row_high  = frontend_index_i[9:0];
        s_front_pair      = 1'b1;
      end
      4'd2: begin
        s_front_legal = frontend_index_i < 14'd10280;
        if (frontend_index_i < 14'd10240) begin
          s_front_bank_low = 4'd3 + frontend_index_i[13:10];
          s_front_row_low  = frontend_index_i[9:0];
        end else begin
          s_front_bank_low = 4'd13;
          s_front_row_low  = 10'(frontend_index_i - 14'd10240);
        end
      end
      4'd3: begin
        s_front_legal   = frontend_index_i < 14'd400;
        s_front_row_low = 10'd480 + frontend_index_i[9:0];
      end
      4'd4: begin
        s_front_legal = frontend_index_i < 14'd1024;
        s_front_pair  = 1'b1;
        if (!frontend_index_i[0]) begin
          s_front_bank_low  = 4'd1;
          s_front_bank_high = 4'd2;
          s_front_row_low   = 10'd256 + frontend_index_i[10:1];
          s_front_row_high  = 10'd256 + frontend_index_i[10:1];
        end else begin
          s_front_bank_low  = 4'd2;
          s_front_bank_high = 4'd1;
          s_front_row_low   = 10'd256 + frontend_index_i[10:1];
          s_front_row_high  = 10'd257 + frontend_index_i[10:1];
        end
      end
      4'd5: begin
        s_front_legal   = frontend_index_i < 14'd63;
        s_front_row_low = 10'd880 + frontend_index_i[9:0];
      end
      4'd6: begin
        s_front_legal   = frontend_index_i < 14'd63;
        s_front_row_low = 10'd943 + frontend_index_i[9:0];
      end
      default: s_front_legal = 1'b0;
    endcase
  end

  assign s_infer_legal = inference_index_i < 7'd125;
  always_comb begin
    s_profile_legal = profile_index_i < 11'd1496;
    if (profile_index_i < 11'd984) begin
      s_profile_bank = 4'd13;
      s_profile_row  = 10'd40 + profile_index_i[9:0];
    end else begin
      s_profile_bank = 4'd14;
      s_profile_row  = 10'(profile_index_i - 11'd984);
    end
  end

  assign loader_ready_o = loader_active_i;
  assign frontend_req_ready_o = !loader_active_i && !profile_req_valid_i &&
      !s_front_pending_q && (!frontend_resp_valid_o || frontend_resp_ready_i);
  assign inference_req_ready_o = !loader_active_i && !profile_req_valid_i &&
      !s_infer_pending_q && (!inference_resp_valid_o || inference_resp_ready_i);
  assign profile_req_ready_o = !loader_active_i && !frontend_req_valid_i &&
      !inference_req_valid_i && !s_profile_pending_q &&
      (!profile_resp_valid_o || profile_resp_ready_i);
  assign s_loader_accept = loader_req_i && loader_ready_o;
  assign s_front_accept = frontend_req_valid_i && frontend_req_ready_o;
  assign s_infer_accept = inference_req_valid_i && inference_req_ready_o;
  assign s_profile_accept = profile_req_valid_i && profile_req_ready_o;

  always_comb begin
    s_bank_cs    = BankCount'(0);
    s_bank_wren  = BankCount'(0);
    s_bank_addr  = '0;
    s_bank_wdata = '0;
    if (s_loader_accept && (loader_addr_i < 14'd15360)) begin
      s_bank_cs[loader_addr_i[13:10]]    = 1'b1;
      s_bank_wren[loader_addr_i[13:10]]  = loader_write_i;
      s_bank_addr[loader_addr_i[13:10]]  = loader_addr_i[9:0];
      s_bank_wdata[loader_addr_i[13:10]] = loader_data_i;
    end else begin
      if (s_profile_accept && s_profile_legal && valid_i) begin
        s_bank_cs[s_profile_bank]   = 1'b1;
        s_bank_addr[s_profile_bank] = s_profile_row;
      end else begin
        if (s_front_accept && s_front_legal && valid_i) begin
          s_bank_cs[s_front_bank_low]   = 1'b1;
          s_bank_addr[s_front_bank_low] = s_front_row_low;
          if (s_front_pair) begin
            s_bank_cs[s_front_bank_high]   = 1'b1;
            s_bank_addr[s_front_bank_high] = s_front_row_high;
          end
        end
        if (s_infer_accept && s_infer_legal && valid_i) begin
          s_bank_cs[14]   = 1'b1;
          s_bank_addr[14] = 10'd512 + {3'd0, inference_index_i};
        end
      end
    end
  end

  for (genvar bank = 0; bank < BankCount; bank++) begin : gen_coefficient_bank
`ifdef HAVE_SRAM_MACRO
    tc_sram_1024x32 u_coefficient_sram (
        .clk_i (clk_i),
        .cs_i  (s_bank_cs[bank]),
        .addr_i(s_bank_addr[bank]),
        .data_i(s_bank_wdata[bank]),
        .mask_i(4'hf),
        .wren_i(s_bank_wren[bank]),
        .data_o(s_bank_rdata[bank])
    );
`else
    logic [31:0] s_storage_q[0:1023];
    always_ff @(posedge clk_i) begin
      if (s_bank_cs[bank]) begin
        if (s_bank_wren[bank]) begin
          s_storage_q[s_bank_addr[bank]] <= s_bank_wdata[bank];
        end else begin
          s_bank_rdata[bank] <= s_storage_q[s_bank_addr[bank]];
        end
      end
    end
`endif
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_front_pending_q      <= 1'b0;
      s_front_fault_q        <= 1'b0;
      s_front_bank_low_q     <= 4'd0;
      s_front_bank_high_q    <= 4'd0;
      s_front_pair_q         <= 1'b0;
      frontend_resp_valid_o  <= 1'b0;
      frontend_resp_data_o   <= 64'd0;
      frontend_resp_fault_o  <= 1'b0;
      s_infer_pending_q      <= 1'b0;
      s_infer_fault_q        <= 1'b0;
      inference_resp_valid_o <= 1'b0;
      inference_resp_data_o  <= 32'd0;
      inference_resp_fault_o <= 1'b0;
      s_profile_pending_q    <= 1'b0;
      s_profile_fault_q      <= 1'b0;
      s_profile_bank_q       <= 4'd0;
      profile_resp_valid_o   <= 1'b0;
      profile_resp_data_o    <= 32'd0;
      profile_resp_fault_o   <= 1'b0;
      s_loader_pending_q     <= 1'b0;
      s_loader_fault_q       <= 1'b0;
      s_loader_bank_q        <= 4'd0;
      loader_valid_o         <= 1'b0;
      loader_data_o          <= 32'd0;
      loader_fault_o         <= 1'b0;
    end else if (abort_i) begin
      s_front_pending_q      <= 1'b0;
      frontend_resp_valid_o  <= 1'b0;
      s_infer_pending_q      <= 1'b0;
      inference_resp_valid_o <= 1'b0;
      s_profile_pending_q    <= 1'b0;
      profile_resp_valid_o   <= 1'b0;
      s_loader_pending_q     <= 1'b0;
      loader_valid_o         <= 1'b0;
    end else begin
      if (frontend_resp_valid_o && frontend_resp_ready_i) frontend_resp_valid_o <= 1'b0;
      if (inference_resp_valid_o && inference_resp_ready_i) inference_resp_valid_o <= 1'b0;
      if (profile_resp_valid_o && profile_resp_ready_i) profile_resp_valid_o <= 1'b0;
      loader_valid_o <= s_loader_pending_q || (s_loader_accept && loader_write_i);
      if (s_loader_pending_q) begin
        loader_fault_o <= s_loader_fault_q;
        loader_data_o  <= s_loader_fault_q ? 32'd0 : s_bank_rdata[s_loader_bank_q];
      end else if (s_loader_accept && loader_write_i) begin
        loader_fault_o <= loader_addr_i >= 14'd15360;
      end

      if (s_front_accept) begin
        s_front_pending_q   <= 1'b1;
        s_front_fault_q     <= !s_front_legal || !valid_i;
        s_front_bank_low_q  <= s_front_bank_low;
        s_front_bank_high_q <= s_front_bank_high;
        s_front_pair_q      <= s_front_pair;
      end else if (s_front_pending_q) begin
        s_front_pending_q <= 1'b0;
        frontend_resp_valid_o <= 1'b1;
        frontend_resp_fault_o <= s_front_fault_q;
        frontend_resp_data_o  <= s_front_fault_q ? 64'd0 :
            {s_front_pair_q ? s_bank_rdata[s_front_bank_high_q] : 32'd0,
             s_bank_rdata[s_front_bank_low_q]};
      end

      if (s_infer_accept) begin
        s_infer_pending_q <= 1'b1;
        s_infer_fault_q   <= !s_infer_legal || !valid_i;
      end else if (s_infer_pending_q) begin
        s_infer_pending_q      <= 1'b0;
        inference_resp_valid_o <= 1'b1;
        inference_resp_fault_o <= s_infer_fault_q;
        inference_resp_data_o  <= s_infer_fault_q ? 32'd0 : s_bank_rdata[14];
      end

      if (s_profile_accept) begin
        s_profile_pending_q <= 1'b1;
        s_profile_fault_q   <= !s_profile_legal || !valid_i;
        s_profile_bank_q    <= s_profile_bank;
      end else if (s_profile_pending_q) begin
        s_profile_pending_q  <= 1'b0;
        profile_resp_valid_o <= 1'b1;
        profile_resp_fault_o <= s_profile_fault_q;
        profile_resp_data_o  <= s_profile_fault_q ? 32'd0 : s_bank_rdata[s_profile_bank_q];
      end

      if (s_loader_accept) begin
        s_loader_fault_q <= loader_addr_i >= 14'd15360;
        s_loader_bank_q <= loader_addr_i[13:10];
        s_loader_pending_q <= !loader_write_i;
      end else begin
        s_loader_pending_q <= 1'b0;
      end
    end
  end
endmodule
