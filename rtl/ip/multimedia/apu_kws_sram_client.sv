// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "apu_define.svh"

module apu_kws_sram_client (
    // verilog_format: off -- preserve model-loader and engine storage columns
    input  logic                    clk_i,
    input  logic                    rst_n_i,
    input  logic                    req_i,
    input  logic                    write_i,
    input  logic [16:0]             addr_i,
    input  logic [31:0]             data_i,
    input  logic [ 3:0]             strb_i,
    output logic                    ready_o,
    output logic [31:0]             data_o,
    output logic                    valid_o,
    output logic                    access_err_o,
    input  logic                    access_req_i,
    output logic                    access_ready_o,
    output logic                    access_done_o,
    output logic                    access_progress_o,
    input  logic                    access_write_i,
    input  logic [15:0]             model_read_valid_i,
    input  logic [15:0][14:0]       model_addr_i,
    output logic [15:0][ 7:0]       model_data_o,
    input  logic                    scratch_clear_i,
    input  logic [19:0]             scratch_read_valid_i,
    input  logic [19:0][15:0]       scratch_read_addr_i,
    output logic [19:0][31:0]       scratch_read_data_o,
    input  logic [ 5:0]             scratch_write_valid_i,
    input  logic [ 5:0][15:0]       scratch_write_addr_i,
    input  logic [ 5:0][31:0]       scratch_write_data_i,
    input  logic [ 5:0][ 3:0]       scratch_write_strb_i,
    output logic                    scratch_access_err_o
    // verilog_format: on
);
  localparam int unsigned BankCount = 16;
  localparam int unsigned FirEntryCount = 63;

  logic [    BankCount-1:0]       s_bank_cs;
  logic [    BankCount-1:0]       s_bank_wren;
  logic [    BankCount-1:0][ 9:0] s_bank_addr;
  logic [    BankCount-1:0][31:0] s_bank_wdata;
  logic [    BankCount-1:0][ 3:0] s_bank_wmask;
  logic [    BankCount-1:0][31:0] s_bank_rdata;

  logic                           s_busy_q;
  logic [             15:0]       s_model_pending_q;
  logic [             15:0][14:0] s_model_addr_q;
  logic [             19:0]       s_scratch_read_pending_q;
  logic [             19:0][15:0] s_scratch_read_addr_q;
  logic [              5:0]       s_scratch_write_pending_q;
  logic [              5:0][15:0] s_scratch_write_addr_q;
  logic [              5:0][31:0] s_scratch_write_data_q;
  logic [              5:0][ 3:0] s_scratch_write_strb_q;
  logic [    BankCount-1:0]       s_read_pipe_valid_q;
  logic [    BankCount-1:0][15:0] s_read_pipe_model_q;
  logic [    BankCount-1:0][19:0] s_read_pipe_scratch_q;

  logic [    BankCount-1:0]       s_issue_write;
  logic [    BankCount-1:0][ 2:0] s_issue_write_lane;
  logic [    BankCount-1:0]       s_issue_read;
  logic [    BankCount-1:0][15:0] s_issue_model_mask;
  logic [    BankCount-1:0][19:0] s_issue_scratch_mask;
  logic [FirEntryCount-1:0]       s_fir_valid_q;

  logic                           s_loader_range_ok;
  logic [             14:0]       s_loader_offset;
  logic [              3:0]       s_loader_bank;
  logic [              9:0]       s_loader_row;
  logic                           s_loader_read_pending_q;
  logic [              3:0]       s_loader_read_bank_q;
  logic                           s_loader_read_err_q;

