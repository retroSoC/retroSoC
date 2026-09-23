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
    input  logic [15:0][14:0]       model_addr_i,
    output logic [15:0][ 7:0]       model_data_o,
    input  logic                    scratch_clear_i,
    input  logic [19:0][15:0]       scratch_read_addr_i,
    output logic [19:0][31:0]       scratch_read_data_o,
    input  logic [ 5:0]             scratch_write_valid_i,
    input  logic [ 5:0][15:0]       scratch_write_addr_i,
    input  logic [ 5:0][31:0]       scratch_write_data_i,
    input  logic [ 5:0][ 3:0]       scratch_write_strb_i,
    output logic                    scratch_access_err_o
    // verilog_format: on
);
  localparam int unsigned ModelWordCount = `RETROSOC_APU_KWS__MODEL_BYTES / 4;
  localparam int unsigned ScratchWordCount = `RETROSOC_APU_KWS__SCRATCH_BYTES / 4;
  localparam int unsigned KwsWordCount = ModelWordCount + ScratchWordCount;
  localparam int unsigned FirEntryCount = 63;

  logic [             31:0] mem           [0:KwsWordCount-1];
  logic [FirEntryCount-1:0] s_fir_valid_q;
  logic                     s_pending_q;
  logic                     s_err_q;
  logic [             31:0] s_data_q;
  logic                     s_range_ok;
  logic [             13:0] s_word_addr;

  assign s_range_ok = (addr_i[1:0] == 2'd0) &&
      (addr_i >= `APB4_APU__LOCAL_KWS_BASE) &&
      (addr_i < (`APB4_APU__LOCAL_KWS_BASE + `RETROSOC_APU_KWS__MODEL_BYTES));
  assign s_word_addr = 14'(addr_i[15:2] - 14'h2800);
  assign ready_o = rst_n_i && !s_pending_q;
  assign data_o = s_data_q;
  assign valid_o = s_pending_q && !s_err_q;
  assign access_err_o = (req_i && ready_o && !s_range_ok) || (s_pending_q && s_err_q);

  for (genvar lane = 0; lane < 16; lane++) begin : gen_model_read
    assign model_data_o[lane] = mem[{1'b0, model_addr_i[lane][14:2]}][8*model_addr_i[lane][1:0]+:8];
  end

  for (genvar lane = 0; lane < 20; lane++) begin : gen_scratch_read
    logic        s_fir_range;
    logic [ 5:0] s_fir_index;
    logic [13:0] s_memory_word;

    assign s_fir_range =
        (scratch_read_addr_i[lane] >= `RETROSOC_APU_KWS__SCRATCH_FIR_BASE) &&
        (scratch_read_addr_i[lane] <
         (`RETROSOC_APU_KWS__SCRATCH_FIR_BASE + 16'(FirEntryCount * 2)));
    assign s_fir_index = 6'((scratch_read_addr_i[lane] - `RETROSOC_APU_KWS__SCRATCH_FIR_BASE) >> 1);
    assign s_memory_word = 14'(ModelWordCount) + {1'b0, scratch_read_addr_i[lane][14:2]};
    assign scratch_read_data_o[lane] =
        scratch_read_addr_i[lane][15] || (s_fir_range && !s_fir_valid_q[s_fir_index]) ?
        32'd0 : mem[s_memory_word];
  end

  always_comb begin
    scratch_access_err_o = 1'b0;
    for (int lane = 0; lane < 6; lane++) begin
      scratch_access_err_o |= scratch_write_valid_i[lane] && scratch_write_addr_i[lane][15];
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_fir_valid_q <= FirEntryCount'(0);
      s_pending_q   <= 1'b0;
      s_err_q       <= 1'b0;
      s_data_q      <= 32'd0;
    end else begin
      s_pending_q <= 1'b0;
      s_err_q     <= 1'b0;
      if (scratch_clear_i) begin
        s_fir_valid_q <= FirEntryCount'(0);
      end
      if (req_i && ready_o) begin
        if (!s_range_ok) begin
          s_pending_q <= 1'b1;
          s_err_q     <= 1'b1;
        end else if (write_i) begin
          if (strb_i[0]) mem[s_word_addr][7:0] <= data_i[7:0];
          if (strb_i[1]) mem[s_word_addr][15:8] <= data_i[15:8];
          if (strb_i[2]) mem[s_word_addr][23:16] <= data_i[23:16];
          if (strb_i[3]) mem[s_word_addr][31:24] <= data_i[31:24];
        end else begin
          s_data_q    <= mem[s_word_addr];
          s_pending_q <= 1'b1;
        end
      end
      for (int lane = 0; lane < 6; lane++) begin
        if (scratch_write_valid_i[lane] && !scratch_write_addr_i[lane][15]) begin
          if (scratch_write_strb_i[lane][0]) begin
            mem[14'(ModelWordCount)+{1'b0, scratch_write_addr_i[lane][14:2]}][7:0] <=
                scratch_write_data_i[lane][7:0];
          end
          if (scratch_write_strb_i[lane][1]) begin
            mem[14'(ModelWordCount)+{1'b0, scratch_write_addr_i[lane][14:2]}][15:8] <=
                scratch_write_data_i[lane][15:8];
          end
          if (scratch_write_strb_i[lane][2]) begin
            mem[14'(ModelWordCount)+{1'b0, scratch_write_addr_i[lane][14:2]}][23:16] <=
                scratch_write_data_i[lane][23:16];
          end
          if (scratch_write_strb_i[lane][3]) begin
            mem[14'(ModelWordCount)+{1'b0, scratch_write_addr_i[lane][14:2]}][31:24] <=
                scratch_write_data_i[lane][31:24];
          end
          if ((scratch_write_addr_i[lane] >= `RETROSOC_APU_KWS__SCRATCH_FIR_BASE) &&
              (scratch_write_addr_i[lane] <
               (`RETROSOC_APU_KWS__SCRATCH_FIR_BASE + 16'(FirEntryCount * 2)))) begin
            s_fir_valid_q[6'(
                (scratch_write_addr_i[lane] - `RETROSOC_APU_KWS__SCRATCH_FIR_BASE) >> 1
            )] <= 1'b1;
          end
        end
      end
    end
  end
endmodule
