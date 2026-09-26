// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module crypto_sram_store #(
    parameter int         ResponseDelay     = 0,
    parameter logic [5:0] DropResponseMask  = 6'd0,
    parameter bit         DuplicateResponse = 1'b0
) (
    input  logic                                   clk_i,
    input  logic                                   rst_n_i,
    input  crypto_mem_pkg::crypto_mem_req_t  [5:0] req_i,
    output crypto_mem_pkg::crypto_mem_resp_t [5:0] resp_o
);
  import crypto_mem_pkg::*;

  for (genvar bank = 0; bank < 6; bank++) begin : gen_bank
    logic [21:0] s_retire_d, s_retire_q, s_retire_delay_q;
    logic [31:0] s_read_data;
    logic [31:0] s_read_data_delay_q;
    logic s_fault_resp, s_use_current_resp, s_base_valid, s_duplicate_valid, s_resp_valid;
    assign s_retire_d = {
      req_i[bank].valid,
      req_i[bank].write,
      req_i[bank].row,
      req_i[bank].tag,
      req_i[bank].epoch,
      req_i[bank].token
    };
    dffr #(
        .DATA_WIDTH(22)
    ) u_retire (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_retire_d),
        .dat_o  (s_retire_q)
    );
    always_ff @(posedge clk_i or negedge rst_n_i) begin
      if (!rst_n_i) begin
        s_retire_delay_q    <= '0;
        s_read_data_delay_q <= '0;
      end else if (ResponseDelay != 0) begin
        s_retire_delay_q    <= s_retire_q;
        s_read_data_delay_q <= s_read_data;
      end
    end
    assign s_use_current_resp = (ResponseDelay == 0) ||
        (s_retire_q[9:8] != 2'd0) ||
        (DuplicateResponse && s_retire_q[21] && (s_retire_q[9:8] == 2'd0));
    assign s_fault_resp = s_use_current_resp ? (s_retire_q[9:8] == 2'd0) :
        (s_retire_delay_q[9:8] == 2'd0);
    assign s_base_valid = (ResponseDelay != 0) && s_fault_resp ? s_retire_delay_q[21] :
        s_retire_q[21];
    assign s_duplicate_valid = DuplicateResponse && (ResponseDelay != 0) && s_fault_resp &&
        s_retire_q[21];
    assign s_resp_valid = s_base_valid || s_duplicate_valid;
    assign resp_o[bank].valid = s_resp_valid && !DropResponseMask[bank];
    assign resp_o[bank].write = !s_use_current_resp ? s_retire_delay_q[20] : s_retire_q[20];
    assign resp_o[bank].row = !s_use_current_resp ? s_retire_delay_q[19:10] : s_retire_q[19:10];
    assign resp_o[bank].tag = !s_use_current_resp ? s_retire_delay_q[9:8] : s_retire_q[9:8];
    assign resp_o[bank].epoch = !s_use_current_resp ? s_retire_delay_q[7:4] : s_retire_q[7:4];
    assign resp_o[bank].token = !s_use_current_resp ? s_retire_delay_q[3:0] : s_retire_q[3:0];
    assign resp_o[bank].data  = s_resp_valid && !resp_o[bank].write ?
        (!s_use_current_resp ? s_read_data_delay_q : s_read_data) : 32'd0;

`ifdef HAVE_SRAM_MACRO
    // Keep one technology wrapper per bank. Unsupported macro selections
    // deliberately fail elaboration instead of silently producing flop RAM.
`ifdef PDK_IHP130
    localparam bit MacroSupported = 1'b1;
`elsif PDK_GF180
    localparam bit MacroSupported = 1'b1;
`elsif PDK_SKY130
    localparam bit MacroSupported = 1'b1;
`elsif PDK_ICS55
    localparam bit MacroSupported = 1'b1;
`elsif PDK_S110
    localparam bit MacroSupported = 1'b1;
`else
    localparam bit MacroSupported = 1'b0;
`endif
    if (MacroSupported) begin : gen_macro
      tc_sram_1024x32 u_sram (
          .clk_i (clk_i),
          .cs_i  (req_i[bank].valid),
          .addr_i(req_i[bank].row),
          .data_i(req_i[bank].data),
          .mask_i(req_i[bank].mask),
          .wren_i(req_i[bank].write),
          .data_o(s_read_data)
      );
    end else begin : gen_unsupported
      crypto_unsupported_sram_mapping u_invalid_mapping ();
    end
`else
    // Explicit synchronous fallback for macro-disabled committed profiles.
    // No reset on the array: physical erasure belongs to the scrub protocol.
    logic [31:0] s_storage_q[0:1023];
    always_ff @(posedge clk_i) begin
      if (req_i[bank].valid) begin
        if (req_i[bank].write) begin
          for (int unsigned lane = 0; lane < 4; lane++) begin
            if (req_i[bank].mask[lane])
              s_storage_q[req_i[bank].row][lane*8+:8] <= req_i[bank].data[lane*8+:8];
          end
          s_read_data <= 'x;
        end else begin
          s_read_data <= s_storage_q[req_i[bank].row];
        end
      end
    end
`endif
  end
endmodule