`ifndef SYNTHESIS
  // Kept as a simulation-loading boundary for the existing APUM/MFCC fixtures.
  // The synthesizable macro path below contains only the sixteen physical banks.
  logic [31:0] mem[0:16383];
`endif

  function automatic logic [3:0] model_bank(input logic [14:0] address_i);
    model_bank = {1'b0, address_i[4:2] ^ address_i[8:6]};
  endfunction

  function automatic logic [3:0] scratch_bank(input logic [15:0] address_i);
    scratch_bank = {1'b1, address_i[4:2] ^ address_i[8:6]};
  endfunction

  function automatic logic [13:0] bank_word(input logic [3:0] bank_i, input logic [9:0] row_i);
    bank_word = {bank_i[3], row_i, bank_i[2:0] ^ row_i[3:1]};
  endfunction

  assign s_loader_range_ok = (addr_i[1:0] == 2'd0) &&
      (addr_i >= `APB4_APU__LOCAL_KWS_BASE) &&
      (addr_i < (`APB4_APU__LOCAL_KWS_BASE + `RETROSOC_APU_KWS__MODEL_BYTES));
  assign s_loader_offset = 15'(addr_i - `APB4_APU__LOCAL_KWS_BASE);
  assign s_loader_bank = model_bank(s_loader_offset);
  assign s_loader_row = s_loader_offset[14:5];

  assign ready_o = rst_n_i && !s_busy_q && !s_loader_read_pending_q;
  assign data_o = s_bank_rdata[s_loader_read_bank_q];
  assign valid_o = s_loader_read_pending_q && !s_loader_read_err_q;
  assign access_err_o = (req_i && ready_o && !s_loader_range_ok) ||
      (s_loader_read_pending_q && s_loader_read_err_q);
  assign access_ready_o = rst_n_i && !s_busy_q && !s_loader_read_pending_q;
  assign access_done_o = s_busy_q && (s_model_pending_q == 16'd0) &&
      (s_scratch_read_pending_q == 20'd0) && (s_scratch_write_pending_q == 6'd0) &&
      (s_read_pipe_valid_q == BankCount'(0));
  assign access_progress_o = |s_issue_write || |s_issue_read;

  always_comb begin
    scratch_access_err_o = 1'b0;
    for (int lane = 0; lane < 20; lane++) begin
      scratch_access_err_o |= scratch_read_valid_i[lane] && scratch_read_addr_i[lane][15];
    end
    for (int lane = 0; lane < 6; lane++) begin
      scratch_access_err_o |= scratch_write_valid_i[lane] && scratch_write_addr_i[lane][15];
    end
  end

  always_comb begin
    s_bank_cs            = BankCount'(0);
    s_bank_wren          = BankCount'(0);
    s_bank_addr          = '0;
    s_bank_wdata         = '0;
    s_bank_wmask         = '0;
    s_issue_write        = BankCount'(0);
    s_issue_write_lane   = '0;
    s_issue_read         = BankCount'(0);
    s_issue_model_mask   = '0;
    s_issue_scratch_mask = '0;

    if (req_i && ready_o && s_loader_range_ok) begin
      s_bank_cs[s_loader_bank]    = 1'b1;
      s_bank_wren[s_loader_bank]  = write_i;
      s_bank_addr[s_loader_bank]  = s_loader_row;
      s_bank_wdata[s_loader_bank] = data_i;
      s_bank_wmask[s_loader_bank] = strb_i;
    end else if (s_busy_q) begin
      for (int bank = 0; bank < BankCount; bank++) begin
        for (int lane = 0; lane < 6; lane++) begin
          if (!s_bank_cs[bank] && s_scratch_write_pending_q[lane] && (scratch_bank(
                  s_scratch_write_addr_q[lane]
              ) == 4'(bank))) begin
            s_issue_write[bank]      = 1'b1;
            s_issue_write_lane[bank] = 3'(lane);
            s_bank_cs[bank]          = 1'b1;
            s_bank_wren[bank]        = 1'b1;
            s_bank_addr[bank]        = s_scratch_write_addr_q[lane][14:5];
            s_bank_wdata[bank]       = s_scratch_write_data_q[lane];
            s_bank_wmask[bank]       = s_scratch_write_strb_q[lane];
          end
        end
        for (int lane = 0; lane < 20; lane++) begin
          if (!s_bank_cs[bank] && s_scratch_read_pending_q[lane] && (scratch_bank(
                  s_scratch_read_addr_q[lane]
              ) == 4'(bank))) begin
            s_issue_read[bank] = 1'b1;
            s_bank_cs[bank]    = 1'b1;
            s_bank_addr[bank]  = s_scratch_read_addr_q[lane][14:5];
          end
        end
        for (int lane = 0; lane < 16; lane++) begin
          if (!s_bank_cs[bank] && s_model_pending_q[lane] && (model_bank(
                  s_model_addr_q[lane]
              ) == 4'(bank))) begin
            s_issue_read[bank] = 1'b1;
            s_bank_cs[bank]    = 1'b1;
            s_bank_addr[bank]  = s_model_addr_q[lane][14:5];
          end
        end
      end
      for (int bank = 0; bank < BankCount; bank++) begin
        for (int lane = 0; lane < 20; lane++) begin
          if (s_issue_read[bank] && s_scratch_read_pending_q[lane] && (scratch_bank(
                  s_scratch_read_addr_q[lane]
              ) == 4'(bank)) && (s_scratch_read_addr_q[lane][14:5] == s_bank_addr[bank])) begin
            s_issue_scratch_mask[bank][lane] = 1'b1;
          end
        end
        for (int lane = 0; lane < 16; lane++) begin
          if (s_issue_read[bank] && s_model_pending_q[lane] && (model_bank(
                  s_model_addr_q[lane]
              ) == 4'(bank)) && (s_model_addr_q[lane][14:5] == s_bank_addr[bank])) begin
            s_issue_model_mask[bank][lane] = 1'b1;
          end
        end
      end
    end
  end

  for (genvar bank = 0; bank < BankCount; bank++) begin : gen_kws_bank
`ifdef HAVE_SRAM_MACRO
    tc_sram_1024x32 u_kws_sram (
        .clk_i (clk_i),
        .cs_i  (s_bank_cs[bank]),
        .addr_i(s_bank_addr[bank]),
        .data_i(s_bank_wdata[bank]),
        .mask_i(s_bank_wmask[bank]),
        .wren_i(s_bank_wren[bank]),
        .data_o(s_bank_rdata[bank])
    );
`elsif PDK_BEHAV
    tc_sram_1024x32 u_kws_sram (
        .clk_i (clk_i),
        .cs_i  (s_bank_cs[bank]),
        .addr_i(s_bank_addr[bank]),
        .data_i(s_bank_wdata[bank]),
        .mask_i(s_bank_wmask[bank]),
        .wren_i(s_bank_wren[bank]),
        .data_o(s_bank_rdata[bank])
    );
`else
`ifndef SYNTHESIS
    logic [31:0] s_read_data_q;

    assign s_bank_rdata[bank] = s_read_data_q;
    always_ff @(posedge clk_i) begin
      if (s_bank_cs[bank]) begin
        if (s_bank_wren[bank]) begin
          if (s_bank_wmask[bank][0]) begin
            mem[bank_word(4'(bank), s_bank_addr[bank])][7:0] <= s_bank_wdata[bank][7:0];
          end
          if (s_bank_wmask[bank][1]) begin
            mem[bank_word(4'(bank), s_bank_addr[bank])][15:8] <= s_bank_wdata[bank][15:8];
          end
          if (s_bank_wmask[bank][2]) begin
            mem[bank_word(4'(bank), s_bank_addr[bank])][23:16] <= s_bank_wdata[bank][23:16];
          end
          if (s_bank_wmask[bank][3]) begin
            mem[bank_word(4'(bank), s_bank_addr[bank])][31:24] <= s_bank_wdata[bank][31:24];
          end
        end else begin
          s_read_data_q <= mem[bank_word(4'(bank), s_bank_addr[bank])];
        end
      end
    end
`else
    logic [31:0] s_storage_q   [0:1023];
    logic [31:0] s_read_data_q;

    assign s_bank_rdata[bank] = s_read_data_q;
    always_ff @(posedge clk_i) begin
      if (s_bank_cs[bank]) begin
        if (s_bank_wren[bank]) begin
          if (s_bank_wmask[bank][0]) begin
            s_storage_q[s_bank_addr[bank]][7:0] <= s_bank_wdata[bank][7:0];
          end
          if (s_bank_wmask[bank][1]) begin
            s_storage_q[s_bank_addr[bank]][15:8] <= s_bank_wdata[bank][15:8];
          end
          if (s_bank_wmask[bank][2]) begin
            s_storage_q[s_bank_addr[bank]][23:16] <= s_bank_wdata[bank][23:16];
          end
          if (s_bank_wmask[bank][3]) begin
            s_storage_q[s_bank_addr[bank]][31:24] <= s_bank_wdata[bank][31:24];
          end
        end else begin
          s_read_data_q <= s_storage_q[s_bank_addr[bank]];
        end
      end
    end
`endif
`endif
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_busy_q                  <= 1'b0;
      s_model_pending_q         <= 16'd0;
      s_model_addr_q            <= '0;
      s_scratch_read_pending_q  <= 20'd0;
      s_scratch_read_addr_q     <= '0;
      s_scratch_write_pending_q <= 6'd0;
      s_scratch_write_addr_q    <= '0;
      s_scratch_write_data_q    <= '0;
      s_scratch_write_strb_q    <= '0;
      s_read_pipe_valid_q       <= BankCount'(0);
      s_read_pipe_model_q       <= '0;
      s_read_pipe_scratch_q     <= '0;
      s_fir_valid_q             <= FirEntryCount'(0);
      model_data_o              <= '0;
      scratch_read_data_o       <= '0;
      s_loader_read_pending_q   <= 1'b0;
      s_loader_read_bank_q      <= 4'd0;
      s_loader_read_err_q       <= 1'b0;
    end else begin
      if (scratch_clear_i) s_fir_valid_q <= FirEntryCount'(0);

      if (access_done_o) begin
        s_busy_q <= 1'b0;
      end else if (access_req_i && access_ready_o) begin
        s_busy_q                  <= 1'b1;
        s_model_pending_q         <= access_write_i ? 16'd0 : model_read_valid_i;
        s_model_addr_q            <= model_addr_i;
        s_scratch_read_pending_q  <= access_write_i ? 20'd0 : scratch_read_valid_i;
        s_scratch_read_addr_q     <= scratch_read_addr_i;
        s_scratch_write_pending_q <= access_write_i ? scratch_write_valid_i : 6'd0;
        s_scratch_write_addr_q    <= scratch_write_addr_i;
        s_scratch_write_data_q    <= scratch_write_data_i;
        s_scratch_write_strb_q    <= scratch_write_strb_i;
      end

      for (int bank = 0; bank < BankCount; bank++) begin
        if (s_issue_write[bank]) begin
          s_scratch_write_pending_q[s_issue_write_lane[bank]] <= 1'b0;
          if ((s_scratch_write_addr_q[s_issue_write_lane[bank]] >=
               `RETROSOC_APU_KWS__SCRATCH_FIR_BASE) &&
              (s_scratch_write_addr_q[s_issue_write_lane[bank]] <
               (`RETROSOC_APU_KWS__SCRATCH_FIR_BASE + 16'(FirEntryCount * 2)))) begin
            s_fir_valid_q[6'((s_scratch_write_addr_q[s_issue_write_lane[bank]] -
                              `RETROSOC_APU_KWS__SCRATCH_FIR_BASE) >> 1)] <= 1'b1;
          end
        end
        if (s_issue_read[bank]) begin
          for (int lane = 0; lane < 16; lane++) begin
            if (s_issue_model_mask[bank][lane]) s_model_pending_q[lane] <= 1'b0;
          end
          for (int lane = 0; lane < 20; lane++) begin
            if (s_issue_scratch_mask[bank][lane]) begin
              s_scratch_read_pending_q[lane] <= 1'b0;
            end
          end
        end
        s_read_pipe_valid_q[bank]   <= s_issue_read[bank];
        s_read_pipe_model_q[bank]   <= s_issue_model_mask[bank];
        s_read_pipe_scratch_q[bank] <= s_issue_scratch_mask[bank];
        if (s_read_pipe_valid_q[bank]) begin
          for (int lane = 0; lane < 16; lane++) begin
            if (s_read_pipe_model_q[bank][lane]) begin
              model_data_o[lane] <= s_bank_rdata[bank][8*s_model_addr_q[lane][1:0]+:8];
            end
          end
          for (int lane = 0; lane < 20; lane++) begin
            if (s_read_pipe_scratch_q[bank][lane]) begin
              if ((s_scratch_read_addr_q[lane] >= `RETROSOC_APU_KWS__SCRATCH_FIR_BASE) &&
                  (s_scratch_read_addr_q[lane] <
                   (`RETROSOC_APU_KWS__SCRATCH_FIR_BASE + 16'(FirEntryCount * 2))) &&
                  !s_fir_valid_q[6'((s_scratch_read_addr_q[lane] -
                                     `RETROSOC_APU_KWS__SCRATCH_FIR_BASE) >> 1)]) begin
                scratch_read_data_o[lane] <= 32'd0;
              end else begin
                scratch_read_data_o[lane] <= s_bank_rdata[bank];
              end
            end
          end
        end
      end

      s_loader_read_pending_q <= 1'b0;
      if (req_i && ready_o && s_loader_range_ok && !write_i) begin
        s_loader_read_pending_q <= 1'b1;
        s_loader_read_bank_q    <= s_loader_bank;
        s_loader_read_err_q     <= 1'b0;
      end else if (req_i && ready_o && !s_loader_range_ok) begin
        s_loader_read_pending_q <= 1'b1;
        s_loader_read_err_q     <= 1'b1;
      end
    end
  end
endmodule
